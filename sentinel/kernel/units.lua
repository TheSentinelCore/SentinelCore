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
--
-- ================================================================================
-- THE GENERATION-STAMPED UnitRef (Phase 4d D5)
-- ================================================================================
-- `hostiles_within` hands back HANDLES, and a handle cannot ride in an intent payload (§2.7). The
-- escape hatch Phase 4c opened was the guid: a guid is a VALUE, so it may travel, and the commit
-- stage resolves it back to a handle in the tick that uses it.
--
-- THAT VALUE HAS NO EXPIRY, AND THAT WAS THE HOLE. A plugin could cache a guid in tick N and submit
-- it in tick N+5, and everything said yes. The LEASE generation cannot catch it: a lease
-- legitimately spans many ticks (its TTL is counted in ticks), so an intent submitted five ticks
-- after the grant is exactly what a lease is FOR. The guid needs its own, much shorter, expiry.
--
-- So `mint_ref` stamps the guid with the tick index of the frozen snapshot the caller is reasoning
-- against, and `resolve_cast_destination` re-checks that stamp against the snapshot COMMIT is
-- running under. A ref minted in tick N is refused in tick N+1.
--
-- WHY THE SNAPSHOT IS AN ARGUMENT RATHER THAN A CONSTRUCTOR DEPENDENCY. `runtime/app.lua` builds
-- `Units` before it builds the `Scheduler`, so there is no tick source to inject at construction
-- time; and the snapshot is the one object a rotation is already required to be holding. Handing it
-- in is not "the caller applying the stamp" -- the caller supplies a kernel-frozen object and the
-- KERNEL reads the number off it. A caller that hands over an OLD snapshot does not forge a fresh
-- stamp, it gets an OLD one, which commit then refuses. The bypass is self-defeating.
--
-- ================================================================================
-- WHAT THE STAMP CANNOT SEE
-- ================================================================================
-- It proves ONE thing: the ref was minted during the tick that is committing it. Everything else a
-- reader might hope it covers, it does not:
--
--   * IT DOES NOT PROVE THE UNIT STILL EXISTS. The mob can die between ACT and COMMIT inside the
--     same tick. `get_object_from_guid` returning nil is a SEPARATE refusal (`unit_unresolved`)
--     and remains the only thing that speaks to existence.
--   * IT DOES NOT PROVE THE UNIT IS IN RANGE OR IN FRONT OF YOU. That is the castable gate's job,
--     asked of the SDK, and it runs after this.
--   * IT DOES NOT PROVE THE UNIT IS THE SAME ENTITY THE ROTATION REASONED ABOUT. A guid is stable;
--     the world is not. The add can be feared, phased, mind-controlled or CC'd between the mint and
--     the commit, and the ref still reads as fresh -- because it IS fresh. Freshness is not
--     identity of circumstance.
--   * IT SAYS NOTHING ABOUT AUTHORITY. That is the lease generation, checked separately at commit.
--     A perfectly fresh ref submitted under a revoked lease is still refused, by that check.

local Geometry = require("core/geometry")

local Units = {}
Units.__index = Units

--- The payload fields a minted ref occupies. FLAT SCALARS, and the names live here so the mint site
--- and the commit-time re-check cannot drift apart.
---
--- DELIBERATELY NOT ONE NESTED `{ guid, generation }` TABLE. `IntentQueue:dedupe_key` flattens
--- exactly one level with `tostring(payload[k])`, so a nested table would key on its ADDRESS: two
--- refs naming the SAME unit would dedupe as distinct (two packets), and the same ref submitted
--- twice would not dedupe at all. Two scalars is not a style choice, it is what makes dedupe work.
Units.REF_GUID_FIELD = "unit_guid"
Units.REF_TICK_FIELD = "unit_ref_tick"

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

-- ---------------------------------------------------------------------------
-- The generation-stamped UnitRef
-- ---------------------------------------------------------------------------

---The generation a snapshot represents, or nil when it cannot say.
---
---A MODULE function rather than a method, and shared with `kernel/intent_executors.lua`, because
---the mint and the commit-time re-check must read the tick the SAME way. Two readings is how a
---stamp and its check drift into always-equal or never-equal.
---
---Returns nil rather than 0 for a snapshot that cannot answer. Zero is a REAL tick index (an empty
---snapshot before tick 1 carries it), so collapsing "cannot say" onto it would make an unanswerable
---snapshot compare equal to a ref minted at boot.
---@param snapshot table|nil a frozen snapshot (kernel/snapshot.lua)
---@return number|nil
function Units.generation_of(snapshot)
    if type(snapshot) ~= "table" then return nil end
    if type(snapshot.tick_index) ~= "function" then return nil end
    local ok, tick = pcall(snapshot.tick_index, snapshot)
    if not ok or type(tick) ~= "number" then return nil end
    return tick
end

---Mint a generation-stamped reference to an arbitrary unit.
---
---THE KERNEL MINTS, THE CALLER CARRIES. The two scalars returned here are the only sanctioned way
---to name a unit that the closed symbolic vocabulary ("player", "target", "pet") cannot -- the
---secondary enemy Polymorph picks, the low-health add Fire Blast finishes. A caller that builds
---`{ unit_guid = ... }` by hand instead is refused at commit as `unstamped_unit_ref`: an omittable
---stamp is a stamp nobody enforces, so it is not optional.
---
---Two RETURN VALUES, not a table, and that shape is load-bearing -- see `REF_TICK_FIELD` above. It
---also makes the nesting mistake impossible rather than merely discouraged: a caller that writes
---`payload.ref = units:mint_ref(...)` captures the guid alone, loses the stamp, and is refused.
---
---Mints NOTHING when the handle cannot name itself or the snapshot cannot name the tick. A
---half-formed ref -- a stamp with a nil guid -- would be refused one stage later as
---`no_cast_destination`, which blames the payload shape for a failure that happened here.
---@param snapshot table this tick's frozen snapshot
---@param unit table a live handle
---@return string|number|nil guid, number|nil generation
function Units:mint_ref(snapshot, unit)
    if unit == nil then return nil end
    local tick = Units.generation_of(snapshot)
    if tick == nil then return nil end
    if type(unit.get_guid) ~= "function" then return nil end
    local ok, guid = pcall(unit.get_guid, unit)
    if not ok or guid == nil then return nil end
    return guid, tick
end

return Units
