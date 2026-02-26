local T = require("tests/TestUtil")

return { run = function()
    local PackTracker = require("ai/PackTracker")

    -- Mock game objects
    local function make_mob(x, y, z, in_combat, target_guid)
        return {
            get_position = function() return { x = x, y = y, z = z } end,
            is_valid = function() return true end,
            is_dead = function() return false end,
            is_in_combat = function() return in_combat or false end,
            get_target = function()
                if target_guid then
                    return { get_guid = function() return target_guid end }
                end
                return nil
            end,
            get_guid = function() return string.format("mob_%d_%d", x, z) end,
        }
    end

    local player_guid = "player_1"
    local player_pos = { x = 0, y = 0, z = 0 }

    -- 1. Empty update
    local pt = PackTracker:new()
    pt:update({}, player_pos, player_guid)
    local pack = pt:get_pack()
    T.assert_eq(pack.count, 0, "empty pack count")

    -- 2. Single mob
    local mob1 = make_mob(5, 0, 5)
    pt:update({ mob1 }, player_pos, player_guid)
    pack = pt:get_pack()
    T.assert_eq(pack.count, 1, "one mob in pack")

    -- 3. Cluster of 4 mobs within 15yd
    local mobs = {
        make_mob(10, 0, 10),
        make_mob(12, 0, 11),
        make_mob(11, 0, 13),
        make_mob(13, 0, 12),
    }
    pt:update(mobs, player_pos, player_guid)
    pack = pt:get_pack()
    T.assert_eq(pack.count, 4, "four mobs")
    T.assert_true(pack.centroid ~= nil, "centroid computed")
    T.assert_true(pack.spread < 10, "spread is small for tight cluster")

    -- 4. Gathered count: mobs targeting player
    local gathered_mobs = {
        make_mob(5, 0, 5, true, player_guid),   -- in combat, targeting player
        make_mob(6, 0, 6, true, player_guid),   -- in combat, targeting player
        make_mob(20, 0, 20, false, nil),          -- not in combat
    }
    pt:update(gathered_mobs, player_pos, player_guid)
    pack = pt:get_pack()
    T.assert_eq(pack.count, 3, "three total mobs")
    T.assert_eq(pack.gathered_count, 2, "two gathered (targeting player)")

    -- 5. Cluster detection
    local spread_mobs = {
        -- Cluster A: around (10, 0, 10)
        make_mob(10, 0, 10),
        make_mob(11, 0, 11),
        make_mob(12, 0, 10),
        -- Cluster B: around (50, 0, 50), far from A
        make_mob(50, 0, 50),
        make_mob(51, 0, 51),
    }
    local clusters = pt:find_clusters(spread_mobs, 15)
    T.assert_eq(#clusters, 2, "two clusters detected")
    -- Clusters sorted by count desc
    T.assert_eq(clusters[1].count, 3, "first cluster has 3")
    T.assert_eq(clusters[2].count, 2, "second cluster has 2")

    -- 6. Nearest distance
    local near_mobs = {
        make_mob(3, 0, 0),   -- 3yd away
        make_mob(10, 0, 0),  -- 10yd away
    }
    pt:update(near_mobs, player_pos, player_guid)
    pack = pt:get_pack()
    T.assert_true(pack.nearest_dist <= 3.1 and pack.nearest_dist >= 2.9, "nearest ~3yd")

    return true
end }
