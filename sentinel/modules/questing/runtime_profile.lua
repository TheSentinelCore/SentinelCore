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

-- UnitHelper is exposed from RuntimeAction for object lookup (Sylvannas API compliant)
local UnitHelper = RuntimeAction.UnitHelper

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
local MAX_CONDITION_WAIT = 300.0        -- Seconds a Completion-role Condition gate may hold before forced advance

local RuntimeProfile = {}
RuntimeProfile.__index = RuntimeProfile

function RuntimeProfile:new(json_path, dry_run)
    local o = setmetatable({}, RuntimeProfile)
    o._json_path = json_path
    o._dry_run = dry_run == true
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
    o._current_action_idx = 1           -- Current action index within operation (W1.1)
    o._nav_start_time = nil             -- When navigation began (W4.2)
    o._ghost_start_time = nil           -- When death was detected (W4.3)
    o._last_blocked_action = nil        -- Copy of the action that triggered blocked
    o._execution_log = {}               -- Structured log entries (W4.5)
    o._wait_started_at = nil            -- When the current Completion-role Condition gate started waiting
    o._wait_action_key = nil            -- Identity of the action currently being waited on

    -- Hot reload (T16)
    o._json_mtime = nil                  -- Last known mtime for hot reload polling

    -- Persistence (W5.2, W5.3)
    o._save_path = o:_compute_save_path()
    o._dirty = false                    -- Track unsaved changes

    -- Extended state for v2 persistence (T18)
    o._completed_quests = {}            -- { [quest_entry] = true }
    o._temporary_variables = {}         -- Runtime-only variables
    o._visited_vendors = {}             -- Vendor entries visited
    o._known_flight_paths = {}          -- Flight path nodes discovered
    o._known_hearth_location = nil      -- Last known hearth position

    -- Dry-run simulation tracking
    o._sim_result = nil

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
        version = 2,
        profile_fingerprint = (self._profile and self._profile.content_hash) or "",
        current_operation_idx = self._current_operation_idx,
        variables = self._variables,
        saved_at = (core and core.time and core.time()) or 0,
        -- v2 additions (T18): full execution state
        current_action_idx = self._current_action_idx,
        completed_quests = self._completed_quests or {},
        temporary_variables = self._temporary_variables or {},
        visited_vendors = self._visited_vendors or {},
        known_flight_paths = self._known_flight_paths or {},
        known_hearth_location = self._known_hearth_location,
        execution_history = self._execution_log or {},
    }
end

--- Persist execution state to disk.
--- Called on operation advance, variable change, stop, and reset.
function RuntimeProfile:_save()
    if self._dry_run then return false end
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

    -- v2 fields (T18) — restore with nil-safe defaults for v1 saves
    if decoded.version == 2 then
        if type(decoded.current_action_idx) == "number" then
            self._current_action_idx = decoded.current_action_idx
        end
        if type(decoded.completed_quests) == "table" then
            self._completed_quests = decoded.completed_quests
        end
        if type(decoded.temporary_variables) == "table" then
            self._temporary_variables = decoded.temporary_variables
        end
        if type(decoded.visited_vendors) == "table" then
            self._visited_vendors = decoded.visited_vendors
        end
        if type(decoded.known_flight_paths) == "table" then
            self._known_flight_paths = decoded.known_flight_paths
        end
        if decoded.known_hearth_location ~= nil then
            self._known_hearth_location = decoded.known_hearth_location
        end
        if type(decoded.execution_history) == "table" then
            self._execution_log = decoded.execution_history
        end
    end

    self._dirty = false
    self:_log_event("save_restored", {
        operation = self._current_operation_idx,
        variable_count = 0, -- table len unreliable for dict
        save_version = decoded.version or 1,
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

        -- T17 — Initialize variables from profile defaults
        self._variables = {}
        if self._profile.variables then
            for _, v in ipairs(self._profile.variables) do
                self._variables[v.name] = v.default_value or 0
            end
        end

        -- W5.2 — Attempt to restore execution state from save file
        -- (restored values override default initializations)
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
        -- Use UnitHelper to find creature (Sylvannas API compliant)
        local npc = UnitHelper.get_nearest_creature({ entry })
        if npc and npc:is_valid() then
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
        return false
    end

    --- Check if a specific game object entry is within loot range.
    --- @param entry number|string Object ID
    --- @param range number Override distance (default LOOT_RANGE)
    --- @return boolean
    function ctx:is_at_object(entry, range)
        range = range or LOOT_RANGE
        -- Use UnitHelper to find game object (Sylvannas API compliant)
        local obj = UnitHelper.get_nearest_game_object({ entry })
        if obj and obj:is_valid() then
            local player_pos = self:_get_player_pos()
            if player_pos and obj.get_position then
                local ok, obj_pos = pcall(obj.get_position, obj)
                if ok and obj_pos then
                    return Geometry.distance(player_pos, obj_pos) <= range
                end
            end
            return true
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

    --- Refresh the quest log caches from Sylvannas APIs.
    --- Called automatically on first access; can be called manually to force.
    function ctx:_refresh_quest_log()
        self._completed_quests = {}
        self._active_quests = {}

        -- Use core.quests.is_quest_flagged_completed for completed quests (Sylvannas API)
        if core and core.quests and core.quests.get_num_quest_log_entries then
            local num_entries = core.quests.get_num_quest_log_entries()
            for i = 1, num_entries do
                local info = core.quests.get_quest_log_title(i)
                if info and not info.is_header then
                    if info.is_complete then
                        self._completed_quests[tostring(info.quest_id)] = true
                    else
                        self._active_quests[tostring(info.quest_id)] = true
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
        -- Also directly check Sylvannas API for active quests
        if core and core.quests and core.quests.is_on_quest then
            local ok, is_on = pcall(core.quests.is_on_quest, quest_entry)
            if ok and is_on then
                return true
            end
        end
        return self._active_quests[tostring(quest_entry)] == true
    end

    function ctx:is_objective_complete(quest_entry, objective_idx)
        -- Use core.quests.get_num_quest_leader_boards and get_quest_log_leader_board (Sylvannas API)
        if core and core.quests and core.quests.get_num_quest_leader_boards then
            -- Find quest log index for this quest
            if self._quest_log_dirty then
                self:_refresh_quest_log()
            end
            -- Try to find quest by ID in our cached log
            local num_entries = core.quests.get_num_quest_log_entries()
            for i = 1, num_entries do
                local info = core.quests.get_quest_log_title(i)
                if info and info.quest_id == quest_entry then
                    local num_obj = core.quests.get_num_quest_leader_boards(i)
                    if objective_idx <= num_obj then
                        local text = core.quests.get_quest_log_leader_board(objective_idx, i)
                        -- Parse "Wolves slain: 3/10" format - check if complete
                        if text and string.match(text, "%((%d+)/(%d+)%)") then
                            local cur, max = string.match(text, "%((%d+)/(%d+)%)")
                            if tonumber(cur) >= tonumber(max) then
                                return true
                            end
                        end
                        return false
                    end
                    break
                end
            end
        end
        -- Fallback: check if quest is completed
        return self:is_quest_completed(quest_entry)
    end

    -- ====================================================================
    -- Player stats facade (W2.5) - Sylvannas API compliant
    -- ====================================================================

    function ctx:get_player_level()
        -- Use get_local_player():get_level() (Sylvannas API)
        local player = UnitHelper.get_local_player()
        if player and player.get_level then
            local ok, level = pcall(player.get_level, player)
            if ok and tonumber(level) then
                return level
            end
        end
        return 1
    end

    function ctx:get_player_class()
        -- Use get_local_player():get_class() (Sylvannas API)
        local player = UnitHelper.get_local_player()
        if player and player.get_class then
            local ok, class = pcall(player.get_class, player)
            if ok and class then
                return class
            end
        end
        return "Unknown"
    end

    function ctx:get_player_race()
        -- Use get_local_player():get_race() (Sylvannas API)
        local player = UnitHelper.get_local_player()
        if player and player.get_race then
            local ok, race = pcall(player.get_race, player)
            if ok and race then
                return race
            end
        end
        return "Unknown"
    end

    function ctx:get_player_faction()
        -- Fallback: derive from race
        local race = ctx:get_player_race()
        local alliance_races = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true }
        local horde_races = { Orc = true, Undead = true, Tauren = true, Troll = true, BloodElf = true }
        if alliance_races[race] then return "Alliance" end
        if horde_races[race] then return "Horde" end
        return "Neutral"
    end

    -- ====================================================================
    -- Inventory facade (W2.5) - Sylvannas API compliant
    -- ====================================================================

    function ctx:get_item_count(item_entry)
        -- Check player's equipped items for item count (Sylvannas API)
        local player = UnitHelper.get_local_player()
        if player and player.get_equipped_items then
            local ok, items = pcall(player.get_equipped_items, player)
            if ok and items then
                local count = 0
                for _, slot_info in ipairs(items) do
                    if slot_info.object and slot_info.object.get_item_id then
                        local ok2, id = pcall(slot_info.object.get_item_id, slot_info.object)
                        if ok2 and tostring(id) == tostring(item_entry) then
                            count = count + 1
                        end
                    end
                end
                return count
            end
        end
        -- Check bags for item count
        if core and core.inventory and core.inventory.get_items_in_bag then
            for bag_id = 0, 4 do
                local ok, items = pcall(core.inventory.get_items_in_bag, core.inventory, bag_id)
                if ok and items then
                    for _, slot_info in ipairs(items) do
                        if slot_info.object and slot_info.object.get_item_id then
                            local ok2, id = pcall(slot_info.object.get_item_id, slot_info.object)
                            if ok2 and tostring(id) == tostring(item_entry) then
                                return 1
                            end
                        end
                    end
                end
            end
        end
        return 0
    end

    function ctx:get_money()
        -- Use core.inventory.get_gold() (Sylvannas API)
        if core and core.inventory and core.inventory.get_gold then
            local ok, copper = pcall(core.inventory.get_gold, core.inventory)
            if ok and tonumber(copper) then
                return copper
            end
        end
        return 0
    end

    -- ====================================================================
    -- Skill / Reputation / Cooldown facade (W2.5) - Sylvannas API compliant
    -- ====================================================================

    function ctx:get_skill_level(skill_name)
        -- Sylvannas doesn't have a direct skill level API, return 0
        return 0
    end

    function ctx:is_item_ready(item_entry)
        -- Use object's get_item_cooldown method (Sylvannas API)
        local player = UnitHelper.get_local_player()
        if player and player.get_item_cooldown then
            local ok, cd = pcall(player.get_item_cooldown, player, item_entry)
            if ok and cd and tonumber(cd) and cd > 0 then
                return false
            end
        end
        return true -- Assume ready if no API or no cooldown
    end

    function ctx:get_reputation(faction_id)
        -- Sylvannas doesn't have a direct reputation getter in core.quests
        -- Would need to use quest APIs or return 0
        return 0
    end

    return ctx
end

-- ============================================================================
-- Hot reload (T16)
-- ============================================================================

--- Get the last modification time of the profile JSON file.
--- Returns a number (timestamp) or nil.
function RuntimeProfile:_get_file_mtime()
    if core and core.get_file_info then
        local ok, info = pcall(core.get_file_info, self._json_path)
        if ok and info and info.mtime then
            return info.mtime
        end
    end
    -- Fallback: LuaFileSystem if available
    local ok, lfs = pcall(require, "lfs")
    if ok and lfs and lfs.attributes then
        local attr = lfs.attributes(self._json_path)
        if attr and attr.modification then
            return attr.modification
        end
    end
    return nil
end

--- Check profile JSON for changes and hot-reload if detected.
--- Guard: only when state is "running".
--- On change: validate content_hash, swap profile preserving _variables.
function RuntimeProfile:_check_hot_reload()
    if self._dry_run then return end
    if self._state ~= "running" then return end

    local mtime = self:_get_file_mtime()
    if not mtime then return end

    -- First check or mtime unchanged?
    if self._json_mtime and mtime <= self._json_mtime then return end

    -- Read file
    local json, err = core.read_data_file and core.read_data_file(self._json_path)
    if not json then
        self._json_mtime = mtime -- Update so we don't retry every tick
        return
    end

    local decoded = JSON and JSON.parse(json)
    if not decoded then
        local fn = load("return " .. json)
        decoded = fn and fn()
    end
    if not decoded or type(decoded) ~= "table" then
        self._json_mtime = mtime
        return
    end

    -- Must have a content_hash to validate
    if not decoded.content_hash then
        self:_log_event("hot_reload_skip", { reason = "no content_hash" })
        self._json_mtime = mtime
        return
    end

    -- Same hash as already running? Update mtime cache only, skip
    if self._profile and self._profile.content_hash == decoded.content_hash then
        self._json_mtime = mtime
        return
    end

    -- Preserve current variables, swap profile, re-init with defaults
    local saved_variables = self._variables
    self._profile = decoded

    -- Re-initialize variables from new profile defaults
    self._variables = {}
    if self._profile.variables then
        for _, v in ipairs(self._profile.variables) do
            self._variables[v.name] = v.default_value or 0
        end
    end

    -- Restore preserved variable values where the key still exists
    for name, value in pairs(saved_variables) do
        if self._variables[name] ~= nil then
            self._variables[name] = value
        end
    end

    self._json_mtime = mtime
    self:_log_event("hot_reload", { hash = decoded.content_hash })
end

-- ============================================================================
-- Recovery state machine methods (Wave 4)
-- ============================================================================

--- Main entry point, called each tick.
--- Dispatches to the current state machine state.
--- When dry_run is true, simulates execution without calling real APIs.
function RuntimeProfile:execute(dry_run)
    if dry_run == true then
        self._dry_run = true
    end

    if not self._profile then
        return "error", "profile not loaded"
    end

    if self._dry_run then
        return self:_execute_dry_run()
    end

    -- T16 — Check for hot reload at start of each tick
    self:_check_hot_reload()

    -- Death detection runs before every state (W4.3)
    local dead = self:_is_player_dead()
    if dead and self._state ~= "ghost" then
        self:_log_event("death_detected", { state = self._state })
        self._state = "ghost"
        self._ghost_start_time = (core and core.time and core.time()) or 0
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
-- Dry-run simulation (no real API calls, no navigation, no persistence)
-- ====================================================================

--- Execute the entire profile in dry-run mode.
--- Walks all operations and actions sequentially. Conditions are evaluated
--- normally (read-only ctx methods are safe). All other actions are
--- simulated as "success". Navigation, saves, and hot reload are skipped.
--- @return string, string "finished" status and summary message.
function RuntimeProfile:_execute_dry_run()
    local operations = self._profile.operations or {}
    local results = {
        operations_count = #operations,
        estimated_duration_seconds = 0,
        blocked_operations = 0,
        failed_actions = 0,
        skipped_conditions = 0,
    }

    local ctx = self:create_context()

    for op_idx, op in ipairs(operations) do
        local op_actions = op.actions or {}
        local op_actions_duration = 0

        for _, action in ipairs(op_actions) do
            local action_type = action.type or "unknown"

            if action_type == "Condition" then
                local cond = action.payload and action.payload.condition
                local ok = cond and RuntimeAction.evaluate_condition(ctx, cond) or false
                if not ok then
                    results.skipped_conditions = results.skipped_conditions + 1
                end
            elseif action_type == "Comment" then
                -- No-op, zero cost
            elseif action_type == "SetVariable" then
                -- Safe to execute; doesn't call external APIs
                RuntimeAction.execute_set_variable(action.payload, ctx)
            else
                -- All real actions: simulate success (the action itself
                -- would trigger Sylvannas APIs, navigation, etc.)
                -- Estimate a nominal per-action cost for duration.
                op_actions_duration = op_actions_duration + 3.0
            end
        end

        results.estimated_duration_seconds = results.estimated_duration_seconds + op_actions_duration
    end

    self._sim_result = results
    self._state = "finished"
    self._current_operation_idx = #operations + 1
    return "finished", "dry-run simulation complete: " .. #operations .. " operations"
end

--- Run the full profile simulation in dry-run mode.
--- Resets state, runs through all operations, and returns a summary table.
--- @return table Summary with operations_count, estimated_duration_seconds,
---         blocked_operations, failed_actions, skipped_conditions.
function RuntimeProfile:simulate()
    local saved_state = self._state
    local saved_op_idx = self._current_operation_idx
    local saved_action_idx = self._current_action_idx
    local saved_variables = self._variables

    self:reset()
    self._dry_run = true

    local ok, err = pcall(function()
        if not self._profile then
            error("profile not loaded")
        end
        self:_execute_dry_run()
    end)

    if not ok then
        self._state = saved_state
        self._current_operation_idx = saved_op_idx
        self._current_action_idx = saved_action_idx
        self._variables = saved_variables
        self._dry_run = false
        return { error = tostring(err) }
    end

    local result = self._sim_result or {
        operations_count = 0,
        estimated_duration_seconds = 0,
        blocked_operations = 0,
        failed_actions = 0,
        skipped_conditions = 0,
    }

    self._state = saved_state
    self._current_operation_idx = saved_op_idx
    self._current_action_idx = saved_action_idx
    self._variables = saved_variables
    self._dry_run = false

    return result
end

-- ====================================================================
-- W4.5 — Structured logging
-- ====================================================================

--- Emit a structured log entry to event bus and internal log.
function RuntimeProfile:_log_event(event_type, data)
    local entry = {
        event = event_type,
        timestamp = (core and core.time and core.time()) or 0,
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

    -- W1.1: Get current action from operation's actions array
    if not op.actions or #op.actions == 0 then
        self._state = "finished"
        return "finished", "operation has no actions"
    end
    if self._current_action_idx > #op.actions then
        self._current_action_idx = 1  -- Reset to first action if out of bounds
    end
    local action = op.actions[self._current_action_idx]
    local ctx = self:create_context()

    local status, msg = RuntimeAction.execute(action, ctx)

    self._blackboard:set("questing.current_operation", self._current_operation_idx)
    self._blackboard:set("questing.current_status", status)
    self._blackboard:set("questing.current_action", action and action.type or "unknown")

    if status == "success" then
        self:_log_event("action_success", { action_type = action and action.type, msg = msg })
        self._current_action_retries = 0
        self._consecutive_failures = 0
        
        -- W1.1: Move to next action within current operation
        self._current_action_idx = self._current_action_idx + 1
        
        -- If we've completed all actions in current operation, advance to next operation
        if self._current_action_idx > #op.actions then
            self:_advance_operation(op)
            self._current_action_idx = 1  -- Reset for next operation
        end
        
        return "running", "next action"

    elseif status == "skipped" then
        self:_log_event("action_skipped", { action_type = action and action.type, msg = msg })
        -- Skipped actions should advance to next action
        self._current_action_idx = self._current_action_idx + 1
        
        -- If we've processed all actions in current operation, advance to next operation
        if self._current_action_idx > #op.actions then
            if op.next_condition == "auto" or op.next_condition == "always" then
                self._current_operation_idx = self._current_operation_idx + 1
            else
                self._current_operation_idx = self._current_operation_idx + 1
            end
        end
        self:_save()  -- W5.3 — Save on skipped advance
        return "running", "skipped, advancing"

    elseif status == "waiting" then
        -- Completion-role Condition gate: hold this action and re-poll next tick. Does not
        -- advance the action index and does not count as a retry/failure (PR5b).
        local key = tostring(op_id) .. ":" .. tostring(self._current_action_idx)
        local now = (core and core.time and core.time()) or 0
        if self._wait_action_key ~= key then
            self._wait_action_key = key
            self._wait_started_at = now
        end

        local elapsed = now - self._wait_started_at
        if elapsed >= MAX_CONDITION_WAIT then
            self:_log_event("condition_wait_timeout", { action_type = action and action.type, duration = elapsed })
            self._wait_started_at = nil
            self._wait_action_key = nil

            -- Bounded wait exceeded: don't deadlock the bot — advance past the gate.
            self._current_action_idx = self._current_action_idx + 1
            if self._current_action_idx > #op.actions then
                self._current_operation_idx = self._current_operation_idx + 1
                self._current_action_idx = 1
            end
            return "running", "condition wait timed out, skipping"
        end

        return "running", "waiting for completion"

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
            
            -- Move to next action after exhausting retries
            self._current_action_idx = self._current_action_idx + 1
            
            -- If we've processed all actions, move to next operation
            if self._current_action_idx > #op.actions then
                self._current_operation_idx = self._current_operation_idx + 1
                self._current_action_idx = 1  -- Reset for next operation
            end
            return "running", "retries exhausted, skipping action"
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
        
        -- Move to next action on failure
        self._current_action_idx = self._current_action_idx + 1
        
        -- If we've processed all actions, move to next operation
        if self._current_action_idx > #op.actions then
            self._current_operation_idx = self._current_operation_idx + 1
            self._current_action_idx = 1  -- Reset for next operation
        end
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
        local now = (core and core.time and core.time()) or 0
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

    local now = (core and core.time and core.time()) or 0
    local elapsed = self._ghost_start_time and (now - self._ghost_start_time) or 0

    -- Timeout: skip current operation
    if elapsed >= GHOST_TIMEOUT then
        self:_log_event("ghost_timeout", { duration = elapsed })
        self._ghost_start_time = nil
        self._current_operation_idx = self._current_operation_idx + 1
        self._state = "running"
        return "running", "ghost recovery timed out, skipping operation"
    end

    -- Release spirit using core.input.release_spirit() (Sylvannas API)
    if core and core.input and core.input.release_spirit then
        core.input.release_spirit()
        self:_log_event("ghost_release_spirit", {})
    end

    -- Resurrect corpse using core.input.resurrect_corpse() (Sylvannas API)
    if core and core.input and core.input.resurrect_corpse then
        core.input.resurrect_corpse()
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
        self._nav_start_time = (core and core.time and core.time()) or 0
        self._last_blocked_action = action
        self:_log_event("nav_already_active", { action_type = action and action.type })
        return "running", "navigating"
    end

    -- Resolve target position from action payload
    local target_pos = self:_resolve_nav_target(action)
    if not target_pos then
        -- Can't navigate: increment retries
        self._current_action_retries = self._current_action_retries + 1
        if self._current_action_retries >= MAX_RETRIES_PER_ACTION then
            -- Exhausted retries → advance to next action
            self._consecutive_failures = self._consecutive_failures + 1
            self:_check_consecutive_failures()
            self._current_action_idx = self._current_action_idx + 1
            local operations = self._profile.operations or {}
            local op = operations[self._current_operation_idx]
            if op and self._current_action_idx > #op.actions then
                self._current_operation_idx = self._current_operation_idx + 1
                self._current_action_idx = 1
            end
            return "running", "blocked (no nav target), retries exhausted, advancing"
        end
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
        self._nav_start_time = (core and core.time and core.time()) or 0
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

    -- 1. Explicit position coordinates (handle both legacy {x,y,z} and new {world_x,world_y,world_z,map} formats)
    if p.position and type(p.position) == "table" then
        if p.position.x then
            -- Legacy format: {x, y, z}
            return { x = p.position.x, y = p.position.y, z = p.position.z }
        elseif p.position.world_x then
            -- New format from compiler: {world_x, world_y, world_z, map}
            return { x = p.position.world_x, y = p.position.world_y, z = p.position.world_z }
        end
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

--- Look up an NPC's position from the object manager (Sylvannas API compliant).
function RuntimeProfile:_get_npc_position(npc_entry)
    local npc = UnitHelper.get_nearest_creature({ npc_entry })
    if npc and npc:is_valid() then
        if npc.get_position then
            local ok, pos = pcall(npc.get_position, npc)
            if ok and pos then
                return { x = pos.x, y = pos.y, z = pos.z }
            end
        end
    end
    return nil
end

--- Look up a game object's position from the object manager (Sylvannas API compliant).
function RuntimeProfile:_get_object_position(object_entry)
    local obj = UnitHelper.get_nearest_game_object({ object_entry })
    if obj and obj:is_valid() then
        if obj.get_position then
            local ok, pos = pcall(obj.get_position, obj)
            if ok and pos then
                return { x = pos.x, y = pos.y, z = pos.z }
            end
        end
    end
    return nil
end

--- Check if the player is dead using Sylvannas API (get_local_player:is_dead()).
function RuntimeProfile:_is_player_dead()
    local player = UnitHelper.get_local_player()
    if player and player:is_valid() then
        if player.is_dead then
            local ok, dead = pcall(player.is_dead, player)
            if ok then
                return dead == true
            end
        end
        -- Fallback: check health
        if player.get_health then
            local ok, health = pcall(player.get_health, player)
            if ok and type(health) == "number" then
                return health <= 0
            end
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
    self._current_action_idx = 1
    self._nav_start_time = nil
    self._ghost_start_time = nil
    self._last_blocked_action = nil
    self._execution_log = {}
    self._json_mtime = nil
    self._completed_quests = {}
    self._temporary_variables = {}
    self._visited_vendors = {}
    self._known_flight_paths = {}
    self._known_hearth_location = nil
    self._sim_result = nil
    self._dry_run = false
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