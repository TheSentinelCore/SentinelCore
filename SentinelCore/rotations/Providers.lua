local Providers = {}

-- Add new class/spec providers here. RotationEngine consumes this catalog.
local CATALOG = {
    [2] = {
        "rotations/paladin/Retribution",
    },
    [9] = {
        "rotations/warlock/Affliction",
    },
}

local _loaded = {}

---@private
---@param path string
---@return table|nil
local function load_provider(path)
    if _loaded[path] ~= nil then
        return _loaded[path] or nil
    end

    local ok, provider = pcall(require, path)
    if ok and provider then
        _loaded[path] = provider
        return provider
    end

    _loaded[path] = false
    return nil
end

---@param class_id number|nil
---@return table[]
function Providers.load_for_class(class_id)
    local providers = {}
    local normalized = tonumber(class_id) or 0
    if normalized <= 0 then
        return providers
    end

    local paths = CATALOG[normalized]
    if type(paths) ~= "table" then
        return providers
    end

    for i = 1, #paths do
        local provider = load_provider(paths[i])
        if provider then
            providers[#providers + 1] = provider
        end
    end

    return providers
end

return Providers
