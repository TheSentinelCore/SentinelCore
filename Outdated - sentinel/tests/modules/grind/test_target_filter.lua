local TargetFilter = require("modules/grind/target_filter")
local T = require("tests/test_util")

local M = {}

local function mock_unit(opts)
    return {
        get_position = function() return { x = opts.x or 0, y = opts.y or 0, z = opts.z or 0 } end,
        get_level = function() return opts.level or 10 end,
        get_name = function() return opts.name or "Mob" end,
        get_npc_id = function() return opts.npc_id or 0 end,
        get_creature_type = function() return opts.creature_type or 7 end,
        get_classification = function() return opts.classification or 0 end,
        is_alive = function() return opts.alive ~= false end,
    }
end

local function mock_player()
    return {
        can_attack = function(self, unit) return true end,
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
    local player = mock_player()

    -- Valid mob passes filter
    local valid = mock_unit({ x = 10, y = 10, z = 0, level = 10, name = "Zhevra" })
    T.assert_true(TargetFilter.passes(valid, spot, 10, player), "valid mob passes filter")

    -- Dead mob fails
    local dead = mock_unit({ alive = false })
    T.assert_false(TargetFilter.passes(dead, spot, 10, player), "dead mob fails filter")

    -- Elite mob fails (classification 1)
    local elite = mock_unit({ classification = 1 })
    T.assert_false(TargetFilter.passes(elite, spot, 10, player), "elite mob fails filter")

    -- Rare mob fails (classification 4)
    local rare = mock_unit({ classification = 4 })
    T.assert_false(TargetFilter.passes(rare, spot, 10, player), "rare mob fails filter")

    -- Out of level range fails (too low)
    local low_level = mock_unit({ level = 3 })
    T.assert_false(TargetFilter.passes(low_level, spot, 10, player), "mob below level_min fails")

    -- Out of level range fails (too high)
    local high_level = mock_unit({ level = 25 })
    T.assert_false(TargetFilter.passes(high_level, spot, 10, player), "mob above level_max fails")

    -- Boundary levels pass
    local at_min = mock_unit({ level = 5 })
    T.assert_true(TargetFilter.passes(at_min, spot, 10, player), "mob at level_min passes")

    local at_max = mock_unit({ level = 20 })
    T.assert_true(TargetFilter.passes(at_max, spot, 10, player), "mob at level_max passes")

    -- Out of radius fails
    local far = mock_unit({ x = 200, y = 200, z = 0, level = 10 })
    T.assert_false(TargetFilter.passes(far, spot, 10, player), "mob out of radius fails")

    -- Blacklisted mob fails
    local bl_spot = make_spot({ mob_blacklist = { "Savannah Prowler" } })
    local blacklisted = mock_unit({ name = "Savannah Prowler", level = 10 })
    T.assert_false(TargetFilter.passes(blacklisted, bl_spot, 10, player), "blacklisted mob fails")

    -- Non-blacklisted mob passes with blacklist present
    local not_blacklisted = mock_unit({ name = "Zhevra", level = 10 })
    T.assert_true(TargetFilter.passes(not_blacklisted, bl_spot, 10, player), "non-blacklisted mob passes")

    -- Whitelist filtering: non-empty whitelist rejects unlisted mobs
    local wl_spot = make_spot({ mob_whitelist = { "Sunscale Raptor" } })
    local unlisted = mock_unit({ name = "Zhevra", level = 10 })
    T.assert_false(TargetFilter.passes(unlisted, wl_spot, 10, player), "unlisted mob rejected by whitelist")

    -- Whitelist filtering: whitelisted mob passes
    local listed = mock_unit({ name = "Sunscale Raptor", level = 10 })
    T.assert_true(TargetFilter.passes(listed, wl_spot, 10, player), "whitelisted mob passes")

    -- Empty whitelist does not filter
    local empty_wl_spot = make_spot({ mob_whitelist = {} })
    local any_mob = mock_unit({ name = "Anything", level = 10 })
    T.assert_true(TargetFilter.passes(any_mob, empty_wl_spot, 10, player), "empty whitelist does not filter")

    -- select_best picks closest valid mob
    local player_pos = { x = 0, y = 0, z = 0 }
    local close = mock_unit({ x = 5, y = 0, z = 0, level = 10, name = "Close" })
    local mid = mock_unit({ x = 20, y = 0, z = 0, level = 10, name = "Mid" })
    local far_valid = mock_unit({ x = 50, y = 0, z = 0, level = 10, name = "Far" })
    local best = TargetFilter.select_best({ far_valid, mid, close }, spot, 10, player_pos, player)
    T.assert_not_nil(best, "select_best returns a unit")
    T.assert_equal(best:get_name(), "Close", "select_best picks closest")

    -- select_best skips blacklisted mobs
    local bl_spot2 = make_spot({ mob_blacklist = { "Close" } })
    local best2 = TargetFilter.select_best({ far_valid, mid, close }, bl_spot2, 10, player_pos, player)
    T.assert_not_nil(best2, "select_best returns a unit when closest is blacklisted")
    T.assert_equal(best2:get_name(), "Mid", "select_best picks next closest after blacklisted")

    -- select_best returns nil when no valid units
    local all_dead = { mock_unit({ alive = false }), mock_unit({ alive = false }) }
    local none = TargetFilter.select_best(all_dead, spot, 10, player_pos, player)
    T.assert_true(none == nil, "select_best returns nil when no valid units")

    -- NpcRef blacklist: unit with matching npc_id -> fails
    local npc_bl_spot = make_spot({
        mob_blacklist = { { npc_id = 100, name = "Bad Mob" } },
    })
    local npc_bl_unit = mock_unit({ npc_id = 100, name = "Bad Mob", level = 10 })
    T.assert_false(TargetFilter.passes(npc_bl_unit, npc_bl_spot, 10, player), "NpcRef blacklist by npc_id should fail")

    -- NpcRef blacklist fallback: unit with npc_id=0, matching name -> fails
    local npc_bl_name_unit = mock_unit({ npc_id = 0, name = "Bad Mob", level = 10 })
    T.assert_false(TargetFilter.passes(npc_bl_name_unit, npc_bl_spot, 10, player), "NpcRef blacklist name fallback should fail")

    -- NpcRef whitelist: unit with matching npc_id -> passes
    local npc_wl_spot = make_spot({
        mob_whitelist = { { npc_id = 200, name = "Good Mob" } },
    })
    local npc_wl_unit = mock_unit({ npc_id = 200, name = "Good Mob", level = 10 })
    T.assert_true(TargetFilter.passes(npc_wl_unit, npc_wl_spot, 10, player), "NpcRef whitelist by npc_id should pass")

    -- creature_types filter: unit with matching creature_type -> passes
    local ct_spot = make_spot({ creature_types = { 1, 7 } })
    local ct_match = mock_unit({ creature_type = 1, level = 10 })
    T.assert_true(TargetFilter.passes(ct_match, ct_spot, 10, player), "creature_type 1 in {1,7} should pass")

    -- creature_types filter: unit with non-matching creature_type -> fails
    local ct_miss = mock_unit({ creature_type = 3, level = 10 })
    T.assert_false(TargetFilter.passes(ct_miss, ct_spot, 10, player), "creature_type 3 not in {1,7} should fail")

    -- Empty creature_types doesn't filter
    local ct_empty_spot = make_spot({ creature_types = {} })
    local ct_any = mock_unit({ creature_type = 5, level = 10 })
    T.assert_true(TargetFilter.passes(ct_any, ct_empty_spot, 10, player), "empty creature_types should not filter")

    -- Blackspot filter: unit inside blackspot -> fails
    local bs_spot = make_spot({
        blackspots = { { x = 10, y = 10, z = 0, radius = 5 } },
    })
    local bs_inside = mock_unit({ x = 10, y = 10, z = 0, level = 10 })
    T.assert_false(TargetFilter.passes(bs_inside, bs_spot, 10, player), "unit inside blackspot should fail")

    -- Blackspot filter: unit outside blackspot -> passes
    local bs_outside = mock_unit({ x = 50, y = 50, z = 0, level = 10 })
    T.assert_true(TargetFilter.passes(bs_outside, bs_spot, 10, player), "unit outside blackspot should pass")

    -- Threat heat scoring: equidistant units, one in threat zone
    local ThreatMap = require("modules/grind/threat_map")
    local tm = ThreatMap:new()
    -- Record heavy threat at (20, 0, 0)
    tm:record("DEATH", { x = 20, y = 0, z = 0 }, 20, 1000)
    local threat_unit = mock_unit({ x = 20, y = 0, z = 0, level = 10, name = "ThreatUnit" })
    local safe_unit = mock_unit({ x = 0, y = 20, z = 0, level = 10, name = "SafeUnit" })
    local threat_opts = { threat_map = tm, now_ms = 1000 }
    local threat_best = TargetFilter.select_best(
        { threat_unit, safe_unit }, spot, 10, player_pos, player, threat_opts
    )
    T.assert_not_nil(threat_best, "threat scoring returns a unit")
    T.assert_equal(threat_best:get_name(), "SafeUnit", "select_best prefers units away from threat")

    -- select_best works normally with nil opts (backward compatible)
    local compat_best = TargetFilter.select_best({ close, mid }, spot, 10, player_pos, player, nil)
    T.assert_not_nil(compat_best, "select_best works with nil opts")

    -- Cluster scoring: units in same cell should have higher cluster count
    -- Place 3 units close together in same grid cell (within 10yd)
    local cluster_a = mock_unit({ x = 5, y = 5, z = 0, level = 10, name = "ClusterA" })
    local cluster_b = mock_unit({ x = 6, y = 5, z = 0, level = 10, name = "ClusterB" })
    local cluster_c = mock_unit({ x = 5, y = 6, z = 0, level = 10, name = "ClusterC" })
    -- Place isolated unit far away
    local isolated = mock_unit({ x = 50, y = 50, z = 0, level = 10, name = "Isolated" })

    -- The isolated unit should be preferred over clustered units (lower cluster penalty)
    local cluster_best = TargetFilter.select_best(
        { cluster_a, cluster_b, cluster_c, isolated }, spot, 10, player_pos, player
    )
    T.assert_not_nil(cluster_best, "cluster scoring returns a unit")
    T.assert_equal(cluster_best:get_name(), "Isolated", "select_best prefers isolated unit over clustered units")
end

return M
