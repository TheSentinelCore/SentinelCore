local T = require("tests/TestUtil")

local function run()
    T.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local ObjectiveService = require("services/ObjectiveService")
    local WaypointObjectiveProvider = require("modes/providers/WaypointObjectiveProvider")
    local Events = require("events/Events")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("objective.quest.queue", {
        { x = 10, y = 0, z = 0, label = "QuestWP1" },
    })
    bb:set("objective.quest.queue_index", 1)

    local selected_count = 0
    local completed_count = 0
    local failed_count = 0
    bus:on(Events.OBJECTIVE_SELECTED, function()
        selected_count = selected_count + 1
    end, { owner = "sc016" })
    bus:on(Events.OBJECTIVE_COMPLETED, function()
        completed_count = completed_count + 1
    end, { owner = "sc016" })
    bus:on(Events.OBJECTIVE_FAILED, function()
        failed_count = failed_count + 1
    end, { owner = "sc016" })

    local nav_calls = 0
    local fake_nav = {
        move_to = function(_, _, callback)
            nav_calls = nav_calls + 1
            if callback then
                callback(true, nil, nil)
            end
        end,
    }

    local service = ObjectiveService:new(bus, bb, {
        objective_timeout = 60.0,
        progress_emit_interval = 0.0,
    })
    local provider = WaypointObjectiveProvider:new({
        mode_id = "quest",
        queue_key = "objective.quest.queue",
        index_key = "objective.quest.queue_index",
        loop_key = "objective.quest.loop",
        default_loop = false,
        arrive_distance = 2.0,
        reissue_secs = 0.0,
        timeout_secs = 30.0,
    })

    service:set_mode("quest", provider, {
        navigation = fake_nav,
    })
    T.assert_true(service:has_work() == true, "objective service should detect queued work")

    local status1, err1 = service:tick(1000.0)
    T.assert_eq(status1, "running", "first objective tick should be running")
    T.assert_eq(err1, nil, "first objective tick should not error")
    T.assert_true(nav_calls >= 1, "objective tick should issue navigation move")
    T.assert_true(service:is_active() == true, "service should hold active objective after first tick")

    bb:set("player.position", { x = 10, y = 0, z = 0 })
    local status2, err2 = service:tick(1001.0)
    T.assert_eq(status2, "success", "objective should complete once destination reached")
    T.assert_eq(err2, nil, "completed objective should not error")
    T.assert_true(service:is_active() == false, "service should clear active objective on success")
    T.assert_eq(tonumber(bb:get("objective.quest.queue_index", 0)), 2, "queue index should advance after completion")

    T.assert_true(selected_count >= 1, "objective selected event missing")
    T.assert_true(completed_count >= 1, "objective completed event missing")

    -- Failure path: provider has work but navigation is unavailable.
    bb:set("objective.gather.queue", {
        { x = 5, y = 5, z = 0, label = "GatherWP1" },
    })
    bb:set("objective.gather.queue_index", 1)
    local gather_provider = WaypointObjectiveProvider:new({
        mode_id = "gather",
        queue_key = "objective.gather.queue",
        index_key = "objective.gather.queue_index",
        loop_key = "objective.gather.loop",
        default_loop = false,
        arrive_distance = 2.0,
        reissue_secs = 0.0,
        timeout_secs = 30.0,
    })
    service:set_mode("gather", gather_provider, {
        -- intentionally no navigation service
    })
    local status3, err3 = service:tick(1002.0)
    T.assert_eq(status3, "failure", "objective should fail when navigation service is missing")
    T.assert_eq(err3, ErrorCodes.DEP_NAVCLIENT_MISSING, "missing navigation should surface dependency error")
    T.assert_true(failed_count >= 1, "objective failed event missing")

    return {
        sc016_objective_service = true,
    }
end

return { run = run }
