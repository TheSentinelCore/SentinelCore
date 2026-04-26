-- StateEntering.lua — Open gate (puller with key), wait at barrier, walk into instance.

local helpers = require("lib/helpers")

local StateEntering = { name = "ENTERING" }

local BARRIER_NAME     = "enter_instance"
local GATE_RETRY_DELAY = 2000    -- ms between retry interact attempts
local GATE_MAX_RETRIES = 3       -- after this many attempts, assume open

function StateEntering:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client
    local duo_nav      = ctx.duo_nav
    local profile      = ctx.profile
    local gate_obj_id  = profile and profile.gate_object_id

    local barrier_entered  = false
    local barrier_released = false
    local gate_confirmed   = false  -- true when gate object gone or max retries hit
    local gate_retry_count = 0
    local gate_retry_ms    = 0

    local function is_in_instance()
        if bb:get("player.in_instance", false) then return true end
        if profile and profile.instance_map_id then
            local ok, map_id = pcall(core.get_map_id)
            if ok and map_id == profile.instance_map_id then return true end
        end
        return false
    end

    local function nav_into_instance()
        -- Follow inside_walk_path if provided; fall back to pull 1 positions.
        if profile and type(profile.inside_walk_path) == "table" and #profile.inside_walk_path > 0 then
            duo_nav:follow_path(profile.inside_walk_path)
            return
        end
        local pull1     = profile and profile.pulls and profile.pulls[1]
        local is_puller = bb:get("duo.is_puller", false)
        if is_puller and pull1 and type(pull1.pull_path) == "table" and #pull1.pull_path > 0 then
            duo_nav:move_to(pull1.pull_path[1])
        elseif pull1 and pull1.safe_position then
            duo_nav:move_to(pull1.safe_position)
        else
            helpers.log_warn("[ENTERING] no inside_walk_path or pull1 positions — cannot nav inside")
        end
    end

    return {
        enter = function(_bb)
            helpers.log("[ENTERING] enter")
            barrier_entered  = false
            barrier_released = false
            gate_confirmed   = false
            gate_retry_count = 0
            gate_retry_ms    = 0
            duo_nav:stop("entering_state")
        end,

        update = function(_bb)
            local gt        = helpers.game_time_ms()
            local is_puller = bb:get("duo.is_puller", false)
            local has_key   = bb:get("duo.has_instance_key", false)

            -- Once inside, proceed to in-instance buff
            if is_in_instance() then
                helpers.log("[ENTERING] in instance — INSIDE_BUFF")
                return "INSIDE_BUFF"
            end

            -- ── Gate opening (puller with key) ───────────────────────────────
            -- Scan objects each frame to detect gate disappearance and retry interact.
            if is_puller and has_key and not gate_confirmed then
                local ok_objs, objects = pcall(core.object_manager.get_all_objects)
                local gate_found = false

                if ok_objs and type(objects) == "table" then
                    for _, obj in ipairs(objects) do
                        local ok_id, npc_id = pcall(obj.get_npc_id, obj)
                        if ok_id and gate_obj_id and npc_id == gate_obj_id then
                            gate_found = true
                            -- Rate-limited retry
                            if gate_retry_count == 0 or gt - gate_retry_ms >= GATE_RETRY_DELAY then
                                pcall(core.input.interact_with_object, obj)
                                gate_retry_ms    = gt
                                gate_retry_count = gate_retry_count + 1
                                helpers.log("[ENTERING] gate interact attempt " .. gate_retry_count)
                            end
                            break
                        end
                    end
                end

                -- Gate object gone = gate opened
                if not gate_found and gate_retry_count > 0 then
                    gate_confirmed = true
                    helpers.log("[ENTERING] gate confirmed open (object not found in scan)")
                end
                -- After max retries, assume open regardless
                if gate_retry_count >= GATE_MAX_RETRIES then
                    gate_confirmed = true
                    helpers.log("[ENTERING] gate assumed open after " .. GATE_MAX_RETRIES .. " attempts")
                end
            end

            -- Support mage: no key, no gate to open — gate_confirmed is irrelevant for support
            if not is_puller or not has_key then
                gate_confirmed = true  -- support doesn't wait for gate, barrier sync handles it
            end

            -- ── Barrier entry ─────────────────────────────────────────────────
            -- Puller: only enter barrier after gate is confirmed open.
            -- Support: enters immediately when at entrance.
            -- This ensures the barrier releases only after the gate is open,
            -- so support walks through an open gate.
            if not barrier_entered and bb:get("duo.at_instance_entrance", false) then
                if gate_confirmed then
                    coord_client:enter_barrier(BARRIER_NAME)
                    barrier_entered = true
                    helpers.log("[ENTERING] barrier entered")
                end
            end

            -- ── Poll barrier ──────────────────────────────────────────────────
            if barrier_entered and not barrier_released then
                local result = coord_client:poll_barrier(BARRIER_NAME)
                if result == true or result == "timeout" then
                    if result == "timeout" then
                        helpers.log_warn("[ENTERING] barrier timeout — solo entry")
                    end
                    coord_client:release_barrier(BARRIER_NAME)
                    barrier_released = true
                    nav_into_instance()
                end
            end
        end,

        exit = function(_bb)
            helpers.log("[ENTERING] exit")
        end,
    }
end

return StateEntering
