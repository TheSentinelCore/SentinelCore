--- Sentinel Questing Module
--- Handles quest execution for a leveling route
---
--- Responsibilities:
--- - Load compiled profiles (Runtime JSON)
--- - Execute actions via Sylvanas APIs
--- - Track quest state and progress
--- - Navigate between objectives
---
--- It owns NO UI. The in-game surface is the IDE shell (`sentinel/ui/`), which renders this
--- module's state through `runner_state.lua`; authoring lives outside the client entirely.

local RuntimeProfile = require("modules/questing/runtime_profile")
local RunnerState = require("modules/questing/runner_state")
local QuestLogSpace = require("modules/questing/quest_log_space")
local ProfileChain = require("modules/questing/profile_chain")
local Recorder = require("modules/questing/recorder")
-- The ONE HTTP layer to QueryServer. Resolving a recording is a POST where every other call is a
-- GET, which is a reason to extend that client and not to grow a second one beside it.
local QueryClient = require("shared/query_client")

-- JSON decoder for the chain manifest — same core/JSON the runtime uses, degrading to nil
-- when the sandbox lib is absent (offline tests inject the manifest directly instead).
local ChainJson = (function()
    local ok, mod = pcall(require, "core/JSON")
    if ok and type(mod) == "table" and mod.decode then
        return mod
    end
    return nil
end)()
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")

local QuestingModule = {}
QuestingModule.__index = QuestingModule

-- Compiled RuntimeProfile JSON lives alongside the existing sentinel data tree in the loader's
-- scripts_data sandbox. Legacy .yaml route files share this folder; list_profiles filters to
-- .json so the two coexist without collision.
local PROFILE_DIR = "sentinel/data/profiles/quests"

-- Chain manifest (RestedXP `#next` route order, class-guarded) deployed alongside the
-- compiled profiles. When present, a finished profile hands off to its successor.
local CHAIN_FILE = "chain.json"

-- Recorded campaigns get their OWN folder rather than sitting beside the compiled profiles. A
-- recording is authoring input sentinel-resolver still has to lower, and list_profiles() offers
-- every .json in the profile directory to the runner — a recording dropped in there would be
-- listed as a runnable route and fail to load as one.
local RECORDING_DIR = "sentinel/data/recordings"

local function now_s()
    return (core and core.time and core.time()) or 0
end

-- The quest-sync refresh walks the full quest log plus every profile operation; per-tick it
-- dominated the tick cost for a panel humans read at seconds granularity.
local QUEST_SYNC_INTERVAL = 5.0

-- Recent step-completion timestamps kept for the windowed ETA (runner_state.build).
local COMPLETION_WINDOW = 10

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
    -- Pause clock: paused wall time is accumulated so elapsed/ETA never count it.
    o._paused_at = nil
    o._paused_accum = 0
    o._recent_completions = {}
    o._last_status_message = nil
    -- View cache: one RunnerState.build per tick timestamp (render calls get_view per frame).
    o._view_cache = nil
    o._view_cache_at = nil

    -- Vendor maintenance (bags full / broken gear). "Inventory is full." arrives only via
    -- UI_ERROR_MESSAGE (bridged as game:ui_error) — get_num_bag_slots returns 0 in the
    -- live client, so there is nothing to poll. The flag is consumed by
    -- _run_vendor_maintenance in tick().
    o._maintenance = { state = "idle", vendor_entry = nil, started_at = nil, last_scan_at = nil }

    -- Recording Mode (ADR 09a W12). Built with THIS module's bus, which is the app's shared bus
    -- whenever the registry constructs us — never a private one. runtime_profile.lua's constructor
    -- already records what a private bus costs: world_observer.lua publishes the eight `game:*`
    -- topics onto the app bus and onto nothing else, so a recorder listening elsewhere would pass
    -- every unit test and capture an empty campaign in game.
    --
    -- Constructed, deliberately NOT started: `Recorder:start` is what subscribes, and the observer
    -- is subscriber-gated, so an idle recorder means zero SDK reads for every character that is not
    -- deliberately recording.
    o._recorder = Recorder:new({ event_bus = o._event_bus })
    o._recording_started_at = nil
    o._event_bus:subscribe("game:ui_error", function(payload)
        local msg = tostring(payload and payload.message or ""):lower()
        if msg:find("inventory is full", 1, true) then
            o._blackboard:set("player.bags_full", true)
        elseif msg:find("quest log is full", 1, true) then
            o:_handle_quest_log_full()
        end
    end)

    return o
end

--- Quest-log-full recovery: the client error fires while the executor's AcceptQuest is
--- mid-retry. Sacrifice a quest no operation from the current one forward references
--- (selection is pure — quest_log_space.lua) via the documented three-step abandon flow;
--- the accept's own retry then proceeds into the freed slot. A log made entirely of
--- route-relevant quests abandons nothing — the accept's retry budget bounds advancement.
function QuestingModule:_handle_quest_log_full()
    local ex = self._executor
    if not (ex and ex._profile and type(ex._profile.operations) == "table") then return end
    local ops = ex._profile.operations
    local op = ops[ex._current_operation_idx or 1]
    local action = op and op.actions and op.actions[ex._current_action_idx or 1]
    if not (action and action.type == "AcceptQuest") then return end

    local q = core and core.quests
    if not (q and q.get_num_quest_log_entries and q.get_quest_log_title
        and q.select_quest_log_entry and q.set_abandon_quest and q.abandon_quest) then
        return
    end

    local entries = {}
    local num = q.get_num_quest_log_entries() or 0
    for i = 1, num do
        local ok, info = pcall(q.get_quest_log_title, i)
        if ok and info and not info.is_header and info.quest_id ~= nil then
            entries[#entries + 1] = {
                index = i,
                quest_id = info.quest_id,
                is_complete = info.is_complete,
            }
        end
    end

    local log_event = function(event, data)
        if type(ex._log_event) == "function" then
            ex:_log_event(event, data)
        else
            self._event_bus:publish("questing:log", { event = event, quest_id = data and data.quest_id })
        end
    end

    local victim = QuestLogSpace.select_sacrificial_quest(
        entries, ops, ex._current_operation_idx or 1)
    if not victim then
        log_event("quest_log_full_unrecoverable", {})
        return
    end

    pcall(q.select_quest_log_entry, victim.index)
    pcall(q.set_abandon_quest)
    pcall(q.abandon_quest)
    log_event("quest_abandoned_for_space", { quest_id = victim.quest_id })
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

    local sync_now = now_s()
    if not self._last_quest_sync_at
        or (sync_now - self._last_quest_sync_at) >= QUEST_SYNC_INTERVAL then
        self._last_quest_sync_at = sync_now
        self:_refresh_quest_sync()
    end

    -- Guardrails are evaluated BEFORE executing: an unattended run that has tripped its limit
    -- must halt on this tick, not after one more action.
    local view = self:get_view()
    if view.guardrails.tripped then
        self:pause()
        self._event_bus:publish("questing:guardrail_tripped", { reason = view.guardrails.reason })
        return
    end

    -- Unattended survival: full bags or badly broken gear preempt the route with a vendor
    -- detour. Returns true while the detour owns the tick; the route resumes exactly where
    -- it was (leading Travels re-satisfy instantly).
    if self:_maintenance_needed() and self:_run_vendor_maintenance() then
        self:_invalidate_view()
        return
    end

    -- The status message feeds get_view directly (blackboard writes here had zero readers).
    local status, message = self._executor:execute()
    self._last_status_message = message

    -- Liveness marker: record when the run last actually moved forward, so the cockpit can tell
    -- a healthy wait from a wedged one. Completion timestamps feed the windowed ETA.
    local op_idx = self._executor._current_operation_idx
    if op_idx ~= self._last_operation_idx then
        self._last_operation_idx = op_idx
        self._last_progress_at = now_s()
        local ring = self._recent_completions
        ring[#ring + 1] = self._last_progress_at
        if #ring > COMPLETION_WINDOW then table.remove(ring, 1) end
    end
    if self._executor._state == "ghost" and not self._counted_death then
        self._deaths = self._deaths + 1
        self._counted_death = true
    elseif self._executor._state ~= "ghost" then
        self._counted_death = false
    end

    -- Terminal failure. `error` is what RuntimeProfile answers once `_state == "failed"`, and it
    -- answers the same thing on every later tick — nothing about re-executing changes it. Park the
    -- run and tell the cockpit ONCE instead of spinning an executor that can no longer progress.
    -- Recovery is skip_current_step (which clears the terminal state) followed by resume.
    if status == "error" then
        self:pause()
        self._event_bus:publish("questing:failed", {
            reason = message,
            path = self._executor._json_path,
            consecutive_failures = self._executor._consecutive_failures,
        })
        self:_invalidate_view()
        return
    end

    if status == "finished" then
        -- 1-70 continuity: a completed zone hands off to its RestedXP chain successor for
        -- this character's class. Only when there is no successor (end of chain, no manifest,
        -- or the next zone isn't compiled yet) does the run truly finish.
        if not self:_advance_to_next_profile() then
            self._enabled = false
            self._blackboard:set("module.questing.enabled", false)
            self._event_bus:publish("questing:finished", {
                path = self._executor._json_path
            })
        end
    end

    -- Execution just mutated the state the cached view was built from.
    self:_invalidate_view()
end

function QuestingModule:shutdown()
    self._enabled = false
    self._blackboard:set("module.questing.enabled", false)
    -- Release the observer's subscriber gate. Left subscribed, a torn-down module keeps
    -- world_observer.lua walking the full quest log (~85 SDK calls) every five seconds on behalf of
    -- a recorder nothing can reach any more.
    if self._recorder:is_recording() then
        self:stop_recording()
    end
end

function QuestingModule:is_enabled()
    return self._enabled
end

-- ======================================================================
-- Vendor maintenance: bags full / broken gear → detour to the nearest
-- visible vendor, sell greys, repair, resume the route.
-- ======================================================================

local MAINTENANCE_SCAN_INTERVAL = 5.0    -- seconds between vendor scans while triggered
local MAINTENANCE_TIMEOUT = 120.0        -- give up on one detour after this long
local REPAIR_POLL_INTERVAL = 30.0        -- seconds between repair-cost polls
local REPAIR_THRESHOLD_COPPER = 500      -- detour once repairs cost more than this

--- Should the route be preempted for vendor maintenance right now?
--- Bags-full arrives via UI_ERROR_MESSAGE (see the game:ui_error subscription);
--- repair need is polled cheaply from get_total_repair_cost.
function QuestingModule:_maintenance_needed()
    if self._blackboard:get("player.bags_full") == true then
        return true
    end
    local now = now_s()
    -- nil marker: the FIRST check is always due (also keeps this testable offline where
    -- the clock reads a constant 0).
    if self._last_repair_poll_at == nil or now - self._last_repair_poll_at >= REPAIR_POLL_INTERVAL then
        self._last_repair_poll_at = now
        local threshold = tonumber(self._blackboard:get("module.questing.repair_threshold_copper"))
            or REPAIR_THRESHOLD_COPPER
        if core and core.inventory and core.inventory.get_total_repair_cost then
            local ok, cost = pcall(core.inventory.get_total_repair_cost)
            self._needs_repair = ok and tonumber(cost) ~= nil and cost > threshold
        end
    end
    return self._needs_repair == true
end

--- Nearest VISIBLE vendor: scan the object manager for unique creature entries and ask
--- QueryServer (cached) which of them vend. Fails safe to nil — no object manager, no
--- QueryServer, or simply no vendor in draw distance.
function QuestingModule:_find_visible_vendor()
    if not (core and core.object_manager and core.object_manager.get_all_objects) then
        return nil
    end
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then
        return nil
    end
    local query = self._executor and self._executor._query
    if not (query and query.get_vendor) then
        return nil
    end
    self._vendor_cache = self._vendor_cache or {}

    local player = core.object_manager.get_local_player
        and core.object_manager.get_local_player() or nil
    local ppos = nil
    if player and player.get_position then
        local ok_p, pos = pcall(player.get_position, player)
        if ok_p then ppos = pos end
    end

    local best_entry, best_dist = nil, math.huge
    local seen = {}
    for _, obj in ipairs(objects) do
        local is_unit = obj and obj.get_npc_id and obj.is_dead
        if is_unit then
            local ok_id, npc_id = pcall(obj.get_npc_id, obj)
            if ok_id and npc_id and npc_id > 0 and not seen[npc_id] then
                seen[npc_id] = true
                local vends = self._vendor_cache[npc_id]
                if vends == nil then
                    local ok_v, info = pcall(query.get_vendor, query, npc_id)
                    vends = ok_v and type(info) == "table"
                    self._vendor_cache[npc_id] = vends
                end
                if vends then
                    local ok_dead, dead = pcall(obj.is_dead, obj)
                    if ok_dead and dead ~= true and ppos and obj.get_position then
                        local ok_pos, opos = pcall(obj.get_position, obj)
                        if ok_pos and opos then
                            local dx = (opos.x or 0) - (ppos.x or 0)
                            local dy = (opos.y or 0) - (ppos.y or 0)
                            local dz = (opos.z or 0) - (ppos.z or 0)
                            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                            if dist < best_dist then
                                best_dist = dist
                                best_entry = npc_id
                            end
                        end
                    end
                end
            end
        end
    end
    return best_entry
end

--- A KNOWN vendor to fall back on when none is visible. Bags fill at remote grind spots
--- (live-caught: the backpack filled while grinding Kobold Laborers at Echo Ridge, no vendor
--- in draw distance, so the visible-only detour never triggered and the grind stalled). The
--- compiled profile carries no Vendor-role NPCs, but it DOES carry Vendor actions with
--- npc_entry — return the one whose operation is nearest the current route position (a good
--- proxy for geographically nearest), so the detour can navigate to it via QueryServer.
function QuestingModule:_find_known_vendor()
    local ex = self._executor
    local ops = ex and ex._profile and ex._profile.operations
    if type(ops) ~= "table" then return nil end
    local cur = ex._current_operation_idx or 1
    local best_entry, best_gap = nil, math.huge
    for idx, op in ipairs(ops) do
        for _, a in ipairs(op.actions or {}) do
            if (a.type == "Vendor" or a.type == "Repair")
                and a.payload and a.payload.npc_entry then
                local gap = math.abs(idx - cur)
                if gap < best_gap then
                    best_gap = gap
                    best_entry = a.payload.npc_entry
                end
            end
        end
    end
    return best_entry
end

function QuestingModule:_end_maintenance(reason)
    self._maintenance.state = "idle"
    self._maintenance.vendor_entry = nil
    self._maintenance.started_at = nil
    self._blackboard:set("module.questing.maintenance", reason)
    self._event_bus:publish("questing:maintenance_ended", { reason = reason })
end

--- Drive one tick of the vendor detour. Returns true while the detour owns the tick.
function QuestingModule:_run_vendor_maintenance()
    local ex = self._executor
    if not ex then return false end
    local now = now_s()
    local m = self._maintenance

    if m.state == "idle" then
        -- nil marker: the first scan is always due (frozen offline clocks included).
        if m.last_scan_at ~= nil and now - m.last_scan_at < MAINTENANCE_SCAN_INTERVAL then
            return false
        end
        m.last_scan_at = now
        -- Prefer a vendor already in view; otherwise fall back to a known route vendor and
        -- navigate to it (the "vendoring" blocked-branch below walks there). Without this
        -- fallback, bags that fill at a remote grind spot never get sold and the run stalls.
        local entry = self:_find_visible_vendor() or self:_find_known_vendor()
        if not entry then
            self._blackboard:set("module.questing.maintenance", "triggered, no vendor known")
            return false
        end
        m.state = "vendoring"
        m.vendor_entry = entry
        m.started_at = now
        self._event_bus:publish("questing:maintenance_started", { vendor = entry })
    end

    if m.state == "vendoring" then
        if now - (m.started_at or now) > MAINTENANCE_TIMEOUT then
            self:_end_maintenance("timeout")
            return false
        end
        local RuntimeAction = require("modules/questing/runtime_action")
        local ctx = ex:create_context()
        local status = RuntimeAction.execute_vendor(
            { npc_entry = m.vendor_entry, sell_grey = true, repair = true }, ctx)
        if status == "success" then
            self._blackboard:set("player.bags_full", false)
            self._needs_repair = false
            self:_end_maintenance("done")
            return false
        elseif status == "blocked" then
            -- Not at the vendor yet — walk there ourselves (the executor's NAVIGATING
            -- state belongs to the route, not to this detour).
            local npc_pos = ex._get_npc_position and ex:_get_npc_position(m.vendor_entry) or nil
            if npc_pos and ctx.nav and ctx.nav.is_active and not ctx.nav:is_active() then
                pcall(function() ctx.nav:move_to(npc_pos, { tolerance = 4.0 }) end)
            end
            return true
        end
        -- retry/waiting: hold the tick and try again.
        return true
    end
    return false
end

-- ======================================================================
-- Runner cockpit control surface
-- ======================================================================

--- Drop the cached view after any state change a control verb or tick makes.
function QuestingModule:_invalidate_view()
    self._view_cache = nil
    self._view_cache_at = nil
end

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
    self._paused_at = nil
    self._paused_accum = 0
    self._recent_completions = {}
    self._last_status_message = nil
    self:_invalidate_view()
    self._event_bus:publish("questing:started", { path = profile_path })
    return true
end

--- Halt execution while keeping the executor, so progress is not lost. The session clock
--- stops with it: paused time must not inflate elapsed, ETA, or the stall detector.
function QuestingModule:pause()
    if not self._paused then
        self._paused_at = now_s()
    end
    self._paused = true
    self._blackboard:set("module.questing.paused", true)
    self:_invalidate_view()
end

function QuestingModule:resume()
    if self._paused and self._paused_at then
        local paused_for = now_s() - self._paused_at
        if paused_for > 0 then
            self._paused_accum = self._paused_accum + paused_for
            -- Shift the executor's wait clock past the pause so is_stalled cannot
            -- false-trip to STUCK the moment the run resumes.
            if self._executor and self._executor._wait_started_at then
                self._executor._wait_started_at = self._executor._wait_started_at + paused_for
            end
        end
    end
    self._paused_at = nil
    self._paused = false
    self._blackboard:set("module.questing.paused", false)
    self:_invalidate_view()
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
    self:_invalidate_view()
    self._event_bus:publish("questing:stopped", {})
end

--- Manual recovery: abandon the current operation and move to the next one.
---
--- This is also the ONLY exit from the executor's terminal `failed` state. `failed` is entered by
--- `_check_consecutive_failures` after MAX_CONSECUTIVE_FAILURES (3), after which `execute()` can
--- only answer "error" forever. Resetting the indices without resetting `_state` left the run just
--- as dead as before the skip — an unattended bot ended its session on three bad actions and only
--- stop() + start() could revive it. Clearing `_consecutive_failures` matters just as much: a
--- carried-over tally of 3 would re-trip `failed` on the very next single failure.
function QuestingModule:skip_current_step()
    if not self._executor then return false end
    self._executor._current_operation_idx = (self._executor._current_operation_idx or 1) + 1
    self._executor._current_action_idx = 1
    self._executor._current_action_retries = 0
    self._executor._state = "running"
    self._executor._consecutive_failures = 0
    -- Releasing the wait timer matters: without it the next gate inherits a stale start time.
    self._executor._wait_started_at = nil
    self._executor._wait_action_key = nil
    self._last_progress_at = now_s()
    self:_invalidate_view()
    self._event_bus:publish("questing:step_skipped", {
        operation = self._executor._current_operation_idx,
    })
    return true
end

function QuestingModule:set_guardrails(cfg)
    self._guardrails = cfg or {}
    self:_invalidate_view()
end

--- Basename of a compiled profile path minus the .json extension — its chain slug.
local function profile_slug(json_path)
    if type(json_path) ~= "string" then return nil end
    return json_path:match("([^/\\]+)%.json$")
end

--- Lazily load and cache the chain manifest from <profile_dir>/chain.json. A missing or
--- unparseable manifest caches a negative so a chainless deployment does not re-read the
--- disk on every profile completion. Tests inject `_chain` directly to bypass file IO.
--- @return table|nil manifest
function QuestingModule:_load_chain()
    if self._chain ~= nil then
        return self._chain or nil
    end
    self._chain = false -- negative cache until proven otherwise
    if not (ChainJson and core and core.read_data_file) then return nil end
    local ok, text = pcall(core.read_data_file, self._profile_dir .. "/" .. CHAIN_FILE)
    if not ok or type(text) ~= "string" then return nil end
    local ok2, decoded = pcall(ChainJson.decode, text)
    if ok2 and type(decoded) == "table" and type(decoded.entries) == "table" then
        self._chain = decoded
        return decoded
    end
    return nil
end

--- On profile completion, resolve and start the next profile in the RestedXP chain for the
--- character's class. Returns true only when a successor was actually started (keeping the
--- run alive); false at the end of the chain, with no manifest, or when the resolved
--- successor has not been compiled — so the caller finalizes the run exactly as before.
function QuestingModule:_advance_to_next_profile()
    local chain = self:_load_chain()
    if not chain then return false end
    local slug = profile_slug(self._executor and self._executor._json_path)
    if not slug then return false end

    -- Class decides the branch (e.g. Warlock takes a different Loch Modan). Fail safe to
    -- "Unknown" — the resolver simply won't match a class-guarded link, ending the chain.
    local class_name = "Unknown"
    if self._executor and self._executor.create_context then
        local ctx = self._executor:create_context()
        if ctx and ctx.get_player_class then
            local ok, name = pcall(ctx.get_player_class, ctx)
            if ok and type(name) == "string" then class_name = name end
        end
    end

    local next_slug = ProfileChain.next_slug(chain, slug, class_name)
    if not next_slug then return false end

    -- Never start a successor that isn't compiled on disk — surface the gap instead of
    -- faulting on a missing file.
    local available = {}
    for _, stem in ipairs(self:list_profiles()) do available[stem] = true end
    if not available[next_slug] then
        self._event_bus:publish("questing:chain_dead_end", {
            from = slug, next_slug = next_slug, reason = "successor not compiled",
        })
        return false
    end

    self._event_bus:publish("questing:chain_advance", { from = slug, to = next_slug })
    return self:start(self._profile_dir .. "/" .. next_slug .. ".json")
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

--- One snapshot for the cockpit to render. Built at most once per tick timestamp: tick
--- (guardrails) and every render frame all read the same cached table until the clock
--- advances or a control verb invalidates it.
function QuestingModule:get_view()
    local now = now_s()
    if self._view_cache and self._view_cache_at == now then
        return self._view_cache
    end
    local ex = self._executor
    local nav = ex and ex._nav or nil
    local paused_s = self._paused_accum
        + (self._paused_at and math.max(now - self._paused_at, 0) or 0)
    self._view_cache = RunnerState.build({
        executor = ex,
        now = now,
        started_at = self._started_at or now,
        last_progress_at = self._last_progress_at,
        deaths = self._deaths,
        guardrails = self._guardrails,
        tracked_quests = self._blackboard:get("module.questing.tracked_quests", nil),
        quest_log = self._blackboard:get("module.questing.quest_log", nil),
        nav_error = (nav and nav.get_last_error) and nav:get_last_error() or nil,
        status_message = self._last_status_message,
        module_faults = self._blackboard:get("system.module_faults", nil),
        maintenance = self._maintenance,
        paused_s = paused_s,
        recent_completions = self._recent_completions,
    })
    self._view_cache_at = now
    return self._view_cache
end

-- ======================================================================
-- Recording Mode control surface (ADR 09a W12)
--
-- These are what an operator drives, from the menu or through the debug bridge. They answer with a
-- table rather than a boolean on purpose: a one-shot `game_eval` of `Sentinel.stop_recording()`
-- that returns `false` tells the human nothing about whether they forgot to start, whether the
-- module is up, or whether the write failed.
-- ======================================================================

local function count_nodes(campaign)
    local graph = campaign and campaign.graphs and campaign.graphs[1]
    return (graph and #graph.nodes) or 0
end

--- A filename a human can find again, and that the loader will accept. `core.write_data_file` takes
--- the path verbatim, so a zone name with spaces or an apostrophe ("Thousand Needles", "Dun Morogh")
--- has to be flattened before it becomes one.
local function recording_slug(name)
    local slug = tostring(name or "recording"):lower():gsub("[^%w]+", "_")
    slug = slug:gsub("^_+", ""):gsub("_+$", "")
    if slug == "" then return "recording" end
    return slug
end

--- Name an unnamed recording after where and when it was taken. A recording called "Recording" is
--- one a human cannot tell apart from the four others they took that evening.
local function default_recording_name()
    local zone = nil
    if core and core.get_map_name then
        local ok, name = pcall(core.get_map_name)
        if ok and type(name) == "string" and name ~= "" then zone = name end
    end
    return string.format("%s %d", zone or "Recording", math.floor(now_s()))
end

--- Begin a recording. Subscribing is what wakes the subscriber-gated world observer, so this call is
--- also the moment the client starts paying for Recording Mode.
--- @return table `{ ok, name, started_at }` or `{ ok = false, reason }`
function QuestingModule:start_recording(name)
    if self._recorder:is_recording() then
        -- `Recorder:start` stops and DISCARDS the campaign in progress when called twice. That is
        -- the right behaviour for the recorder (two play sessions must never blend into one route)
        -- and the wrong one for an operator who mistyped, so the refusal lives here instead.
        return {
            ok = false,
            reason = "a recording is already in progress; stop it first",
            name = self._recorder:get_campaign() and self._recorder:get_campaign().name or nil,
        }
    end

    local chosen = (type(name) == "string" and name ~= "") and name or default_recording_name()
    self._recorder:start(chosen)
    self._recording_started_at = now_s()
    self._event_bus:publish("questing:recording_started", { name = chosen })
    return { ok = true, name = chosen, started_at = self._recording_started_at }
end

--- Stop recording and hand back what was captured. The campaign stays readable afterwards so the
--- operator can inspect it and save it separately.
--- @return table `{ ok, name, nodes, campaign }` or `{ ok = false, reason }`
function QuestingModule:stop_recording()
    if not self._recorder:is_recording() then
        return { ok = false, reason = "no recording in progress" }
    end
    local campaign = self._recorder:stop()
    local nodes = count_nodes(campaign)
    self._event_bus:publish("questing:recording_stopped", {
        name = campaign and campaign.name or nil,
        nodes = nodes,
    })
    return {
        ok = true,
        name = campaign and campaign.name or nil,
        nodes = nodes,
        campaign = campaign,
    }
end

function QuestingModule:is_recording()
    return self._recorder:is_recording()
end

--- What the operator (or the menu) needs to see in one read.
function QuestingModule:recording_status()
    local campaign = self._recorder:get_campaign()
    return {
        recording = self._recorder:is_recording(),
        name = campaign and campaign.name or nil,
        nodes = count_nodes(campaign),
        started_at = self._recording_started_at,
    }
end

--- The captured campaign, live. Returns nil until a recording has been started — a module that has
--- never recorded must not hand back an empty graph that reads like a finished session.
function QuestingModule:get_recording()
    return self._recorder:get_campaign()
end

--- Write the campaign to the scripts_data sandbox through `core.write_data_file` (there is no `io`).
--- @param path string|nil explicit path; defaults to <RECORDING_DIR>/<slug>.json
--- @return table `{ ok, path, name, nodes }` or `{ ok = false, reason }`
function QuestingModule:save_recording(path)
    local campaign = self._recorder:get_campaign()
    if not campaign then
        return { ok = false, reason = "no recording to save" }
    end

    local target = (type(path) == "string" and path ~= "") and path
        or (RECORDING_DIR .. "/" .. recording_slug(campaign.name) .. ".json")

    if not self._recorder:save(target) then
        -- Recorder:save answers a bare boolean and swallows the cause (encode failure, absent file
        -- API, a create/write the loader refused). Naming the path is the one thing that makes the
        -- failure actionable from outside the client.
        return { ok = false, reason = "write failed: " .. target, path = target }
    end

    self._event_bus:publish("questing:recording_saved", { path = target, name = campaign.name })
    return { ok = true, path = target, name = campaign.name, nodes = count_nodes(campaign) }
end

-- ======================================================================
-- Recording -> plan -> run (ADR 09a W13)
--
-- The link the pipeline was missing. Recording Mode writes a Campaign and QueryServer's
-- POST /resolve lowers one into an ExecutionPlan, but nothing in the client joined them: an author
-- had to alt-tab out, curl the file by hand and drop the answer into the profile directory before
-- the route they had just walked could be run.
--
-- Everything here is ASYNCHRONOUS on purpose. `core.http_post` returns before the server answers and
-- has no blocking form; blocking a tick on the network stalls the game client, so `resolve_recording`
-- answers `pending` and the operator (or the bus subscriber) collects the result.
-- ======================================================================

local RESOLVE_PATH = "/resolve"

-- The same core/JSON the chain manifest reads through — aliased so this path does not read as if it
-- borrowed the chain loader's decoder. The Sylvannas sandbox has NO global JSON (query_client.lua
-- carries the same note), so a nil here means encode/decode is absent, not broken.
local Json = ChainJson

-- Enough of the resolver's complaints to act on without turning a one-line answer into a wall.
local DIAGNOSTIC_PREVIEW = 3

local function decode_json(text)
    if not (Json and Json.decode) or type(text) ~= "string" or text == "" then return nil end
    local ok, value = pcall(Json.decode, text)
    if ok and type(value) == "table" then return value end
    return nil
end

--- Every error body this server produces is `{"error": …}` (handlers.rs reads `/resolve`'s body as
--- Bytes precisely so a malformed campaign is not the one reply shaped differently). Falling back to
--- the raw text keeps a proxy's plain-text 502 readable instead of blank.
local function server_error(body)
    local decoded = decode_json(body)
    if decoded and decoded.error ~= nil then return tostring(decoded.error) end
    if type(body) == "string" and body ~= "" then return body end
    return "no detail from the server"
end

--- Where a name typed by an operator actually lives. A bare name is slugged exactly the way
--- `save_recording` slugs a campaign name, so "Northshire" finds the file that save wrote.
local function recording_path(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("/", 1, true) or name:find("\\", 1, true) then return name end
    if name:sub(-5) == ".json" then return RECORDING_DIR .. "/" .. name end
    return RECORDING_DIR .. "/" .. recording_slug(name) .. ".json"
end

--- Fold the resolver's diagnostics into something one answer can carry. Dropping them would defeat
--- the round trip: a 200 WITH diagnostics is a plan that lowered and a route with holes (an NPC with
--- no spawn, a quest the database does not know), and the author is the only one who can fix those.
local function summarize_diagnostics(diagnostics)
    local summary = { count = 0, errors = 0, warnings = 0, messages = {} }
    if type(diagnostics) ~= "table" then return summary end
    for _, entry in ipairs(diagnostics) do
        summary.count = summary.count + 1
        local severity = tostring((entry and entry.severity) or "Info")
        if severity == "Error" then
            summary.errors = summary.errors + 1
        elseif severity == "Warning" then
            summary.warnings = summary.warnings + 1
        end
        if #summary.messages < DIAGNOSTIC_PREVIEW then
            summary.messages[#summary.messages + 1] = string.format("[%s] %s: %s",
                severity,
                tostring((entry and entry.code) or "unknown"),
                tostring((entry and entry.message) or ""))
        end
    end
    return summary
end

--- The QueryServer client, built on first use: a character that never resolves must not pay for one,
--- and a suite that wants a double simply assigns `_query_client` before calling.
function QuestingModule:_resolver_client()
    if not self._query_client then
        self._query_client = QueryClient:new()
    end
    return self._query_client
end

--- Where the plan for a given recording lands. The stem carries over so the operator can tell which
--- recording a profile came from, and `list_profiles()` — which is how the runner discovers routes —
--- picks it up with no further wiring.
function QuestingModule:_plan_path_for(source)
    local stem = tostring(source):match("([^/\\]+)%.json$") or "recording"
    return self._profile_dir .. "/" .. stem .. ".json"
end

--- Persist the plan out of a 200 response. Writes the PLAN, never the envelope: `{plan, diagnostics}`
--- is not something `RuntimeProfile:load` can run, and it would sit in the profile directory looking
--- exactly like a route until someone selected it.
function QuestingModule:_store_plan(body, source, target)
    local response = decode_json(body)
    if not response or type(response.plan) ~= "table" then
        return {
            ok = false, status = "unusable_response", path = source,
            reason = "QueryServer answered 200 with a body carrying no plan; "
                .. "is something else listening on that port?",
        }
    end

    local diagnostics = summarize_diagnostics(response.diagnostics)

    if not (Json and Json.encode) then
        return { ok = false, status = "no_json", path = source,
                 reason = "no JSON encoder in this sandbox; the plan cannot be persisted",
                 diagnostics = diagnostics }
    end
    local encoded, err = Json.encode(response.plan, true)
    if type(encoded) ~= "string" or encoded == "" or err then
        return { ok = false, status = "encode_failed", path = source,
                 reason = "the resolved plan could not be re-encoded: " .. tostring(err),
                 diagnostics = diagnostics }
    end

    if not (core and core.write_data_file) then
        return { ok = false, status = "no_file_api", path = source, plan_path = target,
                 reason = "core.write_data_file is unavailable; the plan resolved but cannot land",
                 diagnostics = diagnostics }
    end
    -- The loader requires the file to exist before it can be written (recorder.lua:544 records what
    -- skipping this cost). `create_data_file` on an existing file is harmless.
    if core.create_data_file then pcall(core.create_data_file, target) end
    if pcall(core.write_data_file, target, encoded) ~= true then
        return { ok = false, status = "write_failed", path = source, plan_path = target,
                 reason = "resolved, but writing the plan to " .. target .. " failed",
                 diagnostics = diagnostics }
    end

    self._last_plan_path = target
    return {
        ok = true,
        -- A resolve with diagnostics must never read exactly like a clean one. The operator's whole
        -- signal from a one-shot eval is this string.
        status = diagnostics.count > 0 and "resolved_with_diagnostics" or "resolved",
        path = source,
        plan_path = target,
        profile = target:match("([^/\\]+)%.json$"),
        operations = #(response.plan.operations or {}),
        diagnostics = diagnostics,
    }
end

--- Turn one HTTP answer into one operator-facing record.
---
--- The three failures stay APART on purpose. `sentinel-resolver` went to real trouble to make an
--- unreadable database (500) distinguishable from an unresolvable reference (200 + diagnostic) and
--- from a campaign the server could not parse (400); collapsing them into "failed" here sends the
--- operator to restart a server that is running fine, or to edit a campaign that is correct.
function QuestingModule:_receive_resolution(http_code, body, source, target, url)
    local record
    if http_code == 200 then
        record = self:_store_plan(body, source, target)
    elseif http_code == 400 then
        record = {
            ok = false, status = "rejected", path = source,
            reason = "QueryServer could not read the campaign (400) -- the recording is the problem, "
                .. "not the server: " .. server_error(body),
        }
    elseif http_code == 500 then
        record = {
            ok = false, status = "backend_error", path = source,
            reason = "QueryServer failed while resolving (500) -- its game database, not the "
                .. "recording: " .. server_error(body),
        }
    elseif http_code == 0 then
        record = {
            ok = false, status = "unreachable", path = source,
            reason = "no answer from " .. tostring(url) .. " -- start QueryServer "
                .. "(cd SentinelQueryServer && SENTINEL_DB=../tbcmangos.sqlite cargo run)",
        }
    else
        record = {
            ok = false, status = "http_error", path = source,
            reason = "unexpected HTTP " .. tostring(http_code) .. " from " .. tostring(url)
                .. ": " .. server_error(body),
        }
    end

    -- `plan_path` is deliberately NOT backfilled onto a failure: naming a file for a request that
    -- never got an answer would send the operator looking for something that was never written.
    record.http_code = http_code
    self._last_resolve = record
    self._event_bus:publish("questing:recording_resolved", record)
    return record
end

--- Resolve a saved recording through QueryServer and leave the plan where the runner looks.
---
--- ASYNCHRONOUS: an `ok = true, status = "pending"` answer means the request left, NOT that a plan
--- exists. Poll `resolve_status()`, or subscribe to `questing:recording_resolved`.
---
--- @param name string|nil a campaign name, a file name, or a path; defaults to this session's recording
--- @return table `{ ok, status, path, plan_path, diagnostics }` — never raises
function QuestingModule:resolve_recording(name)
    if self._resolve_pending then
        return { ok = false, status = "busy",
                 reason = "a resolve is already in flight for " .. tostring(self._resolve_pending) }
    end

    local source = recording_path(name)
    if not source then
        -- The operator who just recorded and saved should not have to retype where it landed. The
        -- campaign stays readable after `stop_recording`, so its name is the same one save slugged.
        local campaign = self._recorder:get_campaign()
        source = campaign and campaign.name and recording_path(campaign.name) or nil
    end
    if not source then
        return { ok = false, status = "no_recording",
                 reason = "name a recording to resolve, or record and save one first" }
    end

    if not (core and core.read_data_file) then
        return { ok = false, status = "no_file_api", path = source,
                 reason = "core.read_data_file is unavailable in this sandbox" }
    end
    local read_ok, text = pcall(core.read_data_file, source)
    if not read_ok or type(text) ~= "string" or text == "" then
        return { ok = false, status = "missing_recording", path = source,
                 reason = "no readable recording at " .. source .. " -- save one first" }
    end

    local client = self:_resolver_client()
    local target = self:_plan_path_for(source)
    local url = client:_url(RESOLVE_PATH)

    -- Set BEFORE dispatch: a transport that answers inside the call would otherwise have its record
    -- overwritten by this placeholder.
    self._last_resolve = { ok = true, status = "pending", path = source, plan_path = target }
    self._resolve_pending = source

    local completed = nil
    local dispatched, why = client:post(RESOLVE_PATH, text, function(http_code, response)
        self._resolve_pending = nil
        completed = self:_receive_resolution(http_code, response, source, target, url)
    end)

    if not dispatched then
        self._resolve_pending = nil
        local record = { ok = false, status = "no_http", path = source,
                         reason = why or "core.http_post is unavailable in this sandbox" }
        self._last_resolve = record
        return record
    end

    -- An offline transport that answered inside the call already has the real result; returning the
    -- pending placeholder over it would make every test assert against a lie.
    if completed then return completed end

    return {
        ok = true, status = "pending", path = source, plan_path = target,
        reason = "resolve dispatched to " .. url .. "; poll Sentinel.resolve_status()",
    }
end

--- The last resolution, for an operator polling a request that had not answered yet.
function QuestingModule:resolve_status()
    return self._last_resolve
        or { status = "idle", reason = "nothing has been resolved this session" }
end

--- Run a resolved plan.
---
--- Loading is NOT reimplemented here: it goes through `start()`, which owns the executor, the session
--- counters and the `questing:started` event. A second loader beside this one is a second set of all
--- three to drift apart.
---
--- @param name string|nil a profile stem, file name, or path; defaults to the last plan resolved
--- @return table `{ ok, status, plan_path }` — never raises
function QuestingModule:run_plan(name)
    local target = nil
    if type(name) == "string" and name ~= "" then
        if name:find("/", 1, true) or name:find("\\", 1, true) then
            target = name
        elseif name:sub(-5) == ".json" then
            target = self._profile_dir .. "/" .. name
        else
            target = self._profile_dir .. "/" .. name .. ".json"
        end
    else
        target = self._last_plan_path
    end

    if not target then
        return { ok = false, status = "no_plan",
                 reason = "name a plan to run, or resolve a recording first" }
    end

    local ok, started = pcall(self.start, self, target)
    if not ok then
        return { ok = false, status = "load_failed", plan_path = target,
                 reason = "starting " .. target .. " raised: " .. tostring(started) }
    end
    if not started then
        return { ok = false, status = "load_failed", plan_path = target,
                 reason = "the plan at " .. target .. " did not load; see the questing:error event" }
    end
    return { ok = true, status = "running", plan_path = target }
end

-- ======================================================================
-- Editor integration
-- ======================================================================

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