local Detector = require("modules/battleground/bg_detector")
local ContextBuilder = require("modules/battleground/context_builder")
local EngagementPolicy = require("modules/battleground/engagement_policy")
local NavController = require("modules/battleground/nav_controller")
local QueueManager = require("modules/battleground/queue_manager")
local LeaveManager = require("modules/battleground/leave_manager")
local MountManager = require("modules/battleground/mount_manager")
local GhostManager = require("modules/battleground/ghost_manager")
local ObjectiveApproach = require("modules/battleground/objective_approach")
local ObjectiveTracker = require("modules/battleground/objective_tracker")
local StrategyEngine = require("modules/battleground/strategy_engine")
local Events = require("modules/battleground/events")
local AllyTracker = require("modules/battleground/ally_tracker")
local Humanization = require("shared/humanization")

local ObjectiveCatalogs = {
    AV = require("modules/battleground/data/objectives/av"),
    WSG = require("modules/battleground/data/objectives/wsg"),
    AB = require("modules/battleground/data/objectives/ab"),
    EOTS = require("modules/battleground/data/objectives/eots"),
}

local SentinelBG = {}
SentinelBG.__index = SentinelBG

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
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function shallow_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, entry in pairs(value) do
        out[key] = entry
    end
    return out
end

local function top_candidates(candidates)
    local out = {}
    for index = 1, math.min(3, #candidates) do
        local candidate = candidates[index]
        out[#out + 1] = {
            id = candidate.id,
            score = candidate.score,
            owner = candidate.owner,
            distance = candidate.distance,
            rejected = candidate.rejected == true,
            rejection_reason = candidate.rejection_reason,
            allies_near = candidate.allies_near,
            enemies_near = candidate.enemies_near,
        }
    end
    return out
end

local function new_eots_prep_state()
    return {
        armed = false,
        active_state_seen = false,
        barrier_seen_while_armed = false,
        released = false,
        release_reason = nil,
    }
end

function SentinelBG:new(event_bus, blackboard, nav_adapter)
    local o = setmetatable({}, SentinelBG)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav_adapter = nav_adapter
    o._detector = Detector:new()
    o._context_builder = ContextBuilder:new(blackboard)
    o._engagement_policy = EngagementPolicy:new()
    o._nav = NavController:new(event_bus, blackboard, nav_adapter)
    o._queue = QueueManager:new(event_bus, blackboard)
    o._leave = LeaveManager:new(event_bus, blackboard)
    o._mount = MountManager:new(event_bus, blackboard, nav_adapter)
    o._ghost = GhostManager:new(event_bus, blackboard, nav_adapter)
    o._objective_tracker = ObjectiveTracker:new(blackboard)
    o._strategy_engine = StrategyEngine:new(blackboard)
    o._subscriptions = {}
    o._active = false
    o._bg_key = nil
    o._bg_data = nil
    o._side = nil
    o._definition = nil
    o._combat_paused = false
    o._last_detected_key = nil
    o._last_detected_at_ms = 0
    o._detect_sticky_ms = 1000
    o._last_handoff_request_at_ms = 0
    o._handoff_request_cooldown_ms = 300
    o._activation_wait_reason = nil
    o._last_state = nil
    o._last_selected_objective_id = nil
    o._last_selected_score = nil
    o._last_nav_authority = nil
    o._last_failure_marker = nil
    o._route_failure_counts = {}
    o._selected_candidate = nil
    o._selected_objective = nil
    o._objective_approach_runtime = ObjectiveApproach.new_runtime({})
    o._eots_prep = new_eots_prep_state()
    o._bootstrap = {
        phase = "idle",
        route_id = nil,
        ready = false,
        failed_attempts = 0,
        reason = nil,
    }
    o._humanization = Humanization.new()
    o._ally_tracker = AllyTracker:new(event_bus, blackboard, o._humanization)
    o._last_ally_nav_pos = nil
    return o
end

function SentinelBG:initialize()
    self._blackboard:set("module.bg.enabled", true)
    self._blackboard:set("module.bg.auto_engage", true)
    self._blackboard:set("module.bg.auto_queue", false)
    self._blackboard:set("module.bg.queue_selection", "AV")
    self._blackboard:set("module.bg.queue_join_interval_s", 12)
    self._blackboard:set("module.bg.queue_accept_delay_min_s", 0.6)
    self._blackboard:set("module.bg.queue_accept_delay_max_s", 1.8)
    self._blackboard:set("module.bg.queue_accept_mode", "strict_pvp")
    self._blackboard:set("module.bg.queue_dependencies_policy", "accept_anyway")
    self._blackboard:set("module.bg.queue_accept_retry_interval_s", 0.35)
    self._blackboard:set("module.bg.queue_accept_max_attempts", 20)
    self._blackboard:set("module.bg.queue_accept_confirm_timeout_s", 2.5)
    self._blackboard:set("module.bg.queue_join_confirm_timeout_s", 5.0)
    self._blackboard:set("module.bg.queue_active_without_bg_timeout_s", 10.0)
    self._blackboard:set("module.bg.post_game_auto_leave", true)
    self._blackboard:set("module.bg.post_game_state5_streak_required", 1)
    self._blackboard:set("module.bg.post_game_leave_initial_delay_s", 2.0)
    self._blackboard:set("module.bg.post_game_leave_retry_interval_s", 1.0)
    self._blackboard:set("module.bg.post_game_leave_max_attempts", 25)
    self._blackboard:set("module.bg.low_health_threshold", 0.35)
    self._blackboard:set("module.bg.engage_outnumber_grace", 1)
    self._blackboard:set("module.bg.retreat_outnumber_delta", 2)
    self._blackboard:set("module.bg.auto_mount", true)
    self._blackboard:set("module.bg.preferred_mount_id", 184865)
    self._blackboard:set("module.bg.mount_distance_threshold", 45)
    self._blackboard:set("module.bg.mount_require_outdoors", true)
    self._blackboard:set("module.bg.mount_prefer_epic", true)
    self._blackboard:set("module.bg.mount_micro_stop_for_cast_s", 0.45)
    self._blackboard:set("module.bg.mount_settle_before_cast_s", 0.25)
    self._blackboard:set("module.bg.mount_no_cast_grace_s", 3.0)
    self._blackboard:set("module.bg.pregame_mount_early", true)
    self._blackboard:set("module.bg.dismount_on_player_threat", true)
    self._blackboard:set("module.bg.player_threat_scan_radius", 35)
    self._blackboard:set("module.bg.capture_radius", 12)
    self._blackboard:set("module.bg.capture_min_hold_s", 1.1)
    self._blackboard:set("module.bg.objective_approach_mode", "adaptive_ring")
    self._blackboard:set("module.bg.objective_approach_standoff_yd", 8)
    self._blackboard:set("module.bg.objective_ring_radius_gy", 7)
    self._blackboard:set("module.bg.objective_ring_radius_tower", 9)
    self._blackboard:set("module.bg.objective_ring_radius_node", 8)
    self._blackboard:set("module.bg.objective_ring_radius_flag", 6)
    self._blackboard:set("module.bg.objective_ring_variant_count", 6)
    self._blackboard:set("module.bg.ghost_mode", "release_wait")
    self._blackboard:set("module.bg.objective_skip_if_satisfied_radius", 18)
    self._blackboard:set("module.bg.objective_skip_threat_enemy_count", 0)

    self._queue:initialize()
    self._leave:initialize()
    self._mount:initialize()
    self._ghost:initialize()

    self:_subscribe("combat:engaged", function(_payload)
        if self._active then
            self._combat_paused = true
            self._nav:stop("combat_handoff", "bg")
            self._blackboard:set("bg.nav_authority", "combat_handoff")
        end
    end)
    self:_subscribe("combat:disengaged", function(payload)
        if self._active then
            self._combat_paused = false
            self._last_handoff_request_at_ms = 0
            self._event_bus:publish(Events.COMBAT_HANDOFF_RECLAIMED, {
                bg_key = self._bg_key,
                reason = payload and payload.reason or "combat_disengaged",
                objective_id = self._selected_objective and self._selected_objective.id or nil,
            })
        end
    end)
    self:_subscribe("nav:failed", function(payload)
        if self._active and self._blackboard:get("nav.owner") == "bg" then
            self._blackboard:set("bg.route_failure_reason", payload and payload.reason or "nav_failed")
        end
    end)
    self:_subscribe("nav:arrived", function(payload)
        if self._active then
            self._blackboard:set("bg.route_failure_reason", nil)
            local objective_id = payload and payload.objective_id or nil
            if objective_id then
                self._event_bus:publish(Events.OBJECTIVE_REACHED, {
                    bg_key = self._bg_key,
                    objective_id = objective_id,
                    target = self._blackboard:get("bg.objective_nav_target"),
                })
            end
        end
    end)
end

function SentinelBG:_subscribe(event_name, handler)
    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe(event_name, handler)
end

function SentinelBG:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
    self._queue:reset("shutdown")
    self._leave:reset("shutdown")
    self._mount:reset("shutdown")
    self._ghost:reset("shutdown")
    self:_deactivate("shutdown")
end

function SentinelBG:_objective_catalog()
    return ObjectiveCatalogs[self._bg_key]
end

function SentinelBG:_strategy_settings()
    return {
        objective_skip_if_satisfied_radius = num(self._blackboard:get("module.bg.objective_skip_if_satisfied_radius", 18)),
        objective_skip_threat_enemy_count = num(self._blackboard:get("module.bg.objective_skip_threat_enemy_count", 0)),
    }
end

function SentinelBG:_movement_settings()
    return {
        capture_radius = num(self._blackboard:get("module.bg.capture_radius", 12)),
        capture_min_hold_s = tonumber(self._blackboard:get("module.bg.capture_min_hold_s", 1.1)) or 1.1,
        objective_approach_mode = self._blackboard:get("module.bg.objective_approach_mode", "adaptive_ring"),
        objective_approach_standoff_yd = tonumber(self._blackboard:get("module.bg.objective_approach_standoff_yd", 8)) or 8,
        objective_ring_radius_gy = tonumber(self._blackboard:get("module.bg.objective_ring_radius_gy", 7)) or 7,
        objective_ring_radius_tower = tonumber(self._blackboard:get("module.bg.objective_ring_radius_tower", 9)) or 9,
        objective_ring_radius_node = tonumber(self._blackboard:get("module.bg.objective_ring_radius_node", 8)) or 8,
        objective_ring_radius_flag = tonumber(self._blackboard:get("module.bg.objective_ring_radius_flag", 6)) or 6,
        objective_ring_variant_count = tonumber(self._blackboard:get("module.bg.objective_ring_variant_count", 6)) or 6,
    }
end

function SentinelBG:_objective_handoff_radius()
    return math.max(12, num(self._blackboard:get("module.bg.objective_skip_if_satisfied_radius", 18)))
end

function SentinelBG:_update_capture_hold(objective_data, player_pos)
    local now_ms = num(self._blackboard:get("system.now_ms", 0))
    local hold_until_ms = num(self._blackboard:get("bg.capture_hold_until_ms", 0))
    local capture_radius = num(self._blackboard:get("module.bg.capture_radius", 12))
    local hold_ms = math.floor((tonumber(self._blackboard:get("module.bg.capture_min_hold_s", 1.1)) or 1.1) * 1000)

    if ObjectiveApproach.is_capture_objective(objective_data)
        and type(player_pos) == "table"
        and distance(player_pos, objective_data) <= capture_radius then
        hold_until_ms = math.max(hold_until_ms, now_ms + hold_ms)
    elseif hold_until_ms <= now_ms then
        hold_until_ms = 0
    end

    self._blackboard:set("bg.capture_hold_until_ms", hold_until_ms)
end

function SentinelBG:_clear_retreat_state()
    self._blackboard:set("bg.retreat_requested", false)
    self._blackboard:set("bg.retreat_reason", nil)
    self._blackboard:set("bg.retreat_set_at_ms", 0)
end

function SentinelBG:_reset_eots_prep_state()
    self._eots_prep = new_eots_prep_state()
end

function SentinelBG:_prep_gate(runtime_signals, now_ms)
    local in_prep = self._blackboard:get("bg.sensor.in_prep", false) == true
    if self._bg_key ~= "EOTS" then
        return in_prep, in_prep and "battlefield_prep_fallback" or "none"
    end

    local supported = type(runtime_signals) == "table" and runtime_signals.visible_objects_supported == true
    local barrier_seen = type(runtime_signals) == "table" and runtime_signals.spawn_barrier_seen == true
    local barrier_distance = num(type(runtime_signals) == "table" and runtime_signals.spawn_barrier_distance or 99999)
    local battlefield_state = num(self._blackboard:get("bg.sensor.battlefield_state", 0))
    local grace_until_ms = num(self._blackboard:get("bg.prep_release_grace_until_ms", 0))
    local prep = self._eots_prep or new_eots_prep_state()
    local barrier_block_radius = 28
    local barrier_blocking = barrier_seen and barrier_distance <= barrier_block_radius

    if supported then
        if prep.armed and barrier_seen then
            prep.barrier_seen_while_armed = true
        end
        if battlefield_state == 3 then
            prep.active_state_seen = true
        end

        if prep.active_state_seen and not barrier_blocking then
            if not prep.released then
                prep.released = true
                prep.release_reason = "barrier_cleared_after_active"
                grace_until_ms = math.max(grace_until_ms, now_ms + 350)
                self._blackboard:set("bg.prep_release_grace_until_ms", grace_until_ms)
            end
            prep.armed = false
        end
        self._eots_prep = prep
        self._blackboard:set("bg.prep_gate_armed", prep.armed == true)
        self._blackboard:set("bg.prep_gate_released", prep.released == true)
        self._blackboard:set("bg.prep_release_reason", prep.release_reason)

        if grace_until_ms > now_ms then
            return true, "release_grace"
        end
        if prep.active_state_seen and not barrier_blocking then
            return false, "none"
        end
        if (prep.armed and prep.barrier_seen_while_armed) or barrier_blocking then
            return true, "eots_spawn_barrier_seen"
        end
        if in_prep then
            return true, "battlefield_prep_fallback"
        end
        return false, "none"
    end

    prep.armed = false
    self._eots_prep = prep
    self._blackboard:set("bg.prep_gate_armed", false)
    self._blackboard:set("bg.prep_gate_released", prep.released == true)
    self._blackboard:set("bg.prep_release_reason", prep.release_reason)
    if in_prep then
        return true, "battlefield_prep_fallback"
    end
    return false, "none"
end

function SentinelBG:_clear_battleground_diagnostics()
    self._context_builder:refresh({ active = false })
    self._blackboard:set("bg.key", nil)
    self._blackboard:set("bg.side", nil)
    self._blackboard:set("bg.detected_key", nil)
    self._blackboard:set("bg.detect_reason", nil)
    self._blackboard:set("bg.objective_type", nil)
    self._blackboard:set("bg.objective_center", nil)
    self._blackboard:set("bg.objective_nav_target", nil)
    self._blackboard:set("bg.nav_map_id", nil)
    self._blackboard:set("bg.route_failure_reason", nil)
    self._blackboard:set("bg.activation_wait_reason", nil)
    self._blackboard:set("bg.capture_hold_until_ms", 0)
    self._blackboard:set("bg.nav_result", nil)
    self:_clear_retreat_state()
    self._blackboard:set("bg.prep_gate_reason", nil)
    self._blackboard:set("bg.prep_release_grace_until_ms", 0)
    self._blackboard:set("bg.prep_gate_armed", false)
    self._blackboard:set("bg.prep_gate_released", false)
    self._blackboard:set("bg.prep_release_reason", nil)
    self._blackboard:set("bg.objective_anchor", nil)
    self._blackboard:set("bg.objective_approach_source", nil)
    self._blackboard:set("bg.objective_approach.stage", nil)
    self._blackboard:set("bg.selection_failure_reason", nil)
    self._blackboard:set("bg.sensor.spawn_barrier_seen", false)
    self._blackboard:set("bg.sensor.spawn_barrier_up", false)
    self._blackboard:set("bg.sensor.spawn_barrier_entry", nil)
    self._blackboard:set("bg.sensor.spawn_barrier_name", nil)
    self._blackboard:set("bg.sensor.spawn_barrier_distance", nil)
    self._blackboard:set("bg.sensor.spawn_barrier_source", nil)
end

function SentinelBG:_clear_bg_owned_nav_if_inactive(reason)
    if self._blackboard:get("nav.owner") == "bg" then
        self._nav:stop(reason or "bg_inactive", "bg")
    end
end

function SentinelBG:_activate(bg_key, bg_data)
    local player_pos = self._blackboard:get("player.position")
    self._bg_key = bg_key
    self._bg_data = bg_data
    self._definition = self._strategy_engine:get_definition(bg_key)
    if not self._bg_key or not self._definition then
        return false
    end

    self._side = self._detector:resolve_side(self._bg_key, player_pos)
    if not self._side then
        self._activation_wait_reason = "awaiting_player_position"
        self._blackboard:set("bg.activation_wait_reason", self._activation_wait_reason)
        return false
    end

    self._objective_tracker:reset()
    self._objective_approach_runtime = ObjectiveApproach.new_runtime(self:_movement_settings())
    self._selected_candidate = nil
    self._selected_objective = nil
    self._route_failure_counts = {}
    self._last_failure_marker = nil
    self._last_state = nil
    self._last_selected_objective_id = nil
    self._last_selected_score = nil
    self._bootstrap = {
        phase = self._blackboard:get("bg.sensor.in_prep", false) == true and "prep" or "pending",
        route_id = nil,
        ready = false,
        failed_attempts = 0,
        reason = nil,
    }

    self._active = true
    self._combat_paused = false
    self._activation_wait_reason = nil
    self._last_handoff_request_at_ms = 0
    self:_reset_eots_prep_state()
    self._ally_tracker:reset()
    self._last_ally_nav_pos = nil
    self._nav:reset()
    self._blackboard:set("bg.active", true)
    self._blackboard:set("bg.key", self._bg_key)
    self._blackboard:set("bg.side", self._side)
    self._blackboard:set("bg.nav_map_id", self._bg_data.map_id)
    self._blackboard:set("bg.activation_wait_reason", nil)
    self._blackboard:set("bg.prep_release_grace_until_ms", 0)
    self:_clear_retreat_state()
    if self._bg_key == "EOTS" then
        self._eots_prep.armed = true
    end
    self._event_bus:publish(Events.ENTERED, {
        bg_key = self._bg_key,
        map_id = self._bg_data.map_id,
        map_name = self._bg_data.name,
    })
    self._event_bus:publish(Events.MODULE_ENABLED, { bg_key = self._bg_key })
    return true
end

function SentinelBG:_deactivate(reason)
    local was_active = self._active == true
    if self._blackboard:get("nav.owner") == "bg" then
        self._nav:stop(reason or "bg_exit", "bg")
    end
    if was_active then
        self._event_bus:publish(Events.LEFT, {
            bg_key = self._bg_key,
            map_id = self._bg_data and self._bg_data.map_id or 0,
            reason = reason or "bg_exit",
        })
        self._event_bus:publish(Events.MODULE_DISABLED, {
            bg_key = self._bg_key,
            reason = reason or "bg_exit",
        })
    end
    self._active = false
    self._bg_key = nil
    self._bg_data = nil
    self._side = nil
    self._definition = nil
    self._combat_paused = false
    self._activation_wait_reason = nil
    self._last_handoff_request_at_ms = 0
    self:_reset_eots_prep_state()
    self._selected_candidate = nil
    self._selected_objective = nil
    self._bootstrap = {
        phase = "idle",
        route_id = nil,
        ready = false,
        failed_attempts = 0,
        reason = nil,
    }
    self._objective_tracker:reset()
    self._ally_tracker:reset()
    self._last_ally_nav_pos = nil
    self:_clear_battleground_diagnostics()
end

function SentinelBG:_route_nodes(route_id)
    if not self._definition or not route_id then
        return nil
    end
    local routes = self._definition:get_routes() or {}
    return routes[route_id]
end

function SentinelBG:_retreat_target()
    local catalog = self:_objective_catalog()
    if catalog and type(catalog.retreat) == "table" then
        return catalog.retreat[self._side]
    end
    return self._bg_data and self._bg_data.anchors and self._bg_data.anchors[self._side] or nil
end

function SentinelBG:_trim_route_nodes(route_nodes, player_pos)
    if type(route_nodes) ~= "table" or #route_nodes == 0 or type(player_pos) ~= "table" then
        return route_nodes
    end

    local nearest_index = 1
    local nearest_distance = distance(player_pos, route_nodes[1])
    for index = 2, #route_nodes do
        local current_distance = distance(player_pos, route_nodes[index])
        if current_distance < nearest_distance then
            nearest_distance = current_distance
            nearest_index = index
        end
    end

    if nearest_distance > 40 then
        return route_nodes
    end

    while nearest_index < #route_nodes and distance(player_pos, route_nodes[nearest_index]) <= 10 do
        nearest_index = nearest_index + 1
    end

    if nearest_index <= 1 then
        return route_nodes
    end

    local trimmed = {}
    for index = nearest_index, #route_nodes do
        trimmed[#trimmed + 1] = shallow_copy(route_nodes[index])
    end
    return trimmed
end

function SentinelBG:_route_nodes_to_issue(route_nodes, player_pos)
    local catalog = self:_objective_catalog()
    if not catalog or type(catalog.by_id) ~= "table" then
        return route_nodes
    end
    local offset = ObjectiveApproach.offset_route_nodes(route_nodes, catalog.by_id, self:_movement_settings(), self._objective_approach_runtime)
    return self:_trim_route_nodes(offset, player_pos)
end

function SentinelBG:_build_summary(evaluation, objective_states, nav_plan)
    local selected = evaluation and evaluation.selected or nil
    local selected_objective = selected and selected.objective or nil
    local selection_meta = evaluation and shallow_copy(evaluation.selection_meta or {}) or {}
    if selected then
        selection_meta.selected_score = selected.score
        selection_meta.selected_owner = selected.owner
        selection_meta.selected_distance = selected.distance
    end

    return {
        active = self._active,
        bg_key = self._bg_key,
        side = self._side,
        state = nav_plan and nav_plan.state or (self._active and "FOLLOWING_STRATEGY" or nil),
        objective_id = selected and selected.id or nil,
        nav_target = nav_plan and nav_plan.nav_target or nil,
        route_id = nav_plan and nav_plan.route_id or nil,
        strategy_id = evaluation and evaluation.strategy_id or nil,
        strategy_label = evaluation and evaluation.strategy_label or nil,
        selected_objective_id = selected and selected.id or nil,
        selected_objective = selected_objective,
        selection_meta = selection_meta,
        selection_failure_reason = nav_plan and nav_plan.selection_failure_reason or nil,
        candidates_top3 = evaluation and top_candidates(evaluation.candidates or {}) or {},
        objective_states = objective_states,
        capture_focus_objective_id = selected and selected.type == "FLAG" and selected.id or nil,
        momentum_score = self._objective_tracker:get_momentum_summary(),
        bootstrap_phase = self._bootstrap.phase,
        bootstrap_route_id = self._bootstrap.route_id,
        bootstrap_ready = self._bootstrap.ready,
        bootstrap_failed_attempts = self._bootstrap.failed_attempts,
        bootstrap_reason = self._bootstrap.reason,
        objective_approach_mode = self._objective_approach_runtime.mode,
        objective_approach_objective_id = selected and self._objective_approach_runtime.objective_id or nil,
        objective_approach_variant = selected and self._objective_approach_runtime.variant or nil,
        objective_approach_last_variant_shift_at_ms = selected and self._objective_approach_runtime.last_variant_shift_at_ms or nil,
        objective_approach_stage = selected and self._objective_approach_runtime.stage or nil,
        objective_anchor = nav_plan and nav_plan.objective_anchor or nil,
        objective_approach_source = nav_plan and nav_plan.objective_approach_source or nil,
        route_source = nav_plan and nav_plan.route_source or nil,
        nav_authority = nav_plan and nav_plan.nav_authority or nil,
    }
end

function SentinelBG:_maybe_publish_state(state, objective_id)
    if state ~= self._last_state then
        self._event_bus:publish(Events.STATE_CHANGED, {
            bg_key = self._bg_key,
            from = self._last_state,
            to = state,
            objective_id = objective_id,
            reason = "strategy_runtime",
        })
        self._last_state = state
    end
end

function SentinelBG:_maybe_publish_objective(selected)
    local selected_id = selected and selected.id or nil
    if selected_id ~= self._last_selected_objective_id then
        self._event_bus:publish(Events.OBJECTIVE_SELECTED, {
            bg_key = self._bg_key,
            objective_id = selected_id,
            lane_id = self._bootstrap.route_id,
            target = selected and selected.objective or nil,
            score = selected and selected.score or nil,
        })
        self._last_selected_objective_id = selected_id
        self._last_selected_score = selected and selected.score or nil
    end
end

function SentinelBG:_record_nav_failure_if_needed()
    local nav_result = self._blackboard:get("bg.nav_result")
    if nav_result ~= "failed" then
        if nav_result == "arrived" then
            self._last_failure_marker = nil
        end
        return
    end

    local marker = table.concat({
        tostring(self._last_nav_authority or ""),
        tostring(self._blackboard:get("bg.nav_route_id") or ""),
        tostring(self._blackboard:get("bg.nav_objective_id") or ""),
    }, "|")

    if marker == self._last_failure_marker then
        return
    end

    self._last_failure_marker = marker
    self._route_failure_counts[marker] = num(self._route_failure_counts[marker]) + 1
    if self._last_nav_authority == "spawn_bootstrap_route" then
        self._bootstrap.failed_attempts = self._bootstrap.failed_attempts + 1
    end
end

function SentinelBG:_failure_count_for(authority, route_id, objective_id)
    local marker = table.concat({
        tostring(authority or ""),
        tostring(route_id or ""),
        tostring(objective_id or ""),
    }, "|")
    return num(self._route_failure_counts[marker])
end

function SentinelBG:_resolve_nav_plan(evaluation, player_pos, prep_blocked)
    local selected = evaluation and evaluation.selected or nil
    local objective = selected and selected.objective or nil
    local objective_id = selected and selected.id or nil
    local objective_center = objective and { x = objective.x, y = objective.y, z = objective.z } or nil
    local objective_anchor = objective and type(objective.approach_anchor) == "table" and shallow_copy(objective.approach_anchor) or nil
    local movement_settings = self:_movement_settings()
    local nav_state = tostring(self._blackboard:get("nav.state", "idle") or "idle")
    local nav_result = self._blackboard:get("bg.nav_result")
    local nav_progress = self._blackboard:get("nav.progress")
    local handoff_radius = self:_objective_handoff_radius()

    self._objective_approach_runtime = ObjectiveApproach.update_runtime(
        self._objective_approach_runtime,
        objective,
        player_pos,
        nav_state,
        nav_result,
        nav_progress,
        movement_settings,
        num(self._blackboard:get("system.now_ms", 0))
    )

    local objective_nav_target = objective and ObjectiveApproach.compute_nav_target(player_pos, objective, movement_settings, self._objective_approach_runtime) or nil
    local objective_handoff_target = objective_anchor or objective_center
    local objective_approach_source = objective_anchor and self._objective_approach_runtime.stage == "anchor" and "anchor" or "ring"
    local retreat_requested = self._blackboard:get("bg.retreat_requested", false) == true

    if prep_blocked then
        self:_clear_retreat_state()
        self._bootstrap.phase = "prep"
        self._bootstrap.ready = false
        self._bootstrap.reason = self._blackboard:get("bg.prep_gate_reason", "waiting_for_prep_end")
        self._bootstrap.route_id = evaluation and evaluation.bootstrap_route_id or self._bootstrap.route_id
        objective_center = nil
        objective_nav_target = nil
        objective_anchor = nil
        objective_approach_source = nil
        return {
            state = "PRE_GAME",
            nav_authority = "pre_game_prep",
            route_source = nil,
            route_id = self._bootstrap.route_id,
            route_nodes = nil,
            nav_target = nil,
            objective = objective,
            objective_id = objective_id,
            objective_center = objective_center,
            objective_nav_target = objective_nav_target,
            objective_anchor = objective_anchor,
            objective_approach_source = objective_approach_source,
            selection_failure_reason = nil,
        }
    end

    if retreat_requested then
        local retreat_target = self:_retreat_target()
        if retreat_target and distance(player_pos, retreat_target) <= 10 then
            self:_clear_retreat_state()
            retreat_requested = false
        elseif not retreat_target then
            self:_clear_retreat_state()
            retreat_requested = false
        else
            return {
                state = "RETREAT",
                nav_authority = "retreat",
                route_source = "objective",
                route_id = nil,
                route_nodes = nil,
                nav_target = retreat_target,
                objective = objective,
                objective_id = objective_id,
                objective_center = objective_center,
                objective_nav_target = objective_nav_target,
                objective_anchor = objective_anchor,
                objective_approach_source = objective_approach_source,
                selection_failure_reason = nil,
            }
        end
    end

    if not self._bootstrap.ready then
        self._bootstrap.phase = "active"
        self._bootstrap.route_id = self._bootstrap.route_id or (evaluation and evaluation.bootstrap_route_id or nil)
        if not self._bootstrap.route_id then
            self._bootstrap.ready = true
            self._bootstrap.phase = "complete"
            self._bootstrap.reason = "no_bootstrap_route"
        else
            local route_id = self._bootstrap.route_id
            local route_nodes = self:_route_nodes(route_id)
            local bootstrap_failures = self:_failure_count_for("spawn_bootstrap_route", route_id, objective_id)
            self._bootstrap.failed_attempts = bootstrap_failures

            local bootstrap_complete = false
            if type(objective_handoff_target) == "table" and distance(player_pos, objective_handoff_target) <= handoff_radius then
                bootstrap_complete = true
                self._bootstrap.reason = "objective_close"
            elseif self._blackboard:get("bg.nav_result") == "arrived" and self._blackboard:get("bg.nav_route_id") == route_id then
                bootstrap_complete = true
                self._bootstrap.reason = "route_arrived"
            elseif self._bg_key == "EOTS" and bootstrap_failures > 1 then
                bootstrap_complete = true
                self._bootstrap.reason = "bootstrap_retry_exhausted"
            elseif not route_nodes then
                bootstrap_complete = true
                self._bootstrap.reason = "missing_bootstrap_route"
            end

            if not bootstrap_complete then
                return {
                    state = "BOOTSTRAP",
                    nav_authority = "spawn_bootstrap_route",
                    route_source = "bootstrap",
                    route_id = route_id,
                    route_nodes = route_nodes,
                    nav_target = objective_nav_target or objective_center,
                    objective = objective,
                    objective_id = objective_id,
                    objective_center = objective_center,
                    objective_nav_target = objective_nav_target,
                    objective_anchor = objective_anchor,
                    objective_approach_source = objective_approach_source,
                    selection_failure_reason = nil,
                }
            end

            self._bootstrap.ready = true
            self._bootstrap.phase = "complete"
        end
    end

    if type(objective_handoff_target) == "table" and distance(player_pos, objective_handoff_target) <= handoff_radius then
        return {
            state = "ATTACKING_OBJECTIVE",
            nav_authority = "objective_approach",
            route_source = "objective",
            route_id = nil,
            route_nodes = nil,
            nav_target = objective_nav_target or objective_center,
            objective = objective,
            objective_id = objective_id,
            objective_center = objective_center,
            objective_nav_target = objective_nav_target,
            objective_anchor = objective_anchor,
            objective_approach_source = objective_approach_source,
            selection_failure_reason = nil,
        }
    end

    local strategy_route_id = evaluation and evaluation.default_route_id or nil
    local strategy_route_nodes = self:_route_nodes(strategy_route_id)
    local strategy_failures = self:_failure_count_for("strategy_route", strategy_route_id, objective_id)

    if self._bg_key == "EOTS" and objective and objective.type == "NODE" then
        strategy_route_id = nil
        strategy_route_nodes = nil
    end

    if strategy_route_id and strategy_route_nodes and not (self._bg_key == "EOTS" and strategy_failures > 1) then
        return {
            state = "FOLLOWING_STRATEGY",
            nav_authority = "strategy_route",
            route_source = "strategy",
            route_id = strategy_route_id,
            route_nodes = strategy_route_nodes,
            nav_target = objective_nav_target or objective_center,
            objective = objective,
            objective_id = objective_id,
            objective_center = objective_center,
            objective_nav_target = objective_nav_target,
            objective_anchor = objective_anchor,
            objective_approach_source = objective_approach_source,
            selection_failure_reason = nil,
        }
    end

    return {
        state = objective and "ATTACKING_OBJECTIVE" or "FOLLOWING_STRATEGY",
        nav_authority = objective and "objective_approach" or nil,
        route_source = objective and "objective" or nil,
        route_id = nil,
        route_nodes = nil,
        nav_target = objective_nav_target or objective_center,
        objective = objective,
        objective_id = objective_id,
        objective_center = objective_center,
        objective_nav_target = objective_nav_target,
        objective_anchor = objective_anchor,
        objective_approach_source = objective_approach_source,
        selection_failure_reason = objective and nil or "no_selected_objective",
    }
end

function SentinelBG:update(blackboard)
    if blackboard:get("module.bg.enabled", true) ~= true then
        self._queue:reset("bg_disabled")
        self._leave:reset("bg_disabled")
        self._ghost:reset("bg_disabled")
        self._mount:reset("bg_disabled")
        self:_deactivate("bg_disabled")
        return
    end

    self._queue:update()
    self._leave:update()

    local map_id = blackboard:get("system.map_id", 0)
    local map_name = blackboard:get("system.map_name", "")
    local instance_id = blackboard:get("system.instance_id", 0)
    local instance_name = blackboard:get("system.instance_name", "")
    local in_bg = blackboard:get("bg.sensor.in_bg", false) == true
    local now_ms = num(blackboard:get("system.now_ms", 0))
    local bg_key, bg_data, detect_reason = self._detector:detect(map_id, map_name, instance_id, instance_name)

    blackboard:set("bg.detected_key", bg_key)
    blackboard:set("bg.detect_reason", detect_reason)

    if bg_key then
        self._last_detected_key = bg_key
        self._last_detected_at_ms = now_ms
    elseif self._active and in_bg and self._bg_key and (now_ms - self._last_detected_at_ms) <= self._detect_sticky_ms then
        bg_key = self._bg_key
        bg_data = self._bg_data
        blackboard:set("bg.detected_key", bg_key)
        blackboard:set("bg.detect_reason", "sticky")
    else
        self._last_detected_key = nil
        self:_clear_bg_owned_nav_if_inactive("not_in_supported_bg")
        self:_deactivate("not_in_supported_bg")
        return
    end

    if not self._active then
        local activated = self:_activate(bg_key, bg_data)
        if not activated then
            self:_clear_bg_owned_nav_if_inactive(self._activation_wait_reason or "bg_activation_pending")
            return
        end
    end

    self._blackboard:set("bg.nav_map_id", self._bg_data and self._bg_data.map_id or nil)
    self._nav:update(blackboard)
    self:_record_nav_failure_if_needed()

    self._ghost:update()
    if self._ghost:is_blocking_strategy() then
        self._context_builder:refresh({
            active = true,
            bg_key = self._bg_key,
            side = self._side,
            state = "REGROUP",
            nav_authority = "retreat",
            objective_approach_mode = self._objective_approach_runtime.mode,
            objective_approach_objective_id = self._objective_approach_runtime.objective_id,
            objective_approach_variant = self._objective_approach_runtime.variant,
            objective_approach_last_variant_shift_at_ms = self._objective_approach_runtime.last_variant_shift_at_ms,
        })
        self._blackboard:set("bg.activation_wait_reason", nil)
        return
    end

    local player_pos = blackboard:get("player.position")
    local objective_states, runtime_signals = self._objective_tracker:update(
        self._side,
        self._definition:get_objectives() or {},
        {
            bg_key = self._bg_key,
            side = self._side,
            player_pos = player_pos,
        }
    )
    runtime_signals = type(runtime_signals) == "table" and runtime_signals or {}
    blackboard:set("bg.sensor.spawn_barrier_seen", runtime_signals.spawn_barrier_seen == true)
    blackboard:set("bg.sensor.spawn_barrier_up", runtime_signals.spawn_barrier_seen == true)
    blackboard:set("bg.sensor.spawn_barrier_entry", runtime_signals.spawn_barrier_entry)
    blackboard:set("bg.sensor.spawn_barrier_name", runtime_signals.spawn_barrier_name)
    blackboard:set("bg.sensor.spawn_barrier_distance", runtime_signals.spawn_barrier_distance)
    blackboard:set("bg.sensor.spawn_barrier_source", runtime_signals.spawn_barrier_source)
    local prep_blocked, prep_reason = self:_prep_gate(runtime_signals, now_ms)
    blackboard:set("bg.prep_gate_reason", prep_reason)
    local evaluation = self._strategy_engine:evaluate({
        bg_key = self._bg_key,
        player_side = self._side,
        player_position = player_pos,
        objective_states = objective_states,
        strategy_settings = self:_strategy_settings(),
        bootstrap_phase = self._bootstrap.phase,
        prep_blocked = prep_blocked,
    })
    self._ally_tracker:update(self._blackboard)

    local nav_plan = self:_resolve_nav_plan(evaluation, player_pos, prep_blocked)

    self._selected_candidate = evaluation and evaluation.selected or nil
    self._selected_objective = self._selected_candidate and self._selected_candidate.objective or nil
    self:_maybe_publish_objective(self._selected_candidate)
    self:_maybe_publish_state(nav_plan.state, nav_plan.objective_id)

    self._blackboard:set("bg.objective_type", nav_plan.objective and nav_plan.objective.type or nil)
    self._blackboard:set("bg.objective_center", nav_plan.objective_center)
    self._blackboard:set("bg.objective_nav_target", nav_plan.objective_nav_target)
    self._blackboard:set("bg.objective_anchor", nav_plan.objective_anchor)
    self._blackboard:set("bg.objective_approach_source", nav_plan.objective_approach_source)
    self._blackboard:set("bg.objective_approach.stage", nav_plan.objective and self._objective_approach_runtime.stage or nil)
    self._blackboard:set("bg.selection_failure_reason", nav_plan.selection_failure_reason)
    self._blackboard:set("bg.activation_wait_reason", nil)
    self:_update_capture_hold(nav_plan.objective, player_pos)

    self._context_builder:refresh(self:_build_summary(evaluation, objective_states, nav_plan))

    local mount_target = nav_plan.nav_target
    if not mount_target and type(nav_plan.route_nodes) == "table" and #nav_plan.route_nodes > 0 then
        mount_target = nav_plan.route_nodes[#nav_plan.route_nodes]
    end
    local mount_state = self._mount:update(mount_target, {
        bg_key = self._bg_key,
        nav_authority = nav_plan.nav_authority,
    })
    if mount_state == "mount_requested" or mount_state == "mount_pending" then
        if blackboard:get("nav.owner") == "bg" or blackboard:get("nav.command") ~= nil then
            self._nav:stop("mount_pending", "bg")
        end
        return
    end

    if nav_plan.nav_authority == "pre_game_prep" then
        self:_clear_retreat_state()
        if blackboard:get("nav.owner") == "bg" then
            self._nav:stop(nav_plan.nav_authority, "bg")
        end
        return
    end

    if nav_plan.nav_authority == "combat_handoff" then
        if blackboard:get("nav.owner") == "bg" then
            self._nav:stop(nav_plan.nav_authority, "bg")
        end
        return
    end

    local retreat, retreat_reason = self._engagement_policy:should_retreat(blackboard)
    if retreat then
        blackboard:set("bg.retreat_requested", true)
        blackboard:set("bg.retreat_reason", retreat_reason)
        blackboard:set("bg.retreat_set_at_ms", now_ms)
        self._event_bus:publish(Events.RETREAT_REQUESTED, {
            bg_key = self._bg_key,
            reason = retreat_reason,
            retreat_target = self:_retreat_target(),
        })
    end

    if self._combat_paused then
        self._blackboard:set("bg.nav_authority", "combat_handoff")
        return
    end

    local engage_delegate = {
        should_engage = function()
            return self._selected_candidate ~= nil
        end,
    }
    if self._engagement_policy:should_engage(blackboard, engage_delegate) then
        local is_mounted = blackboard:get("player.is_mounted", false) == true
        if is_mounted and blackboard:get("module.bg.dismount_on_player_threat", true) == true then
            if self._mount:request_dismount_for_combat() then
                return
            end
        end
        if not is_mounted and (now_ms - self._last_handoff_request_at_ms) >= self._handoff_request_cooldown_ms then
            self._last_handoff_request_at_ms = now_ms
            local handoff_target = blackboard:get("combat.target") or blackboard:get("player.target")
            self._event_bus:publish(Events.COMBAT_HANDOFF_REQUESTED, {
                bg_key = self._bg_key,
                target = handoff_target,
                objective_id = nav_plan.objective_id,
                source_state = nav_plan.state,
                source = "bg",
                leash_center = blackboard:get("player.position"),
                leash_radius = 25,
            })
        end
    end

    local active_nav_objective_id = blackboard:get("bg.nav_objective_id")
    local active_nav_route_id = blackboard:get("bg.nav_route_id")
    local nav_map_id = self._bg_data and self._bg_data.map_id or nil
    self._last_nav_authority = nav_plan.nav_authority

    -- Ally follow override: when following strategy and a follow target is available,
    -- navigate toward the ally cluster instead of the objective route.
    local ally_follow_pos = blackboard:get("bg.follow_target_position")
    local ally_follow_state = nav_plan.state
    if ally_follow_pos
        and ally_follow_state ~= "BOOTSTRAP"
        and ally_follow_state ~= "RETREAT"
        and ally_follow_state ~= "PRE_GAME"
        and ally_follow_state ~= "DEAD"
        and ally_follow_state ~= "GHOST_RUNNING"
    then
        local need_reissue = true
        if self._last_ally_nav_pos then
            local moved = distance(ally_follow_pos, self._last_ally_nav_pos)
            if moved <= 5 then
                need_reissue = false
            end
        end
        if need_reissue and self._humanization:is_ready("nav_issue", 0.1, 0.3) then
            self._blackboard:set("bg.route_failure_reason", nil)
            self._nav:issue_move_to(ally_follow_pos, {
                source = "bg",
                objective_id = nav_plan.objective_id,
                opts = { map_id = nav_map_id },
            })
            self._last_ally_nav_pos = { x = num(ally_follow_pos.x), y = num(ally_follow_pos.y), z = num(ally_follow_pos.z) }
            self._last_nav_authority = "ally_follow"
            blackboard:set("bg.nav_authority", "ally_follow")
        end
        return
    end

    if nav_plan.nav_authority == "spawn_bootstrap_route" or nav_plan.nav_authority == "strategy_route" then
        local issued_nodes = self:_route_nodes_to_issue(nav_plan.route_nodes, player_pos)
        if blackboard:get("nav.owner") ~= "bg"
            or blackboard:get("nav.command") ~= "follow_path"
            or active_nav_objective_id ~= nav_plan.objective_id
            or active_nav_route_id ~= nav_plan.route_id then
            self._blackboard:set("bg.route_failure_reason", nil)
            self._nav:issue_follow_path(issued_nodes, {
                source = "bg",
                objective_id = nav_plan.objective_id,
                route_id = nav_plan.route_id,
                opts = { map_id = nav_map_id },
            })
        end
        return
    end

    if nav_plan.nav_authority == "objective_approach" or nav_plan.nav_authority == "retreat" then
        if nav_plan.nav_target then
            if blackboard:get("nav.owner") ~= "bg"
                or blackboard:get("nav.command") ~= "move_to"
                or active_nav_objective_id ~= nav_plan.objective_id then
                self._blackboard:set("bg.route_failure_reason", nil)
                self._nav:issue_move_to(nav_plan.nav_target, {
                    source = "bg",
                    objective_id = nav_plan.objective_id,
                    opts = { map_id = nav_map_id },
                })
            end
        elseif blackboard:get("nav.owner") == "bg" then
            self._nav:stop("no_nav_target", "bg")
        end
        return
    end

    if blackboard:get("nav.owner") == "bg" then
        self._nav:stop("no_nav_authority", "bg")
    end
end

function SentinelBG:is_active()
    return self._active
end

function SentinelBG:get_state()
    return self._blackboard:get("bg.state", self._active and "FOLLOWING_STRATEGY" or "INACTIVE")
end

function SentinelBG:get_current_bg_key()
    return self._bg_key
end

function SentinelBG:force_regroup(reason)
    if self._active then
        self._blackboard:set("bg.retreat_requested", true)
        self._blackboard:set("bg.retreat_reason", reason or "force_regroup")
        self._blackboard:set("bg.retreat_set_at_ms", num(self._blackboard:get("system.now_ms", 0)))
        self._event_bus:publish(Events.RETREAT_REQUESTED, {
            bg_key = self._bg_key,
            reason = reason or "force_regroup",
            retreat_target = self:_retreat_target(),
        })
    end
end

function SentinelBG:leave_now(reason)
    self._leave:request_now(reason or "ui_manual_test")
end

function SentinelBG:set_enabled(enabled)
    local next_enabled = enabled == true
    local current_enabled = self:is_enabled()
    self._blackboard:set("module.bg.enabled", next_enabled)
    if current_enabled == next_enabled then
        return
    end
    if enabled ~= true then
        self:_deactivate("bg_disabled")
    end
end

function SentinelBG:is_enabled()
    return self._blackboard:get("module.bg.enabled", true) == true
end

return SentinelBG
