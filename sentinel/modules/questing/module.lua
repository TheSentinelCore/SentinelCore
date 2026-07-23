--- Sentinel Questing Module
--- Handles quest execution for a leveling route
---
--- Responsibilities:
--- - Load compiled profiles (Runtime JSON)
--- - Execute actions via Sylvanas APIs
--- - Track quest state and progress
--- - Navigate between objectives
--- - In-game editor (optional, toggled via /qe or toggle_editor())

local RuntimeProfile = require("modules/questing/runtime_profile")
local RunnerState = require("modules/questing/runner_state")
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")

local QuestingModule = {}
QuestingModule.__index = QuestingModule

-- Compiled RuntimeProfile JSON lives alongside the existing sentinel data tree in the loader's
-- scripts_data sandbox. Legacy .yaml route files share this folder; list_profiles filters to
-- .json so the two coexist without collision.
local PROFILE_DIR = "sentinel/data/profiles/quests"

local function now_s()
    return (core and core.time and core.time()) or 0
end

-- ======================================================================
-- Quest-log desync sync (C5)
--
-- The cockpit's "is it lying to me?" panel (runner_state.lua sync) compares
-- module.questing.tracked_quests against module.questing.quest_log, but nothing ever wrote
-- either blackboard key: both defaulted to {} and the panel always reported ok=true. This
-- module owns writing them from data the executor already exposes, WITHOUT editing
-- runtime_profile.lua:
--   - tracked_quests: replayed from the compiled profile's own AcceptQuest/TurnInQuest
--     actions in every operation BEFORE the one currently in progress. The executor
--     keeps no other record of "accepted right now"; this reconstructs it from the
--     profile it is already running.
--   - quest_log: the REAL in-game quest log, sourced via the executor's public
--     create_context()/ctx:_refresh_quest_log() (runtime_profile.lua:547-567) — reused,
--     not duplicated.
-- ======================================================================

--- Replay AcceptQuest/TurnInQuest actions up to (not including) the operation currently
--- in progress to approximate which quest ids the profile currently believes are accepted.
local function tracked_quests_from_profile(executor)
    if not executor or not executor._profile or type(executor._profile.operations) ~= "table" then
        return {}
    end
    local operations = executor._profile.operations
    local current_idx = executor._current_operation_idx or 1
    local tracked, order = {}, {}
    for i = 1, math.min(current_idx - 1, #operations) do
        local op = operations[i]
        local actions = op and op.actions
        if type(actions) == "table" then
            for _, action in ipairs(actions) do
                local payload = action.payload
                if action.type == "AcceptQuest" and type(payload) == "table" and payload.quest_id ~= nil then
                    local qid = tostring(payload.quest_id)
                    if not tracked[qid] then
                        tracked[qid] = true
                        order[#order + 1] = qid
                    end
                elseif action.type == "TurnInQuest" and type(payload) == "table" and payload.quest_id ~= nil then
                    local qid = tostring(payload.quest_id)
                    if tracked[qid] then
                        tracked[qid] = nil
                        for idx, existing in ipairs(order) do
                            if existing == qid then
                                table.remove(order, idx)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    return order
end

--- Read the real in-game quest log via the executor's existing (public) quest-log cache
--- refresh, reused rather than reimplemented. Fails safe to {} — offline/no Sylvannas API,
--- no executor, or an executor without create_context (e.g. test doubles) all yield {}.
local function real_quest_log(executor)
    if not executor or type(executor.create_context) ~= "function" then
        return {}
    end
    local ok, ctx = pcall(executor.create_context, executor)
    if not ok or type(ctx) ~= "table" or type(ctx._refresh_quest_log) ~= "function" then
        return {}
    end
    local refreshed = pcall(ctx._refresh_quest_log, ctx)
    if not refreshed then
        return {}
    end
    local log = {}
    for qid in pairs(ctx._active_quests or {}) do log[qid] = true end
    for qid in pairs(ctx._completed_quests or {}) do log[qid] = true end
    return log
end

function QuestingModule:new(blackboard, event_bus)
    local o = setmetatable({}, QuestingModule)
    o._blackboard = blackboard or Blackboard:new()
    o._event_bus = event_bus or EventBus:new(function(msg)
        if core and core.log then core.log(msg) end
    end)
    o._executor = nil
    o._enabled = false
    -- Runner cockpit control state
    o._paused = false
    o._deaths = 0
    o._started_at = nil
    o._last_progress_at = nil
    o._last_operation_idx = nil
    o._guardrails = {}
    o._profile_dir = PROFILE_DIR
    return o
end

function QuestingModule:initialize(profile_json_path)
    -- Share the module's bus/blackboard so questing actions can reach the combat module.
    self._executor = RuntimeProfile:new(profile_json_path, false, self._event_bus, self._blackboard)
    local success, err = self._executor:load()
    if not success then
        self._event_bus:publish("questing:error", { error = err })
        return false
    end
    self._enabled = true
    self._blackboard:set("module.questing.enabled", true)
    return true
end

--- Refresh the quest-log desync inputs (C5) so the cockpit's sync panel reflects reality
--- instead of two blackboard keys nothing ever wrote.
function QuestingModule:_refresh_quest_sync()
    self._blackboard:set("module.questing.tracked_quests", tracked_quests_from_profile(self._executor))
    self._blackboard:set("module.questing.quest_log", real_quest_log(self._executor))
end

function QuestingModule:tick(delta)
    if not self._enabled or self._paused or not self._executor then return end

    self:_refresh_quest_sync()

    -- Guardrails are evaluated BEFORE executing: an unattended run that has tripped its limit
    -- must halt on this tick, not after one more action.
    local view = self:get_view()
    if view.guardrails.tripped then
        self:pause()
        self._event_bus:publish("questing:guardrail_tripped", { reason = view.guardrails.reason })
        return
    end

    local status, message = self._executor:execute()
    self._blackboard:set("module.questing.status", status)
    self._blackboard:set("module.questing.message", message)

    -- Liveness marker: record when the run last actually moved forward, so the cockpit can tell
    -- a healthy wait from a wedged one.
    local op_idx = self._executor._current_operation_idx
    if op_idx ~= self._last_operation_idx then
        self._last_operation_idx = op_idx
        self._last_progress_at = now_s()
    end
    if self._executor._state == "ghost" and not self._counted_death then
        self._deaths = self._deaths + 1
        self._counted_death = true
    elseif self._executor._state ~= "ghost" then
        self._counted_death = false
    end

    if status == "finished" then
        self._enabled = false
        self._blackboard:set("module.questing.enabled", false)
        self._event_bus:publish("questing:finished", {
            path = self._executor._json_path
        })
    end
end

function QuestingModule:shutdown()
    self._enabled = false
    self._blackboard:set("module.questing.enabled", false)
end

function QuestingModule:is_enabled()
    return self._enabled
end

-- ======================================================================
-- Runner cockpit control surface
-- ======================================================================

--- Load a profile and begin running it. Resets session counters.
function QuestingModule:start(profile_path)
    local ok = self:initialize(profile_path)
    if not ok then return false end
    self._paused = false
    self._deaths = 0
    self._counted_death = false
    self._started_at = now_s()
    self._last_progress_at = self._started_at
    self._last_operation_idx = self._executor and self._executor._current_operation_idx or nil
    self._event_bus:publish("questing:started", { path = profile_path })
    return true
end

--- Halt execution while keeping the executor, so progress is not lost.
function QuestingModule:pause()
    self._paused = true
    self._blackboard:set("module.questing.paused", true)
end

function QuestingModule:resume()
    self._paused = false
    self._blackboard:set("module.questing.paused", false)
end

function QuestingModule:is_paused()
    return self._paused == true
end

--- Full stop: disable and release the executor.
function QuestingModule:stop()
    self._enabled = false
    self._paused = false
    self._executor = nil
    self._blackboard:set("module.questing.enabled", false)
    self._event_bus:publish("questing:stopped", {})
end

--- Manual recovery: abandon the current operation and move to the next one.
function QuestingModule:skip_current_step()
    if not self._executor then return false end
    self._executor._current_operation_idx = (self._executor._current_operation_idx or 1) + 1
    self._executor._current_action_idx = 1
    self._executor._current_action_retries = 0
    -- Releasing the wait timer matters: without it the next gate inherits a stale start time.
    self._executor._wait_started_at = nil
    self._executor._wait_action_key = nil
    self._last_progress_at = now_s()
    self._event_bus:publish("questing:step_skipped", {
        operation = self._executor._current_operation_idx,
    })
    return true
end

function QuestingModule:set_guardrails(cfg)
    self._guardrails = cfg or {}
end

--- Available compiled profiles, discovered from the data folder rather than hardcoded.
--- Returns extension-stripped stems, sorted. A missing/unreadable directory yields {}.
function QuestingModule:list_profiles(dir)
    dir = dir or self._profile_dir
    if not (core and core.read_dir) then return {} end
    local ok, entries = pcall(core.read_dir, dir)
    if not ok or type(entries) ~= "table" then return {} end
    local out = {}
    for _, name in ipairs(entries) do
        local stem = tostring(name):match("^(.+)%.json$")
        -- Skip the runtime's own save sidecars; they are state, not selectable profiles.
        if stem and not stem:match("%.save$") then
            out[#out + 1] = stem
        end
    end
    table.sort(out)
    return out
end

--- One snapshot for the cockpit to render.
function QuestingModule:get_view()
    return RunnerState.build({
        executor = self._executor,
        now = now_s(),
        started_at = self._started_at or now_s(),
        last_progress_at = self._last_progress_at,
        deaths = self._deaths,
        guardrails = self._guardrails,
        tracked_quests = self._blackboard:get("module.questing.tracked_quests", nil),
        quest_log = self._blackboard:get("module.questing.quest_log", nil),
    })
end

-- ======================================================================
-- Editor integration
-- ======================================================================

--- Toggle the in-game quest profile editor.
--- Fires event for the editor subsystem to pick up.
function QuestingModule:toggle_editor()
    self._event_bus:publish("questing:toggle_editor", {})
end

--- Reload the current executor from a compiled profile.
--- Useful after the editor compiles a project — the new profile JSON
--- can be loaded directly.
---@param profile_json string Compiled RuntimeProfile JSON
function QuestingModule:load_compiled_profile(profile_json)
    -- Create a temporary executor that loads from a JSON string
    -- (by writing to a temp file and loading it)
    local temp_path = "SentinelCore/questing/_editor_compile.json"
    -- A8: core.write_file is not a Sylvannas API (docs/SylvannasAPI/dev/api/file-io.md
    -- documents read_data_file/write_data_file/create_data_file). The old guard was always
    -- false, so nothing was ever written and initialize(temp_path) then loaded a MISSING
    -- file, publishing questing:error and leaving the runner disabled on every editor-driven
    -- reload. Match the working RuntimeProfile:_save() path: create then write.
    local wrote = false
    if core and core.write_data_file then
        if core.create_data_file then
            pcall(core.create_data_file, temp_path)
        end
        wrote = pcall(core.write_data_file, temp_path, profile_json)
    end
    if not wrote then
        -- Make the failure diagnosable instead of silently loading a stale/missing file.
        self._event_bus:publish("questing:error", {
            error = "load_compiled_profile: failed to write " .. temp_path,
        })
        return false
    end
    return self:initialize(temp_path)
end

return QuestingModule