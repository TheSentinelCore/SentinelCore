-- kernel/timing.lua
-- GCD state, derived rather than read (ADR 08 §2.5, §5.1, §10).
--
-- ================================================================================
-- WHY THIS SERVICE EXISTS AT ALL
-- ================================================================================
-- ADR-000 specified `Sentinel.timing:gcd_remaining()`. It is not implementable: the injector exposes
-- `core.spell_book.get_global_cooldown()`, which returns the GCD's DURATION, and nothing that
-- returns its remainder. §2.5's conclusion: "The kernel must derive the remainder itself by
-- timestamping its own casts."
--
-- Hence the name on the public surface -- `gcd_remaining_est`. It is an ESTIMATE, and calling it
-- anything else would invite callers to trust it as an observation. It is exact for casts the kernel
-- committed and blind to casts it did not, which is the honest description: a player pressing a key
-- manually, or another Sylvanas plugin casting, opens a GCD this service cannot see.
--
-- ================================================================================
-- THE CLOCK RULE -- THE SINGLE MOST DANGEROUS THING IN THIS FILE
-- ================================================================================
--   core.time()      -> SECONDS since injection      (float)
--   core.game_time() -> MILLISECONDS since game start (integer)
-- They are not comparable and never convertible into each other. Every server-derived timestamp --
-- buff expiry, cast end, cooldown start -- is on the game_time ms axis ONLY.
--
-- THIS FILE TOUCHES `core.game_time()` AND NOTHING ELSE. Mixing them yields a value wrong by a
-- factor of 1000 in the direction that makes every gate pass, so the failure is a rotation that
-- casts continuously rather than one that visibly stalls. `test_the_seconds_clock_is_never_consulted`
-- makes `core.time()` throw for the duration of the test, so a regression fails offline.
--
-- ================================================================================
-- THE UNIT TRAP AT THE BOUNDARY
-- ================================================================================
-- `get_global_cooldown()` is documented to return SECONDS; this file works in ms. The conversion
-- happens exactly once, in `gcd_duration_ms`, and nowhere else.
--
-- The adjacent API is worse and is deliberately NOT used here: §2.5 notes that
-- `get_spell_cooldown_information` mixes units inside one return value -- `start_time` on the
-- game_time ms axis, `duration` documented in seconds. The vendor's own doc example then computes
-- `(start_time + duration) - core.game_time()`, adding seconds to milliseconds. Anything in this
-- kernel that eventually needs per-spell cooldowns must normalise at that boundary, not trust it.

local Timing = {}
Timing.__index = Timing

--- Used when the injector tells us nothing usable. 1500ms is the TBC GCD for the caster classes this
--- targets, and matches what `modules/combat/cooldown_tracker.lua` hardcoded before this service
--- existed. A fallback of 0 would be far worse than a wrong-but-plausible number: it would make the
--- GCD gate pass unconditionally, which is indistinguishable from having no gate.
Timing.DEFAULT_GCD_MS = 1500

---@param opts table|nil { now_ms = function|nil, is_gcd_spell = function|nil }
function Timing:new(opts)
    opts = opts or {}
    local o = setmetatable({}, Timing)
    o._now_ms_override = opts.now_ms
    -- Default: everything is on the GCD. That is the safe direction -- over-gating delays a cast by
    -- one window, under-gating double-casts. Callers that know better (Ice Block, Frost Nova's
    -- off-GCD siblings) pass a predicate.
    o._is_gcd_spell = opts.is_gcd_spell
    o._gcd_until_ms = 0
    o._last_cast_ms = nil
    o._last_cast_spell_id = nil
    return o
end

-- ---------------------------------------------------------------------------
-- The clock
-- ---------------------------------------------------------------------------

---Milliseconds on the game_time axis. The ONLY clock read in this file.
function Timing:now_ms()
    if self._now_ms_override then return self._now_ms_override() end
    if core and core.game_time then
        local ok, value = pcall(core.game_time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Duration
-- ---------------------------------------------------------------------------

---The GCD's length in milliseconds.
---
---Converts the documented SECONDS return exactly once. A missing API, a throwing API, or a
---non-positive answer all fall back rather than yielding a zero-length window.
function Timing:gcd_duration_ms()
    if core and core.spell_book and core.spell_book.get_global_cooldown then
        local ok, seconds = pcall(core.spell_book.get_global_cooldown)
        local value = ok and tonumber(seconds)
        if value and value > 0 then
            return value * 1000
        end
    end
    return Timing.DEFAULT_GCD_MS
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------

---Record a cast the kernel committed. Called from the IntentQueue's cast executor, which is the
---only place a cast can originate (ADR §3.2), so this sees every cast the kernel is responsible for.
---@param spell_id number
---@param at_ms number|nil game-time ms; defaults to now. NEVER seconds.
function Timing:note_cast(spell_id, at_ms)
    local id = tonumber(spell_id)
    if not id then return false end

    local now = tonumber(at_ms) or self:now_ms()
    self._last_cast_ms = now
    self._last_cast_spell_id = id

    if self._is_gcd_spell and not self._is_gcd_spell(id) then
        return false
    end

    -- Restart from THIS cast rather than extending the old window: taking the max of the two would
    -- let an earlier long window swallow a later cast, and taking the old one would let a second
    -- cast shorten the gate meant to be blocking it.
    self._gcd_until_ms = now + self:gcd_duration_ms()
    return true
end

function Timing:last_cast_ms()
    return self._last_cast_ms
end

function Timing:last_cast_spell_id()
    return self._last_cast_spell_id
end

-- ---------------------------------------------------------------------------
-- The estimate
-- ---------------------------------------------------------------------------

---Milliseconds of GCD left, clamped at 0. Never negative -- callers subtract from it.
function Timing:gcd_remaining_est()
    local remaining = self._gcd_until_ms - self:now_ms()
    if remaining <= 0 then return 0 end
    return remaining
end

function Timing:is_gcd_ready()
    return self:gcd_remaining_est() <= 0
end

return Timing
