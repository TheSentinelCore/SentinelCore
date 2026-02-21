---@module BGBOT main
-- Entry point: wires Perception → World Model → Strategist → Intent Controller → Nav.
-- Registers core.register_on_update_callback and core.register_on_render_menu_callback.

local constants    = require("shared/constants")
local config       = require("shared/config")
local utils        = require("shared/utils")
local Logger       = require("shared/logger")
local Scanner      = require("core/perception/scanner")
local WorldModel   = require("core/world_model/world_model")
local Strategist   = require("core/strategist/strategist")
local Controller   = require("core/intent/controller")
local RoamIntent   = require("core/intent/intents/roam")
local CarryFlagIntent = require("core/intent/intents/carry_flag")
local EscortCarrierIntent = require("core/intent/intents/escort_carrier")
local InterceptCarrierIntent = require("core/intent/intents/intercept_carrier")
local ReturnFlagIntent = require("core/intent/intents/return_flag")
local FightIntent = require("core/intent/intents/fight")
local RetreatIntent = require("core/intent/intents/retreat")
local FollowHerdIntent = require("core/intent/intents/follow_herd")
local GrabBgBuffIntent = require("core/intent/intents/grab_bg_buff")
local SpinFlagIntent = require("core/intent/intents/spin_flag")
local FailsafeIntent = require("core/intent/intents/failsafe")
local WsgHelpers  = require("core/intent/intents/wsg_helpers")
local WsgModule    = require("bg/wsg/wsg_module")
local AbModule     = require("bg/ab/ab_module")
local EotsModule   = require("bg/eots/eots_module")
local AvModule     = require("bg/av/av_module")
local CombatMicro = require("core/combat_micro/combat_micro")
local ActionArbiter = require("core/action_arbiter")
local Humanization = require("core/humanization/humanization")

----------------------------------------------------------------------
-- Module Instances
----------------------------------------------------------------------

local world_model = WorldModel.new()
local scanner     = Scanner.new(world_model)

-- Intent registry  (M1: roam only.  M2: all 7 intents.)
local roam_intent   = RoamIntent.new()
local carry_flag_intent = CarryFlagIntent.new()
local escort_carrier_intent = EscortCarrierIntent.new()
local intercept_carrier_intent = InterceptCarrierIntent.new()
local return_flag_intent = ReturnFlagIntent.new()
local fight_intent = FightIntent.new()
local retreat_intent = RetreatIntent.new()
local follow_herd_intent = FollowHerdIntent.new()
local grab_bg_buff_intent = GrabBgBuffIntent.new()
local spin_flag_intent = SpinFlagIntent.new()
local failsafe_intent = FailsafeIntent.new()
local intent_registry = {
    carry_flag = carry_flag_intent,
    escort_carrier = escort_carrier_intent,
    intercept_carrier = intercept_carrier_intent,
    return_flag = return_flag_intent,
    fight = fight_intent,
    retreat = retreat_intent,
    follow_herd = follow_herd_intent,
    grab_bg_buff = grab_bg_buff_intent,
    spin_flag = spin_flag_intent,
    failsafe = failsafe_intent,
    roam = roam_intent,
}

local strategist = Strategist.new(intent_registry)

-- BG modules registry: bg_type string → module table.
-- Modules are set on the strategist dynamically per-tick based on bg_type.
local BG_MODULES = {
    wsg  = WsgModule,
    ab   = AbModule,
    eots = EotsModule,
    av   = AvModule,
}
local active_bg_type = nil  -- tracked to avoid redundant set_bg_module calls
strategist:set_bg_module(nil)  -- no BG module until detection resolves

local controller = Controller.new(roam_intent)
local combat_micro = CombatMicro.new()
local action_arbiter = ActionArbiter.new()
local humanization = Humanization.new()
local telemetry_logger = Logger.new({
    enabled = config.telemetry and config.telemetry.enabled == true,
    dir = (config.telemetry and config.telemetry.dir) or "BGBOT/data/telemetry",
    file_name = (config.telemetry and config.telemetry.file_name) or "events.ndjson",
})
local summary_logger = Logger.new({
    enabled = config.telemetry and config.telemetry.enabled == true,
    dir = (config.telemetry and config.telemetry.dir) or "BGBOT/data/telemetry",
    file_name = (config.telemetry and config.telemetry.summary_file_name) or "match_summaries.ndjson",
})

local match_kpi = {
    active = false,
    summary_emitted = false,
    bg_type = "unknown",
    started_at = 0,
    objective_interactions = 0,
    intent_switches = 0,
    deaths = 0,
    stuck_time = 0,
    stuck_since = 0,
    last_dead = false,
}

-- Death state
local death_release_at = 0
local is_waiting_resurrect = false
local last_interact_at = 0

-- Navigation state (throttle re-requests)
local last_nav_goal   = nil   -- last vec3 sent to SentinelNavClient
local nav_is_moving   = false -- true while client reports moving
local nav_repath_at   = 0     -- earliest time we may re-request
local unknown_phase_since = 0 -- main-loop fallback timer for phase=0 servers

-- Nav stuck penalty tracking (uses SentinelNavClient get_state/get_full_state)
local nav_stuck_penalty_until = 0  -- core.time() deadline for score halving
local nav_stuck_intent_id = nil    -- intent that was active when stuck detected
local nav_failure_tracker = {}     -- { [intent_id] = { first_at, count } }

-- Runtime diagnostics capture (console + scripts_data NDJSON)
local DIAG_DIR = "BGBOT/data/debug"
local DIAG_INTERVAL = 1.0
local diag = {
    enabled = false,
    external_enabled = false,
    tick_enabled = false,
    console_events = false,
    snapshot_requested = false,
    snapshot_reason = "manual",
    file_name = nil,
    file_ready = false,
    buffer = "",
    write_count = 0,
    last_reason = "none",
    last_error = "",
    last_tick_emit = 0,
    prev_bg_type = nil,
    prev_phase = nil,
    prev_intent = nil,
    prev_nav_state = nil,
    prev_role = nil,
}

----------------------------------------------------------------------
-- Persistent menu elements (allocated ONCE, not per-frame)
-- Constructor: core.menu.checkbox(default_state, unique_id)
-- Constructor: core.menu.header()
-- Constructor: core.menu.tree_node()
----------------------------------------------------------------------

local TAG = "bgbot_"
local ROLE_OPTIONS = {
    "Auto",
    "DPS",
    "Healer",
    "Tankish",
}

local function role_mode_to_combo_index(role_mode)
    local mode = tonumber(role_mode) or constants.ROLE.AUTO
    local idx = mode + 1 -- role constants are 0-based; combobox index is 1-based.
    if idx < 1 then idx = 1 end
    if idx > #ROLE_OPTIONS then idx = #ROLE_OPTIONS end
    return idx
end

local function combo_index_to_role_mode(idx)
    local i = tonumber(idx) or 1
    if i < 1 then i = 1 end
    if i > #ROLE_OPTIONS then i = #ROLE_OPTIONS end
    return i - 1
end

local menu_elements = {
    enabled        = core.menu.checkbox(true,  TAG .. "enabled"),
    role_mode      = core.menu.combobox(role_mode_to_combo_index(config.role.mode), TAG .. "role_mode_v2"),
    enable_buffs   = core.menu.checkbox(config.wsg.enable_buff_pickups, TAG .. "enable_buffs"),
    force_action_phase = core.menu.checkbox(config.bg.force_action_phase, TAG .. "force_action_phase"),
    header         = core.menu.header(),
    status_header  = core.menu.header(),
    scan_header    = core.menu.header(),
    nav_header     = core.menu.header(),
    debug_node     = core.menu.tree_node(),
    log_perception = core.menu.checkbox(true, TAG .. "log_perception"),
    log_wm         = core.menu.checkbox(true, TAG .. "log_world_model"),
    log_intent     = core.menu.checkbox(true,  TAG .. "log_intent"),
    log_combat     = core.menu.checkbox(true, TAG .. "log_combat"),
    log_nav        = core.menu.checkbox(true, TAG .. "log_nav"),
    diag_node      = core.menu.tree_node(),
    diag_enabled   = core.menu.checkbox(true, TAG .. "diag_enabled"),
    diag_tick      = core.menu.checkbox(true, TAG .. "diag_tick"),
    diag_console   = core.menu.checkbox(true, TAG .. "diag_console"),
    diag_snapshot  = core.menu.button(TAG .. "diag_snapshot"),
    diag_status    = core.menu.header(),
    diag_file      = core.menu.header(),
    diag_error     = core.menu.header(),
}

----------------------------------------------------------------------
-- Nav helper: only call move_to on goal change or when idle
----------------------------------------------------------------------

local emit_telemetry_event

-- Runtime API guard: some private servers expose partial core.input surfaces.
-- Keep execution alive by skipping missing methods instead of hard-crashing.
local missing_input_method_logged = {}

local function get_core_input_method(method_name)
    local input = core and core.input or nil
    if type(input) ~= "table" then
        return nil
    end

    local fn = input[method_name]
    if type(fn) ~= "function" then
        return nil
    end

    return fn
end

local function log_missing_input_method(method_name)
    local key = tostring(method_name or "")
    if key == "" or missing_input_method_logged[key] then
        return
    end

    missing_input_method_logged[key] = true
    if core and core.log then
        core.log(string.format("[BGBOT][API] Missing core.input.%s; skipping call.", key))
    end
end

local function safe_core_input_call(method_name, ...)
    local fn = get_core_input_method(method_name)
    if not fn then
        log_missing_input_method(method_name)
        return false, "missing_method"
    end

    return pcall(fn, ...)
end

local function goals_equal(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    return math.abs(a.x - b.x) < 1
       and math.abs(a.y - b.y) < 1
       and math.abs(a.z - b.z) < 1
end

-- Keep BGBOT's legacy "stuck" handling compatible with SentinelNavClient's
-- HSM model, where stuck recovery is represented as navigating.recovering.*.
local function resolve_nav_state(nav_client)
    if not nav_client then
        return "no-client", nil
    end

    local ok_state, raw_state = pcall(function()
        return nav_client:get_state()
    end)
    local state = tostring((ok_state and raw_state) or "unknown")

    local full_state = nil
    if nav_client.get_full_state then
        local ok_full, raw_full = pcall(function()
            return nav_client:get_full_state()
        end)
        if ok_full and raw_full then
            full_state = tostring(raw_full)
        end
    end

    if state == "navigating"
        and full_state
        and string.find(full_state, "navigating.recovering", 1, true) == 1 then
        return "stuck", full_state
    end

    return state, full_state
end

local function register_nav_failure(intent_id, reason)
    local id = tostring(intent_id or "")
    if id == "" or id == "none" then
        return
    end

    local now = core.time()
    local threshold = math.max(1, tonumber(config.nav.objective_blacklist_threshold) or 3)
    local window_secs = math.max(1, tonumber(config.nav.objective_blacklist_window) or 20)
    local cooldown_secs = math.max(1, tonumber(config.nav.objective_blacklist_cooldown) or 30)

    local bucket = nav_failure_tracker[id]
    if not bucket or (now - (bucket.first_at or 0)) > window_secs then
        bucket = {
            first_at = now,
            count = 1,
        }
    else
        bucket.count = (bucket.count or 0) + 1
    end

    nav_failure_tracker[id] = bucket

    if (bucket.count or 0) < threshold then
        return
    end

    bucket.count = 0
    bucket.first_at = now

    if strategist and strategist.blacklist_intent then
        strategist:blacklist_intent(id, cooldown_secs, reason or "nav_path_failures")
        emit_telemetry_event("objective_blacklist", {
            objective_intent = id,
            cooldown_secs = cooldown_secs,
            reason = tostring(reason or "nav_path_failures"),
        })
        if config.debug.log_nav then
            core.log(string.format("[BGBOT][Nav] Intent '%s' blacklisted for %.0fs after repeated failures",
                tostring(id), cooldown_secs))
        end
    end
end

local function try_nav_move(goal)
    if not goal then return end

    local now = core.time()
    local client = _G.SentinelNavClient and _G.SentinelNavClient.client

    if not client then
        if config.debug.log_nav then
            core.log("[BGBOT][Nav] SentinelNavClient not available!")
        end
        return
    end

    -- Skip if same goal and client is still moving
    local client_state = resolve_nav_state(client)
    local is_idle = (client_state == "idle" or client_state == "arrived"
                  or client_state == "failed" or client_state == "stuck")
    nav_is_moving = not is_idle

    local same_goal = goals_equal(goal, last_nav_goal)
    local goal_delta_2d = 999999
    if last_nav_goal then
        goal_delta_2d = utils.distance_2d(goal, last_nav_goal)
    end

    -- Global small-delta cooldown gate (applies to idle + moving states).
    if now < nav_repath_at and goal_delta_2d < (constants.NAV.MIN_GOAL_DELTA or 4.0) then
        return
    end

    if same_goal and not is_idle then
        return  -- still navigating to same goal
    end

    -- Do not spam identical goals if already done/idle.
    -- Only resend the same goal when movement is explicitly failed/stuck.
    if same_goal and (client_state == "arrived" or client_state == "idle") then
        return
    end

    -- Respect repath cooldown while moving/requesting.
    if not is_idle and now < nav_repath_at then
        return
    end

    -- Ignore tiny goal jitter while moving; prevents request churn.
    if not is_idle and goal_delta_2d < (constants.NAV.MIN_GOAL_DELTA or 4.0) then
        return
    end

    -- Send move request (pass vec3 table, not 3 numbers)
    local ok_move, move_err = pcall(function()
        client:move_to(goal, function(success, reason)
            if not success then
                nav_is_moving = false
                last_nav_goal = nil
                nav_repath_at = 0
                register_nav_failure(controller:get_current_id(), tostring(reason or "move_to_failed"))
                if config.debug.log_nav then
                    core.log("[BGBOT][Nav] move_to failed: " .. tostring(reason))
                end
            end
        end)
    end)

    if not ok_move then
        nav_is_moving = false
        last_nav_goal = nil
        nav_repath_at = 0
        register_nav_failure(controller:get_current_id(), "move_to_error")
        if config.debug.log_nav then
            core.log("[BGBOT][Nav] move_to errored: " .. tostring(move_err))
        end
        return
    end

    last_nav_goal  = { x = goal.x, y = goal.y, z = goal.z }
    nav_repath_at  = now + constants.NAV.REPATH_CD
    nav_is_moving  = true

    if config.debug.log_nav then
        core.log(string.format("[BGBOT][Nav] move_to(%.0f, %.0f, %.0f)",
            goal.x, goal.y, goal.z))
    end
end

local function stop_nav(reason)
    local client = _G.SentinelNavClient and _G.SentinelNavClient.client

    if client and client.stop then
        local client_state = resolve_nav_state(client)
        if client_state ~= "idle"
            and client_state ~= "arrived"
            and client_state ~= "failed"
            and client_state ~= "stuck" then
            pcall(function()
                client:stop()
            end)
        end
    end

    if (nav_is_moving or last_nav_goal ~= nil) and config.debug.log_nav then
        core.log("[BGBOT][Nav] stop (" .. tostring(reason or "unspecified") .. ")")
    end

    nav_is_moving = false
    last_nav_goal = nil
    nav_repath_at = 0
end

----------------------------------------------------------------------
-- Diagnostics helpers
----------------------------------------------------------------------

local function get_nav_state(nav_client)
    local client = nav_client or (_G.SentinelNavClient and _G.SentinelNavClient.client)
    if not client then
        return "no-client"
    end
    local state = resolve_nav_state(client)
    return state
end

emit_telemetry_event = function(event_name, fields)
    if not telemetry_logger:is_enabled() then
        return
    end

    local bg = world_model:get_bg_state() or {}
    local role_assignment = strategist.get_role_assignment and strategist:get_role_assignment() or nil
    local record = {
        type = "event",
        event = tostring(event_name or "unknown"),
        bg_type = tostring(bg.bg_type or "unknown"),
        phase = tonumber(bg.phase) or 0,
        intent = tostring(controller:get_current_id() or "none"),
        nav_state = tostring(get_nav_state()),
        role = tostring(role_assignment and role_assignment.role or "unknown"),
        role_lane = tostring(role_assignment and role_assignment.lane or "none"),
        role_overcommit = role_assignment and role_assignment.overcommit == true or false,
    }

    for k, v in pairs(fields or {}) do
        record[k] = v
    end

    telemetry_logger:append(record)
end

local function reset_match_kpi(bg_type)
    match_kpi.active = true
    match_kpi.summary_emitted = false
    match_kpi.bg_type = tostring(bg_type or "unknown")
    match_kpi.started_at = core.time()
    match_kpi.objective_interactions = 0
    match_kpi.intent_switches = 0
    match_kpi.deaths = 0
    match_kpi.stuck_time = 0
    match_kpi.stuck_since = 0
    match_kpi.last_dead = false
end

local function compute_outcome(bg, self_state)
    local winner = tonumber(bg and bg.winner) or -1
    local faction = tonumber(self_state and self_state.faction) or -1
    if winner < 0 or faction < 0 then
        return "unknown"
    end
    if winner == faction then
        return "win"
    end
    return "loss"
end

local function flush_stuck_timer()
    if match_kpi.stuck_since > 0 then
        local now = core.time()
        if now > match_kpi.stuck_since then
            match_kpi.stuck_time = match_kpi.stuck_time + (now - match_kpi.stuck_since)
        end
        match_kpi.stuck_since = 0
    end
end

local function emit_match_summary(bg, self_state, reason)
    if not summary_logger:is_enabled() then
        return
    end
    if not match_kpi.active or match_kpi.summary_emitted then
        return
    end

    flush_stuck_timer()
    local now = core.time()
    local summary = {
        type = "match_summary",
        reason = tostring(reason or "phase_finished"),
        bg_type = tostring(bg and bg.bg_type or match_kpi.bg_type or "unknown"),
        phase = tonumber(bg and bg.phase) or 0,
        winner = tonumber(bg and bg.winner),
        outcome = compute_outcome(bg, self_state),
        duration_secs = math.max(0, now - (match_kpi.started_at or now)),
        deaths = tonumber(match_kpi.deaths) or 0,
        stuck_time_secs = tonumber(match_kpi.stuck_time) or 0,
        objective_interactions = tonumber(match_kpi.objective_interactions) or 0,
        intent_switches = tonumber(match_kpi.intent_switches) or 0,
    }

    summary_logger:append(summary)
    core.log("[BGBOT][Telemetry] Match summary written: " .. tostring(summary_logger:get_path()))
    match_kpi.summary_emitted = true
    match_kpi.active = false
end

local function update_match_tracking(bg, self_state)
    local phase = tonumber(bg and bg.phase) or 0
    local bg_type = tostring(bg and bg.bg_type or "unknown")
    if bg_type ~= "unknown" and phase == constants.BG_PHASE.ACTION and not match_kpi.active then
        reset_match_kpi(bg_type)
    end

    if match_kpi.active and self_state then
        local dead_now = (self_state.is_dead == true) or (self_state.is_ghost == true)
        if dead_now and not match_kpi.last_dead then
            match_kpi.deaths = match_kpi.deaths + 1
        end
        match_kpi.last_dead = dead_now
    end

    if phase == constants.BG_PHASE.FINISHED then
        emit_match_summary(bg, self_state, "phase_finished")
    end

    if bg_type == "unknown" and match_kpi.active then
        emit_match_summary(bg, self_state, "left_battleground")
    end
end

local function collect_entity_debug_counts()
    local tracked_players = 0
    local flag_objects = 0
    local buff_objects = 0
    for _, ent in pairs(world_model:get_all_entities()) do
        if ent.is_player then tracked_players = tracked_players + 1 end
        if ent.is_flag_object then flag_objects = flag_objects + 1 end
        if ent.is_buff_object then buff_objects = buff_objects + 1 end
    end
    return tracked_players, flag_objects, buff_objects
end

local function json_escape(s)
    return tostring(s)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
end

local function json_encode_flat(record)
    local parts = {}
    for k, v in pairs(record) do
        local key = '"' .. json_escape(k) .. '"'
        local value
        local t = type(v)
        if t == "string" then
            value = '"' .. json_escape(v) .. '"'
        elseif t == "number" then
            value = tostring(v)
        elseif t == "boolean" then
            value = v and "true" or "false"
        elseif v == nil then
            value = "null"
        else
            value = '"' .. json_escape(tostring(v)) .. '"'
        end
        parts[#parts + 1] = key .. ":" .. value
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function ensure_diag_file()
    if diag.file_ready then
        return true
    end

    -- Avoid relying on `os` library (not guaranteed in plugin runtime).
    diag.file_name = DIAG_DIR .. "/telemetry.ndjson"
    local ok, err = pcall(function()
        core.create_data_folder("BGBOT")
        core.create_data_folder("BGBOT/data")
        core.create_data_folder(DIAG_DIR)

        local read_ok, existing = pcall(core.read_data_file, diag.file_name)
        if read_ok and existing and existing ~= "" then
            diag.buffer = existing
        else
            core.create_data_file(diag.file_name)
            diag.buffer = ""
        end
    end)

    if not ok then
        diag.last_error = tostring(err)
        return false
    end

    diag.file_ready = true
    diag.last_error = ""
    return true
end

local function append_diag_record(record)
    if not diag.enabled then
        return false
    end
    if not ensure_diag_file() then
        return false
    end

    record.time = record.time or core.time()
    diag.buffer = diag.buffer .. json_encode_flat(record) .. "\n"
    
    -- Prevent O(N) memory and disk write scaling by capping buffer
    if string.len(diag.buffer) > 250000 then
        diag.buffer = string.sub(diag.buffer, -100000)
        local first_nl = string.find(diag.buffer, "\n")
        if first_nl then
            diag.buffer = string.sub(diag.buffer, first_nl + 1)
        end
    end

    local ok, err = pcall(core.write_data_file, diag.file_name, diag.buffer)
    if not ok then
        diag.last_error = tostring(err)
        return false
    end

    diag.write_count = diag.write_count + 1
    diag.last_reason = tostring(record.reason or record.event or record.type or "record")
    diag.last_error = ""
    return true
end

local function build_diag_snapshot(reason, recommendation, intent_output)
    local now = core.time()
    local bg = world_model:get_bg_state() or {}
    local self_state = world_model:get_self()
    local counts = world_model:get_entity_counts()
    local scan = scanner:get_debug_stats()
    local tracked_players, flag_objects, buff_objects = collect_entity_debug_counts()
    local role_mode = tonumber(config.role.mode) or constants.ROLE.AUTO
    local resolved_role = WsgHelpers.resolve_role(self_state)
    local role_assignment = strategist.get_role_assignment and strategist:get_role_assignment() or nil

    local snapshot = {
        type = "snapshot",
        reason = tostring(reason or "tick"),
        tick = scan.tick_count or 0,
        bg_type = tostring(bg.bg_type or "unknown"),
        phase = tonumber(bg.phase) or 0,
        phase_source = tostring(bg.phase_source or "unknown"),
        phase_unknown_elapsed = scan.unknown_phase_elapsed or 0,
        phase_unknown_timeout = scan.unknown_phase_timeout or (constants.BG.UNKNOWN_TO_ACTION_SECS or 30),
        phase_unknown_elapsed_main = (unknown_phase_since > 0) and math.max(0, now - unknown_phase_since) or 0,
        map_id = tonumber(bg.map_id) or 0,
        ui_map_id = tonumber(bg.ui_map_id) or 0,
        bg_run_time = tonumber(bg.run_time) or 0,
        prep_active = bg.has_preparation == true,
        prep_aura_id = tonumber(bg.preparation_aura_id) or 0,
        prep_aura_name = tostring(bg.preparation_aura_name or ""),
        our_flag_state = tostring(bg.our_flag_state or "unknown"),
        their_flag_state = tostring(bg.their_flag_state or "unknown"),
        intent = tostring(controller:get_current_id() or "none"),
        rec_intent = recommendation and tostring(recommendation.intent_id or "none") or "",
        rec_score = recommendation and (tonumber(recommendation.score) or 0) or 0,
        all_scores = recommendation and recommendation.all_scores and json_encode_flat(recommendation.all_scores) or "{}",
        allies = counts.allies or 0,
        enemies = counts.enemies or 0,
        entities = counts.total or 0,
        players = tracked_players,
        flag_objects = flag_objects,
        buff_objects = buff_objects,
        scan_v_total = scan.visible_total or 0,
        scan_v_trackable = scan.visible_trackable or 0,
        scan_v_players = scan.visible_player_like or 0,
        scan_v_wsg = scan.visible_wsg_objects or 0,
        scan_v_processed = scan.visible_processed or 0,
        scan_f_total = scan.full_total or 0,
        scan_f_trackable = scan.full_trackable or 0,
        scan_f_players = scan.full_player_like or 0,
        scan_f_wsg = scan.full_wsg_objects or 0,
        scan_f_processed = scan.full_processed or 0,
        scan_f_last_tick = scan.last_full_tick or 0,
        scan_faction = scan.faction or constants.FACTION.UNKNOWN,
        nav_state = get_nav_state(),
        nav_moving = nav_is_moving == true,
        nav_repath_in = math.max(0, nav_repath_at - now),
        nav_goal_x = last_nav_goal and last_nav_goal.x or 0,
        nav_goal_y = last_nav_goal and last_nav_goal.y or 0,
        nav_goal_z = last_nav_goal and last_nav_goal.z or 0,
        role_mode = role_mode,
        role_resolved = resolved_role,
        role_assignment = tostring(role_assignment and role_assignment.role or "unknown"),
        role_lane = tostring(role_assignment and role_assignment.lane or "none"),
        role_overcommit = role_assignment and role_assignment.overcommit == true or false,
    }

    if self_state and self_state.position then
        snapshot.self_x = self_state.position.x
        snapshot.self_y = self_state.position.y
        snapshot.self_z = self_state.position.z
        snapshot.self_hp_pct = self_state.health_pct or 0
        snapshot.self_power_pct = self_state.power_pct or 0
        snapshot.self_dead = self_state.is_dead == true
        snapshot.self_ghost = self_state.is_ghost == true
        snapshot.self_moving = self_state.is_moving == true
        snapshot.self_speed = self_state.movement_speed or 0
        snapshot.self_has_flag = self_state.has_flag == true
        snapshot.self_faction = self_state.faction or constants.FACTION.UNKNOWN
        snapshot.self_class_id = self_state.class_id or 0
        snapshot.self_group_role = self_state.group_role or constants.GROUP_ROLE.NONE
    end

    if intent_output and intent_output.nav_goal then
        snapshot.out_goal_x = intent_output.nav_goal.x or 0
        snapshot.out_goal_y = intent_output.nav_goal.y or 0
        snapshot.out_goal_z = intent_output.nav_goal.z or 0
    end
    if intent_output then
        snapshot.out_has_interact = intent_output.interact_target ~= nil
        snapshot.out_has_face = intent_output.face_target ~= nil

        -- Deep combat micro context
        if intent_output.combat_target and intent_output.combat_target.position and self_state and self_state.position then
            snapshot.active_target_id = tostring(intent_output.combat_target.guid or "unknown")
            snapshot.active_target_dist = utils.distance_3d(self_state.position, intent_output.combat_target.position)
            snapshot.active_target_hp_pct = intent_output.combat_target.health_pct or 0
            snapshot.active_target_class = intent_output.combat_target.class_id or 0
        end

        -- Surrounding context
        local nearby_enemies = 0
        local enemies = world_model:get_enemies() or {}
        for _, enemy in ipairs(enemies) do
             if enemy.position and self_state and self_state.position and utils.distance_3d(self_state.position, enemy.position) <= 30.0 then
                 nearby_enemies = nearby_enemies + 1
             end
        end
        snapshot.enemies_in_30yd = nearby_enemies
    end

    return snapshot
end

local function maybe_emit_diag(reason, recommendation, intent_output, force)
    if not diag.enabled then
        return
    end

    local now = core.time()
    local due = diag.tick_enabled and ((now - diag.last_tick_emit) >= DIAG_INTERVAL)
    local manual = diag.snapshot_requested == true

    if not force and not due and not manual then
        return
    end

    if due then
        diag.last_tick_emit = now
    end

    local final_reason = reason or "tick"
    if manual then
        final_reason = "manual:" .. tostring(diag.snapshot_reason or reason or "snapshot")
        diag.snapshot_requested = false
    end

    append_diag_record(build_diag_snapshot(final_reason, recommendation, intent_output))
end

local function maybe_emit_transition_events(bg)
    local telemetry_enabled = telemetry_logger:is_enabled()
    if not diag.enabled and not diag.console_events and not telemetry_enabled then
        return
    end

    local bg_type = tostring((bg and bg.bg_type) or "unknown")
    local phase = tonumber((bg and bg.phase) or 0)
    local intent_id = tostring(controller:get_current_id() or "none")
    local nav_state = get_nav_state()
    local role_assignment = strategist.get_role_assignment and strategist:get_role_assignment() or nil
    local role = tostring(role_assignment and role_assignment.role or "unknown")

    local function emit_if_changed(field, old_value, new_value)
        if old_value == nil or old_value == new_value then
            return new_value
        end

        if diag.console_events then
            core.log(string.format("[BGBOT][Diag] %s %s -> %s",
                field, tostring(old_value), tostring(new_value)))
        end

        if diag.enabled then
            append_diag_record({
                type = "event",
                event = field,
                reason = "transition",
                from = tostring(old_value),
                to = tostring(new_value),
                bg_type = bg_type,
                phase = phase,
                intent = intent_id,
                nav_state = nav_state,
                role = role,
            })
        end

        if telemetry_enabled then
            emit_telemetry_event("transition_" .. tostring(field), {
                transition_field = tostring(field),
                from = tostring(old_value),
                to = tostring(new_value),
            })
        end

        if match_kpi.active and field == "intent" then
            match_kpi.intent_switches = match_kpi.intent_switches + 1
        end
        if field == "nav_state" then
            local now = core.time()
            if tostring(new_value) == "stuck" and match_kpi.stuck_since == 0 then
                match_kpi.stuck_since = now
            elseif tostring(old_value) == "stuck" and match_kpi.stuck_since > 0 then
                if now > match_kpi.stuck_since then
                    match_kpi.stuck_time = match_kpi.stuck_time + (now - match_kpi.stuck_since)
                end
                match_kpi.stuck_since = 0
            end
        end

        return new_value
    end

    diag.prev_bg_type = emit_if_changed("bg_type", diag.prev_bg_type, bg_type)
    diag.prev_phase = emit_if_changed("phase", diag.prev_phase, phase)
    diag.prev_intent = emit_if_changed("intent", diag.prev_intent, intent_id)
    diag.prev_nav_state = emit_if_changed("nav_state", diag.prev_nav_state, nav_state)
    diag.prev_role = emit_if_changed("role", diag.prev_role, role)
end

----------------------------------------------------------------------
-- Main Update Loop
----------------------------------------------------------------------

core.register_on_update_callback(function()
    -- Sync debug flags from menu
    config.debug.log_perception  = menu_elements.log_perception:get_state()
    config.debug.log_world_model = menu_elements.log_wm:get_state()
    config.debug.log_intent      = menu_elements.log_intent:get_state()
    config.debug.log_combat      = menu_elements.log_combat:get_state()
    config.debug.log_nav         = menu_elements.log_nav:get_state()
    config.role.mode             = combo_index_to_role_mode(menu_elements.role_mode:get())
    config.wsg.enable_buff_pickups = menu_elements.enable_buffs:get_state()
    config.bg.force_action_phase = menu_elements.force_action_phase:get_state()
    config.enabled               = menu_elements.enabled:get_state()
    diag.enabled                 = menu_elements.diag_enabled:get_state() or diag.external_enabled
    diag.tick_enabled            = menu_elements.diag_tick:get_state()
    diag.console_events          = menu_elements.diag_console:get_state()
    local telemetry_enabled = config.telemetry and config.telemetry.enabled == true
    telemetry_logger:set_enabled(telemetry_enabled)
    summary_logger:set_enabled(telemetry_enabled)

    if diag.enabled then
        ensure_diag_file()
    end

    if not config.enabled then
        maybe_emit_diag("return:disabled", nil, nil, false)
        return
    end

    local local_player = core.object_manager.get_local_player()
    local local_valid = false
    if local_player and local_player.is_valid then
        local ok_valid, valid = pcall(function()
            return local_player:is_valid()
        end)
        local_valid = ok_valid and valid == true
    end
    if not local_valid then
        maybe_emit_diag("return:no_local_player", nil, nil, false)
        return
    end

    local now = core.time()

    ----------------------------------------------------------------
    -- 1. Perception: scan world → write to World Model
    ----------------------------------------------------------------
    scanner:tick()

    ----------------------------------------------------------------
    -- 2. World Model: finalize snapshot (evict stale, decay confidence)
    ----------------------------------------------------------------
    world_model:finalize()

    ----------------------------------------------------------------
    -- Auto-detect BG module from bg_type (multi-BG support)
    ----------------------------------------------------------------
    local bg = world_model:get_bg_state()
    if bg.bg_type ~= active_bg_type then
        active_bg_type = bg.bg_type
        local module = BG_MODULES[active_bg_type] or nil
        strategist:set_bg_module(module)
        if config.debug.log_intent then
            core.log(string.format("[BGBOT] BG module switched: bg_type=%s module=%s",
                tostring(active_bg_type),
                module and (module.id or "set") or "nil"
            ))
        end
    end

    if bg.bg_type ~= "unknown"
        and config.bg.force_action_phase
        and not bg.has_preparation
        and (bg.phase == nil or bg.phase == 0) then
        bg.phase = constants.BG_PHASE.ACTION
        bg.phase_source = "forced_menu"
        world_model:update_bg_state(bg)
        bg = world_model:get_bg_state()
    end

    if bg.bg_type ~= "unknown"
        and not bg.has_preparation
        and (bg.phase == nil or bg.phase == 0) then
        if unknown_phase_since == 0 then
            unknown_phase_since = now
        end

        local timeout_secs = math.max(1, tonumber(config.bg.unknown_to_action_secs)
            or constants.BG.UNKNOWN_TO_ACTION_SECS or 30)
        if (now - unknown_phase_since) >= timeout_secs then
            bg.phase = constants.BG_PHASE.ACTION
            bg.phase_source = "main_unknown_timeout"
            world_model:update_bg_state(bg)
            bg = world_model:get_bg_state()
        end
    else
        unknown_phase_since = 0
    end

    maybe_emit_transition_events(bg)
    local self_state = world_model:get_self()
    update_match_tracking(bg, self_state)

    if bg.bg_type == "unknown" then
        if WsgHelpers and WsgHelpers.reset_runtime_state then
            WsgHelpers.reset_runtime_state()
        end
        stop_nav("unknown_bg")
        maybe_emit_diag("return:unknown_bg", nil, nil, false)
        return
    end

    if (bg.phase or 0) <= 0 and not config.bg.allow_unknown_phase_action then
        stop_nav("phase_unknown")
        maybe_emit_diag("return:phase_unknown", nil, nil, false)
        return
    end

    ----------------------------------------------------------------
    -- Phase gates
    ----------------------------------------------------------------
    if bg.phase == constants.BG_PHASE.PREP then
        if WsgHelpers and WsgHelpers.reset_runtime_state then
            WsgHelpers.reset_runtime_state()
        end
        stop_nav("prep_phase")
        maybe_emit_diag("return:prep_phase", nil, nil, false)
        return
    end

    if bg.phase == constants.BG_PHASE.FINISHED then
        if WsgHelpers and WsgHelpers.reset_runtime_state then
            WsgHelpers.reset_runtime_state()
        end
        stop_nav("finished_phase")
        maybe_emit_diag("return:finished_phase", nil, nil, false)
        return
    end

    ----------------------------------------------------------------
    -- Death handling
    ----------------------------------------------------------------
    if not self_state then
        maybe_emit_diag("return:no_self_state", nil, nil, false)
        return
    end

    if self_state.is_dead or self_state.is_ghost then
        stop_nav("dead_or_ghost")
        if self_state.is_dead and not is_waiting_resurrect then
            death_release_at = now + constants.HUMAN.DEATH_RELEASE_MIN
                + (math.random() * (constants.HUMAN.DEATH_RELEASE_MAX - constants.HUMAN.DEATH_RELEASE_MIN))
            is_waiting_resurrect = true

            if config.debug.log_intent then
                core.log("[BGBOT] Died. Will release in " ..
                    string.format("%.1f", death_release_at - now) .. "s")
            end
        end

        if is_waiting_resurrect and now >= death_release_at and self_state.is_dead then
            local released = safe_core_input_call("release_spirit")
            if released and config.debug.log_intent then
                core.log("[BGBOT] Released spirit.")
            end
        end

        maybe_emit_diag("return:dead_or_ghost", nil, nil, false)
        return
    end

    -- Post-resurrect: clear death state, reset confidence
    if is_waiting_resurrect then
        is_waiting_resurrect = false
        world_model:reset_confidence()
        last_nav_goal = nil   -- force fresh nav request
        if config.debug.log_intent then
            core.log("[BGBOT] Resurrected. Confidence reset.")
        end
        maybe_emit_diag("return:post_resurrect", nil, nil, false)
        return  -- Skip one frame to let perception rebuild
    end

    -- Emergency intent overrides for critical state transitions.
    if self_state.health_pct and self_state.health_pct <= constants.COMBAT.CRITICAL_HEALTH_PCT then
        if intent_registry.retreat and controller:get_current_id() ~= "retreat" then
            controller:force_emergency(intent_registry.retreat, 999)
        end
    end

    -- WSG-specific: emergency flag-carry intent override
    if bg.bg_type == "wsg" then
        local self_flag_aura = 0
        if WsgHelpers and WsgHelpers.get_flag_aura_id then
            self_flag_aura = WsgHelpers.get_flag_aura_id(local_player)
        end
        local has_enemy_flag = false
        if WsgHelpers and WsgHelpers.has_enemy_flag_aura then
            has_enemy_flag = WsgHelpers.has_enemy_flag_aura(local_player, self_state)
        else
            has_enemy_flag = self_flag_aura ~= 0
        end
        if not has_enemy_flag and self_state.has_flag and WsgHelpers and WsgHelpers.get_team_flag_auras then
            local _, enemy_flag_aura = WsgHelpers.get_team_flag_auras(self_state)
            if enemy_flag_aura == 0 then
                has_enemy_flag = true
            end
        end
        if has_enemy_flag and intent_registry.carry_flag and controller:get_current_id() ~= "carry_flag" then
            controller:force_emergency(intent_registry.carry_flag, 998)
        end
    end

    ----------------------------------------------------------------
    -- Nav stuck penalty detection (SentinelNavClient get_state/get_full_state pattern)
    ----------------------------------------------------------------
    local nav_client_check = _G.SentinelNavClient and _G.SentinelNavClient.client
    if nav_client_check then
        local check_state, check_full = resolve_nav_state(nav_client_check)
        if check_state == "stuck" and now > nav_stuck_penalty_until then
            nav_stuck_penalty_until = now + (constants.NAV_STUCK.PENALTY_DURATION or 15.0)
            nav_stuck_intent_id = controller:get_current_id()
            register_nav_failure(nav_stuck_intent_id, "nav_recovering_stuck")
            if config.debug.log_nav then
                core.log(string.format("[BGBOT][Nav] Stuck detected (full=%s), penalty on '%s' for %.0fs",
                    tostring(check_full), tostring(nav_stuck_intent_id),
                    constants.NAV_STUCK.PENALTY_DURATION or 15.0))
            end
        end
    end

    ----------------------------------------------------------------
    -- 3. Strategist: score intents
    ----------------------------------------------------------------
    local recommendation = strategist:evaluate(world_model)

    -- Apply stuck penalty: halve the score of the intent that got stuck
    if recommendation and nav_stuck_penalty_until > now and nav_stuck_intent_id then
        if recommendation.intent_id == nav_stuck_intent_id then
            recommendation.score = recommendation.score * (constants.NAV_STUCK.PENALTY_MULTIPLIER or 0.5)
        end
    elseif nav_stuck_penalty_until > 0 and now >= nav_stuck_penalty_until then
        -- Penalty expired, reset
        nav_stuck_penalty_until = 0
        nav_stuck_intent_id = nil
    end

    ----------------------------------------------------------------
    -- 4. Intent Controller: gate switches
    ----------------------------------------------------------------
    local active_intent = controller:process(recommendation)

    -- Ensure intent is entered
    if active_intent and not active_intent._active then
        active_intent:enter(world_model)
    end

    ----------------------------------------------------------------
    -- 5. Active Intent: tick (produces nav goal)
    ----------------------------------------------------------------
    local intent_output = active_intent:tick(world_model)
    local intent_context = active_intent.get_context and active_intent:get_context() or nil

    ----------------------------------------------------------------
    -- 6. Combat Micro + Action Arbiter + Humanization
    ----------------------------------------------------------------
    local combat_output = combat_micro:tick(world_model, intent_context)
    local resolved_output = action_arbiter:resolve(intent_output, combat_output, world_model)
    local final_output = humanization:apply(resolved_output, world_model, controller:get_current_id())

    ----------------------------------------------------------------
    -- 7. Execution (throttled, goal-change gated)
    ----------------------------------------------------------------
    if final_output and final_output.stop_attack then
        safe_core_input_call("stop_attack")
    end

    if final_output and final_output.combat_target then
        safe_core_input_call("set_target", final_output.combat_target)
    end

    if final_output and final_output.face_target then
        local face_target = final_output.face_target
        local face_type = type(face_target)
        local face_valid = false
        if (face_type == "table" or face_type == "userdata") and face_target.is_valid then
            local ok_valid, valid = pcall(function()
                return face_target:is_valid()
            end)
            face_valid = ok_valid and valid == true
        end

        if face_valid then
            safe_core_input_call("set_target", face_target)
            local ok_pos, fp = pcall(function()
                return face_target:get_position()
            end)
            if ok_pos and fp then
                safe_core_input_call("look_at", { x = fp.x, y = fp.y, z = fp.z })
            end
        elseif face_type == "table" and face_target.x and face_target.y and face_target.z then
            safe_core_input_call("look_at", face_target)
        end
    end

    if final_output and final_output.interact_target
        and (now - last_interact_at) >= constants.WSG.INTERACT_COOLDOWN then
        local it = final_output.interact_target
        local it_type = type(it)
        local it_valid = false
        if (it_type == "table" or it_type == "userdata") and it.is_valid then
            local ok_valid, valid = pcall(function()
                return it:is_valid()
            end)
            it_valid = ok_valid and valid == true
        end

        if it_valid then
            local lp = core.object_manager.get_local_player()
            local can_interact = false
            local lp_valid = false
            if lp and lp.is_valid then
                local ok_lp_valid, lp_is_valid = pcall(function()
                    return lp:is_valid()
                end)
                lp_valid = ok_lp_valid and lp_is_valid == true
            end
            if lp_valid then
                local ok_lp, lp_pos = pcall(function()
                    return lp:get_position()
                end)
                local ok_it, it_pos = pcall(function()
                    return it:get_position()
                end)
                local ok_still_valid, still_valid = pcall(function()
                    return it:is_valid()
                end)
                if ok_lp and ok_it and lp_pos and it_pos and ok_still_valid and still_valid then
                    local interact_dist = (constants.HUMAN.FLAG_INTERACT_RANGE or 5.0) + 2.0
                    can_interact = utils.distance_3d(lp_pos, it_pos) <= interact_dist
                end
            end

            if can_interact then
                -- Avoid dual-fire on objective objects; some servers/client builds
                -- are unstable when both interact APIs are called back-to-back.
                local ok, err = safe_core_input_call("interact_with_object", it)

                if not ok then
                    local used = safe_core_input_call("use_object", it)
                    if config.debug.log_intent then
                        if used then
                            core.log("[BGBOT][Intent] interact_with_object failed; used fallback use_object.")
                        else
                            core.log("[BGBOT][Intent] interact_with_object failed: " .. tostring(err))
                        end
                    end
                end

                last_interact_at = now
                if match_kpi.active then
                    match_kpi.objective_interactions = match_kpi.objective_interactions + 1
                end
                local objective_kind = "unknown"
                local objective_record = world_model:get_entity(it)
                if objective_record and objective_record.object_kind then
                    objective_kind = tostring(objective_record.object_kind)
                end
                emit_telemetry_event("objective_interact", {
                    objective_kind = objective_kind,
                    objective_handle = tostring(it),
                })
                if config.debug.log_intent then
                    core.log("[BGBOT][Intent] Interact with objective")
                end
            end
        end
    end

    if final_output and final_output.nav_goal then
        try_nav_move(final_output.nav_goal)
    else
        -- Prevent stale movement when an intent intentionally outputs no nav goal.
        stop_nav("intent_no_goal")
    end

    maybe_emit_transition_events(bg)
    maybe_emit_diag("tick:active", recommendation, final_output or intent_output, false)
end)

----------------------------------------------------------------------
-- Menu  (persistent elements, correct API signatures)
----------------------------------------------------------------------

core.register_on_render_menu_callback(function()
    local color = require("common/color")

    menu_elements.header:render("BGBOT v0.1.0", color.new(187, 134, 252, 255))

    -- Enable toggle
    menu_elements.enabled:render("Enabled", "Enable/Disable BGBOT")
    menu_elements.role_mode:render("Role Profile", ROLE_OPTIONS, "Auto or forced behavior profile")
    menu_elements.enable_buffs:render("Buff Detours", "Detour to WSG buffs when safe")
    menu_elements.force_action_phase:render("Force Action Phase", "Treat unknown phase as action when Preparation aura is absent")

    -- Status line
    local bg = world_model:get_bg_state()
    local self_state = world_model:get_self()
    local intent_id = controller:get_current_id()
    local counts = world_model:get_entity_counts()
    local scan = scanner:get_debug_stats()
    local role_mode = tonumber(config.role.mode) or constants.ROLE.AUTO
    local resolved_role = WsgHelpers.resolve_role(self_state)
    local tracked_players, flag_objects, buff_objects = collect_entity_debug_counts()
    local scanner_unknown_elapsed = tonumber(scan.unknown_phase_elapsed) or 0
    local scanner_unknown_timeout = math.max(1, tonumber(scan.unknown_phase_timeout)
        or tonumber(config.bg.unknown_to_action_secs) or constants.BG.UNKNOWN_TO_ACTION_SECS or 30)
    local main_unknown_elapsed = (unknown_phase_since > 0) and math.max(0, core.time() - unknown_phase_since) or 0

    menu_elements.status_header:render(
        string.format("BG: %s | Phase: %d(%s) | Role: %s->%s | Buffs: %s | FAction: %s | PrepAura: %s(%s,%s) | UPh: %.1f/%.0fs M:%.1fs | map=%s ui=%s | Intent: %s | E: %d A: %d | P: %d | FObj: %d BObj: %d",
            bg.bg_type, bg.phase or 0,
            tostring(bg.phase_source or "n/a"),
            WsgHelpers.role_name(role_mode), WsgHelpers.role_name(resolved_role),
            tostring(config.wsg.enable_buff_pickups),
            tostring(config.bg.force_action_phase),
            tostring(bg.has_preparation), tostring(bg.preparation_aura_id or 0),
            tostring(bg.preparation_aura_name or ""),
            scanner_unknown_elapsed, scanner_unknown_timeout, main_unknown_elapsed,
            tostring(bg.map_id), tostring(bg.ui_map_id),
            intent_id, counts.enemies, counts.allies, tracked_players, flag_objects, buff_objects),
        color.new(0, 255, 0, 255)
    )

    local scan_color = color.new(180, 220, 255, 255)
    if scan.visible_player_like == 0 and scan.full_player_like == 0 then
        scan_color = color.new(255, 140, 140, 255)
    end

    menu_elements.scan_header:render(
        string.format("Scan V[t=%d tr=%d pl=%d wsg=%d upd=%d] | F[t=%d tr=%d pl=%d wsg=%d upd=%d at=%d] | fac=%d | uph=%.1fs",
            scan.visible_total, scan.visible_trackable, scan.visible_player_like, scan.visible_wsg_objects, scan.visible_processed,
            scan.full_total, scan.full_trackable, scan.full_player_like, scan.full_wsg_objects, scan.full_processed, scan.last_full_tick,
            scan.faction, scanner_unknown_elapsed),
        scan_color
    )

    local nav_client = _G.SentinelNavClient and _G.SentinelNavClient.client
    local nav_state = get_nav_state(nav_client)
    local goal_text = "-"
    if last_nav_goal then
        goal_text = string.format("%.0f,%.0f,%.0f", last_nav_goal.x, last_nav_goal.y, last_nav_goal.z)
    end
    local repath_in = math.max(0, nav_repath_at - core.time())

    local nav_color = color.new(255, 214, 153, 255)
    if nav_state == "stuck" or nav_state == "failed" then
        nav_color = color.new(255, 140, 140, 255)
    end

    menu_elements.nav_header:render(
        string.format("Nav state=%s moving=%s repath=%.1fs goal=%s",
            nav_state, tostring(nav_is_moving), repath_in, goal_text),
        nav_color
    )

    -- Debug toggles
    menu_elements.debug_node:render("Debug Options", function()
        menu_elements.log_perception:render("Perception",  "Log perception tick info")
        menu_elements.log_wm:render("World Model", "Log world model state")
        menu_elements.log_intent:render("Intent",      "Log intent switches")
        menu_elements.log_combat:render("Combat",      "Log combat decisions")
        menu_elements.log_nav:render("Navigation", "Log nav move_to calls")
    end)

    menu_elements.diag_node:render("Diagnostics Capture", function()
        menu_elements.diag_enabled:render("Write NDJSON", "Write structured snapshots to scripts_data/BGBOT/data/debug")
        menu_elements.diag_tick:render("Tick Snapshots", "Capture once per second while enabled")
        menu_elements.diag_console:render("Console Events", "Log phase/nav/intent transitions to console")

        menu_elements.diag_snapshot:render("Snapshot Now", "Force one immediate snapshot record")
        if menu_elements.diag_snapshot:is_clicked() then
            diag.snapshot_requested = true
            diag.snapshot_reason = "menu_button"
        end

        menu_elements.diag_status:render(
            string.format("Records=%d Last=%s", diag.write_count, tostring(diag.last_reason or "none")),
            color.new(180, 220, 255, 255)
        )
        menu_elements.diag_file:render(
            "File: " .. tostring(diag.file_name or "(enable capture to create file)"),
            color.new(180, 220, 255, 255)
        )
        if diag.last_error and diag.last_error ~= "" then
            menu_elements.diag_error:render("Error: " .. tostring(diag.last_error), color.new(255, 140, 140, 255))
        end
    end)
end)

----------------------------------------------------------------------
-- External debug hooks (PS/injection-friendly)
----------------------------------------------------------------------

_G.BGBOT = _G.BGBOT or {}

---Enable/disable diagnostics capture without using menu.
---@param state boolean
---@return boolean enabled
function _G.BGBOT.debug_capture_set(state)
    diag.external_enabled = state and true or false
    if diag.external_enabled then
        ensure_diag_file()
    end
    return diag.external_enabled
end

---Request an immediate snapshot on the next update tick.
---@param reason string|nil
---@return boolean
function _G.BGBOT.debug_snapshot(reason)
    if not diag.enabled and not diag.external_enabled then
        diag.external_enabled = true
    end
    if diag.external_enabled then
        ensure_diag_file()
    end
    diag.snapshot_requested = true
    diag.snapshot_reason = tostring(reason or "external_call")
    return true
end

---Get active diagnostics file path (creates it if needed).
---@return string|nil, string|nil
function _G.BGBOT.debug_log_file()
    if not ensure_diag_file() then
        return nil, diag.last_error
    end
    return diag.file_name, nil
end

---Get lightweight diagnostics state for external polling.
---@return table
function _G.BGBOT.debug_status()
    return {
        enabled = diag.enabled,
        external_enabled = diag.external_enabled,
        file_name = diag.file_name,
        write_count = diag.write_count,
        last_reason = diag.last_reason,
        last_error = diag.last_error,
    }
end

----------------------------------------------------------------------
-- Init log
----------------------------------------------------------------------

core.log("[BGBOT] v0.1.0 initialized. Waiting for BG context...")
