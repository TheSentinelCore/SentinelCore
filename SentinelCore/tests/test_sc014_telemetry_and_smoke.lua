local T = require("tests/TestUtil")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

local function run()
    local player = T.mock_object({
        level = 20,
        class_id = 2,
        spec_id = 0,
        position = { x = 10, y = 20, z = 30 },
        xp = 500,
        max_xp = 1000,
    })

    local env = T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return {} end,
        },
    })

    local Client = require("core/Client")
    local SmokeSuite = require("tests/smoke_suite")

    local fake_nav = {
        update = function() end,
        is_available = function() return true, nil end,
        is_server_available = function() return true end,
        stop = function() end,
        move_to = function(_, _, cb) if cb then cb(true, nil, nil) end end,
        estimate_path_cost = function(_, _, _, cb) cb(true, 10, nil) end,
    }

    local fake_world = {
        update = function() end,
        resolve_context = function(_, _, cb)
            cb(true, { map_id = 530, zone_id = 3518, area_id = 3520, confidence = 1.0 }, nil)
        end,
    }

    local client = Client:new({
        navigation_adapter = fake_nav,
        world_data_adapter = fake_world,
        runtime_overrides = {
            telemetry = { flush_interval = 0.1 },
            runtime = { context_resolve_interval = 0.1, dependency_health_interval = 0.1 },
        },
    })

    local ok = client:start("grind")
    T.assert_true(ok == true, "client start failed")

    local bus = client:get_event_bus()
    local flush_count = 0
    local last_flush = nil
    bus:on(Events.TELEMETRY_FLUSHED, function(data)
        flush_count = flush_count + 1
        last_flush = data
    end, { owner = "sc014" })

    env.core._set_time(1000.1)
    client:update()

    bus:emit(Events.KILL_CONFIRMED, {})
    bus:emit(Events.LOOT_COMPLETED, {})
    bus:emit(Events.VENDOR_COMPLETED, {})
    bus:emit(Events.ROTATION_BLOCKED, {
        error_code = ErrorCodes.CAST_GUARD_BLOCKED,
        blocked = {
            { reason = ErrorCodes.CAST_GUARD_BLOCKED, spell_id = 20271, action_type = "cast_spell_target" },
            { reason = ErrorCodes.CAST_GUARD_BLOCKED, spell_id = 35395, action_type = "cast_spell_target" },
        },
    })
    bus:emit(Events.COMBAT_FAILED, { error_code = ErrorCodes.PULL_FAILED })
    bus:emit(Events.COMBAT_FAILED, { error_code = ErrorCodes.TARGET_LOST })
    bus:emit(Events.COMBAT_CHASE_UPDATE, { phase = "combat", reason = "target_shift" })
    bus:emit(Events.COMBAT_CHASE_UPDATE, { phase = "pull", reason = "refresh" })

    env.core._set_time(1000.3)
    client:update()
    env.core._set_time(1000.7)
    client:update()
    local snap = client:get_snapshot()

    T.assert_true(type(snap.telemetry) == "table", "snapshot telemetry missing")
    T.assert_true((snap.telemetry.counters.kills or 0) >= 1, "telemetry kill counter missing")
    T.assert_true((snap.telemetry.counters.cast_guard_blocked or 0) >= 2, "telemetry cast-guard counter missing")
    T.assert_true((snap.telemetry.counters.failed_pulls or 0) >= 1, "telemetry failed pull counter missing")
    T.assert_true((snap.telemetry.counters.unreachable_targets or 0) >= 1, "telemetry unreachable target counter missing")
    T.assert_true((snap.telemetry.counters.chase_repaths or 0) >= 1, "telemetry chase repath counter missing")
    T.assert_true((snap.telemetry.counters.idle_full_resource_secs or 0) > 0, "telemetry idle full-resource timer missing")
    T.assert_true((snap.telemetry.uptime_secs or 0) > 0, "telemetry uptime missing")
    T.assert_true((snap.telemetry.rates.cast_guard_blocked_per_min or 0) > 0,
        "telemetry cast-guard rate missing")
    T.assert_true((snap.telemetry.rates.chase_repaths_per_min or 0) > 0, "telemetry chase repath rate missing")
    T.assert_true((snap.telemetry.rates.combat_downtime_avg_secs or 0) >= 0, "telemetry combat downtime metric missing")
    local by_spell = snap.telemetry.rates.cast_guard_blocked_per_min_by_spell or {}
    T.assert_true(type(by_spell) == "table" and tonumber(by_spell[20271] or 0) > 0,
        "telemetry should expose cast-guard per-minute map by spell id")
    local bb = client:get_blackboard()
    T.assert_true((tonumber(bb:get("telemetry.rates.deaths_per_hour", -1)) or -1) >= 0,
        "telemetry should publish deaths/hour to blackboard")
    T.assert_true((tonumber(bb:get("telemetry.rates.cast_guard_blocked_per_min", 0)) or 0) > 0,
        "telemetry should publish cast-guard blocked/min to blackboard")
    T.assert_true((tonumber(bb:get("telemetry.rates.failed_pulls_per_hour", 0)) or 0) > 0,
        "telemetry should publish failed pulls/hour to blackboard")
    T.assert_true((tonumber(bb:get("telemetry.rates.unreachable_targets_per_hour", 0)) or 0) > 0,
        "telemetry should publish unreachable targets/hour to blackboard")
    T.assert_true((tonumber(bb:get("telemetry.rates.idle_full_resource_pct", 0)) or 0) > 0,
        "telemetry should publish idle full-resource percentage to blackboard")
    T.assert_true(snap.context.map_id == 530, "snapshot canonical map missing")
    T.assert_true(flush_count >= 1 and type(last_flush) == "table", "telemetry flush event missing")
    T.assert_true(type(last_flush.counters) == "table", "flush payload counters missing")
    T.assert_true(type(last_flush.rates) == "table", "flush payload rates missing")

    local smoke = SmokeSuite.run()
    T.assert_true(type(smoke) == "table", "smoke suite did not return results")
    T.assert_true(smoke.start_here_grind_loop_stability == true, "smoke: start_here_grind_loop_stability failed")
    T.assert_true(smoke.kill_loot_cycle_repeats == true, "smoke: kill_loot_cycle_repeats failed")
    T.assert_true(smoke.inventory_threshold_triggers_vendor == true, "smoke: inventory_threshold_triggers_vendor failed")
    T.assert_true(smoke.same_map_vendor_selected == true, "smoke: same_map_vendor_selected failed")
    T.assert_true(smoke.vendor_unavailable_fails_closed == true, "smoke: vendor_unavailable_fails_closed failed")
    T.assert_true(smoke.dependency_outage_escalation == true, "smoke: dependency_outage_escalation failed")
    T.assert_true(smoke.lifecycle_idempotency_under_load == true, "smoke: lifecycle_idempotency_under_load failed")
    T.assert_true(smoke.restart_restores_runtime_state == true, "smoke: restart_restores_runtime_state failed")

    client:stop("sc014_end")
    client:destroy()

    return {
        sc014_telemetry_snapshot = true,
        sc014_smoke_suite = true,
    }
end

return { run = run }
