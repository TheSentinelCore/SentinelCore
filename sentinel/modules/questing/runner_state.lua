--- Sentinel Runner Cockpit — view-model (pure logic, zero Sylvannas calls).
---
--- Everything the operator UI needs is computed here so it can be tested offline; the render
--- layer (`runner_ui.lua`) stays a thin projection of this table. The split is deliberate: the
--- Sylvannas widget layer cannot be exercised outside the game, so no decision logic lives there.
---
--- Design rule: every field answers an operator question, not an internal one.
---   health    -> "do I need to intervene right now?"
---   liveness  -> "is it alive, or wedged?"   (a status-only UI hides a 40-minute hang)
---   progress  -> "is it getting anywhere, and when will it finish?"
---   blocked   -> "why is it stopped?"        (human text first, raw AST behind disclosure)
---   sync      -> "is it lying to me?"        (profile belief vs. real quest log)
---   guardrails-> "when should it stop itself?"
---   events    -> "what happened at 3am?"

local RunnerState = {}

local DEFAULT_STALL_THRESHOLD_S = 300.0  -- a wait longer than this reads STUCK, not WAITING
local DEFAULT_MAX_EVENTS = 12
local NAV_ERROR_RECENT_S = 30.0          -- a nav failure older than this is history, not a blocker
local ETA_WINDOW_MIN_SAMPLES = 3         -- below this the windowed rate is noise; use session avg

-- Execution-log event -> operator severity. Unknown events default to info rather than being
-- dropped, so a new event type can never silently vanish from triage.
local EVENT_SEVERITY = {
    action_failed = "error",
    action_retry_exhausted = "error",
    profile_failed = "error",
    condition_wait_timeout = "warn",
    action_retry = "warn",
    death_detected = "warn",
    nav_timeout = "warn",
    action_success = "info",
    action_skipped = "info",
}

local function num(v, fallback)
    return tonumber(v) or fallback
end

--- Current operation/action the executor is pointed at (nil-safe).
local function current_action(executor)
    if not executor or not executor._profile then return nil end
    local operations = executor._profile.operations
    if type(operations) ~= "table" then return nil end
    local op = operations[executor._current_operation_idx]
    if not op or type(op.actions) ~= "table" then return nil end
    return op.actions[executor._current_action_idx], op
end

--- Render a typed RuntimeCondition as operator-facing text. Falls back to the variant name so an
--- unmapped condition still says something useful instead of rendering blank.
local function humanize_condition(cond)
    if cond == nil then return nil end
    if type(cond) == "string" then return cond end
    if type(cond) ~= "table" then return tostring(cond) end

    local t, p = cond.type, cond.payload
    if t == "ObjectiveComplete" and type(p) == "table" then
        return string.format("quest %s objective %s not complete", tostring(p[1]), tostring(p[2]))
    elseif t == "QuestAccepted" then
        return string.format("quest %s not accepted yet", tostring(p))
    elseif t == "QuestCompleted" then
        return string.format("quest %s not complete", tostring(p))
    elseif t == "QuestRewarded" then
        return string.format("quest %s not turned in", tostring(p))
    elseif t == "ItemCountAtLeast" and type(p) == "table" then
        return string.format("need %s of item %s", tostring(p[2]), tostring(p[1]))
    elseif t == "HasItem" then
        return string.format("missing item %s", tostring(p))
    elseif t == "LevelAtLeast" then
        return string.format("need level %s", tostring(p))
    elseif t == "ClassIs" then
        return string.format("step is for %s only", tostring(p))
    elseif t == "Any" or t == "All" then
        return string.format("%s of %d conditions unmet", t == "Any" and "any" or "all",
            type(p) == "table" and #p or 0)
    elseif t == "Not" then
        return "negated condition unmet"
    end
    return tostring(t or "condition") .. " unmet"
end

--- Short operator-facing label for the action currently executing.
local function humanize_action(action)
    if not action then return "idle" end
    local t = action.type or "unknown"
    local p = action.payload or {}
    if t == "AcceptQuest" then
        return string.format("Accept quest %s", tostring(p.quest_id))
    elseif t == "TurnInQuest" then
        return string.format("Turn in quest %s", tostring(p.quest_id))
    elseif t == "Travel" then
        return string.format("Travel to %s", tostring(p.destination or "destination"))
    elseif t == "Kill" then
        local n = type(p.creature_entries) == "table" and #p.creature_entries or 0
        return string.format("Kill target (%d entries)", n)
    elseif t == "Condition" then
        return "Gate: " .. (humanize_condition(p.condition) or "condition")
    elseif t == "Vendor" then
        return "Vendor"
    elseif t == "Train" then
        return "Train"
    end
    return t
end

--- Operator-facing sentence for a faulting module.
---
--- WHY THE PHASE IS SURFACED AT ALL. `system.module_faults` carries `phase` ("init" | "tick") from
--- `ModuleRegistry`, and this view-model used to reduce only `count` and `last_error` -- so a module
--- that DIED AT BOOT and one that hiccupped on a single tick both rendered as "x1". They demand
--- opposite operator responses, and the difference is not visible in the count:
---   * init -- `initialize_all` set the module SHUTDOWN and `initialize_module` refuses to
---     reinitialise a SHUTDOWN module. It is dead for the life of this client session; the count is
---     pinned at 1 forever and will never clear on its own. The only fix is a reload.
---   * tick -- the fault streak resets on the very next clean tick, and only three CONSECUTIVE
---     faults degrade the module. At count 1 the correct action is usually to do nothing.
--- Rendering "combat x1" for both told the operator to wait for a recovery that could never come.
---
--- The alternative -- dropping `phase` from the blackboard map because nobody read it -- was
--- rejected: the map is the ONLY channel that carries a boot death to the cockpit (the event is
--- published once, at boot, before any UI exists to subscribe), so removing the field would make
--- the two permanently indistinguishable rather than merely undistinguished.
---
--- WHAT THIS CANNOT SEE: it reports the phase the registry claimed, not the module's live state --
--- it never reads `ModuleRegistry:get_state`, so a module that was manually restarted after a boot
--- death would still read DEAD here until the map entry is replaced. An absent phase is reported as
--- unknown rather than assumed to be the milder "tick".
local function humanize_module_fault(name, count, phase)
    if phase == "init" then
        return string.format("%s DIED AT BOOT (init failed) - it will not retry, reload to recover",
            tostring(name))
    elseif phase == "tick" then
        return string.format("%s faulted on tick x%d", tostring(name), count)
    end
    return string.format("%s faulted x%d (phase unknown)", tostring(name), count)
end

--- Is the executor currently holding on a Completion-role gate?
local function waiting_info(executor, now, stall_threshold_s)
    if not executor or executor._wait_action_key == nil or executor._wait_started_at == nil then
        return false, 0, false
    end
    local waited = num(now, 0) - num(executor._wait_started_at, 0)
    if waited < 0 then waited = 0 end
    return true, waited, waited >= stall_threshold_s
end

--- Build the complete cockpit view-model.
--- All inputs are injected so this is a pure function — the UI passes live values, tests pass
--- fixtures. No `core.*` access happens here.
---@param opts table
---   executor          RuntimeProfile-like (may be nil when nothing is loaded)
---   now               current time in seconds
---   started_at        session start time
---   last_progress_at  timestamp of the last forward progress
---   stall_threshold_s wait duration that promotes WAITING -> STUCK
---   deaths            death count this session
---   tracked_quests    array of quest ids the profile believes are accepted
---   quest_log         map of quest_id -> true, from the real game quest log
---   guardrails        { stop_after_deaths, stop_if_stuck_s }
---   max_events        cap on the returned event list
---   nav_error         { command, reason, at, target } from NavAdapter:get_last_error()
---   status_message    the executor's last execute() status message
---   module_faults     map module_name -> { count, phase, last_error } (system.module_faults);
---                     `phase` is "init" (boot death, terminal) or "tick" (transient streak)
---   maintenance       the module's _maintenance table { state, vendor_entry, started_at }
---   paused_s          accumulated paused time, excluded from elapsed/ETA
---   recent_completions ascending timestamps of the last few step completions
function RunnerState.build(opts)
    opts = opts or {}
    local executor = opts.executor
    local now = num(opts.now, 0)
    local started_at = num(opts.started_at, now)
    local stall_threshold_s = num(opts.stall_threshold_s, DEFAULT_STALL_THRESHOLD_S)
    local max_events = num(opts.max_events, DEFAULT_MAX_EVENTS)
    local guardrail_cfg = opts.guardrails or {}
    local deaths = num(opts.deaths, 0)

    local is_waiting, waited_s, is_stalled = waiting_info(executor, now, stall_threshold_s)

    -- ---- health -----------------------------------------------------------------
    local status, is_alarm = "IDLE", false
    if executor then
        local s = executor._state
        if s == "failed" then
            status, is_alarm = "FAILED", true
        elseif s == "finished" then
            status, is_alarm = "FINISHED", false
        elseif s == "ghost" then
            status, is_alarm = "GHOST", true
        elseif s == "navigating" then
            status, is_alarm = "NAVIGATING", false
        elseif is_stalled then
            status, is_alarm = "STUCK", true
        elseif is_waiting then
            status, is_alarm = "WAITING", false
        else
            status, is_alarm = "RUNNING", false
        end
    end

    -- ---- progress ---------------------------------------------------------------
    local total, step = 0, 0
    if executor and executor._profile and type(executor._profile.operations) == "table" then
        total = #executor._profile.operations
        step = num(executor._current_operation_idx, 0)
    end
    local completed = step > 0 and (step - 1) or 0
    local pct = total > 0 and math.floor((completed / total) * 100) or 0
    -- Paused time is excluded: a run paused overnight must not report a 9-hour session or a
    -- diluted steps/hour.
    local elapsed = now - started_at - num(opts.paused_s, 0)
    if elapsed < 0 then elapsed = 0 end
    local remaining = total - completed
    local eta_s, per_step, steps_per_hour = nil, nil, nil
    -- A windowed rate over the recent completions beats the whole-session average: early slow
    -- steps (or one long detour) otherwise poison the ETA for the rest of the run.
    local window = opts.recent_completions
    if type(window) == "table" and #window >= ETA_WINDOW_MIN_SAMPLES
        and num(window[#window], 0) > num(window[1], 0) then
        per_step = (num(window[#window], 0) - num(window[1], 0)) / (#window - 1)
        steps_per_hour = 3600 / per_step
        if remaining > 0 then eta_s = math.floor(per_step * remaining) end
    elseif completed > 0 and elapsed > 0 then
        per_step = elapsed / completed
        steps_per_hour = (completed / elapsed) * 3600
        if remaining > 0 then eta_s = math.floor(per_step * remaining) end
    end

    -- ---- current action & blocked reason (union: failed > ghost > nav > gate) ----
    local action = current_action(executor)
    local nav_error = opts.nav_error
    local nav_error_recent = nav_error ~= nil
        and (now - num(nav_error.at, now)) <= NAV_ERROR_RECENT_S
    local blocked = { is_blocked = false }
    if executor and executor._state == "failed" then
        local failures = num(executor._consecutive_failures, 0)
        blocked = {
            is_blocked = true,
            kind = "failed",
            human_reason = string.format("profile failed after %d consecutive failures", failures),
            detail = { consecutive_failures = failures, message = opts.status_message },
            severity = "alarm",
        }
    elseif executor and executor._state == "ghost" then
        blocked = {
            is_blocked = true,
            kind = "ghost",
            human_reason = "dead - recovering to corpse",
            detail = { ghost_elapsed = now - num(executor._ghost_start_time, now) },
            severity = "alarm",
        }
    elseif nav_error_recent then
        blocked = {
            is_blocked = true,
            kind = "nav",
            human_reason = string.format("navigation failed: %s", tostring(nav_error.reason)),
            detail = { command = nav_error.command, reason = nav_error.reason,
                       target = nav_error.target, at = nav_error.at },
            severity = "alarm",
        }
    elseif is_waiting then
        local cond = action and action.payload and action.payload.condition or nil
        blocked = {
            is_blocked = true,
            kind = "gate",
            waited_s = waited_s,
            human_reason = humanize_condition(cond) or "waiting on a completion gate",
            raw_condition = cond,
            severity = "warn",
        }
    end

    -- ---- health severity (the only thing the render layer switches on) -----------
    local maintenance_in = opts.maintenance or {}
    local maintenance = {
        active = maintenance_in.state ~= nil and maintenance_in.state ~= "idle",
        phase = maintenance_in.state,
        vendor_entry = maintenance_in.vendor_entry,
        started_at = maintenance_in.started_at,
    }
    -- Worst faulting module (highest count; name breaks ties deterministically).
    local module_fault = nil
    for name, info in pairs(opts.module_faults or {}) do
        local count = num(info and info.count, 0)
        if count > 0 and (module_fault == nil or count > module_fault.count
            or (count == module_fault.count and name < module_fault.name)) then
            module_fault = {
                name = name,
                count = count,
                phase = info.phase,
                last_error = info.last_error,
                human_text = humanize_module_fault(name, count, info.phase),
            }
        end
    end
    local severity
    if status == "FAILED" or status == "GHOST" or status == "STUCK"
        or module_fault ~= nil or blocked.kind == "nav" then
        severity = "alarm"
    elseif status == "WAITING" or status == "NAVIGATING" or maintenance.active then
        severity = "warn"
    else
        severity = "ok"
    end
    is_alarm = severity == "alarm"

    -- ---- quest-log desync --------------------------------------------------------
    local tracked = opts.tracked_quests or {}
    local qlog = opts.quest_log or {}
    local missing = {}
    local in_log = 0
    for _, qid in ipairs(tracked) do
        if qlog[qid] then in_log = in_log + 1 else missing[#missing + 1] = qid end
    end
    local sync = {
        tracked = #tracked,
        in_log = in_log,
        missing = missing,
        ok = #missing == 0,
    }

    -- ---- guardrails --------------------------------------------------------------
    local tripped, reason = false, nil
    local death_limit = guardrail_cfg.stop_after_deaths
    if death_limit and deaths >= death_limit then
        tripped = true
        reason = string.format("death limit reached (%d/%d)", deaths, death_limit)
    end
    local stuck_limit = guardrail_cfg.stop_if_stuck_s
    if not tripped and stuck_limit and is_waiting and waited_s >= stuck_limit then
        tripped = true
        reason = string.format("stuck for %ds (limit %ds)", math.floor(waited_s), stuck_limit)
    end

    -- ---- events (newest first, capped, severity-tagged) --------------------------
    local events = {}
    local log = (executor and executor._execution_log) or {}
    for i = #log, 1, -1 do
        if #events >= max_events then break end
        local e = log[i]
        events[#events + 1] = {
            t = e.timestamp,
            sev = EVENT_SEVERITY[e.event] or "info",
            event = e.event,
            operation = e.operation,
            text = e.msg or e.action_type or e.event,
        }
    end

    return {
        health = {
            status = status,
            severity = severity,
            is_alarm = is_alarm,
            profile_loaded = executor ~= nil,
            message = opts.status_message,
            module_fault = module_fault,
        },
        liveness = {
            session_elapsed_s = elapsed,
            time_in_step_s = is_waiting and waited_s or 0,
            time_since_progress_s = opts.last_progress_at and (now - num(opts.last_progress_at, now)) or nil,
            is_stalled = is_stalled,
        },
        progress = {
            step = step,
            total = total,
            pct = pct,
            eta_s = eta_s,
            seconds_per_step = per_step,
            steps_per_hour = steps_per_hour,
        },
        current = {
            action_type = action and action.type or nil,
            human_text = humanize_action(action),
        },
        blocked = blocked,
        maintenance = maintenance,
        recovery = (executor and executor._state == "ghost")
            and { ghost_elapsed = now - num(executor._ghost_start_time, now) } or nil,
        sync = sync,
        counters = {
            deaths = deaths,
            retries = executor and num(executor._current_action_retries, 0) or 0,
            failures = executor and num(executor._consecutive_failures, 0) or 0,
        },
        guardrails = {
            stop_after_deaths = death_limit,
            stop_if_stuck_s = stuck_limit,
            tripped = tripped,
            reason = reason,
        },
        events = events,
    }
end

-- Exposed for the render layer and for tests that assert operator-facing wording.
RunnerState.humanize_condition = humanize_condition
RunnerState.humanize_action = humanize_action

-- Exposed so tests can assert every severity key still has a real emitter (E6): a key with
-- no emitter is dead, permanently-info-defaulted noise waiting to happen again.
RunnerState.EVENT_SEVERITY = EVENT_SEVERITY

return RunnerState
