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

--- Movement key state. Declared HERE, above `release_all`, because Lua resolves an undeclared
--- name to a GLOBAL: written below their first use these would be two globals that
--- `release_all` clears and the reconciler never reads. See the reconciler section at the
--- bottom of this file for what they mean and why they live in this module.
---
--- nil means "stopped". Otherwise a set of key -> true drawn from MovementRelease.KEYS.
local _desired = nil

--- What the kernel believes it has pressed. An optimisation, not a safety record.
local _held = {}

--- The kernel's ONE resolution of the live SDK input table. Both `release_all` and
--- `reconcile` route through here rather than each reaching for `core.input` themselves --
--- "exactly one place" is asserted by
--- tests/kernel/test_intent_executors.test_the_kernel_resolves_core_input_in_exactly_one_place,
--- and it counts call SITES, not files. Two resolutions in this file would already be one too
--- many.
local function live_input()
    return core and core.input or nil
end

---Release every movement key. Never throws, never partially aborts, safe to call twice.
---@param input table|nil The `core.input` table; defaults to the live SDK.
---@return table report { attempted, released, missing, errors, failed_keys }
function MovementRelease.release_all(input)
    if input == nil then
        input = live_input()
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

    -- The desire dies with the keys. This is the line that makes a `move` intent safe to
    -- revoke: without it the reconciler would press everything straight back down on the next
    -- tick, and §2.8's force-release would hold for exactly one frame.
    _desired = nil
    _held = {}

    return report
end

-- ---------------------------------------------------------------------------
-- Desired-state reconciliation (ADR 08 §3.2, Phase 4b)
-- ---------------------------------------------------------------------------
--
-- ================================================================================
-- WHY `move` IS DECLARATIVE AND LIVES HERE
-- ================================================================================
-- The imperative alternative -- `move_forward_start` and `move_forward_stop` as two intent
-- types -- puts a start/stop PAIR in plugin hands, and a pair is a thing that can be left
-- half-finished. Every leak of a held movement key is a missing second half.
--
-- A desired state has no second half. The plugin says what it wants; the kernel reconciles
-- actual keys against that each tick; revocation clears the desire and the release falls out
-- as a consequence. There is nothing to forget to call.
--
-- It lives in THIS module, next to the force-release, because both write the same key state.
-- Two owners of that state is exactly how the §2.8 guarantee rots: the releaser lifts a key
-- and a reconciler that still wants it down presses it again one tick later. Co-locating them
-- means `release_all` clears the desire without the broker needing to know the reconciler
-- exists -- no new wiring on the safety path.
--
-- ================================================================================
-- WHY THE DESIRE IS A KEY SET, NOT A POINT
-- ================================================================================
-- "Move toward this point" cannot be honoured by MOVEMENT alone. With key-based movement and
-- no click-to-move (§2.8), reaching a point requires TURNING -- and turning is the FACING
-- channel, held under a separate lease so a rotation can face while an activity moves (§6.1).
-- A `move` intent that quietly turned the character would be acting outside the lease that
-- authorised it, which is the failure the channel split exists to prevent.
--
-- So `move` names keys, and a plugin that wants to run AT something emits `face` as well --
-- two intents, two channels, two leases, each refusable on its own.
--
-- ================================================================================
-- `_held` IS NOT A SAFETY MECHANISM
-- ================================================================================
-- The header above rejects TRACKED release because a tracking table can never be validated
-- against reality. That verdict stands: `_held` exists ONLY to avoid re-pressing a key that is
-- already down, and nothing safety-critical reads it. `release_all` remains unconditional and
-- resets it, so a `_held` that has drifted out of sync costs a redundant SDK call, never a
-- missed release.

local KEY_SET = {}
for _, key in ipairs(MovementRelease.KEYS) do KEY_SET[key] = true end

---Is `key` one of the documented movement keys? Exposed so the MOVEMENT gate can validate a
---desire WITHOUT storing it -- a gate that mutated state would leave a desire behind on an
---intent a later gate went on to refuse.
---@param key any
---@return boolean
function MovementRelease.is_movement_key(key)
    return KEY_SET[key] == true
end

---The movement state a lease holder wants. Replaces the previous desire wholesale -- there is
---no incremental "also press this", because a partial update is how you end up with a key
---nobody remembers asking for.
---@param keys table|nil key -> true, or nil for stopped
---@return boolean accepted, string|nil reason
function MovementRelease.set_desired(keys)
    if keys == nil then
        _desired = nil
        return true
    end
    if type(keys) ~= "table" then return false, "desired_not_a_table" end

    -- Validate BEFORE storing: a half-accepted desire containing one good key and one typo is
    -- worse than a refusal, because it moves the character in a direction nobody asked for.
    local clean = {}
    local any = false
    for key, wanted in pairs(keys) do
        if not KEY_SET[key] then return false, "unknown_movement_key" end
        if wanted then
            clean[key] = true
            any = true
        end
    end

    _desired = any and clean or nil
    return true
end

---@return table|nil the current desire
function MovementRelease.desired()
    if _desired == nil then return nil end
    local out = {}
    for key in pairs(_desired) do out[key] = true end
    return out
end

---Drive actual keys toward the desired state. Runs every tick, after COMMIT.
---
---Never throws and never partially aborts, for the same reason `release_all` does not: this
---runs on the movement path, and one dead SDK function must not cost the other keys their
---transition.
---@param input table|nil defaults to the live SDK
---@return table report { pressed, released, missing, errors, failed_keys }
function MovementRelease.reconcile(input)
    if input == nil then
        input = live_input()
    end

    local report = { pressed = {}, released = {}, missing = 0, errors = 0, failed_keys = {} }

    local function drive(key, suffix, bucket)
        local fn = input and input[key .. suffix] or nil
        if type(fn) ~= "function" then
            report.missing = report.missing + 1
            return false
        end
        local ok, err = pcall(fn)
        if not ok then
            report.errors = report.errors + 1
            report.failed_keys[#report.failed_keys + 1] =
                { key = key, action = suffix, error = tostring(err) }
            return false
        end
        bucket[#bucket + 1] = key
        return true
    end

    -- Release before press. If a desire swaps strafe_left for strafe_right, lifting first
    -- means the two are never held together -- pressing first would put the character in a
    -- state no lease ever asked for, for the width of one loop.
    for _, key in ipairs(MovementRelease.KEYS) do
        local wanted = _desired ~= nil and _desired[key] == true
        if _held[key] and not wanted then
            if drive(key, "_stop", report.released) then _held[key] = nil end
        end
    end

    for _, key in ipairs(MovementRelease.KEYS) do
        local wanted = _desired ~= nil and _desired[key] == true
        if wanted and not _held[key] then
            if drive(key, "_start", report.pressed) then _held[key] = true end
        end
    end

    return report
end

return MovementRelease
