-- sentinel/ui/ide_panels.lua
-- Where the IDE's panels are bound to the modules they drive (ADR 09b §2.4, §6).
--
-- WHY THIS FILE EXISTS AT ALL
-- --------------------------
-- `shell.lua` must not name a panel (its own suite greps the source for `ui/panels`), and
-- `panels/runner.lua` must not reach for the questing module — it runs inside a render callback,
-- where a module call is both untestable and a side effect Sylvannas re-enters at arbitrary times.
-- Something still has to know both. That something is the HOST, and this is it: the only file in
-- the IDE that is allowed to know that the Runner panel drives questing.
--
-- The alternative — teaching the shell to map `{kind="start"}` onto `module:start(path)` — would
-- put questing inside the one file every later unit shares, and the ownership split in ADR 09b §6
-- exists precisely to keep that from happening.
--
-- WHAT IT OWNS
-- ------------
--  1. THE MODEL. `runner.lua` needs `view`, `profiles`, `selected_profile` and `paused` every
--     frame, and none of that is panel knowledge. It is refreshed on the TICK and read from cache
--     on the render path, because `get_view` rebuilds the entire operator snapshot and
--     `list_profiles` reads a directory — both of which §2.4 forbids per frame.
--  2. THE DISPATCH. The panel answers a click with a command; this maps that command onto a verb
--     and answers `(ok, reason)`. An unrecognised command is REFUSED out loud, because a command
--     silently dropped is a control that looks live and is not — the exact defect this unit closes.

local Runner = require("ui/panels/runner")

local IdePanels = {}

-- ============================================================================
-- Refresh cadence (ADR 09b §2.4)
-- ============================================================================

-- The operator snapshot, four times a second. `get_view` walks the executor, the quest log, the
-- guardrails and the event ring; at frame rate that is the most expensive thing the IDE would do,
-- and nobody can read a status line faster than this anyway. The module caches per whole second
-- internally, so this is a second, independent ceiling rather than a substitute for one.
IdePanels.VIEW_INTERVAL_S = 0.25

-- The compiled-profile directory, every ten seconds. This is real file IO: `list_profiles` calls
-- `core.read_dir`. Profiles appear when a human compiles one, which is an event measured in
-- minutes — and `rescan` exists so nobody ever has to wait out this interval.
IdePanels.PROFILE_INTERVAL_S = 10.0

-- Mirrors `QuestingModule`'s own PROFILE_DIR. Only reached when the module is not there to ask,
-- which is the state the IDE deliberately opens in after a failed boot.
local FALLBACK_PROFILE_DIR = "sentinel/data/profiles/quests"

---The Sylvannas clock, or nil when there is none.
---
---nil is answered rather than 0 because a constant clock makes every interval unreachable, and a
---panel frozen on its first reading is a worse failure than an extra call. Callers treat nil as
---"always due".
local function default_clock()
    if type(core) ~= "table" or type(core.time) ~= "function" then return nil end
    local ok, now = pcall(core.time)
    if not ok then return nil end
    return tonumber(now)
end

-- ============================================================================
-- Paths
-- ============================================================================

---Resolve a profile stem to something `QuestingModule:start` can actually load.
---
---`list_profiles` yields extension-stripped stems, and `initialize` hands its argument straight to
---the profile loader as a file name. Passing the bare stem loads nothing and publishes
---`questing:error` — a Start button that reports success and runs no route. The module builds the
---same path in `_advance_to_next_profile` and `run_plan`; this mirrors that rather than inventing a
---second rule for it.
local function profile_path(questing, stem)
    stem = tostring(stem)
    if stem:sub(-5) == ".json" then return stem end
    local dir = (type(questing) == "table" and type(questing._profile_dir) == "string")
        and questing._profile_dir or FALLBACK_PROFILE_DIR
    return dir .. "/" .. stem .. ".json"
end

-- ============================================================================
-- The Runner binding
-- ============================================================================

local RunnerBinding = {}
RunnerBinding.__index = RunnerBinding

---@param deps table|nil { questing = function():module|nil, now = function():number|nil }
function IdePanels.new_runner(deps)
    deps = deps or {}
    local self = setmetatable({}, RunnerBinding)
    -- A RESOLVER, not a module. The app is torn down and rebuilt by `reload`, and it may never
    -- exist at all; a binding that captured the module once would go on driving a dead one.
    self._questing = deps.questing or function() return nil end
    self._now = deps.now or default_clock
    self._model = Runner.new_model()
    self._view_at = nil
    self._profiles_at = nil
    return self
end

---The panel-local state, live. The panel mutates its own half of it (filter, disclosure) during
---render; this binding owns the half that comes from the module.
function RunnerBinding:model() return self._model end

---Drop the cached readings so the next tick rebuilds them.
---
---Called after every control that changed the run: a Pause that left the panel reading RUNNING for
---a quarter of a second reads as a Pause that did nothing, which is indistinguishable from the
---inert controls this unit exists to fix.
function RunnerBinding:invalidate(include_profiles)
    self._view_at = nil
    if include_profiles then self._profiles_at = nil end
end

---Keep `selected_profile` pointing at a route that still exists.
---
---Without this the Start button is permanently disabled: `runner_panel_state` disables Start when
---`selected_profile` is nil and there is no profile picker on the panel yet.
function RunnerBinding:_reconcile_selection()
    local model = self._model
    for _, stem in ipairs(model.profiles) do
        if stem == model.selected_profile then return end
    end
    model.selected_profile = model.profiles[1]
end

---Refresh the module-owned half of the model. TICK CONTEXT ONLY.
---@param force boolean|nil ignore the intervals
function RunnerBinding:refresh(force)
    local model = self._model
    local questing = self._questing()

    if not questing then
        -- `toggle_ide` bypasses `ensure_initialized` on purpose, because a failed boot is exactly
        -- when an operator opens the IDE. "There is no questing module" therefore has to be a model
        -- the panel can draw rather than an error, and the stale snapshot has to go — a panel still
        -- showing RUNNING for a module that no longer exists is worse than an empty one.
        model.view = nil
        model.profiles = {}
        model.paused = false
        self._view_at = nil
        self._profiles_at = nil
        return model
    end

    local now = self._now()
    local function due(last)
        return force or now == nil or last == nil
    end

    if due(self._view_at) or (now - self._view_at) >= IdePanels.VIEW_INTERVAL_S then
        -- pcall'd individually so a module mid-failure cannot take the directory listing down with
        -- the snapshot, and vice versa.
        local ok, view = pcall(questing.get_view, questing)
        model.view = ok and view or nil
        local ok_paused, paused = pcall(questing.is_paused, questing)
        model.paused = (ok_paused and paused) and true or false
        self._view_at = now
    end

    if due(self._profiles_at) or (now - self._profiles_at) >= IdePanels.PROFILE_INTERVAL_S then
        local ok, profiles = pcall(questing.list_profiles, questing)
        model.profiles = (ok and type(profiles) == "table") and profiles or {}
        self._profiles_at = now
        self:_reconcile_selection()
    end

    return model
end

-- ============================================================================
-- The command vocabulary
-- ============================================================================
-- One entry per command `runner_panel_state.ACTIONS` can emit. Every handler answers
-- `(ok, reason)`: the panel controls are the only surface an operator has for a run in progress, so
-- a refusal that carries no reason leaves them pressing a button and guessing.

local COMMANDS = {
    start = function(binding, command, questing)
        local stem = command.profile or binding._model.selected_profile
        if not stem then return false, "no compiled profile is selected" end
        local path = profile_path(questing, stem)
        if questing:start(path) == false then
            return false, "profile did not load: " .. path
        end
        binding:invalidate()
        return true
    end,

    pause = function(binding, _command, questing)
        questing:pause()
        binding:invalidate()
        return true
    end,

    resume = function(binding, _command, questing)
        questing:resume()
        binding:invalidate()
        return true
    end,

    stop = function(binding, _command, questing)
        questing:stop()
        binding:invalidate()
        return true
    end,

    skip_step = function(binding, _command, questing)
        if questing:skip_current_step() == false then
            return false, "there is no run to skip a step in"
        end
        binding:invalidate()
        return true
    end,

    set_guardrails = function(binding, command, questing)
        questing:set_guardrails(command.guardrails)
        binding:invalidate()
        return true
    end,

    -- The one verb that starts a recording rather than a run. It maps to `start_recording` and not
    -- to a toggle: the panel's own copy is "Record a zone", and a button whose meaning flipped
    -- between presses would make Stop-recording an accident rather than a decision.
    record = function(_binding, _command, questing)
        local result = questing:start_recording()
        if not result or not result.ok then
            return false, tostring(result and result.reason or "recording did not start")
        end
        return true
    end,
}

-- `rescan` is the host's own verb: it re-reads the profile directory and needs no module, so it
-- must still work while questing is down — that is the state in which an operator is most likely
-- to be looking for a route to start.
local HOST_COMMANDS = {
    rescan = function(binding)
        binding:invalidate(true)
        return true
    end,
}

---Carry out one command from the panel. TICK CONTEXT ONLY — the shell queues these during render
---and hands them over here.
---@return boolean ok, string|nil reason
function RunnerBinding:dispatch(command)
    if type(command) ~= "table" or type(command.kind) ~= "string" then
        return false, "a panel command must be a table carrying a string kind"
    end

    local host = HOST_COMMANDS[command.kind]
    if host then return host(self, command) end

    local handler = COMMANDS[command.kind]
    if not handler then
        -- Refused out loud. A command nobody implemented is a control that looks live and is not,
        -- which is precisely how every button on this panel came to be inert.
        return false, "unknown runner command '" .. command.kind .. "'"
    end

    local questing = self._questing()
    if not questing then
        return false, "the questing module is not running"
    end

    local ok, result, reason = pcall(handler, self, command, questing)
    if not ok then return false, tostring(result) end
    return result ~= false, reason
end

---The panel spec the shell registers.
function RunnerBinding:spec()
    local binding = self
    return {
        id = Runner.id,
        title = Runner.title,
        order = Runner.order,
        render = function(window, bounds, _ctx)
            -- Whatever the last TICK left in the model, and nothing more. Refreshing here would put
            -- `list_profiles`' directory read on the per-frame path (ADR 09b §2.4), and the command
            -- is RETURNED rather than dispatched so the effect happens outside this callback.
            return Runner.render(window, bounds, binding._model)
        end,
        on_tick = function() binding:refresh() end,
        dispatch = function(command) return binding:dispatch(command) end,
    }
end

-- ============================================================================
-- Installation
-- ============================================================================

---Register every panel the IDE ships with onto `shell`.
---
---This is the registration site U3-U7 extend — one line each, in a file neither the shell nor any
---panel reads. It is the only place where "which panels exist" and "what each one drives" meet.
---@param shell table the IDE shell
---@param deps table|nil forwarded to each binding
---@return table|nil bindings, string|nil reason
function IdePanels.install(shell, deps)
    local runner = IdePanels.new_runner(deps)
    local ok, reason = shell:register_panel(runner:spec())
    if not ok then return nil, reason end
    return { runner = runner }
end

return IdePanels
