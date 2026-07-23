--- Sentinel Runner Cockpit — render layer.
---
--- Deliberately thin: every decision lives in `runner_state.lua` (pure, offline-tested) and this
--- file only projects that snapshot onto Sylvannas widgets. Nothing here computes health,
--- liveness, ETA, desync or guardrail state — if you find yourself adding logic here, it belongs
--- in the view-model where it can be tested.
---
--- Sylvannas constraints honoured:
---   * windows and menu elements are created ONLY in `ensure_frames_created()`, which main.lua
---     calls from the tick callback — never from a render callback.
---   * `core.menu.button` requires a unique string id.
---   * layout is immediate-mode inside `window:begin(...)`.

local RunnerState = require("modules/questing/runner_state")

local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    if ok and mod ~= nil then return mod end
    return fallback
end

local Color = require_or("common/color", {
    new = function(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end,
})
local Enums = require_or("common/enums", nil)

-- Palette: status colour is the fastest signal on the screen, so it is derived from the
-- view-model's alarm flag rather than from a status string comparison scattered through layout.
local C = {
    ok      = function() return Color.new(120, 220, 140, 255) end,
    warn    = function() return Color.new(240, 200, 100, 255) end,
    alarm   = function() return Color.new(240, 110, 110, 255) end,
    idle    = function() return Color.new(160, 160, 170, 255) end,
    label   = function() return Color.new(160, 165, 200, 255) end,
    value   = function() return Color.new(225, 225, 232, 255) end,
    dim     = function() return Color.new(150, 150, 155, 200) end,
    heading = function() return Color.new(185, 190, 235, 255) end,
    sep     = function() return Color.new(100, 99, 150, 100) end,
}

local SEV_COLOR = { error = C.alarm, warn = C.warn, info = C.dim }

local RunnerUI = {}
RunnerUI.__index = RunnerUI

--- Format seconds as compact H:MM:SS / MM:SS — operators scan durations, they don't parse floats.
local function dur(s)
    if s == nil then return "--" end
    s = math.floor(tonumber(s) or 0)
    if s < 0 then s = 0 end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
    return string.format("%02d:%02d", m, sec)
end

function RunnerUI:new(questing_module)
    local o = setmetatable({}, RunnerUI)
    o._module = questing_module
    o._visible = false
    o._frames = {}
    o._el = nil
    o._profiles = {}
    o._selected_profile = nil
    o._show_condition_details = false
    o._event_filter = "all"      -- all | warn | error
    return o
end

-- ======================================================================
-- Visibility
-- ======================================================================

function RunnerUI:show() self._visible = true end
function RunnerUI:hide()
    self._visible = false
    if self._frames.root then self._frames.root:set_visibility(false) end
end
function RunnerUI:is_visible() return self._visible end
function RunnerUI:toggle()
    if self._visible then self:hide() else self:show() end
end

function RunnerUI:destroy()
    self._frames = {}
    self._el = nil
end

-- ======================================================================
-- Frame creation (TICK CONTEXT ONLY — Sylvannas forbids this in render)
-- ======================================================================

function RunnerUI:ensure_frames_created()
    if not self._visible then return end
    if self._frames.root then return end

    local el = {}
    local window = core.menu.window("sentinel_runner_cockpit")

    el.btn_start      = core.menu.button("sentinel_run_btn_start")
    el.btn_pause      = core.menu.button("sentinel_run_btn_pause")
    el.btn_stop       = core.menu.button("sentinel_run_btn_stop")
    el.btn_estop      = core.menu.button("sentinel_run_btn_estop")
    el.btn_skip       = core.menu.button("sentinel_run_btn_skip")
    el.btn_reload     = core.menu.button("sentinel_run_btn_reload")
    el.btn_refresh    = core.menu.button("sentinel_run_btn_refresh")
    el.btn_details    = core.menu.button("sentinel_run_btn_details")
    el.btn_filter     = core.menu.button("sentinel_run_btn_filter")
    el.profile_combo  = core.menu.combobox(1, "sentinel_run_profile")
    el.tree_events    = core.menu.tree_node()
    el.tree_guard     = core.menu.tree_node()

    self._el = el
    self._frames.root = window
    self:refresh_profiles()
end

function RunnerUI:refresh_profiles()
    if not self._module then return end
    self._profiles = self._module:list_profiles() or {}
end

-- ======================================================================
-- Render
-- ======================================================================

function RunnerUI:_on_render_window()
    if not self._visible then return end
    local window = self._frames.root
    if not window then return end   -- created in tick context

    local vm = self._module and self._module:get_view() or RunnerState.build({})

    window:begin(
        Enums and Enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS or 0,
        true,
        Color.new(0, 0, 0, 0),
        Color.new(100, 99, 150, 255),
        Enums and Enums.window_enums.window_cross_visuals.BLUE_THEME or 0,
        Enums and Enums.window_enums.window_behaviour_flags.NO_SCROLLBAR or 0,
        function()
            self:_draw_health(window, vm)
            self:_draw_progress(window, vm)
            self:_draw_blocked(window, vm)
            self:_draw_sync(window, vm)
            self:_draw_controls(window, vm)
            self:_draw_events(window, vm)
        end
    )

    if window.is_being_shown and not window:is_being_shown() then
        self._visible = false
    end
end

--- Health banner — the one-glance "do I need to intervene?" answer.
function RunnerUI:_draw_health(window, vm)
    local h = vm.health
    local color = C.idle
    if h.is_alarm then color = C.alarm
    elseif h.status == "RUNNING" then color = C.ok
    elseif h.status == "WAITING" or h.status == "NAVIGATING" then color = C.warn
    elseif h.status == "FINISHED" then color = C.ok end

    local dot = h.is_alarm and "!" or "*"
    window:add_text_on_dynamic_pos(color(), string.format("%s %s", dot, h.status))
    window:add_text_on_dynamic_pos(C.value(),
        string.format("   profile: %s", tostring(self._selected_profile or "(none)")))

    -- Liveness: the signal that separates a healthy wait from a wedged run.
    local lv = vm.liveness
    window:add_text_on_dynamic_pos(C.dim(), string.format(
        "   session %s   in-step %s   since progress %s",
        dur(lv.session_elapsed_s), dur(lv.time_in_step_s),
        lv.time_since_progress_s and dur(lv.time_since_progress_s) or "--"))
    window:add_text_on_dynamic_pos(C.dim(), string.format(
        "   deaths %d   retries %d   failures %d",
        vm.counters.deaths, vm.counters.retries, vm.counters.failures))
    window:add_separator(10, 10, 0, 0, C.sep())
end

function RunnerUI:_draw_progress(window, vm)
    local p = vm.progress
    window:add_text_on_dynamic_pos(C.heading(), string.format(
        "Step %d/%d  %d%%%s", p.step, p.total, p.pct,
        p.eta_s and ("   ETA " .. dur(p.eta_s)) or ""))
    if p.steps_per_hour then
        window:add_text_on_dynamic_pos(C.dim(),
            string.format("   %.1f steps/hr", p.steps_per_hour))
    end
    window:add_text_on_dynamic_pos(C.value(), "Now: " .. tostring(vm.current.human_text))
    window:add_separator(10, 10, 0, 0, C.sep())
end

--- Why it is stopped — human text first, raw condition behind a details toggle.
function RunnerUI:_draw_blocked(window, vm)
    if not vm.blocked.is_blocked then return end
    window:add_text_on_dynamic_pos(C.warn(), string.format(
        "WAITING %s - %s", dur(vm.blocked.waited_s), tostring(vm.blocked.human_reason)))
    if self._el.btn_details:render(self._show_condition_details and "hide details" or "details") then
        self._show_condition_details = not self._show_condition_details
    end
    if self._show_condition_details and vm.blocked.raw_condition then
        local c = vm.blocked.raw_condition
        window:add_text_on_dynamic_pos(C.dim(), "   " .. tostring(c.type or "?") ..
            " payload=" .. tostring(c.payload))
    end
    window:add_separator(10, 10, 0, 0, C.sep())
end

--- Desync detector — profile belief vs the real quest log.
function RunnerUI:_draw_sync(window, vm)
    local s = vm.sync
    if s.tracked == 0 then return end
    local color = s.ok and C.ok or C.alarm
    window:add_text_on_dynamic_pos(color(), string.format(
        "Quest log sync: %d tracked / %d in log %s",
        s.tracked, s.in_log, s.ok and "OK" or "MISMATCH"))
    if not s.ok then
        local ids = {}
        for i, q in ipairs(s.missing) do
            if i > 5 then break end
            ids[#ids + 1] = tostring(q)
        end
        window:add_text_on_dynamic_pos(C.alarm(), "   missing: " .. table.concat(ids, ", "))
    end
    window:add_separator(10, 10, 0, 0, C.sep())
end

function RunnerUI:_draw_controls(window, vm)
    -- Profile picker (auto-discovered, never hardcoded)
    if #self._profiles > 0 then
        self._el.profile_combo:render("Profile", self._profiles)
        local idx = self._el.profile_combo:get()
        self._selected_profile = self._profiles[idx] or self._profiles[1]
    else
        window:add_text_on_dynamic_pos(C.dim(), "No compiled profiles found.")
    end
    if self._el.btn_refresh:render("Rescan") then
        self:refresh_profiles()
    end

    local running = vm.health.profile_loaded
    if not running then
        if self._el.btn_start:render("Start") and self._selected_profile then
            self._module:start(self._module._profile_dir .. "/" .. self._selected_profile .. ".json")
        end
    else
        local paused = self._module and self._module:is_paused()
        if self._el.btn_pause:render(paused and "Resume" or "Pause") then
            if paused then self._module:resume() else self._module:pause() end
        end
        if self._el.btn_stop:render("Stop") then
            self._module:stop()
        end
    end

    -- Emergency stop stays available unconditionally: the whole point is that it works when
    -- normal control flow is misbehaving.
    if self._el.btn_estop:render("EMERGENCY STOP") then
        if self._module then
            self._module:pause()
            self._module:stop()
        end
    end

    if running then
        if self._el.btn_skip:render("Skip step") then self._module:skip_current_step() end
        if self._el.btn_reload:render("Reload profile") and self._selected_profile then
            self._module:start(self._module._profile_dir .. "/" .. self._selected_profile .. ".json")
        end
    end

    self._el.tree_guard:render("Guardrails", function()
        local g = vm.guardrails
        window:add_text_on_dynamic_pos(C.label(), string.format(
            "   stop after deaths: %s", tostring(g.stop_after_deaths or "off")))
        window:add_text_on_dynamic_pos(C.label(), string.format(
            "   stop if stuck: %s", g.stop_if_stuck_s and (g.stop_if_stuck_s .. "s") or "off"))
        if g.tripped then
            window:add_text_on_dynamic_pos(C.alarm(), "   TRIPPED: " .. tostring(g.reason))
        end
    end)
    window:add_separator(10, 10, 0, 0, C.sep())
end

--- Event log — the "what happened at 3am" triage surface.
function RunnerUI:_draw_events(window, vm)
    if self._el.btn_filter:render("Filter: " .. self._event_filter) then
        self._event_filter = (self._event_filter == "all" and "warn")
            or (self._event_filter == "warn" and "error")
            or "all"
    end
    self._el.tree_events:render("Events", function()
        local shown = 0
        for _, e in ipairs(vm.events) do
            local pass = (self._event_filter == "all")
                or (self._event_filter == "warn" and (e.sev == "warn" or e.sev == "error"))
                or (self._event_filter == "error" and e.sev == "error")
            if pass then
                shown = shown + 1
                local col = (SEV_COLOR[e.sev] or C.dim)()
                window:add_text_on_dynamic_pos(col, string.format(
                    "   [%s] %s %s", tostring(e.sev), dur(e.t), tostring(e.text)))
            end
        end
        if shown == 0 then
            window:add_text_on_dynamic_pos(C.dim(), "   (no events at this filter)")
        end
    end)
end

return RunnerUI
