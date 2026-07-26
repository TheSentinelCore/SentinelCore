-- tests/modules/questing/test_execution_plan.lua
-- W8 -- ADR 09 §6.2 / ADR 09a §1.4: the runtime executes a resolver ExecutionPlan.
--
-- Two properties are load-bearing here and every case below exists to hold one of them:
--
--   1. NOTHING THAT RUNS TODAY MAY CHANGE. There is compiled content in the old RuntimeProfile
--      shape and a green offline suite over it, so a plan-shaped op and a legacy op must reach the
--      SAME executor. A linear plan (every transition `guard: null`) has to advance byte-for-byte
--      like the `_current_operation_idx + 1` it replaces.
--   2. THE PLAN'S `to_index` IS 0-BASED. It comes off a Rust `Vec` enumerate (resolve.rs
--      `index_of`), and Lua's `operations` is 1-based. Getting that wrong reroutes the whole
--      guide silently -- every branch lands one step early, which looks like a content bug, not
--      an off-by-one. It is pinned explicitly.

local ExecutionPlan = require("modules/questing/execution_plan")
local RuntimeProfile = require("modules/questing/runtime_profile")
local EventSchema = require("core/event_schema")
local JSON = require("core/JSON")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- Harness
-- ============================================================================

local written_files = {}
local player_level = 1

local function mock_globals()
    written_files = {}
    player_level = 1
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            is_unit = function() return true end,
            is_dead = function() return false end,
            is_dead_or_ghost = function() return false end,
            is_ghost = function() return false end,
            get_position = function() return { x = 0, y = 0, z = 0 } end,
            get_level = function() return player_level end,
            get_class = function() return 1 end,
            get_race = function() return "Human" end,
            get_health = function() return 100 end,
            get_name = function() return "PlanTester" end,
        }
    end
    _G.core.write_data_file = function(path, content)
        written_files[path] = content
        return true
    end
    _G.core.read_data_file = function(path) return written_files[path] end
    _G.core.get_file_info = nil
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

local function comment(text)
    return { type = "Comment", payload = { text = text } }
end

--- Ids the resolver would mint as UUIDs. Only their stability matters to the runtime.
local function node(n)
    return string.format("018f0000-0000-0000-0000-0000000000%02d", n)
end

local COND_LEVEL_5 = "018fcccc-0000-0000-0000-000000000005"
local COND_LEVEL_60 = "018fcccc-0000-0000-0000-000000000060"

--- An ExecutionPlan exactly as §1.4 puts it on the wire: 0-based `to_index`, `guard` either
--- null or a condition id. `conditions` carries the ConditionDef table the guards name.
local function plan_wire(operations, conditions)
    return {
        schema_version = 3,
        campaign_id = "018faaaa-0000-0000-0000-000000000001",
        graph_id = "018fbbbb-0000-0000-0000-000000000001",
        db_fingerprint = "tbcmangos@a1b2c3",
        content_hash = "planhash",
        operations = operations,
        conditions = conditions,
    }
end

local function linear_plan_wire()
    return plan_wire({
        { node_id = node(1), actions = { comment("one") }, next = { { to_index = 1, guard = nil } } },
        { node_id = node(2), actions = { comment("two") }, next = { { to_index = 2, guard = nil } } },
        { node_id = node(3), actions = { comment("three") }, next = {} },
    })
end

--- Op 1 forks: level >= 5 goes to op 3 (index 2), otherwise op 2 (index 1). Both rejoin at op 4.
local function branching_plan_wire()
    return plan_wire({
        { node_id = node(1), actions = { comment("fork") }, next = {
            { to_index = 2, guard = COND_LEVEL_5 },
            { to_index = 1, guard = nil },
        } },
        { node_id = node(2), actions = { comment("low road") }, next = { { to_index = 3, guard = nil } } },
        { node_id = node(3), actions = { comment("high road") }, next = { { to_index = 3, guard = nil } } },
        { node_id = node(4), actions = { comment("rejoin") }, next = {} },
    }, {
        { id = COND_LEVEL_5, type = "LevelAtLeast", payload = 5 },
        { id = COND_LEVEL_60, type = "LevelAtLeast", payload = 60 },
    })
end

local function legacy_profile()
    return {
        content_hash = "legacyhash",
        operations = {
            { id = 1, actions = { comment("one") }, next_condition = "auto" },
            { id = 2, actions = { comment("two") }, next_condition = "auto" },
            { id = 3, actions = { comment("three") }, next_condition = "auto" },
        },
    }
end

local function executor_for(profile_table, path)
    mock_globals()
    local executor = RuntimeProfile:new(path or "test_execution_plan.json")
    executor._profile = profile_table
    executor._save_path = executor:_compute_save_path()
    return executor
end

--- Tick until the executor leaves "running", recording the operation index at each tick.
--- Bounded: a route that cannot leave an operation is the bug this whole file is about, and a
--- test that hangs reports nothing.
local function run_route(executor, max_ticks)
    local visited = {}
    for _ = 1, (max_ticks or 60) do
        local idx = executor._current_operation_idx
        if visited[#visited] ~= idx then visited[#visited + 1] = idx end
        local status = executor:execute()
        if status ~= "running" then break end
    end
    return visited
end

-- ============================================================================
-- Normalization: the plan and the legacy profile become one executor shape
-- ============================================================================

function M.test_is_plan_recognises_an_execution_plan()
    T.assert_true(ExecutionPlan.is_plan(linear_plan_wire()), "graph_id + node_id + next is a plan")
end

function M.test_is_plan_rejects_a_legacy_runtime_profile()
    -- The discriminator has to be exact in this direction: a legacy profile misread as a plan
    -- would have every op treated as terminal (no `next`) and the route would stop at op 1.
    T.assert_false(ExecutionPlan.is_plan(legacy_profile()), "a compiled RuntimeProfile is not a plan")
    T.assert_false(ExecutionPlan.is_plan(nil), "nil is not a plan")
    T.assert_false(ExecutionPlan.is_plan({ operations = {} }), "an op-less table is not a plan")
end

function M.test_normalize_rebases_to_index_from_zero_to_one()
    local profile = ExecutionPlan.normalize(linear_plan_wire())
    T.assert_equal(profile.operations[1].next[1].to_index, 2,
        "wire to_index 1 is Lua operations[2]")
    T.assert_equal(profile.operations[2].next[1].to_index, 3,
        "wire to_index 2 is Lua operations[3]")
end

function M.test_normalize_keeps_the_executor_fields_the_runtime_already_reads()
    local profile = ExecutionPlan.normalize(linear_plan_wire())
    T.assert_equal(#profile.operations, 3, "operation count survives")
    T.assert_equal(profile.operations[1].id, 1, "ops carry the id _execute_running keys retries on")
    T.assert_equal(profile.operations[1].actions[1].type, "Comment", "actions are passed through")
    T.assert_equal(profile.operations[2].node_id, node(2), "node identity survives")
    T.assert_equal(profile.content_hash, "planhash", "hot reload still has a hash to compare")
end

function M.test_normalize_resolves_a_guard_id_into_its_condition()
    local profile = ExecutionPlan.normalize(branching_plan_wire())
    local guarded = profile.operations[1].next[1]
    T.assert_equal(guarded.guard_id, COND_LEVEL_5, "the id is kept for diagnostics")
    T.assert_equal(type(guarded.guard), "table", "the guard resolves to a RuntimeCondition")
    T.assert_equal(guarded.guard.type, "LevelAtLeast", "adjacently tagged, as the Lua side dispatches")
    T.assert_equal(guarded.guard.payload, 5, "payload survives resolution")
end

function M.test_normalize_accepts_a_condition_map_as_well_as_a_list()
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("x") }, next = { { to_index = 1, guard = COND_LEVEL_5 } } },
        { node_id = node(2), actions = { comment("y") }, next = {} },
    }, { [COND_LEVEL_5] = { type = "LevelAtLeast", payload = 5 } })
    local profile = ExecutionPlan.normalize(wire)
    T.assert_equal(profile.operations[1].next[1].guard.type, "LevelAtLeast",
        "a map keyed by id resolves the same as a list of ConditionDefs")
end

function M.test_normalize_accepts_an_inline_condition_guard()
    -- The plan wire in ADR 09a §1.4 carries guards as ids, but nothing stops a producer from
    -- inlining the condition. Accepting both keeps the runtime from caring which one ships.
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("x") }, next = {
            { to_index = 1, guard = { type = "LevelAtLeast", payload = 5 } },
        } },
        { node_id = node(2), actions = { comment("y") }, next = {} },
    })
    local profile = ExecutionPlan.normalize(wire)
    T.assert_equal(profile.operations[1].next[1].guard.payload, 5, "an inline guard is used as-is")
end

function M.test_normalize_marks_a_guard_that_names_no_condition()
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("x") }, next = { { to_index = 1, guard = COND_LEVEL_60 } } },
        { node_id = node(2), actions = { comment("y") }, next = {} },
    }, { { id = COND_LEVEL_5, type = "LevelAtLeast", payload = 5 } })
    local profile = ExecutionPlan.normalize(wire)
    T.assert_true(profile.operations[1].next[1].unresolved,
        "a guard id with no ConditionDef behind it must be flagged, not silently dropped")
end

-- ============================================================================
-- Branch selection
-- ============================================================================

local function always(value)
    return function() return value end
end

function M.test_a_lone_unguarded_transition_is_the_sequential_advance()
    local profile = ExecutionPlan.normalize(linear_plan_wire())
    local idx, outcome = ExecutionPlan.select_transition(profile.operations[1], always(true))
    T.assert_equal(outcome, "sequential", "a single guard-null edge is today's +1")
    T.assert_equal(idx, 2, "and it goes to the next operation")
end

function M.test_a_legacy_operation_has_no_transitions_at_all()
    local idx, outcome = ExecutionPlan.select_transition(legacy_profile().operations[1], always(true))
    T.assert_equal(outcome, "linear", "an op without `next` is pre-plan content")
    T.assert_nil(idx, "the caller keeps its own +1 for that case")
end

function M.test_the_first_satisfied_guard_wins()
    local profile = ExecutionPlan.normalize(branching_plan_wire())
    local idx, outcome, detail = ExecutionPlan.select_transition(profile.operations[1], always(true))
    T.assert_equal(outcome, "guarded", "the guarded edge is listed first and is met")
    T.assert_equal(idx, 3, "wire to_index 2 -> operations[3], the high road")
    T.assert_equal(detail.guard_id, COND_LEVEL_5, "the taken guard is reported")
end

function M.test_an_unmet_guard_falls_through_to_the_next_transition()
    local profile = ExecutionPlan.normalize(branching_plan_wire())
    local idx, outcome, detail = ExecutionPlan.select_transition(profile.operations[1], always(false))
    T.assert_equal(outcome, "sequential", "the trailing guard-null edge catches the fall-through")
    T.assert_equal(idx, 2, "the low road")
    T.assert_equal(detail.unmet, 1, "the guard that failed is counted")
end

function M.test_no_outgoing_transition_is_a_terminal_node()
    local profile = ExecutionPlan.normalize(linear_plan_wire())
    local idx, outcome = ExecutionPlan.select_transition(profile.operations[3], always(true))
    T.assert_equal(outcome, "terminal", "`next: []` means the route ends here")
    T.assert_nil(idx, "there is nowhere to go")
end

function M.test_every_guard_unmet_is_a_dead_end_not_a_fall_through()
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("x") }, next = { { to_index = 1, guard = COND_LEVEL_60 } } },
        { node_id = node(2), actions = { comment("y") }, next = {} },
    }, { { id = COND_LEVEL_60, type = "LevelAtLeast", payload = 60 } })
    local profile = ExecutionPlan.normalize(wire)
    local idx, outcome, detail = ExecutionPlan.select_transition(profile.operations[1], always(false))
    T.assert_equal(outcome, "dead_end", "an unsatisfiable node must never fall through to idx+1")
    T.assert_nil(idx, "no successor was chosen")
    T.assert_equal(detail.unmet, 1, "the unmet guard is reported")
end

function M.test_an_unresolved_guard_is_never_taken()
    -- Fail CLOSED, unlike RuntimeAction.evaluate_condition's unknown-TYPE fail-open. A guard id
    -- with no ConditionDef behind it is a broken plan (the resolver emits
    -- `resolver.guard.unknown_condition` for exactly this), and taking the edge would run a
    -- stretch of route the author gated off.
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("x") }, next = { { to_index = 1, guard = COND_LEVEL_60 } } },
        { node_id = node(2), actions = { comment("y") }, next = {} },
    })
    local profile = ExecutionPlan.normalize(wire)
    local _, outcome = ExecutionPlan.select_transition(profile.operations[1], always(true))
    T.assert_equal(outcome, "dead_end", "an unresolvable guard is not satisfiable, even fail-open")
end

-- ============================================================================
-- Execution: a linear plan is indistinguishable from today
-- ============================================================================

function M.test_a_linear_plan_advances_exactly_like_a_legacy_profile()
    local legacy = executor_for(legacy_profile())
    local legacy_path = run_route(legacy)

    local planned = executor_for(ExecutionPlan.normalize(linear_plan_wire()))
    local planned_path = run_route(planned)

    T.assert_equal(#planned_path, #legacy_path, "same number of operation boundaries")
    for i = 1, #legacy_path do
        T.assert_equal(planned_path[i], legacy_path[i],
            "operation " .. i .. " of a linear plan must match the legacy advance")
    end
    T.assert_equal(planned._state, "finished", "and it finishes")
    T.assert_equal(legacy._state, "finished", "as does the legacy profile")
end

function M.test_a_legacy_runtime_profile_still_runs_unchanged()
    local executor = executor_for(legacy_profile())
    local path = run_route(executor)
    T.assert_equal(path[1], 1, "starts at op 1")
    T.assert_equal(path[#path], 4, "walks off the end of a 3-op profile")
    T.assert_equal(executor._state, "finished", "pre-plan content still completes")
end

function M.test_a_branching_plan_takes_the_branch_whose_guard_is_met()
    local executor = executor_for(ExecutionPlan.normalize(branching_plan_wire()))
    player_level = 10
    local path = run_route(executor)
    T.assert_true(T.table_contains(path, 3), "level 10 takes the high road (operations[3])")
    T.assert_false(T.table_contains(path, 2), "and never touches the low road")
    T.assert_true(T.table_contains(path, 4), "both roads rejoin at operations[4]")
end

function M.test_a_branching_plan_takes_the_fall_through_when_the_guard_is_unmet()
    local executor = executor_for(ExecutionPlan.normalize(branching_plan_wire()))
    player_level = 1
    local path = run_route(executor)
    T.assert_true(T.table_contains(path, 2), "level 1 takes the low road (operations[2])")
    T.assert_false(T.table_contains(path, 3), "and never touches the high road")
    T.assert_true(T.table_contains(path, 4), "both roads rejoin at operations[4]")
end

function M.test_a_branch_taken_is_logged_against_the_node_it_left()
    local executor = executor_for(ExecutionPlan.normalize(branching_plan_wire()))
    player_level = 10
    run_route(executor)
    local taken
    for _, e in ipairs(executor:get_log()) do
        if e.event == "plan_branch_taken" then taken = e end
    end
    T.assert_not_nil(taken, "a guarded advance must be observable in the cockpit event list")
    T.assert_equal(taken.node_id, node(1), "attributed to the node the route left")
    T.assert_equal(taken.guard_id, COND_LEVEL_5, "naming the guard that decided it")
end

function M.test_an_unsatisfiable_operation_stops_and_logs_instead_of_hanging()
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("x") }, next = { { to_index = 1, guard = COND_LEVEL_60 } } },
        { node_id = node(2), actions = { comment("y") }, next = {} },
    }, { { id = COND_LEVEL_60, type = "LevelAtLeast", payload = 60 } })
    local executor = executor_for(ExecutionPlan.normalize(wire))
    player_level = 1
    run_route(executor)

    local dead
    for _, e in ipairs(executor:get_log()) do
        if e.event == "plan_dead_end" then dead = e end
    end
    T.assert_not_nil(dead, "a dead end must be logged -- a silent stall is invisible in-game")
    T.assert_equal(dead.node_id, node(1), "named by node")
    T.assert_equal(dead.unmet, 1, "with the count of guards that refused")
    T.assert_equal(executor._state, "finished",
        "and the executor terminates rather than re-running op 1 forever")
    T.assert_true(executor._current_operation_idx ~= 2,
        "it must NOT fall through to the next index")
end

function M.test_a_terminal_node_ends_the_route_even_when_it_is_not_the_last_index()
    -- Topological order does not put terminal nodes last. `next: []` at operations[1] means the
    -- route is over; a `+1` there would run operations[2], which nothing points at.
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("x") }, next = {} },
        { node_id = node(2), actions = { comment("orphan") }, next = {} },
    })
    local executor = executor_for(ExecutionPlan.normalize(wire))
    local path = run_route(executor)
    T.assert_false(T.table_contains(path, 2), "an unreachable operation must not run")
    T.assert_equal(executor._state, "finished", "the terminal node ends the route")
end

-- ============================================================================
-- node_id on the event contract (ADR 09a §1.5)
-- ============================================================================

function M.test_node_id_reaches_emitted_events()
    local executor = executor_for(ExecutionPlan.normalize(linear_plan_wire()))
    executor._current_operation_idx = 2
    executor:_log_event("action_success", { msg = "ok" })
    local entry = executor:get_log()[1]
    T.assert_equal(entry.node_id, node(2), "the event names the graph node it happened at")
    local ok, err = EventSchema.validate(entry)
    T.assert_true(ok, "and still satisfies the schema: " .. tostring(err))
end

function M.test_node_id_follows_the_route_across_a_branch()
    local executor = executor_for(ExecutionPlan.normalize(branching_plan_wire()))
    player_level = 10
    run_route(executor)
    local seen = {}
    for _, e in ipairs(executor:get_log()) do
        if e.node_id then seen[e.node_id] = true end
    end
    T.assert_true(seen[node(3)], "events from the high road are tagged with its node")
    T.assert_nil(seen[node(2)], "and nothing is attributed to the road not taken")
end

function M.test_node_id_stays_nil_for_a_legacy_profile()
    -- W4 shipped node_id as always-nil because the executor had no graph identity. Pre-plan
    -- content still has none, and inventing one would make the field a lie.
    local executor = executor_for(legacy_profile())
    executor:_log_event("load_fresh", {})
    T.assert_nil(executor:get_log()[1].node_id, "a compiled profile has no graph node")
end

-- ============================================================================
-- Route reconciliation under branching (ADR 09 §6.2)
-- ============================================================================

function M.test_route_reconciliation_still_jumps_forward_over_a_plan()
    -- Reconciliation derives position from LIVE quest flags, not from the graph, so it must keep
    -- working verbatim over plan-shaped operations. This is what makes a relog land on the right
    -- step; the branching work is not allowed to cost it.
    local wire = plan_wire({
        { node_id = node(1), actions = { { type = "TurnInQuest", payload = { quest_id = 101 } } },
          next = { { to_index = 1, guard = nil } } },
        { node_id = node(2), actions = { { type = "TurnInQuest", payload = { quest_id = 102 } } },
          next = { { to_index = 2, guard = nil } } },
        { node_id = node(3), actions = { comment("work left to do") }, next = {} },
    })
    local executor = executor_for(ExecutionPlan.normalize(wire))
    _G.core.quests.is_quest_flagged_completed = function(id) return id == 101 or id == 102 end
    _G.core.quests.is_on_quest = function() return false end

    local start_idx = executor:_reconcile_start_operation()
    T.assert_equal(start_idx, 3, "both turn-ins are rewarded, so the route position is op 3")

    executor:_advance_operation(executor._profile.operations[1])
    T.assert_equal(executor._current_operation_idx, 3,
        "the boundary re-reconcile must still overtake the graph's own successor")

    _G.core.quests.is_quest_flagged_completed = function() return false end
    _G.core.quests.is_on_quest = function() return false end
end

function M.test_reconciliation_does_not_override_a_branch_when_nothing_is_observable()
    -- The inverse guard: with no quest work to observe, reconciliation returns op 1 and must not
    -- drag a branching route backwards.
    local executor = executor_for(ExecutionPlan.normalize(branching_plan_wire()))
    player_level = 10
    executor:_advance_operation(executor._profile.operations[1])
    T.assert_equal(executor._current_operation_idx, 3,
        "an unobservable route keeps the guard's verdict")
end

-- ============================================================================
-- Simulation (ADR 09a §2 W6: edit-then-simulate, headless)
-- ============================================================================

function M.test_dry_run_over_a_legacy_profile_reports_what_it_always_did()
    local executor = executor_for(legacy_profile())
    executor._dry_run = true
    local result = executor:simulate()
    T.assert_equal(result.operations_count, 3, "every operation is counted")
    T.assert_equal(result.failed_actions, 0, "comments cannot fail")
    T.assert_equal(result.blocked_operations, 0, "nothing blocks a linear profile")
    T.assert_equal(result.skipped_conditions, 0, "no conditions in this profile")
end

function M.test_dry_run_reports_the_path_taken_through_a_branching_plan()
    local executor = executor_for(ExecutionPlan.normalize(branching_plan_wire()))
    player_level = 10
    local result = executor:simulate()
    T.assert_equal(#result.path, 3, "fork, high road, rejoin -- the low road is not walked")
    T.assert_equal(result.path[1].node_id, node(1), "the path names nodes, not just indices")
    T.assert_equal(result.path[2].operation, 3, "the high road is operations[3]")
    T.assert_equal(result.path[3].node_id, node(4), "and the route rejoins")
end

function M.test_dry_run_walks_the_other_branch_when_the_guard_is_unmet()
    local executor = executor_for(ExecutionPlan.normalize(branching_plan_wire()))
    player_level = 1
    local result = executor:simulate()
    T.assert_equal(result.path[2].operation, 2, "level 1 simulates down the low road")
    T.assert_equal(result.unmet_guards, 1, "and reports the guard it could not satisfy")
end

function M.test_dry_run_reports_a_blocked_operation()
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("x") }, next = { { to_index = 1, guard = COND_LEVEL_60 } } },
        { node_id = node(2), actions = { comment("y") }, next = {} },
    }, { { id = COND_LEVEL_60, type = "LevelAtLeast", payload = 60 } })
    local executor = executor_for(ExecutionPlan.normalize(wire))
    player_level = 1
    local result = executor:simulate()
    T.assert_equal(result.blocked_operations, 1, "the node the walk could not leave is blocked")
    T.assert_equal(result.unmet_guards, 1, "with its refusing guard counted")
    T.assert_equal(#result.path, 1, "and the walk stops there")
end

function M.test_dry_run_reports_a_failed_action()
    local wire = plan_wire({
        { node_id = node(1), actions = { { payload = {} } }, next = {} },
    })
    local executor = executor_for(ExecutionPlan.normalize(wire))
    local result = executor:simulate()
    T.assert_equal(result.failed_actions, 1,
        "a lowered operation carrying an action with no type is a resolver bug, and simulation " ..
        "is where an author must see it")
end

function M.test_dry_run_cannot_hang_on_a_cyclic_plan()
    -- The resolver emits topological order, so a cycle is malformed input -- but simulation is
    -- the offline tool authors point at half-finished graphs, and it must terminate on anything.
    local wire = plan_wire({
        { node_id = node(1), actions = { comment("a") }, next = { { to_index = 1, guard = nil } } },
        { node_id = node(2), actions = { comment("b") }, next = { { to_index = 0, guard = nil } } },
    })
    local executor = executor_for(ExecutionPlan.normalize(wire))
    local result = executor:simulate()
    T.assert_true(result.truncated, "the walk gives up rather than looping forever")
    T.assert_true(#result.path > 0, "and still reports what it saw")
end

function M.test_simulation_needs_no_client()
    -- The whole point of W6: this is callable from the offline harness with no Sylvannas client,
    -- no QueryServer and no NavServer. Strip the nav client and it must still produce a result.
    local executor = executor_for(ExecutionPlan.normalize(branching_plan_wire()))
    _G.SentinelNavClient = nil
    local result = executor:simulate()
    T.assert_nil(result.error, "simulation must not depend on the nav client")
    T.assert_true(#result.path > 0, "and still walks the plan")
end

-- ============================================================================
-- The JSON load path (the in-game one)
-- ============================================================================

function M.test_load_accepts_an_execution_plan_from_json()
    mock_globals()
    -- Guards go over the wire as `null`, which core/JSON decodes to nil -- so a transition table
    -- with no `guard` key IS the unguarded case, not a missing field.
    written_files["plan.json"] = JSON.encode(linear_plan_wire())
    local executor = RuntimeProfile:new("plan.json")
    local ok, err = executor:load()
    T.assert_true(ok, "an ExecutionPlan must load like a profile: " .. tostring(err))
    T.assert_equal(#executor._profile.operations, 3, "operations survive the round trip")
    T.assert_equal(executor._profile.operations[1].next[1].to_index, 2,
        "and to_index is rebased on the way in")
    T.assert_equal(executor._profile.operations[1].node_id, node(1), "node identity survives JSON")
end

function M.test_load_still_accepts_a_legacy_profile_from_json()
    mock_globals()
    written_files["legacy.json"] = JSON.encode(legacy_profile())
    local executor = RuntimeProfile:new("legacy.json")
    local ok, err = executor:load()
    T.assert_true(ok, "existing content must keep loading: " .. tostring(err))
    T.assert_equal(#executor._profile.operations, 3, "unchanged")
    T.assert_nil(executor._profile.operations[1].next, "and it is not rewritten into plan shape")
end

return M
