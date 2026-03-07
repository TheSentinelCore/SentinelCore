local TargetFilter = require("modules/grind/target_filter")
local T = require("tests/test_util")

local M = {}

local function mock_unit(opts)
    return {
        get_position = function() return opts.x or 0, opts.y or 0, opts.z or 0 end,
        get_level = function() return opts.level or 10 end,
        get_name = function() return opts.name or "Mob" end,
        is_alive = function() return opts.alive ~= false end,
        is_tapped_by_other = function() return opts.tapped or false end,
        is_elite = function() return opts.elite or false end,
        is_rare = function() return opts.rare or false end,
    }
end

local function make_spot(overrides)
    local spot = {
        center = { x = 0, y = 0, z = 0 },
        radius = 100,
        level_min = 5,
        level_max = 20,
        mob_blacklist = {},
        mob_whitelist = {},
    }
    if overrides then
        for k, v in pairs(overrides) do
            spot[k] = v
        end
    end
    return spot
end

function M.run()
    local spot = make_spot()

    -- Valid mob passes filter
    local valid = mock_unit({ x = 10, y = 10, z = 0, level = 10, name = "Zhevra" })
    T.assert_true(TargetFilter.passes(valid, spot, 10), "valid mob passes filter")

    -- Dead mob fails
    local dead = mock_unit({ alive = false })
    T.assert_false(TargetFilter.passes(dead, spot, 10), "dead mob fails filter")

    -- Tapped mob fails
    local tapped = mock_unit({ tapped = true })
    T.assert_false(TargetFilter.passes(tapped, spot, 10), "tapped mob fails filter")

    -- Elite mob fails
    local elite = mock_unit({ elite = true })
    T.assert_false(TargetFilter.passes(elite, spot, 10), "elite mob fails filter")

    -- Rare mob fails
    local rare = mock_unit({ rare = true })
    T.assert_false(TargetFilter.passes(rare, spot, 10), "rare mob fails filter")

    -- Out of level range fails (too low)
    local low_level = mock_unit({ level = 3 })
    T.assert_false(TargetFilter.passes(low_level, spot, 10), "mob below level_min fails")

    -- Out of level range fails (too high)
    local high_level = mock_unit({ level = 25 })
    T.assert_false(TargetFilter.passes(high_level, spot, 10), "mob above level_max fails")

    -- Boundary levels pass
    local at_min = mock_unit({ level = 5 })
    T.assert_true(TargetFilter.passes(at_min, spot, 10), "mob at level_min passes")

    local at_max = mock_unit({ level = 20 })
    T.assert_true(TargetFilter.passes(at_max, spot, 10), "mob at level_max passes")

    -- Out of radius fails
    local far = mock_unit({ x = 200, y = 200, z = 0, level = 10 })
    T.assert_false(TargetFilter.passes(far, spot, 10), "mob out of radius fails")

    -- Blacklisted mob fails
    local bl_spot = make_spot({ mob_blacklist = { "Savannah Prowler" } })
    local blacklisted = mock_unit({ name = "Savannah Prowler", level = 10 })
    T.assert_false(TargetFilter.passes(blacklisted, bl_spot, 10), "blacklisted mob fails")

    -- Non-blacklisted mob passes with blacklist present
    local not_blacklisted = mock_unit({ name = "Zhevra", level = 10 })
    T.assert_true(TargetFilter.passes(not_blacklisted, bl_spot, 10), "non-blacklisted mob passes")

    -- Whitelist filtering: non-empty whitelist rejects unlisted mobs
    local wl_spot = make_spot({ mob_whitelist = { "Sunscale Raptor" } })
    local unlisted = mock_unit({ name = "Zhevra", level = 10 })
    T.assert_false(TargetFilter.passes(unlisted, wl_spot, 10), "unlisted mob rejected by whitelist")

    -- Whitelist filtering: whitelisted mob passes
    local listed = mock_unit({ name = "Sunscale Raptor", level = 10 })
    T.assert_true(TargetFilter.passes(listed, wl_spot, 10), "whitelisted mob passes")

    -- Empty whitelist does not filter
    local empty_wl_spot = make_spot({ mob_whitelist = {} })
    local any_mob = mock_unit({ name = "Anything", level = 10 })
    T.assert_true(TargetFilter.passes(any_mob, empty_wl_spot, 10), "empty whitelist does not filter")

    -- select_best picks closest valid mob
    local player_pos = { x = 0, y = 0, z = 0 }
    local close = mock_unit({ x = 5, y = 0, z = 0, level = 10, name = "Close" })
    local mid = mock_unit({ x = 20, y = 0, z = 0, level = 10, name = "Mid" })
    local far_valid = mock_unit({ x = 50, y = 0, z = 0, level = 10, name = "Far" })
    local best = TargetFilter.select_best({ far_valid, mid, close }, spot, 10, player_pos)
    T.assert_not_nil(best, "select_best returns a unit")
    T.assert_equal(best:get_name(), "Close", "select_best picks closest")

    -- select_best skips blacklisted mobs
    local bl_spot2 = make_spot({ mob_blacklist = { "Close" } })
    local best2 = TargetFilter.select_best({ far_valid, mid, close }, bl_spot2, 10, player_pos)
    T.assert_not_nil(best2, "select_best returns a unit when closest is blacklisted")
    T.assert_equal(best2:get_name(), "Mid", "select_best picks next closest after blacklisted")

    -- select_best returns nil when no valid units
    local all_dead = { mock_unit({ alive = false }), mock_unit({ alive = false }) }
    local none = TargetFilter.select_best(all_dead, spot, 10, player_pos)
    T.assert_true(none == nil, "select_best returns nil when no valid units")
end

return M
