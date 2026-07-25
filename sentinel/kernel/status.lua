-- kernel/status.lua
-- ADR 08 §8.3 / §2.10 -- the return-value rule.
--
-- "A tier boundary is only as useful as the richest value that can cross it."
--
-- §2.10 diagnoses LazyBot with this: its Plugin tier is decorative because every method returns
-- `void`, and its State tier is half-working because `NeedToRun` is a rich INBOUND signal with no
-- outbound counterpart -- `DoWork()` returns nothing, so the scheduler learns nothing from having
-- run it. §8.3's correction: "EVERY entry point returns a status to the host. A `tick` that
-- returns `void` is an observer, not a participant."
--
-- And the part that has to be enforced rather than documented: "A `tick` returning `nil` is a
-- MANIFEST VALIDATION ERROR, NOT A DEFAULT." Treating nil as DONE would silently re-create
-- LazyBot's void tier -- the scheduler would carry on having learned nothing, which is exactly
-- the shape this rule exists to forbid.

local Status = {}

Status.DONE = "DONE"       -- finished; the host may move on
Status.RUNNING = "RUNNING" -- still working; call me again next tick
Status.YIELD = "YIELD"     -- I could run but I am deferring; the scheduler may drop a band
Status.BLOCKED = "BLOCKED" -- I cannot proceed, and here is why (carries a reason)
Status.FAILED = "FAILED"   -- I tried and could not

Status.ALL = { Status.DONE, Status.RUNNING, Status.YIELD, Status.BLOCKED, Status.FAILED }

local VALID = {}
for _, s in ipairs(Status.ALL) do VALID[s] = true end

---@return boolean
function Status.is_valid(value)
    return VALID[value] == true
end

---Normalise an entry point's return into `(status, reason)`.
---
---A plugin may return either `"BLOCKED"` or `"BLOCKED", "no path to vendor"`. `BLOCKED` without a
---reason is accepted but flagged: §8.3 says the reason string "is what feeds the runner cockpit's
---blocked-reason display", so a reasonless BLOCKED produces a cockpit that says only "blocked".
---@return string|nil status, string|nil reason_or_error
function Status.normalize(value, reason)
    if value == nil then
        -- §8.3, enforced. Not a default.
        return nil, "tick_returned_nil"
    end
    if not VALID[value] then
        return nil, "invalid_status:" .. tostring(value)
    end
    if value == Status.BLOCKED then
        return value, reason or "unspecified"
    end
    return value, reason
end

return Status
