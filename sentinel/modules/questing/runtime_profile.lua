--- Sentinel Runtime Profile Executor
--- Loads and executes a RuntimeProfile (compiled from sentinel-questing/compiler)
--- Uses Blackboard for state, EventBus for events

local RuntimeAction = require("modules/questing/runtime_action")
local Blackboard = require("core/blackboard")
local Compat = require("shared/compat")
local QueryClient = require("shared/query_client")
local Geometry = require("core/geometry")
local EventBus = require("core/event_bus")
local NavAdapter = require("integrations/nav_client/adapter")

-- ============================================================================
-- Named constants for proximity checks (W3.1, W3.2, W3.6)
-- ============================================================================
local INTERACT_RANGE = 5.0   -- Talking to NPCs, looting, interacting
local LOOT_RANGE = 5.0       -- Looting objects
local COMBAT_RANGE = 30.0     -- Spell / melee range
local ARRIVAL_TOLERANCE = 5.0 -- Close enough to destination

-- ============================================================================
-- Recovery state machine constants (W4.1, W4.4)
-- ============================================================================
local MAX_RETRIES_PER_ACTION = 5        -- Max retry attempts for one action
local MAX_CONSECUTIVE_FAILURES = 3      -- Max failures before profile stops
local NAV_TIMEOUT = 30.0                -- Seconds before navigation is considered timed out
local GHOST_TIMEOUT = 120.0             -- Seconds before ghost recovery is abandoned
local GHOST_RETRY_INTERVAL = 5.0        -- Seconds between death state checks

local RuntimeProfile = {}
RuntimeProfile.__index = RuntimeProfile

function RuntimeProfile:new(json_path)
    local o = setmetatable({}, RuntimeProfile)
    o._json_path = json_path
    o._profile = nil
    o._blackboard = Blackboard:new()
    o._query = QueryClient:new("127.0.0.1", 3030)
    o._current_operation_idx = 1
    o._current_op_id = nil              -- Tracks identity for retry reset
    o._variables = {}
    o._event_bus = EventBus:new()       -- W3.3
    o._nav = NavAdapter:new(o._event_bus) -- W3.3

    -- Recovery state machine (W4.1–W4.5)
    o._state = "running"                -- "running" | "navigating" | "ghost" | "failed" | "finished"
    o._current_action_retries = 0       -- Per-action retry count (W4.1)
    o._consecutive_failures = 0         -- Across-action failure count (W4.4)
    o._nav_start_time = nil             -- When navigation began (W4.2)
    o._ghost_start_time = nil           -- When death was detected (W4.3)
    o._last_blocked_action = nil        -- Copy of the action that triggered blocked
    o._execution_log = {}               -- Structured log entries (W4.5)

    -- Persistence (W5.2, W5.3)
    o._save_path = o:_compute_save_path()
    o._dirty = false                    -- Track unsaved changes
    return o
end

-- ====================================================================
-- Persistence helpers (W5.2)
-- ====================================================================

--- Derive the save file path from the profile JSON path.
--- e.g. "profiles/mage.json" → "profiles/mage.save.json"
function RuntimeProfile:_compute_save_path()
    local path = self._json_path or "questing"
    if path:match("%.json$") then
        return path:gsub("%.json$", ".save.json")
    end
    return path .. ".save.json"
end

--- Serialize current execution state for persistence.
function RuntimeProfile:_serialize_state()
    return {
        version = 1,
        profile_fingerprint = (self._profile and self._profile.content_hash) or "",
        current_operation_idx = self._current_operation_idx,
        variables = self._variables,
        saved_at = (_G.GetTime and _G.GetTime()) or 0,
    }
end

--- Persist execution state to disk.
--- Called on operation advance, variable change, stop, and reset.
function RuntimeProfile:_save()
    local data = self:_serialize_state()
    local json = nil
    if JSON and JSON.stringify then
        json = JSON.stringify(data)
    else
        -- Manual JSON serialization fallback
        json = self:_serialize_lua(data)
    end
    if not json then
        return false
    end
    if core and core.write_data_file then
        local ok, err = pcall(core.write_data_file, core, self._save_path, json)
        if ok then
            self._dirty = false
            return true
        end
    elseif core and core.write_file then
        local ok, err = pcall(core.write_file, core, self._save_path, json)
        if ok then
            self._dirty = false
            return true
        end
    end
    -- Fallback: write to standard Lua file
    local f, err = io.open(self._save_path, "w")
    if f then
        f:write(json)
        f:close()
        self._dirty = false
        return true
    end
    return false
end

--- Attempt to restore execution state from a previous save file.
--- Returns true if state was restored, false if no save or fingerprint mismatch.
function RuntimeProfile:_load_save()
    if not (core and core.read_data_file) then
        return false
    end
    local json, err = core.read_data_file(self._save_path)
    if not json then
        return false
    end
    local decoded = nil
    if JSON and JSON.parse then
        decoded = JSON.parse(json)
    else
        local fn, err = load("return " .. json)
        if fn then
            decoded = fn()
        end
    end
    if not decoded or type(decoded) ~= "table" then
        return false
    end
    -- Verify fingerprint matches current profile
    local profile_hash = self._profile and self._profile.content_hash or ""
    local save_fingerprint = decoded.profile_fingerprint or ""
    if profile_hash == "" or save_fingerprint == "" or save_fingerprint ~= profile_hash then
        return false -- Fingerprint mismatch or empty → start fresh
    end
    -- Restore state
    if type(decoded.current_operation_idx) == "number" then
        self._current_operation_idx = decoded.current_operation_idx
    end
    if type(decoded.variables) == "table" then
        self._variables = decoded.variables
    end
    self._dirty = false
    self:_log_event("save_restored", {
        operation = self._current_operation_idx,
        variable_count = self._variables and #self._variables or 0,
    })
    return true
end

--- Minimal Lua table serialization (compatible with load() parser).
--- Outputs Lua-like table literals that can be parsed by load("return ...").
function RuntimeProfile:_serialize_lua(t)
    if t == nil then return "nil" end
    if type(t) == "number" then return tostring(t) end
    if type(t) == "string" then return '"' .. t:gsub('"', '\\"') .. '"' end
    if type(t) == "boolean" then return t and "true" or "false" end
    if type(t) ~= "table" then return '"' .. tostring(t) .. '"' end
    -- Check if array-like (consecutive numeric keys starting at 1)
    local is_array = true
    local max_key = 0
    local count = 0
    for k, _ in pairs(t) do
        count = count + 1
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
            is_array = false
            break
        end
        if k > max_key then max_key = k end
    end
    if is_array and max_key == count then
        local parts = {}
        for i = 1, max_key do
            parts[i] = self:_serialize_lua(t[i])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    -- Table with mixed/string keys
    local parts = {}
    for k, v in pairs(t) do
        local key_str = type(k) == "string"
            and '["' .. k:gsub('"', '\\"') .. '"]'
            or "[" .. tostring(k) .. "]"
        parts[#parts + 1] = key_str .. "=" .. self:_serialize_lua(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function RuntimeProfile:load()
    if core and core.read_data_file then
        local json, err = core.read_data_file(self._json_path)
        if not json then
            return nil, err or "file not found"
        end
        local decoded = JSON and JSON.parse(json)
        if not decoded then
            decoded = load("return " .. json)()
        end
        self._profile = decoded

        -- W5.2 — Attempt to restore execution state from save file
        local restored = self:_load_save()
        if restored then
            self:_log_event("load_with_save", {
                operation = self._current_operation_idx,
            })
        else
            self:_log_event("load_fresh", {})
        end

        return true
    end
    return nil, "no data file API"
end

--- Runtime context with helper methods and Sylvanas API facade.
function RuntimeProfile:create_context()
    local ctx = {
        variables = self._variables,
        query = self._query,
        nav = self._nav,           -- W3.3: NavAdapter for movement

        -- Quest log tracking caches (W2.3, W2.4)
        _completed_quests = {},   -- { [quest_entry] = true }
        _active_quests = {},      -- { [quest_entry] = true }
        _quest_log_dirty = true,  -- refresh on next query
    }

    -- ====================================================================
    -- Navigation helpers (W3.1, W3.2, W3.3)
    -- ====================================================================

    --- Resolve player's current position.
    --- Returns {x, y, z} table or nil.
    function ctx:_get_player_pos()
        if core and core.object_manager and core.object_manager.get_local_player then
            local player = core.object_manager.get_local_player()
            if player and player.get_position then
                local ok, pos = pcall(player.get_position, player)
                if ok and type(pos) == "table" then
                    return pos
                end
            end
        end
        return nil
    end

    --- Check if a specific NPC entry is within interaction range.
    --- @param entry number|string NPC ID
    --- @param range number Override distance (default INTERACT_RANGE)
    --- @return boolean
    function ctx:is_at_npc(entry, range)
        range = range or INTERACT_RANGE
        if core and core.object_manager and core.object_manager.GetNearestCreature then
            local npc = core.object_manager.GetNearestCreature({ entry })
            if npc and npc.IsValid and npc:IsValid() then
                -- Try precise distance check
                local player_pos = self:_get_player_pos()
                if player_pos and npc.get_position then
                    local ok, npc_pos = pcall(npc.get_position, npc)
                    if ok and npc_pos then
                        return Geometry.distance(player_pos, npc_pos) <= range
                    end
                end
                return true -- NPC exists nearby; best-effort
            end
        end
        return false
    end

    --- Check if a specific game object entry is within loot range.
    --- @param entry number|string Object ID
    --- @param range number Override distance (default LOOT_RANGE)
    --- @return boolean
    function ctx:is_at_object(entry, range)
        range = range or LOOT_RANGE
        if core and core.object_manager then
            local nearest_obj = nil
            if core.object_manager.GetNearestGameObject then
                nearest_obj = core.object_manager.GetNearestGameObject({ entry })
            elseif core.object_manager.GetNearestObject then
                nearest_obj = core.object_manager.GetNearestObject({ entry })
            end
            if nearest_obj and nearest_obj.IsValid and nearest_obj:IsValid() then
                local player_pos = self:_get_player_pos()
                if player_pos and nearest_obj.get_position then
                    local ok, obj_pos = pcall(nearest_obj.get_position, nearest_obj)
                    if ok and obj_pos then
                        return Geometry.distance(player_pos, obj_pos) <= range
                    end
                end
                return true
            end
        end
        return false
    end

    --- Check if player is at a destination position.
    --- Accepts {x, y, z} table or a zone name string (resolved via get_zone_waypoint).
    --- @param dest table|string Position or zone name
    --- @param tolerance number Yards (default ARRIVAL_TOLERANCE)
    --- @return boolean
    function ctx:is_at_destination(dest, tolerance)
        tolerance = tolerance or ARRIVAL_TOLERANCE
        local target_pos = dest
        if type(dest) == "string" then
            target_pos = self:get_zone_waypoint(dest)
            if not target_pos then
                return false -- Can't resolve zone to a position
            end
        end
        if type(target_pos) ~= "table" then
            return false
        end
        local player_pos = self:_get_player_pos()
        if not player_pos then
            return false
        end
        local dist = Geometry.distance(player_pos, target_pos)
        return dist <= tolerance
    end

    --- Resolve a zone name to a waypoint position.
    --- Returns {x, y, z} or nil.
    function ctx:get_zone_waypoint(zone_name)
        -- Attempt to resolve via QueryServer
        if self.query and self.query.resolve_zone then
            local ok, result = pcall(self.query.resolve_zone, self.query, zone_name)
            if ok and type(result) == "table" then
                return result
            end
        end
        -- Fallback: check hardcoded zone centroids (small set of common zones)
        local zone_centroids = {
            ["Elwynn Forest"] = { x = -8949.95, y = -132.49, z = 83.53 },
            ["Dun Morogh"]    = { x = -5401.32, y = -2403.51, z = 400.09 },
            ["Teldrassil"]    = { x = 9947.52, y = 2054.02, z = 1329.63 },
            ["Mulgore"]       = { x = -2237.03, y = -438.46, z = -5.74 },
            ["Tirisfal Glades"] = { x = 1810.12, y = 227.96, z = -8.99 },
            ["Durotar"]       = { x = 259.65, y = -4749.60, z = 10.97 },
        }
        local centroid = zone_centroids[zone_name]
        if centroid then
            return { x = centroid.x, y = centroid.y, z = centroid.z }
        end
        return nil
    end

    -- ====================================================================
    -- Quest log tracking (W2.3, W2.4)
    -- ====================================================================

    --- Refresh the quest log caches from Sylvanas APIs.
    --- Called automatically on first access; can be called manually to force.
    function ctx:_refresh_quest_log()
        self._completed_quests = {}
        self._active_quests = {}

        if core and core.object_manager then
            -- Query completed quests
            if core.object_manager.GetCompletedQuests then
                local completed = core.object_manager.GetCompletedQuests()
                if type(completed) == "table" then
                    for _, entry in ipairs(completed) do
                        self._completed_quests[tostring(entry)] = true
                    end
                end
            end

            -- Query active quests
            if core.object_manager.GetActiveQuests then
                local active = core.object_manager.GetActiveQuests()
                if type(active) == "table" then
                    for _, entry in ipairs(active) do
                        self._active_quests[tostring(entry)] = true
                    end
                end
            end
        end

        self._quest_log_dirty = false
    end

    function ctx:is_quest_completed(quest_entry)
        if self._quest_log_dirty then
            self:_refresh_quest_log()
        end
        return self._completed_quests[tostring(quest_entry)] == true
    end

    function ctx:is_quest_active(quest_entry)
        if self._quest_log_dirty then
            self:_refresh_quest_log()
        end
        return self._active_quests[tostring(quest_entry)] == true
    end

    function ctx:is_objective_complete(quest_entry, objective_idx)
        if core and core.object_manager and core.object_manager.GetQuestObjectiveInfo then
            local completed, _ = core.object_manager.GetQuestObjectiveInfo(quest_entry, objective_idx)
            return completed == true
        end
        -- Fallback: check if quest is completed
        return self:is_quest_completed(quest_entry)
    end

    -- ====================================================================
    -- Player stats facade (W2.5)
    -- ====================================================================

    function ctx:get_player_level()
        if core and core.unit and core.unit.get_level then
            return core.unit.get_level("player") or 1
        end
        return 1
    end

    function ctx:get_player_class()
        if core and core.object_manager and core.object_manager.GetPlayerInfo then
            local info = core.object_manager.GetPlayerInfo()
            if info and info.class_name then
                return info.class_name
            end
        end
        if core and core.unit and core.unit.get_class then
            return core.unit.get_class("player") or "Unknown"
        end
        return "Unknown"
    end

    function ctx:get_player_race()
        if core and core.object_manager and core.object_manager.GetPlayerInfo then
            local info = core.object_manager.GetPlayerInfo()
            if info and info.race_name then
                return info.race_name
            end
        end
        if core and core.unit and core.unit.get_race then
            return core.unit.get_race("player") or "Unknown"
        end
        return "Unknown"
    end

    function ctx:get_player_faction()
        if core and core.object_manager and core.object_manager.GetPlayerInfo then
            local info = core.object_manager.GetPlayerInfo()
            if info and info.faction then
                return info.faction
            end
        end
        -- Fallback: derive from race
        local race = ctx:get_player_race()
        local alliance_races = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true }
        local horde_races = { Orc = true, Undead = true, Tauren = true, Troll = true, BloodElf = true }
        if alliance_races[race] then return "Alliance" end
        if horde_races[race] then return "Horde" end
        return "Neutral"
    end

    -- ====================================================================
    -- Inventory facade (W2.5)
    -- ====================================================================

    function ctx:get_item_count(item_entry)
        if core and core.object_manager and core.object_manager.GetItemCount then
            return core.object_manager.GetItemCount(item_entry) or 0
        end
        return 0
    end

    function ctx:get_money()
        if core and core.unit and core.unit.get_money then
            return core.unit.get_money() or 0
        end
        return 0
    end

    -- ====================================================================
    -- Skill / Reputation / Cooldown facade (W2.5)
    -- ====================================================================

    function ctx:get_skill_level(skill_name)
        if core and core.unit and core.unit.get_skill then
            local skill = core.unit.get_skill(skill_name)
            if skill then
                return skill.current or 0
            end
        end
        return 0
    end

    function ctx:is_item_ready(item_entry)
        if core and core.spell and core.spell.get_item_cooldown then
            local cd = core.spell.get_item_cooldown(item_entry)
            return cd == nil or cd == 0
        end
        return true -- Assume ready if no API
    end

    function ctx:get_reputation(faction_id)
        if core and core.unit and core.unit.get_reputation then
            return core.unit.get_reputation(faction_id) or 0
        end
        return 0
    end

    return ctx
end

-- ============================================================================
-- Recovery state machine methods (Wave 4)
-- ============================================================================

--- Main entry point, called each tick.
--- Dispatches to the current state machine state.
function RuntimeProfile:execute()
    if not self._profile then
        return "error", "profile not loaded"
    end

    -- Death detection runs before every state (W4.3)
    local dead = self:_is_player_dead()
    if dead and self._state ~= "ghost" then
        self:_log_event("death_detected", { state = self._state })
        self._state = "ghost"
        self._ghost_start_time = (_G.GetTime and _G.GetTime()) or 0
        return "running", "player dead, entering ghost recovery"
    end

    if self._state == "running" then
        return self:_execute_running()
    elseif self._state == "navigating" then
        return self:_execute_navigating()
    elseif self._state == "ghost" then
        return self:_execute_ghost()
    elseif self._state == "failed" then
        return "error", "profile failed after " .. self._consecutive_failures .. " consecutive failures"
    elseif self._state == "finished" then
        return "finished", "completed all operations"
    end
    return "error", "unknown state: " .. tostring(self._state)
end

-- ====================================================================
-- W4.5 — Structured logging
-- ====================================================================

--- Emit a structured log entry to event bus and internal log.
function RuntimeProfile:_log_event(event_type, data)
    local entry = {
        event = event_type,
        timestamp = (_G.GetTime and _G.GetTime()) or 0,
        operation = self._current_operation_idx,
        state = self._state,
    }
    if data then
        for k, v in pairs(data) do entry[k] = v end
    end
    table.insert(self._execution_log, entry)

    -- Also publish to event bus for external listeners (editor UI, etc.)
    if self._event_bus then
        self._event_bus:publish("questing:log", entry)
    end
    -- Update blackboard
    self._blackboard:set("questing.last_log", entry)
end

-- ====================================================================
-- W4.1 — Running state: execute current action, handle outcomes
-- ====================================================================

function RuntimeProfile:_execute_running()
    local operations = self._profile.operations or {}
    if #operations == 0 then
        self._state = "finished"
        return "finished", "no operations"
    end

    local op = operations[self._current_operation_idx]
    if not op then
        self._state = "finished"
        return "finished", "completed all operations"
    end

    -- Detect operation change → reset per-action retry counter (W4.1)
    local op_id = op.id or self._current_operation_idx
    if op_id ~= self._current_op_id then
        self._current_op_id = op_id
        self._current_action_retries = 0
        -- If nav was left active from a previous op, stop it
        if self._nav:is_active() then
            self._nav:stop("op_change")
        end
    end

    local action = op.action
    local ctx = self:create_context()

    local status, msg = RuntimeAction.execute(action, ctx)

    self._blackboard:set("questing.current_operation", self._current_operation_idx)
    self._blackboard:set("questing.current_status", status)
    self._blackboard:set("questing.current_action", action and action.type or "unknown")

    if status == "success" then
        self:_log_event("action_success", { action_type = action and action.type, msg = msg })
        self._current_action_retries = 0
        self._consecutive_failures = 0
        self:_advance_operation(op)
        return "running", "next operation"

    elseif status == "skipped" then
        self:_log_event("action_skipped", { action_type = action and action.type, msg = msg })
        -- Skipped conditions should advance per normal flow
        if op.next_condition == "auto" or op.next_condition == "always" then
            self._current_operation_idx = self._current_operation_idx + 1
        else
            self._current_operation_idx = self._current_operation_idx + 1
        end
        self:_save()  -- W5.3 — Save on skipped advance
        return "running", "skipped, advancing"

    elseif status == "retry" then
        self._current_action_retries = self._current_action_retries + 1
        self:_log_event("action_retry", {
            action_type = action and action.type,
            retry = self._current_action_retries,
            max = MAX_RETRIES_PER_ACTION,
        })

        if self._current_action_retries >= MAX_RETRIES_PER_ACTION then
            -- Exhausted retries → treat as failure
            self:_log_event("action_retry_exhausted", { action_type = action and action.type })
            self._consecutive_failures = self._consecutive_failures + 1
            self:_check_consecutive_failures()
            self._current_operation_idx = self._current_operation_idx + 1
            return "running", "retries exhausted, skipping operation"
        end
        return "running", "retry"

    elseif status == "blocked" then
        self:_log_event("action_blocked", { action_type = action and action.type, msg = msg })

        -- Enter navigation recovery (W4.2)
        return self:_handle_blocked(action)

    elseif status == "failed" then
        self:_log_event("action_failed", { action_type = action and action.type, msg = msg })
        self._consecutive_failures = self._consecutive_failures + 1
        self:_check_consecutive_failures()
        self._current_operation_idx = self._current_operation_idx + 1
        return "running", "action failed, skipping"
    end

    return "running", tostring(status)
end

-- ====================================================================
-- W4.4 — Consecutive failure check
-- ====================================================================

function RuntimeProfile:_check_consecutive_failures()
    if self._consecutive_failures >= MAX_CONSECUTIVE_FAILURES then
        self:_log_event("profile_failed", {
            consecutive_failures = self._consecutive_failures,
        })
        self._state = "failed"
    end
end

-- ====================================================================
-- W4.2 — Navigating state: poll NavAdapter, retry on arrival
-- ====================================================================

function RuntimeProfile:_execute_navigating()
    -- If nav completed without us noticing, check if we're there
    if not self._nav:is_active() then
        local state = self._nav:get_state()
        if state == "idle" or state == "arrived" then
            -- Nav finished; retry the action
            self:_log_event("nav_arrived", {})
            self._state = "running"
            return "running", "navigated, retry"
        end
    end

    -- Poll nav
    local state, progress = self._nav:poll()
    self._blackboard:set("questing.nav_state", state)

    if state == "arrived" or state == "idle" then
        self._nav:stop("arrived")
        self:_log_event("nav_arrived", {})
        self._state = "running"
        return "running", "navigated, retry"

    elseif state == "requesting_path" or state == "moving" then
        -- Check timeout
        local now = (_G.GetTime and _G.GetTime()) or 0
        if self._nav_start_time and (now - self._nav_start_time) > NAV_TIMEOUT then
            self:_log_event("nav_timeout", { duration = now - self._nav_start_time })
            self._current_action_retries = self._current_action_retries + 1
            self._nav:stop("timeout")
            self._last_blocked_action = nil
            self._state = "running"
            if self._current_action_retries >= MAX_RETRIES_PER_ACTION then
                self._consecutive_failures = self._consecutive_failures + 1
                self:_check_consecutive_failures()
                self._current_operation_idx = self._current_operation_idx + 1
                return "running", "nav timeout, retries exhausted"
            end
            return "running", "nav timeout, retry"
        end
        return "running", "navigating"

    elseif state == "stuck" then
        -- Pathfinding issue: increment retries, go back to running
        self:_log_event("nav_stuck", {})
        self._current_action_retries = self._current_action_retries + 1
        self._nav:stop("stuck")
        self._state = "running"
        return "running", "nav stuck, retry"

    else
        -- failed / unknown
        self:_log_event("nav_failed", { state = state })
        self._state = "running"
        return "running", "nav failed, retry"
    end
end

-- ====================================================================
-- W4.3 — Ghost state: death recovery
-- ====================================================================

function RuntimeProfile:_execute_ghost()
    -- Check if still dead
    local dead = self:_is_player_dead()
    if not dead then
        -- Alive again! Return to running, retry current operation
        self:_log_event("ghost_rezzed", {})
        self._state = "running"
        self._ghost_start_time = nil
        return "running", "resurrected, retry"
    end

    local now = (_G.GetTime and _G.GetTime()) or 0
    local elapsed = self._ghost_start_time and (now - self._ghost_start_time) or 0

    -- Timeout: skip current operation
    if elapsed >= GHOST_TIMEOUT then
        self:_log_event("ghost_timeout", { duration = elapsed })
        self._ghost_start_time = nil
        self._current_operation_idx = self._current_operation_idx + 1
        self._state = "running"
        return "running", "ghost recovery timed out, skipping operation"
    end

    -- Release corpse if we have spirit
    if core and core.unit and core.unit.has_spirit then
        local has_spirit = core.unit.has_spirit("player")
        if has_spirit and core.input and core.input.release_corpse then
            core.input.release_corpse()
            self:_log_event("ghost_release_corpse", {})
        end
    end

    -- Attempt auto-resurrection if available
    if core and core.unit and core.unit.resurrect then
        core.unit.resurrect("player")
        self:_log_event("ghost_resurrect_attempt", {})
    end

    -- Check every GHOST_RETRY_INTERVAL seconds
    if elapsed % GHOST_RETRY_INTERVAL < 1.0 then
        -- Just polled; return running to tick again
    end

    return "running", "ghost recovery (" .. tostring(math.floor(elapsed)) .. "s)"
end

-- ====================================================================
-- W4.2 — Blocked handler: resolve target and start navigation
-- ====================================================================

--- Called when an action returns "blocked".
--- Attempts to resolve a navigation target from the action payload
--- and starts NavAdapter movement. Transitions to "navigating" state.
function RuntimeProfile:_handle_blocked(action)
    -- If nav is already active (action handler started it), just poll
    if self._nav:is_active() then
        self._state = "navigating"
        self._nav_start_time = (_G.GetTime and _G.GetTime()) or 0
        self._last_blocked_action = action
        self:_log_event("nav_already_active", { action_type = action and action.type })
        return "running", "navigating"
    end

    -- Resolve target position from action payload
    local target_pos = self:_resolve_nav_target(action)
    if not target_pos then
        -- Can't navigate: increment retries
        self._current_action_retries = self._current_action_retries + 1
        return "running", "blocked (no nav target)"
    end

    -- Start navigation
    local ok, err = self._nav:move_to(target_pos, { tolerance = ARRIVAL_TOLERANCE })
    if not ok then
        self._current_action_retries = self._current_action_retries + 1
        self:_log_event("nav_dispatch_failed", { error = err })
        return "running", "blocked (nav dispatch failed)"
    end

    self._state = "navigating"
    self._nav_start_time = (_G.GetTime and _G.GetTime()) or 0
    self._last_blocked_action = action
    self:_log_event("nav_started", {
        target = target_pos,
        action_type = action and action.type,
    })
    return "running", "navigating to target"
end

-- ====================================================================
-- Target resolution helpers
-- ====================================================================

--- Resolve a navigation target from an action's payload.
--- Returns {x, y, z} or nil.
function RuntimeProfile:_resolve_nav_target(action)
    if not action or not action.payload then return nil end
    local p = action.payload

    -- 1. Explicit position coordinates
    if p.position and type(p.position) == "table" and p.position.x then
        return { x = p.position.x, y = p.position.y, z = p.position.z }
    end

    -- 2. NPC entry → look up in object manager
    if p.npc_entry then
        return self:_get_npc_position(p.npc_entry)
    end

    -- 3. Object entry → look up in object manager
    if p.object_entry then
        return self:_get_object_position(p.object_entry)
    end

    -- 4. Creature entries (first one) → look up
    if p.creature_entries and type(p.creature_entries) == "table" and #p.creature_entries > 0 then
        return self:_get_npc_position(p.creature_entries[1])
    end

    -- 5. Zone destination string (e.g. "Elwynn Forest")
    if p.destination and type(p.destination) == "string" then
        -- Create a temporary context for zone waypoint resolution
        local ctx = self:create_context()
        return ctx:get_zone_waypoint(p.destination)
    end

    return nil
end

--- Look up an NPC's position from the object manager.
function RuntimeProfile:_get_npc_position(npc_entry)
    if core and core.object_manager and core.object_manager.GetNearestCreature then
        local npc = core.object_manager.GetNearestCreature({ npc_entry })
        if npc and npc.get_position then
            local ok, pos = pcall(npc.get_position, npc)
            if ok and pos then
                return { x = pos.x, y = pos.y, z = pos.z }
            end
        end
    end
    return nil
end

--- Look up a game object's position from the object manager.
function RuntimeProfile:_get_object_position(object_entry)
    if core and core.object_manager then
        local obj = nil
        if core.object_manager.GetNearestGameObject then
            obj = core.object_manager.GetNearestGameObject({ object_entry })
        elseif core.object_manager.GetNearestObject then
            obj = core.object_manager.GetNearestObject({ object_entry })
        end
        if obj and obj.get_position then
            local ok, pos = pcall(obj.get_position, obj)
            if ok and pos then
                return { x = pos.x, y = pos.y, z = pos.z }
            end
        end
    end
    return nil
end

--- Check if the player is dead using Sylvanas unit API.
function RuntimeProfile:_is_player_dead()
    if core and core.unit and core.unit.is_dead then
        local ok, dead = pcall(core.unit.is_dead, core.unit, "player")
        if ok then
            return dead == true
        end
    end
    -- Fallback: check health
    if core and core.unit and core.unit.get_health then
        local ok, health = pcall(core.unit.get_health, core.unit, "player")
        if ok and type(health) == "number" then
            return health <= 0
        end
    end
    return false -- Assume alive if no API
end

--- Advance to the next operation based on the operation's next_condition.
--- Also triggers auto-save of execution state (W5.3).
function RuntimeProfile:_advance_operation(op)
    if not op or not op.next_condition or op.next_condition == "auto" or op.next_condition == "always" then
        self._current_operation_idx = self._current_operation_idx + 1
    elseif op.next_condition == "conditional" and op.condition_id then
        -- Evaluate the condition to decide next operation
        -- For now, advance sequentially. Full conditional branching needs
        -- the editor's condition evaluation integration.
        self._current_operation_idx = self._current_operation_idx + 1
    else
        self._current_operation_idx = self._current_operation_idx + 1
    end
    -- W5.3 — Auto-save after operation advance
    self:_save()
end

-- ====================================================================
-- Reset / lifecycle
-- ====================================================================

function RuntimeProfile:reset()
    self._current_operation_idx = 1
    self._current_op_id = nil
    self._variables = {}
    self._state = "running"
    self._current_action_retries = 0
    self._consecutive_failures = 0
    self._nav_start_time = nil
    self._ghost_start_time = nil
    self._last_blocked_action = nil
    self._execution_log = {}
    if self._nav then
        self._nav:stop("reset")
    end
end

function RuntimeProfile:get_log()
    return self._execution_log
end

function RuntimeProfile:get_state()
    return self._state, {
        operation = self._current_operation_idx,
        retries = self._current_action_retries,
        consecutive_failures = self._consecutive_failures,
    }
end

return RuntimeProfile