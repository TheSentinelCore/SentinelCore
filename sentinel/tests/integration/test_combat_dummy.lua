-- sentinel/tests/integration/test_combat_dummy.lua
-- Exercises combat-vs-dummy through the full BT tick cycle using mocked APIs

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SentinelCombat = require("modules/combat/module")
local T = require("tests/test_util")

local M = {}

----------------------------------------------------------------------
-- Mock helpers
----------------------------------------------------------------------

local function make_mock_unit(opts)
    opts = opts or {}
    local unit = {}
    unit._hostile = opts.hostile == true
    function unit:get_guid() return opts.guid or "mock-unit" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health() return opts.health or 100 end
    function unit:get_max_health() return opts.max_health or 100 end
    function unit:get_power() return opts.power or 100 end
    function unit:get_max_power() return opts.max_power or 100 end
    function unit:get_health_percentage()
        local h = opts.health or 100
        local m = opts.max_health or 100
        return m > 0 and h / m or 1.0
    end
    function unit:is_dead() return opts.dead == true end
    function unit:get_target() return opts.target end
    function unit:has_buff(spell_id)
        local buffs = opts.buffs or {}
        if type(spell_id) == "table" then
            for _, id in ipairs(spell_id) do
                if buffs[id] then return true end
            end
            return false
        end
        return buffs[spell_id] == true
    end
    function unit:get_buff_data(spell_id)
        return { is_active = unit:has_buff(spell_id), stack_count = 0 }
    end
    function unit:get_buff_stacks() return 0 end
    function unit:get_buffs() return {} end
    function unit:is_casting_spell() return false end
    function unit:is_channelling_spell() return false end
    function unit:is_auto_attacking() return opts.auto_attacking ~= false end
    function unit:get_attack_speed() return opts.attack_speed or 3.0 end
    function unit:is_enemy_with(other) return unit._hostile and other ~= nil end
    function unit:can_attack(other) return other and other._hostile end
    function unit:is_player() return opts.is_player ~= false end
    function unit:get_class() return opts.class or 8 end
    function unit:get_level() return opts.level or 70 end
    function unit:get_name() return opts.name or "MockUnit" end
    return unit
end

local function make_mock_player(opts)
    opts = opts or {}
    local p = make_mock_unit({
        guid = "player-guid",
        position = { x = 0, y = 0, z = 0 },
        hostile = false,
        is_player = true,
        class = opts.class or 2, -- Paladin
        level = opts.level or 70,
        health = opts.health or 100,
        max_health = opts.max_health or 100,
        power = opts.power or 100,
        max_power = opts.max_power or 100,
        buffs = opts.buffs or {},
        target = opts.target,
        dead = opts.dead or false,
        auto_attacking = opts.auto_attacking ~= false,
        attack_speed = opts.attack_speed or 3.0,
        name = "TestPlayer",
    })
    function p:is_moving() return opts.is_moving or false end
    function p:in_combat() return opts.in_combat or false end
    function p:is_mounted() return opts.is_mounted or false end
    function p:is_ghost() return opts.is_ghost or false end
    function p:is_casting() return opts.is_casting or false end
    function p:is_channeling() return opts.is_channeling or false end
    return p
end

local function setup_combat_globals(mock_player)
    -- Set up core globals needed by combat module
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.object_manager.get_local_player = function() return mock_player end
    _G.core.object_manager.get_all_objects = function() return {} end
    _G.core.spell_book = _G.core.spell_book or {}
    _G.core.spell_book.get_specialization_id = function() return 0 end
    _G.core.game_time = function() return 1000 end
    _G.core.delta_time = function() return 0.05 end
    _G.core.log = function(msg) end
    _G.core.log_error = function(msg) end
    _G.core.input = _G.core.input or {}
    _G.core.input.move_forward_stop = function() end
end

local function make_nav_adapter()
    return {
        move_to = function() end,
        stop = function() end,
        is_active = function() return false end,
        follow_path = function() end,
        plan_route = function() end,
        poll = function() return "idle" end,
    }
end

local function make_spell_queue()
    local queued = {}
    local queue = {
        _queued = queued,
        queue_spell_target = function(self, spell_id, target, priority, message)
            queued[#queued + 1] = { spell_id = spell_id, priority = priority, message = message }
            return true
        end,
        queue_spell_target_fast = function(self, spell_id, target, priority, message)
            queued[#queued + 1] = { spell_id = spell_id, priority = priority, message = message }
            return true
        end,
        get_queue_snapshot = function(self) return queued end,
    }
    _G.spell_queue = queue
    return queue
end

local function make_spell_helper()
    _G.spell_helper = {
        is_spell_castable = function() return true end,
        get_spell_cooldown = function() return 0 end,
        is_spell_in_line_of_sight = function() return true end,
    }
end

----------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------

function M.test_combat_idle_state()
    -- Verifies the combat module starts in IDLE state
    local player = make_mock_player()
    setup_combat_globals(player)
    make_spell_queue()
    make_spell_helper()

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local nav = make_nav_adapter()
    local combat = SentinelCombat:new(bus, bb, nav)
    combat:initialize()

    T.assert_equal(combat:get_state(), "IDLE", "combat should start in IDLE state")
    T.assert_false(combat:is_in_combat(), "combat should not be in combat initially")
end

function M.test_combat_engage_disengage_cycle()
    -- Verifies a full engage → disengage cycle
    local enemy = make_mock_unit({
        guid = "target-dummy",
        position = { x = 5, y = 0, z = 0 },
        hostile = true,
        health = 100,
        max_health = 100,
        name = "Training Dummy",
    })

    local player = make_mock_player({ target = enemy })
    setup_combat_globals(player)
    make_spell_queue()
    make_spell_helper()

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local nav = make_nav_adapter()
    local combat = SentinelCombat:new(bus, bb, nav)
    combat:initialize()

    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", enemy)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("player.is_casting", false)
    bb:set("player.is_channeling", false)
    bb:set("player.is_auto_attacking", true)
    bb:set("player.attack_speed_s", 3.0)
    bb:set("combat.leash_radius", 25)
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("combat.ally_count_30yd", 1)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("module.combat.enable_burst", false)
    bb:set("module.combat.enabled", true)
    bb:set("module.combat.auto_engage", true)
    bb:set("module.combat.auto_engage_world", true)
    bb:set("module.grind.enabled", false)

    -- Engage
    combat:engage(enemy, { source = "test" })
    T.assert_true(combat:is_in_combat(), "combat should be in combat after engage")
    T.assert_not_nil(combat:get_current_target(), "combat should have a current target")

    -- Disengage
    combat:disengage("test_complete")
    T.assert_false(combat:is_in_combat(), "combat should not be in combat after disengage")
    T.assert_equal(combat:get_state(), "IDLE", "combat should return to IDLE after disengage")
end

function M.test_combat_idle_no_auto_engage_when_disabled()
    -- Verifies the combat module does NOT auto-engage when disabled
    local enemy = make_mock_unit({
        guid = "target-dummy",
        position = { x = 5, y = 0, z = 0 },
        hostile = true,
        name = "Training Dummy",
    })

    local player = make_mock_player({ target = enemy, in_combat = true })
    setup_combat_globals(player)
    make_spell_queue()
    make_spell_helper()

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local nav = make_nav_adapter()
    local combat = SentinelCombat:new(bus, bb, nav)
    combat:initialize()

    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", enemy)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("player.is_casting", false)
    bb:set("player.is_channeling", false)
    bb:set("player.is_auto_attacking", true)
    bb:set("player.attack_speed_s", 3.0)
    bb:set("combat.leash_radius", 25)
    bb:set("module.combat.enabled", false)
    bb:set("module.combat.auto_engage", true)
    bb:set("module.combat.auto_engage_world", true)
    bb:set("module.grind.enabled", false)

    -- Update while disabled — should not engage
    combat:update(bb)
    T.assert_false(combat:is_in_combat(), "combat should not engage when disabled")
end

function M.test_combat_engage_rejects_invalid_target()
    -- Verifies that engaging with nil or invalid target doesn't crash
    local player = make_mock_player()
    setup_combat_globals(player)
    make_spell_queue()
    make_spell_helper()

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local nav = make_nav_adapter()
    local combat = SentinelCombat:new(bus, bb, nav)
    combat:initialize()

    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("module.combat.enabled", true)
    bb:set("module.grind.enabled", false)

    -- Engage with nil target
    combat:engage(nil, { source = "test" })
    T.assert_false(combat:is_in_combat(), "combat should not engage with nil target")
    T.assert_equal(combat:get_state(), "IDLE", "combat should remain IDLE with nil target")
end

function M.test_combat_shutdown_cleans_up()
    -- Verifies shutdown transitions to IDLE
    local enemy = make_mock_unit({
        guid = "target-dummy",
        position = { x = 5, y = 0, z = 0 },
        hostile = true,
        name = "Training Dummy",
    })

    local player = make_mock_player({ target = enemy })
    setup_combat_globals(player)
    make_spell_queue()
    make_spell_helper()

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local nav = make_nav_adapter()
    local combat = SentinelCombat:new(bus, bb, nav)
    combat:initialize()

    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", enemy)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("module.combat.enabled", true)
    bb:set("module.grind.enabled", false)

    combat:engage(enemy, { source = "test" })
    T.assert_true(combat:is_in_combat(), "combat should be engaged")

    combat:shutdown()
    T.assert_false(combat:is_in_combat(), "combat should be IDLE after shutdown")
end

----------------------------------------------------------------------
-- run() entry point for run_all.lua compatibility
----------------------------------------------------------------------

function M.run()
    -- Run each test_* function in sequence
    for name, fn in pairs(M) do
        if type(fn) == "function" and name:match("^test_") then
            fn()
        end
    end
end

return M
