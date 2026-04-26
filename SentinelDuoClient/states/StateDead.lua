-- StateDead.lua — Release spirit, run to corpse, resurrect, transition to BUFFING.

local helpers = require("lib/helpers")

local StateDead = { name = "DEAD" }

local CORPSE_RANGE_YARDS      = 4.0
local RELEASE_SPIRIT_INTERVAL = 2000   -- ms between release_spirit() attempts
local RESURRECT_INTERVAL      = 3000   -- ms between resurrect_corpse() attempts
local RESURRECT_JITTER_MAX    = 2000   -- ms of extra random delay before first resurrect

function StateDead:create(ctx)
    local bb      = ctx.bb
    local duo_nav = ctx.duo_nav

    local last_release_ms    = 0
    local last_resurrect_ms  = 0
    local corpse_nav_started = false
    local jitter_ms          = 0

    return {
        enter = function(_bb)
            helpers.log("[DEAD] enter")
            local deaths = (bb:get("duo.deaths_this_session", 0)) + 1
            bb:set("duo.deaths_this_session", deaths)
            last_release_ms    = 0
            last_resurrect_ms  = 0
            corpse_nav_started = false
            jitter_ms          = math.random(0, RESURRECT_JITTER_MAX)
        end,

        update = function(_bb)
            local is_dead  = bb:get("player.is_dead",  false)
            local is_ghost = bb:get("player.is_ghost", false)
            local gt       = helpers.game_time_ms()

            -- Fully alive → rebuff
            if not is_dead and not is_ghost then
                helpers.log("[DEAD] alive — BUFFING")
                return "BUFFING"
            end

            -- Step 1: Dead but not yet a ghost — call release_spirit() periodically.
            if is_dead and not is_ghost then
                if gt - last_release_ms >= RELEASE_SPIRIT_INTERVAL then
                    last_release_ms = gt
                    local ok, err = pcall(core.input.release_spirit)
                    helpers.log("[DEAD] release_spirit -> " .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
                end
                return
            end

            -- Step 2: Ghost — navigate to corpse, then resurrect.
            if is_ghost then
                local ok_cp, corpse_pos = pcall(core.game_ui.get_corpse_position)
                if not ok_cp or not corpse_pos then
                    -- No corpse position (e.g. at spirit healer). Try spirit healer interaction.
                    if gt - last_resurrect_ms >= RESURRECT_INTERVAL then
                        last_resurrect_ms = gt
                        -- Attempt to find and interact with the spirit healer NPC.
                        -- Spirit healer NPC IDs for EPL graveyard area.
                        local ok_objs, objs = pcall(core.object_manager.get_all_objects)
                        if ok_objs and type(objs) == "table" then
                            for _, obj in ipairs(objs) do
                                local ok_id, npc_id = pcall(obj.get_npc_id, obj)
                                -- Spirit Healer NPC IDs (common ones across zones)
                                if ok_id and (npc_id == 6491 or npc_id == 13116 or npc_id == 22005) then
                                    pcall(core.input.interact_with_object, obj)
                                    helpers.log("[DEAD] spirit healer interact")
                                    break
                                end
                            end
                        end
                    end
                    return
                end

                -- Start navigation toward corpse (only once; don't restart every frame).
                if not corpse_nav_started then
                    duo_nav:move_to(corpse_pos)
                    corpse_nav_started = true
                    helpers.log(string.format("[DEAD] navigating to corpse (%.1f, %.1f, %.1f)",
                        corpse_pos.x or 0, corpse_pos.y or 0, corpse_pos.z or 0))
                end

                -- Check distance to corpse.
                local ok_pl, player = pcall(core.object_manager.get_local_player)
                if not ok_pl or not player then return end
                local ok_pos, pos = pcall(player.get_position, player)
                if not ok_pos or not pos then return end

                local dx = (pos.x or 0) - (corpse_pos.x or 0)
                local dy = (pos.y or 0) - (corpse_pos.y or 0)
                local dz = (pos.z or 0) - (corpse_pos.z or 0)
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

                if dist <= CORPSE_RANGE_YARDS then
                    duo_nav:stop("at_corpse")

                    -- Check resurrection delay timer.
                    local ok_d, delay = pcall(core.game_ui.get_resurrect_corpse_delay)
                    local can_res = ok_d and (type(delay) == "number") and (delay <= 0)

                    -- Rate-limit to once per RESURRECT_INTERVAL + jitter.
                    if can_res and gt - last_resurrect_ms >= RESURRECT_INTERVAL + jitter_ms then
                        last_resurrect_ms = gt
                        jitter_ms         = 0  -- apply jitter only on first attempt
                        local ok_r = pcall(core.input.resurrect_corpse)
                        helpers.log("[DEAD] resurrect_corpse -> " .. tostring(ok_r))
                    end
                end
            end
        end,

        exit = function(_bb)
            helpers.log("[DEAD] exit")
        end,
    }
end

return StateDead
