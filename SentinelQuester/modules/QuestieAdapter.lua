---@class QuestieAdapter
---@field private _require_path string
---@field private _questie table|nil
---@field private _load_error string|nil
local QuestieAdapter = {}
QuestieAdapter.__index = QuestieAdapter

local DEFAULT_REQUIRE_PATH = "common/utility/questie_tracker"

local function safe_method(obj, method_name, ...)
    if not obj then
        return nil, "missing_object"
    end

    local fn = obj[method_name]
    if type(fn) ~= "function" then
        return nil, "missing_method"
    end

    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil, result
    end

    return result, nil
end

---@param opts? table
---@return QuestieAdapter
function QuestieAdapter:new(opts)
    local o = setmetatable({}, QuestieAdapter)
    opts = opts or {}

    o._require_path = opts.require_path or DEFAULT_REQUIRE_PATH
    o._questie = nil
    o._load_error = nil

    return o
end

---@return boolean
function QuestieAdapter:_try_load()
    if self._questie then
        return true
    end

    local ok, lib = pcall(require, self._require_path)
    if not ok then
        self._load_error = tostring(lib)
        return false
    end

    if type(lib) ~= "table" then
        self._load_error = "questie_tracker did not return a table"
        return false
    end

    self._questie = lib
    self._load_error = nil
    return true
end

---@return boolean
function QuestieAdapter:is_available()
    return self:_try_load()
end

---@return boolean
function QuestieAdapter:is_hooked()
    if not self:_try_load() then
        return false
    end

    local hooked = safe_method(self._questie, "is_hooked")
    return hooked == true
end

---@param obj game_object
---@return boolean
function QuestieAdapter:is_quest_object(obj)
    if not obj then
        return false
    end

    if not self:is_hooked() then
        return false
    end

    local is_target = safe_method(self._questie, "is_quest_object", obj)
    return is_target == true
end

---@param obj game_object
---@return boolean
function QuestieAdapter:is_quest_npc(obj)
    -- Not provided by questie_tracker API in this environment.
    return false
end

---@return string|nil
function QuestieAdapter:get_error()
    return self._load_error
end

---@return string
function QuestieAdapter:get_status()
    if not self:_try_load() then
        return "missing"
    end

    if not self:is_hooked() then
        return "not_hooked"
    end

    return "hooked"
end

return QuestieAdapter
