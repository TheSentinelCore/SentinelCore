-- tests/integrations/test_izi_bridge.lua
-- IziBridge must be CONSTRUCTIBLE OFFLINE.
--
-- ADR 08 §11.6: `SentinelApp:new()` and `initialize()` are provably untestable offline
-- because integrations/izi_bridge.lua did an UNGUARDED `require("common/izi_sdk")` -- an
-- injector-only module. tests/runtime/test_app_tick.lua documented that and hand-stubbed
-- the whole app around it, so the file encoding the kernel's boot contract was asserted
-- by nobody.
--
-- The fix is a guarded require plus nil-safe methods. The discipline that matters: an
-- absent SDK must degrade to a NAMED unavailable state, never to a plausible-looking
-- zero (ADR 08 §9.3) and never to a silent throw at construction time.

local IziBridge = require("integrations/izi_bridge")
local T = require("tests/test_util")

local M = {}

--- The whole point: no injector, no throw.
function M.test_constructs_without_the_injector_sdk()
    local ok, bridge = pcall(function() return IziBridge:new() end)
    T.assert_true(ok, "IziBridge:new() must not throw when common/izi_sdk is absent: " .. tostring(bridge))
    T.assert_not_nil(bridge, "IziBridge:new() must return an instance offline")
end

--- Unavailability is REPORTED, not inferred from a zero (ADR 08 §9.3).
function M.test_reports_unavailable_offline()
    local bridge = IziBridge:new()
    T.assert_false(bridge:is_available(), "no izi_sdk offline, so is_available() must be false")
    T.assert_nil(bridge:get_izi(), "get_izi() must be nil when the SDK never loaded")
end

--- Every accessor must be nil-safe. A missing SDK returns nil/false; it never throws,
--- because these are called from inside the tick and a throw there costs a frame.
function M.test_every_accessor_is_nil_safe_offline()
    local bridge = IziBridge:new()
    local fake_unit = {
        get_health = function() return 50 end,
        get_max_health = function() return 100 end,
    }

    local cases = {
        { "predict_hp_pct", function() return bridge:predict_hp_pct(fake_unit, 3) end },
        { "get_forecast", function() return bridge:get_forecast() end },
        { "get_time_to_die", function() return bridge:get_time_to_die(fake_unit) end },
        { "get_player", function() return bridge:get_player() end },
    }
    for _, case in ipairs(cases) do
        local ok, value = pcall(case[2])
        T.assert_true(ok, case[1] .. " must not throw offline: " .. tostring(value))
        T.assert_nil(value, case[1] .. " must return nil when the SDK is unavailable")
    end

    local ok_bg, is_bg = pcall(function() return bridge:is_battleground(0) end)
    T.assert_true(ok_bg, "is_battleground must not throw offline: " .. tostring(is_bg))
    T.assert_false(is_bg, "is_battleground must be false when the SDK is unavailable")
end

--- Nil units were already guarded; keep that behaviour pinned.
function M.test_nil_unit_is_still_guarded()
    local bridge = IziBridge:new()
    T.assert_nil(bridge:predict_hp_pct(nil, 3), "nil player yields nil prediction")
    T.assert_nil(bridge:get_time_to_die(nil), "nil unit yields nil ttd")
end

--- With an SDK present the bridge must actually USE it -- the guard must not turn into a
--- permanent no-op that silently disables IZI in-game (the LazyBot empty-catch failure mode,
--- ADR 08 §12). Injected here rather than required, since the real module is injector-only.
function M.test_uses_an_injected_sdk_when_one_is_available()
    local bridge = IziBridge:new({
        izi = {
            get_time_to_die_global = function(_self, _unit) return 4.25 end,
            get_player = function() return { name = "stub" } end,
            is_battleground = function(_self, map_id) return map_id == 30 end,
        },
        health_prediction = {
            get_incoming_damage = function(_self, _unit, _seconds) return 25 end,
        },
        combat_forecast = {
            get_forecast = function() return 1.5 end,
        },
    })

    T.assert_true(bridge:is_available(), "an injected SDK must report available")
    T.assert_equal(bridge:get_time_to_die({}), 4.25)
    T.assert_equal(bridge:get_forecast(), 1.5)
    T.assert_true(bridge:is_battleground(30))
    T.assert_false(bridge:is_battleground(0))
    T.assert_not_nil(bridge:get_player())

    -- (100 hp - 25 incoming) / 100 max = 0.75
    local unit = { get_health = function() return 100 end, get_max_health = function() return 100 end }
    T.assert_near(bridge:predict_hp_pct(unit, 3), 0.75, 0.0001)
end

return M
