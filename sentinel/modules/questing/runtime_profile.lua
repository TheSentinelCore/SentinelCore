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

local RuntimeProfile = {}
RuntimeProfile.__index = RuntimeProfile

function RuntimeProfile:new(json_path)
    local o = setmetatable({}, RuntimeProfile)
    o._json_path = json_path
    o._profile = nil
    o._blackboard = Blackboard:new()
    o._query = QueryClient:new("127.0.0.1", 3030)
    o._current_operation_idx = 1
    o._variables = {}
    o._event_bus = EventBus:new()   -- W3.3
    o._nav = NavAdapter:new(o._event_bus)  -- W3.3
    return o
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

function RuntimeProfile:execute()
    if not self._profile then
        return "error", "profile not loaded"
    end

    local operations = self._profile.operations or {}
    if #operations == 0 then
        return "finished", "no operations"
    end

    -- Execute current operation
    local op = operations[self._current_operation_idx]
    if not op then
        return "finished", "completed all operations"
    end

    local action = op.action
    local ctx = self:create_context()

    local status, msg = RuntimeAction.execute(action, ctx)

    self._blackboard:set("questing.current_operation", self._current_operation_idx)
    self._blackboard:set("questing.current_status", status)

    if status == "success" then
        if op.next_condition == "auto" or op.next_condition == "always" then
            self._current_operation_idx = self._current_operation_idx + 1
        elseif op.next_condition == "conditional" and op.condition_id then
            -- Check condition result
            -- TODO: Use QueryServer to evaluate
            self._current_operation_idx = self._current_operation_idx + 1
        else
            self._current_operation_idx = self._current_operation_idx + 1
        end
        return "running", "next operation"
    else
        return "running", msg
    end
end

function RuntimeProfile:reset()
    self._current_operation_idx = 1
    self._variables = {}
end

return RuntimeProfile