local JSON = require("lib/JSON")

local QuestProfileManager = {}
QuestProfileManager.__index = QuestProfileManager

local PROFILE_DIR = "quest_profiles"
local SOURCE_PROFILE_DIR = "sentinel/data/profiles/quests"

---Log a message
local function log(msg)
    if core and core.log then
        core.log("[QuestProfileManager] " .. msg)
    end
end

---Log error
local function log_error(msg)
    if core and core.log_error then
        core.log_error("[QuestProfileManager] " .. msg)
    end
end

---Ensure profiles are copied to scripts_data
local function ensure_profiles_in_scripts_data()
    -- Create the directory in scripts_data
    pcall(core.create_data_folder, PROFILE_DIR)
    
    -- List all YAML files in source directory
    local source_files = core.read_dir(SOURCE_PROFILE_DIR)
    if not source_files then
        log_error("failed to read source profile directory: " .. SOURCE_PROFILE_DIR)
        return false
    end
    
    -- Copy each YAML file to scripts_data if it doesn't exist or is different
    for _, filename in ipairs(source_files) do
        if filename:match("%.yaml$") then
            local source_path = SOURCE_PROFILE_DIR .. "/" .. filename
            local dest_path = PROFILE_DIR .. "/" .. filename
            
            -- Check if destination exists and is same content
            local dest_content = core.read_data_file(dest_path)
            local src_content = core.read_file(source_path)
            
            if src_content and (not dest_content or dest_content ~= src_content) then
                -- Create file if needed and write content
                pcall(core.create_data_file, dest_path)
                local write_ok = pcall(core.write_data_file, dest_path, src_content)
                if write_ok then
                    log("copied profile to scripts_data: " .. filename)
                else
                    log_error("failed to write profile to scripts_data: " .. filename)
                end
            end
        end
    end
    
    return true
end

---Create new QuestProfileManager
---@param event_bus table
---@param blackboard table
---@return QuestProfileManager
function QuestProfileManager.new(event_bus, blackboard)
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _profiles = {},
        _active_profile = nil,
        _active_profile_name = nil,
    }, QuestProfileManager)
end

---Initialize the profile manager (copy YAML profiles to scripts_data)
function QuestProfileManager:initialize()
    ensure_profiles_in_scripts_data()
end

---Ensure YAML profiles are copied to scripts_data
local function ensure_profiles_in_scripts_data()
    pcall(core.create_data_folder, PROFILE_DIR)
    local files = core.read_dir(PROFILE_DIR) or {}
    for _, filename in ipairs(files) do
        if filename:match("%.yaml$") then
            local source_path = "sentinel/data/profiles/quests/" .. filename
            local dest_path = PROFILE_DIR .. "/" .. filename
            local ok, content = pcall(core.read_file, source_path)
            if ok and content and content ~= "" then
                pcall(core.write_data_file, PROFILE_DIR .. "/" .. filename, content)
            end
        end
    end
end

---Load a quest profile by zone name
---@param zone_name string Zone name (e.g., "westfall")
---@return boolean success
---@return string|nil error
function QuestProfileManager:load_profile(zone_name)
    ensure_profiles_in_scripts_data()
    local filename = zone_name:lower() .. ".yaml"
    local path = PROFILE_DIR .. "/" .. filename
    
    local read_ok, content = pcall(core.read_data_file, path)
    if not read_ok or not content or content == "" then
        local err = "failed to read quest profile: " .. path
        log_error(err)
        return false, err
    end
    
    local data = self:_parse_yaml(content)
    if not data then
        local err = "failed to parse YAML: " .. filename
        log_error(err)
        return false, err
    end
    
    -- Validate required fields
    if not data.zone or not data.level_range or not data.rules then
        local err = "invalid quest profile structure: " .. filename
        log_error(err)
        return false, err
    end
    
    -- Normalize rules
    data.rules = self:_normalize_rules(data.rules)
    data.scoring = data.scoring or {}
    data.objective_strategy = data.objective_strategy or "cluster"
    
    self._profiles[zone_name:lower()] = data
    log("loaded quest profile: " .. data.zone)
    
    return true, nil
end

---Auto-load profile for current zone/level
---@param player_level number
---@param map_id number
---@param faction string "Alliance" | "Horde" | "Both"
---@return boolean success
function QuestProfileManager:try_autoload(player_level, map_id, faction)
    -- Map map_id to zone names (only zones with existing YAML profiles)
    -- map_id 0 = Eastern Kingdoms, 1 = Kalimdor
    local zone_map = {
        [0] = {"westfall", "redridge", "duskwood", "loch_modan", "silverpine"},
        [1] = {"the_barrens", "darkshore"},
    }
    
    local zones = zone_map[map_id] or zone_map[0]
    
    -- Try each zone in order
    for _, zone in ipairs(zones) do
        local profile = self._profiles[zone]
        if not profile then
            -- Try to load it
            local ok = self:load_profile(zone)
            if not ok then goto continue end
            profile = self._profiles[zone]
        end
        
        local lr = profile.level_range
        if lr and lr.min <= player_level and player_level <= lr.max then
            local pf = profile.faction
            if pf == "Both" or pf == faction then
                self._active_profile = profile
                self._active_profile_name = zone
                self._blackboard:set("module.quest.active_profile", profile)
                self._event_bus:publish("quest:profile_loaded", {zone = zone})
                log("auto-loaded quest profile: " .. zone)
                return true
            end
        end
        
        ::continue::
    end
    
    -- Fallback to default
    if not self._profiles["default"] then
        self:load_profile("default")
    end
    if self._profiles["default"] then
        self._active_profile = self._profiles["default"]
        self._blackboard:set("module.quest.active_profile", self._active_profile)
        return true
    end
    
    return false
end

---Get active quest profile
---@return table|nil
function QuestProfileManager:get_active_quest_profile()
    return self._active_profile
end

---Get profile by zone name
---@param zone_name string
---@return table|nil
function QuestProfileManager:get_profile(zone_name)
    return self._profiles[zone_name:lower()]
end

---Shutdown
function QuestProfileManager:shutdown()
    self._profiles = {}
    self._active_profile = nil
    self._active_profile_name = nil
end

---Parse simple YAML
---@param content string
---@return table|nil
function QuestProfileManager:_parse_yaml(content)
    local result = {}
    local current_section = result
    local stack = {result}
    
    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$") -- trim
        if line == "" or line:sub(1,1) == "#" then goto continue end
        
        local indent = line:match("^(%s*)")
        local level = #indent / 2
        
        while #stack > level + 1 do
            table.remove(stack)
        end
        current_section = stack[#stack]
        
        local key, val = line:match("^(%w+)%s*:%s*(.*)$")
        if key and val then
            val = val:match("^(.-)%s*#") or val
            val = val:match("^%s*(.-)%s*$")
            
            if val == "true" then val = true
            elseif val == "false" then val = false
            elseif val:match("^%d+$") then val = tonumber(val)
            elseif val:match("^%d+%.%d+$") then val = tonumber(val)
            elseif val:match("^%[.*%]$") then
                val = {}
                for item in val:gmatch("%[?(.-)%]?") do
                    item = item:match("^%s*(.-)%s*$")
                    if item ~= "" then val[#val + 1] = item end
                end
            end
            
            current_section[key] = val
        end
        
        ::continue::
    end
    
    return result
end

---Normalize rules table with defaults
---@param rules table
---@return table
function QuestProfileManager:_normalize_rules(rules)
    local defaults = {
        skip_elites = true,
        skip_escort = false,
        skip_dungeon_chains = true,
        skip_pvp = true,
        max_travel_yards = 1800,
        min_xp_per_minute = 500,
        vendor_threshold_pct = 80,
        repair_threshold_pct = 40,
        min_bag_slots = 4,
    }
    
    local normalized = {}
    for k, v in pairs(defaults) do
        normalized[k] = rules[k] ~= nil and rules[k] or v
    end
    -- Add any extra rules
    for k, v in pairs(rules) do
        if not defaults[k] then normalized[k] = v end
    end
    return normalized
end

return QuestProfileManager