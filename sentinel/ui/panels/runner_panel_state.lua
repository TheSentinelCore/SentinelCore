-- sentinel/ui/panels/runner_panel_state.lua
-- The Runner panel's view-model (ADR 09b §2.1, §6 U5).
--
-- WHAT THIS FILE IS AND IS NOT
-- ---------------------------
-- `modules/questing/runner_state.lua` already answers every OPERATOR question — health, liveness,
-- progress and ETA, blocked reason, quest-log desync, guardrails, events. None of that is
-- recomputed here and none of it may be. This file answers the PANEL questions that snapshot
-- cannot: what is drawn, where, at what size, in which semantic token, which control can act right
-- now, and what a click on it means.
--
-- The output is a flat, ordered list of draw items. `runner.lua` walks it and dispatches by kind,
-- and it contains no branch at all — `tests/ui/test_runner_panel.lua` asserts that structurally,
-- because a branch inside a render callback cannot be reached by any offline test (ADR 09b §2.1).
-- Every decision the panel makes therefore has to be made here, where a test can see it.
--
-- WHY THE PANEL IS SPARSE WHEN NOTHING IS WRONG
-- --------------------------------------------
-- An operator opens this panel because they suspect the bot is stuck. A layout that shows blocked
-- reason, desync, retries, guardrails and events at equal weight all the time makes the one field
-- they came for exactly as loud as the eleven they did not. So: a healthy run draws a status line,
-- a progress bar and a timeline; a broken one grows a banner at a type size nothing else on the
-- panel uses, on the only filled surface on the panel.
--
-- No `core.*` access, no IO, no menu elements: this is built once per frame on the render path
-- (ADR 09b §2.4), and menu elements may only be constructed in the tick callback (§2.2).

local Theme = require("ui/theme")
local RunnerState = require("modules/questing/runner_state")

local RunnerPanelState = {}

local S, MET, LH = Theme.space, Theme.metrics, Theme.line_height

-- Mirrors the fixed character box `widgets.lua` lays out with. `window:get_text_size` exists only
-- inside a render callback, and this file has to place a right-aligned string before one exists.
local CHAR_W = 7

-- Derived from the control height rather than picked, so the transport bar keeps the same rhythm
-- as every other control in the IDE. A `Stop` button sized to its four letters would be a 59px
-- target next to a 96px one, and the row would read as ragged.
local BUTTON_MIN_W = MET.control_height * 3

local MAX_ALERTS = 3
local MAX_MISSING_QUESTS = 5

-- ============================================================================
-- Semantic vocabulary
-- ============================================================================

-- Every run state carries a glyph as well as a colour. A state that reads only as "the green one"
-- is unusable to a red-green colour-blind operator, and this window renders over arbitrary
-- scenery: against a snowfield at noon the hue is the first thing to go. The glyphs are ASCII
-- because layout maths counts bytes (`CHAR_W` above), so a multi-byte glyph would silently
-- mis-measure every string it sits in.
local STATUS_GLYPH = {
    IDLE       = "--",
    RUNNING    = ">",
    NAVIGATING = ">>",
    WAITING    = "..",
    STUCK      = "!!",
    GHOST      = "+",
    FAILED     = "X",
    FINISHED   = "OK",
}

local SEVERITY_TOKEN = { ok = "success", warn = "warning", alarm = "danger" }

-- The blocked kinds `runner_state` emits. Each gets its own mark for the same reason the statuses
-- do: "why is it stopped" must survive being read in greyscale.
local BLOCKED_GLYPH = { failed = "X", ghost = "+", nav = "!!", gate = ".." }

local EVENT_TOKEN = { error = "danger", warn = "warning", info = "text_muted" }
local EVENT_GLYPH = { error = "X", warn = "!", info = "-" }

local FILTER_ORDER = { "all", "warn", "error" }
local FILTER_LABEL = { all = "All", warn = "Warnings", error = "Errors" }

-- Guardrail limits cycle through a ladder on click rather than opening a slider. A slider is a
-- stock `core.menu` element, and stock elements must be constructed in the tick callback — a panel
-- that needed one could not be rendered by a shell that had not been told to build it first.
local DEATH_LADDER = { false, 3, 5, 10 }
local STUCK_LADDER = { false, 300, 600, 1800 }

-- ============================================================================
-- Formatting
-- ============================================================================

local function fit(text, width)
    text = tostring(text or "")
    local max_chars = math.floor((width or 0) / CHAR_W)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

---Compact H:MM:SS / MM:SS. Operators scan durations; they do not parse floats.
local function dur(seconds)
    if seconds == nil then return "--" end
    local s = math.floor(tonumber(seconds) or 0)
    if s < 0 then s = 0 end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s % 60) end
    return string.format("%02d:%02d", m, s % 60)
end

---An ETA that could not be computed says so.
---
---`runner_state` returns nil for the ETA until it has a rate to extrapolate from — a run one step
---in has none. Formatting nil through `dur` would render "00:00", which tells the operator the run
---is about to finish at the exact moment nothing is known about it.
local function eta_text(eta_s)
    if eta_s == nil then return "ETA unknown" end
    return "ETA " .. dur(eta_s)
end

local function rate_text(steps_per_hour)
    if steps_per_hour == nil then return "rate unknown" end
    return string.format("%.1f steps/hr", steps_per_hour)
end

-- ============================================================================
-- Actions
-- ============================================================================

local function next_in_ladder(ladder, current)
    for i, value in ipairs(ladder) do
        if value == current then return ladder[(i % #ladder) + 1] end
    end
    -- A limit set from somewhere other than this panel is not on the ladder. Landing on the first
    -- real value beats silently resetting the operator's setting to off.
    return ladder[2]
end

local function cycle_guardrail(model, key, ladder)
    local current = (model.view and model.view.guardrails and model.view.guardrails[key]) or false
    local guardrails = {
        stop_after_deaths = model.view and model.view.guardrails
            and model.view.guardrails.stop_after_deaths or nil,
        stop_if_stuck_s = model.view and model.view.guardrails
            and model.view.guardrails.stop_if_stuck_s or nil,
    }
    local next_value = next_in_ladder(ladder, current)
    guardrails[key] = next_value or nil
    return { kind = "set_guardrails", guardrails = guardrails }
end

-- A control either changes something the panel owns (and the module never hears about it) or it
-- issues a command the host dispatches to the questing module. Keeping both in one table is what
-- lets `runner.lua` return the result of one lookup instead of branching on the id.
local ACTIONS = {
    details    = function(model) model.show_details = not model.show_details end,
    start      = function(model) return { kind = "start", profile = model.selected_profile } end,
    pause      = function() return { kind = "pause" } end,
    resume     = function() return { kind = "resume" } end,
    stop       = function() return { kind = "stop" } end,
    skip_step  = function() return { kind = "skip_step" } end,
    rescan     = function() return { kind = "rescan" } end,
    record     = function() return { kind = "record" } end,
    ["guard:deaths"] = function(model) return cycle_guardrail(model, "stop_after_deaths", DEATH_LADDER) end,
    ["guard:stuck"]  = function(model) return cycle_guardrail(model, "stop_if_stuck_s", STUCK_LADDER) end,
}

---Fold an activated control id into the model, returning the command the host must dispatch.
---@return table|nil command { kind, ... }
function RunnerPanelState.reduce(model, action_id)
    if not model or not action_id then return nil end

    local filter = tostring(action_id):match("^filter:(.+)$")
    if filter then
        model.event_filter = filter
        return nil
    end

    local action = ACTIONS[action_id]
    if not action then return nil end
    return action(model)
end

---The panel-local state the shell owns between frames.
function RunnerPanelState.new_model(opts)
    opts = opts or {}
    return {
        view = opts.view,
        profiles = opts.profiles or {},
        selected_profile = opts.selected_profile,
        paused = opts.paused or false,
        event_filter = opts.event_filter or "all",
        show_details = opts.show_details or false,
    }
end

-- ============================================================================
-- Plan
-- ============================================================================

local ZERO_BOUNDS = { x = 0, y = 0, w = 0, h = 0 }

local function event_passes(event, filter)
    if filter == "error" then return event.sev == "error" end
    if filter == "warn" then return event.sev == "error" or event.sev == "warn" end
    return true
end

---Alerts, worst first. `table.sort` is not stable in LuaJIT, so the buckets are filled in
---declaration order and concatenated: two alarms must not swap places between frames, or the panel
---flickers between two equally-true readings of the same problem.
local function collect_alerts(view, model)
    local alarms, warnings = {}, {}
    local function add(alert)
        local bucket = (alert.severity == "alarm") and alarms or warnings
        bucket[#bucket + 1] = alert
    end

    local blocked = view.blocked
    if blocked.is_blocked then
        local lines = {}
        if blocked.waited_s then
            lines[#lines + 1] = "waiting " .. dur(blocked.waited_s)
        end
        if blocked.detail and blocked.detail.message then
            lines[#lines + 1] = tostring(blocked.detail.message)
        end
        if model.show_details and blocked.raw_condition then
            lines[#lines + 1] = "condition " .. tostring(blocked.raw_condition.type)
        end
        add({
            severity = blocked.severity or "warn",
            glyph = BLOCKED_GLYPH[blocked.kind] or "!!",
            title = "BLOCKED - " .. tostring(blocked.human_reason),
            lines = lines,
            -- The raw AST sits behind disclosure, never in the operator's face: it is what the
            -- author needs when the human sentence is not enough, and noise otherwise.
            action_id = blocked.raw_condition and "details" or nil,
            action_label = model.show_details and "Hide raw" or "Show raw",
        })
    end

    local fault = view.health.module_fault
    if fault then
        add({
            severity = "alarm",
            glyph = "X",
            title = "MODULE FAULT - " .. tostring(fault.human_text),
            lines = fault.last_error and { tostring(fault.last_error) } or {},
        })
    end

    if view.guardrails.tripped then
        add({
            severity = "warn",
            glyph = "!!",
            title = "GUARDRAIL TRIPPED - " .. tostring(view.guardrails.reason),
            lines = {},
        })
    end

    local out = {}
    for _, alert in ipairs(alarms) do out[#out + 1] = alert end
    for _, alert in ipairs(warnings) do out[#out + 1] = alert end
    while #out > MAX_ALERTS do table.remove(out) end
    return out
end

---Build the complete draw plan for `bounds`.
---@param model table { view, profiles, selected_profile, paused, event_filter, show_details }
---@param bounds table { x, y, w, h }
function RunnerPanelState.build(model, bounds)
    model = model or RunnerPanelState.new_model()
    bounds = bounds or ZERO_BOUNDS
    local view = model.view or RunnerState.build({})
    local health = view.health

    local items, controls = {}, {}
    local plan = {
        items = items,
        controls = controls,
        alerts = {},
        progress = { visible = false, eta_s = view.progress.eta_s, track_w = 0, fill_w = 0 },
        event_rows = 0,
        is_empty = not health.profile_loaded,
    }

    local function push(item) items[#items + 1] = item; return item end
    local function text(x, y, role, token, str)
        return push({
            kind = "text", x = x, y = y, font = Theme.font[role], token = token,
            alpha = Theme.interaction.resting.text, text = str,
        })
    end
    local function rect(b, token, alpha, rounding)
        return push({
            kind = "rect", bounds = b, token = token,
            alpha = alpha or Theme.interaction.active.fill, rounding = rounding or Theme.radius.none,
        })
    end

    local pad = S.lg
    local x = bounds.x + pad
    local w = math.max(0, bounds.w - pad * 2)

    -- The transport bar is pinned to the bottom edge and laid out first, so the body can only ever
    -- take the room that is left. A body that grew into the controls would push them off-window
    -- exactly when a run went wrong and the panel grew a banner.
    local bar = {
        x = bounds.x, y = bounds.y + bounds.h - MET.toolbar_height,
        w = bounds.w, h = MET.toolbar_height,
    }
    local guard_y = bar.y - S.sm - MET.control_height
    local body_bottom = guard_y - S.md

    -- ---- 1. status: is it running, and what is it doing right now ----------------
    local status_token = health.profile_loaded
        and (SEVERITY_TOKEN[health.severity] or "text_secondary")
        or "text_muted"
    local glyph = STATUS_GLYPH[health.status] or "?"
    local status_line = glyph .. "  " .. tostring(health.status)

    local y = bounds.y + pad
    text(x, y, "title", status_token, fit(status_line, w))

    local profile_label = "profile: " .. tostring(model.selected_profile or "(none)")
    profile_label = fit(profile_label, w * 0.5)
    text(x + w - #profile_label * CHAR_W, y + (LH.title - LH.caption) * 0.5,
        "caption", "text_muted", profile_label)
    y = y + LH.title + S.xs

    plan.status = {
        glyph = glyph, label = health.status, token = status_token,
        line = status_line, severity = health.severity,
    }

    if health.profile_loaded then
        text(x, y, "body", "text_primary", fit("Now: " .. tostring(view.current.human_text), w))
        y = y + LH.body + S.xs

        local live = view.liveness
        text(x, y, "caption", "text_muted", fit(string.format(
            "session %s   in-step %s   since progress %s",
            dur(live.session_elapsed_s), dur(live.time_in_step_s),
            dur(live.time_since_progress_s)), w))
        y = y + LH.caption

        -- Counters appear only once there is something to count. Three permanent zeroes are three
        -- fields the eye has to reject on every pass.
        local counters = view.counters
        if counters.deaths > 0 or counters.retries > 0 or counters.failures > 0 then
            text(x, y + S.xs, "caption", "text_secondary", fit(string.format(
                "deaths %d   retries %d   failures %d",
                counters.deaths, counters.retries, counters.failures), w))
            y = y + S.xs + LH.caption
        end
    end

    y = y + S.md
    rect({ x = x, y = y, w = w, h = MET.divider }, "border")
    y = y + MET.divider + S.md

    if plan.is_empty then
        -- ADR 09b §5.5. This is what a new operator meets, because the compiled corpus is empty
        -- today: a blank pane would leave them with nothing to do and no idea what to do next.
        local action_label = model.selected_profile
            and ("Start " .. tostring(model.selected_profile)) or "Record a zone"
        push({
            kind = "empty_state",
            bounds = { x = x, y = y, w = w, h = math.max(0, body_bottom - y) },
            id = model.selected_profile and "start" or "record",
            title = "No profile running",
            message = "Record a zone, or pick a profile to run",
            action_label = action_label,
        })
    else
        -- ---- 2. is it stuck, and why --------------------------------------------
        plan.alerts = collect_alerts(view, model)
        for _, alert in ipairs(plan.alerts) do
            local token = SEVERITY_TOKEN[alert.severity] or "warning"
            local height = S.md * 2 + LH.heading + #alert.lines * LH.caption
            local b = { x = x, y = y, w = w, h = height }
            alert.bounds = b

            -- The only filled surface on the panel, at the only type size above body. Two carriers
            -- that are not colour, so the alert still leads the page in greyscale.
            rect(b, "surface_overlay", 255, Theme.radius.md)
            push({
                kind = "outline", bounds = b, token = token,
                alpha = Theme.interaction.active.border, rounding = Theme.radius.md,
                thickness = MET.focus_thickness,
            })
            rect({ x = b.x, y = b.y, w = MET.selection_marker, h = b.h }, token, 255)

            local action_w = alert.action_id
                and (#alert.action_label * CHAR_W + S.xl) or 0
            local text_x = b.x + MET.selection_marker + S.md
            text(text_x, b.y + S.md, "heading", token,
                fit(alert.glyph .. "  " .. alert.title, b.w - MET.selection_marker - S.md * 2 - action_w))

            local line_y = b.y + S.md + LH.heading
            for _, line in ipairs(alert.lines) do
                text(text_x, line_y, "caption", "text_secondary", fit(line, b.w - S.md * 3))
                line_y = line_y + LH.caption
            end

            if alert.action_id then
                push({
                    kind = "button", id = alert.action_id,
                    bounds = {
                        x = b.x + b.w - action_w - S.md, y = b.y + S.sm,
                        w = action_w, h = MET.control_height,
                    },
                    label = alert.action_label, variant = "ghost",
                })
            end

            y = y + height + S.sm
        end

        -- ---- 3. progress and ETA -------------------------------------------------
        local p = view.progress
        if p.total > 0 then
            text(x, y, "body", "text_primary", string.format("Step %d/%d", p.step, p.total))
            local pct_label = string.format("%d%%", p.pct)
            text(x + w - #pct_label * CHAR_W, y, "body", "text_secondary", pct_label)
            y = y + LH.body + S.xs

            -- The bar's LENGTH is the signal; its colour only agrees with the status already
            -- stated above it, so a colour-blind read loses nothing.
            local track = { x = x, y = y, w = w, h = S.sm }
            rect(track, "surface_raised", 255, Theme.radius.sm)
            local fill_w = math.max(0, math.min(1, p.pct / 100)) * w
            if fill_w > 0 then
                -- A zero-width rounded rect is not nothing: the rounding radius still paints, so a
                -- run at 0% would show a filled dot that reads as progress it has not made.
                rect({ x = x, y = y, w = fill_w, h = S.sm },
                    (health.severity == "alarm") and "danger" or "accent", 255, Theme.radius.sm)
            end
            plan.progress.visible = true
            plan.progress.track_w = w
            plan.progress.fill_w = fill_w
            y = y + S.sm + S.xs

            text(x, y, "caption", "text_muted",
                fit(eta_text(p.eta_s) .. "   " .. rate_text(p.steps_per_hour), w))
            y = y + LH.caption + S.md
        end

        -- ---- 4. quest-log desync -------------------------------------------------
        local sync = view.sync
        if sync.tracked > 0 and sync.ok then
            text(x, y, "caption", "text_muted",
                string.format("Quest log in sync (%d/%d)", sync.in_log, sync.tracked))
            y = y + LH.caption + S.md
        elseif sync.tracked > 0 then
            -- The "is it lying to me" signal gets a marker and body-weight copy rather than the
            -- muted caption its healthy twin gets. A desync that looked identical to sync would
            -- make the calm state meaningless.
            rect({ x = x, y = y, w = MET.selection_marker, h = LH.body }, "warning", 255)
            local ids = {}
            for i, quest_id in ipairs(sync.missing) do
                if i > MAX_MISSING_QUESTS then break end
                ids[#ids + 1] = tostring(quest_id)
            end
            text(x + MET.selection_marker + S.sm, y, "body", "warning", fit(string.format(
                "Quest log MISMATCH - %d of %d tracked quests missing: %s",
                #sync.missing, sync.tracked, table.concat(ids, ", ")),
                w - MET.selection_marker - S.sm))
            y = y + LH.body + S.md
        end

        -- ---- 5. recent events ----------------------------------------------------
        local header_h = LH.heading + S.xs
        local row_h = LH.body + S.xs
        if body_bottom - y >= header_h + MET.control_height + row_h + S.sm * 2 then
            push({
                kind = "section_header", bounds = { x = x, y = y, w = w, h = header_h },
                title = "Recent events",
            })
            y = y + header_h + S.sm

            local cursor = x
            for _, name in ipairs(FILTER_ORDER) do
                local label = FILTER_LABEL[name]
                local chip_w = #label * CHAR_W + S.xl
                push({
                    kind = "chip", id = "filter:" .. name,
                    bounds = { x = cursor, y = y, w = chip_w, h = MET.control_height },
                    label = label, selected = (model.event_filter == name),
                })
                cursor = cursor + chip_w + S.sm
            end
            y = y + MET.control_height + S.sm

            local room = math.floor(math.max(0, body_bottom - y) / row_h)
            local shown = 0
            for _, event in ipairs(view.events) do
                if shown >= room then break end
                if event_passes(event, model.event_filter) then
                    text(x, y, "body", EVENT_TOKEN[event.sev] or "text_muted", fit(string.format(
                        "%s  %s  %s", EVENT_GLYPH[event.sev] or "-", dur(event.t),
                        tostring(event.text)), w))
                    y = y + row_h
                    shown = shown + 1
                end
            end
            plan.event_rows = shown
            if shown == 0 then
                text(x, y, "caption", "text_muted", "No events yet")
            end
        end
    end

    -- ---- 6. controls ------------------------------------------------------------
    -- Guardrails sit on their own row above the transport bar rather than behind a disclosure
    -- triangle: they are what an unattended run is trusted to stop itself on, and a limit nobody
    -- can see is a limit nobody checks.
    local guardrails = view.guardrails
    local guard_specs = {
        {
            id = "guard:deaths",
            label = "Deaths: " .. (guardrails.stop_after_deaths
                and tostring(guardrails.stop_after_deaths) or "off"),
        },
        {
            id = "guard:stuck",
            label = "Stuck: " .. (guardrails.stop_if_stuck_s
                and (tostring(guardrails.stop_if_stuck_s) .. "s") or "off"),
        },
    }
    local guard_x = x
    for _, spec in ipairs(guard_specs) do
        spec.bounds = {
            x = guard_x, y = guard_y,
            w = #spec.label * CHAR_W + S.xl, h = MET.control_height,
        }
        spec.disabled = false
        push({
            kind = "chip", id = spec.id, bounds = spec.bounds, label = spec.label,
            tone = guardrails.tripped and "warning" or nil,
        })
        controls[#controls + 1] = spec
        guard_x = guard_x + spec.bounds.w + S.sm
    end

    rect(bar, "surface_raised", 255)
    rect({ x = bar.x, y = bar.y, w = bar.w, h = MET.divider }, "border")

    -- Every verb is always present, disabled when it cannot act. A Pause button that vanished
    -- while stopped would make the whole row shift under a pointer that is also steering a
    -- character (ADR 09b §3, hit targets).
    local loaded = health.profile_loaded
    local button_specs = {
        {
            id = "start", label = "Start", variant = "primary",
            disabled = loaded or not model.selected_profile,
        },
        {
            id = model.paused and "resume" or "pause",
            label = model.paused and "Resume" or "Pause",
            variant = "secondary", disabled = not loaded,
        },
        { id = "stop", label = "Stop", variant = "danger", disabled = not loaded },
        { id = "skip_step", label = "Skip step", variant = "secondary", disabled = not loaded },
    }

    local button_y = bar.y + (bar.h - MET.control_height) * 0.5
    local button_x = bar.x + S.sm
    for _, spec in ipairs(button_specs) do
        spec.disabled = spec.disabled and true or false
        spec.bounds = {
            x = button_x, y = button_y,
            w = math.max(BUTTON_MIN_W, #spec.label * CHAR_W + S.xl), h = MET.control_height,
        }
        push({
            kind = "button", id = spec.id, bounds = spec.bounds,
            label = spec.label, variant = spec.variant, disabled = spec.disabled,
        })
        controls[#controls + 1] = spec
        button_x = button_x + spec.bounds.w + S.sm
    end

    local rescan = { id = "rescan", label = "Rescan", disabled = false }
    local rescan_w = math.max(BUTTON_MIN_W, #rescan.label * CHAR_W + S.xl)
    rescan.bounds = {
        x = bar.x + bar.w - S.sm - rescan_w, y = button_y,
        w = rescan_w, h = MET.control_height,
    }
    push({
        kind = "button", id = rescan.id, bounds = rescan.bounds,
        label = rescan.label, variant = "ghost",
    })
    controls[#controls + 1] = rescan

    return plan
end

-- Exposed so tests can assert the vocabulary itself rather than one panel's use of it: a status
-- added without a glyph, or two statuses sharing one, is the failure this table exists to prevent.
RunnerPanelState.STATUS_GLYPH = STATUS_GLYPH
RunnerPanelState.SEVERITY_TOKEN = SEVERITY_TOKEN
RunnerPanelState.format_duration = dur
RunnerPanelState.format_eta = eta_text

return RunnerPanelState
