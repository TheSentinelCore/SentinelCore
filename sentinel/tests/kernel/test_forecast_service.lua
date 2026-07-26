-- tests/kernel/test_forecast_service.lua
-- PHASE 4D D1: the blackboard stops holding the IZI bridge, and the six readers that used to fetch
-- it from `module.combat.izi_bridge` read a published kernel service instead.
--
-- ================================================================================
-- WHY THESE PINS HAD TO BE WRITTEN BEFORE THE MIGRATION, NOT AFTER
-- ================================================================================
-- Every one of the six readers guarded with `if izi_bridge then` and fell through to a NON-forecast
-- fallback. So deleting the blackboard write first would have silently turned time-to-die,
-- incoming-damage and predicted-HP gating OFF -- and the whole suite would have stayed green,
-- because no test ever put a bridge on the blackboard in the first place. That is the same class of
-- silent failure this deliverable exists to end.
--
-- Each pin below therefore does three things in one test:
--   1. asserts the FALLBACK verdict with no forecast service published (the "off" answer),
--   2. asserts the BRIDGE-DERIVED verdict with the service published by the NEW route,
--   3. with NO `module.combat.izi_bridge` key on the blackboard at any point.
-- The two verdicts are deliberately OPPOSITE in every pin. A pin whose two branches agree proves
-- the reader ran, not that it read the forecast.
--
-- ================================================================================
-- WHAT THESE PINS CANNOT SEE
-- ================================================================================
--  1. THE REAL IZI SDK. Every forecast here is a hand-built double. `common/izi_sdk` and
--     `common/modules/{health_prediction,combat_forecast}` exist only inside the injector, so what
--     is pinned is the CONTRACT between reader and service, never that the injector answers it.
--     `tests/integrations/test_izi_bridge.lua` covers the adapter's own guarded-absence behaviour.
--  2. WHETHER THE APP ACTUALLY WIRES ONE. These build a surface directly from `Api.build`. That a
--     REAL boot puts a live forecast behind `Sentinel.forecast`, and that combat no longer builds a
--     second IziBridge, is pinned in `tests/integration/test_kernel_end_to_end.lua` -- against a
--     real `SentinelApp`, which is the only composition that can prove it.
--  3. PUBLICATION ORDER. `main.lua` calls `app:initialize()` BEFORE `publish_surface(app)`, so
--     `_G.Sentinel` is nil while combat initialises. Every reader therefore resolves the surface at
--     CALL time and these pins exercise call-time reads only. A reader that captured
--     `_G.Sentinel.forecast` at LOAD or INIT time would capture nil forever in production and still
--     pass here, because the test publishes before it calls.
--  4. THE OTHER IZI CONSUMERS. `TargetSelector`, `ContextBuilder` and the two target strategies
--     receive the bridge by CONSTRUCTOR and never touched the blackboard. They are untouched by
--     this migration and unmeasured by this file.

local Api = require("kernel/api")
local Forecast = require("kernel/forecast")
local Blackboard = require("core/blackboard")
local ConditionLibrary = require("modules/combat/condition_library")
-- Repointed by the Paladin kernel port: the profile moved to `rotations/paladin_retribution/`.
-- The pin below is UNCHANGED -- `target_execute` still asks `Sentinel.forecast:time_to_die` first
-- and falls back to a health read, and that is what this file measures. Only the path moved.
local RetCond = require("rotations/paladin_retribution/retribution_conditions")
local FrostCombatState = require("rotations/mage_frost/frost_combat_state")
local FrostCond = require("rotations/mage_frost/frost_conditions")
local T = require("tests/test_util")

local M = {}

local BRIDGE_KEY = "module.combat.izi_bridge"

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

--- A surface carrying nothing but the forecast service, published for the duration of `fn`.
---
--- Built through `Api.build` rather than by assigning a literal table to `_G.Sentinel`: the field is
--- a LIVE GETTER off the kernel table, and a literal would bypass the exact mechanism the migration
--- depends on.
local function with_forecast(forecast, fn)
    local saved = _G.Sentinel
    _G.Sentinel = Api.build({ forecast = forecast })
    local ok, err = pcall(fn)
    _G.Sentinel = saved
    if not ok then error(err, 0) end
end

--- No surface at all -- the pre-publication state, and the state every non-kernel test runs in.
local function without_surface(fn)
    local saved = _G.Sentinel
    _G.Sentinel = nil
    local ok, err = pcall(fn)
    _G.Sentinel = saved
    if not ok then error(err, 0) end
end

--- A forecast service double answering exactly the questions it is handed.
--- Absent keys answer nil, which is the service's own "cannot say" (never a plausible zero).
local function fake_forecast(answers)
    answers = answers or {}
    return {
        is_available = function() return answers.available ~= false end,
        time_to_die = function() return answers.time_to_die end,
        predicted_health_pct = function() return answers.predicted_health_pct end,
        incoming_damage_pct = function() return answers.incoming_damage_pct end,
        fight_seconds_remaining = function() return answers.fight_seconds_remaining end,
    }
end

--- An IziBridge double, for the service's own unit tests.
local function fake_bridge(answers)
    answers = answers or {}
    return {
        is_available = function() return answers.available == true end,
        get_time_to_die = function() return answers.time_to_die end,
        predict_hp_pct = function() return answers.predicted_health_pct end,
        get_forecast = function() return answers.fight_seconds_remaining end,
    }
end

local function mock_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "unit" end
    function unit:is_dead() return false end
    function unit:get_health_percentage() return opts.health_pct or 100 end
    function unit:get_health() return opts.health or 10000 end
    function unit:get_max_health() return opts.max_health or 10000 end
    return unit
end

--- A blackboard carrying a player and a target and PROVABLY no bridge key.
local function bb_with_target(target_opts)
    local bb = Blackboard:new()
    bb:set("player.object", mock_unit({}))
    bb:set("combat.target", mock_unit(target_opts))
    T.assert_nil(bb:get(BRIDGE_KEY),
        "the pin is worthless if the old blackboard route is still populated")
    return bb
end

-- ---------------------------------------------------------------------------
-- The service itself
-- ---------------------------------------------------------------------------

function M.test_a_forecast_with_no_bridge_answers_nil_rather_than_zero()
    local forecast = Forecast:new()
    T.assert_false(forecast:is_available(), "no bridge means the service cannot say, not that it is fine")
    T.assert_nil(forecast:time_to_die(mock_unit({})), "ADR 08 §9.3: never a plausible-looking zero")
    T.assert_nil(forecast:predicted_health_pct(mock_unit({}), 3))
    T.assert_nil(forecast:incoming_damage_pct(mock_unit({}), 3))
    T.assert_nil(forecast:fight_seconds_remaining())
end

function M.test_a_forecast_over_a_live_bridge_answers_from_it()
    local forecast = Forecast:new({ bridge = fake_bridge({
        available = true,
        time_to_die = 2.5,
        predicted_health_pct = 0.42,
        fight_seconds_remaining = 18.0,
    }) })
    T.assert_true(forecast:is_available())
    T.assert_equal(forecast:time_to_die(mock_unit({})), 2.5)
    T.assert_equal(forecast:predicted_health_pct(mock_unit({}), 3), 0.42)
    T.assert_equal(forecast:fight_seconds_remaining(), 18.0)
end

--- INCOMING DAMAGE IS DERIVED, AND IT HAS TO BE.
---
--- `condition_library.incoming_damage_above` called `izi_bridge:get_incoming_damage(player, secs)`.
--- THAT METHOD HAS NEVER EXISTED on `integrations/izi_bridge.lua` -- the bridge exposes
--- `predict_hp_pct`, `get_forecast`, `get_time_to_die`, `get_player` and `is_battleground`, and
--- nothing else. The condition has no callers, which is the only reason the missing method never
--- threw: the blackboard route was live in-game from Phase 4c, so the first caller would have
--- crashed inside the rotation.
---
--- The service therefore DERIVES it from the prediction the bridge does have. `predict_hp_pct`
--- returns `(hp - incoming) / max_hp`, so `incoming / max_hp` is exactly
--- `hp/max_hp - predicted_pct` -- the same number the condition was computing by hand, minus the
--- call to a method that is not there and minus the divide-by-zero on an unreadable max health.
function M.test_incoming_damage_is_derived_from_the_prediction_the_bridge_actually_has()
    local forecast = Forecast:new({ bridge = fake_bridge({
        available = true,
        -- 10000/10000 now, 6000/10000 in three seconds => 40% of max health incoming.
        predicted_health_pct = 0.60,
    }) })
    local player = mock_unit({ health = 10000, max_health = 10000 })
    T.assert_near(forecast:incoming_damage_pct(player, 3), 0.40, 1e-9,
        "incoming damage is the gap between current and predicted health fraction")

    T.assert_nil(Forecast:new({ bridge = fake_bridge({ available = true }) })
        :incoming_damage_pct(player, 3),
        "and it is nil, not 1.0, when the bridge cannot predict")

    T.assert_nil(forecast:incoming_damage_pct(mock_unit({ health = 1, max_health = 0 }), 3),
        "an unreadable max health is 'cannot say', never a division")
end

--- A bridge that is missing a method must read as "cannot say", not throw. The whole reason this
--- service exists is that a reader called a method the adapter never had.
function M.test_a_bridge_missing_a_method_reads_as_cannot_say()
    local forecast = Forecast:new({ bridge = { is_available = function() return true end } })
    T.assert_nil(forecast:time_to_die(mock_unit({})))
    T.assert_nil(forecast:predicted_health_pct(mock_unit({}), 3))
    T.assert_nil(forecast:fight_seconds_remaining())
end

-- ---------------------------------------------------------------------------
-- The capability claim
-- ---------------------------------------------------------------------------

--- `KERNEL_CAPABILITIES` without `CAPABILITY_BINDINGS` is how `log` shipped for a whole phase with
--- no field behind it (api.lua's own header records it). Both halves, or neither.
function M.test_forecast_is_both_claimed_and_bound()
    T.assert_true(Api.KERNEL_CAPABILITIES["forecast"] == true,
        "a service a plugin cannot require is a service no manifest can be admitted for")
    local binding = Api.CAPABILITY_BINDINGS["forecast"]
    T.assert_not_nil(binding, "claimed with no binding is the exact defect the bindings table exists for")
    T.assert_equal(binding.path[1], "forecast")
end

function M.test_the_forecast_field_resolves_through_the_live_getter()
    local service = Forecast:new()
    with_forecast(service, function()
        T.assert_true(_G.Sentinel.forecast == service,
            "the surface must hand back the app's instance, not a copy or a stub")
    end)
    without_surface(function()
        T.assert_nil(_G.Sentinel, "and the pre-publication state stays nil rather than being invented")
    end)
end

-- ---------------------------------------------------------------------------
-- READER 1-3: modules/combat/condition_library.lua
-- ---------------------------------------------------------------------------

function M.test_time_to_die_below_reads_the_forecast_service()
    local bb = bb_with_target({ health_pct = 95 })
    local condition = ConditionLibrary.time_to_die_below(5)

    without_surface(function()
        T.assert_false(condition(bb),
            "the HP%% fallback must refuse a 95%%-health target -- if this is already true the pin "
            .. "cannot tell the forecast from the fallback")
    end)
    with_forecast(fake_forecast({ time_to_die = 1.0 }), function()
        T.assert_true(condition(bb),
            "a target the forecast says dies in 1s is inside a 5s execute window, whatever its HP")
    end)
end

function M.test_incoming_damage_above_reads_the_forecast_service()
    local bb = bb_with_target({})
    local condition = ConditionLibrary.incoming_damage_above(0.30, 3)

    without_surface(function()
        T.assert_false(condition(bb), "with no forecast there is no incoming-damage answer at all")
    end)
    with_forecast(fake_forecast({ incoming_damage_pct = 0.55 }), function()
        T.assert_true(condition(bb), "55%% of max health inbound is above a 30%% threshold")
    end)
    with_forecast(fake_forecast({ incoming_damage_pct = 0.05 }), function()
        T.assert_false(condition(bb), "and 5%% is not -- the threshold must still be compared")
    end)
end

function M.test_health_prediction_below_reads_the_forecast_service()
    local bb = bb_with_target({})
    local condition = ConditionLibrary.health_prediction_below(0.30, 3)

    without_surface(function()
        T.assert_false(condition(bb), "with no forecast there is no prediction to be below")
    end)
    with_forecast(fake_forecast({ predicted_health_pct = 0.10 }), function()
        T.assert_true(condition(bb), "predicted 10%% is below the 30%% threshold")
    end)
end

-- ---------------------------------------------------------------------------
-- READER 4: rotations/paladin_retribution/retribution_conditions.lua
-- ---------------------------------------------------------------------------

--- `target_execute` is LIVE: `retribution_tbc.lua` gates Hammer of Wrath on it. This is the one
--- migrated reader whose verdict reaches a real rotation entry today.
function M.test_retribution_target_execute_reads_the_forecast_service()
    local bb = bb_with_target({ health_pct = 0.95 })

    without_surface(function()
        T.assert_false(RetCond.target_execute(bb), "a 95%% target is not in execute range by HP")
    end)
    with_forecast(fake_forecast({ time_to_die = 1.0 }), function()
        T.assert_true(RetCond.target_execute(bb),
            "but a target dying in 1s is, which is the entire point of consulting the forecast")
    end)
end

-- ---------------------------------------------------------------------------
-- READER 5: rotations/mage_frost/frost_combat_state.lua
-- ---------------------------------------------------------------------------

--- Kill-secure decides whether an instant can finish the target. Its fallback needs a spell catalog
--- and a Fire Blast/Ice Lance damage comparison; none of that is on this blackboard, so the fallback
--- answers false and the forecast branch is the only thing that can flip it.
function M.test_frost_kill_secure_reads_the_forecast_service()
    local bb = Blackboard:new()
    local state = FrostCombatState:new(bb)
    local target = mock_unit({ health = 100000, max_health = 100000 })
    T.assert_nil(bb:get(BRIDGE_KEY), "no blackboard bridge, by construction")

    without_surface(function()
        state:_refresh_kill_secure(bb, target)
        T.assert_false(bb:get("combat.target_killable_instant"),
            "a 100k-health target is not instant-killable without a forecast")
    end)
    with_forecast(fake_forecast({ time_to_die = 0.1 }), function()
        state:_refresh_kill_secure(bb, target)
        T.assert_true(bb:get("combat.target_killable_instant"),
            "a target the forecast says dies in 0.1s is already dead -- do not spend a nuke on it")
    end)
end

-- ---------------------------------------------------------------------------
-- READER 6: rotations/mage_frost/frost_conditions.lua
-- ---------------------------------------------------------------------------

--- `safe_to_evocate` is LIVE: `frost_tbc.lua:291` gates Evocation on it. Evocation is a channel --
--- being wrong here means standing still while the incoming damage the forecast predicted lands.
function M.test_frost_safe_to_evocate_reads_the_forecast_service()
    local bb = Blackboard:new()
    bb:set("player.object", mock_unit({}))
    bb:set("combat.enemy_count_10yd", 0)
    bb:set("combat.kite_state", "NONE")
    bb:set("player.health_pct", 0.80)
    T.assert_nil(bb:get(BRIDGE_KEY), "no blackboard bridge, by construction")

    without_surface(function()
        T.assert_true(FrostCond.safe_to_evocate(bb),
            "at 80%% health, alone and not kiting, the non-forecast checks all pass")
    end)
    with_forecast(fake_forecast({ predicted_health_pct = 0.10 }), function()
        T.assert_false(FrostCond.safe_to_evocate(bb),
            "but a prediction of 10%% in six seconds must veto the channel")
    end)
end

-- ---------------------------------------------------------------------------
-- The old route is gone, not merely unused
-- ---------------------------------------------------------------------------

--- The ledger entry and the write are atomically coupled -- `test_the_ledger_is_shrink_only` fails
--- if either outlives the other. This asserts the third thing neither of them can: that the KEY is
--- not written back by some other hand.
function M.test_no_source_file_writes_the_bridge_onto_the_blackboard()
    local Scope = require("tests/kernel/audit_scope")
    local pattern = 'set%(%s*"' .. BRIDGE_KEY:gsub("%.", "%%.") .. '"'
    local offenders = {}
    for _, path in ipairs(Scope.lua_files("sentinel")) do
        if not path:match("^sentinel/tests/") then
            local source = Scope.read_file(path)
            if source then
                Scope.each_code_line(source, function(line, line_number)
                    if line:match(pattern) then offenders[#offenders + 1] = path .. ":" .. line_number end
                end)
            end
        end
    end
    T.assert_equal(#offenders, 0,
        "the blackboard must not hold the bridge again:\n  " .. table.concat(offenders, "\n  "))
end

--- The reader side of the same fact. A file that still asks the blackboard for the bridge would get
--- nil forever and fall silently back to its non-forecast branch -- the failure this whole
--- deliverable is about, re-entered from the other direction.
function M.test_no_source_file_still_reads_the_bridge_from_the_blackboard()
    local Scope = require("tests/kernel/audit_scope")
    local pattern = 'get%(%s*"' .. BRIDGE_KEY:gsub("%.", "%%.") .. '"'
    local offenders = {}
    for _, path in ipairs(Scope.lua_files("sentinel")) do
        if not path:match("^sentinel/tests/") then
            local source = Scope.read_file(path)
            if source then
                Scope.each_code_line(source, function(line, line_number)
                    if line:match(pattern) then offenders[#offenders + 1] = path .. ":" .. line_number end
                end)
            end
        end
    end
    T.assert_equal(#offenders, 0,
        "these readers would silently receive nil forever:\n  " .. table.concat(offenders, "\n  "))
end

return M
