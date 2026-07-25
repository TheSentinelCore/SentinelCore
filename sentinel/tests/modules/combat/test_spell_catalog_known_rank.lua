-- Unit B (B1): characterization/red tests for SpellCatalog:resolve_known_rank.
-- Distinct from resolve_best_rank (spell_catalog.lua:125, uses core.spell_book.has_spell) —
-- resolve_known_rank must gate on TRAINED status via is_spell_learned (checked first, per
-- spellbook.md:227 — more reliable for talent-modified spells) falling back to is_spell_known,
-- walking the rank array HIGH->LOW and returning the first known id, or nil if none known.
local SpellCatalog = require("kernel/catalogs/spell")
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

-- frostbolt ranks (spell_catalog.lua:24): 116,205,837,7322,8406,8407,8408,10179,10180,10181,25304,27071,27072,38697

function M.test_resolves_via_is_spell_learned_only()
    set_spell_book({
        is_spell_learned = function(id) return id == 8407 end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("frostbolt"), 8407, "resolves rank known only via is_spell_learned")
    clear_spell_book()
end

function M.test_resolves_via_is_spell_known_only()
    set_spell_book({
        is_spell_known = function(id) return id == 837 end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("frostbolt"), 837, "resolves rank known only via is_spell_known")
    clear_spell_book()
end

function M.test_walks_high_to_low_returns_highest_known()
    set_spell_book({
        is_spell_learned = function(id)
            return id == 116 or id == 837 or id == 8406
        end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("frostbolt"), 8406, "returns HIGHEST known rank, not lowest")
    clear_spell_book()
end

function M.test_low_rank_only_known_leveling_case()
    set_spell_book({
        is_spell_learned = function(id) return id == 205 end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("frostbolt"), 205, "leveling case: only a low rank trained")
    clear_spell_book()
end

function M.test_nil_when_nothing_known()
    set_spell_book({
        is_spell_learned = function() return false end,
        is_spell_known = function() return false end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("frostbolt"), nil, "nil when no rank is known")
    clear_spell_book()
end

function M.test_distinct_from_resolve_best_rank_has_spell_alone_insufficient()
    -- resolve_best_rank (spell_catalog.lua:125) gates on has_spell only; resolve_known_rank
    -- must NOT be satisfied by has_spell alone -- proves the two resolvers are independent,
    -- avoiding mage/paladin blast radius (design D-rank-resolution).
    set_spell_book({
        has_spell = function() return true end,
        is_spell_learned = function() return false end,
        is_spell_known = function() return false end,
    })
    local catalog = SpellCatalog:new()
    T.assert_not_nil(catalog:resolve_best_rank("frostbolt"), "resolve_best_rank is satisfied by has_spell")
    T.assert_equal(catalog:resolve_known_rank("frostbolt"), nil, "resolve_known_rank ignores has_spell entirely")
    clear_spell_book()
end

function M.test_single_id_spell_known_via_is_spell_learned()
    -- ice_lance is a single-id spell (no ranks array) -- spell_catalog.lua:28
    set_spell_book({
        is_spell_learned = function(id) return id == 30455 end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("ice_lance"), 30455, "single-id spell resolves via is_spell_learned")
    clear_spell_book()
end

function M.test_single_id_spell_nil_when_unknown()
    set_spell_book({
        is_spell_learned = function() return false end,
        is_spell_known = function() return false end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("ice_lance"), nil, "single-id spell nil when untrained")
    clear_spell_book()
end

return M
