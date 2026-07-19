local Policy = {}
Policy.__index = Policy

function Policy:new()
    return setmetatable({}, Policy)
end

function Policy:should_engage(blackboard, state_machine)
    if blackboard:get("module.bg.auto_engage", true) ~= true then
        return false
    end
    if not state_machine or not state_machine:should_engage() then
        return false
    end
    local health_pct = tonumber(blackboard:get("player.health_pct", 0)) or 0
    local enemies = tonumber(blackboard:get("combat.enemy_count_10yd", 0)) or 0
    local allies = tonumber(blackboard:get("combat.ally_count_30yd", 0)) or 0
    local health_threshold = tonumber(blackboard:get("module.bg.low_health_threshold", 0.35)) or 0.35
    local engage_grace = tonumber(blackboard:get("module.bg.engage_outnumber_grace", 1)) or 1
    return enemies > 0 and health_pct > health_threshold and enemies <= (allies + engage_grace)
end

function Policy:should_retreat(blackboard)
    local health_pct = tonumber(blackboard:get("player.health_pct", 0)) or 0
    local enemies = tonumber(blackboard:get("combat.enemy_count_10yd", 0)) or 0
    local allies = tonumber(blackboard:get("combat.ally_count_30yd", 0)) or 0
    local health_threshold = tonumber(blackboard:get("module.bg.low_health_threshold", 0.35)) or 0.35
    local retreat_delta = tonumber(blackboard:get("module.bg.retreat_outnumber_delta", 2)) or 2
    if health_pct <= health_threshold then
        return true, "low_health"
    end
    if enemies >= (allies + retreat_delta) and enemies > 0 then
        return true, "outnumbered"
    end
    return false, nil
end

return Policy
