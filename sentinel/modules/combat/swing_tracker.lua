local Events = require("modules/combat/events")

local SwingTracker = {}
SwingTracker.__index = SwingTracker

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

function SwingTracker:new(event_bus, blackboard, opts)
    local o = setmetatable({}, SwingTracker)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._opts = opts or {}
    o._next_swing_at_ms = 0
    o._last_target_guid = nil
    o._last_window_swing = nil
    return o
end

function SwingTracker:_detect_precise_remaining_ms(player)
    local methods = {
        "get_mainhand_swing_remaining_ms",
        "get_swing_timer_remaining_ms",
        "get_swing_timer_remaining",
    }
    for _, method in ipairs(methods) do
        local ok, value = safe_call(player, method)
        if ok and tonumber(value) then
            return tonumber(value), 1.0
        end
    end
    return nil, 0
end

function SwingTracker:update(blackboard)
    local now_ms = blackboard:get("system.now_ms", 0)
    local player = blackboard:get("player.object")
    local attack_speed_s = tonumber(blackboard:get("player.attack_speed_s", 0)) or 0
    local is_auto_attacking = blackboard:get("player.is_auto_attacking", false)
    local target = blackboard:get("combat.target") or blackboard:get("player.target")

    local target_guid = nil
    if target and type(target.get_guid) == "function" then
        local ok_guid, value = pcall(target.get_guid, target)
        if ok_guid then
            target_guid = tostring(value)
        end
    end

    local remaining_ms, confidence = self:_detect_precise_remaining_ms(player)
    if remaining_ms then
        self._next_swing_at_ms = now_ms + remaining_ms
    elseif is_auto_attacking and attack_speed_s > 0 then
        local cycle_ms = math.floor(attack_speed_s * 1000)
        if target_guid ~= self._last_target_guid or self._next_swing_at_ms <= 0 then
            self._next_swing_at_ms = now_ms + cycle_ms
        end
        while self._next_swing_at_ms <= now_ms do
            self._next_swing_at_ms = self._next_swing_at_ms + cycle_ms
        end
        remaining_ms = self._next_swing_at_ms - now_ms
        confidence = 0.35
    else
        self._next_swing_at_ms = 0
        remaining_ms = 99999
        confidence = 0
    end

    local twist_mode = blackboard:get("module.combat.twist_mode", "auto")
    local allow_estimated = blackboard:get("module.combat.allow_estimated_twist", false) == true
    local twist_enabled = false
    if confidence >= 0.95 then
        twist_enabled = true
    elseif confidence > 0 and (twist_mode == "force" or allow_estimated) then
        twist_enabled = true
    end

    blackboard:set("combat.swing.next_at_ms", self._next_swing_at_ms)
    blackboard:set("combat.swing.remaining_ms", remaining_ms)
    blackboard:set("combat.swing.confidence", confidence)
    blackboard:set("rotation.twist.enabled", twist_enabled)

    local twist_window_ms = tonumber(blackboard:get("module.combat.twist_window_ms", 350)) or 350
    if twist_enabled and remaining_ms > 0 and remaining_ms <= twist_window_ms then
        if self._last_window_swing ~= self._next_swing_at_ms then
            self._last_window_swing = self._next_swing_at_ms
            self._event_bus:publish(Events.TWIST_WINDOW_OPEN, {
                next_swing_at_ms = self._next_swing_at_ms,
                remaining_ms = remaining_ms,
                confidence = confidence,
            })
        end
    end

    if blackboard:get("rotation.twist.pending_reseal", false) == true and now_ms >= self._next_swing_at_ms and self._next_swing_at_ms > 0 then
        blackboard:set("rotation.twist.swing_rolled", true)
    else
        blackboard:set("rotation.twist.swing_rolled", false)
    end

    self._last_target_guid = target_guid
end

return SwingTracker
