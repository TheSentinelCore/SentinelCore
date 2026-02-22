---@class RestPolicyThresholds
---@field eat_start_pct number
---@field drink_start_pct number
---@field eat_stop_pct number
---@field drink_stop_pct number
---@field rest_until_full boolean

local RestPolicy = {}

---@private
---@param value any
---@param fallback number
---@return number
local function clamp_pct(value, fallback)
    local pct = tonumber(value)
    if pct == nil then
        pct = tonumber(fallback) or 0
    end
    if pct < 0 then
        return 0
    end
    if pct > 1 then
        return 1
    end
    return pct
end

---@private
---@param policy table|nil
---@param key string
---@param default_value boolean
---@return boolean
local function bool_value(policy, key, default_value)
    if type(policy) ~= "table" then
        return default_value
    end
    local value = policy[key]
    if value == nil then
        return default_value
    end
    return value == true
end

---@private
---@param ctx table|nil
---@return boolean
local function has_active_rest_signal(ctx)
    if type(ctx) ~= "table" then
        return false
    end
    if ctx.eating_or_drinking == true
        or ctx.player_is_eating == true
        or ctx.player_is_drinking == true then
        return true
    end

    local now = tonumber(ctx.now) or 0
    local generic_lock = tonumber(ctx.rest_lock_until) or 0
    if generic_lock > now then
        return true
    end
    local food_lock = tonumber(ctx.rest_lock_food_until) or 0
    if food_lock > now then
        return true
    end
    local water_lock = tonumber(ctx.rest_lock_water_until) or 0
    if water_lock > now then
        return true
    end
    return false
end

---@param policy table|nil
---@param opts? table
---@return RestPolicyThresholds
function RestPolicy.resolve(policy, opts)
    opts = opts or {}
    local eat_start_pct = clamp_pct(type(policy) == "table" and policy.eat_health_pct or nil,
        tonumber(opts.default_eat_start) or 0)
    local drink_start_pct = clamp_pct(type(policy) == "table" and policy.drink_mana_pct or nil,
        tonumber(opts.default_drink_start) or 0)
    local eat_stop_pct = clamp_pct(type(policy) == "table" and policy.rest_resume_health_pct or nil,
        tonumber(opts.default_eat_stop) or 1.0)
    local drink_stop_pct = clamp_pct(type(policy) == "table" and policy.rest_resume_mana_pct or nil,
        tonumber(opts.default_drink_stop) or 1.0)

    if eat_stop_pct < eat_start_pct then
        eat_stop_pct = eat_start_pct
    end
    if drink_stop_pct < drink_start_pct then
        drink_stop_pct = drink_start_pct
    end

    local rest_until_full = bool_value(policy, "rest_until_full", opts.default_rest_until_full ~= false)

    return {
        eat_start_pct = eat_start_pct,
        drink_start_pct = drink_start_pct,
        eat_stop_pct = eat_stop_pct,
        drink_stop_pct = drink_stop_pct,
        rest_until_full = rest_until_full,
    }
end

---@param ctx table|nil
---@param thresholds RestPolicyThresholds
---@return boolean
function RestPolicy.needs_health_rest(ctx, thresholds)
    local health_pct = tonumber(ctx and ctx.player_health_pct)
    if health_pct == nil then
        return false
    end
    if health_pct < thresholds.eat_start_pct then
        return true
    end
    if thresholds.rest_until_full ~= true then
        return false
    end
    if health_pct >= thresholds.eat_stop_pct then
        return false
    end
    return has_active_rest_signal(ctx)
end

---@param ctx table|nil
---@param thresholds RestPolicyThresholds
---@return boolean
function RestPolicy.needs_mana_rest(ctx, thresholds)
    local mana_pct = tonumber(ctx and ctx.player_mana_pct)
    if mana_pct == nil then
        return false
    end
    if mana_pct < thresholds.drink_start_pct then
        return true
    end
    if thresholds.rest_until_full ~= true then
        return false
    end
    if mana_pct >= thresholds.drink_stop_pct then
        return false
    end
    return has_active_rest_signal(ctx)
end

---@param ctx table|nil
---@param thresholds RestPolicyThresholds
---@return boolean
function RestPolicy.should_hold(ctx, thresholds)
    if type(ctx) ~= "table" or ctx.in_combat == true then
        return false
    end
    return RestPolicy.needs_health_rest(ctx, thresholds) or RestPolicy.needs_mana_rest(ctx, thresholds)
end

return RestPolicy
