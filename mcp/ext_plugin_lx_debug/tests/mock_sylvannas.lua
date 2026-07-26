------------------------------------------------------------
-- Offline mock of the Sylvannas injector surface.
--
-- Mirrors the shapes documented in docs/SylvannasAPI/dev/api/. Where the real
-- SDK and the mock disagree, the mock is wrong -- fix it here rather than
-- loosening the tests.
------------------------------------------------------------

local M = {}

------------------------------------------------------------
-- vec3
------------------------------------------------------------
local vec3 = {}
vec3.__index = vec3

function vec3.new(x, y, z)
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vec3)
end

function vec3:dist_to(other)
  local dx, dy, dz = self.x - other.x, self.y - other.y, self.z - other.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

M.vec3 = vec3

------------------------------------------------------------
-- Fake game object
--
-- Only the methods the real API actually exposes. Deliberately does NOT
-- define is_enemy / get_facing / get_active_auras -- those never existed, and
-- their absence is what the regression tests rely on.
------------------------------------------------------------
local unit = {}
unit.__index = unit

function M.unit(spec)
  spec = spec or {}
  return setmetatable({
    _name = spec.name or "Unit",
    _npc_id = spec.npc_id or 0,
    _level = spec.level or 1,
    _health = spec.health or 100,
    _max_health = spec.max_health or 100,
    _dead = spec.dead or false,
    _ghost = spec.ghost or false,
    _in_combat = spec.in_combat or false,
    _moving = spec.moving or false,
    _casting = spec.casting or false,
    _mounted = spec.mounted or false,
    _rotation = spec.rotation or 0,
    _valid = spec.valid ~= false,
    _pos = spec.pos or vec3.new(0, 0, 0),
    _hostile = spec.hostile or false,
    _quest_unit = spec.quest_unit or false,
    _tap_denied = spec.tap_denied or false,
    -- Scenery (signposts, mailboxes) carries a real npc_id but is NOT a unit.
    _is_unit = spec.is_unit ~= false,
    _is_player = spec.is_player or false,
    _powers = spec.powers or {},          -- [power_type_id] = {current, max}
    _buffs = spec.buffs or {},
    _debuffs = spec.debuffs or {},
    _target = spec.target,
    _item_id = spec.item_id,
    _stack = spec.stack,
  }, unit)
end

function unit:is_valid() return self._valid end
function unit:get_name() return self._name end
function unit:get_npc_id() return self._npc_id end
function unit:get_level() return self._level end
function unit:get_health() return self._health end
function unit:get_max_health() return self._max_health end
function unit:is_dead() return self._dead end
function unit:is_ghost() return self._ghost end
function unit:is_in_combat() return self._in_combat end
function unit:is_moving() return self._moving end
function unit:is_casting_spell() return self._casting end
function unit:is_mounted() return self._mounted end
function unit:is_quest_unit() return self._quest_unit end
function unit:is_unit() return self._is_unit end
function unit:is_player() return self._is_player end
function unit:is_basic_object() return not self._is_unit end
function unit:is_tap_denied() return self._tap_denied end
function unit:get_rotation() return self._rotation end
function unit:get_position() return self._pos end
function unit:get_target() return self._target end
function unit:get_buffs() return self._buffs end
function unit:get_debuffs() return self._debuffs end
function unit:get_auras()
  local all = {}
  for _, b in ipairs(self._buffs) do all[#all + 1] = b end
  for _, d in ipairs(self._debuffs) do all[#all + 1] = d end
  return all
end
function unit:get_item_id() return self._item_id end
function unit:get_item_stack_count() return self._stack end

-- Relational hostility, matching the real API.
function unit:is_enemy_with(other) return self._hostile and other ~= nil end
function unit:can_attack(other) return self._hostile and other ~= nil end

function unit:get_power(power_type)
  local p = self._powers[power_type]
  return p and p.current or 0
end

function unit:get_max_power(power_type)
  local p = self._powers[power_type]
  return p and p.max or 0
end

------------------------------------------------------------
-- Buff factory (docs/SylvannasAPI/dev/api/buffs.md field names)
------------------------------------------------------------
function M.buff(spec)
  return {
    buff_name = spec.name,
    buff_id = spec.id,
    count = spec.count or 1,
    expire_time = spec.expire_time or 0,
    duration = spec.duration or 0,
    type = spec.type or 0,
    caster = spec.caster,
    points = spec.points or {},
  }
end

------------------------------------------------------------
-- core
------------------------------------------------------------
function M.install(world)
  world = world or {}
  world.objects = world.objects or {}
  world.quest_log = world.quest_log or {}
  world.gossip = world.gossip or {}
  world.bags = world.bags or {}

  local recorded = {
    logs = {},
    files = {},
    http_get = {},
    http_post = {},
    input = {},
    quests = {},
  }

  local clock = 100.0

  local core = {}

  core.log = function(msg) recorded.logs[#recorded.logs + 1] = msg end
  core.log_error = core.log
  core.log_warning = core.log
  core.time = function() return clock end
  core.game_time = function() return clock * 1000 end
  core.get_map_id = function() return world.map_id or 0 end
  core.get_ping = function() return 42 end

  -- File IO
  core.create_data_folder = function() end
  core.create_data_file = function(path) recorded.files[path] = recorded.files[path] or "" end
  core.write_data_file = function(path, data) recorded.files[path] = data end
  core.read_data_file = function(path) return recorded.files[path] end

  -- HTTP. Callbacks are NOT invoked automatically; tests drive them so that
  -- in-flight behaviour (e.g. the poll guard) stays observable.
  core.http_get = function(url, headers, cb)
    if type(headers) == "function" then cb, headers = headers, {} end
    recorded.http_get[#recorded.http_get + 1] = { url = url, headers = headers, cb = cb }
  end
  core.http_post = function(url, headers, body, cb)
    if type(headers) == "string" then cb, body, headers = body, headers, {} end
    recorded.http_post[#recorded.http_post + 1] = { url = url, headers = headers, body = body, cb = cb }
  end

  -- Callbacks
  core.register_on_update_callback = function(fn) recorded.on_update = fn end
  core.register_on_game_event_callback = function(fn) recorded.on_game_event = fn end

  -- Object manager
  core.object_manager = {
    get_local_player = function() return world.player end,
    get_all_objects = function() return world.objects end,
    get_visible_objects = function() return world.objects end,
  }

  -- Inventory
  core.inventory = {
    get_items_in_bag = function(bag) return world.bags[bag] or {} end,
    get_gold = function() return world.gold or 0 end,
  }

  -- Input
  local function record_input(name)
    return function(...)
      recorded.input[#recorded.input + 1] = { fn = name, args = { ... } }
      return true
    end
  end
  core.input = {
    set_target = record_input("set_target"),
    interact_with_object = record_input("interact_with_object"),
    use_container_item = record_input("use_container_item"),
    loot_object = record_input("loot_object"),
    loot_item = record_input("loot_item"),
    close_loot = record_input("close_loot"),
    buy_item = record_input("buy_item"),
    repair_all_items = record_input("repair_all_items"),
    release_spirit = record_input("release_spirit"),
    resurrect_corpse = record_input("resurrect_corpse"),
  }

  -- Quests
  local function record_quest(name)
    return function(...)
      recorded.quests[#recorded.quests + 1] = { fn = name, args = { ... } }
    end
  end
  core.quests = {
    get_num_quest_log_entries = function() return #world.quest_log end,
    get_quest_log_title = function(i) return world.quest_log[i] end,
    get_num_quest_leader_boards = function(i)
      local e = world.quest_log[i]
      return e and e.objectives and #e.objectives or 0
    end,
    -- Returns a TABLE, not the string the published docs describe.
    -- Verified live against core 2.005 / TBC.
    get_quest_log_leader_board = function(obj_index, log_index)
      local e = world.quest_log[log_index]
      return e and e.objectives and e.objectives[obj_index]
    end,
    is_on_quest = function(id)
      for _, e in ipairs(world.quest_log) do
        if e.quest_id == id then return true end
      end
      return false
    end,
    is_quest_flagged_completed = function(id)
      return (world.completed_quests or {})[id] or false
    end,
    select_quest_log_entry = record_quest("select_quest_log_entry"),
    set_abandon_quest = record_quest("set_abandon_quest"),
    abandon_quest = record_quest("abandon_quest"),
    accept_quest = record_quest("accept_quest"),
    complete_quest = record_quest("complete_quest"),
    get_quest_reward = record_quest("get_quest_reward"),
    select_gossip_available_quest = record_quest("select_gossip_available_quest"),
    select_gossip_active_quest = record_quest("select_gossip_active_quest"),
    is_gossip_frame_shown = function() return world.gossip.shown or false end,
    get_gossip_options = function() return world.gossip.options or {} end,
    get_gossip_available_quests = function() return world.gossip.available or {} end,
    get_gossip_active_quests = function() return world.gossip.active or {} end,
  }

  -- game_ui. Absent from the published API docs entirely; enumerated live via
  -- dbg.inspect on core 2.005.
  core.game_ui = {
    get_all_completed_quest_ids = function() return world.completed_ids or {} end,
    get_loot_item_count = function() return #(world.loot or {}) end,
    get_loot_item_name = function(i) return (world.loot or {})[i] and world.loot[i].name end,
    get_loot_item_id = function(i) return (world.loot or {})[i] and world.loot[i].item_id end,
    get_loot_is_gold = function(i) return (world.loot or {})[i] and world.loot[i].is_gold or false end,
    get_vendor_item_count = function() return #(world.vendor or {}) end,
    get_vendor_item_info = function(i) return (world.vendor or {})[i] end,
    get_corpse_position = function() return world.corpse_position end,
    get_resurrect_corpse_delay = function() return world.resurrect_delay or 0 end,
  }

  -- Spell book
  core.spell_book = {
    is_player_in_control = function()
      if world.in_control == nil then return true end
      return world.in_control
    end,
    get_spell_name = function(id) return (world.spells or {})[id] and world.spells[id].name end,
    is_spell_known = function(id) return (world.spells or {})[id] ~= nil end,
    is_spell_learned = function(id) return (world.spells or {})[id] ~= nil end,
    is_usable_spell = function(id) return (world.spells or {})[id] and world.spells[id].usable or false end,
    get_spell_cooldown = function(id) return (world.spells or {})[id] and world.spells[id].cooldown or 0 end,
    get_global_cooldown = function() return 0 end,
    get_spell_cast_count = function() return 0 end,
    get_spell_costs = function() return {} end,
  }

  _G.core = core

  return {
    core = core,
    world = world,
    recorded = recorded,
    advance = function(seconds) clock = clock + seconds end,
    now = function() return clock end,
  }
end

------------------------------------------------------------
-- Module resolution for requires main.lua performs
------------------------------------------------------------
function M.preload()
  package.preload["common/geometry/vector_3"] = function() return vec3 end
  package.preload["common/izi_sdk"] = function() return {} end
  package.preload["common/utility/spell_helper"] = function()
    return {
      is_spell_in_range = function() return true end,
      is_spell_in_line_of_sight = function() return true end,
      is_spell_castable = function() return true end,
    }
  end
  package.preload["common/utility/auto_attack_helper"] = function()
    return { start_attack = function() end, ATTACK_TYPE = { MELEE = 1 } }
  end
end

return M
