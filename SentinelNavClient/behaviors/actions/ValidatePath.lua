-- ValidatePath.lua
-- BT Action: async path validation. Returns RUNNING while checking.
local BT = require("lib/BehaviorTree")

---@param nav_service table NavigationService instance
---@param validation_service table PathValidationService instance
return function(nav_service, validation_service)
    return BT.Action:new(function(bb, dt)
        -- Check for pending validation
        if bb:get("validation.pending") then
            local result = bb:get("validation.result")
            if result ~= nil then
                bb:set("validation.pending", false)
                bb:clear("validation.result")
                if not result then
                    bb:set("deviation.needs_repath", true)
                end
                return BT.SUCCESS
            end
            return BT.RUNNING
        end

        -- Start validation
        local pos = bb:get("player.position")
        local waypoints = bb:get("path.waypoints")
        local index = bb:get("path.index", 1)
        if not pos or not waypoints then return BT.SUCCESS end

        local remaining = {}
        for i = index, #waypoints do
            remaining[#remaining + 1] = waypoints[i]
        end
        if #remaining < 2 then return BT.SUCCESS end

        bb:set("validation.pending", true)
        validation_service:check_path_validity(nav_service, pos, remaining, function(valid)
            bb:set("validation.result", valid)
        end)

        return BT.RUNNING
    end, "ValidatePath")
end
