-- sentinel/tests/harness/mocks/sylvannas_api.lua
-- Mocks for documented Sylvannas API surface (core.object_manager, core.input,
-- core.log/core.log_error, _G.SentinelNavClient) plus a game_object-shaped mock
-- unit/player factory. Does NOT mock core.player / core.unit / core.spell /
-- core.spell_queue — those namespaces do not exist in the real Sylvannas API
-- (see docs/SylvannasAPI/dev/api/{object-manager,game-object,spellbook,
-- spellbook-helper}.md); real per-unit state is read via colon methods on the
-- game_object itself (e.g. unit:get_health()), and spell state via
-- core.spell_book.* / common/utility/spell_helper.
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
    function unit:get_distance()
        local player = Mock.core.object_manager.get_local_player()
        if not player or not player.get_position then
            return 0
        end
        local player_pos = player:get_position()
        local unit_pos = self:get_position()
        local dx = unit_pos.x - player_pos.x
        local dy = unit_pos.y - player_pos.y
        local dz = unit_pos.z - player_pos.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end
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
    _nav_path = {}
    _nav_state = "IDLE"
    _local_player = nil
    _target = nil
end

return Mock