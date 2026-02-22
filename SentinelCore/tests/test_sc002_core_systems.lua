local T = require("tests/TestUtil")

local function run()
    T.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local StateMachine = require("core/StateMachine")

    local bus = EventBus:new()
    local value = 0
    local id = bus:on("x", function(data) value = data end)
    bus:emit("x", 5)
    T.assert_eq(value, 5, "event publish failed")
    bus:off(id)

    local bb = Blackboard:new(bus)
    local seen = false
    bb:subscribe("hp", function(_, nv) if nv == 99 then seen = true end end)
    bb:set("hp", 99)
    T.assert_true(seen, "blackboard watcher failed")

    local sm = StateMachine:new(bus)
    local ok = sm:transition("running", { mode_id = "grind", substate = "running.grind.scout" })
    T.assert_true(ok == true, "state transition to running failed")
    local set_ok = sm:set_substate("running.grind.combat")
    T.assert_true(set_ok == true, "running substate update failed")
    local pause_ok = sm:transition("paused")
    T.assert_true(pause_ok == true, "pause transition failed")
    sm:register_mode("quest", { "scout", "objective", "combat" }, "scout")
    local resume_ok = sm:transition("running", { mode_id = "quest", substate = "running.quest.scout" })
    T.assert_true(resume_ok == true, "quest mode running transition failed")
    local objective_substate = sm:set_substate("running.quest.objective")
    T.assert_true(objective_substate == true, "quest objective substate should be valid")
    local invalid_substate = sm:set_substate("running.quest.vendor")
    T.assert_true(invalid_substate == false, "invalid quest substate should fail")
    local invalid = sm:transition("running")
    T.assert_true(invalid == false, "invalid transition should fail")

    return {
        sc002_event_bus = true,
        sc002_blackboard = true,
        sc002_state_machine = true,
    }
end

return { run = run }
