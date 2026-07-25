-- kernel/fault_tracker.lua
-- Consecutive-fault counting and the 3-strike quarantine, in one place.
--
-- ADR 08 §5.1 lists "ErrorBoundary + Quarantine" as one kernel subsystem and notes the 3-strike
-- DEGRADED policy is "already implemented" in `runtime/module_registry.lua:232-270`.
--
-- WHY THIS FILE EXISTS. By the end of Phase 2 the same policy was implemented TWICE: inline in
-- ModuleRegistry:tick_all, and again in kernel/scheduler.lua's per-handler quarantine. Phase 3
-- needed it a third time for the plugin lifecycle. Three copies of "what counts as too many
-- faults" is three places for the number to drift, so the rule is extracted here and the copies
-- delegate.
--
-- THE RULE, unchanged from ModuleRegistry's original: only CONSECUTIVE faults degrade. A clean run
-- resets the streak, because a transient error that recurs once an hour must never accumulate into
-- a quarantine.

local FaultTracker = {}
FaultTracker.__index = FaultTracker

--- Kept at ModuleRegistry's original value. Below this a fault is transient and the subject keeps
--- running; at this streak it would re-fault every frame forever.
FaultTracker.DEFAULT_MAX_CONSECUTIVE = 3

function FaultTracker:new(opts)
    opts = opts or {}
    local o = setmetatable({}, FaultTracker)
    o._max = opts.max_consecutive or FaultTracker.DEFAULT_MAX_CONSECUTIVE
    o._streaks = {}
    o._records = {}
    o._quarantined = {}
    return o
end

---Record a fault against `key`.
---@return boolean quarantined_now true only on the transition, so callers publish once
---@return number streak
function FaultTracker:fault(key, err)
    local streak = (self._streaks[key] or 0) + 1
    self._streaks[key] = streak
    self._records[key] = { count = streak, last_error = tostring(err) }

    if streak >= self._max and not self._quarantined[key] then
        self._quarantined[key] = true
        return true, streak
    end
    return false, streak
end

---Record a clean run. Only consecutive faults degrade, so this clears the streak.
function FaultTracker:success(key)
    if self._streaks[key] and self._streaks[key] > 0 then
        self._streaks[key] = 0
        self._records[key] = nil
    end
end

function FaultTracker:is_quarantined(key)
    return self._quarantined[key] == true
end

function FaultTracker:streak(key)
    return self._streaks[key] or 0
end

function FaultTracker:record(key)
    return self._records[key]
end

---Lift a quarantine. Deliberately explicit: nothing un-quarantines itself, because a subject that
---faulted three times running has earned an operator's attention.
function FaultTracker:reinstate(key)
    self._quarantined[key] = nil
    self._streaks[key] = 0
    self._records[key] = nil
end

---@return table key -> { count, last_error, quarantined }
function FaultTracker:report()
    local out = {}
    for key, record in pairs(self._records) do
        out[key] = {
            count = record.count,
            last_error = record.last_error,
            quarantined = self._quarantined[key] == true,
        }
    end
    for key in pairs(self._quarantined) do
        out[key] = out[key] or { count = self._streaks[key] or 0, quarantined = true }
    end
    return out
end

return FaultTracker
