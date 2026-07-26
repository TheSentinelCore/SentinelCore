------------------------------------------------------------
-- Offline tests for ext_plugin_lx_debug.
--
-- Run from this directory:  luajit tests/run_tests.lua
--
-- Every helper that reads the Sylvannas API is covered here, because the
-- v2 bugs (is_enemy, get_active_auras, get_facing, get_power/0) were all
-- silent -- guarded by pcall or `and`, so they returned empty data instead
-- of failing. Tests assert on VALUES, never just on "did not error".
------------------------------------------------------------

package.path = "./?.lua;./tests/?.lua;" .. package.path

local mock = require("mock_sylvannas")

local passed, failed = 0, 0
local failures = {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    failures[#failures + 1] = name .. (detail and ("\n      " .. tostring(detail)) or "")
    io.write("  FAIL  ", name, "\n")
    if detail then io.write("        ", tostring(detail), "\n") end
    return
  end
  io.write("  ok    ", name, "\n")
end

local function eq(name, actual, expected)
  check(name, actual == expected,
    string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

------------------------------------------------------------
-- Load the plugin under the mock
------------------------------------------------------------
local function load_plugin(world)
  -- Fresh module state per scenario.
  package.loaded["init"] = nil
  package.loaded["lib/JSON"] = nil
  _G.LxDebug = nil
  _G.SentinelNavClient = nil

  mock.preload()
  local env = mock.install(world)
  dofile("main.lua")
  return env, _G.LxDebug.dbg, _G.LxDebug._internal
end

------------------------------------------------------------
io.write("\n-- hostility (regression: unit:is_enemy() never existed)\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero", pos = mock.vec3.new(0, 0, 0) })
  local wolf = mock.unit({ name = "Wolf", npc_id = 299, hostile = true, pos = mock.vec3.new(5, 0, 0) })
  local guard = mock.unit({ name = "Guard", npc_id = 68, hostile = false, pos = mock.vec3.new(6, 0, 0) })

  local env, dbg, internal = load_plugin({
    player = player,
    objects = { player, wolf, guard },
  })

  eq("is_hostile_to reports true for a hostile unit", internal.is_hostile_to(wolf, player), true)
  eq("is_hostile_to reports false for a friendly unit", internal.is_hostile_to(guard, player), false)
  eq("is_hostile_to is nil without a reference unit", internal.is_hostile_to(wolf, nil), nil)

  local hostile = dbg.nearby(100, "hostile")
  eq("nearby(hostile) returns only hostile units", hostile.shown, 1)
  eq("nearby(hostile) picked the wolf", hostile.objects[1].name, "Wolf")

  local friendly = dbg.nearby(100, "friendly")
  eq("nearby(friendly) returns only friendly units", friendly.shown, 1)
  eq("nearby(friendly) picked the guard", friendly.objects[1].name, "Guard")

  local _ = env
end

------------------------------------------------------------
io.write("\n-- auras (regression: get_active_auras never existed)\n")
------------------------------------------------------------
do
  local caster = mock.unit({ name = "Mage" })
  local player = mock.unit({
    name = "Hero",
    buffs = {
      mock.buff({ name = "Frost Armor", id = 7301, count = 1, duration = 1800, expire_time = 200000, caster = caster }),
    },
    debuffs = {
      mock.buff({ name = "Rend", id = 772, count = 3, duration = 21, expire_time = 110000 }),
    },
  })

  local _, dbg = load_plugin({ player = player, objects = { player } })
  local auras = dbg.auras("player")

  eq("auras counts buffs and debuffs", auras.count, 2)
  eq("buff name comes from buff_name", auras.auras[1].name, "Frost Armor")
  eq("buff id comes from buff_id", auras.auras[1].id, 7301)
  eq("buff is tagged as a buff", auras.auras[1].kind, "buff")
  eq("buff caster is resolved to a name", auras.auras[1].caster, "Mage")
  eq("debuff stacks come from count", auras.auras[2].stacks, 3)
  eq("debuff is tagged as a debuff", auras.auras[2].kind, "debuff")
end

------------------------------------------------------------
io.write("\n-- player_info (regression: get_power/0 and get_facing)\n")
------------------------------------------------------------
do
  local player = mock.unit({
    name = "Hero",
    level = 42,
    health = 60,
    max_health = 120,
    rotation = 3.14159,
    pos = mock.vec3.new(10.55, -20.44, 30.11),
    powers = { [0] = { current = 500, max = 1000 } },  -- mana
  })

  local _, dbg = load_plugin({ player = player, objects = { player }, map_id = 530 })
  local info = dbg.player_info()

  eq("player_info health_pct", info.health_pct, 50)
  eq("player_info reads rotation, not facing", info.rotation, 3.14)
  check("player_info reports mana from power_type 0", info.power and info.power.mana ~= nil,
    "power table was: " .. tostring(info.power))
  eq("player_info mana current", info.power and info.power.mana.current, 500)
  eq("player_info mana max", info.power and info.power.mana.max, 1000)
  check("player_info omits power types the unit does not have",
    info.power and info.power.rage == nil, "rage should be absent")
  eq("player_info map_id", info.map_id, 530)
end

------------------------------------------------------------
io.write("\n-- quest log\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero" })
  local _, dbg = load_plugin({
    player = player,
    objects = { player },
    completed_quests = { [1000] = true },
    -- Objective entries are tables on the real client, and the title table
    -- carries NO completion flag -- completeness is derived from objectives.
    quest_log = {
      { is_header = true, title = "Elwynn Forest" },
      {
        quest_id = 62, title = "Kobold Candles", level = 7,
        objectives = {
          { description = "Large Candle: 3/8", is_completed = false, objective_type = "item" },
        },
      },
      {
        quest_id = 83, title = "Report to Goldshire", level = 5,
        objectives = {
          { description = "Speak to Marshal Dughan", is_completed = true, objective_type = "event" },
        },
      },
    },
  })

  local log = dbg.quest_log()
  eq("quest_log skips headers", log.count, 2)
  eq("quest_log keeps the raw entry count", log.entries, 3)
  eq("quest_log resolves the first quest id", log.quests[1].quest_id, 62)
  eq("quest_log reads the objective description", log.quests[1].objectives[1].text, "Large Candle: 3/8")
  eq("quest_log parses objective progress (have)", log.quests[1].objectives[1].have, 3)
  eq("quest_log parses objective progress (need)", log.quests[1].objectives[1].need, 8)
  eq("quest_log marks an incomplete objective", log.quests[1].objectives[1].done, false)
  eq("quest_log keeps the objective type", log.quests[1].objectives[1].objective_type, "item")
  eq("quest_log derives incomplete from objectives", log.quests[1].is_complete, false)
  eq("quest_log derives complete from objectives", log.quests[2].is_complete, true)

  local status = dbg.quest_status(62)
  eq("quest_status finds the quest in the log", status.in_log, true)
  eq("quest_status reports on_quest", status.on_quest, true)
  eq("quest_status reports incomplete", status.is_complete, false)
  eq("quest_status title", status.title, "Kobold Candles")

  local done = dbg.quest_status(83)
  eq("quest_status reports a complete quest", done.is_complete, true)

  local never = dbg.quest_status(1000)
  eq("quest_status reports a quest not in the log", never.in_log, false)
  eq("quest_status reports the completed flag", never.flagged_completed, true)

  local missing = dbg.quest_objectives(999)
  check("quest_objectives explains a missing quest", type(missing) == "string", missing)
end

------------------------------------------------------------
io.write("\n-- loot, vendor, corpse, completed quests (live-discovered core.game_ui)\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero", pos = mock.vec3.new(0, 0, 0), dead = true, ghost = true })
  local env, dbg = load_plugin({
    player = player,
    objects = { player },
    completed_ids = { 62, 83, 104 },
    loot = {
      { name = "Linen Cloth", item_id = 2589, is_gold = false },
      { name = "Coins", item_id = 0, is_gold = true },
    },
    vendor = {
      { name = "Refreshing Spring Water", price = 25, quantity = 1 },
    },
    corpse_position = mock.vec3.new(0, 30, 40),
    resurrect_delay = 12,
  })

  local loot = dbg.loot()
  eq("loot reports the window is open", loot.open, true)
  eq("loot counts slots", loot.count, 2)
  eq("loot reads item names", loot.items[1].name, "Linen Cloth")
  eq("loot flags gold", loot.items[2].is_gold, true)

  dbg.loot_all()
  local order = {}
  for _, c in ipairs(env.recorded.input) do
    if c.fn == "loot_item" then order[#order + 1] = c.args[1] end
  end
  -- Looting shifts indices, so slots must be taken back to front.
  eq("loot_all walks slots backwards", table.concat(order, ","), "2,1")

  local vendor = dbg.vendor()
  eq("vendor reports the window is open", vendor.open, true)
  eq("vendor reads item info", vendor.items[1].name, "Refreshing Spring Water")
  eq("vendor tags the slot index", vendor.items[1].index, 1)

  local corpse = dbg.corpse()
  eq("corpse reports ghost state", corpse.is_ghost, true)
  eq("corpse confirms a corpse exists", corpse.has_corpse, true)
  eq("corpse computes distance", corpse.distance, 50)
  eq("corpse reports the resurrect delay", corpse.resurrect_delay, 12)

  local all = dbg.completed_quests()
  eq("completed_quests totals the set", all.total, 3)

  local hit = dbg.completed_quests(83)
  eq("completed_quests confirms a completed quest", hit.completed, true)
  local miss = dbg.completed_quests(999)
  eq("completed_quests reports a missing quest", miss.completed, false)
end

------------------------------------------------------------
io.write("\n-- why_stuck: loss of control and loot blocking\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero" })
  local _, dbg = load_plugin({ player = player, objects = { player }, in_control = false })
  local v = dbg.why_stuck().verdict
  check("why_stuck detects loss of control", v:find("NOT in control", 1, true) ~= nil, v)
end

do
  local player = mock.unit({ name = "Hero" })
  local _, dbg = load_plugin({
    player = player, objects = { player },
    loot = { { name = "Linen Cloth", item_id = 2589 } },
  })
  local v = dbg.why_stuck().verdict
  check("why_stuck detects a blocking loot window", v:find("loot window", 1, true) ~= nil, v)
end

------------------------------------------------------------
io.write("\n-- gossip and quest actions\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero", target = mock.unit({ name = "Marshal Dughan", npc_id = 234 }) })
  local env, dbg = load_plugin({
    player = player,
    objects = { player },
    gossip = { shown = true, options = { "I am ready" }, available = { 62 }, active = { 83 } },
  })

  local g = dbg.gossip()
  eq("gossip reports the frame is shown", g.gossip_frame_shown, true)
  eq("gossip lists available quests", g.available_quests[1], 62)
  eq("gossip resolves the target npc", g.npc.npc_id, 234)

  dbg.abandon_quest(62)
  local calls = {}
  for _, c in ipairs(env.recorded.quests) do calls[#calls + 1] = c.fn end
  check("abandon_quest without a log entry does not call the SDK", #calls == 0,
    "unexpected calls: " .. table.concat(calls, ","))
end

------------------------------------------------------------
io.write("\n-- deferred quest turn-in sequencing\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero" })
  local env, dbg = load_plugin({ player = player, objects = { player } })

  dbg.turn_in_quest(62, 2)
  local function fns()
    local out = {}
    for _, c in ipairs(env.recorded.quests) do out[#out + 1] = c.fn end
    return table.concat(out, ",")
  end

  eq("turn_in selects the active quest immediately", fns(), "select_gossip_active_quest")

  -- Drive the update loop past each deferred step.
  env.advance(0.6)
  env.recorded.on_update()
  eq("turn_in completes after the first delay", fns(),
    "select_gossip_active_quest,complete_quest")

  env.advance(0.6)
  env.recorded.on_update()
  eq("turn_in takes the reward after the second delay", fns(),
    "select_gossip_active_quest,complete_quest,get_quest_reward")

  local reward = env.recorded.quests[3].args[1]
  eq("turn_in passes the requested reward index", reward, 2)
end

------------------------------------------------------------
io.write("\n-- game event recorder\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero" })
  local env, dbg = load_plugin({ player = player, objects = { player } })

  local fire = env.recorded.on_game_event
  check("plugin registered a game event callback", type(fire) == "function")

  fire("PLAYER_REGEN_DISABLED", {})
  fire("UI_ERROR_MESSAGE", { 50, "You are too far away." })
  fire("UI_ERROR_MESSAGE", { 51, "You can't do that yet." })

  local errs = dbg.errors(10)
  eq("errors captures UI_ERROR_MESSAGE only", errs.count, 2)
  eq("errors preserves message text", errs.errors[1].message, "You are too far away.")
  eq("errors orders oldest first", errs.errors[2].message, "You can't do that yet.")
  eq("errors captures the error type", errs.errors[1].error_type, 50)

  local events = dbg.events(10)
  eq("events records non-error events too", events.count, 3)

  local filtered = dbg.events(10, "UI_ERROR")
  eq("events filters by substring", filtered.count, 2)

  -- The combat log fires hundreds of times per second and would evict the
  -- rest of the ring buffer.
  fire("COMBAT_LOG_EVENT_UNFILTERED", { 1, "SPELL_DAMAGE" })
  eq("combat log spam is not buffered", dbg.events(10).count, 3)
end

------------------------------------------------------------
io.write("\n-- nav report\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero", pos = mock.vec3.new(0, 0, 0) })
  local env, dbg = load_plugin({ player = player, objects = { player } })

  eq("nav_report explains a missing nav client",
    dbg.nav_report(), "nav client not available (_G.SentinelNavClient.client is nil)")

  _G.SentinelNavClient = {
    client = {
      get_state = function() return "navigating" end,
      get_full_state = function() return "navigating.recovering.strafing" end,
      is_moving = function() return true end,
      is_server_available = function() return true end,
      get_path_index = function() return 2 end,
      get_destination = function() return mock.vec3.new(30, 40, 0) end,
      get_progress = function()
        return { percent = 0.25, current_index = 2, total_waypoints = 8, waypoints_remaining = 6 }
      end,
      get_current_path = function()
        local p = {}
        for i = 1, 8 do p[i] = mock.vec3.new(i, 0, 0) end
        return p
      end,
    },
  }

  local r = dbg.nav_report()
  eq("nav_report exposes the hierarchical state", r.full_state, "navigating.recovering.strafing")
  eq("nav_report converts progress to a percentage", r.progress.percent, 25)
  eq("nav_report reports waypoint count", r.waypoint_count, 8)
  eq("nav_report computes distance to destination", r.distance_to_destination, 50)
  eq("nav_report trims to the next few waypoints", #r.next_waypoints, 5)
  eq("nav_report starts waypoints at the current index", r.next_waypoints[1].i, 2)

  local _ = env
end

------------------------------------------------------------
io.write("\n-- why_stuck verdicts\n")
------------------------------------------------------------
do
  local dead = mock.unit({ name = "Hero", dead = true, ghost = true })
  local _, dbg = load_plugin({ player = dead, objects = { dead } })
  check("why_stuck detects death", dbg.why_stuck().verdict:find("dead/ghost", 1, true) ~= nil)
end

do
  local player = mock.unit({ name = "Hero" })
  local _, dbg = load_plugin({
    player = player, objects = { player },
    gossip = { shown = true },
  })
  check("why_stuck detects a blocking gossip frame",
    dbg.why_stuck().verdict:find("gossip frame", 1, true) ~= nil)
end

do
  local player = mock.unit({ name = "Hero" })
  local env, dbg = load_plugin({ player = player, objects = { player } })
  env.recorded.on_game_event("UI_ERROR_MESSAGE", { 50, "You are too far away." })
  local v = dbg.why_stuck().verdict
  check("why_stuck surfaces the game's own error", v:find("too far away", 1, true) ~= nil, v)
end

------------------------------------------------------------
io.write("\n-- result delivery\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero" })
  local env = load_plugin({ player = player, objects = { player } })

  -- Feed the poll loop a command and let the plugin answer it.
  env.advance(1.0)
  env.recorded.on_update()

  local poll = env.recorded.http_get[#env.recorded.http_get]
  check("plugin polls the bridge", poll.url:find("/poll", 1, true) ~= nil, poll.url)

  poll.cb(200, "application/json", '{"id":"cmd_1","path":"core.get_ping","args":[],"root":"core"}', {})

  eq("result is POSTed rather than written to disk", #env.recorded.http_post, 1)
  local post = env.recorded.http_post[1]
  check("result POST carries the command id", post.url:find("id=cmd_1", 1, true) ~= nil, post.url)

  local body = post.body
  check("result body reports success", body:find('"ok":true', 1, true) ~= nil, body)
  check("result body carries the ping value", body:find("42", 1, true) ~= nil, body)
end

------------------------------------------------------------
io.write("\n-- poll guard watchdog\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero" })
  local env = load_plugin({ player = player, objects = { player } })

  env.advance(1.0)
  env.recorded.on_update()
  local before = #env.recorded.http_get

  -- Callback never fires: the guard must not pin the bridge forever.
  env.advance(1.0)
  env.recorded.on_update()
  eq("guard suppresses polling while a request is in flight", #env.recorded.http_get, before)

  env.advance(20.0)
  env.recorded.on_update()
  check("guard is released after the watchdog timeout", #env.recorded.http_get > before,
    "still " .. #env.recorded.http_get)
end

------------------------------------------------------------
io.write("\n-- bag scan\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero" })
  local _, dbg = load_plugin({
    player = player,
    objects = { player },
    bags = {
      [0] = {
        { slot_id = 36, object = mock.unit({ name = "Linen Cloth", item_id = 2589, stack = 12 }) },
        { slot_id = 10, object = mock.unit({ name = "Not Storage", item_id = 1 }) },  -- filtered
      },
      [1] = {
        { slot_id = 1, object = mock.unit({ name = "Copper Bar", item_id = 2841, stack = 5 }) },
      },
    },
  })

  local scan = dbg.bag_scan()
  eq("bag_scan skips non-storage slots in bag 0", scan.count, 2)
  eq("bag_scan maps bag 0 raw slot to container slot", scan.items[1].slot, 0)
  eq("bag_scan reads the stack count", scan.items[1].stack, 12)
  eq("bag_scan maps other bags with a -1 offset", scan.items[2].slot, 0)
  eq("bag_scan reads the item id", scan.items[2].item_id, 2841)
end

------------------------------------------------------------
------------------------------------------------------------
io.write("\n-- nearby: scenery must not be reported as NPCs\n")
------------------------------------------------------------
do
  -- Verified live: "Cathedral Square" is a signpost with npc_id=2190,
  -- is_unit=false, is_basic_object=true, level=-1, is_dead=true. Filtering on
  -- npc_id ~= 0 (the old rule) let every signpost through as an NPC.
  local player = mock.unit({ name = "Hero", pos = mock.vec3.new(0, 0, 0) })
  local vendor = mock.unit({ name = "Gunther Weller", npc_id = 1289, level = 30,
                             pos = mock.vec3.new(5, 0, 0) })
  local signpost = mock.unit({ name = "Cathedral Square", npc_id = 2190, level = -1,
                               dead = true, is_unit = false, pos = mock.vec3.new(6, 0, 0) })
  local other = mock.unit({ name = "Otherguy", npc_id = 0, is_player = true,
                            pos = mock.vec3.new(7, 0, 0) })

  local _, dbg = load_plugin({ player = player, objects = { player, vendor, signpost, other } })

  local npcs = dbg.nearby(100, "npc")
  eq("nearby(npc) excludes scenery and players", npcs.shown, 1)
  eq("nearby(npc) keeps the real NPC", npcs.objects[1].name, "Gunther Weller")

  local objects = dbg.nearby(100, "object")
  eq("nearby(object) returns scenery only", objects.shown, 1)
  eq("nearby(object) picked the signpost", objects.objects[1].name, "Cathedral Square")

  local players = dbg.nearby(100, "player")
  eq("nearby(player) uses is_player, not npc_id", players.shown, 1)
  eq("nearby(player) picked the player", players.objects[1].name, "Otherguy")

  local units = dbg.nearby(100, "unit")
  eq("nearby(unit) includes NPCs and players but not scenery", units.shown, 2)
end


------------------------------------------------------------
io.write("\n-- corpse: no corpse must not be reported as a distant one\n")
------------------------------------------------------------
do
  local player = mock.unit({ name = "Hero", pos = mock.vec3.new(-8803, 595, 97) })
  local _, dbg = load_plugin({
    player = player,
    objects = { player },
    -- A live player has no corpse; the client reports the origin.
    corpse_position = mock.vec3.new(0, 0, 0),
  })
  local c = dbg.corpse()
  eq("corpse reports no corpse for a live player", c.has_corpse, false)
  eq("corpse omits a bogus position", c.corpse_position, nil)
  eq("corpse omits a bogus distance", c.distance, nil)
  eq("corpse still reports alive state", c.is_dead, false)
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
  io.write("\nFailures:\n")
  for _, f in ipairs(failures) do io.write("  - ", f, "\n") end
  os.exit(1)
end
