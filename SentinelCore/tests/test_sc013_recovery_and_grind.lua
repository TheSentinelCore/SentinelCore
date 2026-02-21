local T = require("tests/TestUtil")

local function run()
    local env = T.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local RecoveryService = require("services/RecoveryService")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local recovery = RecoveryService:new(bus, bb, {
        auto_restart_max_attempts = 3,
        auto_restart_backoff_secs = { 2, 5, 10 },
    })

    recovery:report_critical("CTX_UNRESOLVED")

    local cmd1 = recovery:update(1000)
    T.assert_eq(cmd1.action, "pause", "first escalation should pause")

    -- Attempt 1
    local cmd2 = recovery:update(1002)
    T.assert_eq(cmd2.action, "restart", "second command should restart")
    recovery:complete_restart_attempt(false)

    -- Attempt 2
    local cmd3 = recovery:update(1007)
    T.assert_eq(cmd3.action, "restart", "third command should restart again")
    recovery:complete_restart_attempt(false)

    -- Attempt 3
    local cmd4 = recovery:update(1017)
    T.assert_eq(cmd4.action, "restart", "fourth command should restart third time")
    recovery:complete_restart_attempt(false)

    -- Exhausted
    local cmd5 = recovery:update(1018)
    T.assert_eq(cmd5.action, "fail", "must hard fail after 3 attempts")
    T.assert_eq(cmd5.error_code, ErrorCodes.RECOVERY_ATTEMPTS_EXHAUSTED, "wrong exhausted error code")

    return {
        sc013_recovery_escalation = true,
    }
end

return { run = run }
