local RC = require("ai/ResponseCurves")

---@class UtilityEvaluator
local UE = {}
UE.__index = UE

function UE:new()
    local o = setmetatable({}, UE)
    o._actions = {}
    return o
end

--- Check if a spell is on cooldown (including GCD for non-bypass actions).
---@param action table
---@param ignore_gcd? boolean  When true, skip the GCD check (for pre-queuing)
---@return boolean true if spell is unavailable
local function is_on_cooldown(action, ignore_gcd)
    if not action.spell_id then return false end
    if not core or not core.spell_book then return false end

    -- Check spell-specific cooldown
    if core.spell_book.get_spell_cooldown then
        local ok, cd = pcall(core.spell_book.get_spell_cooldown, action.spell_id)
        if ok and cd and cd > 0 then return true end
    end

    -- Check GCD for actions that don't bypass it
    if not ignore_gcd and not action.bypasses_gcd and core.spell_book.get_global_cooldown then
        local ok, gcd = pcall(core.spell_book.get_global_cooldown)
        if ok and gcd and gcd > 0 then return true end
    end

    return false
end

---Register an action with utility considerations.
---@param action table { id, weight, considerations[], hard_gate?, action_type?, spell_id?, ... }
function UE:register(action)
    self._actions[#self._actions + 1] = action
end

---Remove all registered actions.
function UE:clear()
    self._actions = {}
end

---Score a single action against the current context.
---Uses Dave Mark's IAUS compensation factor to prevent actions with more
---considerations from being unfairly penalized by multiplication approaching 0.
---@param action table
---@param ctx table
---@return number utility (0 if any consideration is 0)
function UE:_score(action, ctx)
    local considerations = action.considerations
    if not considerations or #considerations == 0 then
        return action.weight or 1.0
    end

    local product = 1
    local n = #considerations
    for i = 1, n do
        local c = considerations[i]
        local input_val = ctx[c.input] or 0
        local score = RC.evaluate(c.curve, input_val, c.params)
        if score ~= score then return 0 end  -- NaN guard
        if score <= 0 then
            return 0
        end
        product = product * score
    end

    -- Geometric mean with compensation factor (Dave Mark IAUS)
    local geo_mean = product ^ (1 / n)
    local make_up = (1 - geo_mean) * (1 - 1 / n)
    local compensated = geo_mean + (make_up * geo_mean)
    return compensated * (action.weight or 1.0)
end

--- Check if an action should be skipped (gates, learned, cooldown).
---@param action table
---@param ignore_gcd? boolean
---@return boolean
local function should_skip(action, ignore_gcd)
    -- Note: hard_gate context evaluation is handled in evaluate() before calling this.
    -- Do NOT early-return here — spell learned and cooldown checks still apply to hard_gate actions.
    if action.spell_id and core and core.spell_book
        and core.spell_book.is_spell_learned then
        if not core.spell_book.is_spell_learned(action.spell_id) then
            return true
        end
    end
    if is_on_cooldown(action, ignore_gcd) then
        return true
    end
    return false
end

---Evaluate all actions and return the best one.
---Uses bucket-priority: scores highest non-empty bucket first, falls through
---to lower buckets if all actions in a bucket score 0.
---Tiebreaker: when two actions have equal utility, the one with higher
---priority field wins (deterministic ordering).
---@param ctx table  Context keys mapping to numeric values
---@param opts? table  { ignore_gcd?: boolean } for GCD-aware pre-queuing
---@return table|nil  { action, utility } or nil if no valid actions
function UE:evaluate(ctx, opts)
    local ignore_gcd = opts and opts.ignore_gcd or false

    -- Collect valid actions into buckets (lower bucket number = higher priority)
    local buckets = {}
    local max_bucket = 0

    for i = 1, #self._actions do
        local action = self._actions[i]
        local skip = false

        if action.hard_gate and not action.hard_gate(ctx) then
            skip = true
        end
        if not skip and should_skip(action, ignore_gcd) then
            skip = true
        end

        if not skip then
            local bucket = action.bucket or 3
            if not buckets[bucket] then
                buckets[bucket] = {}
            end
            buckets[bucket][#buckets[bucket] + 1] = action
            if bucket > max_bucket then max_bucket = bucket end
        end
    end

    -- Score buckets from highest priority (0) to lowest
    for b = 0, max_bucket do
        local actions = buckets[b]
        if actions then
            local best_action = nil
            local best_utility = 0
            local best_priority = -1

            for j = 1, #actions do
                local action = actions[j]
                local utility = self:_score(action, ctx)
                local pri = action.priority or 0
                if utility > best_utility
                    or (utility > 0 and utility == best_utility and pri > best_priority) then
                    best_utility = utility
                    best_action = action
                    best_priority = pri
                end
            end

            if best_action and best_utility > 0 then
                return { action = best_action, utility = best_utility }
            end
            -- All actions in this bucket scored 0, fall through to next bucket
        end
    end

    return nil
end

---Return top K actions sorted by utility (descending).
---@param ctx table
---@param k number
---@param opts? table  { ignore_gcd?: boolean }
---@return table[]  Array of { action, utility }
function UE:get_top_k(ctx, k, opts)
    local ignore_gcd = opts and opts.ignore_gcd or false
    local scored = {}
    for i = 1, #self._actions do
        local action = self._actions[i]
        local skip = false
        if action.hard_gate and not action.hard_gate(ctx) then
            skip = true
        end
        if not skip and should_skip(action, ignore_gcd) then
            skip = true
        end
        if not skip then
            local utility = self:_score(action, ctx)
            if utility > 0 then
                scored[#scored + 1] = { action = action, utility = utility }
            end
        end
    end

    table.sort(scored, function(a, b)
        if a.utility ~= b.utility then return a.utility > b.utility end
        return (a.action.priority or 0) > (b.action.priority or 0)
    end)

    local result = {}
    for i = 1, math.min(k, #scored) do
        result[i] = scored[i]
    end
    return result
end

return UE
