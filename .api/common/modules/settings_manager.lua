
-- Example:
-- ---@type settings_manager
-- local settings = require("common/modules/settings_manager")
-- settings: -> IntelliSense
-- Warning: Access with ":", not "."

---@meta
---@diagnostic disable: undefined-global, missing-fields, lowercase-global

---@class settings_manager
--- Internal storage for attached menu elements (keyed by namespace).
--- Do not modify directly.
---@field public _attached table<string, table|userdata>
--- Set the file name (without extension) for saving/loading settings.
--- Returns false if name is empty or contains invalid characters (\ / : * ? " < > |).
--- The extension ".txt" is automatically appended.
---@field public set_file_name fun(self: settings_manager, name: string): boolean
--- Flatten a nested table into dot-separated keys.
--- Example: {a = {b = 1}} becomes {"a.b" = 1}
---@field public flatten_table fun(self: settings_manager, tbl: table, prefix?: string, result?: table): table
--- Unflatten a dot-separated key table back into nested structure.
--- Example: {"a.b" = 1} becomes {a = {b = 1}}
---@field public unflatten_table fun(self: settings_manager, flat_tbl: table): table
--- Attach menu elements for automatic settings management.
--- Can attach a single element with namespace, or a table of elements (will iterate recursively).
--- Supports tables and userdata with get_state/get/get_default methods.
--- For a single menu element, you MUST provide a namespace/key.
---@field public attach fun(self: settings_manager, element: table|userdata, namespace?: string): nil
--- Build default settings from all attached elements.
--- Calls get_default() on each attached element that has that method.
---@field public build_default_settings fun(self: settings_manager): table
--- Collect current values from all attached elements.
--- Returns nested table structure with current UI values.
---@field public collect_attached_settings fun(self: settings_manager): table
--- Apply nested settings to all attached elements.
--- Converts nested table to flat and calls set on matching elements.
--- Handles type conversion (string to number/boolean) based on element defaults.
--- Skips button, keybind, and tree elements.
---@field public apply_attached_settings fun(self: settings_manager, nested_settings: table): nil
--- Save current settings to file.
--- Shows override confirmation notification if file already exists.
--- Returns false if file name not set or file exists (must click notification to confirm).
--- Use save_int() to bypass the confirmation.
---@field public save fun(self: settings_manager): boolean
--- Internal save function that bypasses override confirmation.
--- Directly writes settings to file without checking if it exists.
---@field public save_int fun(self: settings_manager): boolean
--- Load settings from file.
--- Merges loaded settings with defaults (missing keys get default values).
--- Applies loaded settings to attached elements.
---@field public load fun(self: settings_manager): table|boolean
--- Import settings from file (alias for load).
---@field public import fun(self: settings_manager): table|boolean
--- Get a specific setting value by dot-separated key.
--- Example: settings:get("combat.burst.enabled")
---@field public get fun(self: settings_manager, key: string): any
--- Set a specific setting value by dot-separated key.
--- Updates both current_settings and the attached element if present.
--- Auto-saves after setting.
---@field public set fun(self: settings_manager, key: string, value: any): boolean
--- Reset UI elements to default values without saving to file.
--- Persistent settings on disk remain unchanged.
---@field public resetUI fun(self: settings_manager): nil
--- Full reset to defaults.
--- If saveToFile is true, also persists defaults to disk.
---@field public reset fun(self: settings_manager, saveToFile?: boolean): nil
--- Initialize settings manager.
--- Builds defaults from attached elements and attempts to load from file.
--- Call this after attaching all elements and setting file name.
---@field public init fun(self: settings_manager): table|boolean

--[[
USAGE EXAMPLES:

-- Basic Setup
local settings = require("common/modules/settings_manager")
settings:set_file_name("my_plugin_settings")

local menu = {
    combat = {
        enabled = core.menu.checkbox("Enable Combat", true),
        burst_threshold = core.menu.slider("Burst HP%", 0, 100, 30),
    },
}
settings:attach(menu)
settings:init()

-- Get/Set
local val = settings:get("combat.enabled")
settings:set("combat.burst_threshold", 50)

-- Save/Load
settings:save()
settings:load()

-- Reset
settings:resetUI()           -- UI only
settings:reset(true)         -- UI + save to file
]]

---@type settings_manager
local tbl
return tbl
