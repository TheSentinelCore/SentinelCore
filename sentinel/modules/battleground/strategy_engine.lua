local AVDefinition = require("modules/battleground/definitions/av")
local WSGDefinition = require("modules/battleground/definitions/wsg")
local ABDefinition = require("modules/battleground/definitions/ab")
local EOTSDefinition = require("modules/battleground/definitions/eots")

local StrategyEngine = {}
StrategyEngine.__index = StrategyEngine

local function num(value)
    return tonumber(value) or 0
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function objective_side_from_hint(hint)
    local value = tostring(hint or "")
    if value:find("ALLIANCE", 1, true) then
        return "ALLIANCE"
    end
    if value:find("HORDE", 1, true) then
        return "HORDE"
    end
    return "NEUTRAL"
end

local function is_rejectable_type(objective_type)
    return objective_type == "GRAVEYARD" or objective_type == "TOWER" or objective_type == "NODE"
end

local function is_player_unit(unit)
    if not unit or type(unit.is_player) ~= "function" then
        return false
    end
    local ok, value = pcall(unit.is_player, unit)
    return ok and value == true
end

local function count_units(unit_helper, method, position, radius)
    if not unit_helper or type(unit_helper[method]) ~= "function" or type(position) ~= "table" then
        return 0
    end
    local ok, list = pcall(unit_helper[method], unit_helper, position, radius, true, false)
    if not ok or type(list) ~= "table" then
        return 0
    end
    local count = 0
    for _, unit in ipairs(list) do
        if is_player_unit(unit) then
            count = count + 1
        end
    end
    return count
end

local function is_satisfied_local_friendly(candidate, settings)
    if type(candidate) ~= "table" then
        return false
    end
    if candidate.owner ~= "FRIENDLY" then
        return false
    end
    if not is_rejectable_type(candidate.type) then
        return false
    end
    local radius = tonumber(settings.objective_skip_if_satisfied_radius) or 18
    local threat_limit = tonumber(settings.objective_skip_threat_enemy_count) or 0
    if num(candidate.distance) > radius then
        return false
    end
    if num(candidate.enemies_near) > threat_limit then
        return false
    end
    return true
end

function StrategyEngine:new(blackboard)
    local o = setmetatable({}, StrategyEngine)
    o._blackboard = blackboard
    local ok, unit_helper = pcall(require, "common/utility/unit_helper")
    o._unit_helper = ok and unit_helper or nil
    o._definitions = {
        AV = AVDefinition,
        WSG = WSGDefinition,
        AB = ABDefinition,
        EOTS = EOTSDefinition,
    }
    o._strategy_by_bg = {
        AV = "balanced",
        WSG = "balanced",
        AB = "balanced",
        EOTS = "balanced",
    }
    return o
end

function StrategyEngine:get_definition(bg_key)
    return self._definitions[tostring(bg_key or "")]
end

function StrategyEngine:get_strategy(bg_key)
    return self._strategy_by_bg[tostring(bg_key or "")] or "balanced"
end

function StrategyEngine:evaluate(ctx)
    local definition = self:get_definition(ctx.bg_key)
    if not definition then
        return nil, {}
    end

    local strategy_name = self:get_strategy(ctx.bg_key)
    local strategy = definition:get_strategy(strategy_name)
    if not strategy then
        return nil, {}
    end

    local candidates = {}
    local strategy_settings = ctx.strategy_settings or {}

    for _, objective in ipairs(definition:get_objectives() or {}) do
        local position = { x = objective.x, y = objective.y, z = objective.z }
        local state = ctx.objective_states[objective.id]
        local candidate = {
            id = objective.id,
            type = objective.type,
            x = objective.x,
            y = objective.y,
            z = objective.z,
            objective = objective,
            side = objective_side_from_hint(objective.team_hint),
            owner = state and state.owner or "UNKNOWN",
            raw_owner = state and state.raw_owner or nil,
            distance = distance(ctx.player_position, position),
            allies_near = count_units(self._unit_helper, "get_ally_list_around", position, 35),
            enemies_near = count_units(self._unit_helper, "get_enemy_list_around", position, 35),
            score = 0,
        }
        candidate.score = strategy.score(ctx, candidate, state)
        candidates[#candidates + 1] = candidate
    end

    table.sort(candidates, function(a, b)
        if a.score == b.score then
            return a.distance < b.distance
        end
        return a.score > b.score
    end)

    local selected = nil
    local rejection_meta = nil
    for index, candidate in ipairs(candidates) do
        if is_satisfied_local_friendly(candidate, strategy_settings) then
            candidate.rejected = true
            candidate.rejection_reason = "friendly_local_satisfied"
            if index == 1 and not rejection_meta then
                rejection_meta = {
                    rejected_top_candidate_id = candidate.id,
                    rejection_reason = "friendly_local_satisfied",
                }
            end
        else
            selected = candidate
            break
        end
    end

    if not selected then
        selected = candidates[1]
    end

    local default_route_id = definition:get_route_for_strategy(strategy.id, ctx.player_side)
    if tostring(ctx.bg_key or "") == "EOTS" and selected then
        if selected.id == "CENTER_FLAG" then
            default_route_id = definition:get_route_for_strategy("flag_focus", ctx.player_side)
        else
            default_route_id = nil
        end
    end

    return {
        strategy_id = strategy.id,
        strategy_label = strategy.label,
        selected = selected,
        candidates = candidates,
        selection_meta = {
            rejected_top_candidate_id = rejection_meta and rejection_meta.rejected_top_candidate_id or nil,
            rejection_reason = rejection_meta and rejection_meta.rejection_reason or nil,
            selected_candidate = selected and {
                id = selected.id,
                score = selected.score,
                owner = selected.owner,
                distance = selected.distance,
            } or nil,
        },
        default_route_id = default_route_id,
        bootstrap_route_id = definition.get_bootstrap_route and definition:get_bootstrap_route(ctx.player_side, selected and selected.id or nil, strategy.id) or nil,
    }, candidates
end

return StrategyEngine
