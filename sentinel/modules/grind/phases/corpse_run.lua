local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local CorpseRun = {}

local RELEASE_DELAY_MS = 2500
local RELEASE_RETRY_MS = 2000
local RESURRECT_RETRY_MS = 750
local RESURRECT_DISTANCE = 30
local MAX_CORPSE_RUN_MS = 120000  -- 2 minute max before giving up and retrying

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function is_valid_pos(pos)
    return type(pos) == "table" and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil
end

local function query_corpse_position()
    if core and core.game_ui and type(core.game_ui.get_corpse_position) == "function" then
        local ok, pos = pcall(core.game_ui.get_corpse_position)
        if ok and is_valid_pos(pos) then
            return pos
        end
    end
    return nil
end

---Build the corpse-run phase sub-tree.
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function CorpseRun.build(event_bus, nav_adapter)
    return BT.sequence("corpse_run", {
        -- Gate: player must be dead or ghost
        BT.condition("is_dead_or_ghost", function(bb)
            return bb:get("player.is_dead") == true
                or bb:get("player.is_ghost") == true
        end),

        -- Handle death: either release spirit or run to corpse
        BT.selector("handle_death", {
            -- Branch 1: release spirit if dead but not yet ghost
            BT.sequence("release_spirit", {
                BT.condition("is_dead_not_ghost", function(bb)
                    return bb:get("player.is_dead") == true
                        and bb:get("player.is_ghost") ~= true
                end),
                BT.action("release", function(bb)
                    -- Re-check ghost state (Sequence _running_index skips gate condition)
                    if bb:get("player.is_ghost") == true then
                        return Status.FAILURE
                    end

                    local now = bb:get("system.now_ms", 0)

                    -- Stop any active navigation
                    if nav_adapter and nav_adapter:is_active() then
                        nav_adapter:stop("death")
                    end

                    -- Record when death started (first tick only)
                    if not bb:get("module.grind.death_started_ms") then
                        bb:set("module.grind.death_started_ms", now)
                        event_bus:publish("grind:death", {
                            position = bb:get("player.death_position") or bb:get("player.position"),
                            timestamp = now,
                        })
                    end

                    -- Wait before releasing (configurable delay)
                    local death_start = bb:get("module.grind.death_started_ms", 0)
                    if now - death_start < RELEASE_DELAY_MS then
                        return Status.RUNNING
                    end

                    -- Throttle release attempts
                    local last_release = bb:get("module.grind.last_release_ms", 0)
                    if now - last_release < RELEASE_RETRY_MS then
                        return Status.RUNNING
                    end

                    bb:set("module.grind.last_release_ms", now)
                    if core and core.input and type(core.input.release_spirit) == "function" then
                        pcall(core.input.release_spirit)
                    end
                    return Status.RUNNING
                end),
            }),

            -- Branch 2: ghost running to corpse
            BT.sequence("run_to_corpse", {
                BT.condition("is_ghost", function(bb)
                    return bb:get("player.is_ghost") == true
                end),
                BT.action("navigate_to_corpse", function(bb)
                    -- Re-check alive state (Sequence _running_index skips gate condition)
                    if bb:get("player.is_dead") ~= true and bb:get("player.is_ghost") ~= true then
                        return Status.FAILURE
                    end

                    -- Refresh corpse position every tick (game API is authoritative)
                    local corpse_pos = query_corpse_position()
                    if corpse_pos then
                        bb:set("module.grind.corpse_position", corpse_pos)
                    end

                    -- Fallback chain: game API → sensor death position → stored
                    local corpse_source = "game_api"
                    if not corpse_pos then
                        corpse_pos = bb:get("player.death_position")
                        corpse_source = "death_position"
                    end
                    if not corpse_pos then
                        corpse_pos = bb:get("module.grind.corpse_position")
                        corpse_source = "stored"
                    end
                    if not corpse_pos or not is_valid_pos(corpse_pos) then
                        -- No position yet (API lag) — wait instead of FAILURE so the
                        -- PrioritySelector doesn't fall through to Pull/Acquire as ghost.
                        if nav_adapter and nav_adapter:is_active() then
                            nav_adapter:stop("corpse_waiting")
                        end
                        if core and core.log then
                            pcall(core.log, "[CorpseRun] waiting: no valid corpse position yet")
                        end
                        return Status.RUNNING
                    end

                    local player_pos = bb:get("player.position")
                    local dist = distance_3d(player_pos, corpse_pos)

                    if dist <= RESURRECT_DISTANCE then
                        bb:set("module.grind._corpse_run_start_ms", nil)
                        if nav_adapter and nav_adapter:is_active() then
                            nav_adapter:stop("corpse_arrived")
                        end

                        -- Check resurrect delay before attempting
                        if core and core.game_ui and type(core.game_ui.get_resurrect_corpse_delay) == "function" then
                            local ok_delay, delay = pcall(core.game_ui.get_resurrect_corpse_delay)
                            if ok_delay and type(delay) == "number" and delay > 0.05 then
                                return Status.RUNNING
                            end
                        end

                        -- Throttle resurrect attempts
                        local now = bb:get("system.now_ms", 0)
                        local last_rez = bb:get("module.grind.last_resurrect_ms", 0)
                        if now - last_rez < RESURRECT_RETRY_MS then
                            return Status.RUNNING
                        end

                        bb:set("module.grind.last_resurrect_ms", now)
                        if core and core.input and type(core.input.resurrect_corpse) == "function" then
                            pcall(core.input.resurrect_corpse)
                        end
                        return Status.RUNNING
                    end

                    -- Timeout: if ghost nav takes too long, stop and retry
                    local now_ms = bb:get("system.now_ms", 0)
                    local run_start = bb:get("module.grind._corpse_run_start_ms")
                    if not run_start then
                        bb:set("module.grind._corpse_run_start_ms", now_ms)
                        run_start = now_ms
                    end
                    if now_ms - run_start > MAX_CORPSE_RUN_MS then
                        if nav_adapter and nav_adapter:is_active() then
                            nav_adapter:stop("corpse_run_timeout")
                        end
                        bb:set("module.grind._corpse_run_start_ms", nil)
                        -- Reset to retry from scratch (re-query corpse pos)
                        bb:set("module.grind.corpse_position", nil)
                        return Status.FAILURE
                    end

                    -- Navigate to corpse
                    if nav_adapter and not nav_adapter:is_active() then
                        if core and core.log then
                            pcall(core.log, string.format(
                                "[CorpseRun] NAV_START: src=%s corpse=(%.1f,%.1f,%.1f) player=(%.1f,%.1f,%.1f) dist=%.1f",
                                corpse_source,
                                corpse_pos.x or 0, corpse_pos.y or 0, corpse_pos.z or 0,
                                player_pos.x or 0, player_pos.y or 0, player_pos.z or 0,
                                dist))
                        end
                        nav_adapter:move_to(corpse_pos)
                    end
                    return Status.RUNNING
                end),
            }),
        }),
    })
end

return CorpseRun
