------------------------------------------------------------
-- ext_plugin_lx_debug - Live Debug Bridge v3
-- main.lua - Poll MCP server, dispatch commands, return results.
--
-- v3: results POST straight back to the bridge (no shared-disk dependency),
-- aura/hostility/power reads match the current Sylvannas API, and the questing
-- surface (quest log, gossip, vendor) has first-class helpers.
------------------------------------------------------------
local LxDebugPlugin = require("init")
local JSON = require("lib/JSON")

local VERSION = "3.0.0"
local BUILD = "45"
local SERVER_URL = "http://localhost:7778"
local MAX_RESULT_SIZE = 30000  -- cap JSON output to prevent overflow

-- enums.power_type -- get_power/get_max_power require an explicit type.
-- See docs/SylvannasAPI/dev/api/enums.md "Power Types".
local POWER_TYPES = {
  { id = 0,  name = "mana" },
  { id = 1,  name = "rage" },
  { id = 2,  name = "focus" },
  { id = 3,  name = "energy" },
  { id = 4,  name = "combo_points" },
  { id = 5,  name = "runes" },
  { id = 6,  name = "runic_power" },
  { id = 7,  name = "soul_shards" },
  { id = 8,  name = "lunar_power" },
  { id = 9,  name = "holy_power" },
  { id = 11, name = "maelstrom" },
  { id = 12, name = "chi" },
  { id = 13, name = "insanity" },
  { id = 16, name = "arcane_charges" },
  { id = 17, name = "fury" },
  { id = 18, name = "pain" },
  { id = 19, name = "essence" },
}

-- Ensure data folders exist
core.create_data_folder("lx_debug")

-- Deferred action queue (runs in on_update, not in HTTP callback)
local _deferred_actions = {}

------------------------------------------------------------
-- File write helper (create + write)
------------------------------------------------------------
local function write_file(path, content)
  core.create_data_file(path)
  core.write_data_file(path, content)
end

------------------------------------------------------------
-- Structured logger -- writes to both core.log and lx_debug.log
------------------------------------------------------------
local _log_lines = {}
local _log_max = 500
local _log_flush_t = 0
local _log_dirty = false

local function dlog(category, msg)
  local t = core.time()
  local mins = math.floor(t / 60)
  local secs = t - mins * 60
  local line = string.format("[%02d:%05.2f][%s] %s", mins, secs, category, msg)
  core.log("[LxDebug] " .. msg)
  _log_lines[#_log_lines + 1] = line
  if #_log_lines > _log_max then
    table.remove(_log_lines, 1)
  end
  _log_dirty = true
end

-- Flush log to disk periodically (every 2s when dirty)
local function flush_log()
  if not _log_dirty then return end
  local now = core.time()
  if now - _log_flush_t < 2.0 then return end
  _log_flush_t = now
  _log_dirty = false
  local content = table.concat(_log_lines, "\n")
  write_file("lx_debug/lx_debug.log", content)
end

-- Startup ping
core.http_get(SERVER_URL .. "/startup?version=" .. VERSION .. "&build=" .. BUILD, {}, function(code)
  if code == 200 then
    dlog("INIT", "Startup ping OK (v" .. VERSION .. " build " .. BUILD .. ")")
  else
    dlog("INIT", "Startup ping failed (code=" .. tostring(code) .. ")")
  end
end)

------------------------------------------------------------
-- dbg helpers
------------------------------------------------------------
local _dbg_last_result = nil
local dbg = {}

-- Get nav facade helper (used by nav_ functions)
local function get_nav()
  return (_G.SentinelNavClient and _G.SentinelNavClient.client)
    or (_G.NavLib and _G.NavLib.facade)
end

-- Get player helper
local function get_player()
  local p = core.object_manager.get_local_player()
  return (p and p:is_valid()) and p or nil
end

------------------------------------------------------------
-- Hostility
--
-- There is no unit:is_enemy(). Hostility is relational: is_enemy_with(other)
-- or can_attack(other). Callers must pass the reference unit.
------------------------------------------------------------
local function is_hostile_to(obj, reference)
  if not obj or not reference then return nil end
  if obj.is_enemy_with then
    local ok, v = pcall(obj.is_enemy_with, obj, reference)
    if ok and v ~= nil then return v end
  end
  if obj.can_attack then
    local ok, v = pcall(obj.can_attack, obj, reference)
    if ok and v ~= nil then return v end
  end
  return nil
end

------------------------------------------------------------
-- Power
--
-- get_power(power_type) requires an explicit type, so report every type the
-- unit actually has rather than guessing the class resource.
------------------------------------------------------------
local function read_powers(unit)
  if not unit or not unit.get_max_power then return nil end
  local out = nil
  for _, pt in ipairs(POWER_TYPES) do
    local max_ok, max_v = pcall(unit.get_max_power, unit, pt.id)
    if max_ok and type(max_v) == "number" and max_v > 0 then
      local cur_ok, cur_v = pcall(unit.get_power, unit, pt.id)
      out = out or {}
      out[pt.name] = { current = (cur_ok and cur_v) or 0, max = max_v }
    end
  end
  return out
end

------------------------------------------------------------
-- Aura normalisation
--
-- Raw buffs are {buff_name, buff_id, count, expire_time, duration, type,
-- caster, points} -- see docs/SylvannasAPI/dev/api/buffs.md.
------------------------------------------------------------
local function normalize_aura(a, kind)
  if type(a) ~= "table" then return nil end
  local caster_name = nil
  -- Duck-typed rather than checking for userdata: the caster is a game_object
  -- in game but a plain table under the offline harness.
  if a.caster and a.caster.get_name then
    local ok, n = pcall(a.caster.get_name, a.caster)
    if ok then caster_name = n end
  end
  local remaining = nil
  if type(a.expire_time) == "number" and a.expire_time > 0 then
    -- expire_time is game time; core.game_time() is ms on the same clock.
    local ok, now = pcall(core.game_time)
    if ok and type(now) == "number" then
      remaining = math.floor((a.expire_time - now) / 100) / 10
    else
      remaining = a.expire_time
    end
  end
  return {
    kind = kind,
    id = a.buff_id,
    name = a.buff_name or "?",
    stacks = a.count or 0,
    duration = a.duration,
    expire_time = a.expire_time,
    remaining = remaining,
    caster = caster_name,
  }
end

------------------------------------------------------------
-- dbg.help() -- list all available dbg functions
------------------------------------------------------------
function dbg.help()
  local cmds = {
    "-- Any core.* SDK path is callable directly; these are only the helpers",
    "-- that need more than one call to answer.",
    "",
    "DIAGNOSIS",
    "dbg.why_stuck()                  -- composite: player + nav + errors + verdict",
    "dbg.events(n?, filter?)          -- recent game events (newest last)",
    "dbg.errors(n?)                   -- UI_ERROR_MESSAGE only: the game's failure reasons",
    "dbg.log_tail(n?)                 -- last N plugin log lines (default 50)",
    "dbg.log_search(pattern, n?)      -- search plugin log for pattern",
    "",
    "QUESTING",
    "dbg.quest_log()                  -- all quests with parsed objectives",
    "dbg.quest_status(quest_id)       -- on_quest / complete / flagged + objectives",
    "dbg.quest_objectives(quest_id)   -- objectives only, with have/need counters",
    "dbg.gossip()                     -- gossip frame state, options, offered quests",
    "dbg.accept_quest(quest_id?)      -- select from gossip then accept",
    "dbg.turn_in_quest(id, reward?)   -- select, complete, take reward",
    "dbg.abandon_quest(quest_id)      -- select, mark, confirm",
    "",
    "GUIDE ADDONS (the addon's OWN parse -- cursor, not corpus)",
    "dbg.guides()                     -- which guide addons are actually loaded",
    "dbg.rxp()                        -- RestedXP: step + goals + stickies + waypoints",
    "dbg.rxp_step()                   -- RestedXP current step goals only",
    "dbg.rxp_waypoints()              -- RestedXP waypoints (normalized 0-1, no Z)",
    "dbg.rxp_objectives(quest_id)     -- RestedXP objective progress for a quest",
    "dbg.zygor()                      -- same probe against Zygor",
    "dbg.questie(quest_id?)           -- Questie quest DB in-game (QueryServer's data)",
    "",
    "STATE",
    "dbg.player_info()                -- player snapshot (position, powers, target)",
    "dbg.target_info()                -- target snapshot (hostility, quest unit, tap)",
    "dbg.auras(unit?)                 -- buffs + debuffs on 'player' or 'target'",
    "dbg.bag_scan(bag?)               -- bag contents with bag/slot indices",
    "dbg.nearby(range?, filter?)      -- 'all'|'npc'|'unit'|'object'|'player'|'hostile'|",
    "                                 -- 'friendly'|'dead'|'quest'  ('npc' excludes scenery)",
    "dbg.loot()                       -- loot window contents",
    "dbg.loot_slot(i) / dbg.loot_all()-- take loot",
    "dbg.vendor()                     -- open vendor's inventory",
    "dbg.corpse()                     -- corpse position + resurrect delay",
    "dbg.completed_quests(id?)        -- every completed quest id, or test one",
    "dbg.scan_units(range?)           -- living units in range",
    "dbg.find_vendor(range?)          -- NPCs in range, nearest first",
    "dbg.player_pos()                 -- player position",
    "dbg.in_combat()                  -- combat state",
    "dbg.target_hp()                  -- target health details",
    "dbg.gold()                       -- current gold",
    "dbg.inspect(path)                -- keys/methods on a table (e.g. 'core.input')",
    "",
    "NAVIGATION",
    "dbg.nav_report()                 -- full state, progress, destination, next waypoints",
    "dbg.nav_state()                  -- terse state + is_moving",
    "dbg.nav_to_target()              -- navigate to current target",
    "dbg.nav_move_to(pos)             -- navigate to {x=N, y=N, z=N}",
    "dbg.nav_validate(pos)            -- is this position reachable",
    "dbg.nav_stop()                   -- stop navigation",
    "dbg.nav_random_point(radius?)    -- find random navmesh point",
    "dbg.nav_wander(radius?)          -- move to a random point",
    "dbg.nav_get_heights(pos)         -- all navmesh heights at a position",
    "",
    "ACTIONS",
    "dbg.target_npc(npc_id)           -- target nearest alive NPC by id",
    "dbg.target_dead_npc(npc_id)      -- target nearest dead NPC by id",
    "dbg.interact_npc(npc_id)         -- target + interact with nearest alive NPC",
    "dbg.interact_target()            -- interact with current target",
    "dbg.attack_target()              -- auto-attack current target",
    "dbg.loot_target()                -- loot current target (must be dead)",
    "dbg.sell_item(bag, slot)         -- use_container_item(bag, slot)",
    "dbg.sell_test(npc_id, bag, slot) -- interact NPC + deferred sell + verify",
    "dbg.vendor_buy(index, qty?)      -- buy from the open vendor",
    "dbg.vendor_repair(guild_bank?)   -- repair all equipped items",
    "",
    "SPELLS",
    "dbg.spell_report(spell_id)       -- known/usable/cooldown/range/LoS/castable",
    "",
    "MISC",
    "dbg.http_get(url, headers?)      -- test an HTTP GET from inside the game",
    "dbg.last_result()                -- last async result",
    "dbg.test_lxdata2()               -- test LxData2 library",
    "dbg.fetch_item(id)               -- fetch item via LxData2",
  }
  return table.concat(cmds, "\n")
end

------------------------------------------------------------
-- dbg.player_info() -- comprehensive player state snapshot
------------------------------------------------------------
function dbg.player_info()
  local player = get_player()
  if not player then return "no valid player" end
  local pos = player:get_position()
  local info = {
    name = player:get_name(),
    level = player:get_level(),
    health = player:get_health(),
    max_health = player:get_max_health(),
    health_pct = player:get_max_health() > 0 and math.floor(player:get_health() / player:get_max_health() * 100) or 0,
    in_combat = player:is_in_combat(),
    is_dead = player:is_dead(),
    is_mounted = player:is_mounted(),
    position = { x = math.floor(pos.x * 10) / 10, y = math.floor(pos.y * 10) / 10, z = math.floor(pos.z * 10) / 10 },
    -- get_rotation() is the facing angle; there is no get_facing().
    rotation = player.get_rotation and math.floor((player:get_rotation() or 0) * 100) / 100 or nil,
    is_moving = player.is_moving and player:is_moving() or false,
    is_casting = player.is_casting_spell and player:is_casting_spell() or false,
    is_ghost = player.is_ghost and player:is_ghost() or false,
    map_id = select(2, pcall(core.get_map_id)),
  }
  info.power = read_powers(player)
  -- Target
  local target = player:get_target()
  if target and target:is_valid() then
    info.target_name = target:get_name()
    info.target_npc_id = target:get_npc_id()
    local td = target:get_position():dist_to(pos)
    info.target_dist = math.floor(td * 10) / 10
  else
    info.target_name = "none"
  end
  -- Nav state
  local nav = get_nav()
  if nav then
    info.nav_state = nav:get_state()
    info.nav_moving = nav:is_moving()
  end
  dlog("INFO", "player_info: " .. info.name .. " L" .. info.level .. " HP=" .. info.health_pct .. "%")
  return info
end

------------------------------------------------------------
-- dbg.target_info() -- comprehensive target state snapshot
------------------------------------------------------------
function dbg.target_info()
  local player = get_player()
  if not player then return "no valid player" end
  local target = player:get_target()
  if not target or not target:is_valid() then return "no target" end
  local pos = target:get_position()
  local ppos = player:get_position()
  local info = {
    name = target:get_name(),
    npc_id = target:get_npc_id(),
    level = target:get_level(),
    health = target:get_health(),
    max_health = target:get_max_health(),
    health_pct = target:get_max_health() > 0 and math.floor(target:get_health() / target:get_max_health() * 100) or 0,
    is_dead = target:is_dead(),
    distance = math.floor(ppos:dist_to(pos) * 10) / 10,
    position = { x = math.floor(pos.x * 10) / 10, y = math.floor(pos.y * 10) / 10, z = math.floor(pos.z * 10) / 10 },
  }
  info.is_hostile = is_hostile_to(target, player)
  info.power = read_powers(target)
  if target.is_in_combat then
    local ok, v = pcall(target.is_in_combat, target)
    if ok then info.in_combat = v end
  end
  if target.is_quest_unit then
    local ok, v = pcall(target.is_quest_unit, target)
    if ok then info.is_quest_unit = v end
  end
  if target.is_tap_denied then
    local ok, v = pcall(target.is_tap_denied, target)
    if ok then info.tap_denied = v end
  end
  dlog("INFO", "target_info: " .. info.name .. " npc=" .. tostring(info.npc_id) .. " dist=" .. info.distance)
  return info
end

------------------------------------------------------------
-- dbg.bag_scan(bag?) -- comprehensive bag contents
-- Returns detailed info: bag, raw_slot, container_slot, item_id, name, stack_count
------------------------------------------------------------
function dbg.bag_scan(bag_filter)
  local player = get_player()
  if not player then return "no valid player" end
  bag_filter = bag_filter and tonumber(bag_filter) or nil

  local results = {}
  local start_bag = bag_filter or 0
  local end_bag = bag_filter or 4

  for bag = start_bag, end_bag do
    local items = core.inventory.get_items_in_bag(bag)
    if items then
      for _, slot in ipairs(items) do
        local obj = slot.object
        if obj and obj:is_valid() then
          local sid = slot.slot_id
          -- Skip non-storage slots for bag 0
          if bag == 0 and (sid < 36 or sid > 51) then goto bag_continue end

          local container_slot = bag == 0 and (sid - 36) or (sid - 1)
          local item_id = obj:get_item_id()
          local name = obj:get_name() or "?"
          local stack = 1
          if obj.get_item_stack_count then
            local ok, sc = pcall(obj.get_item_stack_count, obj)
            if ok and sc then stack = sc end
          end

          results[#results + 1] = {
            bag = bag,
            raw_slot = sid,
            slot = container_slot,
            item_id = item_id,
            name = name,
            stack = stack,
          }
          ::bag_continue::
        end
      end
    end
  end

  dlog("BAG", "bag_scan: " .. #results .. " items" .. (bag_filter and (" in bag " .. bag_filter) or " in all bags"))
  write_file("lx_debug/bag_scan.json", JSON.encode({ count = #results, items = results }))
  return { count = #results, items = results }
end

------------------------------------------------------------
-- dbg.nearby(range?, filter?) -- nearby objects with detailed info
-- filter: "all" (default), "hostile", "friendly", "npc", "dead", "player"
------------------------------------------------------------
function dbg.nearby(range, filter)
  range = tonumber(range) or 100
  filter = filter or "all"
  local player = get_player()
  if not player then return "no valid player" end
  local ppos = player:get_position()
  local player_name = player:get_name()
  local all = core.object_manager.get_all_objects()
  local results = {}

  for _, obj in pairs(all) do
    if obj and obj.is_valid and obj:is_valid() and obj.get_position and obj.get_name then
      local name = obj:get_name() or "?"
      if name == player_name then goto nearby_continue end

      local pos = obj:get_position()
      local dist = pos:dist_to(ppos)
      if dist > range then goto nearby_continue end

      local dead = obj.is_dead and obj:is_dead() or false
      local npc_id = obj.get_npc_id and obj:get_npc_id() or 0
      local lvl = obj.get_level and obj:get_level() or 0
      local hp = obj.get_health and obj:get_health() or 0
      local max_hp = obj.get_max_health and obj:get_max_health() or 0
      local is_enemy = is_hostile_to(obj, player) or false
      local quest_unit = false
      if obj.is_quest_unit then
        local ok, v = pcall(obj.is_quest_unit, obj)
        if ok then quest_unit = v or false end
      end

      -- Signposts, mailboxes and flight masters all carry a non-zero npc_id,
      -- so npc_id alone cannot separate creatures from scenery. is_unit() can:
      -- a signpost reports is_unit=false / is_basic_object=true. Those objects
      -- also report is_dead=true and level=-1, which is pure noise in a scan.
      local is_unit_obj = false
      if obj.is_unit then
        local ok, v = pcall(obj.is_unit, obj)
        if ok then is_unit_obj = v or false end
      end
      local is_player_obj = false
      if obj.is_player then
        local ok, v = pcall(obj.is_player, obj)
        if ok then is_player_obj = v or false end
      end

      -- Apply filter
      if filter == "hostile" and not is_enemy then goto nearby_continue end
      if filter == "friendly" and is_enemy then goto nearby_continue end
      if filter == "npc" and (not is_unit_obj or is_player_obj) then goto nearby_continue end
      if filter == "unit" and not is_unit_obj then goto nearby_continue end
      if filter == "object" and is_unit_obj then goto nearby_continue end
      if filter == "dead" and not dead then goto nearby_continue end
      if filter == "player" and not is_player_obj then goto nearby_continue end
      if filter == "quest" and not quest_unit then goto nearby_continue end

      results[#results + 1] = {
        name = name,
        npc_id = npc_id,
        level = lvl,
        dist = math.floor(dist * 10) / 10,
        hp = hp,
        max_hp = max_hp,
        dead = dead,
        enemy = is_enemy,
        quest_unit = quest_unit,
        is_unit = is_unit_obj,
        is_player = is_player_obj,
        pos = { x = math.floor(pos.x * 10) / 10, y = math.floor(pos.y * 10) / 10, z = math.floor(pos.z * 10) / 10 },
      }
      ::nearby_continue::
    end
  end

  table.sort(results, function(a, b) return a.dist < b.dist end)
  -- Cap at 50 to avoid huge responses
  local shown = math.min(#results, 50)
  local trimmed = {}
  for i = 1, shown do trimmed[i] = results[i] end

  dlog("SCAN", string.format("nearby: %d objects in %dyd (filter=%s, shown=%d)", #results, range, filter, shown))
  write_file("lx_debug/nearby.json", JSON.encode({ total = #results, shown = shown, filter = filter, objects = trimmed }))
  return { total = #results, shown = shown, objects = trimmed }
end

------------------------------------------------------------
-- dbg.auras(unit?) -- list auras on player or target
------------------------------------------------------------
function dbg.auras(unit_type)
  unit_type = unit_type or "player"
  local player = get_player()
  if not player then return "no valid player" end

  local unit = player
  if unit_type == "target" then
    unit = player:get_target()
    if not unit or not unit:is_valid() then return "no target" end
  end

  local results = {}
  local function collect(method, kind)
    if not unit[method] then return end
    local ok, auras = pcall(unit[method], unit)
    if not ok or type(auras) ~= "table" then return end
    for _, a in ipairs(auras) do
      local norm = normalize_aura(a, kind)
      if norm then results[#results + 1] = norm end
    end
  end

  -- Prefer the split buff/debuff reads so each aura carries its polarity;
  -- fall back to the combined list when they are unavailable.
  collect("get_buffs", "buff")
  collect("get_debuffs", "debuff")
  if #results == 0 then collect("get_auras", "aura") end

  local name = unit:get_name() or "?"
  dlog("AURA", string.format("auras on %s (%s): %d auras", name, unit_type, #results))
  return { unit = name, count = #results, auras = results }
end

------------------------------------------------------------
-- dbg.inspect(path) -- list keys/methods on a table
-- Usage: dbg.inspect("core.input"), dbg.inspect("player"), dbg.inspect("dbg")
------------------------------------------------------------
function dbg.inspect(root_path)
  -- Handle case where resolver replaced string with the actual table
  if type(root_path) == "table" or type(root_path) == "userdata" then
    local obj = root_path
    local label = tostring(root_path)
    -- Enumerate directly
    local fields, methods, values = {}, {}, {}
    if type(obj) == "table" then
      for k, v in pairs(obj) do
        local kstr = tostring(k)
        if type(v) == "function" then methods[#methods + 1] = kstr
        else fields[#fields + 1] = kstr; values[kstr] = type(v) == "table" and "<table>" or tostring(v)
        end
      end
      local mt = getmetatable(obj)
      if mt and mt.__index and type(mt.__index) == "table" then
        for k, v in pairs(mt.__index) do
          if type(v) == "function" then methods[#methods + 1] = tostring(k) .. " (meta)" end
        end
      end
    elseif type(obj) == "userdata" then
      local mt = getmetatable(obj)
      if mt then
        for k, v in pairs(mt) do
          if type(v) == "function" then methods[#methods + 1] = tostring(k) end
        end
        if mt.__index and type(mt.__index) == "table" then
          for k, v in pairs(mt.__index) do
            if type(v) == "function" then methods[#methods + 1] = tostring(k) end
          end
        end
      end
    end
    table.sort(fields); table.sort(methods)
    return { path = label, type = type(obj), fields = fields, methods = methods, sample_values = values, field_count = #fields, method_count = #methods }
  end

  if not root_path or root_path == "" then return "path required (e.g. 'core.input', 'player')" end

  local player = core.object_manager.get_local_player()
  local roots = {
    core = core,
    izi = require("common/izi_sdk"),
    player = (player and player:is_valid()) and player or nil,
    target = (player and player:is_valid()) and player:get_target() or nil,
    dbg = dbg,
    nav = get_nav(),
  }

  -- Walk the path
  local parts = {}
  for part in root_path:gmatch("[^.:]+") do
    parts[#parts + 1] = part
  end

  local obj = roots[parts[1]]
  if not obj then return "unknown root: " .. parts[1] end

  for i = 2, #parts do
    if obj == nil then return "nil at path segment: " .. parts[i - 1] end
    local next_val = obj[parts[i]]
    if next_val == nil then return "nil at path segment: " .. parts[i] end
    obj = next_val
  end

  -- Enumerate keys
  local fields = {}
  local methods = {}
  local values = {}

  if type(obj) == "table" then
    for k, v in pairs(obj) do
      local kstr = tostring(k)
      if type(v) == "function" then
        methods[#methods + 1] = kstr
      else
        fields[#fields + 1] = kstr
        values[kstr] = type(v) == "table" and "<table>" or tostring(v)
      end
    end
    -- Check metatable
    local mt = getmetatable(obj)
    if mt and mt.__index and type(mt.__index) == "table" then
      for k, v in pairs(mt.__index) do
        local kstr = tostring(k)
        if type(v) == "function" then
          if not methods[kstr] then methods[#methods + 1] = kstr .. " (meta)" end
        end
      end
    end
  elseif type(obj) == "userdata" then
    -- Userdata: try metatable
    local mt = getmetatable(obj)
    if mt then
      for k, v in pairs(mt) do
        local kstr = tostring(k)
        if type(v) == "function" then
          methods[#methods + 1] = kstr
        elseif kstr ~= "__index" and kstr ~= "__newindex" then
          fields[#fields + 1] = kstr
        end
      end
      if mt.__index and type(mt.__index) == "table" then
        for k, v in pairs(mt.__index) do
          local kstr = tostring(k)
          if type(v) == "function" then
            methods[#methods + 1] = kstr
          end
        end
      end
    end
  else
    return "not a table or userdata: type=" .. type(obj) .. " value=" .. tostring(obj)
  end

  table.sort(fields)
  table.sort(methods)

  dlog("INSPECT", string.format("inspect '%s': %d fields, %d methods", root_path, #fields, #methods))
  return {
    path = root_path,
    type = type(obj),
    fields = fields,
    methods = methods,
    sample_values = values,
    field_count = #fields,
    method_count = #methods,
  }
end

------------------------------------------------------------
-- dbg.interact_npc(npc_id) -- find nearest alive NPC, target + interact
------------------------------------------------------------
function dbg.interact_npc(npc_id)
  npc_id = tonumber(npc_id)
  if not npc_id then return "npc_id required" end
  local player = get_player()
  if not player then return "no valid player" end
  local ppos = player:get_position()
  local all = core.object_manager.get_all_objects()
  local best, best_dist = nil, math.huge
  for _, obj in pairs(all) do
    if obj and obj.is_valid and obj:is_valid()
      and obj.get_npc_id and obj:get_npc_id() == npc_id
      and obj.is_dead and not obj:is_dead()
      and obj.get_position then
      local d = obj:get_position():dist_to(ppos)
      if d < best_dist then
        best = obj
        best_dist = d
      end
    end
  end
  if not best then return "no alive NPC with id " .. npc_id .. " found" end
  core.input.set_target(best)
  core.input.interact_with_object(best)
  local name = best:get_name() or "?"
  local msg = string.format("Targeted + interacting: %s (npc=%d) at %.1fyd", name, npc_id, best_dist)
  dlog("NPC", msg)
  return msg
end

------------------------------------------------------------
-- dbg.sell_item(bag, slot) -- sell item by bag+slot
------------------------------------------------------------
function dbg.sell_item(bag, slot)
  bag = tonumber(bag)
  slot = tonumber(slot)
  if not bag or not slot then return "bag and slot required (both numbers)" end
  dlog("SELL", string.format("use_container_item(%d, %d)", bag, slot))
  core.input.use_container_item(bag, slot)
  return string.format("use_container_item(%d, %d) called", bag, slot)
end

------------------------------------------------------------
-- dbg.sell_test(npc_id, bag, slot) -- interact with NPC, wait, then sell
-- Runs entirely in-game loop to avoid MCP latency issues
------------------------------------------------------------
function dbg.sell_test(npc_id, bag, slot)
  npc_id = tonumber(npc_id)
  bag = tonumber(bag)
  slot = tonumber(slot)
  if not npc_id or not bag or not slot then return "usage: sell_test(npc_id, bag, slot)" end

  -- Find the NPC
  local objects = core.object_manager.get_all_objects()
  local npc_obj = nil
  for _, obj in pairs(objects) do
    if obj:is_valid() and obj:get_npc_id() == npc_id then
      npc_obj = obj
      break
    end
  end
  if not npc_obj then return "NPC " .. npc_id .. " not found nearby" end

  local npc_name = npc_obj:get_name() or "?"
  dlog("SELL", string.format("sell_test: interact with %s (%d), then sell bag=%d slot=%d in 1.5s", npc_name, npc_id, bag, slot))

  -- Step 1: target + interact now
  core.input.set_target(npc_obj)
  core.input.interact_with_object(npc_obj)

  -- Step 2: deferred sell after 1.5 seconds
  local sell_time = core.time() + 1.5
  _deferred_actions[#_deferred_actions + 1] = {
    time = sell_time,
    fn = function()
      dlog("SELL", string.format("sell_test: executing use_container_item(%d, %d)", bag, slot))
      core.input.use_container_item(bag, slot)

      -- Log result after another 0.5s
      _deferred_actions[#_deferred_actions + 1] = {
        time = core.time() + 0.5,
        fn = function()
          -- Check if the item is still there
          local items = core.inventory.get_items_in_bag(bag)
          local found = false
          if items then
            for _, s in ipairs(items) do
              local sid = s.slot_id
              local cs = bag == 0 and (sid - 36) or (sid - 1)
              if cs == slot then
                found = true
                local name = s.object and s.object:is_valid() and s.object:get_name() or "?"
                dlog("SELL", string.format("sell_test: item STILL at bag=%d slot=%d: %s (SELL FAILED)", bag, slot, name))
                break
              end
            end
          end
          if not found then
            dlog("SELL", string.format("sell_test: bag=%d slot=%d is now EMPTY (SELL SUCCEEDED)", bag, slot))
          end
        end,
      }
    end,
  }

  return string.format("sell_test: interacting with %s, will sell bag=%d slot=%d in 1.5s (check dbg.log_tail())", npc_name, bag, slot)
end

------------------------------------------------------------
-- dbg.log_tail(n?) -- return last N log lines
------------------------------------------------------------
function dbg.log_tail(n)
  n = tonumber(n) or 50
  local start = math.max(1, #_log_lines - n + 1)
  local lines = {}
  for i = start, #_log_lines do
    lines[#lines + 1] = _log_lines[i]
  end
  return table.concat(lines, "\n")
end

------------------------------------------------------------
-- dbg.log_search(pattern, n?) -- search log lines for pattern
------------------------------------------------------------
function dbg.log_search(pattern, n)
  if not pattern then return "pattern required" end
  n = tonumber(n) or 100
  local matches = {}
  for i = #_log_lines, 1, -1 do
    if _log_lines[i]:find(pattern, 1, true) then
      matches[#matches + 1] = _log_lines[i]
      if #matches >= n then break end
    end
  end
  -- Reverse so newest is last
  local reversed = {}
  for i = #matches, 1, -1 do reversed[#reversed + 1] = matches[i] end
  return table.concat(reversed, "\n")
end

------------------------------------------------------------
-- Questing helpers
--
-- These wrap multi-call sequences that the generic path resolver cannot
-- express in one round-trip (walking the log, correlating objectives to a
-- quest id, reading gossip frame state). Single-call SDK functions are
-- intentionally NOT wrapped -- reach them directly via core.quests.*.
------------------------------------------------------------

-- Quest log index for a quest id, or nil. Headers are skipped.
local function find_quest_log_index(quest_id)
  local n = core.quests.get_num_quest_log_entries() or 0
  for i = 1, n do
    local info = core.quests.get_quest_log_title(i)
    if info and not info.is_header and info.quest_id == quest_id then
      return i, info
    end
  end
  return nil
end

-- get_quest_log_leader_board returns a TABLE on this client
-- ({description, is_completed, objective_type}), not the string the published
-- docs describe. Verified live against core 2.005 / TBC.
local function read_objectives(log_index)
  local objectives = {}
  local num = core.quests.get_num_quest_leader_boards(log_index) or 0
  for oi = 1, num do
    local board = core.quests.get_quest_log_leader_board(oi, log_index)
    if board then
      local text, done, kind
      if type(board) == "table" then
        text = board.description
        done = board.is_completed
        kind = board.objective_type
      else
        text = tostring(board)
      end

      -- Counters are embedded in the description ("Large Candle: 3/8"); pull
      -- them out so callers can compare progress numerically.
      local have, need
      if type(text) == "string" then
        have, need = text:match("(%d+)%s*/%s*(%d+)")
        have, need = tonumber(have), tonumber(need)
      end
      -- Spelled out rather than `a and b or c`: that idiom collapses a
      -- legitimate `false` into `nil`.
      if done == nil and have and need then done = have >= need end

      objectives[#objectives + 1] = {
        index = oi,
        text = text,
        objective_type = kind,
        have = have,
        need = need,
        done = done,
      }
    end
  end
  return objectives
end

-- The quest log title table carries no completion flag on this client, so
-- completeness is derived: every objective reporting done.
local function objectives_complete(objectives)
  if not objectives or #objectives == 0 then return nil end
  for _, o in ipairs(objectives) do
    if o.done ~= true then return false end
  end
  return true
end

-- dbg.quest_log() -- every non-header entry with its objectives
function dbg.quest_log()
  local n = core.quests.get_num_quest_log_entries() or 0
  local quests = {}
  for i = 1, n do
    local info = core.quests.get_quest_log_title(i)
    if info and not info.is_header then
      local objectives = read_objectives(i)
      quests[#quests + 1] = {
        log_index = i,
        quest_id = info.quest_id,
        title = info.title,
        level = info.level,
        is_task = info.is_task,
        is_complete = objectives_complete(objectives),
        objectives = objectives,
      }
    end
  end
  local out = { count = #quests, entries = n, quests = quests }
  dlog("QUEST", string.format("quest_log: %d quests (%d log entries)", #quests, n))
  write_file("lx_debug/quest_log.json", JSON.encode(out))
  return out
end

-- dbg.quest_status(quest_id) -- the single question the runner keeps asking:
-- am I on it, is it done, has it ever been completed?
function dbg.quest_status(quest_id)
  quest_id = tonumber(quest_id)
  if not quest_id then return "quest_id required" end
  local log_index, info = find_quest_log_index(quest_id)
  local objectives = log_index and read_objectives(log_index) or nil
  local status = {
    quest_id = quest_id,
    on_quest = core.quests.is_on_quest(quest_id) or false,
    flagged_completed = core.quests.is_quest_flagged_completed(quest_id) or false,
    in_log = log_index ~= nil,
    log_index = log_index,
    title = info and info.title or nil,
    objectives = objectives,
  }
  -- Assigned separately so a genuine `false` survives; the `a and b or c`
  -- idiom would turn "in the log but not complete" into nil.
  if objectives then status.is_complete = objectives_complete(objectives) end
  dlog("QUEST", string.format("quest_status %d: on=%s complete=%s flagged=%s",
    quest_id, tostring(status.on_quest), tostring(status.is_complete), tostring(status.flagged_completed)))
  return status
end

-- dbg.quest_objectives(quest_id) -- objectives only
function dbg.quest_objectives(quest_id)
  quest_id = tonumber(quest_id)
  if not quest_id then return "quest_id required" end
  local log_index = find_quest_log_index(quest_id)
  if not log_index then return "quest " .. quest_id .. " is not in the quest log" end
  return { quest_id = quest_id, objectives = read_objectives(log_index) }
end

-- dbg.gossip() -- full gossip/quest-giver frame state in one call
function dbg.gossip()
  local shown = core.quests.is_gossip_frame_shown()
  local out = {
    gossip_frame_shown = shown or false,
    options = core.quests.get_gossip_options() or {},
    available_quests = core.quests.get_gossip_available_quests() or {},
    active_quests = core.quests.get_gossip_active_quests() or {},
  }
  local player = get_player()
  local target = player and player:get_target()
  if target and target:is_valid() then
    out.npc = { name = target:get_name(), npc_id = target:get_npc_id() }
  end
  dlog("QUEST", string.format("gossip: shown=%s opts=%d avail=%d active=%d",
    tostring(out.gossip_frame_shown), #out.options, #out.available_quests, #out.active_quests))
  return out
end

-- dbg.accept_quest(quest_id?) -- select from gossip when given an id, then accept
function dbg.accept_quest(quest_id)
  quest_id = tonumber(quest_id)
  if quest_id then
    core.quests.select_gossip_available_quest(quest_id)
    -- The quest detail frame needs a frame to appear before accept lands.
    _deferred_actions[#_deferred_actions + 1] = {
      time = core.time() + 0.5,
      fn = function()
        core.quests.accept_quest()
        dlog("QUEST", "accept_quest: accepted " .. quest_id)
      end,
    }
    return "selected quest " .. quest_id .. " from gossip, accepting in 0.5s"
  end
  core.quests.accept_quest()
  dlog("QUEST", "accept_quest: accepted currently offered quest")
  return "accept_quest() called on the currently offered quest"
end

-- dbg.turn_in_quest(quest_id, reward_index?) -- select, complete, take reward
function dbg.turn_in_quest(quest_id, reward_index)
  quest_id = tonumber(quest_id)
  if not quest_id then return "quest_id required" end
  reward_index = tonumber(reward_index) or 1

  core.quests.select_gossip_active_quest(quest_id)
  _deferred_actions[#_deferred_actions + 1] = {
    time = core.time() + 0.5,
    fn = function()
      core.quests.complete_quest()
      dlog("QUEST", "turn_in_quest: complete_quest for " .. quest_id)
      _deferred_actions[#_deferred_actions + 1] = {
        time = core.time() + 0.5,
        fn = function()
          core.quests.get_quest_reward(reward_index)
          dlog("QUEST", string.format("turn_in_quest: took reward %d for %d", reward_index, quest_id))
        end,
      }
    end,
  }
  return string.format("turning in quest %d (reward %d) -- check dbg.log_tail()", quest_id, reward_index)
end

-- dbg.abandon_quest(quest_id) -- select, mark, confirm
function dbg.abandon_quest(quest_id)
  quest_id = tonumber(quest_id)
  if not quest_id then return "quest_id required" end
  local log_index = find_quest_log_index(quest_id)
  if not log_index then return "quest " .. quest_id .. " is not in the quest log" end
  core.quests.select_quest_log_entry(log_index)
  core.quests.set_abandon_quest()
  core.quests.abandon_quest()
  dlog("QUEST", "abandon_quest: abandoned " .. quest_id)
  return "abandoned quest " .. quest_id
end

-- dbg.completed_quests(quest_id?) -- bulk completion set
--
-- core.game_ui.get_all_completed_quest_ids() returns every quest this
-- character has ever completed in one call, which is far cheaper than probing
-- is_quest_flagged_completed per id when validating a whole guide.
function dbg.completed_quests(quest_id)
  local ok, ids = pcall(core.game_ui.get_all_completed_quest_ids)
  if not ok or type(ids) ~= "table" then
    return "get_all_completed_quest_ids unavailable: " .. tostring(ids)
  end

  quest_id = tonumber(quest_id)
  if quest_id then
    for _, id in ipairs(ids) do
      if id == quest_id then return { quest_id = quest_id, completed = true, total = #ids } end
    end
    return { quest_id = quest_id, completed = false, total = #ids }
  end

  -- The full set is large; return a sample plus the count rather than
  -- flooding the transport.
  local sample = {}
  for i = 1, math.min(#ids, 25) do sample[i] = ids[i] end
  dlog("QUEST", "completed_quests: " .. #ids .. " total")
  write_file("lx_debug/completed_quests.json", JSON.encode({ total = #ids, ids = ids }))
  return {
    total = #ids,
    sample = sample,
    note = "full list written to scripts_data/lx_debug/completed_quests.json",
  }
end

------------------------------------------------------------
-- Guide addon bridge (core.addons.rested_xp / zygor / questie)
--
-- These read a GUIDE ADDON's own parsed state out of the WoW addon environment.
-- That matters because it is the one source of guide semantics the offline
-- importer cannot reach: the addon has already lexed the guide, resolved its
-- directives, and evaluates per-goal completion live.
--
-- IMPORTANT SHAPE: this is a CURSOR, not a corpus. `get_current_step()` returns
-- only the step the addon is on right now, and `get_step_waypoints()` explicitly
-- excludes look-ahead. There is no "give me every step of guide X" call, so this
-- surface can drive a follow-the-addon runner but cannot be compiled ahead of
-- time the way a Runtime Profile is.
--
-- Every helper degrades to { loaded = false } rather than erroring, so they are
-- safe to call before the addon is installed or enabled.
------------------------------------------------------------

--- The addon namespaces all exist on core.addons whether or not the addon is
--- installed, so presence proves nothing — is_loaded() is the only real gate.
local function guide_ns(name)
  local ns = core.addons and core.addons[name]
  if not ns or not ns.is_loaded then return nil end
  local ok, loaded = pcall(ns.is_loaded)
  if not ok or loaded ~= true then return nil end
  return ns
end

--- Normalize one rested_xp/zygor step into a plain table.
--- `action` is the guide directive verb (goto, complete, accept, turnin, mob, ...)
--- and is the field worth studying — it is the addon's own parse of the guide
--- line that the offline importer has to reconstruct from text.
local function read_guide_step(step)
  if type(step) ~= "table" then return nil end
  local goals = {}
  for i, g in ipairs(step.goals or {}) do
    goals[i] = {
      action = g.action,
      quest_id = g.quest_id,
      text = g.text,
      is_complete = g.is_complete,
      text_only = g.text_only,
      ids = g.ids,
    }
  end
  return { num = step.num, is_complete = step.is_complete, goals = goals }
end

local function read_waypoint(w)
  if type(w) ~= "table" then return nil end
  return {
    map_id = w.map_id,
    x = w.x,                        -- normalized 0-1, NOT world coordinates
    y = w.y,
    dist = w.dist,
    title = w.title,
    type = w.type,
    goal_num = w.goal_num,
    is_manual = w.is_manual,
    wrong_continent = w.wrong_continent,
  }
end

-- dbg.rxp() -- one-call snapshot of everything RestedXP currently exposes.
-- This is the probe for "would following the addon beat parsing its guides?".
function dbg.rxp()
  local r = guide_ns("rested_xp")
  if not r then return { loaded = false, note = "RestedXP Guides is not loaded" } end

  local has_step = false
  local ok_h, h = pcall(r.has_current_step)
  if ok_h then has_step = h == true end

  local step = nil
  if has_step then
    local ok_s, s = pcall(r.get_current_step)
    if ok_s then step = read_guide_step(s) end
  end

  local stickies = {}
  local ok_st, st = pcall(r.get_current_stickies)
  if ok_st and type(st) == "table" then
    for i, s in ipairs(st) do stickies[i] = read_guide_step(s) end
  end

  local waypoint = nil
  local ok_w, w = pcall(r.get_current_waypoint)
  if ok_w then waypoint = read_waypoint(w) end

  local waypoints = {}
  local ok_ws, ws = pcall(r.get_step_waypoints)
  if ok_ws and type(ws) == "table" then
    for i, one in ipairs(ws) do waypoints[i] = read_waypoint(one) end
  end

  local out = {
    loaded = true,
    has_current_step = has_step,
    step = step,
    stickies = stickies,
    current_waypoint = waypoint,
    step_waypoints = waypoints,
  }
  dlog("RXP", string.format("rxp: step=%s goals=%d stickies=%d waypoints=%d",
    tostring(step and step.num), step and #step.goals or 0, #stickies, #waypoints))
  write_file("lx_debug/rxp.json", JSON.encode(out))
  return out
end

-- dbg.rxp_step() -- the current step's goals only (the guide-semantics view)
function dbg.rxp_step()
  local r = guide_ns("rested_xp")
  if not r then return { loaded = false } end
  local ok_h, h = pcall(r.has_current_step)
  if not (ok_h and h == true) then return { loaded = true, has_current_step = false } end
  local ok_s, s = pcall(r.get_current_step)
  if not ok_s then return { loaded = true, error = tostring(s) } end
  return { loaded = true, has_current_step = true, step = read_guide_step(s) }
end

-- dbg.rxp_waypoints() -- every waypoint for the ACTIVE steps.
-- Coordinates are normalized 0-1 per map_id and carry no Z, exactly like the
-- guide text the importer reads — so this does NOT solve ground height.
function dbg.rxp_waypoints()
  local r = guide_ns("rested_xp")
  if not r then return { loaded = false } end
  local out = {}
  local ok_ws, ws = pcall(r.get_step_waypoints)
  if ok_ws and type(ws) == "table" then
    for i, w in ipairs(ws) do out[i] = read_waypoint(w) end
  end
  local current = nil
  local ok_w, w = pcall(r.get_current_waypoint)
  if ok_w then current = read_waypoint(w) end
  return { loaded = true, current = current, count = #out, waypoints = out }
end

-- dbg.rxp_objectives(quest_id) -- RestedXP's own objective progress for a quest
function dbg.rxp_objectives(quest_id)
  quest_id = tonumber(quest_id)
  if not quest_id then return "quest_id required" end
  local r = guide_ns("rested_xp")
  if not r then return { loaded = false } end
  local ok, objectives = pcall(r.get_objectives, quest_id)
  if not ok or type(objectives) ~= "table" then
    return { loaded = true, quest_id = quest_id, objectives = {} }
  end
  local out = {}
  for i, o in ipairs(objectives) do
    out[i] = {
      text = o.text,
      type = o.type,
      num_required = o.num_required,
      num_fulfilled = o.num_fulfilled,
      finished = o.finished,
    }
  end
  return { loaded = true, quest_id = quest_id, objectives = out }
end

-- dbg.zygor() -- the same probe against Zygor, whose step surface mirrors RestedXP
function dbg.zygor()
  local z = guide_ns("zygor")
  if not z then return { loaded = false, note = "Zygor is not loaded" } end
  local has_step = false
  local ok_h, h = pcall(z.has_current_step)
  if ok_h then has_step = h == true end
  local step = nil
  if has_step then
    local ok_s, s = pcall(z.get_current_step)
    if ok_s then step = s end -- Zygor's step shape is looser; return it verbatim
  end
  local waypoint = nil
  local ok_w, w = pcall(z.get_current_waypoint)
  if ok_w then waypoint = read_waypoint(w) end
  return { loaded = true, has_current_step = has_step, step = step, current_waypoint = waypoint }
end

-- dbg.questie(quest_id?) -- Questie's compiled quest DB, in-game.
-- Relevant because it is the same data SentinelQueryServer serves over HTTP on
-- 3030; if Questie is present the runner could resolve quest/NPC facts without
-- the external service at all.
function dbg.questie(quest_id)
  local q = guide_ns("questie")
  if not q then return { loaded = false, note = "Questie is not loaded" } end

  local ready = false
  if q.is_ready then
    local ok_r, r = pcall(q.is_ready)
    ready = ok_r and r == true
  end

  quest_id = tonumber(quest_id)
  if quest_id then
    local function field(key)
      if not q.query_quest_single then return nil end
      local ok, v = pcall(q.query_quest_single, quest_id, key)
      return ok and v or nil
    end
    local doable, complete
    if q.is_quest_doable then
      local ok_d, d = pcall(q.is_quest_doable, quest_id); doable = ok_d and d or nil
    end
    if q.is_quest_complete then
      local ok_c, c = pcall(q.is_quest_complete, quest_id); complete = ok_c and c or nil
    end
    return {
      loaded = true, ready = ready, quest_id = quest_id,
      name = field("name"), level = field("questLevel"),
      starts = field("startedBy"), ends = field("finishedBy"),
      objectives = field("objectives"),
      is_doable = doable, is_complete = complete,
    }
  end

  local total = nil
  if q.get_quest_ids then
    local ok_ids, ids = pcall(q.get_quest_ids)
    if ok_ids and type(ids) == "table" then total = #ids end
  end
  local active = {}
  if q.get_quest_npc_ids then
    local ok_n, npcs = pcall(q.get_quest_npc_ids)
    if ok_n and type(npcs) == "table" then active = npcs end
  end
  return { loaded = true, ready = ready, indexed_quests = total, active_quest_npc_ids = active }
end

-- dbg.guides() -- which guide/quest addons are actually usable right now.
-- Call this FIRST: every namespace under core.addons exists unconditionally, so
-- a nil check tells you nothing.
function dbg.guides()
  local names = { "rested_xp", "zygor", "questie" }
  local out = {}
  for _, n in ipairs(names) do out[n] = guide_ns(n) ~= nil end
  return out
end

------------------------------------------------------------
-- Loot window
--
-- A questing runner stalls on loot more than on anything else, and the loot
-- window is invisible to every other helper.
------------------------------------------------------------
function dbg.loot()
  local count = core.game_ui.get_loot_item_count() or 0
  local items = {}
  for i = 1, count do
    local function try(fn)
      if type(fn) ~= "function" then return nil end
      local ok, v = pcall(fn, i)
      -- Preserve a genuine `false` (e.g. is_gold on a non-gold slot).
      if ok then return v end
      return nil
    end
    items[#items + 1] = {
      index = i,
      name = try(core.game_ui.get_loot_item_name),
      item_id = try(core.game_ui.get_loot_item_id),
      is_gold = try(core.game_ui.get_loot_is_gold),
    }
  end
  dlog("LOOT", "loot window: " .. count .. " items")
  return { open = count > 0, count = count, items = items }
end

function dbg.loot_slot(index)
  index = tonumber(index)
  if not index then return "index required" end
  core.input.loot_item(index)
  dlog("LOOT", "loot_item(" .. index .. ")")
  return "loot_item(" .. index .. ") called"
end

function dbg.loot_all()
  local count = core.game_ui.get_loot_item_count() or 0
  if count == 0 then return "loot window is empty or closed" end
  -- Looting shifts indices, so walk backwards.
  for i = count, 1, -1 do core.input.loot_item(i) end
  dlog("LOOT", "loot_all: " .. count .. " slots")
  return "looted " .. count .. " slots"
end

------------------------------------------------------------
-- Ghost / corpse recovery
--
-- runtime_profile.lua has a dedicated `ghost` state; these expose what that
-- state can actually see.
------------------------------------------------------------
function dbg.corpse()
  local player = get_player()
  local out = {}
  if player then
    -- Assigned rather than `player and ... or nil`, which would report a live
    -- player's `false` as `nil`.
    out.is_dead = player:is_dead()
    if player.is_ghost then out.is_ghost = player:is_ghost() end
  end

  local ok, pos = pcall(core.game_ui.get_corpse_position)
  if ok and type(pos) == "table" and pos.x then
    -- With no corpse the client reports the origin. Reporting that verbatim
    -- yields a nonsense "corpse 8800 yards away" instead of "no corpse".
    local is_origin = pos.x == 0 and pos.y == 0 and pos.z == 0
    if is_origin then
      out.has_corpse = false
    else
      out.has_corpse = true
      out.corpse_position = { x = pos.x, y = pos.y, z = pos.z }
      if player then
        local ppos = player:get_position()
        local dx, dy, dz = pos.x - ppos.x, pos.y - ppos.y, pos.z - ppos.z
        out.distance = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) * 10) / 10
      end
    end
  end

  local delay_ok, delay = pcall(core.game_ui.get_resurrect_corpse_delay)
  if delay_ok then out.resurrect_delay = delay end

  return out
end

function dbg.release_spirit()
  core.input.release_spirit()
  dlog("GHOST", "release_spirit")
  return "release_spirit called"
end

function dbg.resurrect()
  core.input.resurrect_corpse()
  dlog("GHOST", "resurrect_corpse")
  return "resurrect_corpse called"
end

------------------------------------------------------------
-- Vendor helpers
------------------------------------------------------------

-- dbg.vendor() -- what the open vendor is actually selling.
-- vendor_buy(index) is blind without this.
function dbg.vendor()
  local count = core.game_ui.get_vendor_item_count() or 0
  local items = {}
  for i = 1, count do
    local ok, info = pcall(core.game_ui.get_vendor_item_info, i)
    if ok and type(info) == "table" then
      info.index = i
      items[#items + 1] = info
    elseif ok then
      items[#items + 1] = { index = i, value = tostring(info) }
    end
  end
  dlog("VENDOR", "vendor window: " .. count .. " items")
  return { open = count > 0, count = count, items = items }
end

function dbg.vendor_buy(index, quantity)
  index = tonumber(index)
  if not index then return "index required" end
  quantity = tonumber(quantity) or 1
  core.input.buy_item(index, quantity)
  dlog("VENDOR", string.format("buy_item(%d, %d)", index, quantity))
  return string.format("buy_item(%d, %d) called", index, quantity)
end

function dbg.vendor_repair(use_guild_bank)
  core.input.repair_all_items(use_guild_bank and true or false)
  dlog("VENDOR", "repair_all_items")
  return "repair_all_items called"
end

function dbg.gold()
  local player = get_player()
  if not player then return "no valid player" end
  local ok, g = pcall(core.inventory.get_gold)
  return ok and g or "unavailable"
end

------------------------------------------------------------
-- Existing dbg helpers (kept from v1, updated with dlog)
------------------------------------------------------------
function dbg.nav_move_to(pos)
  local nav = get_nav()
  if not nav then return "NavLib not available" end
  dlog("NAV", string.format("nav_move_to -> %.1f, %.1f, %.1f", pos.x, pos.y, pos.z))
  nav:move_to(pos, function(ok, reason)
    local msg = ok and "SUCCESS" or ("FAILED: " .. tostring(reason))
    dlog("NAV", "nav_move_to callback: " .. msg)
    _dbg_last_result = msg
    write_file("lx_debug/async_result.json", JSON.encode({ call = "nav_move_to", ok = ok, reason = tostring(reason) }))
  end)
  return "move_to dispatched"
end

function dbg.nav_stop()
  local nav = get_nav()
  if not nav then return "NavLib not available" end
  nav:stop()
  dlog("NAV", "nav stopped")
  return "stopped"
end

function dbg.nav_validate(pos)
  local nav = get_nav()
  if not nav then return "NavLib not available" end
  dlog("NAV", string.format("nav_validate -> %.1f, %.1f, %.1f", pos.x, pos.y, pos.z))
  nav:validate_destination(pos, function(reachable, reason, distance)
    local msg = string.format("reachable=%s reason=%s dist=%s", tostring(reachable), tostring(reason), tostring(distance))
    dlog("NAV", "nav_validate: " .. msg)
    _dbg_last_result = msg
    write_file("lx_debug/async_result.json", JSON.encode({ call = "nav_validate", reachable = reachable, reason = tostring(reason), distance = distance }))
  end)
  return "validate dispatched"
end

function dbg.nav_get_heights(pos)
  local nav = get_nav()
  if not nav then return "NavLib not available" end
  dlog("NAV", string.format("nav_get_heights -> %.1f, %.1f, %.1f", pos.x, pos.y, pos.z))
  nav:get_all_heights(pos, function(ok, data, err)
    if not ok or not data then
      local msg = "FAILED: " .. tostring(err or "no data")
      dlog("NAV", "nav_get_heights: " .. msg)
      _dbg_last_result = msg
      write_file("lx_debug/async_result.json", JSON.encode({ call = "nav_get_heights", ok = false, error = msg }))
      return
    end
    local msg = string.format("count=%d", data.count or 0)
    if data.heights then
      for i, h in ipairs(data.heights) do
        msg = msg .. string.format(" [%d]=%.1f", i, h.height)
      end
    end
    dlog("NAV", "nav_get_heights: " .. msg)
    _dbg_last_result = msg
    write_file("lx_debug/async_result.json", JSON.encode({ call = "nav_get_heights", ok = true, data = data }))
  end)
  return "get_heights dispatched"
end

function dbg.nav_random_point(radius)
  local nav = get_nav()
  if not nav then return "NavLib not available" end
  local nav_svc = nav.nav_client
  if not nav_svc then return "nav_client not available on facade" end
  local player = get_player()
  if not player then return "no valid player" end
  local center = player:get_position()
  radius = radius or 50
  dlog("NAV", string.format("nav_random_point center=%.1f,%.1f,%.1f r=%d", center.x, center.y, center.z, radius))
  nav_svc:random_point(function(ok, data)
    if ok and data and data.point then
      local p = data.point
      local msg = string.format("random_point OK: %.1f, %.1f, %.1f", p.x, p.y, p.z)
      dlog("NAV", msg)
      _dbg_last_result = msg
      write_file("lx_debug/async_result.json", JSON.encode({ call = "nav_random_point", ok = true, point = { x = p.x, y = p.y, z = p.z } }))
    else
      dlog("NAV", "random_point FAILED")
      _dbg_last_result = "random_point failed"
      write_file("lx_debug/async_result.json", JSON.encode({ call = "nav_random_point", ok = false }))
    end
  end, { center = center, radius = radius })
  return "random_point dispatched"
end

function dbg.nav_wander(radius)
  local nav = get_nav()
  if not nav then return "NavLib not available" end
  local nav_svc = nav.nav_client
  if not nav_svc then return "nav_client not available on facade" end
  local player = get_player()
  if not player then return "no valid player" end
  local center = player:get_position()
  radius = radius or 50
  dlog("NAV", string.format("nav_wander r=%d", radius))
  nav_svc:random_point(function(ok, data)
    if ok and data and data.point then
      local p = data.point
      dlog("NAV", string.format("wander target: %.1f, %.1f, %.1f -- moving", p.x, p.y, p.z))
      nav:move_to(p, function(move_ok, reason)
        local msg = move_ok and "ARRIVED" or ("MOVE FAILED: " .. tostring(reason))
        dlog("NAV", "nav_wander: " .. msg)
        _dbg_last_result = msg
        write_file("lx_debug/async_result.json", JSON.encode({ call = "nav_wander", ok = move_ok, reason = tostring(reason), dest = { x = p.x, y = p.y, z = p.z } }))
      end)
    else
      dlog("NAV", "nav_wander: random_point failed")
      _dbg_last_result = "random_point failed"
    end
  end, { center = center, radius = radius })
  return "wander dispatched"
end

function dbg.scan_units(range)
  range = range or 80
  local player = get_player()
  if not player then return "no player" end
  local ppos = player:get_position()
  local all = core.object_manager.get_all_objects()
  local results = {}
  for _, obj in pairs(all) do
    if obj and obj.is_valid and obj:is_valid()
      and obj.get_health and obj.get_position and obj.get_name then
      local pos = obj:get_position()
      local dist = pos:dist_to(ppos)
      if dist <= range and obj:get_name() ~= player:get_name() then
        local hp = obj:get_health()
        local max_hp = (obj.get_max_health and obj:get_max_health()) or 0
        local lvl = (obj.get_level and obj:get_level()) or 0
        local dead = (obj.is_dead and obj:is_dead()) or false
        local npc = (obj.get_npc_id and obj:get_npc_id()) or 0
        local name = obj:get_name() or "?"
        if not dead and max_hp > 0 and lvl > 0 then
          results[#results + 1] = string.format("%s (L%d) %.0fyd npc=%d hp=%d/%d", name, lvl, dist, npc, hp, max_hp)
        end
      end
    end
  end
  local msg = #results .. " units found in " .. range .. "yd"
  dlog("SCAN", msg)
  _dbg_last_result = msg
  write_file("lx_debug/async_result.json", JSON.encode({ call = "scan_units", count = #results, units = results }))
  return msg
end

function dbg.target_npc(npc_id)
  npc_id = tonumber(npc_id)
  if not npc_id then return "npc_id required" end
  local player = get_player()
  if not player then return "no player" end
  local ppos = player:get_position()
  local all = core.object_manager.get_all_objects()
  local best, best_dist = nil, math.huge
  for _, obj in pairs(all) do
    if obj and obj.is_valid and obj:is_valid()
      and obj.get_npc_id and obj:get_npc_id() == npc_id
      and obj.is_dead and not obj:is_dead() and obj.get_position then
      local d = obj:get_position():dist_to(ppos)
      if d < best_dist then best = obj; best_dist = d end
    end
  end
  if not best then return "no alive NPC with id " .. npc_id .. " found" end
  core.input.set_target(best)
  local name = best:get_name() or "?"
  local msg = string.format("Targeted %s (npc=%d) at %.1fyd", name, npc_id, best_dist)
  dlog("NPC", msg)
  return msg
end

function dbg.target_dead_npc(npc_id)
  npc_id = tonumber(npc_id)
  if not npc_id then return "npc_id required" end
  local player = get_player()
  if not player then return "no player" end
  local ppos = player:get_position()
  local all = core.object_manager.get_all_objects()
  local best, best_dist = nil, math.huge
  for _, obj in pairs(all) do
    if obj and obj.is_valid and obj:is_valid()
      and obj.get_npc_id and obj:get_npc_id() == npc_id
      and obj.is_dead and obj:is_dead() and obj.get_position then
      local d = obj:get_position():dist_to(ppos)
      if d < best_dist then best = obj; best_dist = d end
    end
  end
  if not best then return "no dead NPC with id " .. npc_id .. " found" end
  core.input.set_target(best)
  local name = best:get_name() or "?"
  local msg = string.format("Targeted dead %s (npc=%d) at %.1fyd", name, npc_id, best_dist)
  dlog("NPC", msg)
  return msg
end

function dbg.nav_to_target()
  local player = get_player()
  if not player then return "no player" end
  local target = player:get_target()
  if not target or not target:is_valid() then return "no target" end
  local nav = get_nav()
  if not nav then return "NavLib not available" end
  local dest = target:get_position()
  local name = target:get_name() or "?"
  local dist = dest:dist_to(player:get_position())
  dlog("NAV", string.format("nav_to_target: %s at %.1fyd", name, dist))
  nav:move_to(dest, function(ok, reason)
    local msg = ok and "ARRIVED at " .. name or ("MOVE FAILED: " .. tostring(reason))
    dlog("NAV", "nav_to_target: " .. msg)
    _dbg_last_result = msg
    write_file("lx_debug/async_result.json", JSON.encode({ call = "nav_to_target", ok = ok, target = name, reason = tostring(reason) }))
  end)
  return "moving to " .. name .. " (" .. string.format("%.1f", dist) .. "yd)"
end

function dbg.attack_target()
  local player = get_player()
  if not player then return "no player" end
  local target = player:get_target()
  if not target or not target:is_valid() then return "no target" end
  if target:is_dead() then return "target is dead" end
  local auto_attack = require("common/utility/auto_attack_helper")
  auto_attack:start_attack(target, auto_attack.ATTACK_TYPE.MELEE)
  local name = target:get_name() or "?"
  dlog("COMBAT", "Attacking: " .. name)
  return "attacking " .. name
end

function dbg.loot_target()
  local player = get_player()
  if not player then return "no player" end
  local target = player:get_target()
  if not target or not target:is_valid() then return "no target" end
  if not target:is_dead() then return "target is not dead" end
  core.input.loot_object(target)
  local name = target:get_name() or "?"
  dlog("LOOT", "Looting: " .. name)
  return "looting " .. name
end

function dbg.interact_target()
  local player = get_player()
  if not player then return "no player" end
  local target = player:get_target()
  if not target or not target:is_valid() then return "no target" end
  core.input.interact_with_object(target)
  local name = target:get_name() or "?"
  dlog("NPC", "Interacting: " .. name)
  return "interacting with " .. name
end

function dbg.in_combat()
  local player = get_player()
  if not player then return "no player" end
  return player:is_in_combat()
end

function dbg.target_hp()
  local player = get_player()
  if not player then return "no player" end
  local target = player:get_target()
  if not target or not target:is_valid() then return "no target" end
  local hp = target:get_health()
  local max_hp = target:get_max_health()
  local dead = target:is_dead()
  local pct = max_hp > 0 and math.floor(hp / max_hp * 100) or 0
  return string.format("%d/%d (%d%%) dead=%s", hp, max_hp, pct, tostring(dead))
end

function dbg.target_dead()
  local player = get_player()
  if not player then return "no player" end
  local target = player:get_target()
  if not target or not target:is_valid() then return "no target" end
  return target:is_dead()
end

function dbg.find_vendor(range)
  range = range or 200
  local player = get_player()
  if not player then return "no player" end
  local ppos = player:get_position()
  local all = core.object_manager.get_all_objects()
  local npcs = {}
  for _, obj in pairs(all) do
    if obj and obj.is_valid and obj:is_valid()
      and obj.get_npc_id and obj.get_name and obj.get_position
      and obj.is_dead and not obj:is_dead() then
      local d = obj:get_position():dist_to(ppos)
      if d <= range then
        local npc_id = obj:get_npc_id() or 0
        local name = obj:get_name() or "?"
        local lvl = (obj.get_level and obj:get_level()) or 0
        if npc_id > 0 and lvl > 0 then
          npcs[#npcs + 1] = { name = name, npc_id = npc_id, dist = d }
        end
      end
    end
  end
  table.sort(npcs, function(a, b) return a.dist < b.dist end)
  local results = {}
  local limit = math.min(#npcs, 30)
  for i = 1, limit do
    results[i] = string.format("%s (npc=%d) %.0fyd", npcs[i].name, npcs[i].npc_id, npcs[i].dist)
  end
  local msg = #npcs .. " NPCs in " .. range .. "yd"
  dlog("SCAN", msg)
  _dbg_last_result = msg
  write_file("lx_debug/async_result.json", JSON.encode({ call = "find_vendor", count = #npcs, npcs = results }))
  return msg
end

function dbg.player_pos()
  local player = get_player()
  if not player then return "no player" end
  local p = player:get_position()
  return string.format("%.1f, %.1f, %.1f", p.x, p.y, p.z)
end

function dbg.nav_state()
  local nav = get_nav()
  if not nav then return "NavLib not available" end
  local state = nav:get_state()
  local moving = nav:is_moving()
  return string.format("state=%s moving=%s", state, tostring(moving))
end

function dbg.last_result()
  return _dbg_last_result or "no result yet"
end

function dbg.test_lxdata2()
  local ok, lib = pcall(require, "root/ext_lib_lx_data_2/main")
  if not ok then
    local msg = "LxData2 require FAILED: " .. tostring(lib)
    write_file("lx_debug/async_result.json", JSON.encode({ call = "test_lxdata2", ok = false, error = msg }))
    return msg
  end
  lib.items.fetch(19019, function(data, err)
    write_file("lx_debug/async_result.json", JSON.encode({ call = "test_lxdata2", ok = data ~= nil, name = data and data.name or nil, err = err and tostring(err) or nil }, true))
  end)
  return "lxdata2 loaded, fetch dispatched (version=" .. tostring(lib.VERSION) .. " game=" .. tostring(lib.game_version) .. ")"
end

function dbg.fetch_item(id)
  local lxdata = require("root/ext_lib_lx_data_2/main")
  lxdata.items:fetch(id, function(data)
    write_file("lx_debug/item_data.json", JSON.encode(data or {error = "nil"}, true))
  end)
  return "fetching item " .. tostring(id)
end

function dbg.http_get(url, use_headers)
  if not url or url == "" then return "url required" end
  local hdrs = {}
  if use_headers then
    hdrs = {
      ["User-Agent"]      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      ["Accept"]          = "application/json, text/plain, */*",
      ["Accept-Language"]  = "en-US,en;q=0.9",
      ["Accept-Encoding"] = "identity",
    }
  end
  dlog("HTTP", "GET " .. url)
  core.http_get(url, hdrs, function(code, content_type, body, headers)
    local result = {
      code = code,
      content_type = content_type,
      body_len = body and #body or 0,
      body_preview = body and body:sub(1, 2000) or "nil",
    }
    dlog("HTTP", "response: code=" .. tostring(code) .. " len=" .. tostring(result.body_len))
    _dbg_last_result = "HTTP " .. tostring(code) .. " len=" .. tostring(result.body_len)
    write_file("lx_debug/async_result.json", JSON.encode(result, true))
  end)
  return "http_get dispatched"
end

------------------------------------------------------------
-- Game event recorder
--
-- The bridge is otherwise pull-only: it can report current state but not what
-- happened. UI_ERROR_MESSAGE in particular carries the game's own reason an
-- action failed ("You are too far away."), which is the fastest way to explain
-- a stalled runner.
--
-- One callback receives every event, so dispatch happens here. Registered once
-- at load -- registering per-tick raises a Lua error.
------------------------------------------------------------
local _events = {}
local _events_max = 400
local _event_seq = 0

-- Events that say something about why an action did or did not happen.
local INTERESTING_EVENTS = {
  UI_ERROR_MESSAGE = true,
  PLAYER_REGEN_DISABLED = true,
  PLAYER_REGEN_ENABLED = true,
  PLAYER_STARTED_MOVING = true,
  PLAYER_STOPPED_MOVING = true,
  PLAYER_EQUIPMENT_CHANGED = true,
  SPELLS_CHANGED = true,
  GROUP_ROSTER_UPDATE = true,
  ENCOUNTER_START = true,
  ENCOUNTER_END = true,
}

local function record_event(event_name, args)
  _event_seq = _event_seq + 1
  local flat = {}
  if type(args) == "table" then
    for i = 1, 8 do
      local v = args[i]
      if v ~= nil then flat[i] = (type(v) == "table") and "<table>" or v end
    end
  end
  _events[#_events + 1] = {
    seq = _event_seq,
    t = math.floor(core.time() * 100) / 100,
    event = event_name,
    args = flat,
  }
  if #_events > _events_max then table.remove(_events, 1) end
end

-- COMBAT_LOG_EVENT_UNFILTERED fires hundreds of times per second; recording it
-- would evict everything else from the ring buffer within a second.
core.register_on_game_event_callback(function(event_name, args)
  if event_name == "COMBAT_LOG_EVENT_UNFILTERED" then return end
  record_event(event_name, args)
  if event_name == "UI_ERROR_MESSAGE" then
    dlog("UIERR", tostring(args and args[2] or "?"))
  end
end)

-- dbg.events(n?, filter?) -- recent game events, newest last
function dbg.events(n, filter)
  n = tonumber(n) or 50
  local out = {}
  for i = #_events, 1, -1 do
    local e = _events[i]
    if not filter or e.event:find(filter, 1, true) then
      out[#out + 1] = e
      if #out >= n then break end
    end
  end
  -- Reverse so the newest event reads last, like a log tail.
  local ordered = {}
  for i = #out, 1, -1 do ordered[#ordered + 1] = out[i] end
  return { count = #ordered, total_buffered = #_events, events = ordered }
end

-- dbg.errors(n?) -- UI_ERROR_MESSAGE only: the game's own failure reasons
function dbg.errors(n)
  n = tonumber(n) or 20
  local out = {}
  for i = #_events, 1, -1 do
    local e = _events[i]
    if e.event == "UI_ERROR_MESSAGE" then
      out[#out + 1] = { t = e.t, error_type = e.args[1], message = e.args[2] }
      if #out >= n then break end
    end
  end
  local ordered = {}
  for i = #out, 1, -1 do ordered[#ordered + 1] = out[i] end
  return { count = #ordered, errors = ordered }
end

------------------------------------------------------------
-- Navigation diagnostics
------------------------------------------------------------

-- dbg.nav_report() -- everything the nav client knows, in one call
function dbg.nav_report()
  local nav = get_nav()
  if not nav then return "nav client not available (_G.SentinelNavClient.client is nil)" end

  local function try(method, ...)
    if not nav[method] then return nil end
    local ok, v = pcall(nav[method], nav, ...)
    -- See note in the other try() helpers: preserve a genuine `false`.
    if ok then return v end
    return nil
  end

  local report = {
    state = try("get_state"),
    full_state = try("get_full_state"),   -- e.g. "navigating.recovering.strafing"
    is_moving = try("is_moving"),
    server_available = try("is_server_available"),
    path_index = try("get_path_index"),
  }

  local dest = try("get_destination")
  if dest then
    report.destination = { x = dest.x, y = dest.y, z = dest.z }
    local player = get_player()
    if player then
      local ok, d = pcall(dest.dist_to, dest, player:get_position())
      if ok then report.distance_to_destination = math.floor(d * 10) / 10 end
    end
  end

  local progress = try("get_progress")
  if type(progress) == "table" then
    report.progress = {
      percent = progress.percent and math.floor(progress.percent * 1000) / 10 or nil,
      current_index = progress.current_index,
      total_waypoints = progress.total_waypoints,
      waypoints_remaining = progress.waypoints_remaining,
    }
  end

  local path = try("get_current_path")
  if type(path) == "table" then
    report.waypoint_count = #path
    -- Only the next few waypoints matter for diagnosing a stall.
    local head = {}
    local idx = tonumber(report.path_index) or 1
    for i = idx, math.min(idx + 4, #path) do
      local w = path[i]
      if w then head[#head + 1] = { i = i, x = w.x, y = w.y, z = w.z } end
    end
    report.next_waypoints = head
  end

  dlog("NAV", string.format("nav_report: state=%s moving=%s",
    tostring(report.full_state or report.state), tostring(report.is_moving)))
  return report
end

------------------------------------------------------------
-- Spell diagnostics
------------------------------------------------------------

-- dbg.spell_report(spell_id) -- answers "why did this cast not happen?"
function dbg.spell_report(spell_id)
  spell_id = tonumber(spell_id)
  if not spell_id then return "spell_id required" end
  local player = get_player()
  if not player then return "no valid player" end
  local target = player:get_target()

  local sb = core.spell_book
  local function try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    -- `ok and v or nil` would report a legitimate `false` as `nil`, which in a
    -- debugger reads as "unknown" instead of "no".
    if ok then return v end
    return nil
  end

  local report = {
    spell_id = spell_id,
    name = try(sb.get_spell_name, spell_id),
    known = try(sb.is_spell_known, spell_id),
    learned = try(sb.is_spell_learned, spell_id),
    usable = try(sb.is_usable_spell, spell_id),
    cooldown = try(sb.get_spell_cooldown, spell_id),
    global_cooldown = try(sb.get_global_cooldown),
    cast_count = try(sb.get_spell_cast_count, spell_id),
    costs = try(sb.get_spell_costs, spell_id),
  }

  -- spell_helper answers the range/LoS/facing questions the raw book cannot.
  local helper_ok, helper = pcall(require, "common/utility/spell_helper")
  if helper_ok and type(helper) == "table" and target and target:is_valid() then
    report.target = target:get_name()
    report.in_range = try(helper.is_spell_in_range, helper, spell_id, target,
      player:get_position(), target:get_position())
    report.in_line_of_sight = try(helper.is_spell_in_line_of_sight, helper, spell_id, player, target)
    report.castable = try(helper.is_spell_castable, helper, spell_id, player, target, false, false)
  end

  dlog("SPELL", string.format("spell_report %d (%s): known=%s usable=%s castable=%s",
    spell_id, tostring(report.name), tostring(report.known),
    tostring(report.usable), tostring(report.castable)))
  return report
end

------------------------------------------------------------
-- dbg.why_stuck() -- one call, the whole "why is nothing happening" picture
------------------------------------------------------------
function dbg.why_stuck()
  local player = get_player()
  if not player then return { verdict = "no valid player -- not in world?" } end

  local out = {
    player = {
      name = player:get_name(),
      dead = player:is_dead(),
      ghost = player.is_ghost and player:is_ghost() or false,
      in_combat = player:is_in_combat(),
      moving = player.is_moving and player:is_moving() or false,
      casting = player.is_casting_spell and player:is_casting_spell() or false,
      mounted = player:is_mounted(),
      position = dbg.player_pos(),
    },
    nav = dbg.nav_report(),
    recent_errors = dbg.errors(5),
    gossip_open = core.quests.is_gossip_frame_shown() or false,
    loot_open = (core.game_ui.get_loot_item_count() or 0) > 0,
  }

  -- is_player_in_control() is false while stunned/feared/rooted -- the runner
  -- can look idle for reasons no state machine of ours knows about.
  local ctrl_ok, in_control = pcall(core.spell_book.is_player_in_control)
  if ctrl_ok then out.player.in_control = in_control end

  local target = player:get_target()
  out.target = (target and target:is_valid())
    and { name = target:get_name(), npc_id = target:get_npc_id(), dead = target:is_dead() }
    or "none"

  -- Cheapest plausible explanation first.
  local verdict
  if out.player.dead or out.player.ghost then verdict = "player is dead/ghost -- runner should be in ghost recovery (see dbg.corpse())"
  elseif out.player.in_control == false then verdict = "player is NOT in control -- stunned, feared or rooted"
  elseif out.loot_open then verdict = "a loot window is open and blocking further input (see dbg.loot())"
  elseif out.gossip_open then verdict = "a gossip frame is open and blocking further input"
  elseif out.player.casting then verdict = "player is mid-cast"
  elseif type(out.nav) == "table" and out.nav.state == "failed" then
    verdict = "navigation FAILED -- see nav.full_state for the reason"
  elseif type(out.nav) == "table" and out.nav.is_moving and not out.player.moving then
    verdict = "nav thinks it is moving but the character is not -- likely stuck on geometry"
  elseif out.recent_errors.count > 0 then
    verdict = "game rejected a recent action: " .. tostring(out.recent_errors.errors[out.recent_errors.count].message)
  elseif out.player.in_combat then verdict = "in combat -- questing is likely yielding to the combat module"
  else verdict = "no obvious blocker; check dbg.quest_status(<id>) and dbg.events()"
  end
  out.verdict = verdict

  dlog("STUCK", "why_stuck: " .. verdict)
  return out
end

------------------------------------------------------------
-- Known roots (refreshed per-call for dynamic objects)
------------------------------------------------------------
local function get_roots()
  local player = core.object_manager.get_local_player()
  local sentinel_client = _G.SentinelNavClient and _G.SentinelNavClient.client or nil
  local navlib_facade = _G.NavLib and _G.NavLib.facade or nil
  return {
    core     = core,
    izi      = require("common/izi_sdk"),
    player   = player,
    target   = player and player:is_valid() and player:get_target() or nil,
    pet      = player and player:is_valid() and player.get_pet and player:get_pet() or nil,
    nav      = sentinel_client or navlib_facade,
    dbg      = dbg,
  }
end

------------------------------------------------------------
-- Table literal parser
------------------------------------------------------------
local vec3 = require("common/geometry/vector_3")

local function parse_table_literal(s)
  if type(s) ~= "string" then return s end
  local trimmed = s:match("^%s*{(.+)}%s*$")
  if not trimmed then return s end

  local result = {}
  local idx = 1

  for part in (trimmed .. ","):gmatch("([^,]+),") do
    part = part:match("^%s*(.-)%s*$")
    local k, v = part:match("^([%w_]+)%s*=%s*(.+)$")
    if k then
      if v == "true" then v = true
      elseif v == "false" then v = false
      elseif v == "nil" then v = nil
      elseif tonumber(v) then v = tonumber(v)
      else v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
      end
      result[k] = v
    else
      local val = part
      if val == "true" then val = true
      elseif val == "false" then val = false
      elseif val == "nil" then val = nil
      elseif tonumber(val) then val = tonumber(val)
      else val = val:match('^"(.*)"$') or val:match("^'(.*)'$") or val
      end
      result[idx] = val
      idx = idx + 1
    end
  end

  if result.x and result.y and result.z
    and type(result.x) == "number"
    and type(result.y) == "number"
    and type(result.z) == "number" then
    return vec3.new(result.x, result.y, result.z)
  end

  return result
end

------------------------------------------------------------
-- Path resolver + caller
------------------------------------------------------------
local function resolve_and_call(cmd)
  local roots = get_roots()

  local root_name = cmd.root or "core"
  local obj = roots[root_name]
  if not obj then
    return false, "unknown root: " .. tostring(root_name)
  end

  if (root_name == "player" or root_name == "target" or root_name == "pet") then
    if not obj or (type(obj) == "userdata" and obj.is_valid and not obj:is_valid()) then
      return false, root_name .. " is nil or invalid"
    end
  end

  local path_str = cmd.path or ""
  local after_root = path_str:match("^" .. root_name .. "[.:](.+)$") or path_str

  local parts = {}
  for part in after_root:gmatch("[^.:]+") do
    parts[#parts + 1] = part
  end

  if #parts == 0 then
    return false, "empty path after root"
  end

  local parent = obj
  for i = 1, #parts - 1 do
    local next_obj = parent[parts[i]]
    if next_obj == nil then
      return false, "nil at path segment: " .. parts[i]
    end
    parent = next_obj
  end

  local fn_name = parts[#parts]
  local fn = parent[fn_name]
  if type(fn) ~= "function" then
    if fn ~= nil then
      return true, fn
    end
    return false, fn_name .. " is not a function (type: " .. type(fn) .. ")"
  end

  local args = cmd.args or {}
  local call_args = {}
  for i = 1, #args do
    local a = args[i]
    if type(a) == "table" and a.__eval then
      -- Sub-expression: evaluate nested function call
      local sub_ok, sub_result = resolve_and_call(a)
      if not sub_ok then
        return false, "arg " .. i .. " eval failed: " .. tostring(sub_result)
      end
      call_args[i] = sub_result
    elseif type(a) == "string" and roots[a] then
      call_args[i] = roots[a]
    else
      call_args[i] = parse_table_literal(a)
    end
  end

  local ok, result
  local n = #call_args
  if cmd.method then
    if n == 0 then ok, result = pcall(fn, parent)
    elseif n == 1 then ok, result = pcall(fn, parent, call_args[1])
    elseif n == 2 then ok, result = pcall(fn, parent, call_args[1], call_args[2])
    elseif n == 3 then ok, result = pcall(fn, parent, call_args[1], call_args[2], call_args[3])
    elseif n == 4 then ok, result = pcall(fn, parent, call_args[1], call_args[2], call_args[3], call_args[4])
    else ok, result = pcall(fn, parent, call_args[1], call_args[2], call_args[3], call_args[4], call_args[5])
    end
  else
    if n == 0 then ok, result = pcall(fn)
    elseif n == 1 then ok, result = pcall(fn, call_args[1])
    elseif n == 2 then ok, result = pcall(fn, call_args[1], call_args[2])
    elseif n == 3 then ok, result = pcall(fn, call_args[1], call_args[2], call_args[3])
    elseif n == 4 then ok, result = pcall(fn, call_args[1], call_args[2], call_args[3], call_args[4])
    else ok, result = pcall(fn, call_args[1], call_args[2], call_args[3], call_args[4], call_args[5])
    end
  end

  if not ok then return false, result end

  -- Chain: follow-up property access / method calls on the result
  if cmd.chain and result ~= nil then
    for _, step in ipairs(cmd.chain) do
      if result == nil then
        return false, "chain broken: nil result before step"
      end

      local segs = step.segments or {}
      local step_method = step.method

      local cur = result
      for si = 1, #segs - 1 do
        local next_val = cur[segs[si]]
        if next_val == nil then
          return false, "chain: nil at segment '" .. segs[si] .. "'"
        end
        cur = next_val
      end

      local last_seg = segs[#segs]
      if not last_seg then
        return false, "chain: empty segment"
      end

      local step_fn = cur[last_seg]

      if type(step_fn) ~= "function" then
        if step_fn == nil then
          return false, "chain: nil at '" .. last_seg .. "'"
        end
        result = step_fn
      else
        local sargs = step.args or {}
        local step_call_args = {}
        for i = 1, #sargs do
          step_call_args[i] = parse_table_literal(sargs[i])
        end

        local sn = #step_call_args
        local sok, sresult
        if step_method then
          if sn == 0 then sok, sresult = pcall(step_fn, cur)
          elseif sn == 1 then sok, sresult = pcall(step_fn, cur, step_call_args[1])
          elseif sn == 2 then sok, sresult = pcall(step_fn, cur, step_call_args[1], step_call_args[2])
          else sok, sresult = pcall(step_fn, cur, step_call_args[1], step_call_args[2], step_call_args[3])
          end
        else
          if sn == 0 then sok, sresult = pcall(step_fn)
          elseif sn == 1 then sok, sresult = pcall(step_fn, step_call_args[1])
          elseif sn == 2 then sok, sresult = pcall(step_fn, step_call_args[1], step_call_args[2])
          else sok, sresult = pcall(step_fn, step_call_args[1], step_call_args[2], step_call_args[3])
          end
        end

        if not sok then return false, sresult end
        result = sresult
      end
    end
  end

  return true, result
end

------------------------------------------------------------
-- Result serializer (improved: size cap, better error recovery)
------------------------------------------------------------
local function serialize_game_object(obj)
  if not obj or not obj.is_valid or not obj:is_valid() then
    return { invalid = true }
  end
  local info = { name = obj:get_name() }
  if obj.get_npc_id then info.npc_id = obj:get_npc_id() end
  if obj.get_health then info.health = obj:get_health() end
  if obj.get_max_health then info.max_health = obj:get_max_health() end
  if obj.get_level then info.level = obj:get_level() end
  if obj.get_position then
    local p = obj:get_position()
    info.position = { x = p.x, y = p.y, z = p.z }
  end
  if obj.is_dead then
    local ok, v = pcall(obj.is_dead, obj)
    if ok then info.dead = v end
  end
  if obj.is_enemy then
    local ok, v = pcall(obj.is_enemy, obj)
    if ok then info.enemy = v end
  end
  if obj.get_item_id then
    local ok, id = pcall(obj.get_item_id, obj)
    if ok and id then info.item_id = id end
  end
  return info
end

local function safe_value(v, depth)
  depth = depth or 0
  if depth > 6 then return tostring(v) end

  local t = type(v)
  if t == "nil" or t == "number" or t == "boolean" or t == "string" then
    return v
  end
  if t == "userdata" then
    -- Try vec2/vec3 first (some SDK types are userdata with x,y,z accessors)
    local vx_ok, vx = pcall(function() return v.x end)
    local vy_ok, vy = pcall(function() return v.y end)
    if vx_ok and vy_ok and type(vx) == "number" and type(vy) == "number" then
      local vz_ok, vz = pcall(function() return v.z end)
      if vz_ok and type(vz) == "number" then
        return { x = vx, y = vy, z = vz }
      end
      return { x = vx, y = vy }
    end
    if v.is_valid and v.get_name then
      return serialize_game_object(v)
    end
    return tostring(v)
  end
  if t == "function" then
    return "<function>"
  end
  if t == "table" then
    -- vec3 check
    local x_ok, vx = pcall(function() return v.x end)
    local y_ok, vy = pcall(function() return v.y end)
    if x_ok and y_ok and type(vx) == "number" and type(vy) == "number" then
      local z_ok, vz = pcall(function() return v.z end)
      if z_ok and type(vz) == "number" then
        return { x = vx, y = vy, z = vz }
      end
      return { x = vx, y = vy }
    end
    local count_ok, count = pcall(function()
      local c = 0
      for _ in pairs(v) do
        c = c + 1
        if c > 200 then return c end
      end
      return c
    end)
    if not count_ok then return "<table:pairs_error>" end
    if count > 200 then
      return "<table:" .. count .. "+entries>"
    end
    local out = {}
    local iter_ok = pcall(function()
      for k, val in pairs(v) do
        out[k] = safe_value(val, depth + 1)
      end
    end)
    if not iter_ok then return "<table:iter_error>" end
    return out
  end
  return tostring(v)
end

local function serialize_result(ok, value)
  local function try_encode(tbl)
    local enc_ok, encoded = pcall(JSON.encode, tbl)
    if not enc_ok then
      return JSON.encode({ ok = true, value = "encoding failed: " .. tostring(encoded), type = "error" })
    end
    -- Cap output size
    if #encoded > MAX_RESULT_SIZE then
      return JSON.encode({ ok = true, value = "result too large (" .. #encoded .. " bytes, max " .. MAX_RESULT_SIZE .. ")", type = "truncated", original_size = #encoded })
    end
    return encoded
  end

  if not ok then
    return try_encode({ ok = false, error = tostring(value) })
  end

  local t = type(value)

  if value == nil then
    return try_encode({ ok = true, value = "nil", type = "nil" })
  end

  if t == "number" or t == "boolean" or t == "string" then
    return try_encode({ ok = true, value = value, type = t })
  end

  if t == "table" then
    -- vec3/vec2 check (pcall-safe for metatables)
    local vx_ok, vx = pcall(function() return value.x end)
    local vy_ok, vy = pcall(function() return value.y end)
    if vx_ok and vy_ok and type(vx) == "number" and type(vy) == "number" then
      local vz_ok, vz = pcall(function() return value.z end)
      if vz_ok and type(vz) == "number" then
        return try_encode({ ok = true, value = { x = vx, y = vy, z = vz }, type = "vec3" })
      end
      return try_encode({ ok = true, value = { x = vx, y = vy }, type = "vec2" })
    end
    -- game_object array
    local MAX_ARRAY = 25
    local len_ok, len = pcall(function() return #value end)
    if len_ok and len > 0 and type(value[1]) == "userdata" then
      local total = len
      local arr = {}
      local limit = math.min(total, MAX_ARRAY)
      for i = 1, limit do
        arr[i] = serialize_game_object(value[i])
      end
      return try_encode({ ok = true, value = arr, type = "game_object[]", count = total, shown = limit })
    end
    local count_ok, count = pcall(function()
      local c = 0
      for _ in pairs(value) do
        c = c + 1
        if c > 200 then return c end
      end
      return c
    end)
    if not count_ok then
      return try_encode({ ok = true, value = "<table:pairs_error>", type = "table" })
    end
    if count > 100 then
      local keys = {}
      local n = 0
      local k_ok = pcall(function()
        for k in pairs(value) do
          n = n + 1
          if n <= 20 then keys[n] = tostring(k) end
          if n > 100 then break end
        end
      end)
      return try_encode({ ok = true, value = "table with " .. count .. " entries", type = "table (truncated)", count = count, sample_keys = keys })
    end
    local safe = safe_value(value, 0)
    return try_encode({ ok = true, value = safe, type = "table", count = count })
  end

  if t == "userdata" then
    -- Try vec2/vec3 first (SDK vector types exposed as userdata)
    local vx_ok, vx = pcall(function() return value.x end)
    local vy_ok, vy = pcall(function() return value.y end)
    if vx_ok and vy_ok and type(vx) == "number" and type(vy) == "number" then
      local vz_ok, vz = pcall(function() return value.z end)
      if vz_ok and type(vz) == "number" then
        return try_encode({ ok = true, value = { x = vx, y = vy, z = vz }, type = "vec3" })
      end
      return try_encode({ ok = true, value = { x = vx, y = vy }, type = "vec2" })
    end
    local info = serialize_game_object(value)
    if info.invalid then
      return try_encode({ ok = true, value = tostring(value), type = "userdata" })
    end
    return try_encode({ ok = true, value = info, type = "game_object" })
  end

  return try_encode({ ok = true, value = tostring(value), type = t })
end

------------------------------------------------------------
-- Result delivery
--
-- POST the payload straight back so the bridge needs no access to the game's
-- scripts_data directory. Older servers only understand the file handshake, so
-- fall back to that when the POST does not land.
------------------------------------------------------------
local function send_result(id, json_result)
  local delivered = false

  local function fallback()
    if delivered then return end
    delivered = true
    local filename = "lx_debug/result_" .. id .. ".json"
    write_file(filename, json_result)
    core.http_get(SERVER_URL .. "/result?id=" .. id .. "&file=" .. filename, {}, function() end)
  end

  if core.http_post then
    core.http_post(
      SERVER_URL .. "/result?id=" .. id,
      { ["Content-Type"] = "application/json" },
      json_result,
      function(code)
        if code == 200 then
          delivered = true
        else
          dlog("RESULT", "POST failed (code=" .. tostring(code) .. "), falling back to file")
          fallback()
        end
      end
    )
  else
    fallback()
  end
end

------------------------------------------------------------
-- Poll loop (handles single commands + batch /multi commands)
------------------------------------------------------------
local POLL_INTERVAL = 0.2
local POLL_TIMEOUT = 15.0   -- release the in-flight guard if a callback is lost
local last_poll = 0
local busy = false
local busy_since = 0

core.register_on_update_callback(function()
  -- Process deferred actions
  local now = core.time()
  local i = 1
  while i <= #_deferred_actions do
    local action = _deferred_actions[i]
    if now >= action.time then
      local ok, err = pcall(action.fn)
      if not ok then dlog("DEFER", "error: " .. tostring(err)) end
      table.remove(_deferred_actions, i)
    else
      i = i + 1
    end
  end

  -- Flush log periodically
  flush_log()

  -- If an http_get callback is never invoked (transport failure) the guard
  -- would otherwise pin `busy` forever and the bridge would go silent.
  if busy then
    if now - busy_since > POLL_TIMEOUT then
      dlog("POLL", "poll callback lost after " .. POLL_TIMEOUT .. "s -- releasing guard")
      busy = false
    else
      return
    end
  end
  if now - last_poll < POLL_INTERVAL then return end
  last_poll = now

  busy = true
  busy_since = now
  core.http_get(SERVER_URL .. "/poll", {}, function(code, ct, body, headers)
    busy = false
    if code ~= 200 or not body or body == "" then return end
    if body == '{"id":""}' then return end

    local dispatch_ok, dispatch_err = pcall(function()
      local parse_ok, cmd = pcall(JSON.decode, body)
      if not parse_ok or not cmd or not cmd.id or cmd.id == "" then return end

      -- Check for raw Lua execution
      if cmd.lua_exec and cmd.code then
        local fn, compile_err = loadstring("return " .. cmd.code)
        if not fn then
          -- Try without "return " prefix (statements like for/if/local)
          fn, compile_err = loadstring(cmd.code)
        end
        local ok, result
        if fn then
          -- Provide common roots as upvalues via environment
          local env = setmetatable({
            player = core.object_manager.get_local_player(),
            target = nil,
            pet = nil,
            dbg = dbg,
            nav = get_nav(),
            izi = require("common/izi_sdk"),
            JSON = JSON,
            vec3 = vec3,
          }, { __index = _G })
          local p = env.player
          if p and p:is_valid() then
            env.target = p:get_target()
            if p.get_pet then
              local pet_ok, pet_val = pcall(p.get_pet, p)
              if pet_ok then env.pet = pet_val end
            end
          end
          setfenv(fn, env)
          ok, result = pcall(fn)
        else
          ok, result = false, "compile error: " .. tostring(compile_err)
        end
        send_result(cmd.id, serialize_result(ok, result))
        return
      end

      -- Check for multi-command batch
      if cmd.multi and type(cmd.commands) == "table" then
        local results = {}
        for i, sub_cmd in ipairs(cmd.commands) do
          local sub_ok, sub_result
          if sub_cmd.lua_exec and sub_cmd.code then
            local fn, compile_err = loadstring("return " .. sub_cmd.code)
            if not fn then
              fn, compile_err = loadstring(sub_cmd.code)
            end
            if fn then
              local env = setmetatable({
                player = core.object_manager.get_local_player(),
                target = nil,
                pet = nil,
                dbg = dbg,
                nav = get_nav(),
                izi = require("common/izi_sdk"),
                JSON = JSON,
                vec3 = vec3,
              }, { __index = _G })
              local p = env.player
              if p and p:is_valid() then
                env.target = p:get_target()
                if p.get_pet then
                  local pet_ok, pet_val = pcall(p.get_pet, p)
                  if pet_ok then env.pet = pet_val end
                end
              end
              setfenv(fn, env)
              sub_ok, sub_result = pcall(fn)
            else
              sub_ok, sub_result = false, "compile error: " .. tostring(compile_err)
            end
          else
            sub_ok, sub_result = resolve_and_call(sub_cmd)
          end
          results[i] = { command = sub_cmd.code or sub_cmd.path, ok = sub_ok }
          if sub_ok then
            results[i].value = safe_value(sub_result, 0)
          else
            results[i].error = tostring(sub_result)
          end
        end
        local json_result = JSON.encode({ ok = true, type = "multi", count = #results, results = results })
        if #json_result > MAX_RESULT_SIZE then
          json_result = JSON.encode({ ok = true, type = "multi", count = #results, value = "batch result too large (" .. #json_result .. " bytes)" })
        end
        send_result(cmd.id, json_result)
        return
      end

      -- Single command (path resolution)
      local ok, result = resolve_and_call(cmd)
      send_result(cmd.id, serialize_result(ok, result))
    end)

    if not dispatch_ok then
      dlog("ERROR", "dispatch crash: " .. tostring(dispatch_err))
      local err_id = body:match('"id"%s*:%s*"([^"]+)"')
      if err_id then
        send_result(err_id, JSON.encode({ ok = false, error = "dispatch crash: " .. tostring(dispatch_err) }))
      end
    end
  end)
end)

------------------------------------------------------------
-- Public surface
--
-- Exposed so other in-game scripts (and the offline test harness) can reach
-- the helpers without going through the bridge.
------------------------------------------------------------
_G.LxDebug = {
  VERSION = VERSION,
  BUILD = BUILD,
  dbg = dbg,
  -- Internals the offline tests exercise directly.
  _internal = {
    is_hostile_to = is_hostile_to,
    read_powers = read_powers,
    normalize_aura = normalize_aura,
    serialize_result = serialize_result,
    safe_value = safe_value,
    resolve_and_call = resolve_and_call,
    parse_table_literal = parse_table_literal,
    record_event = record_event,
  },
}

dlog("INIT", "v" .. VERSION .. " build " .. BUILD .. " loaded -- polling localhost:7778")
