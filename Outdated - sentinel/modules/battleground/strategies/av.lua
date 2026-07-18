local Strategies = {}

local _strategies = {
    zerg_rush = {
        id = "zerg_rush",
        label = "Zerg Rush",
    },
    tower_push = {
        id = "tower_push",
        label = "Tower Push",
    },
    turtle_defense = {
        id = "turtle_defense",
        label = "Turtle Defense",
    },
    balanced = {
        id = "balanced",
        label = "Balanced",
    },
}

local function num(v)
    return tonumber(v) or 0
end

local AV_MIN_X = -1450
local AV_MAX_X = 900
local AV_X_RANGE = AV_MAX_X - AV_MIN_X

local BASE_GY_IDS = {
    AID_STATION = true,
    STORMPIKE_GY = true,
    FROSTWOLF_GY = true,
    FROSTWOLF_HUT = true,
}

local function clamp01(v)
    if v < 0 then
        return 0
    end
    if v > 1 then
        return 1
    end
    return v
end

local function strategy_settings(ctx)
    if type(ctx) ~= "table" then
        return {}
    end
    if type(ctx.strategy_settings) == "table" then
        return ctx.strategy_settings
    end
    if type(ctx.settings) == "table" and type(ctx.settings.strategy) == "table" then
        return ctx.settings.strategy
    end
    return {}
end

local function priority_type_bonus(ctx, objective_type)
    local settings = strategy_settings(ctx)
    local list = settings and settings.objective_priority
    if type(list) ~= "table" then return 0 end
    for i, t in ipairs(list) do
        if t == objective_type then
            return math.max(0, (#list - i + 1) * 2)
        end
    end
    return 0
end

local function is_home_objective(ctx, objective)
    local side = objective and objective.side or "NEUTRAL"
    return side ~= "NEUTRAL" and side == (ctx and ctx.player_side or "UNKNOWN")
end

local function forward_progress_score(player_side, objective_x)
    local x = num(objective_x)
    if player_side == "ALLIANCE" then
        return clamp01((AV_MAX_X - x) / AV_X_RANGE)
    end
    if player_side == "HORDE" then
        return clamp01((x - AV_MIN_X) / AV_X_RANGE)
    end
    return 0
end

local function is_enemy_controlled(state)
    if state == nil then
        return false
    end
    return state.owner == "ENEMY"
end

local function is_friendly_controlled(state)
    if state == nil then
        return false
    end
    return state.owner == "FRIENDLY"
end

local function score_common(ctx, objective)
    local distance = num(objective.distance)
    local friendly_near = num(objective.allies_near)
    local enemy_near = num(objective.enemies_near)

    local score = 0
    score = score - (distance * 0.05)
    score = score + (friendly_near * 1.1)
    score = score - (enemy_near * 1.0)

    if objective.type == "BOSS" then
        score = score + 8
    elseif objective.type == "TOWER" then
        score = score + 6
    elseif objective.type == "GRAVEYARD" then
        score = score + 5
    end

    score = score + priority_type_bonus(ctx, objective.type)
    return score
end

local function zerg_rush_score(ctx, objective, state)
    local score = score_common(ctx, objective)
    if state and state.owner == "CONTESTED" then
        score = score + 15
    end
    if objective.type == "BOSS" then
        score = score + 40
    end
    if objective.type == "TOWER" then
        score = score - 10
    end
    if objective.type == "GRAVEYARD" then
        score = score - 6
    end
    return score
end

local function tower_push_score(ctx, objective, state)
    local score = score_common(ctx, objective)
    if state and state.owner == "CONTESTED" then
        score = score + 15
    end
    if objective.type == "TOWER" then
        score = score + 28
    end
    if objective.type == "BOSS" then
        score = score - 8
    end
    if objective.side and objective.side ~= "NEUTRAL" and is_enemy_controlled(state) then
        score = score + 15
    end
    return score
end

local function turtle_defense_score(ctx, objective, state)
    local score = score_common(ctx, objective)
    if state and state.owner == "CONTESTED" then
        score = score + 15
    end
    if objective.side == ctx.player_side then
        score = score + 14
    end
    if is_friendly_controlled(state) then
        score = score + 8
    end
    if objective.type == "BOSS" and objective.side ~= ctx.player_side then
        score = score - 20
    end
    return score
end

local function balanced_score(ctx, objective, state)
    local score = score_common(ctx, objective)
    local settings = strategy_settings(ctx)
    local momentum = num(ctx.momentum_score)
    local enemy_near = num(objective.enemies_near)
    local owner = objective.owner or (state and state.owner) or "UNKNOWN"
    local side = objective.side or "NEUTRAL"

    local advance_first = settings.balanced_advance_first ~= false
    local home_idle_penalty = tonumber(settings.balanced_home_idle_penalty) or 28
    local base_gy_idle_penalty = tonumber(settings.balanced_base_gy_idle_penalty) or 36
    local enemy_owner_bonus = tonumber(settings.balanced_enemy_owner_bonus) or 14
    local contested_bonus = tonumber(settings.balanced_contested_bonus) or 18
    local forward_weight = tonumber(settings.balanced_forward_progress_weight) or 0.035
    local home_threat_threshold = tonumber(settings.balanced_home_threat_threshold) or 1

    if owner == "ENEMY" then
        score = score + enemy_owner_bonus
    end
    if owner == "CONTESTED" then
        score = score + contested_bonus
    end
    if side ~= "NEUTRAL" and side ~= ctx.player_side then
        score = score + (enemy_owner_bonus * 0.7)
    end

    local home_objective = is_home_objective(ctx, objective)
    local defended_under_threat = home_objective and owner == "FRIENDLY" and enemy_near >= home_threat_threshold
    if home_objective and owner == "FRIENDLY" and (not defended_under_threat) then
        score = score - home_idle_penalty
        if BASE_GY_IDS[objective.id] then
            score = score - base_gy_idle_penalty
        end
    elseif defended_under_threat then
        score = score + (contested_bonus * 0.6)
    end

    if advance_first then
        local forward_progress = forward_progress_score(ctx.player_side, objective.x)
        score = score + (forward_progress * forward_weight * 100)
    end

    score = score + (momentum * 4)

    -- Late-game urgency: push toward enemy boss after 20 minutes
    local runtime_min = num(ctx.runtime_ms or 0) / 60000
    if runtime_min >= 20 then
        local urgency = math.min(1.0, (runtime_min - 20) / 10)
        if objective.type == "BOSS" and not is_home_objective(ctx, objective) then
            score = score + (urgency * 15)
        end
    end

    return score
end

local score_dispatch = {
    zerg_rush = zerg_rush_score,
    tower_push = tower_push_score,
    turtle_defense = turtle_defense_score,
    balanced = balanced_score,
}

function Strategies:list()
    local out = {}
    for _, v in pairs(_strategies) do
        out[#out + 1] = { id = v.id, label = v.label }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Strategies:get(name)
    local key = tostring(name or "balanced")
    local entry = _strategies[key]
    if not entry then
        entry = _strategies.balanced
        key = "balanced"
    end

    return {
        id = entry.id,
        label = entry.label,
        score = function(ctx, objective, state)
            local fn = score_dispatch[key] or balanced_score
            return fn(ctx, objective, state)
        end,
    }
end

return Strategies
