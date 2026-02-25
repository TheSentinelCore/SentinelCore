local BT = require("ai/BehaviorTree")
local BTStatus = BT.Status
local Helpers = require("lib/Helpers")
local Events = require("events/Events")
local get_now = require("lib/TimeHelper").get_now
local UnitQueries = require("lib/UnitQueries")
local safe_method = UnitQueries.safe_method

---@private
---@param value any
---@return boolean
local function is_valid_position(value)
    if type(value) ~= "table" then
        return false
    end
    return tonumber(value.x) ~= nil and tonumber(value.y) ~= nil and tonumber(value.z) ~= nil
end

---@private
---@param pos vec3|nil
---@return vec3|nil
local function copy_position(pos)
    if not is_valid_position(pos) then
        return nil
    end
    return {
        x = tonumber(pos.x) or 0,
        y = tonumber(pos.y) or 0,
        z = tonumber(pos.z) or 0,
    }
end

---@class DeathRecoveryService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _nav NavigationAdapter|nil
---@field private _active boolean
---@field private _state string
---@field private _started_at number
---@field private _corpse_position vec3|nil
---@field private _last_distance number|nil
---@field private _last_release_at number
---@field private _last_resurrect_at number
---@field private _last_move_to_at number
---@field private _last_move_to_dest vec3|nil
---@field private _corpse_reachability_checked boolean
local DeathRecoveryService = {}
DeathRecoveryService.__index = DeathRecoveryService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table|nil
---@param navigation NavigationAdapter|nil
---@return DeathRecoveryService
function DeathRecoveryService:new(event_bus, blackboard, cfg, navigation, logger)
    local o = setmetatable({}, DeathRecoveryService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._nav = navigation
    o._active = false
    o._state = "idle"
    o._started_at = 0
    o._corpse_position = nil
    o._last_distance = nil
    o._last_release_at = 0
    o._last_resurrect_at = 0
    o._last_move_to_at = 0
    o._last_move_to_dest = nil
    o._corpse_reachability_checked = false
    -- Ghost run / death-loop detection ring buffer
    o._death_locations = {}        -- { {position={x,y,z}, timestamp=N}, ... }
    o._ghost_run_max_entries = 5
    o._ghost_run_cluster_radius = 60   -- meters
    o._ghost_run_cluster_count = 3     -- deaths required to trigger
    o._ghost_run_window_secs = 600     -- 10-minute sliding window
    o._log = logger or { debug=function()end, info=function()end, warn=function()end, error=function()end }
    o:_write_blackboard_state()
    return o
end

---@private
---@param key string
---@param fallback number
---@return number
function DeathRecoveryService:_cfg_number(key, fallback)
    local value = tonumber(self._cfg and self._cfg[key])
    if value == nil then
        return fallback
    end
    return value
end

---@private
function DeathRecoveryService:_write_blackboard_state()
    self._blackboard:set("death.active", self._active == true)
    self._blackboard:set("death.state", tostring(self._state or "idle"))
    self._blackboard:set("death.started_at", tonumber(self._started_at) or 0)
    if self._corpse_position then
        self._blackboard:set("death.corpse_position", copy_position(self._corpse_position))
    else
        self._blackboard:clear("death.corpse_position")
    end
    if self._last_distance ~= nil then
        self._blackboard:set("death.distance_to_corpse", tonumber(self._last_distance) or 0)
    else
        self._blackboard:clear("death.distance_to_corpse")
    end
end

---@private
---@return game_object|nil
function DeathRecoveryService:_get_player()
    local player = self._blackboard:get("player.object")
    if type(player) ~= "table" then
        return nil
    end
    if player.is_valid then
        local valid = safe_method(player, "is_valid")
        if valid ~= true then
            return nil
        end
    end
    return player
end

---@private
---@param player game_object|nil
---@return vec3|nil
function DeathRecoveryService:_read_player_position(player)
    local pos = self._blackboard:get("player.position")
    if is_valid_position(pos) then
        return copy_position(pos)
    end
    pos = safe_method(player, "get_position")
    return copy_position(pos)
end

---@private
---@return vec3|nil
function DeathRecoveryService:_query_corpse_position()
    local fn = nil
    if core and core.game_ui and type(core.game_ui.get_corpse_position) == "function" then
        fn = core.game_ui.get_corpse_position
    elseif core and type(core.get_corpse_position) == "function" then
        fn = core.get_corpse_position
    end
    if not fn then
        return nil
    end
    local ok, value = pcall(fn)
    if not ok then
        return nil
    end
    return copy_position(value)
end

---@private
---@param player game_object|nil
---@param dead boolean
---@param ghost boolean
function DeathRecoveryService:_refresh_corpse_position(player, dead, ghost)
    local corpse_pos = self:_query_corpse_position()
    if corpse_pos then
        self._corpse_position = corpse_pos
        return
    end

    if dead == true and ghost ~= true and self._corpse_position == nil then
        self._corpse_position = self:_read_player_position(player)
    end

    -- Fallback: use sensor-cached death position from blackboard.
    -- Covers the case where the "dead but not ghost" window was missed
    -- (e.g. ghost on first detection frame, or bot was paused during death).
    if self._corpse_position == nil then
        local cached = self._blackboard:get("player.death_position")
        if is_valid_position(cached) then
            self._corpse_position = copy_position(cached)
        end
    end
end

---@private
---@param now number
function DeathRecoveryService:_record_death(now)
    local pos = self._blackboard:get("player.death_position") or self._blackboard:get("player.position")
    if not is_valid_position(pos) then return end
    -- Add to ring buffer
    table.insert(self._death_locations, {
        position = { x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0, z = tonumber(pos.z) or 0 },
        timestamp = now,
    })
    -- Keep only last N entries
    while #self._death_locations > self._ghost_run_max_entries do
        table.remove(self._death_locations, 1)
    end
    -- Check for ghost run pattern
    self:_check_ghost_run(now)
end

---@private
---@param now number
function DeathRecoveryService:_check_ghost_run(now)
    local window_cutoff = now - self._ghost_run_window_secs
    -- Collect deaths within the sliding window
    local recent = {}
    for _, entry in ipairs(self._death_locations) do
        if entry.timestamp >= window_cutoff then
            recent[#recent + 1] = entry
        end
    end
    if #recent < self._ghost_run_cluster_count then return end
    -- Check whether any subset of cluster_count deaths are within the radius
    for i = 1, #recent do
        local cluster = 1
        local a = recent[i].position
        for j = i + 1, #recent do
            local b = recent[j].position
            local dx, dy = a.x - b.x, a.y - b.y
            if math.sqrt(dx * dx + dy * dy) <= self._ghost_run_cluster_radius then
                cluster = cluster + 1
            end
        end
        if cluster >= self._ghost_run_cluster_count then
            self._log:error(
                "Ghost run detected: %d deaths within %.0fm in %.0f minutes — stopping bot",
                cluster, self._ghost_run_cluster_radius, self._ghost_run_window_secs / 60
            )
            if self._event_bus then
                self._event_bus:emit("CRITICAL_ERROR", {
                    error_code = "GHOST_RUN_DETECTED",
                    message = string.format(
                        "%d deaths in same location within %d minutes",
                        cluster, math.floor(self._ghost_run_window_secs / 60)
                    ),
                })
            end
            -- Clear ring buffer to prevent repeated triggers
            self._death_locations = {}
            return
        end
    end
end

---@private
function DeathRecoveryService:_stop_navigation()
    if self._nav and type(self._nav.stop) == "function" then
        pcall(self._nav.stop, self._nav)
    end
end

---@private
---@param now number
---@param state string
function DeathRecoveryService:_activate(now, state)
    if self._active == true then
        return
    end
    self._active = true
    self._state = state
    self._started_at = now
    self._last_release_at = 0
    self._last_resurrect_at = 0
    self._last_move_to_at = 0
    self._last_move_to_dest = nil
    self._last_distance = nil
    self._corpse_reachability_checked = false
    -- Record this death for ghost run / death-loop detection
    self:_record_death(now)
    self:_stop_navigation()
    self._log:info("death recovery started: state=%s", tostring(state))
    self._event_bus:emit(Events.DEATH_RECOVERY_STARTED, {
        state = state,
    })
end

---@private
---@param now number
function DeathRecoveryService:_deactivate(now)
    if self._active ~= true then
        self._state = "idle"
        self._started_at = 0
        self._corpse_position = nil
        self._last_distance = nil
        self:_write_blackboard_state()
        return
    end

    self:_stop_navigation()
    local duration = math.max(0, now - self._started_at)
    self._log:info("resurrected after %.1fs", duration)
    self._event_bus:emit(Events.DEATH_RESURRECTED, {
        duration = duration,
    })

    self._active = false
    self._state = "idle"
    self._started_at = 0
    self._corpse_position = nil
    self._last_distance = nil
    self._last_release_at = 0
    self._last_resurrect_at = 0
    self._last_move_to_at = 0
    self._last_move_to_dest = nil
    self._corpse_reachability_checked = false
    self._blackboard:set("death.skip_corpse_run", false)
    self:_write_blackboard_state()
end

---@private
---@param now number
function DeathRecoveryService:_attempt_release_spirit(now)
    if not core or not core.input or type(core.input.release_spirit) ~= "function" then
        return
    end

    local release_delay = math.max(0, self:_cfg_number("death_release_delay_secs", 2.5))
    local release_retry = math.max(0.2, self:_cfg_number("death_release_retry_secs", 2.0))

    if (now - self._started_at) < release_delay then
        return
    end
    if self._last_release_at > 0 and (now - self._last_release_at) < release_retry then
        return
    end

    self._last_release_at = now
    local ok, result = pcall(core.input.release_spirit)
    if ok and result ~= false then
        self._log:debug("spirit released")
        self._event_bus:emit(Events.DEATH_SPIRIT_RELEASED, {})
    end
end

---@private
---@param destination vec3
---@param now number
function DeathRecoveryService:_issue_move_to(destination, now)
    if not self._nav or type(self._nav.move_to) ~= "function" then
        return
    end

    local move_cooldown = math.max(0.1, self:_cfg_number("death_move_to_cooldown", 0.9))
    local reissue_distance = math.max(0.1, self:_cfg_number("death_move_reissue_distance", 1.0))

    if self._last_move_to_at > 0 and (now - self._last_move_to_at) < move_cooldown then
        return
    end

    if self._last_move_to_dest ~= nil and Helpers.distance_3d(self._last_move_to_dest, destination) < reissue_distance then
        return
    end

    self._last_move_to_at = now
    self._last_move_to_dest = copy_position(destination)
    pcall(self._nav.move_to, self._nav, destination)

    self._event_bus:emit(Events.DEATH_CORPSE_RUN_UPDATE, {
        state = self._state,
        distance = tonumber(self._last_distance) or 0,
        destination = copy_position(destination),
    })
end

---@private
---@param now number
function DeathRecoveryService:_attempt_resurrect(now)
    if not core or not core.input or type(core.input.resurrect_corpse) ~= "function" then
        return
    end

    local retry = math.max(0.25, self:_cfg_number("death_resurrect_retry_secs", 0.75))
    if self._last_resurrect_at > 0 and (now - self._last_resurrect_at) < retry then
        return
    end

    local resurrect_delay = 0
    local delay_fn = nil
    if core and core.game_ui and type(core.game_ui.get_resurrect_corpse_delay) == "function" then
        delay_fn = core.game_ui.get_resurrect_corpse_delay
    elseif core and type(core.get_resurrect_corpse_delay) == "function" then
        delay_fn = core.get_resurrect_corpse_delay
    end
    if delay_fn then
        local ok_delay, value = pcall(delay_fn)
        if ok_delay then
            resurrect_delay = tonumber(value) or 0
        end
    end
    if resurrect_delay > 0.05 then
        return
    end

    self._last_resurrect_at = now
    local ok, result = pcall(core.input.resurrect_corpse)
    if ok and result ~= false then
        self._log:debug("resurrect attempt")
        self._event_bus:emit(Events.DEATH_RESURRECT_ATTEMPT, {})
    end
end

---@private
---@param now number
---@param player game_object|nil
function DeathRecoveryService:_run_to_corpse(now, player)
    local player_pos = self:_read_player_position(player)
    local corpse_pos = copy_position(self._corpse_position)
    if not player_pos or not corpse_pos then
        self._last_distance = nil
        return
    end

    -- Perform a one-shot reachability check when first entering corpse run.
    -- Only skip corpse run when we get a confirmed path cost that exceeds
    -- the max threshold. A failed estimate (cost=nil) does NOT mean
    -- unreachable — long-distance paths may fail to compute in one shot
    -- but the nav system can still navigate incrementally.
    if not self._corpse_reachability_checked then
        self._corpse_reachability_checked = true
        if self._nav and type(self._nav.estimate_path_cost) == "function" then
            local max_cost = self:_cfg_number("corpse_max_path_cost", 800)
            self._nav:estimate_path_cost(player_pos, corpse_pos, function(ok, cost)
                if ok and cost ~= nil and cost > max_cost then
                    self._log:warn(
                        "Corpse unreachable (cost=%.0f > max=%d), forcing spirit rez",
                        cost, max_cost
                    )
                    self._blackboard:set("death.skip_corpse_run", true)
                elseif not ok then
                    self._log:debug(
                        "Corpse path cost unavailable, proceeding with corpse run anyway"
                    )
                end
            end)
        end
    end

    -- If reachability check determined corpse is unreachable, skip the run.
    if self._blackboard:get("death.skip_corpse_run", false) == true then
        self:_stop_navigation()
        self:_attempt_resurrect(now)
        return
    end

    self._last_distance = Helpers.distance_3d(player_pos, corpse_pos)
    local resurrect_distance = math.max(1.0, self:_cfg_number("death_resurrect_distance", 10.0))

    if self._last_distance > resurrect_distance then
        self._log:debug("corpse run: dist=%.1f", self._last_distance)
        self:_issue_move_to(corpse_pos, now)
        return
    end

    self:_stop_navigation()
    self:_attempt_resurrect(now)
end

---@return boolean
function DeathRecoveryService:is_active()
    return self._active == true
end

---@return string
function DeathRecoveryService:get_state()
    return self._state
end

---@param now? number
---@return boolean
---@return string|nil
function DeathRecoveryService:update(now)
    now = tonumber(now) or (get_now())

    local player = self:_get_player()

    -- Read death state from blackboard (Sensors updates these even when
    -- is_valid() fails, so they're authoritative for dead/ghost detection).
    local dead = self._blackboard:get("player.is_dead", false) == true
    local ghost = self._blackboard:get("player.is_ghost", false) == true

    -- If we have a valid player object, prefer direct method calls
    if player then
        dead = safe_method(player, "is_dead") == true
        ghost = safe_method(player, "is_ghost") == true
    end

    if not dead and not ghost then
        self:_deactivate(now)
        return true, nil
    end

    local state = ghost and "corpse_run" or "dead"
    self:_activate(now, state)
    self._state = state
    self:_refresh_corpse_position(player, dead, ghost)

    if ghost then
        self:_run_to_corpse(now, player)
    else
        self:_stop_navigation()
        self:_attempt_release_spirit(now)
    end

    self:_write_blackboard_state()
    return true, nil
end

function DeathRecoveryService:reset()
    self._active = false
    self._state = "idle"
    self._started_at = 0
    self._corpse_position = nil
    self._last_distance = nil
    self._last_release_at = 0
    self._last_resurrect_at = 0
    self._last_move_to_at = 0
    self._last_move_to_dest = nil
    self._corpse_reachability_checked = false
    self:_write_blackboard_state()
end

--- Build BT node for death recovery phase (used by GrindService).
--- Delegates all logic to the service's update() method.
---@return table BT node
function DeathRecoveryService:build()
    local bb = self._blackboard

    return BT.ReactiveSequence:new("death_recovery", {
        -- Gate: must be dead or ghost (re-evaluated every tick)
        BT.Condition:new("is_dead_or_ghost", function()
            local is_dead = bb:get("player.is_dead", false)
            local is_ghost = bb:get("player.is_ghost", false)
            return is_dead or is_ghost
        end),

        -- Tick the service each frame
        BT.Action:new("death_recovery_tick", function()
            self:update()

            -- Stay RUNNING while active (dead or ghost)
            if self:is_active() then
                return BTStatus.RUNNING
            end

            -- Service deactivated — player is alive
            return BTStatus.SUCCESS
        end),
    })
end

return DeathRecoveryService
