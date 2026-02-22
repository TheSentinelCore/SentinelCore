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
---@param ctx table
---@return number
local function resolve_action_scheduler_bonus(action, intent_weights, mode, ctx)
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
    elseif type(dynamic_bonus) == "function" then
        local ok_bonus, value = pcall(dynamic_bonus, ctx, action, mode)
        if ok_bonus and tonumber(value) then
            bonus = bonus + tonumber(value)
        end
    end

    return bonus
end

local DEFAULT_RELATIVE_DEADLINES = {
    defensive = 0.45,
    interrupt = 0.20,
    execute = 0.40,
    sustain = 0.95,
    burst = 1.20,
    recover = 1.10,
    utility = 1.60,
}

---@private
---@param action table
---@return string[]
local function action_intents(action)
    if type(action) ~= "table" then
        return { "sustain" }
    end

    if type(action.intent) == "string" and action.intent ~= "" then
        return { string.lower(action.intent) }
    end

    if type(action.intent) == "table" and #action.intent > 0 then
        local out = {}
        for i = 1, #action.intent do
            out[#out + 1] = string.lower(tostring(action.intent[i]))
        end
        return out
    end

    return { "sustain" }
end

---@private
---@param action table
---@param mode string
---@return number|nil
local function action_relative_deadline_override(action, mode)
    if type(action) ~= "table" then
        return nil
    end

    if tonumber(action.relative_deadline_sec) then
        return tonumber(action.relative_deadline_sec)
    end

    local per_mode = action.relative_deadline_by_mode
    if type(per_mode) == "table" then
        local mode_deadline = tonumber(per_mode[mode]) or tonumber(per_mode.default)
        if mode_deadline then
            return mode_deadline
        end
    end

    return nil
end

---@private
---@param action table
---@param ctx table
---@return number
local function resolve_action_release_delay(action, ctx)
    local release = tonumber(action and action.release_delay_sec) or 0
    if type(action) ~= "table" then
        return math.max(0, release)
    end

    local action_type = tostring(action.action_type or "")
    if (action_type == "cast_spell_target" or action_type == "cast_spell_self" or action_type == "cast_spell_position") then
        local gcd = tonumber(ctx and ctx.global_cooldown_remaining) or 0
        if gcd > release then
            release = gcd
        end

        local spell_id = tonumber(action._resolved_spell_id or action.spell_id) or 0
        if spell_id <= 0 and type(action.spell_id) == "function" then
            local ok_spell, value = pcall(action.spell_id, ctx, action)
            if ok_spell and tonumber(value) and tonumber(value) > 0 then
                spell_id = tonumber(value)
            end
        end

        if spell_id > 0 and type(ctx and ctx.spell_cooldown_remaining) == "function" then
            local ok_cd, cooldown = pcall(ctx.spell_cooldown_remaining, spell_id)
            if ok_cd and tonumber(cooldown) and tonumber(cooldown) > release then
                release = tonumber(cooldown)
            end
        end
    end

    local target_distance = tonumber(ctx and ctx.target_distance)
    local move_speed = tonumber(ctx and ctx.player_move_speed) or 7.0
    if move_speed <= 0 then
        move_speed = 7.0
    end

    if target_distance and action.max_target_distance and target_distance > action.max_target_distance then
        local travel = (target_distance - action.max_target_distance) / move_speed
        if travel > release then
            release = travel
        end
    end
    if target_distance and action.min_target_distance and target_distance < action.min_target_distance then
        local retreat = (action.min_target_distance - target_distance) / move_speed
        if retreat > release then
            release = retreat
        end
    end

    if action.allow_movement ~= true and ctx and ctx.player_is_moving == true then
        if 0.25 > release then
            release = 0.25
        end
    end

    if action.target_must_be_casting == true and ctx and ctx.target_is_casting ~= true then
        if 1.20 > release then
            release = 1.20
        end
    end

    if release < 0 then
        release = 0
    end
    return release
end

---@private
---@param action table
---@param ctx table
---@param mode string
---@return number
local function resolve_action_relative_deadline(action, ctx, mode)
    local override = action_relative_deadline_override(action, mode)
    if override and override > 0 then
        return override
    end

    local intents = action_intents(action)
    local deadline = nil
    for i = 1, #intents do
        local candidate = tonumber(DEFAULT_RELATIVE_DEADLINES[intents[i]])
        if candidate ~= nil and (deadline == nil or candidate < deadline) then
            deadline = candidate
        end
    end
    if deadline == nil then
        deadline = DEFAULT_RELATIVE_DEADLINES.sustain
    end

    local player_health_pct = tonumber(ctx and ctx.player_health_pct) or 1.0
    if player_health_pct <= 0.20 then
        deadline = math.min(deadline, 0.20)
    elseif player_health_pct <= 0.35 then
        deadline = math.min(deadline, 0.35)
    end

    local melee = action and action.max_target_distance and tonumber(action.max_target_distance) ~= nil
        and tonumber(action.max_target_distance) <= 6.0
    local swing_remaining = tonumber(ctx and ctx.melee_swing_remaining) or 0
    if melee and swing_remaining > 0 then
        deadline = math.min(deadline, math.max(0.12, swing_remaining + 0.10))
    end

    return math.max(0.08, deadline)
end

---@private
---@param plan table[]
---@param ctx table
local function apply_combat_scheduler(plan, ctx)
    local mode = resolve_scheduler_mode(ctx)
    local intent_weights = resolve_intent_weights(ctx)
    local now = tonumber(ctx and ctx.now) or 0

    local kept = {}
    for i = 1, #plan do
        local action = plan[i]
        if action_mode_allowed(action, mode) then
            local base_priority = tonumber(action.priority) or 0
            local scheduler_bonus = resolve_action_scheduler_bonus(action, intent_weights, mode, ctx)
            local release_delay = resolve_action_release_delay(action, ctx)
            local relative_deadline = resolve_action_relative_deadline(action, ctx, mode)
            action._scheduler_priority = base_priority + scheduler_bonus
            action._scheduler_release = release_delay
            action._scheduler_relative_deadline = relative_deadline
            action._scheduler_deadline = now + release_delay + relative_deadline
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
        if type(action) == "table" then
            local kind = tostring(action.item_kind or "")
            if kind == "food" then
                bonus = bonus + (food_deficit * 120)
            elseif kind == "water" then
                bonus = bonus + (water_deficit * 120)
            end
            if dominant_kind ~= nil and kind == dominant_kind then
                bonus = bonus + 18
            end
        end
        action._scheduler_priority = base_priority + bonus
    end
end

---@private
---@param plan table[]
---@param ready_window number
local function stable_deadline_sort(plan, ready_window)
    local insertion_order = {}
    for i = 1, #plan do
        insertion_order[plan[i]] = i
    end

    table.sort(plan, function(a, b)
        local ar = tonumber(a and a._scheduler_release) or 0
        local br = tonumber(b and b._scheduler_release) or 0
        local a_ready = ar <= ready_window
        local b_ready = br <= ready_window
        if a_ready ~= b_ready then
            return a_ready
        end

        local ad = tonumber(a and a._scheduler_deadline) or math.huge
        local bd = tonumber(b and b._scheduler_deadline) or math.huge
        if ad ~= bd then
            return ad < bd
        end

        if ar ~= br then
            return ar < br
        end

        local ap = tonumber(a and (a._scheduler_priority or a.priority)) or 0
        local bp = tonumber(b and (b._scheduler_priority or b.priority)) or 0
        if ap ~= bp then
            return ap > bp
        end

        return (insertion_order[a] or 0) < (insertion_order[b] or 0)
    end)
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
    stable_deadline_sort(plan, tonumber(ctx and ctx.scheduler_ready_window) or 0.05)
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
