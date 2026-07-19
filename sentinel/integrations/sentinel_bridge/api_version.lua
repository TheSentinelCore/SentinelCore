-- sentinel/integrations/sentinel_bridge/api_version.lua
-- API Versioning - ADR 009 §12
-- Handles version checking and drift detection for Sylvanas API

local ApiVersion = {}

ApiVersion.CURRENT_API_VERSION = "1.0.0"

ApiVersion.REQUIRED_MODULES = {
    "core.game_time",
    "core.object_manager",
    "core.player",
    "core.quests",
    "core.graphics",
}

---Check if Sylvanas API is available and at correct version
---@return boolean available
---@return string? error_message
function ApiVersion.check_availability()
    if not _G.core then
        return false, "core API not available - Sylvanas not loaded?"
    end

    for _, module_path in ipairs(ApiVersion.REQUIRED_MODULES) do
        local parts = {}
        for part in string.gmatch(module_path, "[^.]+") do
            table.insert(parts, part)
        end

        local current = _G.core
        local found = true
        for _, part in ipairs(parts) do
            if type(current) ~= "table" or current[part] == nil then
                found = false
                break
            end
            current = current[part]
        end

        if not found then
            return false, "Required module not available: " .. module_path
        end
    end

    return true, nil
end

---Get the current API version from Sylvanas
---@return string|nil version or nil if unavailable
function ApiVersion.get_runtime_version()
    if _G.core and _G.core.get_api_version and type(_G.core.get_api_version) == "function" then
        local ok, version = pcall(_G.core.get_api_version)
        if ok and type(version) == "string" then
            return version
        end
    end
    return nil
end

---Verify API version compatibility
---@return boolean compatible
---@return string? error_message
function ApiVersion.verify_version()
    local available, err = ApiVersion.check_availability()
    if not available then
        return false, err
    end

    local runtime_version = ApiVersion.get_runtime_version()
    if runtime_version and runtime_version ~= ApiVersion.CURRENT_API_VERSION then
        return false, string.format(
            "Sentinel bridge built against Sylvanas API v%s, detected v%s. " ..
            "Please update SentinelCore to match your Sylvanas version.",
            ApiVersion.CURRENT_API_VERSION,
            runtime_version
        )
    end

    return true, nil
end

---Get the QuestClient factory (real or mock based on availability)
---@return table quest_client QuestClient implementation
function ApiVersion.get_quest_client()
    local available, _ = ApiVersion.check_availability()
    if available then
        local QuestBridge = require("integrations/sentinel_bridge/quest_bridge")
        return QuestBridge
    else
        local MockBridge = require("integrations/sentinel_bridge/mock_bridge")
        return MockBridge.get_quest_client()
    end
end

---Get the AddonsClient factory (real or mock based on availability)
---@return table addons_client AddonsClient implementation
function ApiVersion.get_addons_client()
    local available, _ = ApiVersion.check_availability()
    if available then
        local AddonsBridge = require("integrations/sentinel_bridge/addons_bridge")
        return AddonsBridge
    else
        local MockBridge = require("integrations/sentinel_bridge/mock_bridge")
        return MockBridge.get_addons_client()
    end
end

return ApiVersion