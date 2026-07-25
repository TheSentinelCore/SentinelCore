-- tests/kernel/test_one_fault_tracker.lua
-- "What counts as too many faults" must have exactly ONE implementation.
--
-- ================================================================================
-- WHY THIS IS A TEST AND NOT A COMMENT
-- ================================================================================
-- `kernel/scheduler.lua`'s header records the history: the 3-strike policy was written inline in the
-- scheduler, which made it the SECOND copy after `runtime/module_registry.lua`, and Phase 3's plugin
-- lifecycle needed a THIRD. Two of the three were extracted into `kernel/fault_tracker.lua`. The
-- module registry was left as "the last holdout" while it was the running path.
--
-- Phase 4c retires it, and a private streak counter kept here is exactly the kind of second
-- authority the extraction removed. Three copies of a threshold is three places for the number to
-- change; two is no better in kind.
--
-- WHAT THIS FILE ORIGINALLY SAID, AND WHY IT WAS WRONG: "combat now registers through the plugin
-- registry, so the module registry drives questing alone". It does not. `ModuleRegistry.modules`
-- registers combat (enabled, priority 10), `app.lua` calls `register_all` on THIS registry, and
-- nothing anywhere calls `PluginRegistry:register`. The consolidation is still right -- but its
-- blast radius includes the rotation engine, not questing alone, so the threshold this file pins
-- is what decides whether COMBAT keeps ticking.
--
-- ================================================================================
-- WHAT THIS CHECK CANNOT SEE
-- ================================================================================
--  1. A FOURTH IMPLEMENTATION SPELLED DIFFERENTLY. It greps for a literal streak-counting shape --
--     a `_fault_counts`-style table plus a `>= N` comparison, and a hardcoded max. Someone counting
--     faults with different identifiers, or with arithmetic this pattern does not match, is
--     invisible to it. The behavioural half below is the backstop: it pins that the module registry
--     and the scheduler agree on the threshold, so a divergent fourth copy driving either one shows
--     up as a behaviour difference even when the grep misses it.
--  2. WHETHER THE SHARED TRACKER IS CORRECT. `tests/kernel/test_*` cover FaultTracker itself. This
--     file only asserts there is one of it.
--  3. NON-LUA COPIES. Nothing under SentinelQuesting/, SentinelNavServer/ or SentinelQueryServer/ is
--     scanned; the Rust side has its own error handling and is out of scope by construction.

local FaultTracker = require("kernel/fault_tracker")
local ModuleRegistry = require("runtime/module_registry")
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

--- Files that may legitimately name a consecutive-failure threshold, and WHY.
---
--- The rule being consolidated is LIFECYCLE fault tracking: how many times a ticked unit -- a
--- module, a plugin, a scheduler handler -- may throw before the host stops driving it. Two entries
--- here, and the second is the interesting one.
local ALLOWED = {
    -- The one implementation.
    ["sentinel/kernel/fault_tracker.lua"] =
        "the shared tracker; this is where the rule lives",

    -- A DIFFERENT RULE THAT READS THE SAME. `MAX_CONSECUTIVE_FAILURES = 3` here counts quest ACTIONS
    -- that failed in a row before the runtime profile stops advancing -- a guide-execution budget,
    -- not a host lifecycle policy. It answers "is this quest step stuck", where the tracker answers
    -- "is this module too broken to keep ticking". Folding them together because both happen to be 3
    -- would couple a questing behaviour to a host policy and make each one's number unchangeable
    -- without moving the other.
    ["sentinel/modules/questing/runtime_profile.lua"] =
        "quest-action failure budget, not lifecycle fault tracking -- a different rule that "
        .. "coincidentally shares the number 3",
}

local function lua_files_under(dir)
    local files = {}
    local find = io.popen('find ' .. dir .. ' -type f -name "*.lua" | sort')
    if find then
        for line in find:lines() do files[#files + 1] = line end
        find:close()
    end
    return files
end

-- ---------------------------------------------------------------------------
-- Structural: one implementation
-- ---------------------------------------------------------------------------

function M.test_only_the_fault_tracker_hardcodes_a_consecutive_fault_threshold()
    local offenders = {}
    for _, dir in ipairs({ "sentinel/kernel", "sentinel/runtime", "sentinel/modules", "sentinel/core" }) do
        for _, path in ipairs(lua_files_under(dir)) do
            if not ALLOWED[path] then
                local handle = io.open(path, "r")
                if handle then
                    local line_number = 0
                    for line in handle:lines() do
                        line_number = line_number + 1
                        -- A named maximum for consecutive faults, assigned a literal.
                        if line:match("MAX_CONSECUTIVE[%w_]*%s*=%s*%d")
                            or line:match("_fault_counts%s*%[") then
                            offenders[#offenders + 1] = path .. ":" .. line_number
                        end
                    end
                    handle:close()
                end
            end
        end
    end

    T.assert_equal(#offenders, 0,
        "the 3-strike policy must live only in kernel/fault_tracker.lua, but is also written at:\n  "
        .. table.concat(offenders, "\n  "))
end

-- ---------------------------------------------------------------------------
-- Behavioural: the one tracker is the one actually driving the registry
-- ---------------------------------------------------------------------------
-- The grep above proves nobody ELSE hardcodes the number. These prove the registry's behaviour comes
-- FROM the tracker rather than merely coinciding with it -- a private counter initialised to the
-- same 3 would satisfy the grep by using a differently-spelled identifier.

local function registry_with_a_module(tick_fn)
    local bb = Blackboard:new()
    local bus = EventBus:new(function() end)
    local registry = ModuleRegistry:new()
    registry:register("faulty", {
        namespace = "faulty",
        capabilities = {},
        configuration = { enabled = true },
        init = function() return { tick = tick_fn } end,
    })
    registry:initialize_module("faulty", bb, bus)
    return registry, bb
end

function M.test_the_module_registry_degrades_at_the_trackers_threshold()
    local registry = registry_with_a_module(function() error("boom", 0) end)

    for strike = 1, FaultTracker.DEFAULT_MAX_CONSECUTIVE - 1 do
        registry:tick_all(16)
        T.assert_equal(registry:get_state("faulty"), "active",
            "strike " .. strike .. " is below the threshold and must not degrade")
    end

    registry:tick_all(16)
    T.assert_equal(registry:get_state("faulty"), "degraded",
        "the module must degrade at exactly FaultTracker.DEFAULT_MAX_CONSECUTIVE")
end

--- Only CONSECUTIVE faults degrade -- the streak-reset rule, which a naive total counter gets wrong.
function M.test_a_clean_tick_resets_the_streak()
    local explode = true
    local registry, bb = registry_with_a_module(function()
        if explode then error("boom", 0) end
    end)

    registry:tick_all(16)
    registry:tick_all(16)
    explode = false
    registry:tick_all(16)
    T.assert_nil(bb:get("system.module_faults")["faulty"],
        "a clean tick must clear the fault record, not merely stop adding to it")

    explode = true
    for _ = 1, FaultTracker.DEFAULT_MAX_CONSECUTIVE - 1 do registry:tick_all(16) end
    T.assert_equal(registry:get_state("faulty"), "active",
        "and the streak must restart from zero, not resume where it left off")
end

--- The cockpit reads `system.module_faults`. Moving to the shared tracker must not silently drop the
--- mirror, which is the only place a fault is visible without a log.
function M.test_faults_are_still_mirrored_to_the_blackboard_for_the_cockpit()
    local registry, bb = registry_with_a_module(function() error("boom", 0) end)
    registry:tick_all(16)

    local faults = bb:get("system.module_faults")
    T.assert_not_nil(faults and faults["faulty"])
    T.assert_equal(faults["faulty"].count, 1)
    T.assert_true(tostring(faults["faulty"].last_error):find("boom", 1, true) ~= nil)
end

return M
