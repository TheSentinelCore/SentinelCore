local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local PvPTargetSelector = require("modules/combat/pvp_target_selector")
local T = require("tests/test_util")

local M = {}

local function make_player()
    local p = {}
    function p:get_guid() return "player_guid" end
    function p:get_position() return { x = 0, y = 0, z = 0 } end
    function p:is_dead() return false end
    function p:is_player() return true end
    function p:is_enemy_with() return false end
    function p:is_friend_with(other) return other == p end
    function p:can_attack(other) return other ~= p end
    function p:get_faction_id() return 1 end
    function p:get_class() return 1 end
    return p
end

local function make_enemy(opts)
    opts = opts or {}
    local u = {}
    function u:get_guid() return opts.guid or "enemy" end
    function u:get_position() return opts.position or { x = 10, y = 0, z = 0 } end
    function u:is_dead() return opts.dead == true end
    function u:is_player() return true end
    function u:is_enemy_with() return true end
    function u:can_attack() return true end
    function u:is_friend_with() return false end
    function u:get_faction_id() return opts.faction or 2 end
    function u:get_class() return opts.class_id or 1 end
    function u:get_health() return opts.health or 80 end
    function u:get_max_health() return opts.max_health or 100 end
    function u:get_target() return opts.target end
    function u:get_group_role() return opts.role or 0 end
    function u:is_damage_immune() return opts.immune == true end
    function u:get_loss_of_control_info() return { valid = false } end
    function u:is_casting_spell() return false end
    function u:is_channelling_spell() return false end
    function u:is_active_spell_interruptable() return false end
    function u:is_in_combat() return true end
    function u:is_mounted() return false end
    function u:is_unit() return true end
    function u:get_npc_id() return 0 end
    return u
end

function M.run()
    local mock_time = 0
    core = { game_time = function() return mock_time end }

    -- 1. Cloth caster scored higher than plate
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local selector = PvPTargetSelector.new(bus, bb)
        local player = make_player()

        local mage = make_enemy({ guid = "mage1", class_id = 8, position = { x = 10, y = 0, z = 0 } })
        local warrior = make_enemy({ guid = "warrior1", class_id = 1, position = { x = 10, y = 0, z = 0 } })

        selector._collect_enemies = function(self, p, s) return { mage, warrior } end

        mock_time = 0
        local best = selector:select(player, {})
        T.assert_not_nil(best, "should select a target")
        T.assert_equal(best:get_guid(), "mage1", "cloth mage should be scored higher than plate warrior")
    end

    -- 2. Healer prioritized
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local selector = PvPTargetSelector.new(bus, bb)
        local player = make_player()

        local healer = make_enemy({ guid = "healer1", role = 1, position = { x = 10, y = 0, z = 0 } })
        local dps = make_enemy({ guid = "dps1", role = 0, position = { x = 10, y = 0, z = 0 } })

        selector._collect_enemies = function(self, p, s) return { healer, dps } end

        mock_time = 1000
        selector.last_target_guid = nil
        selector.last_switch_ms = 0
        local best = selector:select(player, {})
        T.assert_not_nil(best, "should select a target")
        T.assert_equal(best:get_guid(), "healer1", "healer should be prioritized over DPS")
    end

    -- 3. Hard immune skipped
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local selector = PvPTargetSelector.new(bus, bb)
        local player = make_player()

        local immune_enemy = make_enemy({ guid = "immune1", immune = true, position = { x = 10, y = 0, z = 0 } })

        selector._collect_enemies = function(self, p, s) return { immune_enemy } end

        mock_time = 2000
        selector.last_target_guid = nil
        selector.last_switch_ms = 0
        local best = selector:select(player, {})
        T.assert_equal(best, nil, "immune target should be skipped")
    end

    -- 4. Low HP target preferred
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local selector = PvPTargetSelector.new(bus, bb)
        local player = make_player()

        local low_hp = make_enemy({ guid = "low_hp1", health = 20, max_health = 100, class_id = 1, position = { x = 10, y = 0, z = 0 } })
        local full_hp = make_enemy({ guid = "full_hp1", health = 90, max_health = 100, class_id = 1, position = { x = 10, y = 0, z = 0 } })

        selector._collect_enemies = function(self, p, s) return { low_hp, full_hp } end

        mock_time = 3000
        selector.last_target_guid = nil
        selector.last_switch_ms = 0
        local best = selector:select(player, {})
        T.assert_not_nil(best, "should select a target")
        T.assert_equal(best:get_guid(), "low_hp1", "low HP target should be preferred")
    end

    -- 5. Flag carrier bonus
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local selector = PvPTargetSelector.new(bus, bb)
        local player = make_player()

        local carrier = make_enemy({ guid = "carrier1", class_id = 1, position = { x = 10, y = 0, z = 0 } })
        local normal = make_enemy({ guid = "normal1", class_id = 1, position = { x = 10, y = 0, z = 0 } })

        selector._collect_enemies = function(self, p, s) return { carrier, normal } end
        selector._has_flag_carrier_aura = function(self, unit, settings)
            return unit:get_guid() == "carrier1"
        end

        mock_time = 4000
        selector.last_target_guid = nil
        selector.last_switch_ms = 0
        local best = selector:select(player, {})
        T.assert_not_nil(best, "should select a target")
        T.assert_equal(best:get_guid(), "carrier1", "flag carrier should be scored highest")
    end

    -- 6. Assist train bonus
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local selector = PvPTargetSelector.new(bus, bb)
        local player = make_player()

        local focused = make_enemy({ guid = "focused1", class_id = 1, position = { x = 10, y = 0, z = 0 } })
        local unfocused = make_enemy({ guid = "unfocused1", class_id = 1, position = { x = 10, y = 0, z = 0 } })

        selector._collect_enemies = function(self, p, s) return { focused, unfocused } end

        -- Mock the ally scanning by providing unit_helper that returns allies targeting focused
        local ally1 = { get_target = function() return focused end }
        local ally2 = { get_target = function() return focused end }
        selector.unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...) return { ally1, ally2 } end,
        }

        mock_time = 5000
        selector.last_target_guid = nil
        selector.last_switch_ms = 0
        local best = selector:select(player, { assist_train_enabled = true, assist_train_min_allies = 2 })
        T.assert_not_nil(best, "should select a target")
        T.assert_equal(best:get_guid(), "focused1", "target with assist train should be preferred")
    end

    -- 7. Switch hesitation
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local selector = PvPTargetSelector.new(bus, bb)
        local player = make_player()

        local target_a = make_enemy({ guid = "switch_a", class_id = 1, health = 50, max_health = 100, position = { x = 10, y = 0, z = 0 } })
        local target_b = make_enemy({ guid = "switch_b", class_id = 8, role = 1, health = 50, max_health = 100, position = { x = 10, y = 0, z = 0 } })

        -- First select target_a alone
        selector._collect_enemies = function(self, p, s) return { target_a } end

        mock_time = 10000
        selector.last_target_guid = nil
        selector.last_switch_ms = 0
        local best1 = selector:select(player, {})
        T.assert_equal(best1:get_guid(), "switch_a", "should select target_a initially")

        -- Now add better target_b within hesitation window (< 1200ms)
        selector._collect_enemies = function(self, p, s) return { target_a, target_b } end
        mock_time = 10500
        local best2 = selector:select(player, {})
        T.assert_equal(best2:get_guid(), "switch_a", "switch hesitation should keep target_a within 1200ms")
    end
end

return M
