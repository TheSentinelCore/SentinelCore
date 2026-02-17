--[[
    SentinelGather - Automated Gathering Bot

    A World of Warcraft herbalism/mining gathering bot built on the Sylvannas API.

    Features:
    - JSON-based profile system for routes
    - Event-driven architecture
    - Navigation service integration
    - Human-like behavior patterns
    - Combat and death handling

    Usage:
        local SentinelGather = require("init")
        SentinelGather:start("profiles/elwynn_copper.json")

    CRITICAL: Uses ONLY Sylvannas API - no WoW Lua API calls permitted.
]]

---@class SentinelGather
---@field private _bot_manager BotManager|nil
---@field private _initialized boolean
---@field private _update_registered boolean
---@field VERSION string
---@field NAME string
local SentinelGather = {}
SentinelGather.__index = SentinelGather

-- Version info
SentinelGather.VERSION = "1.0.0"
SentinelGather.NAME = "Sentinel Gather"

-- Singleton instance
local _instance = nil

---Get the SentinelGather singleton instance
---@return SentinelGather
function SentinelGather:get_instance()
    if not _instance then
        _instance = self:_create_instance()
    end
    return _instance
end

---Create a new instance (internal)
---@return SentinelGather
function SentinelGather:_create_instance()
    local instance = setmetatable({}, SentinelGather)

    -- Import BotManager (relative path since we're in SentinelGather folder)
    local success, BotManager = pcall(require, "core/BotManager")
    if not success then
        core.log_error("[SentinelGather] Failed to load BotManager: " .. tostring(BotManager))
        return instance
    end

    -- Create bot manager
    instance._bot_manager = BotManager:new()
    instance._initialized = false
    instance._update_registered = false

    return instance
end

---Initialize SentinelGather
---@return boolean success
function SentinelGather:initialize()
    local instance = self:get_instance()

    if instance._initialized then
        return true
    end

    if not instance._bot_manager then
        core.log_error("[SentinelGather] BotManager not available")
        return false
    end

    -- Initialize bot manager
    local success = instance._bot_manager:initialize()
    if not success then
        core.log_error("[SentinelGather] Failed to initialize BotManager")
        return false
    end

    -- Register update callback if not already done
    if not instance._update_registered then
        core.register_on_update_callback(function()
            instance:update()
        end)
        instance._update_registered = true
    end

    instance._initialized = true
    core.log("[SentinelGather] Initialized v" .. SentinelGather.VERSION)

    return true
end

---Start gathering with optional profile
---@param profile_path? string Path to profile JSON file
---@return boolean success
function SentinelGather:start(profile_path)
    local instance = self:get_instance()

    -- Auto-initialize if needed
    if not instance._initialized then
        if not self:initialize() then
            return false
        end
    end

    if not instance._bot_manager then
        return false
    end

    return instance._bot_manager:start(profile_path)
end

---Stop gathering
function SentinelGather:stop()
    local instance = self:get_instance()

    if instance._bot_manager then
        instance._bot_manager:stop()
    end
end

---Pause gathering
function SentinelGather:pause()
    local instance = self:get_instance()

    if instance._bot_manager then
        instance._bot_manager:pause()
    end
end

---Resume gathering
function SentinelGather:resume()
    local instance = self:get_instance()

    if instance._bot_manager then
        instance._bot_manager:resume()
    end
end

---Toggle pause state
function SentinelGather:toggle_pause()
    local instance = self:get_instance()

    if instance._bot_manager then
        instance._bot_manager:toggle_pause()
    end
end

---Update tick (called automatically)
function SentinelGather:update()
    local instance = self:get_instance()

    if instance._bot_manager and instance._initialized then
        instance._bot_manager:update()
    end
end

---Check if running
---@return boolean
function SentinelGather:is_running()
    local instance = self:get_instance()

    if instance._bot_manager then
        return instance._bot_manager:is_running()
    end
    return false
end

---Check if paused
---@return boolean
function SentinelGather:is_paused()
    local instance = self:get_instance()

    if instance._bot_manager then
        return instance._bot_manager:is_paused()
    end
    return false
end

---Get current state
---@return string
function SentinelGather:get_state()
    local instance = self:get_instance()

    if instance._bot_manager then
        return instance._bot_manager:get_state()
    end
    return "unknown"
end

---Get bot manager (for advanced usage)
---@return BotManager|nil
function SentinelGather:get_bot_manager()
    local instance = self:get_instance()
    return instance._bot_manager
end

---Get a specific module
---@param name string Module name
---@return table|nil
function SentinelGather:get_module(name)
    local instance = self:get_instance()

    if instance._bot_manager then
        return instance._bot_manager:get_module(name)
    end
    return nil
end

---Get statistics
---@return table|nil
function SentinelGather:get_statistics()
    local stats_module = self:get_module("Statistics")
    if stats_module then
        return stats_module:get_stats()
    end
    return nil
end

---Load a profile
---@param path string Profile path
---@return boolean success
function SentinelGather:load_profile(path)
    local profile_mgr = self:get_module("ProfileManager")
    if profile_mgr then
        return profile_mgr:load_profile(path)
    end
    return false
end

---Clean up (call when unloading)
function SentinelGather:destroy()
    local instance = self:get_instance()

    if instance._bot_manager then
        instance._bot_manager:destroy()
        instance._bot_manager = nil
    end

    instance._initialized = false
    _instance = nil

    core.log("[SentinelGather] Destroyed")
end

---Run all unit tests
---@return table<string, table<string, boolean>> All test results
function SentinelGather:run_tests()
    local results = {}

    -- Test modules (use relative paths since we're in SentinelGather folder)
    local test_modules = {
        { name = "JSON", path = "lib/JSON" },
        { name = "Helpers", path = "lib/Helpers" },
        { name = "Logger", path = "lib/Logger" },
        { name = "EventBus", path = "core/EventBus" },
        { name = "StateMachine", path = "core/StateMachine" },
        { name = "Nodes", path = "data/Nodes" },
        { name = "Settings", path = "core/Settings" },
        { name = "ProfileManager", path = "modules/ProfileManager" },
        { name = "Navigation", path = "modules/Navigation" },
        { name = "Movement", path = "modules/Movement" },
        { name = "NodeScanner", path = "modules/NodeScanner" },
        { name = "Gather", path = "modules/Gather" },
        { name = "Mount", path = "modules/Mount" },
        { name = "Safety", path = "modules/Safety" },
        { name = "Inventory", path = "modules/Inventory" },
        { name = "Statistics", path = "modules/Statistics" },
        { name = "BotManager", path = "core/BotManager" },
    }

    for _, module_info in ipairs(test_modules) do
        local success, module = pcall(require, module_info.path)
        if success and module and module._test then
            local test_success, test_results = pcall(module._test, module)
            if test_success then
                results[module_info.name] = test_results
            else
                results[module_info.name] = { error = tostring(test_results) }
            end
        end
    end

    -- Print results
    local total_tests = 0
    local passed_tests = 0

    core.log("[SentinelGather] Test Results:")
    for module_name, module_results in pairs(results) do
        local module_passed = 0
        local module_total = 0

        for test_name, result in pairs(module_results) do
            module_total = module_total + 1
            if result == true then
                module_passed = module_passed + 1
            end
        end

        total_tests = total_tests + module_total
        passed_tests = passed_tests + module_passed

        local status = module_passed == module_total and "PASS" or "FAIL"
        core.log(string.format("  %s: %s (%d/%d)", module_name, status, module_passed, module_total))
    end

    core.log(string.format("[SentinelGather] Total: %d/%d tests passed", passed_tests, total_tests))

    return results
end

return SentinelGather
