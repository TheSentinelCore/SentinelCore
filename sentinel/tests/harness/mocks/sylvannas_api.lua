-- sentinel/tests/harness/mocks/sylvannas_api.lua
-- Mocks for Sylvannas API (core.*, _G.SentinelNavClient, spell_queue)
-- Used by out-of-game test harness

local Mock = {}

-- Core game time
Mock._game_time = 0
Mock._frame_count = 0

function Mock.advance_time(ms)
    Mock._game_time = Mock._game_time + ms
    Mock._frame_count = Mock._frame_count + 1
end

function Mock.reset_time()
    Mock._game_time = 0
    Mock._frame_count = 0
end

-- ============================================================================
-- core.game_time
-- ============================================================================
Mock.core = Mock.core or {}
Mock.core.game_time = function()
    return Mock._game_time
end

-- ============================================================================
-- core.object_manager
-- ============================================================================
Mock.core.object_manager = Mock.core.object_manager or {}

local _objects = {}
local _local_player = nil
local _target = nil

function Mock.core.object_manager.get_local_player()
    return _local_player
end

function Mock.core.object_manager.get_target()
    return _target
end

function Mock.core.object_manager.get_all_objects()
    local result = {}
    for _, obj in pairs(_objects) do
        table.insert(result, obj)
    end
    return result
end

function Mock.core.object_manager.get_objects_in_range(x, y, z, range)
    local result = {}
    for _, obj in pairs(_objects) do
        if obj.get_position then
            local ok, pos = pcall(obj.get_position, obj)
            if ok and pos then
                local dx = pos.x - x
                local dy = pos.y - y
                local dz = pos.z - z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                if dist <= range then
                    table.insert(result, obj)
                end
            end
        end
    end
    return result
end

function Mock.set_local_player(player)
    _local_player = player
end

function Mock.set_target(unit)
    _target = unit
end

function Mock.add_object(guid, obj)
    _objects[guid] = obj
end

function Mock.remove_object(guid)
    _objects[guid] = nil
end

function Mock.clear_objects()
    _objects = {}
end

-- ============================================================================
-- core.player
-- ============================================================================
Mock.core.player = Mock.core.player or {}

function Mock.core.player.get_class()
    if _local_player and _local_player.get_class then
        return _local_player:get_class()
    end
    return 8 -- Mage
end

function Mock.core.player.get_level()
    if _local_player and _local_player.get_level then
        return _local_player:get_level()
    end
    return 60
end

function Mock.core.player.is_moving()
    if _local_player and _local_player.is_moving then
        return _local_player:is_moving()
    end
    return false
end

function Mock.core.player.get_position()
    if _local_player and _local_player.get_position then
        return _local_player:get_position()
    end
    return { x = 0, y = 0, z = 0 }
end

function Mock.core.player.get_health()
    if _local_player and _local_player.get_health then
        return _local_player:get_health()
    end
    return 100
end

function Mock.core.player.get_max_health()
    if _local_player and _local_player.get_max_health then
        return _local_player:get_max_health()
    end
    return 100
end

function Mock.core.player.get_power()
    if _local_player and _local_player.get_power then
        return _local_player:get_power()
    end
    return 100
end

function Mock.core.player.get_max_power()
    if _local_player and _local_player.get_max_power then
        return _local_player:get_max_power()
    end
    return 100
end

function Mock.core.player.get_power_type()
    if _local_player and _local_player.get_power_type then
        return _local_player:get_power_type()
    end
    return 0 -- Mana
end

function Mock.core.player.is_dead()
    if _local_player and _local_player.is_dead then
        return _local_player:is_dead()
    end
    return false
end

function Mock.core.player.is_ghost()
    if _local_player and _local_player.is_ghost then
        return _local_player:is_ghost()
    end
    return false
end

function Mock.core.player.is_mounted()
    if _local_player and _local_player.is_mounted then
        return _local_player:is_mounted()
    end
    return false
end

function Mock.core.player.in_combat()
    if _local_player and _local_player.in_combat then
        return _local_player:in_combat()
    end
    return false
end

-- ============================================================================
-- core.unit
-- ============================================================================
Mock.core.unit = Mock.core.unit or {}

function Mock.core.unit.get_guid(unit)
    if unit and unit.get_guid then
        return unit:get_guid()
    end
    return nil
end

function Mock.core.unit.get_position(unit)
    if unit and unit.get_position then
        return unit:get_position()
    end
    return { x = 0, y = 0, z = 0 }
end

function Mock.core.unit.get_health(unit)
    if unit and unit.get_health then
        return unit:get_health()
    end
    return 100
end

function Mock.core.unit.get_max_health(unit)
    if unit and unit.get_max_health then
        return unit:get_max_health()
    end
    return 100
end

function Mock.core.unit.get_power(unit)
    if unit and unit.get_power then
        return unit:get_power()
    end
    return 100
end

function Mock.core.unit.get_max_power(unit)
    if unit and unit.get_max_power then
        return unit:get_max_power()
    end
    return 100
end

function Mock.core.unit.get_power_type(unit)
    if unit and unit.get_power_type then
        return unit:get_power_type()
    end
    return 0
end

function Mock.core.unit.get_distance(unit)
    if unit and unit.get_distance then
        return unit:get_distance()
    end
    local player_pos = Mock.core.player.get_position()
    local unit_pos = Mock.core.unit.get_position(unit)
    local dx = unit_pos.x - player_pos.x
    local dy = unit_pos.y - player_pos.y
    local dz = unit_pos.z - player_pos.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function Mock.core.unit.is_enemy(unit)
    if unit and unit.is_enemy then
        return unit:is_enemy()
    end
    return true
end

function Mock.core.unit.is_friendly(unit)
    if unit and unit.is_friendly then
        return unit:is_friendly()
    end
    return false
end

function Mock.core.unit.is_dead(unit)
    if unit and unit.is_dead then
        return unit:is_dead()
    end
    return false
end

function Mock.core.unit.get_target(unit)
    if unit and unit.get_target then
        return unit:get_target()
    end
    return nil
end

function Mock.core.unit.get_casting_spell(unit)
    if unit and unit.get_casting_spell then
        return unit:get_casting_spell()
    end
    return nil
end

function Mock.core.unit.get_channeling_spell(unit)
    if unit and unit.get_channeling_spell then
        return unit:get_channeling_spell()
    end
    return nil
end

function Mock.core.unit.get_name(unit)
    if unit and unit.get_name then
        return unit:get_name()
    end
    return "Unknown"
end

function Mock.core.unit.get_level(unit)
    if unit and unit.get_level then
        return unit:get_level()
    end
    return 1
end

function Mock.core.unit.get_creature_type(unit)
    if unit and unit.get_creature_type then
        return unit:get_creature_type()
    end
    return "Humanoid"
end

function Mock.core.unit.get_faction(unit)
    if unit and unit.get_faction then
        return unit:get_faction()
    end
    return 0
end

function Mock.core.unit.get_reaction(unit)
    if unit and unit.get_reaction then
        return unit:get_reaction()
    end
    return 4 -- Neutral
end

function Mock.core.unit.get_casting_time_left(unit)
    if unit and unit.get_casting_time_left then
        return unit:get_casting_time_left()
    end
    return 0
end

function Mock.core.unit.get_channeling_time_left(unit)
    if unit and unit.get_channeling_time_left then
        return unit:get_channeling_time_left()
    end
    return 0
end

function Mock.core.unit.get_aura(unit, spell_id)
    if unit and unit.get_aura then
        return unit:get_aura(spell_id)
    end
    return nil
end

function Mock.core.unit.get_all_auras(unit)
    if unit and unit.get_all_auras then
        return unit:get_all_auras()
    end
    return {}
end

-- ============================================================================
-- core.spell
-- ============================================================================
Mock.core.spell = Mock.core.spell or {}

local _spell_data = {}

function Mock.core.spell.get_spell_cooldown(spell_id)
    if _spell_data[spell_id] and _spell_data[spell_id].cooldown then
        return _spell_data[spell_id].cooldown
    end
    return 0
end

function Mock.core.spell.get_spell_charges(spell_id)
    if _spell_data[spell_id] and _spell_data[spell_id].charges then
        return _spell_data[spell_id].charges
    end
    return 0
end

function Mock.core.spell.get_spell_max_charges(spell_id)
    if _spell_data[spell_id] and _spell_data[spell_id].max_charges then
        return _spell_data[spell_id].max_charges
    end
    return 0
end

function Mock.core.spell.get_spell_charge_cooldown(spell_id)
    if _spell_data[spell_id] and _spell_data[spell_id].charge_cooldown then
        return _spell_data[spell_id].charge_cooldown
    end
    return 0
end

function Mock.core.spell.is_spell_known(spell_id)
    if _spell_data[spell_id] ~= nil then
        return true
    end
    -- Default known spells for testing
    local known_spells = {
        [116] = true, -- Frostbolt
        [122] = true, -- Frost Nova
        [120] = true, -- Cone of Cold
        [12472] = true, -- Icy Veins
        [45438] = true, -- Ice Block
        [1953] = true, -- Blink
        [31687] = true, -- Summon Water Elemental
        [84714] = true, -- Frozen Orb
        [44614] = true, -- Flurry
        [205021] = true, -- Ray of Frost
        [257541] = true, -- Glacial Spike
        [30455] = true, -- Ice Lance
        [228597] = true, -- Frostbolt (Brain Freeze)
        [190356] = true, -- Blizzard
        [157997] = true, -- Ice Nova
        [214634] = true, -- Ebonbolt
        [228354] = true, -- Flurry (Winter's Chill)
    }
    return known_spells[spell_id] == true
end

function Mock.core.spell.get_spell_range(spell_id)
    if _spell_data[spell_id] and _spell_data[spell_id].range then
        return _spell_data[spell_id].range
    end
    local ranges = {
        [116] = 40, -- Frostbolt
        [30455] = 40, -- Ice Lance
        [84714] = 40, -- Frozen Orb
        [122] = 10, -- Frost Nova
        [120] = 10, -- Cone of Cold
        [1953] = 20, -- Blink
        [45438] = 0, -- Ice Block
    }
    return ranges[spell_id] or 40
end

function Mock.core.spell.get_spell_gcd(spell_id)
    if _spell_data[spell_id] and _spell_data[spell_id].gcd then
        return _spell_data[spell_id].gcd
    end
    return 1.5
end

function Mock.core.spell.get_spell_cast_time(spell_id)
    if _spell_data[spell_id] and _spell_data[spell_id].cast_time then
        return _spell_data[spell_id].cast_time
    end
    local cast_times = {
        [116] = 1.5, -- Frostbolt
        [30455] = 0, -- Ice Lance (instant)
        [84714] = 0, -- Frozen Orb
        [122] = 0, -- Frost Nova
        [120] = 0, -- Cone of Cold
        [1953] = 0, -- Blink
        [45438] = 0, -- Ice Block
        [12472] = 0, -- Icy Veins
        [31687] = 2.5, -- Water Elemental
    }
    return cast_times[spell_id] or 0
end

function Mock.set_spell_data(spell_id, data)
    _spell_data[spell_id] = data
end

-- ============================================================================
-- core.input
-- ============================================================================
Mock.core.input = Mock.core.input or {}

function Mock.core.input.cast_spell(spell_id, target)
    print(string.format("[MOCK] CastSpell(%d, %s)", spell_id, target and target:get_guid() or "nil"))
    return true
end

function Mock.core.input.cast_spell_at(spell_id, x, y, z)
    print(string.format("[MOCK] CastSpellAt(%d, %.1f, %.1f, %.1f)", spell_id, x, y, z))
    return true
end

function Mock.core.input.interact(unit)
    print(string.format("[MOCK] Interact(%s)", unit and unit:get_guid() or "nil"))
    return true
end

function Mock.core.input.move_forward_start()
    print("[MOCK] MoveForwardStart")
    return true
end

function Mock.core.input.move_forward_stop()
    print("[MOCK] MoveForwardStop")
    return true
end

function Mock.core.input.turn_left_start()
    print("[MOCK] TurnLeftStart")
    return true
end

function Mock.core.input.turn_left_stop()
    print("[MOCK] TurnLeftStop")
    return true
end

function Mock.core.input.turn_right_start()
    print("[MOCK] TurnRightStart")
    return true
end

function Mock.core.input.turn_right_stop()
    print("[MOCK] TurnRightStop")
    return true
end

function Mock.core.input.jump()
    print("[MOCK] Jump")
    return true
end

-- ============================================================================
-- core.spell_queue
-- ============================================================================
Mock.core.spell_queue = Mock.core.spell_queue or {}

local _queued_spells = {}

function Mock.core.spell_queue.queue_spell(spell_id, target_guid, x, y, z)
    table.insert(_queued_spells, {
        spell_id = spell_id,
        target_guid = target_guid,
        x = x, y = y, z = z,
        time = Mock._game_time
    })
    return true
end

function Mock.core.spell_queue.clear_queue()
    _queued_spells = {}
end

function Mock.core.spell_queue.get_queue()
    return _queued_spells
end

function Mock.core.spell_queue.get_queued_count()
    return #_queued_spells
end

function Mock.get_queued_spells()
    return _queued_spells
end

function Mock.clear_queued_spells()
    _queued_spells = {}
end

-- ============================================================================
-- core.log / core.log_error
-- ============================================================================
Mock.core.log = function(message)
    print("[LOG] " .. tostring(message))
end

Mock.core.log_error = function(message)
    print("[ERROR] " .. tostring(message))
end

-- ============================================================================
-- _G.SentinelNavClient
-- ============================================================================
Mock.SentinelNavClient = Mock.SentinelNavClient or {}
Mock.SentinelNavClient.client = Mock.SentinelNavClient.client or {}

local _nav_path = {}
local _nav_state = "IDLE"

function Mock.SentinelNavClient.client.request_path(start_x, start_y, start_z, end_x, end_y, end_z)
    _nav_path = {
        { x = start_x, y = start_y, z = start_z },
        { x = end_x, y = end_y, z = end_z }
    }
    _nav_state = "COMPLETE"
    return true
end

function Mock.SentinelNavClient.client.get_path()
    return _nav_path
end

function Mock.SentinelNavClient.client.get_state()
    return _nav_state
end

function Mock.SentinelNavClient.client.raycast(x, y, z, dx, dy, dz, distance)
    return false, x + dx * distance, y + dy * distance, z + dz * distance
end

function Mock.SentinelNavClient.client.random_point_near(x, y, z, radius)
    return x + math.random(-radius, radius), y + math.random(-radius, radius), z
end

function Mock.set_nav_path(path)
    _nav_path = path
end

function Mock.set_nav_state(state)
    _nav_state = state
end

-- ============================================================================
-- Mock Unit Factory
-- ============================================================================
function Mock.create_mock_unit(guid, data)
    data = data or {}
    local unit = {
        _guid = guid,
        _position = data.position or { x = 0, y = 0, z = 0 },
        _health = data.health or 100,
        _max_health = data.max_health or 100,
        _power = data.power or 100,
        _max_power = data.max_power or 100,
        _power_type = data.power_type or 0,
        _level = data.level or 1,
        _name = data.name or "MockUnit",
        _creature_type = data.creature_type or "Humanoid",
        _faction = data.faction or 0,
        _reaction = data.reaction or 4,
        _is_enemy = data.is_enemy ~= false,
        _is_friendly = data.is_friendly == true,
        _is_dead = data.is_dead == true,
        _target = data.target,
        _casting_spell = data.casting_spell,
        _channeling_spell = data.channeling_spell,
        _auras = data.auras or {},
    }

    function unit:get_guid() return self._guid end
    function unit:get_position() return self._position end
    function unit:get_health() return self._health end
    function unit:get_max_health() return self._max_health end
    function unit:get_power() return self._power end
    function unit:get_max_power() return self._max_power end
    function unit:get_power_type() return self._power_type end
    function unit:get_level() return self._level end
    function unit:get_name() return self._name end
    function unit:get_creature_type() return self._creature_type end
    function unit:get_faction() return self._faction end
    function unit:get_reaction() return self._reaction end
    function unit:is_enemy() return self._is_enemy end
    function unit:is_friendly() return self._is_friendly end
    function unit:is_dead() return self._is_dead end
    function unit:get_target() return self._target end
    function unit:get_casting_spell() return self._casting_spell end
    function unit:get_channeling_spell() return self._channeling_spell end
    function unit:get_aura(spell_id) return self._auras[spell_id] end
    function unit:get_all_auras() return self._auras end
    function unit:get_distance() return Mock.core.unit.get_distance(self) end
    function unit:get_casting_time_left() return 0 end
    function unit:get_channeling_time_left() return 0 end

    return unit
end

function Mock.create_mock_player(data)
    local unit = Mock.create_mock_unit("Player-1234", data)
    unit._class = data.class or 8 -- Mage
    unit._is_moving = data.is_moving or false
    unit._in_combat = data.in_combat or false
    unit._is_mounted = data.is_mounted or false
    unit._is_dead = data.is_dead or false
    unit._is_ghost = data.is_ghost or false
    unit._is_casting = data.is_casting or false
    unit._is_channeling = data.is_channeling or false

    function unit:get_class() return self._class end
    function unit:is_moving() return self._is_moving end
    function unit:in_combat() return self._in_combat end
    function unit:is_mounted() return self._is_mounted end
    function unit:is_dead() return self._is_dead end
    function unit:is_ghost() return self._is_ghost end
    function unit:is_casting() return self._is_casting end
    function unit:is_channeling() return self._is_channeling end

    return unit
end

-- ============================================================================
-- Global Setup / Teardown
-- ============================================================================
function Mock.setup_globals()
    _G.core = Mock.core
    _G.SentinelNavClient = Mock.SentinelNavClient
    _G.SentinelNavClient.client = Mock.SentinelNavClient.client
end

function Mock.teardown_globals()
    _G.core = nil
    _G.SentinelNavClient = nil
end

function Mock.reset()
    Mock.reset_time()
    Mock.clear_objects()
    Mock.clear_queued_spells()
    _spell_data = {}
    _nav_path = {}
    _nav_state = "IDLE"
    _local_player = nil
    _target = nil
end

return Mock