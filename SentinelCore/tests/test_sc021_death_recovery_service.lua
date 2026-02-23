local T = require("tests/TestUtil")

local function run()
    -- ── Shared mock infrastructure ──────────────────────────────────
    local release_calls = 0
    local resurrect_calls = 0
    local corpse_pos = nil
    local resurrect_delay = 0

    T.install_core_stub({
        get_corpse_position = function()
            return corpse_pos
        end,
        get_resurrect_corpse_delay = function()
            return resurrect_delay
        end,
        game_ui = {
            get_corpse_position = function()
                return corpse_pos
            end,
            get_resurrect_corpse_delay = function()
                return resurrect_delay
            end,
            get_loot_item_count = function() return 0 end,
            is_map_open = function() return false end,
            is_rendering_kick_warning = function() return false end,
        },
        input = {
            release_spirit = function()
                release_calls = release_calls + 1
                return true
            end,
            resurrect_corpse = function()
                resurrect_calls = resurrect_calls + 1
                return true
            end,
            cast_target_spell = function() return true end,
            cast_self_spell = function() return true end,
            set_target = function() return true end,
            is_key_pressed = function() return false end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local DeathRecoveryService = require("services/DeathRecoveryService")

    -- ── Helper: capture emitted events ──────────────────────────────
    local function make_event_log(bus)
        local log = {}
        bus:on_pattern("death.*", function(data, event_name)
            log[#log + 1] = { event = event_name, data = data }
        end)
        return log
    end

    -- ── Helper: mock navigation adapter ─────────────────────────────
    local function make_mock_nav()
        local nav = { move_to_calls = 0, stop_calls = 0, last_dest = nil }
        function nav:move_to(dest)
            self.move_to_calls = self.move_to_calls + 1
            self.last_dest = dest
        end
        function nav:stop()
            self.stop_calls = self.stop_calls + 1
        end
        return nav
    end

    -- ── Test 1: Idle when alive ─────────────────────────────────────
    do
        release_calls = 0; resurrect_calls = 0; corpse_pos = nil; resurrect_delay = 0
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local player = T.mock_object({ dead = false, ghost = false, position = { x = 10, y = 20, z = 30 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        local svc = DeathRecoveryService:new(bus, bb, {})
        local ok, err = svc:update(1000)
        T.assert_true(ok == true, "t1: update should return true")
        T.assert_eq(svc:is_active(), false, "t1: should not be active when alive")
        T.assert_eq(svc:get_state(), "idle", "t1: state should be idle")
        T.assert_eq(bb:get("death.active", false), false, "t1: bb death.active should be false")
    end

    -- ── Test 2: Activates on death ──────────────────────────────────
    do
        release_calls = 0; resurrect_calls = 0; corpse_pos = nil; resurrect_delay = 0
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local events = make_event_log(bus)
        local player = T.mock_object({ dead = true, ghost = false, position = { x = 5, y = 5, z = 5 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        local svc = DeathRecoveryService:new(bus, bb, {})
        svc:update(1000)
        T.assert_true(svc:is_active(), "t2: should be active when dead")
        T.assert_eq(svc:get_state(), "dead", "t2: state should be 'dead'")
        T.assert_eq(bb:get("death.active"), true, "t2: bb death.active should be true")
        T.assert_eq(bb:get("death.state"), "dead", "t2: bb death.state should be 'dead'")

        local found_start = false
        for i = 1, #events do
            if events[i].event == "death.recovery_started" then
                found_start = true
            end
        end
        T.assert_true(found_start, "t2: DEATH_RECOVERY_STARTED should be emitted")
    end

    -- ── Test 3: Release spirit after delay ──────────────────────────
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local events = make_event_log(bus)
        local player = T.mock_object({ dead = true, ghost = false, position = { x = 0, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        release_calls = 0
        local svc = DeathRecoveryService:new(bus, bb, {
            death_release_delay_secs = 1.0,
            death_release_retry_secs = 0.5,
        })

        -- First update at t=100: activates, delay not passed yet
        svc:update(100)
        T.assert_eq(release_calls, 0, "t3: should not release before delay")

        -- Update at t=101.5: delay of 1.0s passed since started_at=100
        svc:update(101.5)
        T.assert_eq(release_calls, 1, "t3: should release after delay")

        local found_released = false
        for i = 1, #events do
            if events[i].event == "death.spirit_released" then
                found_released = true
            end
        end
        T.assert_true(found_released, "t3: DEATH_SPIRIT_RELEASED should be emitted")
    end

    -- ── Test 4: Corpse run (ghost + corpse position) ────────────────
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local events = make_event_log(bus)
        local nav = make_mock_nav()
        local player = T.mock_object({ dead = false, ghost = true, position = { x = 0, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        corpse_pos = { x = 100, y = 0, z = 0 }

        local svc = DeathRecoveryService:new(bus, bb, {
            death_resurrect_distance = 10.0,
            death_move_to_cooldown = 0.1,
        }, nav)

        svc:update(200)
        T.assert_eq(svc:get_state(), "corpse_run", "t4: state should be 'corpse_run'")
        T.assert_true(nav.move_to_calls >= 1, "t4: nav.move_to should be called for corpse run")
        T.assert_true(nav.last_dest ~= nil, "t4: nav destination should be set")

        local found_update = false
        for i = 1, #events do
            if events[i].event == "death.corpse_run_update" then
                found_update = true
            end
        end
        T.assert_true(found_update, "t4: DEATH_CORPSE_RUN_UPDATE should be emitted")

        corpse_pos = nil
    end

    -- ── Test 5: Resurrect when near corpse ──────────────────────────
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local events = make_event_log(bus)
        local nav = make_mock_nav()
        local player = T.mock_object({ dead = false, ghost = true, position = { x = 50, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        corpse_pos = { x = 52, y = 0, z = 0 }
        resurrect_calls = 0
        resurrect_delay = 0

        local svc = DeathRecoveryService:new(bus, bb, {
            death_resurrect_distance = 10.0,
            death_resurrect_retry_secs = 0.1,
        }, nav)

        svc:update(300)
        T.assert_true(nav.stop_calls >= 1, "t5: nav.stop should be called when near corpse")
        T.assert_eq(resurrect_calls, 1, "t5: resurrect_corpse should be called")

        local found_attempt = false
        for i = 1, #events do
            if events[i].event == "death.resurrect_attempt" then
                found_attempt = true
            end
        end
        T.assert_true(found_attempt, "t5: DEATH_RESURRECT_ATTEMPT should be emitted")

        corpse_pos = nil
        resurrect_delay = 0
    end

    -- ── Test 6: Deactivation on resurrection ────────────────────────
    do
        release_calls = 0; resurrect_calls = 0; corpse_pos = nil; resurrect_delay = 0
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local events = make_event_log(bus)
        local player = T.mock_object({ dead = true, ghost = false, position = { x = 0, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        local svc = DeathRecoveryService:new(bus, bb, {})
        svc:update(400)
        T.assert_true(svc:is_active(), "t6: should be active while dead")

        -- Player comes back alive
        player._dead = false
        player._ghost = false
        svc:update(410)
        T.assert_eq(svc:is_active(), false, "t6: should deactivate after resurrection")
        T.assert_eq(svc:get_state(), "idle", "t6: state should return to idle")
        T.assert_eq(bb:get("death.active", false), false, "t6: bb death.active should be false")

        local found_resurrected = false
        for i = 1, #events do
            if events[i].event == "death.resurrected" then
                found_resurrected = true
            end
        end
        T.assert_true(found_resurrected, "t6: DEATH_RESURRECTED should be emitted")
    end

    -- ── Test 7: Reset clears all state ──────────────────────────────
    do
        release_calls = 0; resurrect_calls = 0; corpse_pos = nil; resurrect_delay = 0
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local player = T.mock_object({ dead = true, ghost = false, position = { x = 0, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        local svc = DeathRecoveryService:new(bus, bb, {})
        svc:update(500)
        T.assert_true(svc:is_active(), "t7: should be active before reset")

        svc:reset()
        T.assert_eq(svc:is_active(), false, "t7: should be inactive after reset")
        T.assert_eq(svc:get_state(), "idle", "t7: state should be idle after reset")
        T.assert_eq(bb:get("death.active", false), false, "t7: bb cleared after reset")
    end

    -- ── Test 8: Config overrides apply ──────────────────────────────
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local nav = make_mock_nav()
        local player = T.mock_object({ dead = false, ghost = true, position = { x = 0, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        corpse_pos = { x = 100, y = 0, z = 0 }

        local svc = DeathRecoveryService:new(bus, bb, {
            death_resurrect_distance = 200.0,
        }, nav)

        resurrect_calls = 0
        resurrect_delay = 0
        svc:update(600)
        T.assert_eq(resurrect_calls, 1, "t8: custom resurrect_distance should be used")
        T.assert_true(nav.move_to_calls == 0, "t8: should not move when within custom distance")

        corpse_pos = nil
    end

    -- ── Test 9: Resurrect delay gate ────────────────────────────────
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local nav = make_mock_nav()
        local player = T.mock_object({ dead = false, ghost = true, position = { x = 50, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        corpse_pos = { x = 50, y = 0, z = 0 }
        resurrect_delay = 5.0
        resurrect_calls = 0

        local svc = DeathRecoveryService:new(bus, bb, {
            death_resurrect_distance = 10.0,
        }, nav)

        svc:update(700)
        T.assert_eq(resurrect_calls, 0, "t9: should not resurrect when delay active")

        resurrect_delay = 0
        svc:update(700.8)
        T.assert_eq(resurrect_calls, 1, "t9: should resurrect once delay expires")

        corpse_pos = nil
        resurrect_delay = 0
    end

    -- ── Test 10: No player deactivates cleanly ──────────────────────
    do
        release_calls = 0; resurrect_calls = 0; corpse_pos = nil; resurrect_delay = 0
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)

        local svc = DeathRecoveryService:new(bus, bb, {})
        local ok, err = svc:update(800)
        T.assert_true(ok == true, "t10: update should succeed with no player")
        T.assert_eq(svc:is_active(), false, "t10: should not activate without player")
    end

    -- ── Test 11: Ghost-first with blackboard death position fallback ─
    -- Covers the case where core.get_corpse_position doesn't exist and
    -- the "dead but not ghost" frame was missed. The sensor-cached
    -- player.death_position in the blackboard should be used as fallback.
    do
        release_calls = 0; resurrect_calls = 0; resurrect_delay = 0
        corpse_pos = nil  -- simulate core.get_corpse_position not existing

        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local nav = make_mock_nav()

        -- Player is already a ghost at graveyard (missed "dead" frame)
        local player = T.mock_object({ dead = false, ghost = true, position = { x = 0, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        -- Simulate sensor-cached death position (where the body is)
        bb:set("player.death_position", { x = 200, y = 100, z = 0 })

        local svc = DeathRecoveryService:new(bus, bb, {
            death_resurrect_distance = 10.0,
            death_move_to_cooldown = 0.1,
        }, nav)

        svc:update(900)
        T.assert_eq(svc:get_state(), "corpse_run", "t11: state should be 'corpse_run'")
        T.assert_true(nav.move_to_calls >= 1, "t11: nav.move_to should be called using bb death position")
        T.assert_true(nav.last_dest ~= nil, "t11: nav destination should be set")
        T.assert_eq(nav.last_dest.x, 200, "t11: destination x should match death position")
        T.assert_eq(nav.last_dest.y, 100, "t11: destination y should match death position")
    end

    -- ── Test 12: Uses core.game_ui.get_corpse_position path ──────────
    do
        release_calls = 0; resurrect_calls = 0; resurrect_delay = 0
        local saved_get_corpse = core.get_corpse_position
        local saved_get_delay = core.get_resurrect_corpse_delay
        core.get_corpse_position = nil
        core.get_resurrect_corpse_delay = nil
        local gui_corpse_pos = { x = 300, y = 150, z = 50 }
        core.game_ui.get_corpse_position = function()
            return gui_corpse_pos
        end
        core.game_ui.get_resurrect_corpse_delay = function()
            return resurrect_delay
        end

        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local nav = make_mock_nav()
        local player = T.mock_object({ dead = false, ghost = true, position = { x = 0, y = 0, z = 0 } })
        bb:set("player.object", player)
        bb:set("player.position", player:get_position())

        local svc = DeathRecoveryService:new(bus, bb, {
            death_resurrect_distance = 10.0,
            death_move_to_cooldown = 0.1,
        }, nav)

        svc:update(1000)
        T.assert_eq(svc:get_state(), "corpse_run", "t12: state should be 'corpse_run'")
        T.assert_true(nav.move_to_calls >= 1, "t12: nav.move_to should be called using game_ui corpse position")
        T.assert_eq(nav.last_dest.x, 300, "t12: destination x should match game_ui corpse position")
        T.assert_eq(nav.last_dest.y, 150, "t12: destination y should match game_ui corpse position")

        core.get_corpse_position = saved_get_corpse
        core.get_resurrect_corpse_delay = saved_get_delay
        core.game_ui.get_corpse_position = nil
        core.game_ui.get_resurrect_corpse_delay = nil
    end

    return {
        idle_when_alive = true,
        activates_on_death = true,
        release_spirit_after_delay = true,
        corpse_run = true,
        resurrect_near_corpse = true,
        deactivation_on_resurrection = true,
        reset_clears_state = true,
        config_overrides = true,
        resurrect_delay_gate = true,
        no_player_deactivates = true,
        ghost_first_bb_fallback = true,
        game_ui_corpse_path = true,
    }
end

return { run = run }
