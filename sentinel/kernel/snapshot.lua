-- kernel/snapshot.lua
-- The per-tick frozen world view. Sense once, read many, VALUES ONLY.
--
-- ================================================================================
-- WHY THIS CANNOT STORE HANDLES (ADR 08 §2.7)
-- ================================================================================
-- "Every game_object is a raw 8-byte pointer into game memory that can become invalid
--  BETWEEN USES, and the docs say to guard before EVERY use, not just at acquisition. A
--  'snapshot frozen for the tick' that stores game_object references is therefore unsound
--  -- the pointer can die inside the tick that froze it."
--
-- A comment saying "please only store values" is not a mechanism. So `put` REFUSES
-- anything that carries behaviour: userdata, functions, threads, or any table containing
-- one at any depth -- which is what every handle looks like. Accepted tables are
-- deep-copied, so the snapshot owns its data and no later mutation of the source can
-- reach it.
--
-- ================================================================================
-- WHY IT SUPERSEDES Blackboard:snapshot(prefix)
-- ================================================================================
-- ADR 08 §5.1 flags `core/blackboard.lua`'s `snapshot(prefix)` as having ZERO CALLERS.
-- It was not extended, it was replaced, for a reason beyond dead code: it returned a
-- shallow copy of live blackboard state, and the blackboard holds `player.object` -- a raw
-- handle written by runtime/sensors/player_sensor.lua. It therefore produced exactly the
-- unsound artefact §2.7 forbids, under a name that invited trust. Leaving it in place next
-- to this file would be a trap, so it was deleted.
--
-- ================================================================================
-- WHAT THIS DELIBERATELY DOES NOT DO
-- ================================================================================
-- Deep copy on `put` prevents the SOURCE from mutating captured data. It does not stop a
-- consumer from mutating a table it got back from `get` -- LuaJIT's `__newindex` fires
-- only for absent keys, so an existing-field overwrite cannot be intercepted without a
-- proxy that breaks `pairs()` on 5.1. Sealing the read side belongs with the public API
-- wrapper in Phase 3; this file does not pretend to have done it.

local Snapshot = {}

local MAX_DEPTH = 8

-- ---------------------------------------------------------------------------
-- Value validation + deep copy
-- ---------------------------------------------------------------------------

--- Copy a plain-data value, refusing anything that carries behaviour.
--- @return any copy
--- @error string when the value is not pure data
local function copy_value(value, key, depth, seen)
    local t = type(value)

    if t == "nil" or t == "number" or t == "string" or t == "boolean" then
        return value
    end

    if t == "function" or t == "userdata" or t == "thread" then
        error(string.format(
            "snapshot refused key '%s': a %s carries behaviour, and the snapshot stores VALUES only "
            .. "(ADR 08 §2.7 -- a game_object pointer can die inside the tick that froze it)",
            tostring(key), t), 0)
    end

    if t ~= "table" then
        error(string.format("snapshot refused key '%s': unsupported type '%s'", tostring(key), t), 0)
    end

    if depth > MAX_DEPTH then
        error(string.format("snapshot refused key '%s': nested deeper than %d levels",
            tostring(key), MAX_DEPTH), 0)
    end

    if seen[value] then
        error(string.format("snapshot refused key '%s': the value contains a cycle", tostring(key)), 0)
    end
    seen[value] = true

    local out = {}
    for k, v in pairs(value) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then
            error(string.format("snapshot refused key '%s': table key of type '%s' is not a value",
                tostring(key), kt), 0)
        end
        out[k] = copy_value(v, key, depth + 1, seen)
    end

    seen[value] = nil
    return out
end

-- ---------------------------------------------------------------------------
-- Frozen snapshot
-- ---------------------------------------------------------------------------

local Frozen = {}
Frozen.__index = Frozen
Frozen.__newindex = function(_, k)
    error("snapshot is frozen: cannot assign field '" .. tostring(k) .. "'", 2)
end

function Frozen:get(key, default)
    local value = self._data[key]
    if value == nil then return default end
    return value
end

function Frozen:has(key)
    return self._data[key] ~= nil
end

function Frozen:keys()
    local out = {}
    for k in pairs(self._data) do out[#out + 1] = k end
    return out
end

function Frozen:tick_index()
    return self._tick_index
end

function Frozen:is_frozen()
    return true
end

-- ---------------------------------------------------------------------------
-- Builder
-- ---------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

---Capture one extracted value.
---@param key string
---@param value any Pure data only -- scalars, or tables of scalars.
function Builder:put(key, value)
    if self._frozen then
        error("snapshot is frozen: cannot put '" .. tostring(key) .. "' after freeze()", 0)
    end
    if type(key) ~= "string" or key == "" then
        error("snapshot key must be a non-empty string, got " .. type(key), 0)
    end
    self._data[key] = copy_value(value, key, 0, {})
    return self
end

--- Readable while filling, so a later sensor in the same SENSE stage can build on an
--- earlier one without going back to a live handle.
function Builder:get(key, default)
    local value = self._data[key]
    if value == nil then return default end
    return value
end

function Builder:has(key)
    return self._data[key] ~= nil
end

function Builder:is_frozen()
    return self._frozen == true
end

---Seal the snapshot for the rest of the tick.
---@return table frozen snapshot
function Builder:freeze()
    self._frozen = true
    local frozen = setmetatable({}, Frozen)
    rawset(frozen, "_data", self._data)
    rawset(frozen, "_tick_index", self._tick_index)
    return frozen
end

---@param opts table|nil { tick_index }
function Snapshot.builder(opts)
    opts = opts or {}
    return setmetatable({
        _data = {},
        _frozen = false,
        _tick_index = opts.tick_index or 0,
    }, Builder)
end

---An empty frozen snapshot. Handed to consumers on a tick where SENSE produced nothing,
---so downstream code never has to nil-check the snapshot itself.
function Snapshot.empty(tick_index)
    return Snapshot.builder({ tick_index = tick_index }):freeze()
end

return Snapshot
