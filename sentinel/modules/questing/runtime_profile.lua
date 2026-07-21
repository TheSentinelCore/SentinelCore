--- Sentinel Runtime Profile Executor
--- Loads and executes a RuntimeProfile (compiled from sentinel-questing/compiler)
--- Uses Blackboard for state, EventBus for events

local RuntimeAction = require("modules/questing/runtime_action")
local Blackboard = require("core/blackboard")
local Compat = require("shared/compat")
local QueryClient = require("shared/query_client")

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

        -- Quest log tracking caches (W2.3, W2.4)
        _completed_quests = {},   -- { [quest_entry] = true }
        _active_quests = {},      -- { [quest_entry] = true }
        _quest_log_dirty = true,  -- refresh on next query
    }

    -- ====================================================================
    -- Navigation helpers (stubs — filled by Wave 3)
    -- ====================================================================
    function ctx:is_at_npc(entry)
        if core and core.object_manager and core.object_manager.GetNearestCreature then
            local npc = core.object_manager.GetNearestCreature({ entry })
            if npc and npc.IsValid and npc:IsValid() then
                return true
            end
        end
        return false
    end

    function ctx:is_at_destination(zone_name, tolerance)
        if core and core.object_manager and core.object_manager.GetPlayerInfo then
            local player = core.object_manager.GetPlayerInfo()
            return false
        end
        return false
    end

    function ctx:get_zone_waypoint(zone_name)
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