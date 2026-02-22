---@class RotationPlanComposer
local PlanComposer = {}

local NEG_INF = -1000000000

---@private
---@param plan table[]
---@param actions table[]|nil
---@param default_intent string|nil
local function append_actions(plan, actions, default_intent)
    if type(actions) ~= "table" then
        return
    end

    for i = 1, #actions do
        local action = actions[i]
        if type(action) == "table" then
            if action.intent == nil and default_intent ~= nil then
                action.intent = default_intent
            end
            plan[#plan + 1] = action
        end
    end
end

---@private
---@param target table
---@param source table|nil
local function merge_state(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return
    end
    for key, value in pairs(source) do
        target[key] = value
    end
end

---@private
---@param action table
---@param current_mode string|nil
---@return boolean
local function action_mode_allowed(action, current_mode)
    if type(action) ~= "table" then
        return false
    end
    if current_mode == nil or current_mode == "" then
        return true
    end

    local modes = action.combat_modes
    if modes == nil then
        return true
    end

    if type(modes) == "string" then
        return modes == current_mode
    end

    if type(modes) == "table" then
        for i = 1, #modes do
            if tostring(modes[i]) == current_mode then
                return true
            end
        end
        return false
    end

    return true
end

---@private
---@param ctx table
---@return boolean
local function is_execute_phase(ctx)
    if type(ctx) ~= "table" then
        return false
    end
    if ctx.in_execute_phase == true then
        return true
    end
    local target_health_pct = tonumber(ctx.target_health_pct)
    return target_health_pct ~= nil and target_health_pct <= 0.20
end

---@private
---@param ctx table
---@return string
local function resolve_scheduler_mode(ctx)
    if type(ctx) ~= "table" then
        return "burst"
    end

    local mode = tostring(ctx.combat_mode or ctx.mana_mode or "")
    if mode ~= "" then
        return string.lower(mode)
    end

    local mana = tonumber(ctx.player_mana_pct)
    if mana ~= nil and mana <= 0.20 then
        return "recovery"
    end
    if mana ~= nil and mana <= 0.45 then
        return "sustain"
    end
    return "burst"
end

---@private
---@param ctx table
---@return table
local function resolve_intent_weights(ctx)
    local mode = resolve_scheduler_mode(ctx)
    local execute = is_execute_phase(ctx)

    local weights = {
        defensive = 320,
        interrupt = 260,
        utility = 45,
        sustain = 80,
        burst = 80,
        recover = 45,
        execute = execute and 150 or 0,
    }

    if mode == "burst" then
        weights.burst = 150
        weights.sustain = 70
        weights.recover = -160
    elseif mode == "sustain" then
        weights.sustain = 130
        weights.burst = 15
        weights.recover = 35
    elseif mode == "recovery" then
        weights.recover = 170
        weights.sustain = 65
        weights.burst = -220
    end

    local provider_intents = type(ctx) == "table" and ctx.planner_intents or nil
    if type(provider_intents) == "table" then
        for key, value in pairs(provider_intents) do
            local intent = string.lower(tostring(key or ""))
            if intent ~= "" then
                local existing = tonumber(weights[intent]) or 0
                local numeric = tonumber(value)
                if numeric ~= nil then
                    if math.abs(numeric) <= 2.0 then
                        weights[intent] = existing + (numeric * 100)
                    else
                        weights[intent] = numeric
                    end
                elseif value == true then
                    weights[intent] = existing + 100
                elseif value == false then
                    weights[intent] = existing - 220
                end
            end
        end
    end

    return weights
end

---@private
---@param action table
---@param intent_weights table
---@param mode string
---@return number
local function resolve_action_scheduler_bonus(action, intent_weights, mode)
    local bonus = tonumber(action and action.scheduler_bias) or 0
    if type(action) ~= "table" then
        return bonus
    end

    local intent = action.intent
    if type(intent) == "string" then
        bonus = bonus + (tonumber(intent_weights[string.lower(intent)]) or 0)
    elseif type(intent) == "table" then
        local best = 0
        for i = 1, #intent do
            local weight = tonumber(intent_weights[string.lower(tostring(intent[i]))]) or 0
            if i == 1 or weight > best then
                best = weight
            end
        end
        bonus = bonus + best
    end

    local dynamic_bonus = action.intent_bonus
    if type(dynamic_bonus) == "number" then
        bonus = bonus + dynamic_bonus
    elseif type(dynamic_bonus) == "table" then
        local mode_bonus = tonumber(dynamic_bonus[mode])
        if mode_bonus ~= nil then
            bonus = bonus + mode_bonus
        end
    end

    return bonus
end

---@private
---@param plan table[]
---@param ctx table
local function apply_combat_scheduler(plan, ctx)
    local mode = resolve_scheduler_mode(ctx)
    local intent_weights = resolve_intent_weights(ctx)

    local kept = {}
    for i = 1, #plan do
        local action = plan[i]
        if action_mode_allowed(action, mode) then
            local base_priority = tonumber(action.priority) or 0
            local scheduler_bonus = resolve_action_scheduler_bonus(action, intent_weights, mode)
            action._scheduler_priority = base_priority + scheduler_bonus
            kept[#kept + 1] = action
        else
            action._scheduler_priority = NEG_INF
        end
    end

    for i = 1, #kept do
        plan[i] = kept[i]
    end
    for i = #kept + 1, #plan do
        plan[i] = nil
    end
end

---@private
---@param actions table[]
---@param kind string
---@param ctx table
---@return number
local function maintenance_deficit(actions, kind, ctx)
    local current = nil
    local threshold = nil
    if kind == "food" then
        current = tonumber(ctx and ctx.player_health_pct) or 1.0
        for i = 1, #actions do
            local action = actions[i]
            if type(action) == "table" and action.item_kind == "food" and action.max_player_health_pct ~= nil then
                local candidate = tonumber(action.max_player_health_pct)
                if candidate ~= nil and (threshold == nil or candidate > threshold) then
                    threshold = candidate
                end
            end
        end
    elseif kind == "water" then
        current = tonumber(ctx and ctx.player_mana_pct) or 1.0
        for i = 1, #actions do
            local action = actions[i]
            if type(action) == "table" and action.item_kind == "water" and action.max_player_mana_pct ~= nil then
                local candidate = tonumber(action.max_player_mana_pct)
                if candidate ~= nil and (threshold == nil or candidate > threshold) then
                    threshold = candidate
                end
            end
        end
    end

    if threshold == nil then
        return 0
    end

    local missing = threshold - current
    if missing <= 0 then
        return 0
    end

    return missing / math.max(0.01, threshold)
end

---@private
---@param plan table[]
---@param ctx table
local function apply_maintenance_scheduler(plan, ctx)
    local food_deficit = maintenance_deficit(plan, "food", ctx)
    local water_deficit = maintenance_deficit(plan, "water", ctx)

    local dominant_kind = nil
    if food_deficit > 0 or water_deficit > 0 then
        dominant_kind = (water_deficit > food_deficit) and "water" or "food"
    end

    for i = 1, #plan do
        local action = plan[i]
        local base_priority = tonumber(action and action.priority) or 0
        local bonus = tonumber(action and action.scheduler_bias) or 0
        if dominant_kind ~= nil and type(action) == "table" and action.item_kind == dominant_kind then
            bonus = bonus + 25
        end
        action._scheduler_priority = base_priority + bonus
    end
end

---@private
---@param plan table[]
local function stable_priority_sort(plan)
    local insertion_order = {}
    for i = 1, #plan do
        insertion_order[plan[i]] = i
    end

    table.sort(plan, function(a, b)
        local ap = tonumber(a and (a._scheduler_priority or a.priority)) or 0
        local bp = tonumber(b and (b._scheduler_priority or b.priority)) or 0
        if ap == bp then
            return (insertion_order[a] or 0) < (insertion_order[b] or 0)
        end
        return ap > bp
    end)
end

---@param provider table
---@param ctx table
---@param aoe_threshold number
---@return table[]
function PlanComposer.compose_combat(provider, ctx, aoe_threshold)
    if provider and provider.resolve_combat_state then
        local ok_state, state = pcall(provider.resolve_combat_state, provider, ctx)
        if ok_state and type(state) == "table" then
            merge_state(ctx, state)
        end
    end

    local plan = {}

    append_actions(plan, provider:defensive(ctx), "defensive")
    append_actions(plan, provider:interrupt(ctx), "interrupt")
    append_actions(plan, provider:utility(ctx), "utility")

    local enemies = tonumber(ctx.enemy_count) or 1
    if enemies >= (tonumber(aoe_threshold) or 3) then
        append_actions(plan, provider:aoe(ctx), "sustain")
    else
        append_actions(plan, provider:combat(ctx), "sustain")
    end

    apply_combat_scheduler(plan, ctx)
    stable_priority_sort(plan)
    return plan
end

---@param provider table
---@param ctx table
---@return table[]
function PlanComposer.compose_maintenance(provider, ctx)
    if provider and provider.resolve_maintenance_state then
        local ok_state, state = pcall(provider.resolve_maintenance_state, provider, ctx)
        if ok_state and type(state) == "table" then
            merge_state(ctx, state)
        end
    end

    local plan = {}

    if provider and provider.maintenance then
        append_actions(plan, provider:maintenance(ctx), "recover")
    end

    apply_maintenance_scheduler(plan, ctx)
    stable_priority_sort(plan)
    return plan
end

return PlanComposer
