---@class Settings
---Settings management with persistence to JSON file
local Settings = {}
Settings.__index = Settings

-- Import dependencies (relative paths since we're in GatherBuddy folder)
local JSON = require("lib/JSON")
local Helpers = require("lib/Helpers")
local Constants = require("core/Constants")

-- Settings file path (relative to scripts_data/)
local SETTINGS_PATH = "gatherbuddy/settings.json"
local SETTINGS_FOLDER = "gatherbuddy"

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "lib/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("Settings")
    end
    return nil
end

-- Current settings (loaded or default)
local _current_settings = nil
local _log = nil

---Initialize the settings system
---@return table settings The current settings
function Settings.init()
    _log = get_logger()
    _current_settings = Helpers.deep_copy(Constants.DEFAULT_SETTINGS)

    -- Try to load existing settings
    Settings.load()

    return _current_settings
end

---Ensure the settings folder exists
local function ensure_folder()
    core.create_data_folder(SETTINGS_FOLDER)
end

---Load settings from file
---@return boolean success True if settings were loaded
function Settings.load()
    if not _current_settings then
        _current_settings = Helpers.deep_copy(Constants.DEFAULT_SETTINGS)
    end

    local json_str = core.read_data_file(SETTINGS_PATH)
    if not json_str or json_str == "" then
        if _log then
            _log:info("No settings file found, using defaults")
        end
        return false
    end

    local data, err = JSON.decode(json_str)
    if not data then
        if _log then
            _log:error("Failed to parse settings: %s", tostring(err))
        end
        return false
    end

    -- Merge loaded settings with defaults (to handle new settings added in updates)
    Settings._merge_settings(_current_settings, data)

    if _log then
        _log:info("Settings loaded successfully")
    end

    return true
end

---Recursively merge loaded settings into current settings
---@param target table Target table (defaults)
---@param source table Source table (loaded data)
function Settings._merge_settings(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            Settings._merge_settings(target[key], value)
        else
            target[key] = value
        end
    end
end

---Save current settings to file
---@return boolean success True if settings were saved
function Settings.save()
    if not _current_settings then
        if _log then
            _log:error("No settings to save")
        end
        return false
    end

    ensure_folder()

    local json_str, err = JSON.encode(_current_settings, true) -- pretty print
    if not json_str or json_str == "" then
        if _log then
            _log:error("Failed to encode settings: %s", tostring(err))
        end
        return false
    end

    core.create_data_file(SETTINGS_PATH)
    core.write_data_file(SETTINGS_PATH, json_str)

    if _log then
        _log:info("Settings saved successfully")
    end

    return true
end

---Get a setting value by path
---@param path string Dot-separated path (e.g., "movement.mount_threshold")
---@param default? any Default value if not found
---@return any value The setting value or default
function Settings.get(path, default)
    if not _current_settings then
        Settings.init()
    end

    return Helpers.get_nested(_current_settings, path, default)
end

---Set a setting value by path
---@param path string Dot-separated path
---@param value any The value to set
---@return boolean success True if setting was updated
function Settings.set(path, value)
    if not _current_settings then
        Settings.init()
    end

    local success = Helpers.set_nested(_current_settings, path, value)

    if success and _log then
        _log:debug("Set %s = %s", path, tostring(value))
    end

    return success
end

---Get all settings
---@return table settings A copy of all current settings
function Settings.get_all()
    if not _current_settings then
        Settings.init()
    end

    return Helpers.deep_copy(_current_settings)
end

---Reset all settings to defaults
function Settings.reset()
    _current_settings = Helpers.deep_copy(Constants.DEFAULT_SETTINGS)

    if _log then
        _log:info("Settings reset to defaults")
    end
end

---Reset a specific section to defaults
---@param section string The section to reset (e.g., "movement")
---@return boolean success True if section was reset
function Settings.reset_section(section)
    if not Constants.DEFAULT_SETTINGS[section] then
        if _log then
            _log:warn("Unknown settings section: %s", section)
        end
        return false
    end

    if not _current_settings then
        Settings.init()
    end

    _current_settings[section] = Helpers.deep_copy(Constants.DEFAULT_SETTINGS[section])

    if _log then
        _log:info("Reset section '%s' to defaults", section)
    end

    return true
end

---Get a section of settings
---@param section string The section name
---@return table|nil section_settings The section or nil if not found
function Settings.get_section(section)
    if not _current_settings then
        Settings.init()
    end

    local section_data = _current_settings[section]
    if section_data then
        return Helpers.deep_copy(section_data)
    end

    return nil
end

---Update multiple settings at once
---@param updates table<string, any> Map of path -> value
function Settings.update(updates)
    for path, value in pairs(updates) do
        Settings.set(path, value)
    end
end

---Check if a setting exists
---@param path string Dot-separated path
---@return boolean exists
function Settings.has(path)
    local value = Settings.get(path, nil)
    return value ~= nil
end

---Get the settings file path
---@return string path
function Settings.get_file_path()
    return SETTINGS_PATH
end

---Validate settings against schema
---@return boolean valid, string[] errors
function Settings.validate()
    local errors = {}

    if not _current_settings then
        Settings.init()
    end

    -- Check required sections exist
    local required_sections = {
        "general", "movement", "gathering", "safety",
        "anti_detection", "inventory", "navigation", "ui"
    }

    for _, section in ipairs(required_sections) do
        if not _current_settings[section] then
            table.insert(errors, "Missing section: " .. section)
        end
    end

    -- Validate numeric ranges
    local function check_range(path, min, max)
        local value = Settings.get(path)
        if value then
            if type(value) ~= "number" then
                table.insert(errors, path .. " must be a number")
            elseif value < min or value > max then
                table.insert(errors, path .. " must be between " .. min .. " and " .. max)
            end
        end
    end

    check_range("movement.mount_threshold", 0, 500)
    check_range("movement.waypoint_tolerance", 0.5, 20)
    check_range("gathering.node_search_radius", 10, 200)
    check_range("gathering.gather_timeout", 1, 60)
    check_range("safety.enemy_scan_radius", 5, 100)
    check_range("safety.flee_health_threshold", 1, 100)

    -- Validate boolean settings
    local function check_boolean(path)
        local value = Settings.get(path)
        if value ~= nil and type(value) ~= "boolean" then
            table.insert(errors, path .. " must be a boolean")
        end
    end

    check_boolean("general.enabled")
    check_boolean("general.debug_mode")
    check_boolean("anti_detection.enabled")

    return #errors == 0, errors
end

---Run unit tests
---@return table<string, boolean> Test results
function Settings._test()
    local results = {}

    -- Save current settings for restoration
    local backup = _current_settings

    -- Test 1: Init creates settings
    Settings.reset()
    results.init = (_current_settings ~= nil)

    -- Test 2: Get default value
    local mount_threshold = Settings.get("movement.mount_threshold")
    results.get_default = (mount_threshold == Constants.DEFAULT_SETTINGS.movement.mount_threshold)

    -- Test 3: Get with path
    local nested = Settings.get("anti_detection.random_pause_enabled")
    results.get_nested = (nested == true)

    -- Test 4: Get with default
    local missing = Settings.get("nonexistent.path", 12345)
    results.get_with_default = (missing == 12345)

    -- Test 5: Set value
    Settings.set("movement.mount_threshold", 99)
    results.set_value = (Settings.get("movement.mount_threshold") == 99)

    -- Test 6: Has check
    results.has_exists = Settings.has("movement.mount_threshold")
    results.has_missing = not Settings.has("completely.fake.path")

    -- Test 7: Get section
    local movement = Settings.get_section("movement")
    results.get_section = (movement ~= nil and movement.mount_threshold == 99)

    -- Test 8: Reset section
    Settings.reset_section("movement")
    results.reset_section = (Settings.get("movement.mount_threshold") == Constants.DEFAULT_SETTINGS.movement.mount_threshold)

    -- Test 9: Reset all
    Settings.set("general.debug_mode", true)
    Settings.reset()
    results.reset_all = (Settings.get("general.debug_mode") == false)

    -- Test 10: Validate
    local valid, errors = Settings.validate()
    results.validate = valid

    -- Test 11: Update multiple
    Settings.update({
        ["general.debug_mode"] = true,
        ["movement.mount_threshold"] = 50
    })
    results.update_multiple = (
        Settings.get("general.debug_mode") == true and
        Settings.get("movement.mount_threshold") == 50
    )

    -- Restore backup
    _current_settings = backup or Helpers.deep_copy(Constants.DEFAULT_SETTINGS)

    return results
end

return Settings
