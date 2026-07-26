-- tests/modules/questing/test_runtime_action.lua
-- Unit tests for runtime action execution and condition evaluation

local RuntimeAction = require("modules/questing/runtime_action")

local M = {}

-- ============================================================================
-- Helper: create a mock context with condition evaluation stubs
-- ============================================================================
local function mock_context(overrides)
    overrides = overrides or {}
    return {
        -- Quest tracking
        is_quest_completed = overrides.is_quest_completed or function() return false end,
        is_quest_active = overrides.is_quest_active or function() return false end,
        is_objective_complete = overrides.is_objective_complete or function() return false end,

        -- Player stats
        get_player_level = overrides.get_player_level or function() return 1 end,
        get_player_class = overrides.get_player_class or function() return "Unknown" end,
        get_player_race = overrides.get_player_race or function() return "Unknown" end,
        get_player_faction = overrides.get_player_faction or function() return "Neutral" end,

        -- Inventory
        get_item_count = overrides.get_item_count or function() return 0 end,
        get_money = overrides.get_money or function() return 0 end,

        -- Skills / reputation / cooldown
        get_skill_level = overrides.get_skill_level or function() return 0 end,
        is_item_ready = overrides.is_item_ready or function() return true end,
        get_reputation = overrides.get_reputation or function() return 0 end,

        -- Variables
        variables = overrides.variables or {},
        query = overrides.query or {},
    }
end

-- ============================================================================
-- Basic RuntimeAction tests
-- ============================================================================

function M.test_runtime_action_table()
    assert(type(RuntimeAction) == "table", "RuntimeAction should be a table")
    assert(type(RuntimeAction.execute) == "function", "RuntimeAction.execute should be a function")
end

function M.test_execute_comment()
    local ctx = mock_context()
    local action = { type = "Comment", payload = { text = "Test comment" } }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "Comment action should succeed")
end

function M.test_execute_set_variable()
    local ctx = mock_context()
    local action = { type = "SetVariable", payload = { name = "test_var", value = 42 } }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "SetVariable action should succeed")
    assert(ctx.variables.test_var == 42, "Variable should be set")
end

-- ============================================================================
-- evaluate_condition() tests
-- ============================================================================

function M.test_condition_always_true()
    local ctx = mock_context()
    local result = RuntimeAction.evaluate_condition(ctx, "AlwaysTrue")
    assert(result == true, "AlwaysTrue should return true")
end

function M.test_condition_quest_completed()
    local ctx = mock_context({
        is_quest_completed = function(self, entry)
            return entry == 33
        end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "QuestCompleted", payload = 33 }) == true,
        "QuestCompleted(33) with completed quest should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "QuestCompleted", payload = 99 }) == false,
        "QuestCompleted(99) with incomplete quest should be false")
end

function M.test_condition_quest_active()
    local ctx = mock_context({
        is_quest_active = function(self, entry)
            return entry == 42
        end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "QuestAccepted", payload = 42 }) == true,
        "QuestAccepted(42) with active quest should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "QuestAccepted", payload = 99 }) == false,
        "QuestAccepted(99) with inactive quest should be false")
end

function M.test_condition_level_at_least()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelAtLeast", payload = 60 }) == true,
        "LevelAtLeast(60) at level 60 should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelAtLeast", payload = 70 }) == false,
        "LevelAtLeast(70) at level 60 should be false")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelAtLeast", payload = 10 }) == true,
        "LevelAtLeast(10) at level 60 should be true")
end

function M.test_condition_level_below()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelBelow", payload = 70 }) == true,
        "LevelBelow(70) at level 60 should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelBelow", payload = 60 }) == false,
        "LevelBelow(60) at level 60 should be false")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "LevelBelow", payload = 50 }) == false,
        "LevelBelow(50) at level 60 should be false")
end

function M.test_condition_has_item()
    local ctx = mock_context({
        get_item_count = function(self, entry)
            if entry == 6948 then return 1 end
            return 0
        end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "HasItem", payload = 6948 }) == true,
        "HasItem(6948) with item should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "HasItem", payload = 9999 }) == false,
        "HasItem(9999) without item should be false")
end

function M.test_condition_item_count_at_least()
    local ctx = mock_context({
        get_item_count = function(self, entry)
            if entry == 6948 then return 3 end
            return 0
        end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "ItemCountAtLeast", payload = { 6948, 3 } }) == true,
        "ItemCountAtLeast(6948, 3) with 3 items should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "ItemCountAtLeast", payload = { 6948, 5 } }) == false,
        "ItemCountAtLeast(6948, 5) with 3 items should be false")
end

function M.test_condition_gold_at_least()
    local ctx = mock_context({
        get_money = function() return 50000 end,  -- 5 gold
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "GoldAtLeast", payload = 50000 }) == true,
        "GoldAtLeast(50000) with 5g should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "GoldAtLeast", payload = 100000 }) == false,
        "GoldAtLeast(100000) with 5g should be false")
end

function M.test_condition_class_is()
    local ctx = mock_context({
        get_player_class = function() return "Priest" end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "ClassIs", payload = "Priest" }) == true,
        "ClassIs(Priest) for priest should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "ClassIs", payload = "Mage" }) == false,
        "ClassIs(Mage) for priest should be false")
end

function M.test_condition_race_is()
    local ctx = mock_context({
        get_player_race = function() return "Human" end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "RaceIs", payload = "Human" }) == true,
        "RaceIs(Human) for human should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "RaceIs", payload = "Orc" }) == false,
        "RaceIs(Orc) for human should be false")
end

function M.test_condition_faction_is()
    local ctx = mock_context({
        get_player_faction = function() return "Alliance" end,
    })
    assert(RuntimeAction.evaluate_condition(ctx, { type = "FactionIs", payload = "Alliance" }) == true,
        "FactionIs(Alliance) for alliance should be true")
    assert(RuntimeAction.evaluate_condition(ctx, { type = "FactionIs", payload = "Horde" }) == false,
        "FactionIs(Horde) for alliance should be false")
end

function M.test_condition_not()
    local ctx = mock_context({
        get_player_class = function() return "Priest" end,
    })
    -- Not(ClassIs(Mage)) — priest is not a mage → true
    local cond = { type = "Not", payload = { type = "ClassIs", payload = "Mage" } }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == true,
        "Not(ClassIs(Mage)) for priest should be true")
    -- Not(ClassIs(Priest)) — priest IS a priest → false
    cond = { type = "Not", payload = { type = "ClassIs", payload = "Priest" } }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == false,
        "Not(ClassIs(Priest)) for priest should be false")
end

function M.test_condition_all()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
        is_quest_completed = function(self, entry)
            return entry == 33
        end,
    })
    -- All(LevelAtLeast(10), QuestCompleted(33)) — both true → true
    local cond = {
        type = "All",
        payload = {
            { type = "LevelAtLeast", payload = 10 },
            { type = "QuestCompleted", payload = 33 },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == true,
        "All(true, true) should be true")

    -- All(LevelAtLeast(70), QuestCompleted(33)) — first false → false
    cond = {
        type = "All",
        payload = {
            { type = "LevelAtLeast", payload = 70 },
            { type = "QuestCompleted", payload = 33 },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == false,
        "All(false, true) should be false")
end

function M.test_condition_any()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
        is_quest_completed = function(self, entry)
            return entry == 33
        end,
    })
    -- Any(LevelAtLeast(10), QuestCompleted(99)) — first true → true
    local cond = {
        type = "Any",
        payload = {
            { type = "LevelAtLeast", payload = 10 },
            { type = "QuestCompleted", payload = 99 },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == true,
        "Any(true, false) should be true")

    -- Any(LevelAtLeast(70), QuestCompleted(99)) — both false → false
    cond = {
        type = "Any",
        payload = {
            { type = "LevelAtLeast", payload = 70 },
            { type = "QuestCompleted", payload = 99 },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == false,
        "Any(false, false) should be false")
end

function M.test_condition_nested_logic()
    local ctx = mock_context({
        get_player_level = function() return 60 end,
        get_player_class = function() return "Priest" end,
        is_quest_completed = function(self, entry)
            return entry == 33
        end,
    })
    -- Not(All(LevelAtLeast(10), Not(ClassIs(Priest))))
    -- inner: All(LevelAtLeast(10)=true, Not(ClassIs(Priest)=false)=false) = false
    -- Not(false) = true
    local cond = {
        type = "Not",
        payload = {
            type = "All",
            payload = {
                { type = "LevelAtLeast", payload = 10 },
                { type = "Not", payload = { type = "ClassIs", payload = "Priest" } },
            },
        },
    }
    assert(RuntimeAction.evaluate_condition(ctx, cond) == true,
        "Nested Not(All(Level≥10, Not(Priest))) should be true")
end

-- ============================================================================
-- execute_condition() mapping tests
-- ============================================================================

function M.test_execute_condition_gate_passes()
    local ctx = mock_context({
        is_quest_completed = function(self, entry) return entry == 33 end,
    })
    local action = {
        type = "Condition",
        payload = { condition = { type = "QuestCompleted", payload = 33 } },
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "Condition gate should pass when condition is true")
end

function M.test_execute_condition_gate_skips()
    -- PR5b: role now selects the gating semantics. Applicability-role gates skip on unmet
    -- conditions (best-effort). See test_execute_condition_missing_role_defaults_to_completion
    -- below for the no-role back-compat case, which now waits instead of skipping.
    local ctx = mock_context({
        is_quest_completed = function(self, entry) return false end,
    })
    local action = {
        type = "Condition",
        payload = { condition = { type = "QuestCompleted", payload = 99 }, role = "Applicability" },
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "skipped", "Condition gate should skip when condition is false")
end

-- ============================================================================
-- PR5b — execute_condition role gating (Completion vs Applicability)
-- ============================================================================

function M.test_execute_condition_completion_role_unmet_waits()
    local ctx = mock_context({
        is_quest_completed = function(self, entry) return false end,
    })
    local action = {
        type = "Condition",
        payload = {
            condition = { type = "QuestCompleted", payload = 99 },
            role = "Completion",
        },
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "waiting", "Completion-role gate should wait when condition is unmet")
end

function M.test_execute_condition_completion_role_met_succeeds()
    local ctx = mock_context({
        is_quest_completed = function(self, entry) return entry == 33 end,
    })
    local action = {
        type = "Condition",
        payload = {
            condition = { type = "QuestCompleted", payload = 33 },
            role = "Completion",
        },
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "Completion-role gate should succeed when condition is met")
end

function M.test_execute_condition_applicability_role_unmet_skips()
    local ctx = mock_context({
        is_quest_active = function(self, entry) return false end,
    })
    local action = {
        type = "Condition",
        payload = {
            condition = { type = "QuestAccepted", payload = 99 },
            role = "Applicability",
        },
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "skipped", "Applicability-role gate should skip (best-effort) when condition is unmet")
end

function M.test_execute_condition_applicability_role_met_succeeds()
    local ctx = mock_context({
        is_quest_active = function(self, entry) return true end,
    })
    local action = {
        type = "Condition",
        payload = {
            condition = { type = "QuestAccepted", payload = 33 },
            role = "Applicability",
        },
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "Applicability-role gate should succeed when condition is met")
end

function M.test_execute_condition_missing_role_defaults_to_completion()
    -- Back-compat: profiles compiled before PR5a carry no `role` field at all.
    local ctx = mock_context({
        is_quest_completed = function(self, entry) return false end,
    })
    local action = {
        type = "Condition",
        payload = { condition = { type = "QuestCompleted", payload = 99 } }, -- no role field
    }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "waiting", "Condition action with no role field should default to Completion (waiting, not skipped)")
end

-- ============================================================================
-- Unknown action type
-- ============================================================================

function M.test_execute_wait_waits_then_succeeds()
    local ctx = mock_context()
    local action = { type = "Wait", payload = { duration = 5 } }
    local now = 100
    local orig_time = _G.core and _G.core.time
    _G.core = _G.core or {}
    _G.core.time = function() return now end

    local first = RuntimeAction.execute(action, ctx)
    now = 103
    local mid = RuntimeAction.execute(action, ctx)
    now = 106
    local last = RuntimeAction.execute(action, ctx)

    _G.core.time = orig_time

    -- "blocked" routed a plain timer into nav recovery, burned retries, and counted
    -- spurious failures; a running Wait must hold as "waiting" instead.
    assert(first == "waiting", "Wait must return waiting when the timer starts, got " .. tostring(first))
    assert(mid == "waiting", "Wait must return waiting before the duration elapses, got " .. tostring(mid))
    assert(last == "success", "Wait must succeed once the duration has elapsed, got " .. tostring(last))
    assert(ctx.wait_start == nil, "the timer must be cleared for the next Wait")
end

function M.test_execute_unknown_type()
    local ctx = mock_context()
    local action = { type = "NonExistentType", payload = {} }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "failed", "Unknown action type should return failed")
end

function M.test_evaluate_condition_unknown_type()
    local ctx = mock_context()
    -- Unknown condition types default to true (fails open)
    local result = RuntimeAction.evaluate_condition(ctx, { type = "MadeUpCondition", payload = "foo" })
    assert(result == true, "Unknown condition type should default to true")
end

-- ============================================================================
-- F4 — per-execute_kill object snapshot
-- ============================================================================

--- Two UnitHelper lookups made INSIDE one snapshot window must share a single
--- get_all_objects() scan.
function M.test_f4_snapshot_window_shares_one_scan()
    local UnitHelper = RuntimeAction.UnitHelper
    local scan_count = 0
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    local saved = _G.core.object_manager.get_all_objects
    _G.core.object_manager.get_all_objects = function()
        scan_count = scan_count + 1
        return {}
    end

    UnitHelper._begin_snapshot()
    UnitHelper.get_nearest_creature({ 123 })
    UnitHelper.get_nearest_creature({ 456 })
    UnitHelper.get_nearest_game_object({ 789 })
    UnitHelper._end_snapshot()

    _G.core.object_manager.get_all_objects = saved
    assert(scan_count == 1,
        "expected exactly one get_all_objects scan inside one snapshot window, got " .. tostring(scan_count))
end

--- Outside a snapshot window (the default, unaffected state) every lookup still gets its own
--- fresh scan — F4 must not change behavior for any caller other than execute_kill.
function M.test_f4_lookups_outside_a_snapshot_scan_independently()
    local UnitHelper = RuntimeAction.UnitHelper
    local scan_count = 0
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    local saved = _G.core.object_manager.get_all_objects
    _G.core.object_manager.get_all_objects = function()
        scan_count = scan_count + 1
        return {}
    end

    assert(UnitHelper._snapshot_active == false, "no snapshot should be active outside execute_kill")
    UnitHelper.get_nearest_creature({ 123 })
    UnitHelper.get_nearest_creature({ 456 })

    _G.core.object_manager.get_all_objects = saved
    assert(scan_count == 2,
        "expected each lookup to scan independently outside a snapshot window, got " .. tostring(scan_count))
end

--- execute_kill itself must open and always close the snapshot, including when its
--- implementation errors, so a thrown error can never leave a later, unrelated action sharing
--- a stale snapshot.
function M.test_f4_execute_kill_closes_snapshot_even_on_error()
    local UnitHelper = RuntimeAction.UnitHelper
    local original_impl = RuntimeAction.execute_kill

    -- Force the real implementation to error by handing it a payload that makes
    -- table.concat(entries, ",") explode (entries must be an array of strings/numbers).
    local ok = pcall(function()
        RuntimeAction.execute_kill({ creature_entries = { {} } }, { persist = {} })
    end)

    assert(ok == false, "a bad payload should still surface as an error from execute_kill")
    assert(UnitHelper._snapshot_active == false,
        "the snapshot must be closed even when execute_kill's implementation errors")

    RuntimeAction.execute_kill = original_impl
end

-- ============================================================================
-- Run all tests
-- ============================================================================

-- ============================================================================
-- Gossip pacing (turn-in): attempts are TIME-paced, not frame-paced
-- ============================================================================

function M.test_turnin_attempts_are_time_paced()
    local now = 100
    local complete_calls, reward_choice = 0, nil
    local rewarded = false
    _G.core = _G.core or {}
    local prev_time, prev_quests = _G.core.time, _G.core.quests
    _G.core.time = function() return now end
    _G.core.quests = {
        is_quest_flagged_completed = function(_) return rewarded end,
        is_on_quest = function(_) return not rewarded end,
        is_gossip_frame_shown = function() return true end,
        select_gossip_active_quest = function(_) end,
        complete_quest = function() complete_calls = complete_calls + 1 end,
        get_quest_reward = function(choice) reward_choice = choice end,
    }
    local ctx = { persist = {} }
    function ctx:is_at_npc(_e, _r) return true end

    local payload = { quest_id = 7, npc_entry = 1 }

    -- Attempt 1 fires immediately and claims the DEFAULT reward slot.
    local s1 = RuntimeAction.execute_turnin_quest(payload, ctx)
    assert(s1 == "retry", "unverified attempt reports retry, got " .. tostring(s1))
    assert(complete_calls == 1, "first tick must issue exactly one real attempt")
    assert(reward_choice == 1, "reward must be claimed with default slot 1")

    -- Frames inside the pacing window HOLD instead of burning the retry budget.
    now = 100.1
    local s2 = RuntimeAction.execute_turnin_quest(payload, ctx)
    assert(s2 == "waiting", "inside the pacing window the action must hold, got " .. tostring(s2))
    assert(complete_calls == 1, "no second attempt inside the pacing window")

    -- A settling attempt is detected WHILE holding, without a new attempt.
    rewarded = true
    now = 100.2
    local s3 = RuntimeAction.execute_turnin_quest(payload, ctx)
    assert(s3 == "success", "the hold path must verify and succeed, got " .. tostring(s3))
    assert(complete_calls == 1, "success on settle must not re-attempt")

    -- After the interval, a still-unfinished turn-in gets a fresh real attempt.
    rewarded = false
    now = 200
    local s4 = RuntimeAction.execute_turnin_quest(payload, ctx)
    assert(s4 == "retry", "past the interval a new attempt runs, got " .. tostring(s4))
    assert(complete_calls == 2, "one more real attempt after the interval")

    _G.core.time = prev_time
    _G.core.quests = prev_quests
end

function M.test_turnin_guide_reward_choice_wins()
    local reward_choice = nil
    _G.core = _G.core or {}
    local prev_time, prev_quests = _G.core.time, _G.core.quests
    _G.core.time = function() return 50 end
    _G.core.quests = {
        is_quest_flagged_completed = function(_) return false end,
        is_on_quest = function(_) return true end,
        is_gossip_frame_shown = function() return true end,
        select_gossip_active_quest = function(_) end,
        complete_quest = function() end,
        get_quest_reward = function(choice) reward_choice = choice end,
    }
    local ctx = { persist = {} }
    function ctx:is_at_npc(_e, _r) return true end

    RuntimeAction.execute_turnin_quest({ quest_id = 33, npc_entry = 1, choose_reward = 2 }, ctx)
    assert(reward_choice == 2, "the guide's `.turnin 33,2` choice must win over the default")

    _G.core.time = prev_time
    _G.core.quests = prev_quests
end

local tests = {
    test_turnin_attempts_are_time_paced = M.test_turnin_attempts_are_time_paced,
    test_turnin_guide_reward_choice_wins = M.test_turnin_guide_reward_choice_wins,
    test_runtime_action_table = M.test_runtime_action_table,
    test_f4_snapshot_window_shares_one_scan = M.test_f4_snapshot_window_shares_one_scan,
    test_f4_lookups_outside_a_snapshot_scan_independently = M.test_f4_lookups_outside_a_snapshot_scan_independently,
    test_f4_execute_kill_closes_snapshot_even_on_error = M.test_f4_execute_kill_closes_snapshot_even_on_error,
    test_execute_comment = M.test_execute_comment,
    test_execute_set_variable = M.test_execute_set_variable,

    test_condition_always_true = M.test_condition_always_true,
    test_condition_quest_completed = M.test_condition_quest_completed,
    test_condition_quest_active = M.test_condition_quest_active,
    test_condition_level_at_least = M.test_condition_level_at_least,
    test_condition_level_below = M.test_condition_level_below,
    test_condition_has_item = M.test_condition_has_item,
    test_condition_item_count_at_least = M.test_condition_item_count_at_least,
    test_condition_gold_at_least = M.test_condition_gold_at_least,
    test_condition_class_is = M.test_condition_class_is,
    test_condition_race_is = M.test_condition_race_is,
    test_condition_faction_is = M.test_condition_faction_is,
    test_condition_not = M.test_condition_not,
    test_condition_all = M.test_condition_all,
    test_condition_any = M.test_condition_any,
    test_condition_nested_logic = M.test_condition_nested_logic,

    test_execute_condition_gate_passes = M.test_execute_condition_gate_passes,
    test_execute_condition_gate_skips = M.test_execute_condition_gate_skips,
    test_execute_condition_completion_role_unmet_waits = M.test_execute_condition_completion_role_unmet_waits,
    test_execute_condition_completion_role_met_succeeds = M.test_execute_condition_completion_role_met_succeeds,
    test_execute_condition_applicability_role_unmet_skips = M.test_execute_condition_applicability_role_unmet_skips,
    test_execute_condition_applicability_role_met_succeeds = M.test_execute_condition_applicability_role_met_succeeds,
    test_execute_condition_missing_role_defaults_to_completion = M.test_execute_condition_missing_role_defaults_to_completion,

    test_execute_unknown_type = M.test_execute_unknown_type,
    test_evaluate_condition_unknown_type = M.test_evaluate_condition_unknown_type,
    test_execute_wait_waits_then_succeeds = M.test_execute_wait_waits_then_succeeds,
}

function M.run()
    -- Deterministic order: `pairs` varies per run, turning cross-suite state leakage into an
    -- intermittent failure that reads as flaky.
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

-- ============================================================================
-- Flight — the take_taxi SDK ceiling, and the operator's skip ruling
-- ============================================================================

--- MEASURED LIVE (2026-07-26): `core.input.take_taxi` does not exist, and nothing taxi-shaped
--- exists in any of the SDK's 22 namespaces. OPERATOR RULING: a flight step is SKIPPED, not
--- retried — the guides follow every `.fly` with `.goto` lines at the arrival zone, so the
--- runner nav-walks there instead of spinning its retry budget against a missing API.
--- CANNOT SEE: whether a future injector build adds the API (the resolver path below covers it).
function M.test_flight_without_taxi_api_is_skipped_not_retried()
    local notes = {}
    local ctx = mock_context({})
    ctx.is_at_npc = function() return true end
    ctx.persist = {}
    ctx.publish = function(_, event, payload) notes[#notes + 1] = { event = event, payload = payload } end
    local saved_input = core and core.input
    if core then core.input = {} end -- the measured live shape: no take_taxi anywhere
    local action = { type = "Flight", payload = { npc_entry = 123, destination = "Ironforge" } }
    local result = RuntimeAction.execute(action, ctx)
    if core then core.input = saved_input end
    assert(result == "success", "a flight step with no taxi API must SKIP (ruling), got: " .. tostring(result))
end

--- The other half: when the API exists, a NAMED destination resolves through the taxi catalog
--- (faction-disambiguated, Title-case accepted) and the node id — not the raw string, not a
--- guessed index — is what reaches take_taxi.
function M.test_flight_with_taxi_api_resolves_a_name_to_its_node()
    local taken = {}
    local ctx = mock_context({ get_player_faction = function() return "Alliance" end })
    ctx.is_at_npc = function() return true end
    ctx.persist = {}
    local saved_input = core and core.input
    if core then core.input = { take_taxi = function(idx) taken[#taken + 1] = idx end } end
    local action = { type = "Flight", payload = { npc_entry = 123, destination = "Tanaris" } }
    local result = RuntimeAction.execute(action, ctx)
    if core then core.input = saved_input end
    assert(result == "success", "resolvable flight must succeed, got: " .. tostring(result))
    assert(#taken == 1 and taken[1] == 39,
        "Tanaris + Alliance must fly node 39 (Gadgetzan A), got: " .. tostring(taken[1]))
end

return M