local CombatZoneDetector = {}
CombatZoneDetector.__index = CombatZoneDetector

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function safe_require(mod)
    local ok, m = pcall(require, mod)
    if ok then
        return m
    end
    return nil
end

function CombatZoneDetector:new(event_bus, blackboard)
    local o = setmetatable({}, CombatZoneDetector)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._unit_helper = safe_require("common/utility/unit_helper")
    o._in_combat_zone = false
    o._current_tier = 0
    o._last_eval_ms = 0
    o._eval_interval_ms = 500
    return o
end

function CombatZoneDetector:update(blackboard)
    local now_ms = blackboard:get("system.now_ms", 0)

    local player_pos = blackboard:get("player.position")

    -- Always re-evaluate when BG becomes inactive - clear cached state
    if blackboard:get("bg.active", false) ~= true then
        self:_set_state(false, 0)
        blackboard:set("bg.combat_zone", self._in_combat_zone)
        blackboard:set("bg.combat_zone_tier", self._current_tier)
        self._last_eval_ms = 0 -- Reset throttle so next BG activation triggers immediate eval
        return
    end

    -- Throttle to 500ms when BG is active
    if (now_ms - self._last_eval_ms) < self._eval_interval_ms then
        blackboard:set("bg.combat_zone", self._in_combat_zone)
        blackboard:set("bg.combat_zone_tier", self._current_tier)
        return
    end
    self._last_eval_ms = now_ms

    -- Scan allies within 60yd
    local allies = {}
    if self._unit_helper and type(self._unit_helper.get_ally_list_around) == "function" and type(player_pos) == "table" then
        local ok, list = pcall(self._unit_helper.get_ally_list_around, self._unit_helper, player_pos, 60, true, false, false)
        if ok and type(list) == "table" then
            allies = list
        end
    end

    if #allies < 2 then
        self:_set_state(false, 0)
        blackboard:set("bg.combat_zone", self._in_combat_zone)
        blackboard:set("bg.combat_zone_tier", self._current_tier)
        return
    end

    local new_tier = 0
    local new_combat_zone = false

    -- Tier 2 check: 40%+ allies in combat, <33% mounted
    local total_count = #allies
    local in_combat_count = 0
    local mounted_count = 0
    for i = 1, total_count do
        local ally = allies[i]
        local ok_c, in_combat = safe_call(ally, "is_in_combat")
        if ok_c and in_combat == true then
            in_combat_count = in_combat_count + 1
        end
        local ok_m, is_mounted = safe_call(ally, "is_mounted")
        if ok_m and is_mounted == true then
            mounted_count = mounted_count + 1
        end
    end

    local combat_pct = in_combat_count / total_count
    local mount_pct = mounted_count / total_count

    if combat_pct >= 0.40 and mount_pct < 0.33 then
        new_tier = 2
        new_combat_zone = true
    end

    -- Tier 3 check: direct threat (always runs, overrides tier 2)
    local player = blackboard:get("player.object")
    if self._unit_helper and type(self._unit_helper.get_enemy_list_around) == "function" and type(player_pos) == "table" then
        local ok, enemy_list = pcall(self._unit_helper.get_enemy_list_around, self._unit_helper, player_pos, 16, true, false, true, false)
        if ok and type(enemy_list) == "table" then
            for i = 1, #enemy_list do
                local enemy = enemy_list[i]
                local ok_t, target = safe_call(enemy, "get_target")
                if ok_t and target then
                    local ok_f, is_friend = safe_call(target, "is_friend_with", player)
                    if ok_f and is_friend == true then
                        local ok_tp, target_pos = safe_call(target, "get_position")
                        if ok_tp and type(target_pos) == "table" and type(player_pos) == "table" then
                            local dx = (tonumber(target_pos.x) or 0) - (tonumber(player_pos.x) or 0)
                            local dy = (tonumber(target_pos.y) or 0) - (tonumber(player_pos.y) or 0)
                            local dz = (tonumber(target_pos.z) or 0) - (tonumber(player_pos.z) or 0)
                            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                            if dist <= 30 then
                                new_tier = 3
                                new_combat_zone = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    self:_set_state(new_combat_zone, new_tier)
    blackboard:set("bg.combat_zone", self._in_combat_zone)
    blackboard:set("bg.combat_zone_tier", self._current_tier)
end

function CombatZoneDetector:_set_state(combat_zone, tier)
    local was_in_zone = self._in_combat_zone
    self._in_combat_zone = combat_zone
    self._current_tier = tier

    if not was_in_zone and combat_zone then
        self._event_bus:publish("bg:combat_zone_entered", { tier = tier })
    elseif was_in_zone and not combat_zone then
        self._event_bus:publish("bg:combat_zone_left", {})
    end
end

function CombatZoneDetector:is_combat_zone()
    return self._in_combat_zone
end

function CombatZoneDetector:get_tier()
    return self._current_tier
end

return CombatZoneDetector
