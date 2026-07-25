-- kernel/cond/fraction.lua
-- THE UNIT BOUNDARY. The one place in kernel/cond that knows what "30%" means.
--
-- ================================================================================
-- THE PIN: 0-1, CHOSEN TO MATCH THE SNAPSHOT
-- ================================================================================
-- Predicates read the frozen snapshot, and the snapshot stores a ratio:
--
--     kernel/snapshot_source.lua:100   builder:put(prefix .. ".health_pct",
--                                        ratio(hp_ok, hp, hp_max_ok, hp_max))
--     kernel/snapshot_source.lua:55-60 ratio(...) -> current / max
--
-- So 0-1 is not a preference, it is the scale the data already arrives on. Any other
-- choice would put a conversion between the sensor and every single predicate.
--
-- ================================================================================
-- WHY THIS IS A MODULE AND NOT A COMMENT
-- ================================================================================
-- Three scales are live in this repo simultaneously (measured):
--
--   1. 0-1 fraction, snapshot     kernel/snapshot_source.lua:100
--   2. 0-1 fraction, blackboard   runtime/sensors/player_sensor.lua:22 normalizes
--                                 izi's 0-100 with `if value > 1 then value = value / 100 end`
--   3. 0-100 raw, live SDK        `get_health_percentage` returns 1-100. Divided by 100 at
--                                 modules/combat/condition_library.lua:105, NOT divided at
--                                 :468 (`time_to_die_below`), and multiplied back up at
--                                 modules/combat/pvp_target_selector.lua:215.
--
-- A port that carries the assertions across along with the code inherits whichever scale
-- the original happened to use, and every test still passes. The defect is invisible
-- because the test and the bug were copied from the same place.
--
-- So the conversion is not spread across the predicates. It is here, it is three
-- functions, and both directions of the mistake are made loud:
--
--   * `threshold` -- the CALL SITE mistake. `health_below(30)` raises. Under a 0-1 pin
--     it would otherwise be always-true: every real health_pct is <= 1 < 30, so the gate
--     would never gate, and a gate that never gates looks exactly like a gate.
--
--   * `read` -- the SENSOR mistake, which is the worse direction. If a sensor starts
--     writing 0-100 into `health_pct`, every threshold in the codebase remains a legal
--     fraction, so nothing raises and every gate silently inverts. A source value off the
--     pin is therefore UNREADABLE (nil), which the predicate above it turns into
--     Truth.Unknown -- ADR 08 §9.3's "unavailable is a value", applied to a scale error.
--
-- `from_percent` is the ONLY division by 100 permitted anywhere under kernel/cond.
-- tests/kernel/test_cond.lua enforces that by scanning the tree.

local Fraction = {}

--- The pin, as data. Asserted by test_the_pin_is_zero_to_one.
Fraction.MIN = 0
Fraction.MAX = 1

--- Float slack for the ceiling only. `hp / hp_max` is mathematically <= 1, but the
--- division can land a few ULPs above it; that is arithmetic noise, not a scale error.
--- Deliberately far too small to admit 1.01, let alone 30.
local EPSILON = 1e-9

-- ---------------------------------------------------------------------------
-- Call-site thresholds
-- ---------------------------------------------------------------------------

---Validate a caller-supplied threshold as a 0-1 fraction.
---
---Raises rather than coercing. A `tonumber`/clamp here would turn `health_below(30)`
---into `health_below(1)` -- still always-true, but now with the evidence destroyed.
---@param value any
---@param who string Predicate name, so the error names the site that must change.
---@return number the validated fraction
function Fraction.threshold(value, who)
    who = who or "a kernel/cond predicate"
    if type(value) ~= "number" then
        error(who .. " expects a 0-1 fraction threshold, got " .. type(value)
            .. " -- the kernel pin is 0-1 (see kernel/cond/fraction.lua)", 3)
    end
    if value ~= value then -- NaN: fails every comparison below, so it is caught by name
        error(who .. " expects a 0-1 fraction threshold, got NaN", 3)
    end
    if value < Fraction.MIN or value > Fraction.MAX + EPSILON then
        error(string.format(
            "%s expects a 0-1 fraction threshold, got %s -- did you mean %s? "
            .. "The kernel pin is 0-1, not 0-100, and %s would never gate",
            who, tostring(value), tostring(value / 100), tostring(value)), 3)
    end
    return value
end

-- ---------------------------------------------------------------------------
-- Snapshot source values
-- ---------------------------------------------------------------------------

---Read a snapshot value that is supposed to be on the pin.
---
---Returns nil -- meaning "could not read this", which the caller lifts to Truth.Unknown --
---for anything that is not a number on the pin. That includes a number on the WRONG pin:
---a 0-100 value arriving here is evidence the sensor changed scale, and the honest answer
---to "is 30 below 0.30" is not False, it is "I cannot tell".
---@param value any
---@return number|nil
function Fraction.read(value)
    if type(value) ~= "number" then return nil end
    if value ~= value then return nil end -- NaN is not a reading
    if value < Fraction.MIN or value > Fraction.MAX + EPSILON then return nil end
    return value
end

-- ---------------------------------------------------------------------------
-- The single conversion
-- ---------------------------------------------------------------------------

---Convert a 0-100 percentage onto the pin. THE ONLY `/ 100` under kernel/cond.
---
---Nothing in the kernel calls this today, because the snapshot already stores fractions.
---It exists so that when a warm/cold sensor does need to cross a raw
---`get_health_percentage` into the kernel, there is an obvious place to do it and a test
---that fails if it is done anywhere else.
---@param percent number 0-100
---@return number 0-1
function Fraction.from_percent(percent)
    if type(percent) ~= "number" or percent ~= percent then
        error("Fraction.from_percent expects a number 0-100, got " .. type(percent), 2)
    end
    if percent < 0 or percent > 100 then
        error("Fraction.from_percent expects a percentage in 0-100, got " .. tostring(percent), 2)
    end
    return percent / 100
end

return Fraction
