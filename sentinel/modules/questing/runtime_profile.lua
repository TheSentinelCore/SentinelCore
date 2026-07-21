--- Sentinel Runtime Profile Executor
--- Loads and executes a RuntimeProfile (compiled from sentinel-questing/compiler)
--- Uses Blackboard for state, EventBus for events

local RuntimeAction = require("modules/questing/runtime_action")
local Blackboard = require("core/blackboard")
local Compat = require("shared/compat")
local QueryClient = require("shared/query_client")

local RuntimeProfile = {}
RuntimeProfile.__index = RuntimeProfile

function RuntimeProfile:new(json_path)
    local o = setmetatable({}, RuntimeProfile)
    o._json_path = json_path
    o._profile = nil
    o._blackboard = Blackboard:new()
    o._query = QueryClient:new("127.0.0.1", 3030)
    o._current_operation_idx = 1
    o._variables = {}
    return o
end

function RuntimeProfile:load()
    if core and core.read_data_file then
        local json, err = core.read_data_file(self._json_path)
        if not json then
            return nil, err or "file not found"
        end
        local decoded = JSON and JSON.parse(json)
        if not decoded then
            decoded = load("return " .. json)()
        end
        self._profile = decoded
        return true
    end
    return nil, "no data file API"
end

--- Runtime context with helper methods
function RuntimeProfile:create_context()
    local ctx = {
        variables = self._variables,
        query = self._query,
    }

    function ctx:is_at_npc(entry)
        -- Check if player is near the specified NPC entry
        if core and core.object_manager and core.object_manager.GetNearestCreature then
            local npc = core.object_manager.GetNearestCreature({ entry })
            if npc and npc.IsValid and npc:IsValid() then
                return true
            end
        end
        return false
    end

    function ctx:is_at_destination(zone_name, tolerance)
        -- Check if player is in the destination zone
        if core and core.object_manager and core.object_manager.GetPlayerInfo then
            local player = core.object_manager.GetPlayerInfo()
            -- TODO: Use QueryServer to get zone bounds and check position
            return false
        end
        return false
    end

    function ctx:get_zone_waypoint(zone_name)
        -- Query zone center coordinates
        -- TODO: Use QueryServer
        return nil
    end

    return ctx
end

function RuntimeProfile:execute()
    if not self._profile then
        return "error", "profile not loaded"
    end

    local operations = self._profile.operations or {}
    if #operations == 0 then
        return "finished", "no operations"
    end

    -- Execute current operation
    local op = operations[self._current_operation_idx]
    if not op then
        return "finished", "completed all operations"
    end

    local action = op.action
    local ctx = self:create_context()

    local status, msg = RuntimeAction.execute(action, ctx)

    self._blackboard:set("questing.current_operation", self._current_operation_idx)
    self._blackboard:set("questing.current_status", status)

    if status == "success" then
        if op.next_condition == "auto" or op.next_condition == "always" then
            self._current_operation_idx = self._current_operation_idx + 1
        elseif op.next_condition == "conditional" and op.condition_id then
            -- Check condition result
            -- TODO: Use QueryServer to evaluate
            self._current_operation_idx = self._current_operation_idx + 1
        else
            self._current_operation_idx = self._current_operation_idx + 1
        end
        return "running", "next operation"
    else
        return "running", msg
    end
end

function RuntimeProfile:reset()
    self._current_operation_idx = 1
    self._variables = {}
end

return RuntimeProfile