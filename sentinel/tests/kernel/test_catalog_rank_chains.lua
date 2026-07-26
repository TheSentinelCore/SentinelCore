-- tests/kernel/test_catalog_rank_chains.lua
-- Every rank array in both catalogs, pinned against the GAME DATABASE rather than against an audit.
--
-- ================================================================================
-- WHY THIS SUITE EXISTS: A WRONG RANK ARRAY IS INVISIBLE TO A GREEN SUITE
-- ================================================================================
-- `SpellCatalog:resolve_best_rank` / `resolve_known_rank` walk the array from the HIGHEST index
-- DOWN and return the first id `core.spell_book` says the player owns. That loop is total: an id
-- the player cannot possibly know is skipped in silence, and a rank the array never lists cannot
-- be reached at all. So a wrong array does not raise, does not log, and does not fail a test --
-- it just casts a weaker spell forever.
--
-- MEASURED, before the fix (tbcmangos.sqlite, MaNGOS TBC 2.4.3):
--
--   seal_of_righteousness  carried 20284/20285/20286 -- which are JUDGEMENT of Righteousness ranks
--                          6-8, a different spell entirely -- and 27156, the hidden BaseLevel-0
--                          proc from the second same-named chain (Attributes 2359296) that is never
--                          in a spellbook. Ranks 7, 8 and 9 of the real seal (20292 lvl 50,
--                          20293 lvl 58, 27155 lvl 66) were ABSENT. Walking high-first, a level-70
--                          paladin fell past all four unknown ids to 20291 -- Rank 6, level 42.
--                          BOTH spell.lua and aura.lua carried the same wrong array, so checking
--                          either against the other would have agreed.
--   fireball               stopped at 27070 (Rank 13, level 66). Rank 14, 38692, level 70, missing.
--   frost_ward             stopped at 28609 (Rank 5, level 60). Rank 6, 32796, level 70, missing.
--   conjure_water          ended ..., 27090, 37420 -- inverted. 37420 is Rank 8 (level 65) and
--                          27090 is Rank 9 (level 70), so the highest INDEX held the lower RANK
--                          and a level-70 mage conjured rank 8 water.
--
-- ================================================================================
-- WHY THE FIXTURE, AND NOT A QUERY
-- ================================================================================
-- tbcmangos.sqlite is 298 MB and gitignored. A test that opened it would SKIP on CI and on every
-- machine but one, and a skipping test reads exactly like a passing one -- the failure mode
-- `test_spell_catalog_gcd_truth.lua` names in its own "what this suite cannot see" section, where
-- the Phase 4e audit was a one-off script that could not be re-run and four entries stayed wrong.
--
-- So the query is committed instead: `sentinel/tools/regen_catalog_chain_fixture.py` writes
-- `tests/fixtures/spell_chain_tbc243.lua`, and this suite compares the catalogs against it with no
-- database, no `io` and no sqlite -- which is also what the Sylvannas sandbox requires. The fixture
-- carries SpellName, rank label and BaseLevel next to every id, so a failure states which rank is
-- wrong instead of only that two arrays differ.
--
-- ================================================================================
-- WHAT THIS SUITE CANNOT SEE
-- ================================================================================
--  1. FIXTURE DRIFT. If the database is swapped, only
--     `regen_catalog_chain_fixture.py --check` notices. This suite pins catalog-against-fixture;
--     it is fixture-against-database that has no offline witness. The internal-consistency test
--     below is the partial backstop: a hand-edited fixture that breaks ascending order is caught.
--  2. THE `unchained` FAMILIES. `spell_chain` has no rows for talent ranks (Vengeance, Frostbite),
--     Retribution Aura or the water elemental's Freeze. For those the database proves the ids
--     exist, share one SpellName and ascend -- and for the two Vengeance arrays it cannot prove
--     nothing is MISSING, because SpellName+Attributes does not separate the paladin talent from
--     the druid one. Each entry states its own verdict in `completeness`.
--  3. WHETHER A ROTATION ASKS FOR THE RIGHT KEY. This pins what the catalog answers, not that
--     anyone consults it, and not that `has_spell` reports truthfully in a live client.

local SpellCatalog = require("kernel/catalogs/spell")
local AuraCatalog = require("kernel/catalogs/aura")
local FIX = require("tests/fixtures/spell_chain_tbc243")
local T = require("tests/test_util")

local M = {}

local function fmt(ids)
    return "{ " .. table.concat(ids, ", ") .. " }"
end

--- Compares two id arrays and reports the FIRST divergence with the database's own evidence for
--- it, because "expected {a,b,c} got {a,b,d}" on a fourteen-rank array is unreadable.
local function assert_chain(label, actual, expect)
    actual = actual or {}
    local n = math.max(#actual, #expect.ids)
    for i = 1, n do
        local got, want = actual[i], expect.ids[i]
        if got ~= want then
            local detail
            if want == nil then
                detail = "the array is LONGER than the database chain -- id " .. tostring(got)
                    .. " at index " .. i .. " is not part of it"
            elseif got == nil then
                detail = "MISSING rank " .. i .. ": id " .. want .. " ("
                    .. (expect.rank_labels[i] ~= "" and expect.rank_labels[i] or "no rank label")
                    .. ", BaseLevel " .. expect.levels[i] .. ")"
            else
                detail = "index " .. i .. " is " .. got .. " but the database says " .. want
                    .. " (" .. (expect.rank_labels[i] ~= "" and expect.rank_labels[i] or "no label")
                    .. ", BaseLevel " .. expect.levels[i] .. ")"
            end
            error(label .. ": " .. detail .. "\n     actual   " .. fmt(actual)
                .. "\n     database " .. fmt(expect.ids), 0)
        end
    end
end

local function expectation(key)
    return FIX.chains[key] or FIX.unchained[key]
end

--- Every array-valued field of aura.lua, by name. `pairs` over the module also yields functions
--- and the buff_manager handle, so filter to all-number arrays.
local function aura_arrays()
    local out = {}
    for field, value in pairs(AuraCatalog) do
        if type(value) == "table" and #value > 0 then
            local all_numbers = true
            for i = 1, #value do
                if type(value[i]) ~= "number" then all_numbers = false break end
            end
            if all_numbers then out[field] = value end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- spell.lua
-- ---------------------------------------------------------------------------

--- THE PRIMARY ASSERTION. Every `ranks` array in spell.lua, against the chain the database
--- reconstructs for it.
function M.test_every_spell_rank_array_matches_the_database_chain()
    local failures = {}
    for key, entry in pairs(SpellCatalog:new():all()) do
        if entry.ranks then
            local expect = expectation(key)
            if not expect then
                table.insert(failures, key .. ": no fixture entry. Re-run "
                    .. "sentinel/tools/regen_catalog_chain_fixture.py -- an unclassified rank "
                    .. "array is an UNAUDITED one")
            else
                local ok, err = pcall(assert_chain, key, entry.ranks, expect)
                if not ok then table.insert(failures, tostring(err)) end
            end
        end
    end
    table.sort(failures)
    T.assert_equal(#failures, 0, "\n  " .. table.concat(failures, "\n  "))
end

--- The other direction: a chain the fixture knows about must still be IN the catalog. Deleting an
--- entry would otherwise make the test above pass by having nothing left to check.
function M.test_no_catalog_rank_array_has_gone_missing()
    local spells = SpellCatalog:new():all()
    local aura = aura_arrays()
    for key in pairs(FIX.chains) do
        local present = (spells[key] and spells[key].ranks ~= nil) or aura[key] ~= nil
        T.assert_true(present, key .. " is in the fixture but no longer in either catalog")
    end
end

-- ---------------------------------------------------------------------------
-- aura.lua
-- ---------------------------------------------------------------------------

--- aura.lua's arrays are the same chains under different field names, and it drifted independently:
--- `seal_of_righteousness_ranks` carried the identical wrong ten ids as spell.lua.
function M.test_every_aura_rank_array_matches_the_database_chain()
    local failures = {}
    for field, ids in pairs(aura_arrays()) do
        local alias = FIX.aura_aliases[field]
        local expect = alias and expectation(alias) or expectation(field)
        if expect then
            local ok, err = pcall(assert_chain, "aura." .. field, ids, expect)
            if not ok then table.insert(failures, tostring(err)) end
        elseif not (FIX.curated[field] or FIX.derived[field]) then
            table.insert(failures, "aura." .. field .. ": unclassified array. Add it to "
                .. "AURA_ALIASES, AURA_ONLY_ANCHORS, CURATED or DERIVED in "
                .. "sentinel/tools/regen_catalog_chain_fixture.py and regenerate")
        end
    end
    table.sort(failures)
    T.assert_equal(#failures, 0, "\n  " .. table.concat(failures, "\n  "))
end

--- `all_frozen_debuffs` is a union, not a chain. It is also the array the frozen-target gating
--- reads, so it going stale while its three sources are fixed is a live regression -- which is
--- what a hand-maintained union invites.
function M.test_derived_unions_equal_the_concatenation_of_their_sources()
    local arrays = aura_arrays()
    for field, sources in pairs(FIX.derived) do
        local expect = {}
        for _, src in ipairs(sources) do
            T.assert_true(arrays[src] ~= nil, field .. " names a source that does not exist: " .. src)
            for _, id in ipairs(arrays[src]) do table.insert(expect, id) end
        end
        T.assert_equal(fmt(arrays[field] or {}), fmt(expect),
            "aura." .. field .. " must be " .. table.concat(sources, " .. ") .. ", in order")
    end
end

-- ---------------------------------------------------------------------------
-- The fixture itself
-- ---------------------------------------------------------------------------

--- The one check that can catch a HAND-EDITED fixture: the database orders every chain by
--- `spell_chain.rank`, and that order was measured to coincide with ascending BaseLevel for all
--- 37 chains. Rank-array order is load-bearing -- the resolvers read the highest INDEX as the
--- highest RANK -- so a fixture whose levels descend has been edited by hand, not generated.
function M.test_fixture_chains_ascend_by_base_level()
    for _, section in ipairs({ FIX.chains, FIX.unchained }) do
        for key, entry in pairs(section) do
            T.assert_equal(#entry.ids, #entry.levels, key .. ": one BaseLevel per id")
            for i = 2, #entry.levels do
                T.assert_true(entry.levels[i] >= entry.levels[i - 1],
                    key .. ": BaseLevel must not descend -- index " .. i .. " is "
                    .. entry.levels[i] .. " after " .. entry.levels[i - 1]
                    .. ". A generated fixture cannot look like this.")
            end
            T.assert_equal(#entry.names, 1,
                key .. ": every id in one chain must share one SpellName, got "
                .. table.concat(entry.names, " / ")
                .. " -- an array mixing two spells is the seal_of_righteousness bug")
        end
    end
end

return M
