local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local Profile = require("rotations/mage_frost/frost_tbc")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health_percentage() return opts.health_pct or 1.0 end
    function unit:is_dead() return false end
    function unit:get_target() return opts.target end
    function unit:has_buff(buff_id)
        local buffs = opts.buffs or {}
        if type(buff_id) == "table" then
            for _, id in ipairs(buff_id) do
                if buffs[id] then return true end
            end
            return false
        end
        return buffs[buff_id] == true
    end
    function unit:get_buff_data(spell_id)
        return { is_active = unit:has_buff(spell_id), stack_count = 0 }
    end
    function unit:get_buff_stacks(_spell_id) return 0 end
    function unit:get_buffs() return {} end
    function unit:is_casting_spell() return opts.casting == true end
    function unit:is_channelling_spell() return false end
    function unit:is_active_spell_interruptable() return opts.interruptible ~= false end
    return unit
end

local function make_bb()
    spell_helper = {
        is_spell_castable = function(_self, _spell_id, _source, _target, _ignore_facing, _ignore_range)
            return true
        end,
        get_spell_cooldown = function(_self, _spell_id)
            return 0
        end,
        is_spell_in_line_of_sight = function()
            return true
        end,
    }

    local bb = Blackboard:new()
    local player = make_unit({ guid = "player", position = { x = 0, y = 0, z = 0 }, buffs = {} })
    local target = make_unit({ guid = "target", position = { x = 25, y = 0, z = 0 }, health_pct = 0.80 })
    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.level", 70)
    bb:set("player.in_combat", true)
    bb:set("player.is_moving", false)
    bb:set("combat.target", target)
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 0)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("module.combat.catalog", require("kernel/catalogs/spell"):new())
    bb:set("module.combat.cooldowns", {
        spell_ready = function() return true end,
        is_gcd_ready = function() return true end,
    })
    bb:set("module.combat.dispatcher", {
        queue_target = function(_self, _action_id, _spell_id, _target, _priority, _message, _opts)
            return true
        end,
        queue_position = function(_self, _action_id, _spell_id, _position, _priority, _message)
            return true
        end,
    })
    return bb
end

local function build()
    local bb = make_bb()
    return Profile.build(bb, EventBus:new()), bb
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

function M.test_build_returns_a_profile_with_the_expected_id()
    local profile = build()
    T.assert_not_nil(profile, "build() should return a non-nil profile")
    T.assert_equal(profile.id, "mage_frost_tbc", "profile id should be mage_frost_tbc")
end

function M.test_build_publishes_the_profile_id_on_the_blackboard()
    local _, bb = build()
    T.assert_equal(bb:get("rotation.profile_id"), "mage_frost_tbc",
        "rotation.profile_id should be set on blackboard")
end

function M.test_the_profile_exposes_its_three_tick_surfaces_and_reset()
    local profile = build()
    T.assert_true(type(profile.tick_maintenance) == "function", "should have tick_maintenance method")
    T.assert_true(type(profile.tick_off_gcd) == "function", "should have tick_off_gcd method")
    T.assert_true(type(profile.tick_gcd) == "function", "should have tick_gcd method")
    T.assert_true(type(profile.reset) == "function", "should have reset method")
end

--- Grind-era hooks (prepare_rest, tick_pull, get_pull_strategy, _aoe_tree) were removed with
--- ADR-001 (audit E3) -- they had no caller left.
function M.test_the_dead_grind_era_hooks_are_gone()
    local profile = build()
    T.assert_nil(profile.prepare_rest, "prepare_rest should be removed (dead grind-era hook)")
    T.assert_nil(profile.tick_pull, "tick_pull should be removed (dead grind-era hook)")
    T.assert_nil(profile.get_pull_strategy, "get_pull_strategy should be removed (dead grind-era hook)")
end

-- ---------------------------------------------------------------------------
-- Ticking
-- ---------------------------------------------------------------------------

function M.test_reset_does_not_error()
    local profile = build()
    local ok, err = pcall(function() profile:reset() end)
    T.assert_true(ok, "reset() should not error: " .. tostring(err))
end

function M.test_every_tick_surface_runs_without_erroring()
    local profile, bb = build()
    for _, name in ipairs({ "tick_maintenance", "tick_off_gcd", "tick_gcd" }) do
        local ok, err = pcall(function() return profile[name](profile, bb) end)
        T.assert_true(ok, name .. " should not error: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- The GCD diagnostic (ADR 08 §10 -- `Sentinel.log`, auto-attributed)
-- ---------------------------------------------------------------------------
--
-- This used to be `pcall(core.log, ...)` behind an `if core and core.log` guard: a plugin
-- reaching straight past the public API for the one thing §10 says the API provides. The
-- interesting property is not that a line comes out -- it is WHOSE NAME is on it, because
-- attribution is derived from the call site rather than typed by the caller, and a wrong name
-- in a log line looks exactly like a right one.

--- Drive `tick_gcd` down its FAILURE branch deterministically.
---
--- The GCD tree's own verdict depends on 25 priority entries, so forcing it through the
--- blackboard would be a test of the rotation rather than of the diagnostic. Substituting the
--- runner names the one input this test is about.
local function tick_gcd_with_failing_tree(profile, bb)
    profile._gcd = { tick = function() return "FAILURE" end, reset = function() end }

    local lines = {}
    local previous = _G.core.log
    _G.core.log = function(line) lines[#lines + 1] = line end
    local ok, err = pcall(function() return profile:tick_gcd(bb) end)
    _G.core.log = previous

    if not ok then error(err, 0) end
    return lines
end

function M.test_the_gcd_diagnostic_reaches_the_kernel_logger()
    local profile, bb = build()
    local lines = tick_gcd_with_failing_tree(profile, bb)

    T.assert_equal(#lines, 1, "a failing GCD tree must produce exactly one diagnostic")
    T.assert_true(lines[1]:find("[FrostGCD]", 1, true) ~= nil,
        "the diagnostic's own text must survive: " .. lines[1])
end

--- §10: "(auto-attributed)". The plugin does not type its own name, so a copy-paste into
--- another rotation cannot carry a stale one.
function M.test_the_gcd_diagnostic_is_attributed_to_this_rotation()
    local profile, bb = build()
    local lines = tick_gcd_with_failing_tree(profile, bb)

    T.assert_true(lines[1]:find("[rotations.mage_frost]", 1, true) ~= nil,
        "attribution must name the calling package: " .. lines[1])
    T.assert_true(lines[1]:find("[debug]", 1, true) ~= nil,
        "a diagnostic is debug level: " .. lines[1])
end

--- A diagnostic that can crash the tick is a liability, and this one runs inside plugin code
--- the ErrorBoundary would then blame for the logger's fault. With no sink at all the line is
--- dropped and the tick continues.
function M.test_the_gcd_diagnostic_survives_having_nowhere_to_write()
    local profile, bb = build()
    profile._gcd = { tick = function() return "FAILURE" end, reset = function() end }

    local previous = _G.core.log
    _G.core.log = nil
    local ok, err = pcall(function() return profile:tick_gcd(bb) end)
    _G.core.log = previous

    T.assert_true(ok, "an absent sink must not reach the tick: " .. tostring(err))
end

--- Throttled to one line every two seconds, so a rotation that fails every 75ms tick does not
--- bury the log it is trying to explain.
function M.test_the_gcd_diagnostic_is_throttled()
    local profile, bb = build()
    tick_gcd_with_failing_tree(profile, bb)
    local again = tick_gcd_with_failing_tree(profile, bb)
    T.assert_equal(#again, 0, "a second failure inside the window must stay quiet")

    bb:set("system.now_ms", 1000 + 2000)
    local later = tick_gcd_with_failing_tree(profile, bb)
    T.assert_equal(#later, 1, "and speak again once the window has passed")
end

-- ---------------------------------------------------------------------------
-- The audit's claim, checked where the change happened
-- ---------------------------------------------------------------------------

function M.test_the_profile_names_core_nowhere()
    local handle = io.open("sentinel/rotations/mage_frost/frost_tbc.lua", "r")
    T.assert_not_nil(handle, "frost_tbc.lua must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()

    local line_number = 0
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        line_number = line_number + 1
        if not line:match("^%s*%-%-") then
            T.assert_nil(line:match("%f[%w_]core%s*%."),
                "direct SDK access at frost_tbc.lua:" .. line_number .. " -- " .. line)
        end
    end
end

return M
