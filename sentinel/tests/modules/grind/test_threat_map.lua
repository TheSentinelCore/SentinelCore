local ThreatMap = require("modules/grind/threat_map")
local T = require("tests/test_util")

local M = {}

function M.run()
    -- -------------------------------------------------------
    -- Record and retrieve heat at a position
    -- -------------------------------------------------------
    local tm = ThreatMap:new()
    local pos = { x = 100, y = 100, z = 0 }
    tm:record("DEATH", pos, 5.0, 0)

    T.assert_equal(tm:entry_count(), 1, "should have 1 entry after recording")

    local heat = tm:get_heat(pos, 60, 0)
    T.assert_equal(heat, 5.0, "heat at same position at t=0 should equal weight")

    -- -------------------------------------------------------
    -- Heat decays over time (half-life based exponential decay)
    -- -------------------------------------------------------
    local tm2 = ThreatMap:new()
    local pos2 = { x = 50, y = 50, z = 0 }
    tm2:record("DEATH", pos2, 8.0, 0) -- DEATH half-life = 30 min = 1,800,000 ms

    -- After exactly one half-life, weight should be halved
    local heat_half = tm2:get_heat(pos2, 60, 1800000)
    local expected_half = 4.0
    local diff_half = math.abs(heat_half - expected_half)
    T.assert_true(diff_half < 0.01,
        "heat after one DEATH half-life should be ~4.0, got " .. tostring(heat_half))

    -- After two half-lives, weight should be quartered
    local heat_quarter = tm2:get_heat(pos2, 60, 3600000)
    local expected_quarter = 2.0
    local diff_quarter = math.abs(heat_quarter - expected_quarter)
    T.assert_true(diff_quarter < 0.01,
        "heat after two DEATH half-lives should be ~2.0, got " .. tostring(heat_quarter))

    -- -------------------------------------------------------
    -- Heat is zero for positions far away from any entries
    -- -------------------------------------------------------
    local tm3 = ThreatMap:new()
    tm3:record("DEATH", { x = 0, y = 0, z = 0 }, 10.0, 0)

    local far_pos = { x = 500, y = 500, z = 0 }
    local heat_far = tm3:get_heat(far_pos, 60, 0)
    T.assert_equal(heat_far, 0, "heat far from any entry should be 0")

    -- -------------------------------------------------------
    -- is_dangerous() threshold check
    -- -------------------------------------------------------
    local tm4 = ThreatMap:new()
    local danger_pos = { x = 200, y = 200, z = 0 }

    -- Below threshold (DANGER_THRESHOLD = 8)
    tm4:record("DEATH", danger_pos, 5.0, 0)
    T.assert_false(tm4:is_dangerous(danger_pos, 0),
        "weight 5 should NOT be dangerous (threshold is 8)")

    -- At threshold exactly
    tm4:record("DEATH", danger_pos, 3.0, 0)
    local is_at = tm4:is_dangerous(danger_pos, 0)
    -- total heat = 5 + 3 = 8, which is NOT > 8
    T.assert_false(is_at,
        "weight exactly 8 should NOT be dangerous (must exceed threshold)")

    -- Above threshold
    tm4:record("DEATH", danger_pos, 1.0, 0)
    T.assert_true(tm4:is_dangerous(danger_pos, 0),
        "weight 9 should be dangerous (exceeds threshold 8)")

    -- -------------------------------------------------------
    -- get_safest_hotspot() picks hotspot with lowest heat
    -- -------------------------------------------------------
    local tm5 = ThreatMap:new()
    tm5:record("DEATH", { x = 100, y = 100, z = 0 }, 10.0, 0)
    tm5:record("DEATH", { x = 300, y = 300, z = 0 }, 2.0, 0)

    local hotspots = {
        { center = { x = 100, y = 100, z = 0 }, radius = 40 },
        { center = { x = 300, y = 300, z = 0 }, radius = 40 },
        { center = { x = 500, y = 500, z = 0 }, radius = 40 },
    }

    local safest = tm5:get_safest_hotspot(hotspots, 0)
    T.assert_equal(safest, 3,
        "hotspot 3 (no threats nearby) should be safest")

    -- -------------------------------------------------------
    -- gc() removes fully-decayed entries
    -- -------------------------------------------------------
    local tm6 = ThreatMap:new()
    tm6:record("PVP_PLAYER", { x = 0, y = 0, z = 0 }, 1.0, 0)
    -- PVP_PLAYER half-life = 10 min = 600,000 ms
    -- After enough half-lives, weight < 0.1 (GC_MIN_WEIGHT)
    -- 1.0 * 2^(-t/600000) < 0.1  =>  t > 600000 * log2(10) ~ 1,993,157 ms
    -- Use ~2,000,000 ms to be safe

    T.assert_equal(tm6:entry_count(), 1, "should have 1 entry before gc")
    tm6:gc(2000000)
    T.assert_equal(tm6:entry_count(), 0,
        "gc should remove entry decayed below 0.1")

    -- Verify gc keeps entries that are still significant
    local tm6b = ThreatMap:new()
    tm6b:record("DEATH", { x = 0, y = 0, z = 0 }, 10.0, 0)
    tm6b:gc(0)
    T.assert_equal(tm6b:entry_count(), 1,
        "gc should NOT remove entry with weight 10 at t=0")

    -- -------------------------------------------------------
    -- Different threat types have different half-lives
    -- -------------------------------------------------------
    local tm7 = ThreatMap:new()
    local shared_pos = { x = 0, y = 0, z = 0 }

    -- PVP_PLAYER: half-life = 10 min (600,000 ms)
    tm7:record("PVP_PLAYER", shared_pos, 8.0, 0)
    local pvp_heat = tm7:get_heat(shared_pos, 60, 600000)
    local pvp_diff = math.abs(pvp_heat - 4.0)
    T.assert_true(pvp_diff < 0.01,
        "PVP_PLAYER heat after 10min should be ~4.0, got " .. tostring(pvp_heat))

    -- Separate map for DEATH comparison
    local tm7b = ThreatMap:new()
    tm7b:record("DEATH", shared_pos, 8.0, 0)
    -- DEATH half-life = 30 min (1,800,000 ms) -- at 600,000 ms it's only 1/3 of a half-life
    local death_heat = tm7b:get_heat(shared_pos, 60, 600000)
    -- effective = 8 * 2^(-600000/1800000) = 8 * 2^(-1/3) ~ 8 * 0.7937 ~ 6.35
    T.assert_true(death_heat > 6.0,
        "DEATH heat after 10min should still be >6.0 (longer half-life), got " .. tostring(death_heat))
    T.assert_true(death_heat < 7.0,
        "DEATH heat after 10min should be <7.0, got " .. tostring(death_heat))

    -- -------------------------------------------------------
    -- Multiple entries within radius aggregate
    -- -------------------------------------------------------
    local tm8 = ThreatMap:new()
    local center = { x = 100, y = 100, z = 0 }
    tm8:record("DEATH", { x = 105, y = 100, z = 0 }, 3.0, 0)
    tm8:record("DEATH", { x = 100, y = 105, z = 0 }, 4.0, 0)
    local agg_heat = tm8:get_heat(center, 60, 0)
    T.assert_equal(agg_heat, 7.0,
        "heat should aggregate entries within radius: 3+4=7")

    -- -------------------------------------------------------
    -- get_safest_hotspot with single hotspot returns 1
    -- -------------------------------------------------------
    local tm9 = ThreatMap:new()
    local single = { { center = { x = 0, y = 0, z = 0 }, radius = 40 } }
    T.assert_equal(tm9:get_safest_hotspot(single, 0), 1,
        "single hotspot should return index 1")

    -- -------------------------------------------------------
    -- get_safest_hotspot with empty list returns nil
    -- -------------------------------------------------------
    local tm10 = ThreatMap:new()
    local empty_result = tm10:get_safest_hotspot({}, 0)
    T.assert_equal(empty_result, nil,
        "empty hotspot list should return nil")
end

return M
