local Compat = require("shared/compat")
local safe_call = Compat.safe_call

local TransitionDetector = {}
TransitionDetector.__index = TransitionDetector

function TransitionDetector:new(blackboard, event_bus)
    return setmetatable({
        _blackboard = blackboard,
        _event_bus = event_bus,
    }, TransitionDetector)
end

function TransitionDetector:_unit_health_pct(unit, unit_helper)
    if not unit then return 1 end
    if unit_helper and type(unit_helper.get_health_percentage) == "function" then
        local ok, value = pcall(unit_helper.get_health_percentage, unit_helper, unit)
        if ok and type(value) == "number" then
            if value > 1 then value = value / 100 end
            return value
        end
    end
    local health = tonumber(safe_call(unit, "get_health") or 0) or 0
    local max_health = tonumber(safe_call(unit, "get_max_health") or 0) or 0
    if max_health <= 0 then return 1 end
    return health / max_health
end

function TransitionDetector:refresh(player, now_ms, unit_helper)
    if not player then return end
    local bb = self._blackboard
    local eb = self._event_bus

    -- Combat state
    local was_combat = bb:get("player.in_combat", false)
    local now_combat = safe_call(player, "is_in_combat") == true
    if was_combat ~= now_combat then
        eb:publish("player:combat_changed", {
            in_combat = now_combat,
            position = bb:get("player.position"),
        })
    end

    -- Death state
    local was_dead = bb:get("player.is_dead", false)
    local was_ghost = bb:get("player.is_ghost", false)
    local now_dead = safe_call(player, "is_dead") == true
    local now_ghost = safe_call(player, "is_ghost") == true
    if was_dead ~= now_dead or was_ghost ~= now_ghost then
        eb:publish("player:death_changed", {
            is_dead = now_dead,
            is_ghost = now_ghost,
        })
    end

    -- Mount state
    local was_mounted = bb:get("player.is_mounted", false)
    local now_mounted = safe_call(player, "is_mounted") == true
    if was_mounted ~= now_mounted then
        eb:publish("player:mount_changed", {
            is_mounted = now_mounted,
        })
    end

    -- Cast state transitions
    local was_casting = bb:get("player.is_casting", false)
    local was_channeling = bb:get("player.is_channeling", false)
    local now_casting = safe_call(player, "is_casting_spell") == true
    local now_channeling = safe_call(player, "is_channelling_spell") == true
    if not was_casting and now_casting then
        eb:publish("player:cast_started", {})
    elseif was_casting and not now_casting then
        eb:publish("player:cast_ended", {})
    end
    if not was_channeling and now_channeling then
        eb:publish("player:channel_started", {})
    elseif was_channeling and not now_channeling then
        eb:publish("player:channel_ended", {})
    end

    -- Health threshold crossings
    local prev_hp = bb:get("player.health_pct", 1)
    local curr_hp = self:_unit_health_pct(player, unit_helper)
    local thresholds = { 0.10, 0.15, 0.20, 0.30, 0.40, 0.50, 0.80, 0.95 }
    for _, t in ipairs(thresholds) do
        if (prev_hp >= t and curr_hp < t) or (prev_hp < t and curr_hp >= t) then
            eb:publish("player:health_threshold", {
                health_pct = curr_hp,
                threshold = t,
                direction = curr_hp < t and "below" or "above",
            })
        end
    end

    -- Auto-attack state
    local was_auto = bb:get("player.is_auto_attacking", false)
    local now_auto = safe_call(player, "is_auto_attacking") == true
    if was_auto ~= now_auto then
        eb:publish("player:auto_attack_changed", {
            is_auto_attacking = now_auto,
        })
    end
end

return TransitionDetector
