-- kernel/lib/priority_builder.lua
-- The Tier-1 rotation DSL, published as `Sentinel.rotation` (ADR 08 §5.4, §8.4).
--
-- PROMOTED FROM `modules/combat/priority_builder.lua`, unchanged except for the two dead requires
-- noted below. §13 risk 5 is explicit that the combat DSL is a mature asset to port rather than
-- rewrite, so the behaviour here is byte-for-byte the behaviour the three shipped profiles were
-- authored against; tests/kernel/test_rotation_lib.lua pins the contracts they rely on.
--
-- The move was possible at all because the only real dependencies were `core/bt/*`. It also used to
-- bind `condition_library` and `action_library` at the top of the file and then never reference
-- either -- they survive only in the comments at `_validate_priority` and `_build_priority_node`
-- that describe the `{function, arg}` call shapes. Those two requires were the sole thing tying this
-- file to `modules/combat/`, and they were never load-bearing.

local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local PriorityBuilder = {}
PriorityBuilder.__index = PriorityBuilder

-- ============================================================================
-- PRIORITY BUILDER DSL
-- ============================================================================

--- Create a new PriorityBuilder instance
-- @param profile_name string Name of the class/spec (e.g. "MAGE", "PALADIN")
-- @param spec_name string Specialization name (e.g. "FROST", "RETRIBUTION")
-- @return table PriorityBuilder instance
function PriorityBuilder.new(profile_name, spec_name)
    local self = setmetatable({}, PriorityBuilder)
    self.profile_name = profile_name
    self.spec_name = spec_name
    self.icon = nil
    self.priorities = {}  -- Ordered list of priority entries
    self.shared_subtrees = {}  -- Named subtrees to inject
    self.custom_conditions = {}  -- Custom condition functions
    self.custom_actions = {}   -- Custom action functions
    return self
end

--- Set the icon for this profile
-- @param icon number|string Spell ID or texture path
-- @return PriorityBuilder self (for chaining)
function PriorityBuilder:set_icon(icon)
    self.icon = icon
    return self
end

--- Add a custom condition function
-- @param name string Name of the condition
-- @param func function Function that takes blackboard and returns boolean
-- @return PriorityBuilder self (for chaining)
function PriorityBuilder:add_condition(name, func)
    self.custom_conditions[name] = func
    return self
end

--- Add a custom action function
-- @param name string Name of the action
-- @param func function Function that takes blackboard and returns BT.Status
-- @return PriorityBuilder self (for chaining)
function PriorityBuilder:add_action(name, func)
    self.custom_actions[name] = func
    return self
end

--- Add a priority entry
-- @param name string Display name for debugging
-- @param conditions table|function Condition(s) that must be true
-- @param action table|function Action to execute when conditions pass
-- @param children table Optional child priorities (for subtrees)
-- @param priority number Optional explicit priority override
-- @return PriorityBuilder self (for chaining)
function PriorityBuilder:add_priority(name, conditions, action, children, priority)
    table.insert(self.priorities, {
        name = name,
        conditions = conditions,
        action = action,
        children = children or {},
        priority = priority or 0  -- Lower numbers = higher priority in BST
    })
    return self
end

--- Add a shared subtree to be injected at specific points
-- @param name string Name of the subtree
-- @param subtree function Function that returns a BT node
-- @param insert_at string Where to insert: "start", "end", or number index
-- @return PriorityBuilder self (for chaining)
function PriorityBuilder:add_shared_subtree(name, subtree, insert_at)
    self.shared_subtrees[name] = {
        subtree = subtree,
        insert_at = insert_at or "end"
    }
    return self
end

--- Build the behavior tree from the priority list
-- @param blackboard table The blackboard to use
-- @return BT.Node The root behavior tree node
function PriorityBuilder:build(blackboard)
    self._blackboard = blackboard
    -- Validate all priorities
    for i, priority in ipairs(self.priorities) do
        if not self:_validate_priority(priority, i) then
            error(string.format("Invalid priority #%d: %s", i, priority.name or "unnamed"))
        end
    end
    
    -- Sort priorities by priority number (lower = higher priority)
    table.sort(self.priorities, function(a, b)
        return (a.priority or 0) < (b.priority or 0)
    end)
    
    -- Build the main selector (priority queue)
    local priority_nodes = {}
    for _, priority in ipairs(self.priorities) do
        local node = self:_build_priority_node(priority, blackboard)
        table.insert(priority_nodes, node)
    end
    
    local selector
    if #priority_nodes == 1 then
        selector = priority_nodes[1]
    else
        selector = BT.priority_selector(self.profile_name .. "_" .. self.spec_name .. "_priorities", priority_nodes)
    end
    
    -- Apply shared subtrees
    return self:_apply_shared_subtrees(selector)
end

-- ============================================================================
-- PRIVATE HELPER METHODS
-- ============================================================================

function PriorityBuilder:_validate_priority(priority, index)
    if not priority.name or type(priority.name) ~= "string" then
        return false
    end
    
    -- Conditions can be function or table of functions
    if priority.conditions then
        if type(priority.conditions) == "function" then
            -- Valid single condition
        elseif type(priority.conditions) == "table" then
            -- Validate each condition in the table
            for i, cond in ipairs(priority.conditions) do
                if type(cond) ~= "function" then
                    -- Could be a condition library reference like {ConditionLibrary.health_below, 0.3}
                    if type(cond) == "table" and #cond == 2 and type(cond[1]) == "function" then
                        -- Valid: function + arg
                    else
                        return false
                    end
                end
            end
        else
            return false
        end
    end
    
    -- Action can be function or table
    if priority.action then
        if type(priority.action) == "function" then
            -- Valid single action
        elseif type(priority.action) == "table" then
            -- Could be action library reference like {ActionLibrary.cast_target, "spell_key"}
            if #priority.action >= 1 and type(priority.action[1]) == "function" then
                -- Valid: function + args
            else
                return false
            end
        else
            return false
        end
    end
    
    -- Children should be a table if present
    if priority.children and type(priority.children) ~= "table" then
        return false
    end
    
    return true
end

function PriorityBuilder:_build_priority_node(priority, blackboard)
    -- Build condition node(s)
    local condition_node
    if type(priority.conditions) == "function" then
        condition_node = BT.condition(priority.name .. "_condition", priority.conditions)
    elseif type(priority.conditions) == "table" then
        -- Handle condition library references
        local conditions = {}
        for i, cond_spec in ipairs(priority.conditions) do
            if type(cond_spec) == "function" then
                table.insert(conditions, BT.condition(priority.name .. "_cond_" .. i, cond_spec))
            elseif type(cond_spec) == "table" and #cond_spec == 2 then
                -- Format: {function, arg}
                local func, arg = unpack(cond_spec)
                table.insert(conditions, BT.condition(priority.name .. "_cond_" .. i, 
                    function(bb) return func(bb, arg) end))
            else
                error("Invalid condition specification in priority " .. priority.name)
            end
        end
        -- Combine all conditions with AND
        if #conditions == 1 then
            condition_node = conditions[1]
        else
            condition_node = BT.sequence(priority.name .. "_conditions", conditions)
        end
    else
        -- No conditions = always true
        condition_node = BT.condition(priority.name .. "_always_true", function() return true end)
    end
    
    -- Build action node(s)
    local action_node
    if type(priority.action) == "function" then
        action_node = BT.action(priority.name .. "_action", priority.action)
    elseif type(priority.action) == "table" then
        -- Handle action library references
        local func = priority.action[1]
        local args = {select(2, unpack(priority.action))}
        action_node = BT.action(priority.name .. "_action", 
            function(bb)
                -- Unpack args and resolve any blackboard lookups
                local resolved_args = {}
                for i, arg in ipairs(args) do
                    if type(arg) == "table" and arg.type == "blackboard_lookup" then
                        resolved_args[i] = blackboard:get(arg.key)
                    else
                        resolved_args[i] = arg
                    end
                end
                return func(bb, unpack(resolved_args))
            end)
    else
        -- No action = noop
        action_node = BT.action(priority.name .. "_noop", function()
            return Status.FAILURE
        end)
    end

    local nodes = { condition_node, action_node }
    for _, child in ipairs(priority.children or {}) do
        if type(child) == "function" then
            nodes[#nodes + 1] = child(blackboard)
        elseif type(child) == "table" and type(child.tick) == "function" then
            nodes[#nodes + 1] = child
        else
            error("Invalid child subtree in priority " .. priority.name)
        end
    end
    return BT.sequence(priority.name, nodes)
end

function PriorityBuilder:_apply_shared_subtrees(root)
    local nodes = { root }
    local ordered = {}
    for name, entry in pairs(self.shared_subtrees) do
        ordered[#ordered + 1] = { name = name, entry = entry }
    end
    table.sort(ordered, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    for _, item in ipairs(ordered) do
        local entry = item.entry
        if type(entry.subtree) ~= "function" then
            error("Invalid shared subtree: " .. tostring(item.name))
        end
        local child = entry.subtree(self._blackboard)
        if child then
            if entry.insert_at == "start" then
                table.insert(nodes, 1, child)
            else
                nodes[#nodes + 1] = child
            end
        end
    end
    if #nodes == 1 then
        return root
    end
    return BT.priority_selector(self.profile_name .. "_" .. self.spec_name .. "_with_shared", nodes)
end

return PriorityBuilder
