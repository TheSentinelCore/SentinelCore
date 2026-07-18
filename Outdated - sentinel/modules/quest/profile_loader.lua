-- sentinel/modules/quest/profile_loader.lua
-- Profile Loader: Discovers and loads quest profiles from scripts_data/quest_profiles/
-- Profiles are copied from the bundled source on first run, then read from scripts_data.

local ProfileLoader = {}
ProfileLoader.__index = ProfileLoader

local JSON = require("lib/JSON")

local PROFILE_DIR = "quest_profiles"
local SOURCE_PROFILE_DIR = "sentinel/data/profiles/quests"

function ProfileLoader.new()
    return setmetatable({
        _profiles = {},       -- loaded profile data by ID
        _available = nil,     -- cached list of {id, name, levelRange, faction} from filesystem
        _active_profile = nil,
    }, ProfileLoader)
end

-- ============================================================================
-- FILESYSTEM HELPERS
-- ============================================================================

-- Ensure profiles are copied from bundled source to scripts_data (JSON only)
local function ensure_profiles_in_scripts_data()
    pcall(core.create_data_folder, PROFILE_DIR)
    
    local source_files = core.read_dir(SOURCE_PROFILE_DIR)
    if not source_files then return false end
    
    for _, filename in ipairs(source_files) do
        if filename:match("%.json$") then
            local source_path = SOURCE_PROFILE_DIR .. "/" .. filename
            local dest_path = PROFILE_DIR .. "/" .. filename
            
            local dest_content = core.read_data_file(dest_path)
            local src_content = core.read_file(source_path)
            
            if src_content and (not dest_content or dest_content ~= src_content) then
                pcall(core.create_data_file, dest_path)
                pcall(core.write_data_file, dest_path, src_content)
            end
        end
    end
    
    return true
end

-- Parse a JSON profile string and extract just the metadata header
local function parse_profile_metadata(content)
    if not content or content == "" then return nil end
    
    local ok, data = pcall(JSON.decode, content)
    if not ok or not data then return nil end
    if not data.profile then return nil end
    
    local p = data.profile
    return {
        id = p.id or "unknown",
        name = p.name or p.id or "Unknown Profile",
        faction = p.faction or "Any",
        race = p.race,
        class = p.class,
        levelRange = p.levelRange,
        expansion = p.expansion,
    }
end

-- ============================================================================
-- PROFILE DISCOVERY
-- ============================================================================

-- Discover all available profiles from scripts_data/quest_profiles/
-- Returns a sorted array of metadata tables.
function ProfileLoader:discoverProfiles()
    local list = {}
    
    if not core.read_dir then return list end
    
    local files = core.read_dir(PROFILE_DIR)
    if not files then return list end
    
    for _, filename in ipairs(files) do
        if filename:match("%.json$") then
            local id = filename:gsub("%.json$", "")
            local path = PROFILE_DIR .. "/" .. filename
            
            -- Try cached data first
            if self._profiles[id] then
                local p = self._profiles[id].profile or {}
                table.insert(list, {
                    id = id,
                    name = p.name or id,
                    faction = p.faction or "Any",
                    levelRange = p.levelRange,
                })
            else
                -- Read and parse just for metadata
                local ok, content = pcall(core.read_data_file, path)
                if ok and content and content ~= "" then
                    local meta = parse_profile_metadata(content)
                    if meta then
                        table.insert(list, meta)
                    end
                end
            end
        end
    end
    
    -- Sort by name for consistent display
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    
    return list
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function ProfileLoader:initialize()
    ensure_profiles_in_scripts_data()
    self._available = nil  -- invalidate cache
end

function ProfileLoader:loadProfile(profileId)
    if self._profiles[profileId] then
        return self._profiles[profileId]
    end
    
    local filename = profileId .. ".json"
    local path = PROFILE_DIR .. "/" .. filename
    
    local read_ok, content = pcall(core.read_data_file, path)
    if not read_ok or not content or content == "" then
        return nil, "failed to read profile: " .. path
    end
    
    local decode_ok, data = pcall(JSON.decode, content)
    if not decode_ok or not data then
        return nil, "failed to parse JSON: " .. tostring(data)
    end
    
    if not data.profile or not data.profile.id then
        return nil, "invalid profile structure"
    end
    
    self._profiles[profileId] = data
    return data
end

function ProfileLoader:loadActiveProfile()
    local available = self:discoverProfiles()
    if #available == 0 then return nil end
    
    for _, meta in ipairs(available) do
        if not self._profiles[meta.id] then
            local data = self:loadProfile(meta.id)
            if data then
                self._active_profile = data
                return data
            end
        end
    end
    return nil
end

function ProfileLoader:getProfile(profileId)
    return self._profiles[profileId]
end

function ProfileLoader:getActiveProfile()
    return self._active_profile
end

function ProfileLoader:setActiveProfile(profileId)
    local profile = self:loadProfile(profileId)
    if profile then
        self._active_profile = profile
        return true
    end
    return false
end

-- Returns a list of all discoverable profiles (does not require loading them all)
function ProfileLoader:listProfiles()
    return self:discoverProfiles()
end

function ProfileLoader:shutdown()
    self._profiles = {}
    self._available = nil
    self._active_profile = nil
end

return ProfileLoader