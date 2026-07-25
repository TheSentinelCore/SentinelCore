-- kernel/movement_release.lua
-- Kernel-enforced release of every movement key.
--
-- ================================================================================
-- WHY THIS IS SAFETY-CRITICAL, NOT HOUSEKEEPING (ADR 08 §2.8)
-- ================================================================================
-- "There is NO core.input.move(x,y,z) and NO click-to-move. Movement is stateful key
--  start/stop pairs. Consequence: if a MOVEMENT lease is revoked without the holder
--  releasing its keys, THE CHARACTER KEEPS RUNNING. on_revoke is not a courtesy callback;
--  it is the only thing standing between a preemption and the bot sprinting into a lake.
--  The broker must therefore treat MOVEMENT revocation as a KERNEL-ENFORCED KEY-RELEASE,
--  not as a request the plugin may ignore."
--
-- The broker calls this AFTER `on_revoke`, unconditionally -- whether on_revoke succeeded,
-- threw, or was never provided.
--
-- ================================================================================
-- THIS IS THE ONLY `core.input.*` CALL SITE IN THE KERNEL
-- ================================================================================
-- Deliberately fenced to one file so the boundary is greppable:
--     rg "core\.input" sentinel/kernel/     -> this file, nothing else
-- Plugins never reach input at all; they emit intents (ADR 08 §3.2). If a second call site
-- ever appears in kernel/, ambient authority has leaked back in.
--
-- ================================================================================
-- DECISION: UNCONDITIONAL RELEASE, NOT TRACKED RELEASE
-- ================================================================================
-- Both are defensible (the ADR leaves it open), so here is the reasoning.
--
-- TRACKED would mean the broker records which keys a holder pressed and stops only those.
-- It is cheaper -- one or two SDK calls instead of eight -- and it reads more precisely.
--
-- UNCONDITIONAL wins on the only axis that matters here: FAILURE DIRECTION.
--   * The kernel cannot observe key state. `is_key_pressed` reports the HUMAN's keyboard,
--     not keys the injector pressed synthetically, so a tracking table can never be
--     validated against reality -- only trusted.
--   * Tracking can be wrong in the dangerous direction. A plugin that pressed a key through
--     a path the kernel did not record, a record lost to a mid-tick fault, or a stale entry
--     after a reload all produce UNDER-release: the character keeps running and the kernel
--     believes it stopped. Unconditional release cannot under-release.
--   * The cost is bounded and lands where it does not matter. Eight calls, only on
--     revocation -- not per frame. Stopping a key that was never pressed is a documented
--     no-op, so the wasted calls are inert.
--
-- A safety net whose correctness depends on bookkeeping being right is not a safety net.
-- Revisit this only if profiling shows revocation frequency is itself a problem, and note
-- that frequent revocation is the bug in that case, not the eight calls.

local MovementRelease = {}

--- Every documented movement key pair (docs/SylvannasAPI/dev/api/input.md:147-161).
---
--- ADR 08 §2.8 names only `move_forward`, `turn_left` and `strafe_*`. Releasing just those
--- would leave `move_backward`, `move_up` and `move_down` held -- and "mostly stopped" is
--- indistinguishable from "not stopped" once the character is in a lake.
MovementRelease.KEYS = {
    "move_forward",
    "move_backward",
    "move_up",
    "move_down",
    "turn_left",
    "turn_right",
    "strafe_left",
    "strafe_right",
}

---Release every movement key. Never throws, never partially aborts, safe to call twice.
---@param input table|nil The `core.input` table; defaults to the live SDK.
---@return table report { attempted, released, missing, errors, failed_keys }
function MovementRelease.release_all(input)
    if input == nil then
        input = core and core.input or nil
    end

    local report = {
        attempted = 0,
        released = 0,
        missing = 0,
        errors = 0,
        failed_keys = {},
    }

    for _, key in ipairs(MovementRelease.KEYS) do
        local fn = input and input[key .. "_stop"] or nil
        if type(fn) ~= "function" then
            -- A partial injector build. Counted separately from an error: nothing went
            -- wrong, the capability simply is not there.
            report.missing = report.missing + 1
        else
            report.attempted = report.attempted + 1
            -- Each call is isolated. One dead SDK function must not cost the other seven
            -- keys their release -- that is the whole reason this loop pcalls per key
            -- rather than wrapping the sweep.
            local ok, err = pcall(fn)
            if ok then
                report.released = report.released + 1
            else
                report.errors = report.errors + 1
                report.failed_keys[#report.failed_keys + 1] = { key = key, error = tostring(err) }
            end
        end
    end

    return report
end

return MovementRelease
