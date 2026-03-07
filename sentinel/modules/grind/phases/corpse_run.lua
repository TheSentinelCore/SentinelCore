local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local CorpseRun = {}

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
                    -- Store death position for corpse run
                    local pos = bb:get("player.position")
                    if pos then
                        bb:set("module.grind.corpse_position", pos)
                    end
                    -- Release spirit via Sylvannas API
                    if core and core.input and core.input.release_spirit then
                        core.input.release_spirit()
                    end
                    event_bus:publish("grind:death", { position = pos })
                    return Status.SUCCESS
                end),
            }),

            -- Branch 2: ghost running to corpse
            BT.sequence("run_to_corpse", {
                BT.condition("is_ghost", function(bb)
                    return bb:get("player.is_ghost") == true
                end),
                BT.action("navigate_to_corpse", function(bb)
                    -- Try the game API corpse position first, fall back to stored
                    local corpse_pos = nil
                    if core and core.game_ui and core.game_ui.get_corpse_position then
                        local ok, pos = pcall(core.game_ui.get_corpse_position)
                        if ok and type(pos) == "table" and pos.x then
                            corpse_pos = pos
                        end
                    end
                    if not corpse_pos then
                        corpse_pos = bb:get("module.grind.corpse_position")
                    end
                    if not corpse_pos then
                        return Status.FAILURE
                    end

                    local player_pos = bb:get("player.position")
                    if player_pos then
                        local dx = (player_pos.x or 0) - (corpse_pos.x or 0)
                        local dy = (player_pos.y or 0) - (corpse_pos.y or 0)
                        local dz = (player_pos.z or 0) - (corpse_pos.z or 0)
                        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if dist <= 30 then
                            return Status.SUCCESS
                        end
                    end

                    if not nav_adapter:is_active() then
                        nav_adapter:move_to(corpse_pos)
                    end
                    return Status.RUNNING
                end),
                BT.condition("safe_to_rez", function(bb)
                    local count = bb:get("combat.enemy_count_30yd", 0)
                    return count == 0
                end),
                BT.action("accept_resurrect", function(bb)
                    -- Resurrect at corpse via Sylvannas API
                    if core and core.input and core.input.resurrect_corpse then
                        core.input.resurrect_corpse()
                    end
                    bb:set("module.grind.corpse_position", nil)
                    bb:set("module.grind.current_target", nil)
                    event_bus:publish("grind:resurrect", {})
                    return Status.SUCCESS
                end),
            }),
        }),
    })
end

return CorpseRun
