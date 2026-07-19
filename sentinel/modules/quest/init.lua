-- sentinel/modules/quest/init.lua
-- Quest Module entry point for runtime quest execution
-- Provides goal checking, sub-operation support, and integration with runtime engine

local GoalChecker = require("modules/quest/goal_checker")
local RuntimeEngine = require("runtime/runtime_engine")

local QuestModule = {}
QuestModule.__index = QuestModule

---Create a new QuestModule
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param runtime_engine table The RuntimeEngine instance
---@return table QuestModule instance
function QuestModule:new(blackboard, event_bus, runtime_engine)
    local o = setmetatable({}, QuestModule)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._engine = runtime_engine
    o._goal_checker = GoalChecker:new(blackboard)
    o._initialized = false
    o._active_profile = nil
    o._sub_tokens = {}  -- Event unsubscribe tokens
    return o
end

---Initialize the module: register event handlers
function QuestModule:init()
    if self._initialized then
        return
    end

    self._initialized = true

    -- Subscribe to events that trigger goal re-evaluation
    self._sub_tokens.quest_completed = self._event_bus:subscribe(
        "quest_completed",
        function(payload) self:_on_quest_completed(payload) end,
        50
    )

    self._sub_tokens.level_gained = self._event_bus:subscribe(
        "level_gained",
        function(payload) self:_on_level_gained(payload) end,
        50
    )

    self._sub_tokens.item_acquired = self._event_bus:subscribe(
        "item_acquired",
        function(payload) self:_on_item_acquired(payload) end,
        50
    )

    -- Also listen for compile events to swap profiles
    self._sub_tokens.profile_compiled = self._event_bus:subscribe(
        "profile_compiled",
        function(payload) self:_on_profile_compiled(payload) end,
        50
    )

    -- Store module state in blackboard
    self._blackboard:set("module.quest.initialized", true)
end

---Per-frame tick
---@param delta number Milliseconds since last tick
---@return table|nil Result from runtime engine
function QuestModule:tick(delta)
    if not self._initialized then
        return nil
    end

    -- Delegate to runtime engine
    if self._engine and self._active_profile then
        return self._engine:tick(delta)
    end
    return nil
end

---Shutdown the module: cleanup
function QuestModule:shutdown()
    self._initialized = false
    self._active_profile = nil

    -- Unsubscribe from events
    for _, token in pairs(self._sub_tokens) do
        if token then
            self._event_bus:unsubscribe(token)
        end
    end
    self._sub_tokens = {}

    -- Clear blackboard state
    self._blackboard:set("module.quest.initialized", nil)
    self._blackboard:set("module.quest.active_profile", nil)
    self._blackboard:set("module.quest.sub_ops", nil)
end

---Load a compiled profile
---@param profile table RuntimeProfile
function QuestModule:load_profile(profile)
    if not profile then
        return false
    end

    self._active_profile = profile
    self._blackboard:set("module.quest.active_profile", profile.id or profile.name)

    -- Initialize sub-operations if present
    if profile.operations then
        for _, op in ipairs(profile.operations) do
            if op.sub_operations and #op.sub_operations > 0 then
                self:_init_sub_operations(op)
            end
        end
    end

    -- Set profile on runtime engine if available
    if self._engine and type(self._engine.set_profile) == "function" then
        self._engine:set_profile(profile)
    end

    return true
end

---Check goals for an operation
---@param operation table Operation with goals field
---@return table Result: { all_met: bool, uncovered: [] }
function QuestModule:check_goals(operation)
    if not operation then
        return { all_met = true, uncovered = {} }
    end

    local goals = operation.goals or {}

    -- If operation has sub-operations, also consider their goals
    if operation.sub_operations and #operation.sub_operations > 0 then
        for _, sub_op in ipairs(operation.sub_operations) do
            if sub_op.goals and #sub_op.goals > 0 then
                -- Add sub-operation goals to check
                for _, goal in ipairs(sub_op.goals) do
                    table.insert(goals, goal)
                end
            end
        end
    end

    return self._goal_checker:check_all_goals(goals)
end

---Initialize sub-operation tracking for an operation
---@param operation table Operation with sub_operations
function QuestModule:_init_sub_operations(operation)
    if not operation.sub_operations or #operation.sub_operations == 0 then
        return
    end

    local sub_ops = self._blackboard:get("module.quest.sub_ops") or {}
    sub_ops[operation.id] = {
        current_sub = nil,
        completed_subs = {},
        sub_operations = operation.sub_operations
    }
    self._blackboard:set("module.quest.sub_ops", sub_ops)
end

---Get the active sub-operation for a parent operation
---@param parent_op_id string Parent operation ID
---@return table|nil Active sub-operation
function QuestModule:_get_active_sub_operation(parent_op_id)
    local sub_ops = self._blackboard:get("module.quest.sub_ops")
    if not sub_ops then return nil end

    local parent_state = sub_ops[parent_op_id]
    if not parent_state then return nil end

    -- Return the highest priority sub-operation that isn't completed
    if parent_state.sub_operations then
        local best = nil
        for _, sub in ipairs(parent_state.sub_operations) do
            if not parent_state.completed_subs[sub.id] then
                if not best or (sub.priority or 0) > (best.priority or 0) then
                    best = sub
                end
            end
        end
        parent_state.current_sub = best and best.id or nil
        return best
    end

    return nil
end

---Mark a sub-operation as completed
---@param parent_op_id string Parent operation ID
---@param sub_op_id string Sub-operation ID to mark completed
function QuestModule:_complete_sub_operation(parent_op_id, sub_op_id)
    local sub_ops = self._blackboard:get("module.quest.sub_ops")
    if not sub_ops then return end

    local parent_state = sub_ops[parent_op_id]
    if parent_state then
        parent_state.completed_subs[sub_op_id] = true
        self._blackboard:set("module.quest.sub_ops", sub_ops)
    end
end

---Handle quest_completed event
---@param payload table Event payload
function QuestModule:_on_quest_completed(payload)
    if not payload or not payload.quest_id then return end

    -- Re-evaluate goals for all operations in active profile
    if self._active_profile and self._active_profile.operations then
        for _, op in ipairs(self._active_profile.operations) do
            local result = self:check_goals(op)
            if result.all_met then
                self._event_bus:publish("operation_goals_met", { op_id = op.id })
            end
        end
    end
end

---Handle level_gained event
---@param payload table Event payload with player level
function QuestModule:_on_level_gained(payload)
    -- Check ReachLevel goals
    if self._active_profile and self._active_profile.operations then
        for _, op in ipairs(self._active_profile.operations) do
            if op.goals then
                for _, goal in ipairs(op.goals) do
                    if goal.type == "ReachLevel" then
                        local result = self:check_goals(op)
                        if result.all_met then
                            self._event_bus:publish("operation_goals_met", { op_id = op.id })
                        end
                    end
                end
            end
        end
    end
end

---Handle item_acquired event
---@param payload table Event payload with entry and count
function QuestModule:_on_item_acquired(payload)
    if not payload then return end

    -- Check AcquireItem goals
    if self._active_profile and self._active_profile.operations then
        for _, op in ipairs(self._active_profile.operations) do
            if op.goals then
                for _, goal in ipairs(op.goals) do
                    if goal.type == "AcquireItem" and goal.entry == payload.entry then
                        local result = self:check_goals(op)
                        if result.all_met then
                            self._event_bus:publish("operation_goals_met", { op_id = op.id })
                        end
                    end
                end
            end
        end
    end
end

---Handle profile_compiled event
---@param payload table Event payload with compiled profile
function QuestModule:_on_profile_compiled(payload)
    if payload and payload.profile then
        self:load_profile(payload.profile)
    end
end

return QuestModule