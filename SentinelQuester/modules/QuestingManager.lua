local simple_movement = require("common/utility/simple_movement")
local ObjectiveScanner = require("modules/ObjectiveScanner")

---@class QuestingManager
---@field private _config table
---@field private _scanner ObjectiveScanner
---@field private _enabled boolean
---@field private _state string
---@field private _current_target table|nil
---@field private _target_acquired_at number
---@field private _next_interact_time number
---@field private _last_move_time number
---@field private _last_progress_time number
---@field private _best_distance number|nil
---@field private _blacklist table<number|string, number>
---@field private _last_idle_log_time number
local QuestingManager = {}
QuestingManager.__index = QuestingManager

local STATE_IDLE = "idle"
local STATE_MOVING = "moving"
local STATE_INTERACTING = "interacting"
local STATE_WAITING = "waiting"

local DEFAULT_CONFIG = {
    scan_interval = 0.30,
    scan_radius = 70.0,
    interact_range = 5.0,
    interact_retry_delay = 1.2,
    objective_timeout = 25.0,
    move_refresh_interval = 1.0,
    progress_timeout = 6.0,
    progress_epsilon = 0.5,
    blacklist_seconds = 20.0,
    require_questie = true,
    fallback_include_hostiles = true,
    debug = false,
}

local function merge_config(target, source)
    if not source then
        return
    end

    for k, v in pairs(source) do
        target[k] = v
    end
end

local function safe_method(obj, method_name, ...)
    if not obj then
        return nil
    end

    local fn = obj[method_name]
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil
    end

    return result
end

local function safe_bool(obj, method_name, ...)
    return safe_method(obj, method_name, ...) == true
end

local function dist3(a, b)
    if not a or not b then
        return math.huge
    end

    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@param config? table
---@return QuestingManager
function QuestingManager:new(config)
    local o = setmetatable({}, QuestingManager)

    o._config = {}
    merge_config(o._config, DEFAULT_CONFIG)
    merge_config(o._config, config)

    o._scanner = ObjectiveScanner:new({
        scan_interval = o._config.scan_interval,
        scan_radius = o._config.scan_radius,
        require_questie = o._config.require_questie,
        fallback_include_hostiles = o._config.fallback_include_hostiles,
    })

    o._enabled = false
    o._state = STATE_IDLE
    o._current_target = nil
    o._target_acquired_at = 0
    o._next_interact_time = 0
    o._last_move_time = 0
    o._last_progress_time = 0
    o._best_distance = nil
    o._blacklist = {}
    o._last_idle_log_time = 0

    simple_movement:set_smoothing_enabled(false)
    simple_movement:set_use_look_at(true)
    simple_movement:set_threshold(math.max(1.5, o._config.interact_range))
    simple_movement:set_final_threshold(math.max(1.0, o._config.interact_range * 0.5))

    return o
end

function QuestingManager:_set_state(new_state)
    if self._state == new_state then
        return
    end

    if self._config.debug then
        core.log("[QuestingBuddy] State: " .. self._state .. " -> " .. new_state)
    end
    self._state = new_state
end

function QuestingManager:_clear_target()
    self._current_target = nil
    self._target_acquired_at = 0
    self._best_distance = nil
    self._last_progress_time = 0
end

---@param target table|nil
---@return boolean
function QuestingManager:_is_target_valid(target)
    if not target or not target.object then
        return false
    end

    if not safe_bool(target.object, "is_valid") then
        return false
    end

    local guid = target.guid
    local until_time = guid and self._blacklist[guid]
    if until_time and until_time > core.time() then
        return false
    end

    return true
end

---@param guid number|string|nil
---@param reason string
function QuestingManager:_blacklist_target(guid, reason)
    if not guid then
        return
    end

    self._blacklist[guid] = core.time() + self._config.blacklist_seconds
    if self._config.debug then
        core.log("[QuestingBuddy] Blacklisted target " .. tostring(guid) .. " (" .. reason .. ")")
    end
end

function QuestingManager:_clean_blacklist()
    local now = core.time()
    for guid, expires_at in pairs(self._blacklist) do
        if expires_at <= now then
            self._blacklist[guid] = nil
        end
    end
end

---@param player game_object
function QuestingManager:_acquire_target(player)
    local best = self._scanner:get_best_objective(player, self._blacklist)
    if not best then
        self:_clear_target()
        return
    end

    self._current_target = best
    self._target_acquired_at = core.time()
    self._best_distance = best.distance
    self._last_progress_time = core.time()

    if self._config.debug then
        core.log(string.format(
            "[QuestingBuddy] New objective: %s (dist=%.1f, quest_obj=%s, quest_npc=%s, named_npc=%s, flagged_npc=%s)",
            best.name,
            best.distance or -1,
            tostring(best.is_quest_object == true),
            tostring(best.is_quest_npc == true),
            tostring(best.is_named_quest_npc == true),
            tostring(best.is_flagged_quest_npc == true)
        ))
    end
end

---@param player game_object
---@param target game_object
---@param target_pos vec3
---@return string
function QuestingManager:_interact(player, target, target_pos)
    core.input.look_at(target_pos)

    if safe_bool(target, "can_be_looted") then
        core.input.loot_object(target)
        return "loot"
    end

    if safe_bool(target, "can_be_used") then
        core.input.use_object(target)
        return "use"
    end

    local hostile = safe_method(target, "is_enemy_with", player) == true
        or safe_method(player, "is_enemy_with", target) == true
        or safe_method(player, "can_attack", target) == true

    if hostile then
        core.input.set_target(target)
        core.input.interact_with_object(target)
        return "engage"
    end

    core.input.interact_with_object(target)
    return "interact"
end

---@param overrides table
function QuestingManager:update_config(overrides)
    merge_config(self._config, overrides)

    self._scanner:update_config({
        scan_interval = self._config.scan_interval,
        scan_radius = self._config.scan_radius,
        require_questie = self._config.require_questie,
        fallback_include_hostiles = self._config.fallback_include_hostiles,
    })

    simple_movement:set_threshold(math.max(1.5, self._config.interact_range))
    simple_movement:set_final_threshold(math.max(1.0, self._config.interact_range * 0.5))
end

---@param enabled boolean
function QuestingManager:set_enabled(enabled)
    if self._enabled == enabled then
        return
    end

    self._enabled = enabled
    if not enabled then
        simple_movement:clear_navigation()
        self:_clear_target()
        self:_set_state(STATE_IDLE)
        return
    end

    self:_set_state(STATE_WAITING)
end

---@return boolean
function QuestingManager:is_enabled()
    return self._enabled
end

---@return string
function QuestingManager:get_state()
    return self._state
end

---@return table
function QuestingManager:get_status()
    local scanner_status = self._scanner:get_status()

    return {
        enabled = self._enabled,
        state = self._state,
        has_target = self._current_target ~= nil,
        target_name = self._current_target and self._current_target.name or nil,
        target_distance = self._current_target and self._current_target.distance or nil,
        candidate_count = scanner_status.candidate_count,
        questie_status = scanner_status.questie_status,
        require_questie = scanner_status.require_questie,
    }
end

function QuestingManager:update()
    if not self._enabled then
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not safe_bool(player, "is_valid") then
        return
    end

    if safe_bool(player, "is_dead") or safe_bool(player, "is_ghost") then
        simple_movement:stop()
        self:_set_state(STATE_WAITING)
        return
    end

    self:_clean_blacklist()

    local now = core.time()
    if not self:_is_target_valid(self._current_target) then
        self:_clear_target()
    end

    if not self._current_target then
        self:_acquire_target(player)
        if not self._current_target then
            self:_set_state(STATE_IDLE)
            if self._config.debug and (now - self._last_idle_log_time) > 5.0 then
                local st = self._scanner:get_status()
                core.log("[QuestingBuddy] No objective. Questie status: "
                    .. tostring(st.questie_status)
                    .. ", fallback_used=" .. tostring(st.fallback_used))
                self._last_idle_log_time = now
            end
            return
        end
    end

    local target = self._current_target
    if (now - self._target_acquired_at) > self._config.objective_timeout then
        self:_blacklist_target(target.guid, "objective_timeout")
        self:_clear_target()
        simple_movement:stop()
        self:_set_state(STATE_WAITING)
        return
    end

    local target_obj = target.object
    local target_pos = safe_method(target_obj, "get_position")
    local player_pos = safe_method(player, "get_position")
    if not target_pos or not player_pos then
        self:_blacklist_target(target.guid, "missing_position")
        self:_clear_target()
        simple_movement:stop()
        self:_set_state(STATE_WAITING)
        return
    end

    local distance = dist3(player_pos, target_pos)
    target.distance = distance

    if not self._best_distance or (distance + self._config.progress_epsilon) < self._best_distance then
        self._best_distance = distance
        self._last_progress_time = now
    end

    if distance > self._config.interact_range then
        if (now - self._last_progress_time) > self._config.progress_timeout then
            self:_blacklist_target(target.guid, "no_progress")
            self:_clear_target()
            simple_movement:clear_navigation()
            self:_set_state(STATE_WAITING)
            return
        end

        local refresh_interval = self._config.move_refresh_interval
        if (not simple_movement:is_moving()) or ((now - self._last_move_time) > refresh_interval) then
            simple_movement:move_to_position(target_pos)
            self._last_move_time = now
        end

        simple_movement:process()
        self:_set_state(STATE_MOVING)
        return
    end

    if simple_movement:is_moving() then
        simple_movement:stop()
    end

    self:_set_state(STATE_INTERACTING)
    if now < self._next_interact_time then
        return
    end

    local action = self:_interact(player, target_obj, target_pos)
    self._next_interact_time = now + self._config.interact_retry_delay

    if self._config.debug then
        core.log(string.format("[QuestingBuddy] %s on %s", action, target.name or "<unnamed>"))
    end
end

return QuestingManager
