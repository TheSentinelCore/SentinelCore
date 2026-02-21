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
    local ok = sm:transition("running", { substate = "running.grind.scout" })
    T.assert_true(ok == true, "state transition to running failed")
    local invalid = sm:transition("running")
    T.assert_true(invalid == false, "invalid transition should fail")

    return {
        sc002_event_bus = true,
        sc002_blackboard = true,
        sc002_state_machine = true,
    }
end

return { run = run }
