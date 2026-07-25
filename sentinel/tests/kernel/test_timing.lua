-- tests/kernel/test_timing.lua
-- The Timing service, and specifically `gcd_remaining_est` (ADR 08 §2.5, §10).
--
-- §2.5: "Remaining GCD is not readable. Only `core.spell_book.get_global_cooldown()` exists, and it
-- returns the GCD DURATION, not the remainder. The kernel must derive the remainder itself by
-- timestamping its own casts."
--
-- §13 risk 3 calls Timing "the highest-bug-density service ... two incompatible clocks, one API
-- mixing units inside a single return value, and a GCD remainder that must be inferred. It needs
-- disproportionate test coverage." Hence the size of this file.
--
-- THE CLOCK RULE, which most of these tests exist to enforce:
--   core.time()      -> SECONDS since injection
--   core.game_time() -> MILLISECONDS since game start
-- Every server-derived timestamp is on the game_time ms axis only. Timing touches that axis and
-- nothing else -- `test_the_seconds_clock_is_never_consulted` makes that mechanical rather than
-- aspirational.

local Timing = require("kernel/timing")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

--- Install a `core` whose `game_time` the test drives by hand, and whose `time` EXPLODES. Any
--- accidental read of the seconds clock therefore fails loudly here rather than producing a
--- 1000x-wrong GCD in the game.
local function with_core(gcd_seconds, fn)
    local saved = _G.core
    local clock = { ms = 0 }
    _G.core = {
        game_time = function() return clock.ms end,
        time = function()
            error("clock mixing: core.time() is SECONDS since injection and must never reach Timing")
        end,
        spell_book = gcd_seconds ~= nil
            and { get_global_cooldown = function() return gcd_seconds end }
            or {},
    }
    local ok, err = pcall(fn, clock)
    _G.core = saved
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- Duration
-- ---------------------------------------------------------------------------

--- `get_global_cooldown()` is documented to return SECONDS (docs/SylvannasAPI spellbook.md). Timing
--- works in ms throughout, so the boundary conversion happens exactly once, here.
function M.test_gcd_duration_converts_the_documented_seconds_return_to_ms()
    with_core(1.5, function()
        T.assert_equal(Timing:new():gcd_duration_ms(), 1500)
    end)
end

function M.test_gcd_duration_falls_back_when_the_api_is_absent()
    with_core(nil, function()
        T.assert_equal(Timing:new():gcd_duration_ms(), Timing.DEFAULT_GCD_MS,
            "an absent API must not yield a zero-length GCD, which would gate nothing")
    end)
end

--- A zero or negative return is the injector telling us nothing useful. Trusting it would open the
--- floodgates: a 0ms GCD makes every gate pass.
function M.test_a_nonsense_duration_falls_back_rather_than_disabling_the_gate()
    with_core(0, function()
        T.assert_equal(Timing:new():gcd_duration_ms(), Timing.DEFAULT_GCD_MS)
    end)
    with_core(-1, function()
        T.assert_equal(Timing:new():gcd_duration_ms(), Timing.DEFAULT_GCD_MS)
    end)
end

-- ---------------------------------------------------------------------------
-- The estimate
-- ---------------------------------------------------------------------------

function M.test_no_cast_means_no_remaining_gcd()
    with_core(1.5, function()
        local timing = Timing:new()
        T.assert_equal(timing:gcd_remaining_est(), 0)
        T.assert_true(timing:is_gcd_ready())
    end)
end

function M.test_the_estimate_decays_across_the_window_and_clamps_at_zero()
    with_core(1.5, function(clock)
        local timing = Timing:new()
        clock.ms = 10000
        timing:note_cast(133) -- Fireball

        T.assert_equal(timing:gcd_remaining_est(), 1500, "the full window opens at the cast")
        T.assert_false(timing:is_gcd_ready())

        clock.ms = 10600
        T.assert_equal(timing:gcd_remaining_est(), 900)
        T.assert_false(timing:is_gcd_ready())

        clock.ms = 11500
        T.assert_equal(timing:gcd_remaining_est(), 0, "exactly at the boundary the GCD is done")
        T.assert_true(timing:is_gcd_ready())

        clock.ms = 99999
        T.assert_equal(timing:gcd_remaining_est(), 0, "and it never goes negative")
    end)
end

--- Off-GCD abilities exist and must not open a window. Ice Block is the case that matters for the
--- frost port: gating it behind a GCD it does not use would make the panic button unreachable.
function M.test_an_off_gcd_cast_does_not_open_a_window()
    with_core(1.5, function(clock)
        local timing = Timing:new({ is_gcd_spell = function(id) return id ~= 45438 end })
        clock.ms = 5000
        timing:note_cast(45438) -- Ice Block
        T.assert_equal(timing:gcd_remaining_est(), 0)
        T.assert_true(timing:is_gcd_ready())
    end)
end

--- Casting again mid-window restarts the window from the NEW cast, not from the old one. Anything
--- else lets a second cast shorten the gate that is supposed to be blocking it.
function M.test_a_second_cast_restarts_the_window_from_the_later_timestamp()
    with_core(1.5, function(clock)
        local timing = Timing:new()
        clock.ms = 1000
        timing:note_cast(133)
        clock.ms = 1900
        timing:note_cast(116)
        T.assert_equal(timing:gcd_remaining_est(), 1500)
        clock.ms = 3400
        T.assert_equal(timing:gcd_remaining_est(), 0)
    end)
end

--- An explicit timestamp is on the SAME axis as the implicit one. This is the seam where a caller
--- could hand in `core.time()` seconds by mistake, so it is pinned.
function M.test_an_explicit_timestamp_is_on_the_game_time_axis()
    with_core(1.5, function(clock)
        local timing = Timing:new()
        clock.ms = 8000
        timing:note_cast(133, 7500) -- recorded as having happened 500ms ago
        T.assert_equal(timing:gcd_remaining_est(), 1000)
    end)
end

-- ---------------------------------------------------------------------------
-- The clock rule
-- ---------------------------------------------------------------------------

--- The harness makes `core.time()` throw. If any path in Timing reaches for the seconds clock, this
--- test is where it surfaces -- rather than in-game as a GCD that is wrong by a factor of 1000.
function M.test_the_seconds_clock_is_never_consulted()
    with_core(1.5, function(clock)
        local timing = Timing:new()
        clock.ms = 4000
        timing:note_cast(133)
        timing:gcd_duration_ms()
        timing:gcd_remaining_est()
        timing:is_gcd_ready()
        timing:last_cast_ms()
        -- Reaching here at all is the assertion: none of the above touched core.time().
        T.assert_equal(timing:last_cast_ms(), 4000)
    end)
end

--- The whole point of the service, stated as the failure it prevents: a rotation that asks "may I
--- cast?" every tick must be told NO for the whole window, not just on the tick it cast.
function M.test_a_rotation_polling_every_tick_is_refused_for_the_whole_window()
    with_core(1.5, function(clock)
        local timing = Timing:new()
        clock.ms = 0
        timing:note_cast(133)

        local allowed = 0
        for tick = 1, 30 do
            clock.ms = tick * 75 -- the 75ms rotation cadence the profiles are authored against
            if timing:is_gcd_ready() then allowed = allowed + 1 end
        end
        -- 1500ms window / 75ms tick = ready from tick 20 onward, i.e. 11 of 30 polls.
        T.assert_equal(allowed, 11, "the GCD must hold for its full duration, not one tick")
    end)
end

return M
