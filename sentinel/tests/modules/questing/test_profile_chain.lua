-- tests/modules/questing/test_profile_chain.lua
-- Pins the chain-resolution semantics against the real manifest shapes emitted
-- by SentinelQuesting/tools/build_chain_manifest.py: multi-option fallbacks,
-- line- and option-level class guards, guarded target entries, chain ends.

local ProfileChain = require("modules/questing/profile_chain")
local T = require("tests/test_util")

local M = {}

local function manifest()
    return {
        entries = {
            ["1-11-Elwynn-Forest"] = {
                name = "1-11 Elwynn Forest",
                next = {
                    { slug = "12-14-Loch-Modan", class_only = "Warlock" },
                    { slug = "11-12-Loch-Modan", class_not = "Warlock" },
                    { slug = "12-14-Darkshore", class_not = "Warlock" },
                },
            },
            -- The Warlock variant registers under its own guarded entry.
            ["12-14-Loch-Modan"] = { name = "12-14 Loch Modan", class_only = "Warlock", next = {} },
            ["11-12-Loch-Modan"] = {
                name = "11-12 Loch Modan",
                class_not = "Warlock",
                next = { { slug = "12-14-Darkshore" } },
            },
            ["12-14-Darkshore"] = {
                name = "12-14 Darkshore",
                next = { { slug = "missing-target" } },
            },
        },
    }
end

function M.test_class_guards_pick_the_right_branch()
    local m = manifest()
    T.assert_equal(ProfileChain.next_slug(m, "1-11-Elwynn-Forest", "Paladin"),
        "11-12-Loch-Modan", "non-warlock takes the !Warlock branch")
    T.assert_equal(ProfileChain.next_slug(m, "1-11-Elwynn-Forest", "Warlock"),
        "12-14-Loch-Modan", "warlock takes the Warlock branch")
end

function M.test_guarded_target_entry_blocks_ineligible_class()
    local m = manifest()
    -- Remove the link guard: the TARGET's own class_only must still exclude a Paladin.
    m.entries["1-11-Elwynn-Forest"].next = {
        { slug = "12-14-Loch-Modan" },
        { slug = "11-12-Loch-Modan" },
    }
    T.assert_equal(ProfileChain.next_slug(m, "1-11-Elwynn-Forest", "Paladin"),
        "11-12-Loch-Modan", "a target entry guarded to another class is skipped")
end

function M.test_missing_target_falls_through_and_ends_chain()
    local m = manifest()
    T.assert_equal(ProfileChain.next_slug(m, "12-14-Darkshore", "Paladin"), nil,
        "a dangling link must not resolve")
    T.assert_equal(ProfileChain.next_slug(m, "unknown-slug", "Paladin"), nil,
        "an unknown current slug ends the chain")
end

function M.test_walk_is_cycle_safe()
    local m = manifest()
    m.entries["12-14-Darkshore"].next = { { slug = "1-11-Elwynn-Forest" } }
    local order = ProfileChain.walk(m, "1-11-Elwynn-Forest", "Paladin")
    T.assert_equal(#order, 3, "a cycle terminates after visiting each entry once")
    T.assert_equal(order[1], "1-11-Elwynn-Forest")
    T.assert_equal(order[2], "11-12-Loch-Modan")
    T.assert_equal(order[3], "12-14-Darkshore")
end

function M.test_multi_class_guard_lists()
    T.assert_true(ProfileChain._eligible("Human/NightElf", nil, "Human"))
    T.assert_false(ProfileChain._eligible("Human/NightElf", nil, "Paladin"))
    T.assert_false(ProfileChain._eligible(nil, "Warlock/Mage", "Mage"))
    T.assert_true(ProfileChain._eligible(nil, "Warlock/Mage", "Paladin"))
end

function M.run()
    local names = {}
    for name in pairs(M) do
        if name:match("^test") then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(M[name])
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
