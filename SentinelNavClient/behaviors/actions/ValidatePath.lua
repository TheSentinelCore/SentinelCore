-- ValidatePath.lua
-- BT Action: async path validation. Returns RUNNING while checking.
local BT = require("lib/BehaviorTree")

local function next_validation_id(bb)
    local validation_id = bb:get("validation.next_id", 0) + 1
    bb:set("validation.next_id", validation_id)
    return validation_id
end

---@param nav_service table NavigationService instance
---@param validation_service table PathValidationService instance
return function(nav_service, validation_service)
    return BT.Action:new(function(bb, dt)
        local current_session = bb:get("nav.session_id", 0)

        -- Check for pending validation
        if bb:get("validation.pending") then
            if bb:get("validation.active_session") ~= current_session then
                bb:set("validation.pending", false)
                bb:clear("validation.result")
                bb:clear("validation.active_id")
                bb:clear("validation.active_session")
                return BT.SUCCESS
            end

            local result = bb:get("validation.result")
            if result ~= nil then
                bb:set("validation.pending", false)
                bb:clear("validation.result")
                bb:clear("validation.active_id")
                bb:clear("validation.active_session")
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

        local validation_id = next_validation_id(bb)
        bb:set("validation.pending", true)
        bb:set("validation.active_id", validation_id)
        bb:set("validation.active_session", current_session)
        bb:clear("validation.result")
        validation_service:check_path_validity(nav_service, pos, remaining, function(valid)
            if bb:get("nav.session_id", 0) ~= current_session then
                return
            end
            if bb:get("validation.active_id") ~= validation_id then
                return
            end
            bb:set("validation.result", valid)
        end)

        return BT.RUNNING
    end, "ValidatePath")
end
