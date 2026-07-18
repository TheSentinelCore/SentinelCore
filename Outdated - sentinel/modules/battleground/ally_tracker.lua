local Events = require("modules/battleground/events")

local unit_helper
do
    local ok, mod = pcall(require, "common/utility/unit_helper")
    if ok and mod then
        unit_helper = mod
    end
end

local function num(v)
    return tonumber(v) or 0
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, result = pcall(obj[method], obj, ...)
    if ok then
        return result
    end
    return nil
end

local function get_guid(unit)
    if not unit then
        return nil
    end
    if type(unit.get_guid) == "function" then
        local ok, guid = pcall(unit.get_guid, unit)
        if ok and guid then
            return tostring(guid)
        end
    end
    return nil
end

local AllyTracker = {}
AllyTracker.__index = AllyTracker

function AllyTracker:new(event_bus, blackboard, humanization)
    local o = setmetatable({}, AllyTracker)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._humanization = humanization
    o._unit_helper = unit_helper
    o._current_target = nil
    o._current_target_guid = nil
    o._current_score = nil
    o._cache_until_ms = 0
    o._idle_blacklist = {}
    o._last_positions = {}
    o._scan_radius = 60
    o._idle_threshold_ms = 7000
    o._cache_duration_ms = 4000
    return o
end

function AllyTracker:reset()
    self._current_target = nil
    self._current_target_guid = nil
    self._current_score = nil
    self._cache_until_ms = 0
    self._idle_blacklist = {}
    self._last_positions = {}
end

function AllyTracker:update(blackboard)
    local now_ms = num(blackboard:get("system.now_ms", 0))
    local player = blackboard:get("player.object")
    local player_pos = blackboard:get("player.position")

    if blackboard:get("bg.active", false) ~= true then
        self:reset()
        return
    end

    local allies = self:_scan_allies(player_pos)
    self:_update_idle_blacklist(allies, now_ms)

    -- Check if cached target is still valid
    if now_ms < self._cache_until_ms and self._current_target then
        local guid = self._current_target_guid
        if not self:_is_blacklisted(guid) and self:_is_valid_target(self._current_target, player_pos) then
            self:_write_blackboard(blackboard, allies)
            return
        end
    end

    -- Score all non-blacklisted allies and pick best
    local enemies = self:_scan_enemies(player_pos)
    local best_target = nil
    local best_guid = nil
    local best_score = -math.huge

    for _, ally in ipairs(allies) do
        local guid = get_guid(ally)
        if guid and not self:_is_blacklisted(guid) then
            local score = self:_score_ally(ally, player_pos, allies, enemies)
            if score > best_score then
                best_score = score
                best_target = ally
                best_guid = guid
            end
        end
    end

    -- Publish event if target changed
    if best_guid ~= self._current_target_guid then
        self._event_bus:publish(Events.FOLLOW_TARGET_CHANGED, {
            previous_guid = self._current_target_guid,
            new_guid = best_guid,
            score = best_score,
        })
    end

    -- Cache new target
    self._current_target = best_target
    self._current_target_guid = best_guid
    self._current_score = best_target and best_score or nil
    self._cache_until_ms = now_ms + self._cache_duration_ms

    self:_write_blackboard(blackboard, allies)
end

function AllyTracker:_write_blackboard(blackboard, allies)
    local target = self._current_target
    if not target then
        blackboard:set("bg.follow_target", nil)
        blackboard:set("bg.follow_target_position", nil)
        blackboard:set("bg.follow_target_score", nil)
        blackboard:set("bg.follow_target_guid", nil)
        blackboard:set("bg.ally_cluster_count", 0)
        return
    end

    local ally_pos = safe_call(target, "get_position")
    local jittered = ally_pos and self._humanization:jitter_point(ally_pos, 2.0) or nil

    -- Count allies within 15yd of follow target
    local cluster_count = 0
    if ally_pos then
        for _, other in ipairs(allies or {}) do
            local other_pos = safe_call(other, "get_position")
            if other_pos and distance(ally_pos, other_pos) <= 15 then
                cluster_count = cluster_count + 1
            end
        end
    end

    blackboard:set("bg.follow_target", target)
    blackboard:set("bg.follow_target_position", jittered)
    blackboard:set("bg.follow_target_score", self._current_score)
    blackboard:set("bg.follow_target_guid", self._current_target_guid)
    blackboard:set("bg.ally_cluster_count", cluster_count)
end

function AllyTracker:_scan_allies(player_pos)
    if not player_pos then
        return {}
    end

    -- Try unit_helper first
    if self._unit_helper and type(self._unit_helper.get_ally_list_around) == "function" then
        local ok, list = pcall(self._unit_helper.get_ally_list_around, player_pos, self._scan_radius, true, false, false)
        if ok and type(list) == "table" then
            return list
        end
    end

    -- Fallback to object manager
    if not core or not core.object_manager or type(core.object_manager.get_visible_objects) ~= "function" then
        return {}
    end

    local ok, objects = pcall(core.object_manager.get_visible_objects)
    if not ok or type(objects) ~= "table" then
        return {}
    end

    local player_obj = self._blackboard:get("player.object")
    local allies = {}
    for _, obj in ipairs(objects) do
        if obj ~= player_obj then
            local is_friend = safe_call(obj, "is_friend_with", player_obj)
            if is_friend then
                local pos = safe_call(obj, "get_position")
                if pos and distance(player_pos, pos) <= self._scan_radius then
                    local is_dead = safe_call(obj, "is_dead")
                    if not is_dead then
                        allies[#allies + 1] = obj
                    end
                end
            end
        end
    end
    return allies
end

function AllyTracker:_scan_enemies(player_pos)
    if not player_pos then
        return {}
    end

    if self._unit_helper and type(self._unit_helper.get_enemy_list_around) == "function" then
        local ok, list = pcall(self._unit_helper.get_enemy_list_around, player_pos, 30, true, false, true, false)
        if ok and type(list) == "table" then
            return list
        end
    end

    return {}
end

function AllyTracker:_update_idle_blacklist(allies, now_ms)
    for _, ally in ipairs(allies) do
        local guid = get_guid(ally)
        if guid then
            local pos = safe_call(ally, "get_position")
            if pos then
                local last = self._last_positions[guid]
                if last and distance(pos, last) < 0.5 then
                    -- Position hasn't changed
                    if not self._idle_blacklist[guid] then
                        self._idle_blacklist[guid] = { pos = { x = pos.x, y = pos.y, z = pos.z }, idle_since_ms = now_ms }
                    end
                    -- Already in blacklist, just keep it
                else
                    -- Position changed, remove from blacklist
                    self._idle_blacklist[guid] = nil
                end
                self._last_positions[guid] = { x = num(pos.x), y = num(pos.y), z = num(pos.z) }
            end
        end
    end
end

function AllyTracker:_score_ally(ally, player_pos, all_allies, enemies)
    local score = 0
    local ally_pos = safe_call(ally, "get_position")
    if not ally_pos then
        return score
    end

    -- Healer bonus
    if self._unit_helper and type(self._unit_helper.is_healer) == "function" then
        local ok, is_healer = pcall(self._unit_helper.is_healer, ally)
        if ok and is_healer then
            score = score + 10
        end
    elseif type(ally.get_group_role) == "function" then
        local ok, role = pcall(ally.get_group_role, ally)
        if ok and role == 1 then
            score = score + 10
        end
    end

    -- Friend density
    for _, other in ipairs(all_allies) do
        if other ~= ally then
            local other_pos = safe_call(other, "get_position")
            if other_pos then
                local d = distance(ally_pos, other_pos)
                if d <= 30 then
                    score = score + 2.0 * math.exp(-0.1 * d)
                end
            end
        end
    end

    -- Enemy proximity penalty
    for _, enemy in ipairs(enemies or {}) do
        local enemy_pos = safe_call(enemy, "get_position")
        if enemy_pos then
            local d = distance(ally_pos, enemy_pos)
            if d <= 30 then
                score = score - 0.5 * math.exp(-0.1 * d)
            end
        end
    end

    -- Distance penalty
    score = score - 0.1 * distance(player_pos, ally_pos)

    return score
end

function AllyTracker:_is_blacklisted(guid)
    if not guid then
        return false
    end
    local entry = self._idle_blacklist[guid]
    if not entry then
        return false
    end
    local now_ms = num(self._blackboard:get("system.now_ms", 0))
    return (now_ms - num(entry.idle_since_ms)) >= self._idle_threshold_ms
end

function AllyTracker:_is_valid_target(target, player_pos)
    if not target then
        return false
    end
    local is_dead = safe_call(target, "is_dead")
    if is_dead then
        return false
    end
    if not player_pos then
        return false
    end
    local pos = safe_call(target, "get_position")
    if not pos then
        return false
    end
    return distance(player_pos, pos) <= self._scan_radius
end

return AllyTracker
