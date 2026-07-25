-- tests/kernel/test_rotation_lib.lua
-- `Sentinel.rotation` -- PriorityBuilder promoted out of the combat module (ADR 08 §5.4).
--
-- §5.4: "promote to the kernel library. It is the best existing asset ... and it is currently
-- trapped inside the combat module. It is also the honest basis for the Tier-1 rotation DSL."
--
-- This is a PROMOTION, not a rewrite (§13 risk 5). The behaviour tests below pin the two contracts
-- the three existing profiles actually depend on -- ascending priority order and AND-ed conditions --
-- so a "tidy-up" during the move shows up as a failure rather than as drift.

local Api = require("kernel/api")
local Blackboard = require("core/blackboard")
local Status = require("core/bt/status")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- Exposure
-- ---------------------------------------------------------------------------

function M.test_sentinel_rotation_exposes_the_priority_builder()
    local surface = Api.build({})
    T.assert_not_nil(surface.rotation, "ADR §10 lists `Sentinel.rotation` on the surface")
    T.assert_true(type(surface.rotation.new) == "function",
        "a rotation library a plugin cannot instantiate is not a library")
end

--- The whole point of promoting it. A kernel library that reaches back into `modules/combat/` would
--- make every plugin using it depend on the module it was extracted from -- and would silently fail
--- the rotation's own require audit by proxy.
function M.test_the_promoted_library_reaches_outside_neither_kernel_nor_core()
    local path = "sentinel/kernel/lib/priority_builder.lua"
    local handle = io.open(path, "r")
    T.assert_not_nil(handle, "expected the promoted library at " .. path)
    local source = handle:read("*a")
    handle:close()

    local offenders = {}
    for required in source:gmatch('require%s*%(?%s*"([^"]+)"') do
        local head = required:match("^([^/]+)")
        if head ~= "kernel" and head ~= "core" then
            offenders[#offenders + 1] = required
        end
    end
    T.assert_equal(#offenders, 0,
        "kernel library must not require outside kernel/ or core/, found: "
        .. table.concat(offenders, ", "))
end

-- ---------------------------------------------------------------------------
-- Ported behaviour
-- ---------------------------------------------------------------------------

local function build(entries)
    local PriorityBuilder = Api.build({}).rotation
    local builder = PriorityBuilder.new("TEST", "SPEC")
    for _, e in ipairs(entries) do
        builder:add_priority(e.name, e.conditions, e.action, e.children, e.priority)
    end
    return builder:build(Blackboard:new())
end

--- LOWER number wins. The three shipped profiles are authored against this ordering; flipping it
--- would silently reorder every rotation in the tree.
function M.test_a_lower_priority_number_runs_first()
    local fired = {}
    local root = build({
        { name = "second", priority = 20,
          conditions = function() return true end,
          action = function() fired[#fired + 1] = "second" return Status.SUCCESS end },
        { name = "first", priority = 10,
          conditions = function() return true end,
          action = function() fired[#fired + 1] = "first" return Status.SUCCESS end },
    })

    root:tick(Blackboard:new())
    T.assert_equal(fired[1], "first", "priority 10 must be evaluated before priority 20")
    T.assert_equal(#fired, 1, "and the selector must stop at the first success")
end

--- A failing gate must hand the tick to the next entry rather than ending it.
function M.test_a_failed_condition_falls_through_to_the_next_priority()
    local fired = {}
    local root = build({
        { name = "gated", priority = 10,
          conditions = function() return false end,
          action = function() fired[#fired + 1] = "gated" return Status.SUCCESS end },
        { name = "fallback", priority = 20,
          conditions = function() return true end,
          action = function() fired[#fired + 1] = "fallback" return Status.SUCCESS end },
    })

    root:tick(Blackboard:new())
    T.assert_equal(fired[1], "fallback")
    T.assert_equal(#fired, 1)
end

--- Multiple conditions are AND-ed. `frost_conditions.lua` leans on this for every gated ability.
function M.test_multiple_conditions_are_anded()
    local fired = {}
    local root = build({
        { name = "both", priority = 10,
          conditions = { function() return true end, function() return false end },
          action = function() fired[#fired + 1] = "both" return Status.SUCCESS end },
    })

    root:tick(Blackboard:new())
    T.assert_equal(#fired, 0, "one false condition must veto the entry")
end

--- The `{function, arg}` condition form the profiles use for parameterised gates.
function M.test_a_condition_pair_passes_its_argument()
    local seen = nil
    local root = build({
        { name = "parameterised", priority = 10,
          conditions = { { function(_, arg) seen = arg return true end, 0.35 } },
          action = function() return Status.SUCCESS end },
    })

    root:tick(Blackboard:new())
    T.assert_equal(seen, 0.35, "the second element must be passed through as the argument")
end

return M
