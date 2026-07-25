-- kernel/config.lua
-- Plugins declare a schema; the kernel validates, stores and persists.
--
-- ADR 08 §5.1: "Config + UIHost -- plugins declare schema; kernel renders and persists. MENU IDS
-- SHARE ONE GLOBAL NAMESPACE, so allocation must be centralised."
--
-- ================================================================================
-- WHY ID ALLOCATION IS HERE, WITH NO UI IN THIS PHASE
-- ================================================================================
-- §2.3 records that menu-element IDs share one namespace ACROSS ALL SYLVANAS PLUGINS -- not just
-- across Sentinel's own elements. Two plugins that pick the same string collide silently, and the
-- collision surfaces as a menu element that renders someone else's state. Centralising allocation
-- costs nothing now and cannot be retrofitted once plugins have shipped hardcoded IDs, so the
-- allocator lands in Phase 3 even though UIHost does not.
--
-- ================================================================================
-- PERSISTENCE IS NAMESPACED
-- ================================================================================
-- §5.1 on Persist: "Namespaced save state. Sandboxed to `scripts_data/`; no `io` table in-game."
-- Each plugin's values are stored under its own id, so one plugin cannot read or clobber another's
-- settings, and an uninstalled plugin's values do not leak into whatever takes its id later.

local Config = {}
Config.__index = Config

--- Every allocated menu ID carries this prefix, so a collision with a THIRD-PARTY plugin's element
--- requires that plugin to have chosen a `sentinel_`-prefixed string on purpose.
Config.MENU_ID_PREFIX = "sentinel_"

---@param opts table|nil { persist = { load(ns) -> table, save(ns, table) } }
function Config:new(opts)
    opts = opts or {}
    local o = setmetatable({}, Config)
    o._persist = opts.persist
    o._schemas = {}    -- plugin_id -> { key -> entry }
    o._values = {}     -- plugin_id -> { key -> value }
    o._menu_ids = {}   -- allocated id -> "plugin_id/key"
    return o
end

---Register a validated manifest's config block.
---@param plugin_id string
---@param entries table the manifest's `config` array
function Config:declare(plugin_id, entries)
    self._schemas[plugin_id] = self._schemas[plugin_id] or {}
    self._values[plugin_id] = self._values[plugin_id] or {}

    for _, entry in ipairs(entries or {}) do
        self._schemas[plugin_id][entry.key] = entry
        if self._values[plugin_id][entry.key] == nil then
            self._values[plugin_id][entry.key] = entry.default
        end
    end

    -- Values persisted from a previous session override defaults, but only where they still
    -- validate: a stored value whose schema changed shape must not resurrect as a type error.
    if self._persist then
        local ok, stored = pcall(function() return self._persist.load(plugin_id) end)
        if ok and type(stored) == "table" then
            for key, value in pairs(stored) do
                if self:_validate(plugin_id, key, value) then
                    self._values[plugin_id][key] = value
                end
            end
        end
    end
    return true
end

function Config:_validate(plugin_id, key, value)
    local schema = self._schemas[plugin_id]
    if schema == nil then return false, "plugin_not_declared" end
    local entry = schema[key]
    if entry == nil then return false, "unknown_key:" .. tostring(key) end

    if entry.type == "bool" then
        if type(value) ~= "boolean" then return false, "type_mismatch:" .. key end
    elseif entry.type == "int" then
        if type(value) ~= "number" or value ~= math.floor(value) then
            return false, "type_mismatch:" .. key
        end
    elseif entry.type == "float" then
        if type(value) ~= "number" then return false, "type_mismatch:" .. key end
    elseif entry.type == "string" then
        if type(value) ~= "string" then return false, "type_mismatch:" .. key end
    elseif entry.type == "enum" then
        if type(value) ~= "string" then return false, "type_mismatch:" .. key end
        local found = false
        for _, v in ipairs(entry.values or {}) do
            if v == value then found = true break end
        end
        if not found then return false, "not_in_enum:" .. key end
    else
        return false, "unknown_type:" .. tostring(entry.type)
    end

    if entry.min ~= nil and type(value) == "number" and value < entry.min then
        return false, "below_min:" .. key
    end
    if entry.max ~= nil and type(value) == "number" and value > entry.max then
        return false, "above_max:" .. key
    end
    return true
end

---@return any value, or `default_if_missing` when the key was never declared
function Config:get(plugin_id, key, default_if_missing)
    local values = self._values[plugin_id]
    if values == nil then return default_if_missing end
    local value = values[key]
    if value == nil then return default_if_missing end
    return value
end

---@return boolean ok, string|nil reason
function Config:set(plugin_id, key, value)
    local ok, reason = self:_validate(plugin_id, key, value)
    if not ok then return false, reason end
    self._values[plugin_id][key] = value
    return true
end

---@return table|nil { key -> entry }
function Config:schema(plugin_id)
    return self._schemas[plugin_id]
end

---Allocate a globally unique menu-element ID.
---
---Deterministic in `(plugin_id, key)` so the same element gets the same ID across reloads -- a
---menu ID that changed per session would lose whatever the injector keyed to it.
---@return string|nil id, string|nil reason
function Config:allocate_menu_id(plugin_id, key)
    if type(plugin_id) ~= "string" or plugin_id == "" then return nil, "missing_plugin_id" end
    if type(key) ~= "string" or key == "" then return nil, "missing_key" end

    local owner = plugin_id .. "/" .. key
    -- Non-alphanumerics are folded out: the ID crosses into the injector's global namespace and
    -- there is no documented character set for it.
    local id = (Config.MENU_ID_PREFIX .. plugin_id .. "_" .. key):gsub("[^%w_]", "_")

    local existing = self._menu_ids[id]
    if existing ~= nil then
        if existing == owner then
            return id -- idempotent for the same owner
        end
        return nil, "menu_id_collision:" .. id
    end
    self._menu_ids[id] = owner
    return id
end

function Config:menu_id_owner(id)
    return self._menu_ids[id]
end

---Persist every plugin's values under its own namespace.
function Config:save()
    if not self._persist then return false, "no_persist_backend" end
    local saved = 0
    for plugin_id, values in pairs(self._values) do
        local ok = pcall(function() self._persist.save(plugin_id, values) end)
        if ok then saved = saved + 1 end
    end
    return true, saved
end

return Config
