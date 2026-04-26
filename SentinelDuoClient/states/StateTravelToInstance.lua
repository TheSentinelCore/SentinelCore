-- StateTravelToInstance.lua — Navigate to the Stratholme SE entrance.

local helpers = require("lib/helpers")

local StateTravelToInstance = { name = "TRAVEL_TO_INSTANCE" }

local ENTRANCE_THRESHOLD_YARDS = 5.0

function StateTravelToInstance:create(ctx)
    local bb      = ctx.bb
    local duo_nav = ctx.duo_nav
    local profile = ctx.profile

    -- Direct check: are we already inside the instance?
    local function already_inside()
        -- Primary: blackboard (set by App sensors each tick via exact instance_map_id match)
        if bb:get("player.in_instance", false) then return true end
        -- Fallback: direct check in case sensors haven't fired yet this tick
        if profile and profile.instance_map_id then
            local ok, map_id = pcall(core.get_map_id)
            if ok and map_id == profile.instance_map_id then return true end
        end
        return false
    end

    return {
        enter = function(_bb)
            -- Diagnostic log so we can see exactly what values are present.
            local raw_map = bb:get("player.map_id", -1)
            local in_bb   = bb:get("player.in_instance", false)
            helpers.log(string.format(
                "[TRAVEL_TO_INSTANCE] enter — map_id=%s in_instance=%s profile_instance_map=%s",
                tostring(raw_map), tostring(in_bb),
                tostring(profile and profile.instance_map_id or "nil")))

            -- Already inside — skip navigation entirely.
            if already_inside() then
                helpers.log("[TRAVEL_TO_INSTANCE] already inside — skipping travel")
                return
            end
            if profile and profile.entrance_walk_path then
                duo_nav:follow_path(profile.entrance_walk_path)
            elseif profile and profile.entrance_position then
                duo_nav:move_to(profile.entrance_position)
            else
                helpers.log_warn("[TRAVEL_TO_INSTANCE] no profile entrance path")
            end
        end,

        update = function(_bb)
            -- Already inside the instance — go straight to FARMING.
            if already_inside() then
                duo_nav:stop("already_inside")
                helpers.log("[TRAVEL_TO_INSTANCE] inside detected — going to FARMING")
                return "FARMING"
            end

            if not profile then return "ENTERING" end

            local dest = profile.entrance_position
            if not dest then return "ENTERING" end

            local ok, player = pcall(core.object_manager.get_local_player)
            if not ok or not player then return end

            local ok_pos, pos = pcall(player.get_position, player)
            if not ok_pos or not pos then return end

            local dx = (pos.x or 0) - (dest.x or 0)
            local dy = (pos.y or 0) - (dest.y or 0)
            local dz = (pos.z or 0) - (dest.z or 0)
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

            if dist <= ENTRANCE_THRESHOLD_YARDS then
                bb:set("duo.at_instance_entrance", true)
                duo_nav:stop("arrived")
                return "ENTERING"
            end
        end,

        exit = function(_bb)
            helpers.log("[TRAVEL_TO_INSTANCE] exit")
        end,
    }
end

return StateTravelToInstance
