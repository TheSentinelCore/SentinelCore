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
---@return boolean true if spell is unavailable
local function is_on_cooldown(action)
    if not action.spell_id then return false end
    if not core or not core.spell_book then return false end

    -- Check spell-specific cooldown
    if core.spell_book.get_spell_cooldown then
        local ok, cd = pcall(core.spell_book.get_spell_cooldown, action.spell_id)
        if ok and cd and cd > 0 then return true end
    end

    -- Check GCD for actions that don't bypass it
    if not action.bypasses_gcd and core.spell_book.get_global_cooldown then
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

    -- Geometric mean * weight
    local geo_mean = product ^ (1 / n)
    return geo_mean * (action.weight or 1.0)
end

---Evaluate all actions and return the best one.
---@param ctx table  Context keys mapping to numeric values
---@return table|nil  { action, utility } or nil if no valid actions
function UE:evaluate(ctx)
    local best_action = nil
    local best_utility = 0

    for i = 1, #self._actions do
        local action = self._actions[i]
        local skip = false

        -- Hard gate check
        if action.hard_gate and not action.hard_gate(ctx) then
            skip = true
        end

        -- Skip unlearned spells
        if not skip and action.spell_id and core and core.spell_book
            and core.spell_book.is_spell_learned then
            if not core.spell_book.is_spell_learned(action.spell_id) then
                skip = true
            end
        end

        -- Skip spells on cooldown (including GCD)
        if not skip and is_on_cooldown(action) then
            skip = true
        end

        if not skip then
            local utility = self:_score(action, ctx)
            if utility > best_utility then
                best_utility = utility
                best_action = action
            end
        end
    end

    if not best_action then return nil end
    return { action = best_action, utility = best_utility }
end

---Return top K actions sorted by utility (descending).
---@param ctx table
---@param k number
---@return table[]  Array of { action, utility }
function UE:get_top_k(ctx, k)
    local scored = {}
    for i = 1, #self._actions do
        local action = self._actions[i]
        if action.hard_gate and not action.hard_gate(ctx) then
            -- skip
        elseif action.spell_id and core and core.spell_book
            and core.spell_book.is_spell_learned
            and not core.spell_book.is_spell_learned(action.spell_id) then
            -- skip unlearned
        elseif is_on_cooldown(action) then
            -- skip on cooldown
        else
            local utility = self:_score(action, ctx)
            if utility > 0 then
                scored[#scored + 1] = { action = action, utility = utility }
            end
        end
    end

    table.sort(scored, function(a, b) return a.utility > b.utility end)

    local result = {}
    for i = 1, math.min(k, #scored) do
        result[i] = scored[i]
    end
    return result
end

return UE
