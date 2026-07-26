-- tests/integration/test_recording_pipeline.lua
-- ADR 09a W7: the proof that Recording Mode is connected end to end.
--
-- recorder.lua landed subscribed to nine topics of which exactly one had a producer, so the whole
-- content pipeline was inert in game while every recorder unit test passed -- the suite drove
-- `observe()` directly and never asked whether anything published. This suite closes that hole: a
-- real EventBus, a real WorldObserver reading a scripted client, and a real Recorder, wired the way
-- SentinelApp wires them. Nothing here calls `Recorder:observe` by hand.

local EventBus = require("core/event_bus")
local Recorder = require("modules/questing/recorder")
local WorldObserver = require("runtime/sensors/world_observer")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- A scripted client, driven as a play session
-- ---------------------------------------------------------------------------

local function new_client()
    local c = { entries = {}, flagged = {}, boards = {}, gossip = false, trainer = 0, vendor = 0 }

    c.quests = {
        get_num_quest_log_entries = function() return #c.entries end,
        get_quest_log_title = function(index) return c.entries[index] end,
        is_on_quest = function(quest_id)
            for _, entry in ipairs(c.entries) do
                if entry.quest_id == quest_id then return true end
            end
            return false
        end,
        is_quest_flagged_completed = function(quest_id) return c.flagged[quest_id] == true end,
        get_num_quest_leader_boards = function(log_index)
            local entry = c.entries[log_index]
            local board = entry and c.boards[entry.quest_id]
            return board and #board or 0
        end,
        get_quest_log_leader_board = function(obj_index, log_index)
            local entry = c.entries[log_index]
            local board = entry and c.boards[entry.quest_id]
            return board and board[obj_index] or nil
        end,
        is_gossip_frame_shown = function() return c.gossip end,
        get_num_trainer_services = function() return c.trainer end,
    }
    c.vendor_item_count = function() return c.vendor end

    function c.accept(quest_id, title)
        c.entries[#c.entries + 1] = { quest_id = quest_id, title = title, is_header = false }
    end

    function c.leave(quest_id)
        for index = #c.entries, 1, -1 do
            if c.entries[index].quest_id == quest_id then table.remove(c.entries, index) end
        end
    end

    return c
end

local function npc_unit(entry_id, name)
    return {
        get_npc_id = function() return entry_id end,
        get_name = function() return name end,
    }
end

--- One play session, replayed at second granularity. Returns the finished campaign graph.
local function record_a_session()
    local client = new_client()
    local bus = EventBus:new()
    local recorder = Recorder:new({ event_bus = bus, now = function() return 0 end })
    local observer = WorldObserver:new(bus, {
        quests = client.quests,
        vendor_item_count = client.vendor_item_count,
    })

    local clock = 0
    local position = { x = -8900, y = -130, z = 83 }
    local target = nil

    --- One frame of the real wiring: SensorHub publishes the player snapshot, then the observer
    --- derives world events from the same tick. Order matters -- a task node's `context.position`
    --- must be where the player was when the task happened.
    local function tick(seconds)
        clock = clock + (seconds or 1)
        bus:publish("player:profile_refreshed", { position = position, map_id = 0 })
        observer:refresh(clock, { position = position, map_id = 0, target = target })
    end

    recorder:start("Northshire")
    tick(0)   -- baseline: an empty log, recorded as nothing

    -- Talk to Deputy Willem and take his quest.
    target = npc_unit(823, "Deputy Willem")
    client.gossip = true
    tick(1)
    client.gossip = false
    client.accept(33, "Wolves Across the Border")
    client.boards[33] = { "Wolves slain: 0/10" }
    bus:publish("game:quest_log_update", {})
    tick(1)

    -- Kill wolves. The counter climbs over several ticks; that is ONE task.
    target = nil
    position = { x = -9100, y = -200, z = 80 }
    for step = 1, 10 do
        client.boards[33] = { "Wolves slain: " .. step .. "/10" }
        bus:publish("game:quest_log_update", {})
        tick(6)
    end

    -- Hand it in to Marshal McBride.
    position = { x = -8912, y = -132, z = 83 }
    target = npc_unit(197, "Marshal McBride")
    client.gossip = true
    tick(1)
    client.gossip = false
    client.leave(33)
    client.flagged[33] = true
    bus:publish("game:quest_log_update", {})
    tick(1)
    tick(1)   -- the departure resolves on a later poll, never at the moment it is observed
    tick(1)

    -- Sell the pelts.
    target = npc_unit(1447, "Innkeeper Farley")
    client.vendor = 20
    tick(2)
    client.vendor = 0

    return recorder:stop(), recorder
end

local function nodes_of(campaign)
    return campaign.graphs[1].nodes
end

local function node_types(campaign)
    local types = {}
    for index, node in ipairs(nodes_of(campaign)) do
        types[index] = node.type
    end
    return types
end

-- ---------------------------------------------------------------------------
-- The pipeline
-- ---------------------------------------------------------------------------

function M.test_a_played_session_becomes_a_campaign_without_any_hand_fed_events()
    local campaign = record_a_session()

    T.assert_not_nil(campaign, "the recording must produce a campaign")
    local types = node_types(campaign)
    T.assert_equal(table.concat(types, ","),
        "questing.AcceptQuest,questing.Kill,questing.TurnIn,questing.Vendor",
        "the session must lower to exactly the four tasks the human performed, in play order")
end

function M.test_the_accept_carries_the_quest_giver()
    local campaign = record_a_session()
    local accept = nodes_of(campaign)[1]

    T.assert_equal(accept.intent.quest.ref, "quest:33", "the AcceptQuest names its quest")
    T.assert_equal(accept.intent.quest.label, "Wolves Across the Border", "the log title survives as the label")
    T.assert_equal(accept.intent.from.ref, "npc:823", "the EntityRef the whole unit exists to produce")
    T.assert_equal(accept.intent.from.label, "Deputy Willem", "and its cached display label")
end

function M.test_ten_kills_collapse_into_one_task_carrying_the_requirement()
    local campaign = record_a_session()
    local kill = nodes_of(campaign)[2]

    T.assert_equal(kill.type, "questing.Kill", "a rising kill counter is a Kill task")
    T.assert_equal(kill.intent.quest.ref, "quest:33", "the Kill belongs to its quest")
    T.assert_equal(kill.intent.count, 10, "ten separate progress observations are one task of count ten")
end

function M.test_the_turn_in_carries_the_receiving_npc()
    local campaign = record_a_session()
    local turn_in = nodes_of(campaign)[3]

    T.assert_equal(turn_in.intent.quest.ref, "quest:33", "the TurnIn names its quest")
    T.assert_equal(turn_in.intent.to.ref, "npc:197", "and the npc it was handed to")
end

function M.test_the_vendor_visit_is_recorded_with_its_npc()
    local campaign = record_a_session()
    local vendor = nodes_of(campaign)[4]

    T.assert_equal(vendor.intent.npc.ref, "npc:1447", "a Vendor task is nothing without its npc")
end

function M.test_tasks_carry_the_position_they_happened_at_as_context_only()
    local campaign = record_a_session()
    local accept = nodes_of(campaign)[1]
    local kill = nodes_of(campaign)[2]

    T.assert_not_nil(accept.context.position, "position rides as recording provenance")
    T.assert_true(math.abs(accept.context.position.x - (-8900)) < 1,
        "the accept was recorded where the quest giver stood")
    T.assert_true(math.abs(kill.context.position.x - (-9100)) < 1,
        "the kill task was recorded out in the field, disambiguating which spawn was used")
    T.assert_nil(accept.intent.position, "position is never part of intent -- intent is what the resolver lowers")
end

function M.test_the_recorded_graph_is_a_linear_chain()
    local campaign = record_a_session()
    local graph = campaign.graphs[1]

    T.assert_equal(#graph.edges, #graph.nodes - 1, "a recorded route is strictly sequential")
    T.assert_equal(graph.entry_node, graph.nodes[1].id, "the entry point is the first thing the human did")
    for index, edge in ipairs(graph.edges) do
        T.assert_equal(edge.from, graph.nodes[index].id, "each edge leaves the node before it")
        T.assert_equal(edge.to, graph.nodes[index + 1].id, "and enters the node after it")
    end
end

function M.test_a_stopped_recorder_stops_costing_the_client_anything()
    local client = new_client()
    local bus = EventBus:new()
    local recorder = Recorder:new({ event_bus = bus })
    local reads = 0
    local counted = { get_num_quest_log_entries = function() reads = reads + 1; return 0 end }
    setmetatable(counted, { __index = client.quests })
    local observer = WorldObserver:new(bus, { quests = counted, vendor_item_count = client.vendor_item_count })

    recorder:start("Northshire")
    observer:refresh(0, { position = { x = 0, y = 0, z = 0 } })
    T.assert_true(reads > 0, "a live recording polls the quest log")

    recorder:stop()
    local after_stop = reads
    for tick = 1, 50 do
        observer:refresh(10 + tick, { position = { x = 0, y = 0, z = 0 } })
    end

    T.assert_equal(reads, after_stop,
        "with no recording subscribed the observer must go silent -- it runs on every character")
end

return M
