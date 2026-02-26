local T = require("tests/TestUtil")

return { run = function()
    local PerformanceAdvisor = require("ai/PerformanceAdvisor")
    local EventBus = require("events/EventBus")

    -- Helper: build a telemetry.flushed payload
    local function make_payload(kills, deaths, xp)
        return { snapshot = { kills = kills, deaths = deaths, xp_gained = xp } }
    end

    -- 1. new — creates with empty stats, biases return 1.0
    do
        local advisor = PerformanceAdvisor:new(nil)
        T.assert_true(advisor ~= nil, "advisor created")
        T.assert_eq(advisor:get_bias("anything"), 1.0, "default bias is 1.0")
        T.assert_eq(advisor:get_stats("anything"), nil, "no stats initially")
    end

    -- 2. set_active_tactic — sets active name
    do
        local advisor = PerformanceAdvisor:new(nil)
        advisor:set_active_tactic("aoe_kite")
        T.assert_eq(advisor._active_tactic, "aoe_kite", "active tactic set")
    end

    -- 3. _on_telemetry — accumulates kills/deaths/xp to active tactic
    do
        local advisor = PerformanceAdvisor:new(nil)
        advisor:set_active_tactic("single")

        -- First call: sets last_snapshot, no delta yet
        advisor:_on_telemetry(make_payload(0, 0, 0))
        local stats = advisor:get_stats("single")
        T.assert_true(stats ~= nil, "stats created after first telemetry")
        T.assert_eq(stats.kills, 0, "no kills on first tick (no previous snapshot)")

        -- Second call: delta of 5 kills, 1 death, 500 xp
        advisor:_on_telemetry(make_payload(5, 1, 500))
        stats = advisor:get_stats("single")
        T.assert_eq(stats.kills, 5, "5 kills accumulated")
        T.assert_eq(stats.deaths, 1, "1 death accumulated")
        T.assert_eq(stats.xp_gained, 500, "500 xp accumulated")
        T.assert_eq(stats.active_secs, 1, "1 active second (one delta tick)")

        -- Third call: delta of 3 more kills, 0 deaths, 300 xp
        advisor:_on_telemetry(make_payload(8, 1, 800))
        stats = advisor:get_stats("single")
        T.assert_eq(stats.kills, 8, "8 total kills")
        T.assert_eq(stats.deaths, 1, "still 1 death (no new deaths)")
        T.assert_eq(stats.xp_gained, 800, "800 total xp")
        T.assert_eq(stats.active_secs, 2, "2 active seconds")
    end

    -- 4. _on_telemetry — ignores data when no active tactic
    do
        local advisor = PerformanceAdvisor:new(nil)
        -- No active tactic set
        advisor:_on_telemetry(make_payload(0, 0, 0))
        advisor:_on_telemetry(make_payload(10, 0, 1000))
        -- No stats should exist for any tactic
        T.assert_eq(advisor:get_stats("single"), nil, "no stats when no active tactic")
        -- But last_snapshot should be saved
        T.assert_true(advisor._last_snapshot ~= nil, "last_snapshot saved even without active tactic")
    end

    -- 5. _recompute_biases — better tactic gets higher bias, worse gets lower
    do
        local advisor = PerformanceAdvisor:new(nil)
        advisor._min_sample_secs = 2  -- lower threshold for testing

        -- Simulate "good" tactic: 0 deaths, high xp
        advisor:set_active_tactic("good")
        advisor:_on_telemetry(make_payload(0, 0, 0))
        advisor:_on_telemetry(make_payload(10, 0, 1000))
        advisor:_on_telemetry(make_payload(20, 0, 2000))
        -- good: kills=20, deaths=0, xp=2000, active_secs=2

        -- Simulate "bad" tactic: lots of deaths, low xp
        advisor:set_active_tactic("bad")
        advisor:_on_telemetry(make_payload(20, 0, 2000))  -- first tick for "bad", sets baseline
        advisor:_on_telemetry(make_payload(22, 3, 2200))
        advisor:_on_telemetry(make_payload(24, 6, 2400))
        -- bad: kills=4, deaths=6, xp=400, active_secs=2
        -- effective_xp: good = 2000 - 0*300 = 2000, bad = 400 - 6*300 = -1400 -> clamped to 0.001
        -- score: good = 2000/2 = 1000, bad = 0.001/2 = 0.0005
        -- max_score = 1000
        -- good ratio = 1.0 -> bias = 0.8 + 0.4*1.0 = 1.2
        -- bad ratio = 0.0005/1000 ≈ 0.0 -> bias ≈ 0.8

        local good_bias = advisor:get_bias("good")
        local bad_bias = advisor:get_bias("bad")
        T.assert_true(good_bias > 1.15 and good_bias < 1.25,
            "good tactic bias ~1.2, got " .. tostring(good_bias))
        T.assert_true(bad_bias >= 0.79 and bad_bias < 0.85,
            "bad tactic bias ~0.8, got " .. tostring(bad_bias))
        T.assert_true(good_bias > bad_bias, "good bias > bad bias")
    end

    -- 6. _min_sample_secs — no bias before minimum sample
    do
        local advisor = PerformanceAdvisor:new(nil)
        -- Default min is 120; simulate only a few ticks
        advisor:set_active_tactic("short")
        advisor:_on_telemetry(make_payload(0, 0, 0))
        for i = 1, 10 do
            advisor:_on_telemetry(make_payload(i * 5, 0, i * 500))
        end
        -- 10 active_secs < 120 min_sample_secs
        T.assert_eq(advisor:get_bias("short"), 1.0,
            "no bias before min_sample_secs (default 1.0 returned)")
        local stats = advisor:get_stats("short")
        T.assert_eq(stats.active_secs, 10, "10 active seconds accumulated")
    end

    -- 7. reset — clears all stats and biases
    do
        local advisor = PerformanceAdvisor:new(nil)
        advisor._min_sample_secs = 1
        advisor:set_active_tactic("t1")
        advisor:_on_telemetry(make_payload(0, 0, 0))
        advisor:_on_telemetry(make_payload(10, 0, 1000))
        T.assert_true(advisor:get_stats("t1") ~= nil, "stats exist before reset")

        advisor:reset()
        T.assert_eq(advisor:get_stats("t1"), nil, "stats cleared after reset")
        T.assert_eq(advisor:get_bias("t1"), 1.0, "bias reset to default")
        T.assert_eq(advisor._active_tactic, nil, "active tactic cleared")
        T.assert_eq(advisor._last_snapshot, nil, "last snapshot cleared")
    end

    -- 8. EventBus integration — emit telemetry.flushed, verify advisor receives it
    do
        local bus = EventBus:new()
        local advisor = PerformanceAdvisor:new(bus)
        advisor:set_active_tactic("integrated")

        -- Emit first snapshot to establish baseline
        bus:emit("telemetry.flushed", make_payload(0, 0, 0))
        -- Emit second snapshot with delta
        bus:emit("telemetry.flushed", make_payload(7, 0, 700))

        local stats = advisor:get_stats("integrated")
        T.assert_true(stats ~= nil, "stats created via EventBus")
        T.assert_eq(stats.kills, 7, "7 kills via EventBus")
        T.assert_eq(stats.xp_gained, 700, "700 xp via EventBus")
        T.assert_eq(stats.active_secs, 1, "1 active second via EventBus")

        -- destroy unsubscribes
        advisor:destroy()
        bus:emit("telemetry.flushed", make_payload(20, 0, 2000))
        -- Stats should NOT have changed (unsubscribed)
        stats = advisor:get_stats("integrated")
        T.assert_eq(stats.kills, 7, "no new kills after destroy")
    end

    return true
end }
