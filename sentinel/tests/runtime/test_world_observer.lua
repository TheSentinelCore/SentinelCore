-- tests/runtime/test_world_observer.lua
-- ADR 09a W7: the producers for the eight `game:*` topics recorder.lua subscribes to.
--
-- The Sylvannas SDK has no "quest accepted" callback, so every one of these events is DERIVED by
-- diffing observable state. That makes the derivation rules the whole product, and they are pinned
-- here: the SDK is replaced by a scripted fake world so a transition can be replayed exactly.

local EventBus = require("core/event_bus")
local WorldObserver = require("runtime/sensors/world_observer")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- A scripted client
-- ---------------------------------------------------------------------------
-- Every SDK reader the observer is allowed to touch, and nothing else. `sdk_calls` counts them so
-- the pacing and subscriber-gating claims are assertions rather than comments.
local function new_world()
    local w = {
        entries = {},   -- the quest log, exactly as get_quest_log_title yields it
        flagged = {},   -- quest_id -> boolean | function(nth_call) -> boolean
        flag_calls = {},
        boards = {},    -- quest_id -> array of leader-board strings
        gossip = false,
        trainer = 0,
        vendor = 0,
        sdk_calls = 0,
    }

    local function count()
        w.sdk_calls = w.sdk_calls + 1
    end

    w.quests = {
        get_num_quest_log_entries = function()
            count()
            return #w.entries
        end,
        get_quest_log_title = function(index)
            count()
            return w.entries[index]
        end,
        is_on_quest = function(quest_id)
            count()
            for _, entry in ipairs(w.entries) do
                if entry.quest_id == quest_id then
                    return true
                end
            end
            return false
        end,
        is_quest_flagged_completed = function(quest_id)
            count()
            w.flag_calls[quest_id] = (w.flag_calls[quest_id] or 0) + 1
            local value = w.flagged[quest_id]
            if type(value) == "function" then
                return value(w.flag_calls[quest_id]) == true
            end
            return value == true
        end,
        get_num_quest_leader_boards = function(log_index)
            count()
            local entry = w.entries[log_index]
            local board = entry and w.boards[entry.quest_id]
            return board and #board or 0
        end,
        get_quest_log_leader_board = function(obj_index, log_index)
            count()
            local entry = w.entries[log_index]
            local board = entry and w.boards[entry.quest_id]
            return board and board[obj_index] or nil
        end,
        is_gossip_frame_shown = function()
            count()
            return w.gossip
        end,
        get_num_trainer_services = function()
            count()
            return w.trainer
        end,
    }

    w.vendor_item_count = function()
        count()
        return w.vendor
    end

    function w.add_quest(quest_id, title)
        w.entries[#w.entries + 1] = { quest_id = quest_id, title = title, is_header = false }
    end

    function w.remove_quest(quest_id)
        for index = #w.entries, 1, -1 do
            if w.entries[index].quest_id == quest_id then
                table.remove(w.entries, index)
            end
        end
    end

    return w
end

local function npc_unit(entry_id, name)
    return {
        get_npc_id = function() return entry_id end,
        get_name = function() return name end,
    }
end

--- Subscribe a collector to every topic the observer produces. This doubles as the subscriber gate:
--- with a collector attached the observer is "recording", without one it must stay silent.
local function collect(bus)
    local seen = {}
    for _, topic in ipairs(WorldObserver.TOPICS) do
        local captured = topic
        bus:subscribe(topic, function(payload)
            seen[#seen + 1] = { topic = captured, payload = payload or {} }
        end)
    end
    return seen
end

local function events_of(seen, topic)
    local out = {}
    for _, event in ipairs(seen) do
        if event.topic == topic then
            out[#out + 1] = event.payload
        end
    end
    return out
end

local function new_observer(world, bus)
    return WorldObserver:new(bus, {
        quests = world.quests,
        vendor_item_count = world.vendor_item_count,
        taxi_nodes = world.taxi_nodes,
    })
end

--- The default context: a player standing still with no target. Individual tests override.
local function ctx(overrides)
    local base = { position = { x = 0, y = 0, z = 0 }, map_id = 0, zone_id = 12, zone_name = "Elwynn Forest" }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

-- ---------------------------------------------------------------------------
-- Accept
-- ---------------------------------------------------------------------------

function M.test_a_quest_appearing_in_the_log_publishes_one_accept()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.add_quest(100, "Wolves Across the Border")
    observer:refresh(10, ctx())

    local accepts = events_of(seen, "game:quest_accepted")
    T.assert_equal(#accepts, 1, "a quest entering the log is exactly one accept")
    T.assert_equal(accepts[1].quest_id, 100, "the accept must carry the quest id the recorder refs on")
    T.assert_equal(accepts[1].quest_name, "Wolves Across the Border", "the label is cached from the log title")
end

function M.test_quests_already_in_the_log_are_baselined_not_replayed()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Old Business")
    world.add_quest(101, "Older Business")
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    observer:refresh(10, ctx())

    T.assert_equal(#seen, 0,
        "quests taken before recording began were accepted at unknown npcs; replaying them fabricates route")
end

function M.test_an_accept_is_never_republished_by_later_polls()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.add_quest(100, "Wolves Across the Border")
    for tick = 1, 6 do
        observer:refresh(tick * 10, ctx())
    end

    T.assert_equal(#events_of(seen, "game:quest_accepted"), 1, "one transition is one event, however often it is polled")
end

-- ---------------------------------------------------------------------------
-- Turn-in vs abandon, and the cold read between them
-- ---------------------------------------------------------------------------

function M.test_a_departure_with_the_completed_flag_is_a_turn_in()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.remove_quest(100)
    world.flagged[100] = true
    for tick = 1, 8 do
        observer:refresh(tick, ctx())
    end

    local turn_ins = events_of(seen, "game:quest_turned_in")
    T.assert_equal(#turn_ins, 1, "a completed quest leaving the log is one turn-in")
    T.assert_equal(turn_ins[1].quest_id, 100, "the turn-in must identify the quest")
    T.assert_equal(#events_of(seen, "game:quest_abandoned"), 0, "a turn-in is never also an abandon")
end

function M.test_a_departure_without_the_completed_flag_is_an_abandon()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.remove_quest(100)
    for tick = 1, 8 do
        observer:refresh(tick, ctx())
    end

    local abandons = events_of(seen, "game:quest_abandoned")
    T.assert_equal(#abandons, 1, "a quest dropped without completion is one abandon")
    T.assert_equal(abandons[1].quest_id, 100, "the abandon must identify the quest so the recorder can retract it")
    T.assert_equal(#events_of(seen, "game:quest_turned_in"), 0, "an abandon is never also a turn-in")
end

function M.test_a_cold_completed_flag_does_not_mint_a_spurious_abandon()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.remove_quest(100)
    -- The exact failure this guard exists for: the client has not received the completed-quests
    -- bitmask yet, so the FIRST read answers a cold false and only later reads tell the truth.
    world.flagged[100] = function(nth_call) return nth_call >= 2 end
    for tick = 1, 8 do
        observer:refresh(tick, ctx())
    end

    T.assert_equal(#events_of(seen, "game:quest_abandoned"), 0,
        "the first completed-flag read is never conclusive; a cold false must not retract a real turn-in")
    T.assert_equal(#events_of(seen, "game:quest_turned_in"), 1,
        "once the flag warms up the departure resolves as the turn-in it was")
end

function M.test_one_flag_sample_is_never_enough_to_abandon()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.remove_quest(100)
    -- A single very late refresh: the settle DURATION has elapsed many times over, but the observer
    -- has still only asked the client once. Time alone must not license an abandon.
    observer:refresh(600, ctx())

    T.assert_equal(#events_of(seen, "game:quest_abandoned"), 0,
        "elapsed time is not evidence; a second independent flag read is")
end

function M.test_a_quest_that_reappears_cancels_its_pending_departure()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    -- QUEST_LOG_UPDATE churn: the log walk can transiently report fewer entries than the character
    -- actually holds. Treating that as a departure would retract a quest still being played -- and
    -- treating its return as a new accept would then duplicate it.
    world.remove_quest(100)
    bus:publish("game:quest_log_update", {})
    observer:refresh(1, ctx())
    world.add_quest(100, "Wolves Across the Border")
    bus:publish("game:quest_log_update", {})
    for tick = 2, 10 do
        observer:refresh(tick, ctx())
    end

    T.assert_equal(#seen, 0, "a quest that never actually left produces no accept, no turn-in and no abandon")
end

-- ---------------------------------------------------------------------------
-- NPC attribution
-- ---------------------------------------------------------------------------

function M.test_an_accept_is_attributed_to_the_npc_whose_frame_was_open()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.gossip = true
    observer:refresh(1, ctx({ target = npc_unit(823, "Deputy Willem") }))
    world.gossip = false
    world.add_quest(100, "Wolves Across the Border")
    bus:publish("game:quest_log_update", {})
    observer:refresh(2, ctx())

    local accepts = events_of(seen, "game:quest_accepted")
    T.assert_equal(#accepts, 1, "one accept")
    T.assert_equal(accepts[1].npc_id, 823, "the recorder needs the quest GIVER, not just the quest")
    T.assert_equal(accepts[1].npc_name, "Deputy Willem", "the cached label rides along with the ref")
end

function M.test_a_turn_in_is_attributed_to_the_npc_whose_frame_was_open()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.gossip = true
    observer:refresh(1, ctx({ target = npc_unit(197, "Marshal McBride") }))
    world.gossip = false
    world.remove_quest(100)
    world.flagged[100] = true
    for tick = 2, 8 do
        observer:refresh(tick, ctx())
    end

    local turn_ins = events_of(seen, "game:quest_turned_in")
    T.assert_equal(#turn_ins, 1, "one turn-in")
    T.assert_equal(turn_ins[1].npc_id, 197, "the turn-in npc is what makes the TurnIn task routable")
end

function M.test_a_stale_interaction_is_not_used_as_attribution()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.gossip = true
    observer:refresh(1, ctx({ target = npc_unit(823, "Deputy Willem") }))
    world.gossip = false
    -- Far past the attribution window: the human closed that frame and played on. Guessing here
    -- would put an AcceptQuest at an npc that never gave the quest, which is worse than no npc.
    world.add_quest(100, "Wolves Across the Border")
    observer:refresh(1 + WorldObserver.NPC_ATTRIBUTION_TTL + 5, ctx())

    local accepts = events_of(seen, "game:quest_accepted")
    T.assert_equal(#accepts, 1, "the accept is still published")
    T.assert_nil(accepts[1].npc_id, "an unattributable accept publishes a nil npc rather than a fabricated one")
end

-- ---------------------------------------------------------------------------
-- Objective progress
-- ---------------------------------------------------------------------------

function M.test_a_rising_leader_board_publishes_progress_once_per_change()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    world.boards[100] = { "Wolves slain: 0/10" }
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.boards[100] = { "Wolves slain: 3/10" }
    for tick = 1, 6 do
        observer:refresh(tick * 10, ctx())
    end
    world.boards[100] = { "Wolves slain: 4/10" }
    for tick = 7, 12 do
        observer:refresh(tick * 10, ctx())
    end

    local progress = events_of(seen, "game:quest_objective_progress")
    T.assert_equal(#progress, 2, "two counter changes across twelve polls is two events, not twelve")
    T.assert_equal(progress[1].have, 3, "the first change carries the new count")
    T.assert_equal(progress[1].need, 10, "the requirement is what the recorder stores as the task count")
    T.assert_equal(progress[1].quest_id, 100, "progress must name its quest")
    T.assert_equal(progress[2].have, 4, "the second change carries the raised count")
end

function M.test_a_zero_counter_on_a_freshly_accepted_quest_is_not_progress()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.add_quest(100, "Wolves Across the Border")
    world.boards[100] = { "Wolves slain: 0/10" }
    observer:refresh(10, ctx())

    T.assert_equal(#events_of(seen, "game:quest_objective_progress"), 0,
        "an untouched objective is not a task the human performed")
end

function M.test_two_objectives_of_one_quest_are_tracked_independently()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    world.boards[100] = { "Wolves slain: 0/10", "Wolf Pelt: 0/5" }
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.boards[100] = { "Wolves slain: 1/10", "Wolf Pelt: 0/5" }
    observer:refresh(10, ctx())
    world.boards[100] = { "Wolves slain: 1/10", "Wolf Pelt: 1/5" }
    observer:refresh(20, ctx())

    local progress = events_of(seen, "game:quest_objective_progress")
    T.assert_equal(#progress, 2, "each objective reports its own change")
    T.assert_equal(progress[1].objective_index, 1, "the index is the recorder's collapse key")
    T.assert_equal(progress[2].objective_index, 2, "the second objective must not collapse into the first")
end

-- ---------------------------------------------------------------------------
-- Services
-- ---------------------------------------------------------------------------

function M.test_a_vendor_frame_opening_publishes_one_vendor_used()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.vendor = 42
    for tick = 1, 5 do
        observer:refresh(tick, ctx({ target = npc_unit(1447, "Innkeeper Farley") }))
    end
    world.vendor = 0
    observer:refresh(6, ctx())

    local vendors = events_of(seen, "game:vendor_used")
    T.assert_equal(#vendors, 1, "a merchant frame held open for five polls is one visit")
    T.assert_equal(vendors[1].npc_id, 1447, "a Vendor task without its npc cannot be routed")
end

function M.test_a_trainer_frame_opening_publishes_one_trainer_used()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.trainer = 12
    for tick = 1, 5 do
        observer:refresh(tick, ctx({ target = npc_unit(328, "Llane Beshere") }))
    end

    local trainers = events_of(seen, "game:trainer_used")
    T.assert_equal(#trainers, 1, "one trainer frame is one visit")
    T.assert_equal(trainers[1].npc_id, 328, "the trainer npc is the whole content of a Trainer task")
end

-- ---------------------------------------------------------------------------
-- Taxi
-- ---------------------------------------------------------------------------

local function two_node_world()
    local world = new_world()
    world.taxi_nodes = {
        [2] = { name = "Stormwind, Elwynn", map = 0, x = 0, y = 0, z = 0 },
        [4] = { name = "Sentinel Hill, Westfall", map = 0, x = 2000, y = 0, z = 0 },
    }
    return world
end

function M.test_a_flight_between_two_nodes_publishes_taxi_taken()
    local world, bus = two_node_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.gossip = true
    observer:refresh(1, ctx({ position = { x = 5, y = 0, z = 0 }, target = npc_unit(352, "Dungar Longdrink") }))
    world.gossip = false
    -- 2000 yards in 60 seconds is ~33 yd/s: no ground travel in TBC reaches that.
    observer:refresh(61, ctx({ position = { x = 2000, y = 0, z = 0 } }))

    local flights = events_of(seen, "game:taxi_taken")
    T.assert_equal(#flights, 1, "arriving at a different node at flight speed is one Flight task")
    T.assert_equal(flights[1].from_node, 2, "the origin node is where the flight master was")
    T.assert_equal(flights[1].to_node, 4, "the destination node is what the recorder refs on")
    T.assert_equal(flights[1].npc_id, 352, "the flight master is attributable")
end

function M.test_walking_between_two_nodes_is_not_a_flight()
    local world, bus = two_node_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.gossip = true
    observer:refresh(1, ctx({ position = { x = 5, y = 0, z = 0 }, target = npc_unit(352, "Dungar Longdrink") }))
    world.gossip = false
    -- Same 2000 yards, but over 400 seconds (5 yd/s). A human who opened the flight map, declined,
    -- and then ran there must not be recorded as having flown.
    observer:refresh(401, ctx({ position = { x = 2000, y = 0, z = 0 } }))

    T.assert_equal(#events_of(seen, "game:taxi_taken"), 0, "ground travel is not a flight")
end

-- ---------------------------------------------------------------------------
-- Hearthstone
-- ---------------------------------------------------------------------------

function M.test_a_hearth_cast_followed_by_a_teleport_publishes_hearthstone_used()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx({ position = { x = 0, y = 0, z = 0 } }))
    bus:publish("spell:manual_cast", { spell_id = WorldObserver.HEARTHSTONE_SPELL_ID })
    observer:refresh(12, ctx({ position = { x = 4000, y = 0, z = 0 }, zone_id = 1519, zone_name = "Stormwind City" }))

    local hearths = events_of(seen, "game:hearthstone_used")
    T.assert_equal(#hearths, 1, "the cast plus the landing is one Hearth task")
    T.assert_equal(hearths[1].zone_id, 1519, "the destination is where the player ARRIVED, not where they cast")
    T.assert_equal(hearths[1].zone_name, "Stormwind City", "the label is cached from the client")
end

function M.test_a_hearth_cast_that_never_lands_publishes_nothing()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx({ position = { x = 0, y = 0, z = 0 } }))
    bus:publish("spell:manual_cast", { spell_id = WorldObserver.HEARTHSTONE_SPELL_ID })
    -- Interrupted: the ten-second channel was broken and the player never moved. Using the item is
    -- not arriving -- the same distinction runtime_action.lua's hearth handler had to learn.
    for tick = 1, 40 do
        observer:refresh(tick, ctx({ position = { x = 1, y = 0, z = 0 } }))
    end

    T.assert_equal(#events_of(seen, "game:hearthstone_used"), 0, "an interrupted hearth is not a Hearth task")
end

-- ---------------------------------------------------------------------------
-- Cost
-- ---------------------------------------------------------------------------

function M.test_nothing_is_polled_while_nobody_is_recording()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    local observer = new_observer(world, bus)

    for tick = 1, 100 do
        observer:refresh(tick, ctx())
    end

    T.assert_equal(world.sdk_calls, 0,
        "the observer exists on every character; it must cost nothing until a recording subscribes")
end

function M.test_the_quest_log_is_not_walked_on_every_refresh()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    local after_baseline = world.sdk_calls
    -- Sixty refreshes inside one quest-poll interval: a frame-rate log walk is ~85 SDK calls each.
    for tick = 1, 60 do
        observer:refresh(tick * (WorldObserver.QUEST_POLL_INTERVAL / 120), ctx())
    end

    T.assert_true(world.sdk_calls - after_baseline < 60,
        "the quest log walk must be paced, not run once per frame")
end

function M.test_a_quest_log_update_forces_an_immediate_walk()
    local world, bus = new_world(), EventBus:new()
    local seen = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    world.add_quest(100, "Wolves Across the Border")
    -- The client's own QUEST_LOG_UPDATE is the only signal that fires AT the transition. Waiting out
    -- the pacing interval instead would let the human close the gossip frame and walk away, and the
    -- accept would lose its npc.
    bus:publish("game:quest_log_update", {})
    observer:refresh(0.05, ctx())

    T.assert_equal(#events_of(seen, "game:quest_accepted"), 1,
        "a client quest-log signal must be honoured immediately, not at the next paced walk")
end

function M.test_a_new_recording_rebaselines_instead_of_replaying_the_log()
    local world, bus = new_world(), EventBus:new()
    world.add_quest(100, "Wolves Across the Border")
    local first = collect(bus)
    local observer = new_observer(world, bus)

    observer:refresh(0, ctx())
    T.assert_equal(#first, 0, "baseline is silent")

    -- Stop recording (drop every subscriber), then start a second one.
    bus._subs = {}
    observer:refresh(10, ctx())
    local second = collect(bus)
    observer:refresh(20, ctx())
    observer:refresh(30, ctx())

    T.assert_equal(#second, 0,
        "the second recording must baseline the log it inherits, not replay it as fresh accepts")
end

return M
