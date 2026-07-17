-- sentinel/modules/quest/routing_policy_loader.lua
-- Routing Policy Loader: loads and validates YAML policy files

local JSON = require("lib/JSON")

local RoutingPolicyLoader = {}
RoutingPolicyLoader.__index = RoutingPolicyLoader

local POLICY_DIR = "sentinel/data/routing_policies/"

local SCHEMA = {
    required = {"name", "strategy"},
    properties = {
        name = {type = "string"},
        strategy = {type = "string", enum = {"smart", "direct", "road_only", "offroad"}},
        preferredPath = {type = "string", enum = {"road", "any", "offroad"}},
        avoid = {type = "array", items = {type = "string"}},
        dynamicReplan = {type = "boolean"},
        allowShortcuts = {type = "boolean"},
        opportunisticKills = {type = "array", items = {type = "string"}},
        opportunisticLoot = {type = "array", items = {type = "string"}},
        ignore = {type = "array", items = {type = "string"}},
    }
}

local DEFAULTS = {
    strategy = "smart",
    preferredPath = "road",
    avoid = {},
    dynamicReplan = true,
    allowShortcuts = true,
    opportunisticKills = {},
    opportunisticLoot = {},
    ignore = {"Rare", "Elite"},
}

function RoutingPolicyLoader.new(policyDir)
    return setmetatable({
        _dir = policyDir or POLICY_DIR,
        _cache = {},
    }, RoutingPolicyLoader)
end

function RoutingPolicyLoader:load(name)
    if self._cache[name] then
        return self._cache[name]
    end

    local path = self._dir .. name .. ".yaml"
    local content = core.read_file(path)
    if not content then
        return nil, "Policy file not found: " .. path
    end

    -- Parse YAML (simple subset parser)
    local policy = self:_parseYAML(content)
    if not policy then
        return nil, "Failed to parse YAML: " .. path
    end

    -- Validate
    local ok, err = self:_validate(policy)
    if not ok then
        return nil, err
    end

    -- Apply defaults
    for k, v in pairs(DEFAULTS) do
        if policy[k] == nil then
            policy[k] = v
        end
    end

    self._cache[name] = policy
    return policy
end

function RoutingPolicyLoader:_parseYAML(content)
    local policy = {}
    local current_array = nil
    local current_key = nil

    for line in content:gmatch("([^\n]*)\n?") do
        -- Skip comments and empty lines
        line = line:match("^%s*(.-)%s*$")
        if line == "" or line:match("^#") then
            goto continue
        end

        -- Check for array item (- item)
        local array_item = line:match("^-%s*(.+)$")
        if array_item then
            -- Strip trailing # comments
            array_item = array_item:gsub("#.*$", "")
            array_item = array_item:match("^%s*(.-)%s*$")
            if current_array and array_item then
                table.insert(current_array, array_item)
            end
            goto continue
        end

        -- Key: value
        local key, value = line:match("^([^:]+):%s*(.*)$")
        if key then
            key = key:match("^%s*(.-)%s*$")
            value = value:match("^%s*(.-)%s*$")

            if value == "" or value == "[]" then
                -- Start array
                current_array = {}
                policy[key] = current_array
                current_key = key
            elseif value == "{}" then
                policy[key] = {}
            elseif value:match("^%d+$") then
                policy[key] = tonumber(value)
            elseif value == "true" then
                policy[key] = true
            elseif value == "false" then
                policy[key] = false
            else
                -- String value (quoted or unquoted)
                -- Strip trailing # comments
                value = value:gsub("#.*$", "")
                value = value:match("^%s*(.-)%s*$")
                value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
                policy[key] = value
            end
            current_array = nil
        end

        ::continue::
    end

    return policy
end

function RoutingPolicyLoader:_validate(policy)
    for _, req in ipairs(SCHEMA.required) do
        if policy[req] == nil then
            return false, "Missing required field: " .. req
        end
    end

    -- Validate enums
    if policy.strategy and not self:_contains(SCHEMA.properties.strategy.enum, policy.strategy) then
        return false, "Invalid strategy: " .. policy.strategy
    end

    if policy.preferredPath and not self:_contains(SCHEMA.properties.preferredPath.enum, policy.preferredPath) then
        return false, "Invalid preferredPath: " .. policy.preferredPath
    end

    return true, nil
end

function RoutingPolicyLoader:_contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

function RoutingPolicyLoader:list()
    local files = core.read_dir(self._dir) or {}
    local policies = {}
    for _, f in ipairs(files) do
        local name = f:match("^(.+)%.yaml$")
        if name then
            table.insert(policies, name)
        end
    end
    return policies
end

function RoutingPolicyLoader:clearCache()
    self._cache = {}
end

return RoutingPolicyLoader