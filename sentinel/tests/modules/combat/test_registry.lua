-- Unit C (C1): characterization/red tests for Registry.resolve fail-loud behavior.
-- registry.lua previously silently fell back to PaladinRetTBC for ANY unmapped
-- class_id (registry.lua:13-16) -- a correctness bug: an unsupported class would
-- run the WRONG rotation instead of being disabled. This is the core regression
-- guard: resolve() on an unknown class_id must return nil and must NOT return
-- Paladin's profile module.
local Registry = require("modules/combat/profiles/registry")
local PaladinRetTBC = require("modules/combat/profiles/paladin/retribution_tbc")
local MageFrostTBC = require("modules/combat/profiles/mage/frost_tbc")
local T = require("tests/test_util")

local M = {}

-- 9 (Warlock) was the unmapped fixture as of Unit C; Unit D registered it
-- (WarlockAfflictionTBC), so the unmapped-id fixture moved to 99 -- a class_id
-- with no plausible mapping in any unit of this change.
local UNMAPPED_CLASS_ID = 99

function M.test_unknown_class_id_returns_nil()
    T.assert_nil(Registry.resolve(UNMAPPED_CLASS_ID), "unmapped class_id must resolve to nil")
end

function M.test_unknown_class_id_does_not_fall_back_to_paladin()
    local resolved = Registry.resolve(UNMAPPED_CLASS_ID)
    T.assert_true(resolved ~= PaladinRetTBC, "unmapped class_id must NOT silently fall back to Paladin's profile")
end

function M.test_totally_bogus_class_id_returns_nil()
    T.assert_nil(Registry.resolve(999), "a class_id with no plausible mapping must resolve to nil")
end

function M.test_known_mage_class_id_still_resolves()
    T.assert_equal(Registry.resolve(8), MageFrostTBC, "class_id 8 (Mage) must still resolve to MageFrostTBC")
end

function M.test_known_paladin_class_id_still_resolves()
    T.assert_equal(Registry.resolve(2), PaladinRetTBC, "class_id 2 (Paladin) must still resolve to PaladinRetTBC")
end

return M
