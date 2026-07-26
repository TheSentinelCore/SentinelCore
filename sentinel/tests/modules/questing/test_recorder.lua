-- tests/modules/questing/test_recorder.lua
-- Recording Mode (ADR 09a W5) — the replacement content pipeline.
--
-- The importer produced 107,399 actions across 277 profiles and every one of its 38,726 Travel
-- positions carried world_z = 0, because guide text never had heights. The recorder exists so a
-- human plays a zone once and the platform gets a first-draft campaign instead. That is why the
-- assertions below are mostly about what the recorder REFUSES to emit: a route waypoint recorded
-- here would reintroduce exactly the coordinate corpus this design was built to delete.
--
-- The event bus under test is the real `core/event_bus` — a stub bus would let the recorder pass
-- against a pub/sub shape the runtime does not have.

local EventBus = require("core/event_bus")
local Recorder = require("modules/questing/recorder")
local T = require("tests/test_util")

local M = {}

local function fresh(opts)
    opts = opts or {}
    local bus = EventBus:new(function() end)
    local seq = 0
    local rec = Recorder:new({
        event_bus = bus,
        now = opts.now or function() return 1000 end,
        -- Deterministic ids keep failure messages readable; the real generator is covered
        -- separately by test_generated_ids_are_uuid_shaped_and_unique.
        new_id = opts.new_id or function()
            seq = seq + 1
            return string.format("id-%03d", seq)
        end,
    })
    return rec, bus
end

local function accept_payload()
    return {
        quest_id = 783,
        quest_name = "Kobold Camp Cleanup",
        npc_id = 823,
        npc_name = "Deputy Willem",
    }
end

local function nodes_of(rec)
    local campaign = rec:get_campaign()
    if not campaign then return {} end
    return campaign.graphs[1].nodes
end

-- ============================================================================
-- Start / stop gating — a recorder that is off must be inert
-- ============================================================================

function M.test_nothing_is_recorded_before_start()
    local rec, bus = fresh()
    bus:publish("game:quest_accepted", accept_payload())
    T.assert_false(rec:is_recording(), "a fresh recorder is not recording")
    T.assert_nil(rec:get_campaign(), "no campaign exists until start()")
end

function M.test_nothing_is_recorded_after_stop()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    rec:stop()
    bus:publish("game:quest_accepted", accept_payload())
    T.assert_false(rec:is_recording(), "stop() clears the recording flag")
    T.assert_equal(#nodes_of(rec), 0, "events after stop() must not append nodes")
end

function M.test_stop_returns_the_campaign_and_keeps_it_readable()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:quest_accepted", accept_payload())
    local returned = rec:stop()
    T.assert_not_nil(returned, "stop() returns the recorded campaign")
    T.assert_equal(#returned.graphs[1].nodes, 1, "the campaign returned by stop() holds the work")
    T.assert_equal(rec:get_campaign(), returned, "get_campaign() still reads the same campaign")
end

function M.test_restart_begins_a_new_campaign()
    local rec, bus = fresh()
    rec:start("Run A")
    bus:publish("game:quest_accepted", accept_payload())
    rec:stop()
    rec:start("Run B")
    T.assert_equal(#nodes_of(rec), 0, "a second start() must not inherit the first run's nodes")
    T.assert_equal(rec:get_campaign().name, "Run B", "the new campaign carries the new name")
end

-- ============================================================================
-- Quest tasks — intent only, EntityRef shape from plan §1.2
-- ============================================================================

function M.test_accept_event_produces_one_accept_quest_node()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:quest_accepted", accept_payload())

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 1, "one accept observation is exactly one node")
    T.assert_equal(nodes[1].type, "questing.AcceptQuest", "accept maps to questing.AcceptQuest")
    T.assert_equal(nodes[1].intent.quest.ref, "quest:783", "quest ref is <kind>:<id>")
    T.assert_equal(nodes[1].intent.quest.label, "Kobold Camp Cleanup", "quest label is the cached name")
    T.assert_equal(nodes[1].intent.from.ref, "npc:823", "the giver is an npc EntityRef")
    T.assert_equal(nodes[1].intent.from.label, "Deputy Willem", "the giver label is the cached name")
end

function M.test_turn_in_event_produces_a_turn_in_node()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:quest_turned_in", {
        quest_id = 783, quest_name = "Kobold Camp Cleanup",
        npc_id = 823, npc_name = "Deputy Willem",
    })

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 1, "one turn-in is one node")
    T.assert_equal(nodes[1].type, "questing.TurnIn", "turn-in maps to questing.TurnIn")
    T.assert_equal(nodes[1].intent.quest.ref, "quest:783", "turn-in carries the quest ref")
    T.assert_equal(nodes[1].intent.to.ref, "npc:823", "turn-in names the receiving npc")
end

function M.test_repeated_accept_of_the_same_quest_is_one_node()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:quest_accepted", accept_payload())
    bus:publish("game:quest_accepted", accept_payload())
    bus:publish("game:quest_accepted", accept_payload())

    T.assert_equal(#nodes_of(rec), 1, "a re-fired accept for a quest already accepted is not new intent")
end

-- ============================================================================
-- Objective progress — the collapse rule
-- ============================================================================

function M.test_ten_kill_ticks_collapse_to_one_kill_task_with_count_ten()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    for have = 1, 10 do
        bus:publish("game:quest_objective_progress", {
            quest_id = 783, quest_name = "Kobold Camp Cleanup",
            objective_index = 1, kind = "kill",
            target_id = 6, target_name = "Kobold Vermin",
            have = have, need = 10,
        })
    end

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 1, "an objective ticking 1/10 -> 10/10 is ONE task, not ten nodes")
    T.assert_equal(nodes[1].type, "questing.Kill", "a monster objective maps to questing.Kill")
    T.assert_equal(nodes[1].intent.count, 10, "the collapsed task carries the required count")
    T.assert_equal(nodes[1].intent.target.ref, "npc:6", "the kill target is an npc EntityRef")
    T.assert_equal(nodes[1].intent.target.label, "Kobold Vermin", "the target label is the cached name")
    T.assert_equal(nodes[1].intent.quest.ref, "quest:783", "the task points back at its quest")
end

function M.test_item_objective_maps_to_collect()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    for have = 1, 4 do
        bus:publish("game:quest_objective_progress", {
            quest_id = 783, objective_index = 2, kind = "collect",
            item_id = 2672, item_name = "Kobold Candle",
            have = have, need = 8,
        })
    end

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 1, "collect ticks collapse the same way kill ticks do")
    T.assert_equal(nodes[1].type, "questing.Collect", "an item objective maps to questing.Collect")
    T.assert_equal(nodes[1].intent.item.ref, "item:2672", "the collect target is an item EntityRef")
    T.assert_equal(nodes[1].intent.count, 8, "the collapsed task carries the required count")
end

function M.test_interleaved_objectives_do_not_duplicate_each_other()
    -- Two objectives of one quest advancing together is the normal case in the field (a mob that
    -- both dies and drops). Consecutive-only dedup would emit a node per alternation.
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    for i = 1, 5 do
        bus:publish("game:quest_objective_progress", {
            quest_id = 783, objective_index = 1, kind = "kill",
            target_id = 6, target_name = "Kobold Vermin", have = i, need = 5,
        })
        bus:publish("game:quest_objective_progress", {
            quest_id = 783, objective_index = 2, kind = "collect",
            item_id = 2672, item_name = "Kobold Candle", have = i, need = 5,
        })
    end

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 2, "two distinct objectives are exactly two tasks")
    T.assert_equal(nodes[1].type, "questing.Kill", "the kill objective keeps its own task")
    T.assert_equal(nodes[2].type, "questing.Collect", "the collect objective keeps its own task")
end

function M.test_count_falls_back_to_the_highest_observed_progress()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    for have = 1, 3 do
        bus:publish("game:quest_objective_progress", {
            quest_id = 783, objective_index = 1, kind = "kill",
            target_id = 6, target_name = "Kobold Vermin", have = have,
        })
    end

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 1, "a need-less objective still collapses")
    T.assert_equal(nodes[1].intent.count, 3, "without `need`, the highest observed `have` is the count")
end

function M.test_the_same_objective_reopens_after_the_quest_is_turned_in()
    -- A daily/repeatable quest re-accepted later is genuinely new intent, not a duplicate.
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    local tick = {
        quest_id = 783, objective_index = 1, kind = "kill",
        target_id = 6, target_name = "Kobold Vermin", have = 1, need = 1,
    }
    bus:publish("game:quest_objective_progress", tick)
    bus:publish("game:quest_turned_in", { quest_id = 783, npc_id = 823 })
    bus:publish("game:quest_accepted", { quest_id = 783, npc_id = 823 })
    bus:publish("game:quest_objective_progress", tick)

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 4, "turn-in closes the objective, so a later tick opens a fresh task")
    T.assert_equal(nodes[4].type, "questing.Kill", "the reopened objective is a new Kill task")
end

-- ============================================================================
-- Service tasks
-- ============================================================================

function M.test_vendor_trainer_flight_and_hearth_map_to_their_task_types()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:vendor_used", { npc_id = 384, npc_name = "Corina Steele", actions = { "sell", "repair" } })
    bus:publish("game:trainer_used", { npc_id = 197, npc_name = "Llane Beshere" })
    bus:publish("game:taxi_taken", {
        npc_id = 352, npc_name = "Dungar Longdrink",
        from_area_id = 12, from_area_name = "Elwynn Forest",
        to_area_id = 1519, to_area_name = "Stormwind City",
    })
    bus:publish("game:hearthstone_used", { area_id = 1519, area_name = "Stormwind City" })

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 4, "four services are four tasks")
    T.assert_equal(nodes[1].type, "questing.Vendor", "vendor maps to questing.Vendor")
    T.assert_equal(nodes[1].intent.npc.ref, "npc:384", "the vendor is an npc EntityRef")
    T.assert_equal(nodes[1].intent.actions[2], "repair", "the observed vendor actions are kept")
    T.assert_equal(nodes[2].type, "questing.Trainer", "trainer maps to questing.Trainer")
    T.assert_equal(nodes[2].intent.npc.ref, "npc:197", "the trainer is an npc EntityRef")
    T.assert_equal(nodes[3].type, "questing.Flight", "taxi maps to questing.Flight")
    T.assert_equal(nodes[3].intent.to.ref, "area:1519", "the flight destination is an area EntityRef")
    T.assert_equal(nodes[3].intent.from.ref, "area:12", "the flight origin is an area EntityRef")
    T.assert_equal(nodes[4].type, "questing.Hearth", "hearthstone maps to questing.Hearth")
    T.assert_equal(nodes[4].intent.destination.ref, "area:1519", "hearth records where it landed")
end

function M.test_consecutive_vendor_visits_collapse()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    for _ = 1, 6 do
        bus:publish("game:vendor_used", { npc_id = 384, npc_name = "Corina Steele", actions = { "sell" } })
    end

    T.assert_equal(#nodes_of(rec), 1, "spam-clicking one vendor is one Vendor task")
end

-- ============================================================================
-- THE CENTRAL RULE — Tasks, never waypoints
-- ============================================================================

function M.test_a_position_stream_never_produces_route_nodes()
    -- `player:profile_refreshed` is the real position firehose (sensor_hub publishes it every
    -- refresh). The recorder must consume it and still emit nothing: movement is regenerated by
    -- NavServer at resolve time, which is the whole reason recording sidesteps world_z.
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    for i = 1, 200 do
        bus:publish("player:profile_refreshed", { position = { x = i, y = i * 2, z = 0 } })
    end

    T.assert_equal(#nodes_of(rec), 0, "200 position samples must produce ZERO nodes")
end

function M.test_no_emitted_node_is_a_travel_or_waypoint_type()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    for i = 1, 20 do
        bus:publish("player:profile_refreshed", { position = { x = i, y = i, z = 0 } })
        bus:publish("game:quest_accepted", { quest_id = 700 + i, npc_id = 800 + i })
    end

    for _, node in ipairs(nodes_of(rec)) do
        T.assert_equal(node.type, "questing.AcceptQuest", "only real tasks are recorded")
        T.assert_nil(node.intent.waypoints, "a task never carries a waypoint list")
        T.assert_nil(node.intent.path, "a task never carries a path")
    end
end

function M.test_position_is_incidental_context_on_a_task_not_a_node()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("player:profile_refreshed", { position = { x = -8913.2, y = 554.6, z = 93.7 }, map_id = 0 })
    bus:publish("game:quest_accepted", accept_payload())

    local nodes = nodes_of(rec)
    T.assert_equal(#nodes, 1, "the position sample added no node of its own")
    T.assert_not_nil(nodes[1].context, "the task keeps where it was observed, as context")
    T.assert_near(nodes[1].context.position.z, 93.7, 0.001,
        "the observed z is a real height, never the importer's world_z = 0 placeholder")
    T.assert_nil(nodes[1].intent.position, "observed position is context, never authored intent")
end

-- ============================================================================
-- Campaign shape (plan §1.3) — intent only, `resolved` omitted
-- ============================================================================

function M.test_campaign_matches_the_plan_shape_with_resolved_absent()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:quest_accepted", accept_payload())
    local campaign = rec:get_campaign()

    T.assert_equal(campaign.schema_version, 3, "recordings are schema_version 3")
    T.assert_not_nil(campaign.id, "the campaign carries an id")
    T.assert_equal(campaign.name, "Elwynn Forest", "the campaign carries the recording name")
    T.assert_equal(#campaign.imports, 0, "a recording imports nothing")
    T.assert_equal(#campaign.variables, 0, "a recording declares no variables")
    T.assert_equal(#campaign.conditions, 0, "a recording declares no conditions")
    T.assert_equal(#campaign.graphs, 1, "a recording is one graph")

    local graph = campaign.graphs[1]
    T.assert_not_nil(graph.id, "the graph carries an id")
    T.assert_equal(graph.entry_node, graph.nodes[1].id, "entry_node points at the first task")
    T.assert_nil(graph.nodes[1].resolved,
        "`resolved` is derived server-side; a recording must never claim it")
end

function M.test_nodes_are_chained_by_linear_unguarded_edges()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:quest_accepted", { quest_id = 1, npc_id = 11 })
    bus:publish("game:quest_accepted", { quest_id = 2, npc_id = 12 })
    bus:publish("game:quest_accepted", { quest_id = 3, npc_id = 13 })

    local graph = rec:get_campaign().graphs[1]
    T.assert_equal(#graph.nodes, 3, "three accepts are three nodes")
    T.assert_equal(#graph.edges, 2, "a linear route of n nodes has n-1 edges")
    T.assert_equal(graph.edges[1].from, graph.nodes[1].id, "edge 1 leaves node 1")
    T.assert_equal(graph.edges[1].to, graph.nodes[2].id, "edge 1 arrives at node 2")
    T.assert_nil(graph.edges[1].guard, "a recorded route is unguarded; branches are authored later")
end

-- ============================================================================
-- Abandon — retraction, because the task vocabulary has no Abandon
-- ============================================================================

function M.test_abandoning_a_quest_retracts_its_recorded_tasks()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:quest_accepted", { quest_id = 783, npc_id = 823 })
    bus:publish("game:quest_objective_progress", {
        quest_id = 783, objective_index = 1, kind = "kill",
        target_id = 6, have = 1, need = 4,
    })
    bus:publish("game:quest_accepted", { quest_id = 900, npc_id = 901 })
    T.assert_equal(#nodes_of(rec), 3, "three tasks before the abandon")

    bus:publish("game:quest_abandoned", { quest_id = 783 })

    local graph = rec:get_campaign().graphs[1]
    T.assert_equal(#graph.nodes, 1, "abandoning a quest removes the tasks the human just undid")
    T.assert_equal(graph.nodes[1].intent.quest.ref, "quest:900", "the unrelated quest survives")
    T.assert_equal(graph.entry_node, graph.nodes[1].id, "entry_node follows the surviving head")
    T.assert_equal(#graph.edges, 0, "edges are rebuilt for the surviving chain")
end

-- ============================================================================
-- Identity and persistence
-- ============================================================================

function M.test_generated_ids_are_uuid_shaped_and_unique()
    local bus = EventBus:new(function() end)
    local rec = Recorder:new({ event_bus = bus, now = function() return 1 end })
    rec:start("Elwynn Forest")
    local seen = {}
    for i = 1, 50 do
        bus:publish("game:quest_accepted", { quest_id = i, npc_id = i })
    end
    for _, node in ipairs(rec:get_campaign().graphs[1].nodes) do
        T.assert_true(node.id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil,
            "node ids are v4-shaped uuids, got " .. tostring(node.id))
        T.assert_nil(seen[node.id], "node ids are never reused")
        seen[node.id] = true
    end
end

function M.test_id_generation_never_disturbs_the_global_random_stream()
    -- The recorder mints ids from a private stream on purpose. Seeding or drawing from
    -- `math.random` would change every draw the rest of the addon and every other offline suite
    -- gets, from humanization delays to combat jitter.
    -- Asserted by spying rather than by re-seeding, so this test does not itself become the thing
    -- it forbids: math.randomseed here would move the stream for every suite registered after it.
    local original_random, original_seed = math.random, math.randomseed
    local touched = false
    math.random = function(...) touched = true; return original_random(...) end
    math.randomseed = function(...) touched = true; return original_seed(...) end

    local ok, err = pcall(function()
        local bus = EventBus:new(function() end)
        local rec = Recorder:new({ event_bus = bus, now = function() return 1 end })
        rec:start("Elwynn Forest")
        for i = 1, 10 do
            bus:publish("game:quest_accepted", { quest_id = i, npc_id = i })
        end
        T.assert_equal(#rec:get_campaign().graphs[1].nodes, 10, "ten accepts minted ten ids")
    end)

    math.random, math.randomseed = original_random, original_seed
    if not ok then error(err) end
    T.assert_false(touched, "minting ids must never read or reseed the global random stream")
end

function M.test_save_writes_encodable_json_through_the_sandbox_file_io()
    local rec, bus = fresh()
    rec:start("Elwynn Forest")
    bus:publish("game:quest_accepted", accept_payload())

    local captured = {}
    local original_write = core.write_data_file
    core.write_data_file = function(path, content)
        captured.path, captured.content = path, content
        return true
    end
    local ok = rec:save("recordings/elwynn.json")
    core.write_data_file = original_write

    T.assert_true(ok, "save() reports success when core.write_data_file accepts the write")
    T.assert_equal(captured.path, "recordings/elwynn.json", "save() writes to the requested path")
    T.assert_true(captured.content:find('"questing.AcceptQuest"', 1, true) ~= nil,
        "the written JSON carries the recorded task type")
    T.assert_true(captured.content:find("resolved", 1, true) == nil,
        "the written JSON must not contain a `resolved` block")
end

function M.test_save_without_a_campaign_fails_instead_of_writing()
    local rec = fresh()
    T.assert_false(rec:save("recordings/nothing.json"), "there is nothing to save before start()")
end

return M
