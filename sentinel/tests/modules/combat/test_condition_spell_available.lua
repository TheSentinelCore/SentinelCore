-- Unit B (B3): characterization/red tests for ConditionLibrary.spell_available.
-- Distinct from spell_ready (condition_library.lua:245, cooldown/castability/LoS only) --
-- spell_available gates on TRAINED status (via SpellCatalog:resolve_known_rank), with an
-- optional "usable" mode additionally requiring core.spell_book.is_usable_spell.
local Blackboard = require("core/blackboard")
local SpellCatalog = require("kernel/catalogs/spell")
local ConditionLibrary = require("modules/combat/condition_library")
local T = require("tests/test_util")

local M = {}

local function set_spell_book(mock)
    _G.core = _G.core or {}
    _G.core.spell_book = mock
end

local function clear_spell_book()
    if _G.core then
        _G.core.spell_book = nil
    end
end

local function make_bb()
    local bb = Blackboard:new()
    bb:set("module.combat.catalog", SpellCatalog:new())
    return bb
end

-- frostbolt ranks (spell_catalog.lua:24): ... 8406, 8407, 8408, ... 38697 (best)

function M.test_untrained_spell_is_unavailable_via_is_spell_known()
    set_spell_book({
        is_spell_known = function() return false end,
    })
    local bb = make_bb()
    T.assert_false(ConditionLibrary.spell_available("frostbolt")(bb), "untrained spell must be unavailable")
    clear_spell_book()
end

function M.test_trained_spell_available_via_is_spell_known()
    set_spell_book({
        is_spell_known = function(id) return id == 837 end,
    })
    local bb = make_bb()
    T.assert_true(ConditionLibrary.spell_available("frostbolt")(bb), "trained spell available via is_spell_known")
    clear_spell_book()
end

function M.test_talent_rank_spell_unavailable_until_learned_via_is_spell_learned()
    -- is_spell_known reports false for the talent-modified rank; only is_spell_learned is
    -- reliable (spellbook.md:227). Same blackboard is re-evaluated before/after "learning".
    set_spell_book({
        is_spell_known = function() return false end,
        is_spell_learned = function() return false end,
    })
    local bb = make_bb()
    T.assert_false(ConditionLibrary.spell_available("frostbolt")(bb), "unavailable before talent/rank is learned")

    set_spell_book({
        is_spell_known = function() return false end,
        is_spell_learned = function(id) return id == 8406 end,
    })
    T.assert_true(ConditionLibrary.spell_available("frostbolt")(bb), "available once is_spell_learned reports true")
    clear_spell_book()
end

function M.test_trained_and_usable_spell_passes_usable_mode()
    set_spell_book({
        is_spell_learned = function(id) return id == 8406 end,
        is_usable_spell = function(id) return id == 8406 end,
    })
    local bb = make_bb()
    T.assert_true(ConditionLibrary.spell_available("frostbolt", "usable")(bb), "usable mode passes when trained+usable")
    clear_spell_book()
end

function M.test_usable_mode_fails_when_not_usable()
    -- trained (learned) but currently not usable (e.g. out of mana/reagents)
    set_spell_book({
        is_spell_learned = function(id) return id == 8406 end,
        is_usable_spell = function() return false end,
    })
    local bb = make_bb()
    T.assert_false(ConditionLibrary.spell_available("frostbolt", "usable")(bb), "usable mode fails when not usable")
    clear_spell_book()
end

function M.test_default_mode_does_not_require_usable()
    -- default/"known" mode must NOT gate on is_usable_spell -- only trained status matters.
    set_spell_book({
        is_spell_learned = function(id) return id == 8406 end,
        is_usable_spell = function() return false end,
    })
    local bb = make_bb()
    T.assert_true(ConditionLibrary.spell_available("frostbolt")(bb), "default mode ignores is_usable_spell")
    clear_spell_book()
end

function M.test_missing_catalog_returns_false_not_error()
    set_spell_book({ is_spell_known = function() return true end })
    local bb = Blackboard:new() -- no module.combat.catalog set
    T.assert_false(ConditionLibrary.spell_available("frostbolt")(bb), "no catalog on blackboard -> false, not error")
    clear_spell_book()
end

function M.test_unknown_spell_key_returns_false_not_error()
    set_spell_book({ is_spell_learned = function() return true end })
    local bb = make_bb()
    T.assert_false(ConditionLibrary.spell_available("not_a_real_spell_key")(bb), "unknown catalog key -> false, not error")
    clear_spell_book()
end

function M.test_composes_with_and_not()
    set_spell_book({
        is_spell_learned = function(id) return id == 8406 end,
    })
    local bb = make_bb()
    local trained_and_not_usable = ConditionLibrary.and_(
        ConditionLibrary.spell_available("frostbolt"),
        ConditionLibrary.not_(ConditionLibrary.spell_available("ice_lance"))
    )
    T.assert_true(trained_and_not_usable(bb), "spell_available composes with and_/not_")
    clear_spell_book()
end

return M
