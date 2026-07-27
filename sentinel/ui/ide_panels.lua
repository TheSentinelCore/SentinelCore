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
local Explorer = require("ui/panels/explorer")
local ExplorerState = require("ui/panels/explorer_state")
local Properties = require("ui/panels/properties")
local PropertiesState = require("ui/panels/properties_state")
local Graph = require("ui/panels/graph")
local GraphState = require("ui/panels/graph_state")
local EscortRecorder = require("ui/panels/escort_recorder")
local Database = require("ui/panels/database")
local DatabaseState = require("ui/panels/database_state")

-- Phase 5 shell extensions
local TravelEditorState = require("ui/panels/travel_editor_state")
local TravelEditor = require("ui/panels/travel_editor")
local ValidationStatus = require("ui/panels/validation_status")
local StatsDashboard = require("ui/panels/stats_dashboard")

local IdePanels = {}

-- ============================================================================
-- Absent query client (spec: QueryClient Wiring at Install)
-- ============================================================================
--
-- Every data binding used to answer a missing client with a bare `return`. That is the failure this
-- change exists to remove: the panel kept rendering its idle view, so an operator with no
-- QueryServer running saw a panel that looked merely empty rather than one that was disconnected,
-- and there was nothing on screen to distinguish "no results" from "nobody asked".
--
-- The states already carry an `error` field that every `build_plan` projects, so saying so costs one
-- assignment and no new render branch. `_dirty` is deliberately NOT re-armed: render reads
-- `state.error` fresh each frame, so the message stays on screen without spending a tick per frame.
--
-- Kept SHORT deliberately. The Explorer's error row runs the string through `fit(text, content_w)`,
-- so a sentence of explanation would be truncated to an ellipsis at the width that matters most --
-- a narrow panel. The explanation belongs in this comment; the panel gets the fact.
local QUERY_SERVER_UNAVAILABLE = "query server unavailable"

---Record the absent client on a panel state. Idempotent: re-running a tick rewrites the same string.
---@param state table a panel state carrying `error` / `loading`
local function mark_query_client_unavailable(state)
    state.loading = false
    state.error = QUERY_SERVER_UNAVAILABLE
end

---Exposed so tests assert against the real string instead of a copy that can drift out of step.
IdePanels.QUERY_SERVER_UNAVAILABLE = QUERY_SERVER_UNAVAILABLE

-- ============================================================================
-- The selection channel (spec: Cross-Panel Selection Bus)
-- ============================================================================
--
-- Selecting anything used to change nothing outside the panel it happened in — the inspector held a
-- context nobody ever set, so it stayed on whatever it was last given. The shell now carries a
-- content-free channel; this file is the one that knows what a `kind` means, because it is the only
-- file allowed to know both the shell and the panels (ADR 09b §6).
--
-- Published from `dispatch`, never from `render`. `dispatch` is called by `Shell:_dispatch_pending`
-- in TICK context, and `Shell:publish_selection` refuses a render frame outright.

---@param ctx table|nil the tick context the shell hands to `dispatch`
local function publish_selection(ctx, panel_id, kind, id)
    -- nil ctx is the normal case in a unit test that calls `dispatch` directly, and a panel that
    -- required a shell to select would be a panel no test could drive.
    local shell = ctx and ctx.shell
    if type(shell) ~= "table" or type(shell.publish_selection) ~= "function" then return end
    shell:publish_selection({ panel_id = panel_id, kind = kind, id = id })
end

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
-- The Explorer binding (U6 — Quest Browser)
-- ============================================================================

local ExplorerBinding = {}
ExplorerBinding.__index = ExplorerBinding

---@param opts table|nil { query_client = table|nil } a QueryClient instance, not a resolver
---@param opts table|nil { query_client = table|nil, editor_client = table|nil,
---                        campaign = function():string|nil, now = function():number|nil }
function IdePanels.new_explorer(opts)
    opts = opts or {}
    local self = setmetatable({}, ExplorerBinding)
    self._state = ExplorerState.new()
    self._query_client = opts.query_client
    -- The :3031 campaign client. Absent until PR7 builds it, and absent in-game whenever the editor
    -- is down -- both of which have to READ as absent rather than as a write that quietly did
    -- nothing (obs #225: both authoring commands answered "(not yet implemented)" and returned ok).
    self._editor_client = opts.editor_client
    -- A RESOLVER: the campaign is owned by the Graph panel and changes under this one.
    self._campaign = opts.campaign or function() return nil end
    self._now = opts.now or default_clock
    return self
end

---Write generated nodes to the open campaign.
---@return boolean ok, string reason
function ExplorerBinding:_commit_nodes(nodes, what)
    local state = self._state
    if #nodes == 0 then
        state.error = what .. " produced no nodes"
        return false, state.error
    end

    local editor = self._editor_client
    if not editor or type(editor.add_nodes) ~= "function" then
        state.error = "editor unavailable: " .. what .. " needs the campaign editor at :3031"
        return false, state.error
    end

    local campaign = self._campaign()
    if not campaign or campaign == "" then
        state.error = "no campaign is open: " .. what .. " has nowhere to write"
        return false, state.error
    end

    -- Contained: a client that raises must surface as a failed write, not take the whole dispatch
    -- down with it. `called` is pcall's own verdict; `wrote` is the client's.
    local called, wrote, why = pcall(editor.add_nodes, editor, campaign, nodes)
    if not called then
        state.error = what .. " failed: " .. tostring(wrote)
        return false, state.error
    end
    -- A live editor REFUSING the write is not the same thing as no editor, and neither may be
    -- reported as success.
    if wrote == false then
        state.error = what .. " was refused by the editor: " .. tostring(why or "no reason given")
        return false, state.error
    end

    state.error = nil
    return true, string.format("%s: %d node(s) added to '%s'", what, #nodes, campaign)
end

---Access the panel state, exposed so tests can inspect it.
function ExplorerBinding:state() return self._state end

---The panel spec the shell registers.
function ExplorerBinding:spec()
    local binding = self
    return {
        id = Explorer.id,
        title = Explorer.title,
        order = Explorer.order,
        render = function(window, bounds, _ctx)
            local view = binding._state:build()
            return Explorer.render(window, bounds, view)
        end,
        on_tick = function()
            local state = binding._state
            local now = binding._now()

            -- BEFORE the dirty gate, on purpose. Typing happens inside a render callback, which can
            -- mutate the buffer but cannot schedule anything; nothing else would ever notice a
            -- keystroke, and the search bar would be typeable and still inert.
            state:sync_search_input(now)
            -- A debounce that has not elapsed still has to be looked at next tick, or the search
            -- fires only if a later keystroke happens to re-arm the flag.
            if state._search_waiting then state._dirty = true end

            if not state._dirty then return end
            state._dirty = false

            local qc = binding._query_client
            if not qc then
                mark_query_client_unavailable(state)
                return
            end

            -- Only fire queries when there's an active selection or search. Each fetch goes through
            -- its own slot: a pending answer re-arms `_dirty` (see `ui/async_slot.lua`), so the tick
            -- that collects the answer actually runs.
            local slots = state._slots
            if state.selected_id then
                local id = state.selected_id
                local ok_detail, detail = slots.detail:poll(function() return qc:get_quest(id) end)
                if ok_detail == "ok" then state.selected_detail = detail end

                local ok_chain, chain = slots.chain:poll(function() return qc:get_quest_chain(id) end)
                if ok_chain == "ok" then state.chain_data = chain end

                local ok_obj, objectives =
                    slots.objectives:poll(function() return qc:get_quest_objectives(id) end)
                if ok_obj == "ok" then state.objectives = objectives end
            end

            -- The gate is the debounce, not "results are empty". The old condition could only ever
            -- run one search per panel: a second query with results still on screen never fired.
            if state:search_due(now) then
                local query = state.search_query
                local ok_search, results =
                    slots.search:poll(function() return qc:search_quests(query) end)
                if ok_search == "ok" then
                    state.results = results
                    state:mark_search_served()
                elseif ok_search ~= "pending" then
                    -- Resolved to nothing. The slot has already named it in `state.error`; leaving
                    -- the gate open would re-fire the same doomed query every tick forever.
                    state:mark_search_served()
                end
            end
        end,
        dispatch = function(command, ctx)
            local state = binding._state
            if command.kind == "select_quest" then
                state:select(command.id)
                publish_selection(ctx, Explorer.id, "quest", command.id)
                return true
            elseif command.kind == "clear_search" then
                state.search_input:set_value("")
                state:set_query("", binding._now())
                state.results = {}
                state:mark_search_served()
                return true
            elseif command.kind == "submit_search" then
                -- Enter skips the wait: the operator has already said they are finished typing.
                state:sync_search_input(binding._now())
                state._query_changed_at = nil
                state._dirty = true
                return true
            elseif command.kind == "cancel_search" then
                -- Escape put the committed value back in the buffer; the query follows it, so a
                -- half-typed string never reaches the server.
                state:sync_search_input(binding._now())
                return true
            elseif command.kind == "cycle_zone_filter" then
                -- Cycle through zones: nil -> first available zone from results -> nil
                if state.zone_filter == nil then
                    local zones = {}
                    for _, r in ipairs(state.results) do
                        if r.zone and not zones[r.zone] then
                            zones[r.zone] = true
                            state.zone_filter = r.zone
                            break
                        end
                    end
                else
                    state.zone_filter = nil
                end
                state._dirty = true
                return true
            elseif command.kind == "cycle_level_filter" then
                -- Simple toggle: nil -> 1-20 -> 20-40 -> nil
                if state.level_min == nil then
                    state.level_min = 1
                    state.level_max = 20
                elseif state.level_min == 1 then
                    state.level_min = 20
                    state.level_max = 40
                else
                    state.level_min = nil
                    state.level_max = nil
                end
                state._dirty = true
                return true
            elseif command.kind == "add_to_profile" then
                -- The objectives are what turn a quest into a route, and they arrive on their own
                -- slot. Generating Accept→TurnIn with the middle missing because the fetch had not
                -- landed yet would write a quest the bot accepts and then stands still in.
                if not state.objectives then
                    state.error = "add to profile: objectives for quest "
                        .. tostring(command.quest_id) .. " have not loaded yet"
                    return false, state.error
                end
                local nodes, skipped = ExplorerState.build_quest_subgraph(
                    command.quest_id, state.selected_detail, state.objectives)
                local ok_write, reason = binding:_commit_nodes(nodes, "add to profile")
                if ok_write and #skipped > 0 then
                    return true, reason .. "; skipped unknown objective kind(s): "
                        .. table.concat(skipped, ", ")
                end
                return ok_write, reason
            elseif command.kind == "add_chain" then
                if not state.chain_data then
                    state.error = "add chain: the chain for quest "
                        .. tostring(command.quest_id) .. " has not loaded yet"
                    return false, state.error
                end
                return binding:_commit_nodes(
                    ExplorerState.build_chain_subgraph(state.chain_data), "add chain")
            end
            return false, "unknown explorer command '" .. tostring(command.kind) .. "'"
        end,
    }
end

-- ============================================================================
-- The Properties binding (U7 — NPC Inspector, Vendor/Condition/Inventory editors)
-- ============================================================================

local PropertiesBinding = {}
PropertiesBinding.__index = PropertiesBinding

---@param opts table|nil { query_client = table|nil } a QueryClient instance, not a resolver
function IdePanels.new_properties(opts)
    opts = opts or {}
    local self = setmetatable({}, PropertiesBinding)
    self._state = PropertiesState.new()
    self._query_client = opts.query_client
    return self
end

---Access the panel state, exposed so tests can inspect it.
function PropertiesBinding:state() return self._state end

---The panel spec the shell registers.
function PropertiesBinding:spec()
    local binding = self
    return {
        id = Properties.id,
        title = Properties.title,
        order = Properties.order,
        render = function(window, bounds, _ctx)
            local view = binding._state:build()
            return Properties.render(window, bounds, view)
        end,
        on_tick = function()
            local state = binding._state
            if not state._dirty then return end
            state._dirty = false

            -- The client check comes BEFORE the context check on purpose. Having no QueryServer is
            -- a fact about the panel, not about the current selection: an inspector that waits for
            -- a selection to admit it can never fetch anything is the silent idle this change kills.
            local qc = binding._query_client
            if not qc then
                mark_query_client_unavailable(state)
                return
            end

            local ctx = state.context
            if not ctx then return end

            local ctype = ctx.selection_type
            local sid = ctx.selection_id
            -- One slot, because the inspector holds one context at a time. It owns `loading` too:
            -- pending keeps it true and re-arms `_dirty`, resolution clears it.
            local slot = state._slots.detail

            if ctype == "npc" and sid then
                local status, detail = slot:poll(function() return qc:get_npc(sid) end)
                if status == "ok" then state.npc_detail = detail end
            elseif ctype == "vendor" and sid then
                local status, info = slot:poll(function() return qc:get_vendor(sid) end)
                if status == "ok" then
                    state.vendor_info = info
                    state.vendor_items = {}
                    for _, item in ipairs(info.sells or {}) do
                        state.vendor_items[#state.vendor_items + 1] = {
                            entry = item.entry,
                            name = item.name,
                            price = item.price,
                            enabled = true,
                            mode = item.mode or "buy",
                            threshold = item.threshold or 5,
                        }
                    end
                end
            elseif ctype == "object" and sid then
                local status, obj = slot:poll(function() return qc:get_object(sid) end)
                if status == "ok" then state.object_info = obj end
            else
                -- A context nothing fetches for (node, condition, inventory): there is no request in
                -- flight, so the spinner must not be left on from `set_context`.
                state.loading = false
            end
        end,
        dispatch = function(command)
            local state = binding._state
            if command.kind == "set_npc_tab" then
                state:set_npc_tab(command.tab)
                return true
            elseif command.kind == "toggle_vendor_item" then
                if state.vendor_items then
                    for _, item in ipairs(state.vendor_items) do
                        if item.entry == command.entry then
                            item.enabled = not item.enabled
                            break
                        end
                    end
                end
                return true
            elseif command.kind == "add_condition" then
                return true, "add_condition (not yet implemented)"
            elseif command.kind == "add_condition_group" then
                return true, "add_condition_group " .. tostring(command.group_type) .. " (not yet implemented)"
            elseif command.kind == "delete_condition" then
                return true, "delete_condition (not yet implemented)"
            elseif command.kind == "add_inventory_rule" then
                return true, "add_inventory_rule (not yet implemented)"
            elseif command.kind == "clear_inventory_rules" then
                state.inventory_rules = {}
                return true
            end
            return false, "unknown properties command '" .. tostring(command.kind) .. "'"
        end,
    }
end

-- ============================================================================
-- The Graph binding (Phase 3 — Campaign graph editor, waypoint/escort/combat tools)
-- ============================================================================

local GraphBinding = {}
GraphBinding.__index = GraphBinding

---@param opts table|nil { editor_client = table|nil } an EditorClient instance, not a resolver
function IdePanels.new_graph(opts)
    opts = opts or {}
    local self = setmetatable({}, GraphBinding)
    self._state = GraphState.new()
    self._recorder = EscortRecorder.new()
    -- The :3031 campaign client. This binding took NO options at all before -- the Rust CRUD had
    -- zero Lua callers (obs #225) and every campaign verb on this panel was a placeholder string.
    self._editor_client = opts.editor_client
    -- The name of a campaign whose CREATE is in flight. Nil the rest of the time.
    self._creating = nil
    return self
end

---Access the panel state, exposed so tests can inspect it.
function GraphBinding:state() return self._state end

---Access the recorder, exposed for test inspection.
function GraphBinding:recorder() return self._recorder end

---The campaign this panel currently has open, or nil. The Explorer's authoring commands resolve
---their target campaign through this, since the Graph owns it and it changes under them.
function GraphBinding:campaign_name()
    local name = self._state.campaign_name
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

---The editor client, or nil plus the message the panel should be showing instead.
function GraphBinding:_editor()
    local ec = self._editor_client
    if not ec then
        return nil, "campaign editor unavailable: no client for the editor at :3031"
    end
    return ec
end

---Write one node of `node_type` into the open campaign, and re-read the graph from the editor.
---
---Nothing is inserted locally. On failure the panel gains an error and gains NO node, which is the
---requirement in one line: editor down means `state.error`, never a phantom.
---@return boolean handled, string reason
function GraphBinding:_write_node(node_type)
    local state = self._state
    local info = GraphState.node_type_info(node_type)
    if not info then
        state.error = "unknown node type '" .. tostring(node_type) .. "'"
        return true, state.error
    end

    local ec, unavailable = self:_editor()
    if not ec then
        state.error = unavailable
        return true, unavailable
    end
    local campaign = self:campaign_name()
    if not campaign then
        state.error = "no campaign is open: a new node has nowhere to go"
        return true, state.error
    end

    local intent = {}
    for k, v in pairs(info.default_intent or {}) do intent[k] = v end

    -- Contained: a client that raises must read as a failed write, not take the dispatch down.
    local called, wrote, why = pcall(ec.add_nodes, ec, campaign, {
        { id = "new_" .. info.label, type = node_type, preview = info.label, intent = intent },
    })
    if not called then
        state.error = "add " .. info.label .. " failed: " .. tostring(wrote)
        return true, state.error
    end
    if wrote == false then
        state.error = "add " .. info.label .. " was refused: " .. tostring(why or "no reason given")
        return true, state.error
    end

    state.error = nil
    -- Yesterday's clean bill over a graph that has changed since is worse than no verdict at all,
    -- because it is believed.
    state:invalidate_validation()
    -- F19-R1: every save re-validates. Armed rather than run, because the graph has to come back
    -- from the editor first -- validating the copy the write just replaced answers about the wrong
    -- document.
    self._revalidate = true
    -- The graph on screen is the editor's, so re-read it rather than patching the local copy.
    state._slots.campaign:reset()
    state._dirty = true
    return true, "added " .. info.label .. " to '" .. campaign .. "'"
end

---Start a validate or compile. Both are POSTs whose ANSWER is the point, so the dispatch only
---ARMS them and the tick collects the answer through a slot.
---@param which string "validate" | "compile"
---@return boolean handled, string reason
function GraphBinding:_ask_editor(which)
    local state = self._state
    local ec, unavailable = self:_editor()
    if not ec then
        state.error = unavailable
        return true, unavailable
    end
    local campaign = self:campaign_name()
    if not campaign then
        state.error = "no campaign is open: there is nothing to " .. which
        return true, state.error
    end

    -- `forget` first, always. Validate and compile are ACTIONS, and a remembered answer would
    -- replay the verdict from before the edit that prompted the second click.
    if type(ec.forget) == "function" then ec:forget(which .. " '" .. campaign .. "'") end
    state._slots[which]:reset()
    self._asking = which
    state.error = nil
    state._dirty = true
    return true, which .. " '" .. campaign .. "'"
end

---Poll a validate or compile that a dispatch armed. TICK CONTEXT.
---@return boolean handled whether this owned the tick
function GraphBinding:_poll_ask(ec)
    local which = self._asking
    if not which then return false end
    local state = self._state
    local campaign = self:campaign_name()
    if not campaign then
        self._asking = nil
        return false
    end

    local status, answer = state._slots[which]:poll(function() return ec[which](ec, campaign) end)
    if status == "pending" then return true end
    self._asking = nil
    if status ~= "ok" then return true end

    if which == "validate" then
        state:set_diagnostics(answer)
    else
        -- The editor's compile is still a summary rather than a profile, so the panel reports what
        -- it actually said instead of claiming a build happened.
        state.compile_message = tostring((answer or {}).message or "compiled")
    end
    return true
end

---Surface refusals the editor sent AFTER the write that caused them had already returned.
---
---A mutation can only report that its request LEFT. Everything the server said about it arrives
---here, on a later tick, and this is the only place it becomes visible.
function GraphBinding:_drain_editor_errors()
    local ec = self._editor_client
    if not ec or type(ec.take_error) ~= "function" then return end
    local err = ec:take_error()
    if err then self._state.error = err end
end

---The panel spec the shell registers.
function GraphBinding:spec()
    local binding = self
    return {
        id = Graph.id,
        title = Graph.title,
        order = Graph.order,
        render = function(window, bounds, ctx)
            -- Pass current player position from tick context to the state
            local state = binding._state
            if ctx and ctx.player_position then
                if state.waypoint_mode then
                    state:capture_position(ctx.player_position)
                end
                if state.escort_mode then
                    state:tick_escort_position(ctx.player_position)
                end
            end

            local view = state:build()
            return Graph.render(window, bounds, view)
        end,
        on_tick = function()
            local state = binding._state
            local recorder = binding._recorder

            -- Tick the recorder (independent mode)
            if recorder.recording then
                local ctx = { player_position = nil }
                if type(core) == "table" and type(core.object_manager) == "table" then
                    local player = core.object_manager.get_local_player()
                    if player and type(player.get_position) == "function" then
                        local ok, pos = pcall(player.get_position, player)
                        if ok then ctx.player_position = pos end
                    end
                end
                recorder:tick(ctx)
            end

            -- Anything the editor refused since the last tick, whatever issued it.
            binding:_drain_editor_errors()

            if not state._dirty then return end
            state._dirty = false

            local ec = binding._editor_client
            if not ec then
                state.error = "campaign editor unavailable: no client for the editor at :3031"
                state.loading = false
                return
            end

            -- A create in flight owns the tick: the campaign it names cannot be opened until the
            -- editor has answered, and asking early caches a 404.
            if binding._creating then
                local name = binding._creating
                local status, summary = state._slots.create:poll(function()
                    return ec:create_campaign(name)
                end)
                if status == "ok" then
                    binding._creating = nil
                    if type(ec.forget_create) == "function" then ec:forget_create(name) end
                    state:set_campaign(tostring((summary or {}).name or name))
                elseif status ~= "pending" then
                    binding._creating = nil
                end
                return
            end

            if binding:_poll_ask(ec) then return end

            if state.campaign_name and state.campaign_name ~= "" then
                local name = state.campaign_name
                local status, loaded = state._slots.campaign:poll(function()
                    return ec:load_campaign(name)
                end)
                if status == "ok" then
                    state:apply_campaign(loaded)
                    if binding._revalidate then
                        binding._revalidate = nil
                        binding:_ask_editor("validate")
                    end
                end
                return
            end

            if not state.campaigns_loaded then
                local status, list = state._slots.list:poll(function() return ec:list_campaigns() end)
                if status == "ok" then state:set_campaigns(list) end
            end
        end,
        dispatch = function(command, ctx)
            local state = binding._state
            local recorder = binding._recorder

            if command.kind == "create_campaign" then
                local name = state:pending_campaign_name()
                if name == "" then
                    state.error = "name the campaign before creating it"
                    return true, state.error
                end
                local ec, unavailable = binding:_editor()
                if not ec then
                    state.error = unavailable
                    return true, unavailable
                end
                -- The create is only STARTED here. The panel opens the campaign when the editor
                -- answers, on a later tick -- not on the assumption that it will.
                binding._creating = name
                state.name_input:set_value("")
                state._slots.create:reset()
                state.error = nil
                state._dirty = true
                return true, "creating campaign '" .. name .. "'"
            elseif command.kind == "cancel_campaign_name" then
                state.name_input:set_value("")
                return true
            elseif command.kind == "open_campaign" then
                local ec, unavailable = binding:_editor()
                if not ec then
                    state.error = unavailable
                    return true, unavailable
                end
                state:set_campaign(command.name)
                return true, "opening campaign '" .. tostring(command.name) .. "'"
            elseif command.kind == "close_campaign" then
                state:close_campaign()
                return true
            elseif command.kind == "select_node" then
                state:select_node(command.node_id)
                publish_selection(ctx, Graph.id, "node", command.node_id)
                return true
            elseif command.kind == "toggle_expand" then
                state:toggle_expand_node(command.node_id)
                return true
            elseif command.kind == "remove_node" then
                state:remove_node(command.node_id)
                return true
            elseif command.kind == "show_add_node_menu" then
                -- For v1 the template is a Kill node. It is WRITTEN, not inserted locally: a node
                -- that appears because the panel assumed the write worked looks exactly like a node
                -- the editor stored, and that is how the last cycle shipped phantom authoring.
                return binding:_write_node("questing.Kill")
            elseif command.kind == "edit_intent" then
                -- Placeholder: would prompt for a new value via the editor crate
                return true, "edit_intent " .. tostring(command.node_id) .. ":" .. tostring(command.field) .. " (open editor)"
            elseif command.kind == "toggle_waypoint" then
                state:toggle_waypoint_mode()
                return true
            elseif command.kind == "commit_waypoint" then
                state:commit_waypoint()
                return true
            elseif command.kind == "toggle_escort" then
                if state.escort_mode then
                    state:set_escort_mode(false)
                else
                    state:set_escort_mode(true)
                end
                return true
            elseif command.kind == "generate_escort_nodes" then
                state:generate_escort_nodes()
                return true
            elseif command.kind == "set_filter" then
                state:set_filter(command.node_type)
                return true
            elseif command.kind == "validate_graph" then
                return binding:_ask_editor("validate")
            elseif command.kind == "compile_graph" then
                return binding:_ask_editor("compile")
            elseif command.kind == "select_diagnostic" then
                -- A diagnostic that blames no node is still readable; it just does not navigate.
                local node_id = state:diagnostic_node(command.index)
                if not node_id then return true, "that diagnostic names no node" end
                state:select_node(node_id)
                publish_selection(ctx, Graph.id, "node", node_id)
                return true, "selected " .. node_id
            end
            return false, "unknown graph command '" .. tostring(command.kind) .. "'"
        end,
    }
end

-- ============================================================================
-- The Database binding (Phase 4 — Spawn Scanner, Grinding Area Generator)
-- ============================================================================

local DatabaseBinding = {}
DatabaseBinding.__index = DatabaseBinding

---@param opts table|nil { query_client = table|nil } a QueryClient instance, not a resolver
function IdePanels.new_database(opts)
    opts = opts or {}
    local self = setmetatable({}, DatabaseBinding)
    self._state = DatabaseState.new()
    self._query_client = opts.query_client
    return self
end

---Access the panel state, exposed so tests can inspect it.
function DatabaseBinding:state() return self._state end

---The panel spec the shell registers.
function DatabaseBinding:spec()
    local binding = self
    return {
        id = Database.id,
        title = Database.title,
        order = Database.order,
        render = function(window, bounds, _ctx)
            local view = binding._state:build()
            return Database.render(window, bounds, view)
        end,
        on_tick = function()
            local state = binding._state
            if not state._dirty then return end
            state._dirty = false

            local qc = binding._query_client
            if not qc then
                -- Detail and grind are server-backed; drop them here rather than letting the state
                -- reach its own nil-client branches, which currently answer with fabricated data.
                -- (That fabrication is removed wholesale in the mock-data sweep; this gate means the
                -- installed panel cannot reach it in the meantime.) The scan is NOT dropped: it
                -- reads the object manager, a different source that a dead QueryServer does not
                -- affect.
                state._pending_detail = false
                state._pending_grind = false
                mark_query_client_unavailable(state)
            end

            -- Execute pending scan
            if state._pending_scan then
                state:execute_scan(qc)
            end

            -- Load detail for selected entry
            if state._pending_detail then
                state:execute_load_detail(qc)
            end

            -- Execute grinding generation
            if state._pending_grind then
                state:execute_grind(qc)
            end
        end,
        dispatch = function(command, ctx)
            local state = binding._state
            if command.kind == "set_tab" then
                state:set_tab(command.tab)
                return true
            elseif command.kind == "scan" then
                state:request_scan()
                return true
            elseif command.kind == "cycle_scan_mode" then
                state:set_scan_mode(state.scan_mode == "nearby" and "manual" or "nearby")
                return true
            elseif command.kind == "cycle_range" then
                local ranges = { 25, 50, 75, 100 }
                for i, r in ipairs(ranges) do
                    if r == state.scan_range then
                        state:set_scan_range(ranges[(i % #ranges) + 1])
                        return true
                    end
                end
                state:set_scan_range(50)
                return true
            elseif command.kind == "set_filter" then
                state:set_scan_filter(command.filter)
                state:request_scan()
                return true
            elseif command.kind == "select_entry" then
                state:select_entry(command.entry)
                publish_selection(ctx, Database.id, "npc", command.entry)
                return true
            elseif command.kind == "view_detail" then
                -- "View NPC Detail" IS the spec's "Open in NPC Inspector": both land on the same
                -- selection, and the second one exists only because a row click and a button click
                -- arrive as different action ids.
                state:select_entry(command.entry)
                publish_selection(ctx, Database.id, "npc", command.entry)
                return true
            elseif command.kind == "add_as_kill" then
                return true, "add_as_kill: " .. tostring(command.entry) .. " (not yet implemented)"
            elseif command.kind == "generate_grind" then
                state:request_grind()
                return true
            elseif command.kind == "edit_grind_entry" then
                return true, "edit_grind_entry (open editor placeholder)"
            elseif command.kind == "edit_grind_zone" then
                return true, "edit_grind_zone (open editor placeholder)"
            end
            return false, "unknown database command '" .. tostring(command.kind) .. "'"
        end,
    }
end

-- ============================================================================
-- Installation
-- ============================================================================

---Register every panel the IDE ships with onto `shell`.
---
---This is the registration site U3-U7 extend — one line each, in a file neither the shell nor any
---panel reads. It is the only place where "which panels exist" and "what each one meets" meet.
---
---Phase 5 extensions (F12, F19, F20) are also created here and wired into panel specs. The shell
---renders whatever the panel's render function returns; wrapping the spec at install time is how
---the validation bar, stats dashboard, and travel editor compose with existing panels.
---@param shell table the IDE shell
---@param deps table|nil forwarded to each binding
---@return table|nil bindings, string|nil reason
function IdePanels.install(shell, deps)
    -- ====================================================================
    -- Create Phase 5 extension instances
    -- ====================================================================
    local validation = ValidationStatus.new()
    local stats = StatsDashboard.new()
    local travel = TravelEditorState.new()

    -- Store for getter access
    IdePanels._validation_bar = validation
    IdePanels._stats_dashboard = stats
    IdePanels._travel_editor = travel

    -- ====================================================================
    -- Validation bar — set on shell for footer rendering
    -- ====================================================================
    shell:set_validation_bar(function(window, bounds)
        local view = validation:build()
        local plan = ValidationStatus.build_plan(view, bounds)
        local activated = ValidationStatus.render(window, plan)
        if activated then
            local _, check_id = activated:match("^validation_expand:(.+)$")
            if check_id then
                validation:toggle_expand(check_id)
            end
        end
    end)

    -- ====================================================================
    -- Runner panel — wrap render/dispatch to include stats dashboard
    -- ====================================================================
    local runner = IdePanels.new_runner(deps)
    local runner_spec = runner:spec()
    local runner_render = runner_spec.render
    local runner_dispatch = runner_spec.dispatch
    runner_spec.render = function(window, bounds, ctx)
        local command = runner_render(window, bounds, ctx)
        if stats.visible then
            local view = stats:build()
            local plan = StatsDashboard.build_plan(view, bounds)
            StatsDashboard.render(window, plan)
        end
        return command
    end
    runner_spec.dispatch = function(command, ctx)
        if command.kind == "toggle_stats" then
            stats:toggle()
            return true
        end
        return runner_dispatch(command, ctx)
    end
    local ok, reason = shell:register_panel(runner_spec)
    if not ok then return nil, reason end

    -- ====================================================================
    -- Explorer panel — wrap render/dispatch to include travel editor
    -- ====================================================================
    -- Forward-declared on purpose. The Explorer's authoring commands write into whatever campaign
    -- the GRAPH panel has open, and that is why `campaign` is a resolver rather than a value: it
    -- changes under the Explorer every time the operator opens a different campaign.
    local graph
    local explorer_deps = setmetatable({
        campaign = deps.campaign or function() return graph and graph:campaign_name() or nil end,
    }, { __index = deps })
    local explorer = IdePanels.new_explorer(explorer_deps)
    local explorer_spec = explorer:spec()
    local explorer_render = explorer_spec.render
    local explorer_dispatch = explorer_spec.dispatch
    explorer_spec.render = function(window, bounds, ctx)
        local command = explorer_render(window, bounds, ctx)
        if travel.activated then
            local view = travel:build()
            local plan = TravelEditorState.build_plan(view, bounds)
            local editor_cmd = TravelEditor.render(window, bounds, view)
            -- Merge editor commands into the returned command
            if editor_cmd and not command then
                command = editor_cmd
            end
        end
        return command
    end
    explorer_spec.dispatch = function(command, ctx)
        if command.kind == "travel_toggle" then
            travel:toggle()
            return true
        elseif command.kind == "travel_select_route" then
            travel:select_route(command.route_id)
            return true
        elseif command.kind == "travel_toggle_edit" then
            travel:set_editing(not travel.editing_waypoints)
            return true
        elseif command.kind == "travel_move_waypoint" then
            if command.direction == "up" then
                travel:move_waypoint_up(command.route_id, command.index)
            else
                travel:move_waypoint_down(command.route_id, command.index)
            end
            return true
        elseif command.kind == "travel_add_waypoint" then
            return true, "travel_add_waypoint (not yet implemented — requires player position)"
        end
        return explorer_dispatch(command, ctx)
    end
    local ok2, reason2 = shell:register_panel(explorer_spec)
    if not ok2 then return nil, reason2 end

    -- ====================================================================
    -- Regular panels (no extensions)
    -- ====================================================================
    local properties = IdePanels.new_properties(deps)
    local ok3, reason3 = shell:register_panel(properties:spec())
    if not ok3 then return nil, reason3 end

    -- The other end of the selection channel. Subscribed exactly once, here, because this is the
    -- only file that may know both that a shell has a channel and that Properties is the inspector.
    --
    -- FOCUS-FOLLOW: a selection made ELSEWHERE brings the inspector to the front, because the whole
    -- point of selecting an NPC in the Database is to look at it — leaving the operator to find the
    -- Properties tab themselves is the same dead end as not routing the selection at all. A
    -- selection made INSIDE Properties does not re-activate it: the panel is already in front, and
    -- an activate() from its own dispatch would fight a tab the operator just switched away from.
    shell:on_selection(function(event)
        properties:state():set_context({
            selection_type = event.kind,
            selection_id = event.id,
        })
        if event.panel_id ~= Properties.id then shell:activate(Properties.id) end
    end)

    graph = IdePanels.new_graph(deps)
    local ok4, reason4 = shell:register_panel(graph:spec())
    if not ok4 then return nil, reason4 end

    local database = IdePanels.new_database(deps)
    local ok5, reason5 = shell:register_panel(database:spec())
    if not ok5 then return nil, reason5 end

    return {
        runner = runner,
        explorer = explorer,
        properties = properties,
        graph = graph,
        database = database,
        validation = validation,
        stats = stats,
        travel = travel,
    }
end

-- ============================================================================
-- Phase 5 extension accessors (F12, F19, F20)
-- ============================================================================

---Return the ValidationStatus instance, or nil if install hasn't run.
function IdePanels.get_validation_bar()
    return IdePanels._validation_bar
end

---Return the StatsDashboard instance, or nil if install hasn't run.
function IdePanels.get_stats_dashboard()
    return IdePanels._stats_dashboard
end

---Return the TravelEditorState instance, or nil if install hasn't run.
function IdePanels.get_travel_editor()
    return IdePanels._travel_editor
end

return IdePanels
