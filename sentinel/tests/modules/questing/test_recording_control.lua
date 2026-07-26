-- tests/modules/questing/test_recording_control.lua
-- ADR 09a W12: Recording Mode, owned by a module that actually runs.
--
-- recorder.lua and world_observer.lua were both complete and both tested, and the pipeline was still
-- dead in game: nothing in the tree ever constructed a Recorder, so `_subscribe` never ran, the
-- subscriber-gated observer stayed at zero SDK reads forever, and a human had no way to begin or end
-- a session. This suite pins the missing half -- ownership, lifecycle and persistence on
-- QuestingModule -- against the SHARED bus the app builds.
--
-- The shared-bus point is the one that has already gone wrong once in this tree: runtime_profile.lua
-- carries a constructor note about publishing onto a private bus nothing subscribed to. A Recorder
-- built with `EventBus:new()` of its own would pass every recorder unit test and record nothing,
-- because world_observer publishes onto the app's bus and no other.

local EventBus = require("core/event_bus")
local Blackboard = require("core/blackboard")
local QuestingModule = require("modules/questing/module")
local WorldObserver = require("runtime/sensors/world_observer")
local JSON = require("core/JSON")
local T = require("tests/test_util")

local M = {}

local function new_module()
    local bus = EventBus:new()
    local blackboard = Blackboard:new()
    return QuestingModule:new(blackboard, bus), bus, blackboard
end

local function count_subs(bus, topic)
    local list = bus._subs[topic]
    return list and #list or 0
end

--- A scripted client, the same shape tests/integration/test_recording_pipeline.lua drives, reduced
--- to the reads one accept needs.
local function new_client()
    local c = { entries = {}, gossip = false }
    c.quests = {
        get_num_quest_log_entries = function() return #c.entries end,
        get_quest_log_title = function(index) return c.entries[index] end,
        is_on_quest = function() return true end,
        is_quest_flagged_completed = function() return false end,
        get_num_quest_leader_boards = function() return 0 end,
        get_quest_log_leader_board = function() return nil end,
        is_gossip_frame_shown = function() return c.gossip end,
        get_num_trainer_services = function() return 0 end,
    }
    return c
end

local function npc_unit(entry_id, name)
    return {
        get_npc_id = function() return entry_id end,
        get_name = function() return name end,
    }
end

--- Swap `core.write_data_file` for a recorder, run `fn`, restore. Returns every write it saw.
local function capture_writes(fn)
    local writes = {}
    local saved_write, saved_create = _G.core.write_data_file, _G.core.create_data_file
    _G.core.write_data_file = function(path, content)
        writes[#writes + 1] = { path = path, content = content }
        return true
    end
    _G.core.create_data_file = function() return nil end
    local ok, err = pcall(fn)
    _G.core.write_data_file = saved_write
    _G.core.create_data_file = saved_create
    if not ok then error(err, 0) end
    return writes
end

-- ---------------------------------------------------------------------------
-- Ownership
-- ---------------------------------------------------------------------------

--- The whole unit in one assertion. A Recorder on a bus of its own is indistinguishable from a
--- correct one in every unit test recorder.lua has, and records nothing in game.
function M.test_the_recorder_listens_on_the_shared_bus_not_a_private_one()
    local questing, bus = new_module()
    questing:start_recording("Elwynn")

    bus:publish("game:quest_accepted", { quest_id = 33, quest_name = "Wolves Across the Border" })

    local campaign = questing:get_recording()
    T.assert_not_nil(campaign, "starting a recording must produce a campaign")
    T.assert_equal(#campaign.graphs[1].nodes, 1,
        "an event published on the APP's bus must reach the module's recorder")
end

function M.test_nothing_is_recorded_before_start_is_called()
    local questing, bus = new_module()

    bus:publish("game:quest_accepted", { quest_id = 33, quest_name = "Wolves Across the Border" })
    bus:publish("game:vendor_used", { npc_id = 1447 })

    local status = questing:recording_status()
    T.assert_false(status.recording, "a freshly constructed module must not be recording")
    T.assert_nil(questing:get_recording(),
        "recording must never start on its own -- an unasked-for recording is a file the operator "
        .. "did not consent to and a poll cost every character pays")
end

-- ---------------------------------------------------------------------------
-- Lifecycle and the subscriber gate
-- ---------------------------------------------------------------------------

--- world_observer.lua gates every SDK read on having a subscriber. That gate is only worth anything
--- if stopping actually removes the subscriptions -- otherwise the ~85 calls of a quest-log walk run
--- forever on a character that is not recording.
function M.test_starting_subscribes_and_stopping_lets_the_observer_go_idle_again()
    local questing, bus = new_module()
    local reads = 0
    local observer = WorldObserver:new(bus, {
        quests = { get_num_quest_log_entries = function() reads = reads + 1; return 0 end },
        vendor_item_count = function() return 0 end,
    })

    observer:refresh(0, { position = { x = 0, y = 0, z = 0 } })
    T.assert_equal(reads, 0, "with no recording the observer must cost the client nothing")

    questing:start_recording("Elwynn")
    observer:refresh(1, { position = { x = 0, y = 0, z = 0 } })
    T.assert_true(reads > 0, "a live recording must wake the observer")

    questing:stop_recording()
    local after_stop = reads
    for tick = 1, 20 do
        observer:refresh(10 + tick, { position = { x = 0, y = 0, z = 0 } })
    end
    T.assert_equal(reads, after_stop,
        "stopping must unsubscribe: the observer runs on every character, recording or not")
end

--- Tick is where a leak would accumulate 60 times a second. The recorder is driven entirely by bus
--- subscriptions, so tick must neither re-subscribe nor tear the recording down.
function M.test_a_module_tick_neither_ends_the_recording_nor_leaks_subscriptions()
    local questing, bus = new_module()
    questing:start_recording("Elwynn")
    local subscribed = count_subs(bus, "game:quest_accepted")
    T.assert_equal(subscribed, 1, "one recording, one subscription per topic")

    for _ = 1, 30 do questing:tick(0.016) end

    T.assert_equal(count_subs(bus, "game:quest_accepted"), subscribed,
        "a tick must not re-subscribe -- duplicate handlers record every event twice")
    T.assert_true(questing:recording_status().recording, "and must not end the session")
end

--- Restarting silently would drop a played session on the floor. `Recorder:start` does exactly that
--- by design (it stops first), so the guard has to live here, at the operator-facing verb.
function M.test_starting_twice_refuses_rather_than_discarding_the_session_in_progress()
    local questing, bus = new_module()
    questing:start_recording("Elwynn")
    bus:publish("game:quest_accepted", { quest_id = 33 })

    local result = questing:start_recording("Westfall")

    T.assert_false(result.ok, "a second start must not silently replace the first")
    T.assert_true(type(result.reason) == "string" and result.reason ~= "",
        "and must say why, not just answer false")
    T.assert_equal(#questing:get_recording().graphs[1].nodes, 1,
        "the session already recorded must survive the refusal")
end

function M.test_stopping_without_a_recording_reports_a_reason()
    local questing = new_module()
    local result = questing:stop_recording()

    T.assert_false(result.ok, "there was nothing to stop")
    T.assert_true(type(result.reason) == "string" and result.reason ~= "",
        "an operator driving this from outside the client needs the reason, not a bare false")
end

function M.test_status_reports_the_session_a_human_needs_to_see()
    local questing, bus = new_module()
    T.assert_false(questing:recording_status().recording, "idle before start")

    questing:start_recording("Northshire")
    bus:publish("game:quest_accepted", { quest_id = 33 })
    bus:publish("game:vendor_used", { npc_id = 1447 })

    local status = questing:recording_status()
    T.assert_true(status.recording, "status must report a live recording")
    T.assert_equal(status.name, "Northshire", "under the name the operator gave it")
    T.assert_equal(status.nodes, 2, "and how much has been captured so far")
end

--- Module teardown must release the gate too. A shutdown that left the subscriptions in place would
--- keep the observer polling against a recorder nobody can reach any more.
function M.test_shutdown_ends_an_open_recording()
    local questing, bus = new_module()
    questing:start_recording("Elwynn")
    questing:shutdown()

    T.assert_equal(count_subs(bus, "game:quest_accepted"), 0,
        "shutdown must release the observer's subscriber gate")
    T.assert_false(questing:recording_status().recording, "and report the recording as ended")
end

-- ---------------------------------------------------------------------------
-- The real producer, through the real bus
-- ---------------------------------------------------------------------------

--- Nothing here calls `Recorder:observe`. The only inputs are a scripted client and the module's own
--- verbs, so this is the first test in the tree that would fail if the module owned no recorder.
function M.test_a_played_session_reaches_the_modules_recorder_through_the_real_wiring()
    local questing, bus = new_module()
    local client = new_client()
    local observer = WorldObserver:new(bus, {
        quests = client.quests,
        vendor_item_count = function() return 0 end,
    })

    local position = { x = -8900, y = -130, z = 83 }
    local clock, target = 0, nil
    local function tick(seconds)
        clock = clock + (seconds or 1)
        -- The order SensorHub:refresh uses: the player snapshot first, then the world derivation, so
        -- a task node is stamped with the position it was recorded at.
        bus:publish("player:profile_refreshed", { position = position, map_id = 0 })
        observer:refresh(clock, { position = position, map_id = 0, target = target })
    end

    questing:start_recording("Northshire")
    tick(0)

    target = npc_unit(823, "Deputy Willem")
    client.gossip = true
    tick(1)
    client.gossip = false
    client.entries[1] = { quest_id = 33, title = "Wolves Across the Border", is_header = false }
    bus:publish("game:quest_log_update", {})
    tick(1)

    local result = questing:stop_recording()
    T.assert_true(result.ok, "the recording must stop cleanly")

    local nodes = result.campaign.graphs[1].nodes
    T.assert_equal(#nodes, 1, "one accept, one task")
    T.assert_equal(nodes[1].type, "questing.AcceptQuest", "and it is the accept the human performed")
    T.assert_equal(nodes[1].intent.quest.ref, "quest:33", "carrying the quest")
    T.assert_equal(nodes[1].intent.from.ref, "npc:823", "and the giver the observer attributed")
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function M.test_save_writes_resolver_readable_json_through_the_sandbox_file_api()
    local questing, bus = new_module()
    questing:start_recording("Northshire")
    bus:publish("game:quest_accepted", { quest_id = 33, quest_name = "Wolves Across the Border" })

    local result
    local writes = capture_writes(function()
        result = questing:save_recording()
    end)

    T.assert_true(result.ok, "a recording with content must save")
    T.assert_equal(#writes, 1, "exactly one write, through core.write_data_file")
    T.assert_equal(writes[1].path, result.path, "the reported path must be the one written")
    T.assert_true(writes[1].path:find("recordings", 1, true) ~= nil,
        "recordings land in their own folder a human can find: " .. tostring(writes[1].path))
    T.assert_true(writes[1].path:sub(-5) == ".json", "and are JSON on disk")

    local decoded = JSON.decode(writes[1].content)
    T.assert_not_nil(decoded, "what was written must parse as JSON")
    T.assert_equal(decoded.schema_version, 3, "the resolver dispatches on the schema version")
    T.assert_equal(decoded.name, "Northshire", "the campaign keeps the operator's name")
    T.assert_equal(#decoded.graphs[1].nodes, 1, "and the tasks survive the round trip")
    T.assert_equal(decoded.graphs[1].nodes[1].type, "questing.AcceptQuest",
        "with the node type sentinel-resolver lowers")
end

function M.test_save_accepts_an_explicit_path()
    local questing, bus = new_module()
    questing:start_recording("Northshire")
    bus:publish("game:quest_accepted", { quest_id = 33 })

    local result
    local writes = capture_writes(function()
        result = questing:save_recording("sentinel/data/recordings/custom.json")
    end)

    T.assert_true(result.ok, "an explicit path must be honoured")
    T.assert_equal(writes[1].path, "sentinel/data/recordings/custom.json", "verbatim")
end

function M.test_saving_without_a_recording_reports_a_reason_and_writes_nothing()
    local questing = new_module()

    local result
    local writes = capture_writes(function()
        result = questing:save_recording()
    end)

    T.assert_false(result.ok, "there is nothing to save")
    T.assert_true(type(result.reason) == "string" and result.reason ~= "",
        "and the operator is told why")
    T.assert_equal(#writes, 0, "an empty save must not create a file")
end

--- Stop leaves the campaign readable on purpose, so the operator can inspect it and only then
--- commit it to disk. A save that only worked while recording would force the human to keep the
--- observer polling while they decide.
function M.test_a_stopped_recording_is_still_savable()
    local questing, bus = new_module()
    questing:start_recording("Northshire")
    bus:publish("game:quest_accepted", { quest_id = 33 })
    questing:stop_recording()

    local result
    local writes = capture_writes(function()
        result = questing:save_recording()
    end)

    T.assert_true(result.ok, "a finished session must still be savable")
    T.assert_equal(#writes, 1, "and reach the disk")
end

return M
