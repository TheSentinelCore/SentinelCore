-- kernel/cond/init.lua
-- Condition predicates: frozen snapshot in, Truth out.
--
-- ================================================================================
-- WHAT THIS SET IS, AND WHAT IT IS NOT
-- ================================================================================
-- Seventeen predicates, out of the sixty-five in modules/combat/condition_library.lua.
-- They are a FIXTURE PROVING THE TYPE, not a usable rotation vocabulary. They were chosen
-- for coverage of TYPE BEHAVIOUR -- Unknown propagating through Kleene composition, policy
-- resolving at the call site, TreatTrue announcing itself, and Unknown arising from data
-- the snapshot genuinely does not carry -- and explicitly NOT for what a frost mage needs.
-- A set of seventeen predicates that all read `health_pct` would prove nothing.
--
-- The other forty-eight are not omitted for effort. They read data that does not exist
-- yet: auras, bags, the spellbook, cooldown ledgers, a pet tier, izi damage history.
-- kernel/snapshot_source.lua captures the HOT tier only -- `player.*` and `target.*` --
-- and inventing a live read for the rest would reintroduce the mid-tick inconsistency the
-- snapshot exists to prevent (ADR 08 §13 risk 2). The rejected list is the Phase 1b
-- worklist, not an apology.
--
-- ================================================================================
-- WHY EVERY RETURN IS A Truth
-- ================================================================================
-- ADR 07 §5.1.2. The old library answered "I could not read that" with `false` at least
-- eleven times -- condition_library.lua:103 returns false for "no target", which any
-- caller that negates it reads as "the target is fine". Those are different facts and a
-- boolean has no room for the difference. See kernel/truth.lua for why the type rather
-- than a convention, including the honest limit: Lua has no `__toboolean`, so
-- `if predicate() then` cannot be made to raise. What it CAN be made to do is be wrong
-- immediately and every time, rather than correct-looking until the one tick the data
-- goes unreadable.
--
-- ================================================================================
-- UNITS
-- ================================================================================
-- Symbolic refs only (UNIT_PLAYER / UNIT_TARGET / UNIT_PET), never a handle: §2.7's
-- pointer can die inside the tick that froze it, and a predicate holding one would be
-- exactly the unsound artefact the snapshot was built to remove. A ref resolves to a
-- snapshot key prefix and nothing else, so a predicate cannot reach past its unit.
--
-- All fraction comparisons go through kernel/cond/fraction.lua. There is no `/ 100` in
-- this file, and tests/kernel/test_cond.lua enforces that by scanning the tree.

local Fraction = require("kernel/cond/fraction")
local Geometry = require("core/geometry")
local Truth = require("kernel/truth")

local Cond = {}

--- Re-exported so a caller validating a threshold uses the module the predicates use,
--- rather than a second private copy of the pin that can drift from it.
Cond.FRACTION = Fraction

--- Declared, not derived. `bind` asserts the namespace it builds matches this number, so
--- an eighteenth predicate cannot arrive unmeasured -- and the test that counts them is
--- not comparing the implementation against itself.
Cond.PREDICATE_COUNT = 17

-- ---------------------------------------------------------------------------
-- Symbolic unit refs
-- ---------------------------------------------------------------------------

Cond.UNIT_PLAYER = "UNIT_PLAYER"
Cond.UNIT_TARGET = "UNIT_TARGET"
Cond.UNIT_PET = "UNIT_PET"

--- Ref -> snapshot key prefix.
---
--- UNIT_PET is deliberately present with NO sensor behind it. kernel/snapshot_source.lua
--- captures `player.*` (capture_player) and `target.*` (capture_unit on get_target); there
--- is no pet tier anywhere. So every pet predicate returns Unknown because the datum is
--- genuinely missing in the real system. That is the honest answer, and it gives the type
--- a case that a test fixture cannot manufacture.
local PREFIX = {
    UNIT_PLAYER = "player",
    UNIT_TARGET = "target",
    UNIT_PET = "pet",
}

local function prefix_for(ref, who)
    local prefix = PREFIX[ref]
    if prefix == nil then
        error(who .. " expects a symbolic unit ref (Cond.UNIT_PLAYER | UNIT_TARGET | "
            .. "UNIT_PET), got " .. tostring(ref)
            .. " -- predicates never take handles (ADR 08 §2.7)", 3)
    end
    return prefix
end

-- ---------------------------------------------------------------------------
-- Snapshot reads
-- ---------------------------------------------------------------------------

---Is this unit tier readable at all?
---
---Three cases, and the middle one is the whole reason for the tri-state:
---  key absent        -> the tier never ran. We do not know. Unknown.
---  available == false -> the sensor RAN and found no unit. That is a reading. False.
---  available == true  -> True.
local function availability(snapshot, ref, who)
    local available = snapshot:get(prefix_for(ref, who) .. ".available")
    if available == nil then return Truth.Unknown end
    return Truth.of(available == true)
end

---Read one field of a unit, or nil if it cannot be trusted.
---
---A field is only meaningful when the unit itself was readable: snapshot_source.lua:93-96
---sets `available = false` and writes NO other keys when a handle dies partway through
---capture, so reading a field off an unavailable unit would read a stale or absent value.
local function field(snapshot, ref, name, who)
    local prefix = prefix_for(ref, who)
    if snapshot:get(prefix .. ".available") ~= true then return nil end
    return snapshot:get(prefix .. "." .. name)
end

---Lift a snapshot field that is a nullable boolean. `nil` becomes Unknown, never False --
---ADR 08 §9.3, and the single mapping this whole type exists for.
local function boolean_field(snapshot, ref, name, who)
    local value = field(snapshot, ref, name, who)
    if type(value) ~= "boolean" then return Truth.Unknown end
    return Truth.of(value)
end

---Compare a fraction field against a fraction threshold.
---
---Both sides go through the boundary module: the threshold because `health_below(30)`
---would otherwise never gate, and the value because a sensor that switched to 0-100 would
---otherwise invert every gate silently. `compare` receives two numbers on the pin.
local function fraction_field(snapshot, ref, name, threshold, who, compare)
    Fraction.threshold(threshold, who)
    local value = Fraction.read(field(snapshot, ref, name, who))
    if value == nil then return Truth.Unknown end
    return Truth.of(compare(value, threshold))
end

local function strictly_below(value, threshold) return value < threshold end
local function strictly_above(value, threshold) return value > threshold end

---A count/level threshold. Explicitly NOT fraction-validated: levels run 1-70 and the
---0-1 pin applies to fractions, not to every number in the kernel. Applying the clamp
---indiscriminately is the mirror-image mistake of forgetting it.
local function integer_threshold(value, who)
    if type(value) ~= "number" or value ~= value or value < 1 or value ~= math.floor(value) then
        error(who .. " expects a positive integer level, got " .. tostring(value)
            .. " -- levels are a 1-70 scale, not a 0-1 fraction", 3)
    end
    return value
end

local function yards(value, who)
    if type(value) ~= "number" or value ~= value or value < 0 then
        error(who .. " expects a non-negative distance in yards, got " .. tostring(value)
            .. " -- yards are not a fraction", 3)
    end
    return value
end

local function readable_position(value)
    if type(value) ~= "table" then return nil end
    if type(value.x) ~= "number" or type(value.y) ~= "number" or type(value.z) ~= "number" then
        return nil
    end
    return value
end

-- ---------------------------------------------------------------------------
-- The bound namespace
-- ---------------------------------------------------------------------------

--- Raises on an unknown key rather than yielding nil. Without this, `cond.helth_below(0.3)`
--- fails as "attempt to call a nil value" at a site that says nothing about the typo, and
--- `local f = cond.helth_below` fails nowhere at all.
local Namespace = {}
Namespace.__index = function(_, key)
    error("kernel/cond has no predicate '" .. tostring(key)
        .. "' -- only " .. Cond.PREDICATE_COUNT .. " predicates are ported; the rest are "
        .. "blocked on warm/cold snapshot tiers (see the header of kernel/cond/init.lua)", 2)
end
Namespace.__newindex = function(_, key)
    error("kernel/cond is not extensible at runtime: cannot assign '" .. tostring(key)
        .. "'", 2)
end

---Bind the predicates to one tick's frozen snapshot.
---
---Bound per tick rather than taking a snapshot argument, so that a rotation physically
---cannot mix two ticks' data inside one decision: the snapshot is captured in the closure
---at the moment SENSE finished, and there is no parameter through which a stale one could
---be passed in.
---@param snapshot table A frozen snapshot (kernel/snapshot.lua)
---@return table predicates
function Cond.bind(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.get) ~= "function" then
        error("Cond.bind expects a frozen snapshot (kernel/snapshot.lua), got "
            .. type(snapshot), 2)
    end

    local P, T_, PET = Cond.UNIT_PLAYER, Cond.UNIT_TARGET, Cond.UNIT_PET

    local predicates = {
        -- --- Fractions: the pin, applied five times so it cannot be adjusted in one place
        health_below = function(threshold)
            return fraction_field(snapshot, P, "health_pct", threshold,
                "cond.health_below", strictly_below)
        end,
        health_above = function(threshold)
            return fraction_field(snapshot, P, "health_pct", threshold,
                "cond.health_above", strictly_above)
        end,
        power_below = function(threshold)
            return fraction_field(snapshot, P, "power_pct", threshold,
                "cond.power_below", strictly_below)
        end,
        -- The snapshot already stores a FRACTION (snapshot_source.lua:100). The library
        -- this replaces divided a live 0-100 read by 100 here
        -- (condition_library.lua:105); doing that again would make this fire only below
        -- 0.3% health.
        target_health_below = function(threshold)
            return fraction_field(snapshot, T_, "health_pct", threshold,
                "cond.target_health_below", strictly_below)
        end,
        target_health_above = function(threshold)
            return fraction_field(snapshot, T_, "health_pct", threshold,
                "cond.target_health_above", strictly_above)
        end,

        -- --- Availability: "known absent" and "could not look" are different answers
        has_target = function()
            return availability(snapshot, T_, "cond.has_target")
        end,
        unit_available = function(ref)
            return availability(snapshot, ref, "cond.unit_available")
        end,
        unit_health_below = function(ref, threshold)
            return fraction_field(snapshot, ref, "health_pct", threshold,
                "cond.unit_health_below", strictly_below)
        end,

        -- --- Nullable booleans: nil lifts to Unknown, never to False
        in_combat = function()
            return boolean_field(snapshot, P, "in_combat", "cond.in_combat")
        end,
        is_casting = function()
            return boolean_field(snapshot, P, "is_casting", "cond.is_casting")
        end,
        is_channeling = function()
            return boolean_field(snapshot, P, "is_channeling", "cond.is_channeling")
        end,
        is_moving = function()
            return boolean_field(snapshot, P, "is_moving", "cond.is_moving")
        end,
        is_dead = function()
            return boolean_field(snapshot, P, "is_dead", "cond.is_dead")
        end,

        -- --- Integers: proof the fraction pin is scoped to fractions
        level_at_least = function(level)
            integer_threshold(level, "cond.level_at_least")
            local value = field(snapshot, P, "level", "cond.level_at_least")
            if type(value) ~= "number" then return Truth.Unknown end
            return Truth.of(value >= level)
        end,
        target_level_at_least = function(level)
            integer_threshold(level, "cond.target_level_at_least")
            local value = field(snapshot, T_, "level", "cond.target_level_at_least")
            if type(value) ~= "number" then return Truth.Unknown end
            return Truth.of(value >= level)
        end,

        -- --- Enum equality, against the NORMALIZED name. `get_class()` returns a numeric
        -- id and ClassIs compares Title-Case; snapshot_source.lua:108 normalizes at
        -- capture so this predicate never sees the raw id.
        class_is = function(name)
            if type(name) ~= "string" then
                error("cond.class_is expects a Title-Case class name, got " .. type(name), 2)
            end
            local value = field(snapshot, P, "class", "cond.class_is")
            if type(value) ~= "string" then return Truth.Unknown end
            return Truth.of(value == name)
        end,

        -- --- Yards: a third scale, neither fraction nor percentage
        target_within = function(range)
            yards(range, "cond.target_within")
            local origin = readable_position(field(snapshot, P, "position", "cond.target_within"))
            local other = readable_position(field(snapshot, T_, "position", "cond.target_within"))
            if origin == nil or other == nil then return Truth.Unknown end
            -- Geometry.distance rather than an inlined distance_3d, per CLAUDE.md; the
            -- nil cases are already resolved to Unknown above, so its math.huge sentinel
            -- is unreachable from here.
            return Truth.of(Geometry.distance(origin, other) <= range)
        end,
    }

    local count = 0
    for _ in pairs(predicates) do count = count + 1 end
    if count ~= Cond.PREDICATE_COUNT then
        error(string.format(
            "kernel/cond built %d predicates but declares PREDICATE_COUNT = %d -- update "
            .. "the declaration deliberately, and say in the rejected list what the new "
            .. "one reads", count, Cond.PREDICATE_COUNT), 2)
    end

    -- `_ = PET` keeps the ref named here: it is the one unit with no sensor behind it, and
    -- a reader scanning this function should see that absence is intentional.
    local _ = PET

    return setmetatable(predicates, Namespace)
end

return Cond
