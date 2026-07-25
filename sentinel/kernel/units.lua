-- kernel/units.lua
-- `Sentinel.units` -- unit access for plugins (ADR 08 §10).
--
-- ================================================================================
-- WHY THIS EXISTS SEPARATELY FROM THE SNAPSHOT
-- ================================================================================
-- §2.7: the frozen snapshot holds VALUES, not handles. That is the right call for everything a
-- rotation READS -- `target.health_pct` is a number, consistent for the whole tick, and cannot go
-- stale mid-evaluation.
--
-- But a plugin sometimes needs the HANDLE itself: to hand to an SDK call, or to ask a question the
-- snapshot did not pre-capture. §13 risk 2 names this exact tension -- "under-capture forces a
-- mid-tick live read, which reintroduces exactly the inconsistency the snapshot exists to prevent".
--
-- So the rule this file encodes: READ THROUGH THE SNAPSHOT, RESOLVE THROUGH HERE. Handles obtained
-- here are for passing onward, not for reading values that the snapshot already froze. Every
-- accessor is guarded and returns nil rather than a dead pointer, because §2.7's other lesson is
-- that a handle can die between two reads in the same tick.
--
-- The Phase 4 frost port needed exactly one thing beyond player/target: `hostiles_within`, which
-- `shared/aoe_helper.lua` was providing to the combat module privately. It is general -- every
-- rotation with an AoE branch needs it -- so it is kernel rather than plugin-local.

local Geometry = require("core/geometry")

local Units = {}
Units.__index = Units

---@param opts table|nil { object_manager? } -- injected in tests, live SDK otherwise
function Units:new(opts)
    opts = opts or {}
    local o = setmetatable({}, Units)
    o._om = opts.object_manager
    return o
end

function Units:_object_manager()
    if self._om then return self._om end
    return core and core.object_manager or nil
end

local function alive(handle)
    if handle == nil then return false end
    if type(handle.is_valid) == "function" then
        local ok, valid = pcall(handle.is_valid, handle)
        if ok and valid == false then return false end
    end
    return true
end

---@return table|nil the local player handle
function Units:player()
    local om = self:_object_manager()
    if not om or type(om.get_local_player) ~= "function" then return nil end
    local ok, player = pcall(om.get_local_player)
    if not ok or not alive(player) then return nil end
    return player
end

---@return table|nil the player's current target
function Units:target()
    local player = self:player()
    if not player or type(player.get_target) ~= "function" then return nil end
    local ok, target = pcall(player.get_target, player)
    if not ok or not alive(target) then return nil end
    return target
end

---Hostile units within `range` yards of the player.
---
---`get_all_objects()` is documented as expensive per-frame and `get_visible_objects()` is not
---implemented (§2.7), so this is a WARM-tier read: call it once per tick and reuse the answer, never
---once per condition. A rotation with fifteen AoE predicates calling this fifteen times is the
---O(n x m) scan the snapshot exists to prevent.
---@param range number yards
---@return table list of handles, nearest first
function Units:hostiles_within(range)
    local out = {}
    local player = self:player()
    if not player then return out end

    local om = self:_object_manager()
    if not om or type(om.get_all_objects) ~= "function" then return out end
    local ok, objects = pcall(om.get_all_objects)
    if not ok or type(objects) ~= "table" then return out end

    local ok_pos, origin = pcall(player.get_position, player)
    if not ok_pos or type(origin) ~= "table" then return out end

    local limit = tonumber(range) or 0
    for _, handle in ipairs(objects) do
        if alive(handle) and handle ~= player then
            local enemy_ok, is_enemy = pcall(function()
                return type(handle.is_enemy) == "function" and handle:is_enemy()
            end)
            local dead_ok, is_dead = pcall(function()
                return type(handle.is_dead) == "function" and handle:is_dead()
            end)
            if enemy_ok and is_enemy and (not dead_ok or not is_dead) then
                local p_ok, position = pcall(handle.get_position, handle)
                if p_ok then
                    -- Geometry.distance is nil-safe and returns infinity rather than erroring,
                    -- which is why it is used here instead of an inline distance_3d.
                    local distance = Geometry.distance(origin, position)
                    if distance <= limit then
                        out[#out + 1] = { handle = handle, distance = distance }
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b) return a.distance < b.distance end)
    local handles = {}
    for i, entry in ipairs(out) do handles[i] = entry.handle end
    return handles
end

---How many hostiles are within `range`. The common case, so it does not force callers to build and
---discard a list.
function Units:hostile_count_within(range)
    return #self:hostiles_within(range)
end

return Units
