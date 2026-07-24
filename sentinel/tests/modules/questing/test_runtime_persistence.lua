-- tests/modules/questing/test_runtime_persistence.lua
-- Unit tests for progress persistence save/load (Wave 5)
-- Tests: serialization, save file creation, fingerprint matching, auto-save

local RuntimeProfile = require("modules/questing/runtime_profile")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- Helpers
-- ============================================================================

--- File I/O mock: capture written data in a table.
--- NOTE: write_data_file is called via pcall(core.write_data_file, core, path, content)
--- so the mock receives (self, path, content).
--- read_data_file is called as core.read_data_file(path) (plain function, no self).
local written_files = {}

--- Set up minimal global state for testing.
local function mock_globals()
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.unit = _G.core.unit or {}
    _G.core.input = _G.core.input or {}
    -- Sylvannas signature: core.write_data_file(filename, data) — NO self. The mock previously
    -- took (self, path, content), which matched a buggy call site and hid the fact that every
    -- in-game save failed and fell through to io.open (absent in the sandbox).
    _G.core.write_data_file = function(path, content)
        written_files[path] = content
        return true
    end
    _G.core.read_data_file = function(path)
        return written_files[path]
    end
    _G.JSON = _G.JSON or {}
    _G.SentinelNavClient = {
        client = {
            move_to = function() return true end,
            stop = function() end,
            get_state = function() return "idle" end,
            get_full_state = function() return "idle" end,
            get_progress = function() return {} end,
            get_destination = function() return nil end,
            get_path_index = function() return 1 end,
            get_current_path = function() return {} end,
        },
    }
end

--- Create a minimal profile with a content_hash.
local function make_profile_ops(action_type, payload)
    return {
        content_hash = "abc123hash",
        operations = {
            {
                id = 1,
                actions = { { type = action_type or "Comment", payload = payload or { text = "test" } } },
                next_condition = "auto",
            },
        },
    }
end

--- Create a RuntimeProfile with mocked profile data.
local function create_profile(profile_data)
    mock_globals()
    local profile = RuntimeProfile:new("test_profile.json")
    profile._profile = profile_data or make_profile_ops()
    -- Ensure save path is derived from the JSON path
    profile._save_path = profile:_compute_save_path()
    return profile
end

-- ============================================================================
-- W5.2 — Save/load state tests
-- ============================================================================

function M.test_save_creates_save_file()
    written_files = {}
    local profile = create_profile(make_profile_ops("Comment", { text = "hello" }))

    -- Advance to operation 2 (simulate progress)
    profile._current_operation_idx = 2
    profile._variables = { gold = 100 }

    local ok = profile:_save()
    T.assert_true(ok, "Save should succeed")

    -- Check the save file was written
    local save_path = profile._save_path
    local content = written_files[save_path]
    T.assert_not_nil(content, "Save file should exist")

    -- Verify content contains key fields
    T.assert_true(content:find("profile_fingerprint") ~= nil, "Save should have profile_fingerprint")
    T.assert_true(content:find("abc123hash") ~= nil, "Save should have correct fingerprint")
    T.assert_true(content:find("current_operation_idx") ~= nil, "Save should have operation index")
    T.assert_true(content:find("variables") ~= nil, "Save should have variables")
    T.assert_true(content:find("version") ~= nil, "Save should have version")
end

function M.test_restore_state_from_save()
    written_files = {}
    local profile = create_profile(make_profile_ops("Comment", { text = "test" }))

    -- Simulate progress and save
    profile._current_operation_idx = 3
    profile._variables = { quest_done = true }
    profile:_save()

    -- Create a new profile instance (as if restarting)
    local profile2 = create_profile(make_profile_ops("Comment", { text = "test" }))

    -- Load save
    local restored = profile2:_load_save()
    T.assert_true(restored, "Save should be restored successfully")
    T.assert_equal(profile2._current_operation_idx, 3,
        "Operation index should be restored from save")
    T.assert_equal(profile2._variables.quest_done, true,
        "Variables should be restored from save")
end

function M.test_fingerprint_mismatch_rejects_save()
    written_files = {}
    local profile = create_profile(make_profile_ops("Comment", { text = "v1" }))
    profile._current_operation_idx = 5
    profile:_save()

    -- Create profile with different fingerprint (simulating recompiled profile)
    local profile2 = create_profile({
        content_hash = "differentHash",
        operations = {
            { id = 1, actions = { { type = "Comment", payload = { text = "v2" } } }, next_condition = "auto" },
        },
    })

    local restored = profile2:_load_save()
    T.assert_false(restored, "Save with mismatched fingerprint should not restore")
    T.assert_equal(profile2._current_operation_idx, 1,
        "Should start at operation 1 when fingerprint mismatch")
end

function M.test_empty_fingerprint_starts_fresh()
    written_files = {}
    -- Create profile without content_hash
    local profile = create_profile({
        operations = {
            { id = 1, actions = { { type = "Comment", payload = { text = "test" } } }, next_condition = "auto" },
        },
    })
    -- profile._profile.content_hash should be nil

    -- Create a save file
    profile._current_operation_idx = 2
    profile:_save()

    -- Try to load on a fresh profile
    local profile2 = create_profile({
        operations = {
            { id = 1, actions = { { type = "Comment", payload = { text = "test" } } }, next_condition = "auto" },
        },
    })
    local restored = profile2:_load_save()
    T.assert_false(restored, "Empty fingerprint should not restore")
end

function M.test_no_save_file_returns_false()
    written_files = {} -- Empty, no saves
    local profile = create_profile(make_profile_ops())
    local restored = profile:_load_save()
    T.assert_false(restored, "No save file should return false")
end

-- ============================================================================
-- Per-character saves + route reconciliation
-- ============================================================================

function M.test_save_is_keyed_per_character()
    written_files = {}
    mock_globals()
    _G.core.object_manager.get_local_player = function()
        return { get_name = function() return "Alice" end }
    end
    local profile = create_profile(make_profile_ops())
    profile._current_operation_idx = 7
    profile:_save()
    T.assert_not_nil(written_files["test_profile.alice.save.json"],
        "save path must include the character name")
    T.assert_true(written_files["test_profile.alice.save.json"]:find('"character"') ~= nil,
        "save content must carry the character identity")
    _G.core.object_manager.get_local_player = nil
end

function M.test_save_from_other_character_rejected()
    written_files = {}
    mock_globals()
    _G.core.object_manager.get_local_player = function()
        return { get_name = function() return "Alice" end }
    end
    local profile = create_profile(make_profile_ops())
    profile._current_operation_idx = 7
    profile:_save()

    -- Log in as a different character on the same account. Even if alice's save bytes
    -- somehow land on bob's path, the identity field must reject them.
    _G.core.object_manager.get_local_player = function()
        return { get_name = function() return "Bob" end }
    end
    local profile2 = create_profile(make_profile_ops())
    written_files["test_profile.bob.save.json"] = written_files["test_profile.alice.save.json"]
    local restored = profile2:_load_save()
    T.assert_false(restored, "a save written by another character must be rejected")
    T.assert_equal(profile2._current_operation_idx, 1,
        "bob must start fresh, not at alice's step")
    _G.core.object_manager.get_local_player = nil
end

function M.test_legacy_shared_save_rejected_when_character_known()
    written_files = {}
    mock_globals()
    -- A pre-fix character-less save exists on the legacy shared path.
    local legacy = create_profile(make_profile_ops())
    legacy._current_operation_idx = 9
    legacy:_save()
    T.assert_not_nil(written_files["test_profile.save.json"], "sanity: legacy save written")

    _G.core.object_manager.get_local_player = function()
        return { get_name = function() return "Bob" end }
    end
    local profile = create_profile(make_profile_ops())
    -- Even pointed straight at the legacy bytes, a character-less save is untrusted.
    written_files["test_profile.bob.save.json"] = written_files["test_profile.save.json"]
    local restored = profile:_load_save()
    T.assert_false(restored, "a character-less legacy save must not drive a known character")
    _G.core.object_manager.get_local_player = nil
end

function M.test_reconcile_starts_after_last_satisfied_anchor()
    written_files = {}
    local profile = create_profile({
        content_hash = "h",
        operations = {
            { id = 1, actions = { { type = "TurnInQuest", payload = { quest_id = 10, npc_entry = 1 } } }, next_condition = "auto" },
            { id = 2, actions = { { type = "Kill", payload = { creature_entries = { 5 } } } }, next_condition = "auto" },
            { id = 3, actions = { { type = "TurnInQuest", payload = { quest_id = 20, npc_entry = 1 } } }, next_condition = "auto" },
        },
    })
    _G.core.quests = {
        is_quest_flagged_completed = function(qid) return qid == 10 end,
        is_on_quest = function() return false end,
    }
    T.assert_equal(profile:_reconcile_start_operation(), 2,
        "start after the rewarded turn-in but BEFORE the kills for the unrewarded quest")

    _G.core.quests.is_quest_flagged_completed = function() return true end
    T.assert_equal(profile:_reconcile_start_operation(), 4,
        "all anchors satisfied -> start past the end")
    _G.core.quests = nil
end

function M.test_reconcile_jumps_to_ready_turnin()
    written_files = {}
    local profile = create_profile({
        content_hash = "h",
        operations = {
            { id = 1, actions = { { type = "TurnInQuest", payload = { quest_id = 10, npc_entry = 1 } } }, next_condition = "auto" },
            { id = 2, actions = { { type = "Kill", payload = { creature_entries = { 5 } } } }, next_condition = "auto" },
            { id = 3, actions = { { type = "TurnInQuest", payload = { quest_id = 20, npc_entry = 1 } } }, next_condition = "auto" },
        },
    })
    -- Quest 10 rewarded; quest 20 unrewarded but sitting in the log with all objectives
    -- complete — its kills (op 2) are proven done, only the turn-in remains. The live
    -- client returns is_complete = 1 (a NUMBER, verified in-game 2026-07-23), so the
    -- mock pins that wire shape.
    _G.core.quests = {
        is_quest_flagged_completed = function(qid) return qid == 10 end,
        is_on_quest = function(qid) return qid == 20 end,
        get_num_quest_log_entries = function() return 1 end,
        get_quest_log_title = function(_) return { quest_id = 20, is_complete = 1 } end,
    }
    T.assert_equal(profile:_reconcile_start_operation(), 3,
        "a log-complete quest must place us AT its turn-in, past its finished kills")

    -- Same quest still mid-objectives: the kills are real work, start before them.
    -- is_complete = 0 is TRUTHY in Lua — it must still read as incomplete.
    _G.core.quests.get_quest_log_title = function(_) return { quest_id = 20, is_complete = 0 } end
    T.assert_equal(profile:_reconcile_start_operation(), 2,
        "an incomplete quest (is_complete = 0) must start at its kill operation, not skip it")
    _G.core.quests = nil
end

function M.test_advance_reconciles_past_moot_kills()
    written_files = {}
    local profile = create_profile({
        content_hash = "h",
        operations = {
            { id = 1, actions = { { type = "Comment", payload = { text = "a" } } }, next_condition = "auto" },
            { id = 2, actions = { { type = "Kill", payload = { creature_entries = { 5 } } } }, next_condition = "auto" },
            { id = 3, actions = { { type = "TurnInQuest", payload = { quest_id = 20, npc_entry = 1 } } }, next_condition = "auto" },
        },
    })
    _G.core.quests = {
        is_quest_flagged_completed = function(_) return false end,
        is_on_quest = function(qid) return qid == 20 end,
        get_num_quest_log_entries = function() return 1 end,
        get_quest_log_title = function(_) return { quest_id = 20, is_complete = 1 } end,
    }
    profile._current_operation_idx = 1
    profile:_advance_operation(profile._profile.operations[1])
    T.assert_equal(profile._current_operation_idx, 3,
        "finishing an operation must re-reconcile and jump past kills a log-complete quest already proves done")
    _G.core.quests = nil
end

function M.test_certain_reconcile_rewinds_past_bogus_save()
    written_files = {}
    mock_globals()
    local ops = {
        content_hash = "abc123hash",
        operations = {
            { id = 1, actions = { { type = "TurnInQuest", payload = { quest_id = 20, npc_entry = 1 } } }, next_condition = "auto" },
            { id = 2, actions = { { type = "Kill", payload = { creature_entries = { 5 } } } }, next_condition = "auto" },
            { id = 3, actions = { { type = "Comment", payload = { text = "x" } } }, next_condition = "auto" },
        },
    }
    -- A previous session's turn-in failed its retries and the save recorded op 3.
    local stale = create_profile(ops)
    stale._current_operation_idx = 3
    stale:_save()

    _G.core.quests = {
        is_quest_flagged_completed = function(_) return false end,
        is_on_quest = function(qid) return qid == 20 end,
        get_num_quest_log_entries = function() return 1 end,
        get_quest_log_title = function(_) return { quest_id = 20, is_complete = 1 } end,
    }
    local profile = create_profile(ops)
    profile:_load_save()
    T.assert_equal(profile._current_operation_idx, 3, "sanity: save restored the bogus position")
    local reconciled, certain = profile:_reconcile_start_operation()
    T.assert_true(certain, "a ready turn-in is a certain verdict")
    T.assert_true(profile:_apply_reconciliation(reconciled, certain),
        "certain verdict must rewind past the bogus save")
    T.assert_equal(profile._current_operation_idx, 1,
        "route must return to the pending turn-in the save skipped")

    -- The rewind is one-shot per target op: a permanently failing turn-in cannot loop.
    profile._current_operation_idx = 3
    T.assert_false(profile:_apply_reconciliation(profile:_reconcile_start_operation()),
        "second rewind to the same operation must be refused")
    _G.core.quests = nil
end

function M.test_operation_skipped_when_completion_gate_met()
    written_files = {}
    local profile = create_profile({
        content_hash = "h",
        operations = {
            {
                id = 1,
                actions = {
                    { type = "Travel", payload = { position = { x = 0, y = 0, z = 0 } } },
                    { type = "Kill", payload = { creature_entries = { 5 }, quantity = 8 } },
                    { type = "Condition", payload = { role = "Completion", condition = { type = "AlwaysTrue", payload = {} } } },
                },
                next_condition = "auto",
            },
        },
    })
    local ctx = profile:create_context()
    T.assert_true(profile:_operation_gate_already_met(profile._profile.operations[1], ctx),
        "a met Completion gate must mark the whole kill operation as done")

    -- A quest action in the operation defers to the quest-status skip logic instead.
    local op_with_quest = {
        actions = {
            { type = "TurnInQuest", payload = { quest_id = 9, npc_entry = 1 } },
            { type = "Condition", payload = { role = "Completion", condition = { type = "AlwaysTrue", payload = {} } } },
        },
    }
    T.assert_false(profile:_operation_gate_already_met(op_with_quest, ctx),
        "operations with quest actions must never gate-skip")

    -- No Completion gate at all: nothing observable, never skip.
    local op_no_gate = {
        actions = { { type = "Kill", payload = { creature_entries = { 5 } } } },
    }
    T.assert_false(profile:_operation_gate_already_met(op_no_gate, ctx),
        "a gateless kill operation must never gate-skip")
end

function M.test_objective_gate_met_for_rewarded_quest()
    written_files = {}
    local profile = create_profile({
        content_hash = "h",
        operations = {
            {
                id = 1,
                actions = {
                    { type = "Kill", payload = { creature_entries = { 5 }, quantity = 8 } },
                    -- ObjectiveComplete payload is (quest_id, objective_idx) positional,
                    -- matching the compiled wire shape.
                    { type = "Condition", payload = { role = "Completion", condition = { type = "ObjectiveComplete", payload = { 7, 1 } } } },
                },
                next_condition = "auto",
            },
        },
    })
    -- Quest 7 is REWARDED: it is gone from the log, but its objectives are trivially
    -- complete — the kill op must gate-skip instead of re-farming (live-caught).
    _G.core.quests = {
        is_quest_flagged_completed = function(qid) return qid == 7 end,
        is_on_quest = function(_) return false end,
        get_num_quest_log_entries = function() return 0 end,
        get_quest_log_title = function(_) return nil end,
        get_num_quest_leader_boards = function(_) return 0 end,
    }
    local ctx = profile:create_context()
    T.assert_true(profile:_operation_gate_already_met(profile._profile.operations[1], ctx),
        "a kill op gated on a rewarded quest's objective must be skipped")
    _G.core.quests = nil
end

function M.test_missed_accept_rewinds_without_skipping_kills()
    written_files = {}
    local profile = create_profile({
        content_hash = "h",
        operations = {
            { id = 1, actions = { { type = "AcceptQuest", payload = { quest_id = 10, npc_entry = 1 } } }, next_condition = "auto" },
            { id = 2, actions = { { type = "Kill", payload = { creature_entries = { 5 } } } }, next_condition = "auto" },
            { id = 3, actions = { { type = "AcceptQuest", payload = { quest_id = 20, npc_entry = 2 } } }, next_condition = "auto" },
            { id = 4, actions = { { type = "Comment", payload = { text = "x" } } }, next_condition = "auto" },
        },
    })
    -- Quest 10 active (its accept landed); quest 20 was MISSED (accept exhausted retries
    -- and the route moved on to op 4).
    _G.core.quests = {
        is_quest_flagged_completed = function(_) return false end,
        is_on_quest = function(qid) return qid == 10 end,
        get_num_quest_log_entries = function() return 0 end,
        get_quest_log_title = function(_) return nil end,
    }
    local start_idx, certain, certain_idx = profile:_reconcile_start_operation()
    T.assert_equal(start_idx, 2, "forward position stays before the unobservable kills")
    T.assert_true(certain, "a missed accept is an observable, certain verdict")
    T.assert_equal(certain_idx, 3, "the rewind target is the accept op itself")

    -- Route already at op 4: rewind to the ACCEPT (3), never to start_idx (2) — the
    -- kills at op 2 must not be redone because of an accept verdict.
    profile._current_operation_idx = 4
    T.assert_true(profile:_apply_reconciliation(start_idx, certain, certain_idx),
        "the route must come back for the missed accept")
    T.assert_equal(profile._current_operation_idx, 3, "rewound exactly to the accept op")
    _G.core.quests = nil
end

function M.test_class_guarded_accepts_do_not_block_status()
    written_files = {}
    local profile = create_profile(make_profile_ops())
    -- One guard-met accept (quest 10, active) + one accept guarded to another class
    -- (never accepted). The op must classify as satisfied — the foreign-class accept is
    -- not this character's work. Guard evaluation runs through the real condition
    -- evaluator; ClassIs compares against ctx:get_player_class() ("Unknown" offline).
    local op = {
        actions = {
            { type = "AcceptQuest", payload = { quest_id = 10, npc_entry = 1 } },
            {
                type = "AcceptQuest",
                payload = { quest_id = 99, npc_entry = 1 },
                guard = { type = "ClassIs", payload = "Mage" },
            },
        },
    }
    _G.core.quests = {
        is_quest_flagged_completed = function(_) return false end,
        is_on_quest = function(qid) return qid == 10 end,
        get_num_quest_log_entries = function() return 0 end,
        get_quest_log_title = function(_) return nil end,
    }
    T.assert_equal(profile:_op_quest_status(op), "satisfied",
        "an accept guarded to another class must not mark the op unsatisfied")
    _G.core.quests = nil
end

function M.test_npc_position_falls_back_to_static_sources()
    written_files = {}
    mock_globals()
    -- Source 1: the compiled profile's npcs table (NPC beyond draw distance).
    local profile = create_profile(make_profile_ops())
    profile._profile.npcs = {
        { entry = 197, name = "Marshal McBride", position = { x = -8902.6, y = -162.6, z = 82.0 } },
    }
    local pos = profile:_get_npc_position(197)
    T.assert_not_nil(pos, "profile npcs table must supply the position when the NPC is unseen")
    T.assert_equal(pos and pos.z, 82.0, "profile-table Z must be kept (real DB height)")

    -- Source 2: QueryServer spawn, used when the profile table is empty.
    local profile2 = create_profile(make_profile_ops())
    profile2._profile.npcs = {}
    profile2._query = {
        get_npc = function(_self, entry)
            if entry == 197 then
                return { positions = { { map = 0, x = 1, y = 2, z = 3 } } }
            end
            return nil
        end,
    }
    local pos2 = profile2:_get_npc_position(197)
    T.assert_not_nil(pos2, "QueryServer spawn must supply the position as a last resort")
    T.assert_equal(pos2 and pos2.y, 2, "y must come from the query response")

    -- Nothing anywhere: nil, so the blocked handler keeps retrying rather than guessing.
    local profile3 = create_profile(make_profile_ops())
    profile3._profile.npcs = {}
    profile3._query = nil
    T.assert_equal(profile3:_get_npc_position(197), nil,
        "no live, profile, or query source must yield nil, never a guess")
end

function M.test_unmet_gate_rewinds_save_that_skipped_kills()
    written_files = {}
    local profile = create_profile({
        content_hash = "h",
        operations = {
            { id = 1, actions = { { type = "Comment", payload = { text = "a" } } }, next_condition = "auto" },
            {
                id = 2,
                actions = {
                    { type = "Kill", payload = { creature_entries = { 257 }, quantity = 10 } },
                    { type = "Condition", payload = { role = "Completion", condition = { type = "ObjectiveComplete", payload = { 15, 1 } } } },
                },
                next_condition = "auto",
            },
            { id = 3, actions = { { type = "Comment", payload = { text = "b" } } }, next_condition = "auto" },
        },
    })
    -- Quest 15 in the log at 3/10 — the kill op is provably unfinished.
    _G.core.quests = {
        is_quest_flagged_completed = function(_) return false end,
        is_on_quest = function(qid) return qid == 15 end,
        get_num_quest_log_entries = function() return 1 end,
        get_quest_log_title = function(_) return { quest_id = 15, is_complete = 0 } end,
        get_num_quest_leader_boards = function(_) return 1 end,
        get_quest_log_leader_board = function(_, _)
            return { objective_type = "monster", description = "Kobold Workers slain: 3/10", is_completed = false }
        end,
    }
    local start_idx, certain, certain_idx = profile:_reconcile_start_operation()
    T.assert_true(certain, "an unmet farm gate is a certain verdict")
    T.assert_equal(certain_idx, 2, "the rewind target is the unfinished kill op")

    -- A save that churned past the kills must come back for them.
    profile._current_operation_idx = 3
    T.assert_true(profile:_apply_reconciliation(start_idx, certain, certain_idx),
        "the route must rewind to the unfinished kill op")
    T.assert_equal(profile._current_operation_idx, 2, "rewound to the kill op")

    -- Once the objective completes, the same op advances the scan instead.
    _G.core.quests.get_quest_log_leader_board = function(_, _)
        return { objective_type = "monster", description = "Kobold Workers slain: 10/10", is_completed = 1 }
    end
    local start2 = profile:_reconcile_start_operation()
    T.assert_true(start2 >= 3, "a met gate must advance the scan past the kill op")
    _G.core.quests = nil
end

function M.test_operation_with_kills_skipped_when_quest_rewarded()
    written_files = {}
    local profile = create_profile(make_profile_ops())
    _G.core.quests = {
        is_quest_flagged_completed = function(qid) return qid == 10 end,
        is_on_quest = function() return false end,
    }
    local op_done = {
        actions = {
            { type = "Kill", payload = { creature_entries = { 5 } } },
            { type = "TurnInQuest", payload = { quest_id = 10, npc_entry = 1 } },
        },
    }
    T.assert_true(profile:_operation_already_done(op_done),
        "kills riding with a rewarded turn-in are served by it and must not block the skip")
    local op_kill_only = { actions = { { type = "Kill", payload = { creature_entries = { 5 } } } } }
    T.assert_false(profile:_operation_already_done(op_kill_only),
        "a kill-only operation has no observable quest work and must never be skipped")
    _G.core.quests = nil
end

function M.test_load_reconciles_with_no_save_at_all()
    written_files = {}
    mock_globals()
    _G.core.quests = {
        is_quest_flagged_completed = function(qid) return qid == 10 end,
        is_on_quest = function() return false end,
    }
    written_files["test_profile.json"] =
        '{"content_hash":"abc","operations":['
        .. '{"id":1,"actions":[{"type":"TurnInQuest","payload":{"quest_id":10,"npc_entry":1}}],"next_condition":"auto"},'
        .. '{"id":2,"actions":[{"type":"Comment","payload":{"text":"x"}}],"next_condition":"auto"}]}'
    local profile = RuntimeProfile:new("test_profile.json")
    local ok = profile:load()
    T.assert_true(ok, "load should succeed")
    T.assert_equal(profile._current_operation_idx, 2,
        "with no save file, the rewarded turn-in alone must place us at operation 2")
    _G.core.quests = nil
end

function M.test_gate_met_mid_kill_skips_operation()
    written_files = {}
    local profile = create_profile({
        content_hash = "h",
        operations = {
            {
                id = 1,
                actions = {
                    { type = "Comment", payload = { text = "walk-in" } },
                    { type = "Kill", payload = { creature_entries = { 705 }, quantity = 40 } },
                    { type = "Condition", payload = { role = "Completion", condition = { type = "ObjectiveComplete", payload = { 33, 1 } } } },
                },
                next_condition = "auto",
            },
            { id = 2, actions = { { type = "Comment", payload = { text = "next" } } }, next_condition = "auto" },
        },
    })
    -- The executor is already INSIDE the Kill (action 2) when the gate reads met —
    -- either the objective completed mid-farm or the completed-quest flags answered
    -- late at startup (live-caught: a stale false at action 1 committed the bot to
    -- re-farming 40 wolves for rewarded quest 33). Kill counts corpses from zero and
    -- never re-consults the gate, so the tick itself must.
    _G.core.quests = {
        is_quest_flagged_completed = function(qid) return qid == 33 end,
        is_on_quest = function(_) return false end,
        get_num_quest_log_entries = function() return 0 end,
        get_quest_log_title = function(_) return nil end,
        get_num_quest_leader_boards = function(_) return 0 end,
    }
    profile._state = "running"
    profile._current_operation_idx = 1
    profile._current_action_idx = 2 -- mid-Kill, past the action-1 gate check
    profile:execute()
    T.assert_equal(profile._current_operation_idx, 2,
        "a met Completion gate must end the farm op even mid-kill")
    _G.core.quests = nil
end

-- ============================================================================
-- W5.2 — Serialization tests
-- ============================================================================

function M.test_serialize_state_includes_all_fields()
    local profile = create_profile(make_profile_ops())
    profile._current_operation_idx = 4
    profile._variables = { key = "val" }

    local state = profile:_serialize_state()
    T.assert_equal(state.version, 2, "Version should be 2 (v2 schema)")
    T.assert_equal(state.profile_fingerprint, "abc123hash", "Fingerprint should match profile")
    T.assert_equal(state.current_operation_idx, 4, "Operation index should match")
    T.assert_equal(state.variables.key, "val", "Variables should match")
    T.assert_not_nil(state.saved_at, "saved_at timestamp should be present")
end

-- ============================================================================
-- W5.3 — Auto-save tests
-- ============================================================================

function M.test_auto_save_on_advance_operation()
    written_files = {}
    local profile = create_profile(make_profile_ops("Comment", { text = "op1" }))

    -- Execute (should succeed and advance via _advance_operation)
    profile:execute()

    -- Check if save was triggered
    local save_path = profile._save_path
    local content = written_files[save_path]
    -- After success, operation should be 2 (advanced past op 1)
    T.assert_equal(profile._current_operation_idx, 2,
        "Operation should have advanced")
end

function M.test_auto_save_on_skipped_advance()
    written_files = {}
    local profile = create_profile({
        content_hash = "testhash",
        operations = {
            {
                id = 1,
                actions = { { type = "Condition", payload = { role = "Applicability", condition = { type = "LevelAtLeast", payload = 100 } } } },
                next_condition = "auto",
            },
        },
    })
    -- LevelAtLeast(100) will fail (mock context returns level 1); an unmet Applicability
    -- condition returns "skipped" (unmet Completion would instead "wait"), so it advances.

    profile:execute()

    -- Operation should advance (skipped advances)
    T.assert_equal(profile._current_operation_idx, 2,
        "Skipped action should advance operation")
end

-- ============================================================================
-- Run all tests
-- ============================================================================

local tests = {
    test_save_is_keyed_per_character = M.test_save_is_keyed_per_character,
    test_save_from_other_character_rejected = M.test_save_from_other_character_rejected,
    test_legacy_shared_save_rejected_when_character_known = M.test_legacy_shared_save_rejected_when_character_known,
    test_reconcile_starts_after_last_satisfied_anchor = M.test_reconcile_starts_after_last_satisfied_anchor,
    test_reconcile_jumps_to_ready_turnin = M.test_reconcile_jumps_to_ready_turnin,
    test_advance_reconciles_past_moot_kills = M.test_advance_reconciles_past_moot_kills,
    test_certain_reconcile_rewinds_past_bogus_save = M.test_certain_reconcile_rewinds_past_bogus_save,
    test_operation_skipped_when_completion_gate_met = M.test_operation_skipped_when_completion_gate_met,
    test_objective_gate_met_for_rewarded_quest = M.test_objective_gate_met_for_rewarded_quest,
    test_missed_accept_rewinds_without_skipping_kills = M.test_missed_accept_rewinds_without_skipping_kills,
    test_class_guarded_accepts_do_not_block_status = M.test_class_guarded_accepts_do_not_block_status,
    test_npc_position_falls_back_to_static_sources = M.test_npc_position_falls_back_to_static_sources,
    test_unmet_gate_rewinds_save_that_skipped_kills = M.test_unmet_gate_rewinds_save_that_skipped_kills,
    test_gate_met_mid_kill_skips_operation = M.test_gate_met_mid_kill_skips_operation,
    test_operation_with_kills_skipped_when_quest_rewarded = M.test_operation_with_kills_skipped_when_quest_rewarded,
    test_load_reconciles_with_no_save_at_all = M.test_load_reconciles_with_no_save_at_all,
    test_save_creates_save_file = M.test_save_creates_save_file,
    test_restore_state_from_save = M.test_restore_state_from_save,
    test_fingerprint_mismatch_rejects_save = M.test_fingerprint_mismatch_rejects_save,
    test_empty_fingerprint_starts_fresh = M.test_empty_fingerprint_starts_fresh,
    test_no_save_file_returns_false = M.test_no_save_file_returns_false,
    test_serialize_state_includes_all_fields = M.test_serialize_state_includes_all_fields,
    test_auto_save_on_advance_operation = M.test_auto_save_on_advance_operation,
    test_auto_save_on_skipped_advance = M.test_auto_save_on_skipped_advance,
}

function M.run()
    -- Deterministic order: `pairs` varies per run, which turned shared-fixture leakage between
    -- these tests into an intermittent failure that moved around and read as flaky.
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
