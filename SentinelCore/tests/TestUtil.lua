local TestUtil = {}

---@param value any
---@return any
function TestUtil.deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[TestUtil.deep_copy(k)] = TestUtil.deep_copy(v)
    end
    return out
end

---@param overrides? table
---@return table
function TestUtil.install_core_stub(overrides)
    local previous_core = _G.core
    local previous_nav = _G.SentinelNavClient
    local previous_sc = _G.SentinelCore
    local previous_preload = {}
    local preload_keys = {
        "common/color",
        "common/geometry/vector_2",
        "common/enums",
    }
    rawset(_G, "__SentinelCoreHostCore", rawget(_G, "__SentinelCoreHostCore") or previous_core)

    local fs = {}
    local now = 1000
    local function _noop() end
    local function _false() return false end

    local core_stub = {
        time = function()
            return now
        end,
        _set_time = function(value)
            now = value
        end,
        delta_time = function()
            return 0.016
        end,
        log = function() end,
        log_warning = function() end,
        log_error = function() end,
        get_game_version = function()
            return "Classic Tbc"
        end,
        get_exact_game_version = function()
            return "classic_tbc"
        end,
        get_map_id = function()
            return 530
        end,
        get_instance_type = function()
            return "none"
        end,
        create_data_folder = function() end,
        create_data_file = function(path)
            if fs[path] == nil then
                fs[path] = ""
            end
        end,
        write_data_file = function(path, data)
            fs[path] = data
        end,
        read_data_file = function(path)
            return fs[path] or ""
        end,
        http_get = function(url, cb)
            cb(500, "application/json", "{}", "")
        end,
        object_manager = {
            get_local_player = function()
                return nil
            end,
            get_visible_objects = function()
                return {}
            end,
        },
        inventory = {
            get_items_in_bag = function()
                return {}
            end,
        },
        spell_book = {
            is_usable_spell = function()
                return true
            end,
            get_global_cooldown = function()
                return 0
            end,
        },
        input = {
            cast_target_spell = function() return true end,
            cast_self_spell = function() return true end,
            cast_position_spell = function() return true end,
            set_target = function() return true end,
            use_item = function() return true end,
            pet_cast_target_spell = function() return true end,
            pet_attack = function() return true end,
            loot_object = function() end,
            loot_item = function() end,
            close_loot = function() end,
            interact_with_object = function() end,
            interact = function() end,
            stop_moving = function() end,
            attack_target = function() end,
            use_container_item = function() end,
            is_key_pressed = function() return false end,
            cursor_has_spell = function() return false end,
        },
        game_ui = {
            get_loot_item_count = function() return 0 end,
            is_map_open = function() return false end,
            is_rendering_kick_warning = function() return false end,
        },
        graphics = setmetatable({}, {
            __index = function()
                return _noop
            end,
        }),
        utility = {
            timer_has_finished = _false,
        },
        menu = {
            tree_node = function() return { render = function(_, _, fn) if fn then fn() end end } end,
            button = function() return { render = function() return false end } end,
            checkbox = function()
                return {
                    render = function() return false end,
                    set = _noop,
                    get = _false,
                }
            end,
        },
        register_on_update_callback = function() end,
        register_on_render_menu_callback = function() end,
    }

    if overrides then
        for key, value in pairs(overrides) do
            core_stub[key] = value
        end
    end

    previous_preload["common/color"] = package.preload["common/color"]
    package.preload["common/color"] = function()
        return {
            new = function(r, g, b, a)
                return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 }
            end,
            white = function(a)
                return { r = 255, g = 255, b = 255, a = a or 255 }
            end,
        }
    end

    previous_preload["common/geometry/vector_2"] = package.preload["common/geometry/vector_2"]
    package.preload["common/geometry/vector_2"] = function()
        return {
            new = function(x, y)
                return { x = x or 0, y = y or 0 }
            end,
        }
    end

    previous_preload["common/enums"] = package.preload["common/enums"]
    package.preload["common/enums"] = function()
        return {
            window_enums = {
                font_id = {
                    FONT_SMALL = 0,
                    FONT_SEMI_BIG = 0,
                },
                window_resizing_flags = {
                    RESIZE_BOTH_AXIS = 0,
                },
                window_cross_visuals = {
                    DEFAULT = 0,
                },
                window_behaviour_flags = {
                    NO_SCROLLBAR = 0,
                },
            },
        }
    end

    _G.core = core_stub
    return {
        core = core_stub,
        fs = fs,
        restore = function()
            _G.core = previous_core or rawget(_G, "__SentinelCoreHostCore")
            _G.SentinelNavClient = previous_nav
            _G.SentinelCore = previous_sc
            for i = 1, #preload_keys do
                local key = preload_keys[i]
                package.preload[key] = previous_preload[key]
            end
        end,
    }
end

---@param props? table
---@return table
function TestUtil.mock_object(props)
    props = props or {}
    local obj = {
        _valid = props.valid ~= false,
        _dead = props.dead == true,
        _ghost = props.ghost == true,
        _unit = props.unit ~= false,
        _name = props.name or "Mock",
        _level = props.level or 1,
        _health = props.health or 100,
        _max_health = props.max_health or 100,
        _mana = props.mana or 100,
        _max_mana = props.max_mana or 100,
        _class_id = props.class_id or 2,
        _spec_id = props.spec_id or 0,
        _faction_id = props.faction_id or 0,
        _position = props.position or { x = 0, y = 0, z = 0 },
        _target = props.target,
        _npc_id = props.npc_id or 0,
        _item_id = props.item_id or 0,
        _in_combat = props.in_combat == true,
        _casting = props.casting == true,
        _channeling = props.channeling == true,
        _can_attack = props.can_attack ~= false,
        _is_enemy = props.is_enemy ~= false,
        _classification = props.classification or 0,
        _stack_count = props.stack_count or 1,
        _quality = props.quality or 0,
        _has_loot = props.has_loot == true,
        _can_be_looted = props.can_be_looted == true,
    }

    function obj:is_valid() return self._valid end
    function obj:is_unit() return self._unit end
    function obj:is_dead() return self._dead end
    function obj:is_ghost() return self._ghost end
    function obj:is_in_combat() return self._in_combat end
    function obj:is_casting_spell() return self._casting end
    function obj:is_channelling_spell() return self._channeling end
    function obj:get_position() return self._position end
    function obj:get_name() return self._name end
    function obj:get_level() return self._level end
    function obj:get_health() return self._health end
    function obj:get_max_health() return self._max_health end
    function obj:get_power() return self._mana end
    function obj:get_max_power() return self._max_mana end
    function obj:get_class() return self._class_id end
    function obj:get_specialization_id() return self._spec_id end
    function obj:get_faction_id() return self._faction_id end
    function obj:get_target() return self._target end
    function obj:get_npc_id() return self._npc_id end
    function obj:get_item_id() return self._item_id end
    function obj:get_item_stack_count() return self._stack_count end
    function obj:get_quality() return self._quality end
    function obj:get_xp() return props.xp or 0 end
    function obj:get_max_xp() return props.max_xp or 1000 end
    function obj:can_attack() return self._can_attack end
    function obj:is_enemy_with() return self._is_enemy end
    function obj:get_classification() return self._classification end
    function obj:has_loot() return self._has_loot end
    function obj:can_be_looted() return self._can_be_looted end
    function obj:get_guid() return props.guid or tostring(obj) end
    function obj:get_pet() return props.pet or nil end

    return obj
end

---@param value boolean
---@param message string
function TestUtil.assert_true(value, message)
    if not value then
        error(message)
    end
end

---@param actual any
---@param expected any
---@param message string
function TestUtil.assert_eq(actual, expected, message)
    if actual ~= expected then
        error(message .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

return TestUtil
