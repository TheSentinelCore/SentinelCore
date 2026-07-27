-- sentinel/ui/async_slot.lua
-- One poll-until-resolved slot, shared by every IDE panel that fetches from a server.
--
-- WHY THIS FILE EXISTS
-- --------------------
-- `QueryClient:_get` is ASYNC in the injector: the first call fires the request and answers
-- `(nil, true)` -- "pending, ask again next tick". Every data binding had hand-rolled its own
-- reaction to that, and all three versions made the same mistake in a different place: they cleared
-- the flag that schedules the next tick BEFORE the fetch had resolved (`ide_panels.lua:337-338`,
-- `database_state.lua:161-162`). The tick that would have collected the answer therefore never ran,
-- so a panel froze on its first pending fetch and showed an idle view forever. Offline it was
-- invisible, because the offline mocks resolved synchronously and the pending branch was dead code.
--
-- The rule this file enforces, in one place instead of three:
--
--     a flag may clear ONLY on resolution -- data stored, or an error recorded.
--
-- CONTRACT
-- --------
--   `fn` is the fetch, and it returns exactly what `QueryClient:_get` returns:
--     data          -> resolved
--     (nil, true)   -> in flight, poll again
--     (nil, nil)    -> resolved to nothing (404, transport failure, dead server) -- terminal
--
--   `poll` answers `(status, data)` where status is one of:
--     "ok"      the fetch resolved; `data` is the value and `slot.data` caches it
--     "pending" still in flight; the owner's `_dirty` has been RE-ARMED, so the next tick polls
--     "failed"  resolved to nothing; `owner.error` names the lookup
--     "timeout" `max_ticks` polls went by without an answer; `owner.error` names the lookup
--
-- The owner is a panel state (`explorer_state`, `properties_state`, `database_state`, ...). The slot
-- only ever touches three of its fields -- `_dirty`, `loading`, `error` -- which every panel state
-- already has and every `build`/`build_plan` already projects, so a slot costs no new render branch.

local AsyncSlot = {}
AsyncSlot.__index = AsyncSlot

-- Roughly two seconds at 60 fps of ticks. A fetch still unanswered by then is a server that is not
-- coming back on this attempt, and an unbounded poll is a panel that spins forever with nothing on
-- screen to say why -- the same silence this file exists to remove, just slower.
AsyncSlot.DEFAULT_MAX_TICKS = 120

---@param opts table|nil { label = string, owner = table|nil, max_ticks = number|nil }
function AsyncSlot.new(opts)
    opts = opts or {}
    return setmetatable({
        label = tostring(opts.label or "fetch"),
        owner = opts.owner,
        max_ticks = tonumber(opts.max_ticks) or AsyncSlot.DEFAULT_MAX_TICKS,
        status = "idle",
        ticks = 0,
        data = nil,
        -- The exact string this slot last wrote to `owner.error`, so a later success clears its own
        -- message and never another slot's. Two slots on one state fail independently.
        _message = nil,
    }, AsyncSlot)
end

function AsyncSlot:is_pending() return self.status == "pending" end

---Forget an in-flight fetch. Called when the thing being fetched CHANGES (a new selection), so the
---abandoned request's tick count cannot expire the fresh one early.
function AsyncSlot:reset()
    self.status = "idle"
    self.ticks = 0
    self.data = nil
    if self.owner and self.owner.error == self._message then self.owner.error = nil end
    self._message = nil
end

function AsyncSlot:_fail(suffix, status)
    self.status = status
    self.ticks = 0
    self.data = nil
    self._message = self.label .. " " .. suffix
    local owner = self.owner
    if owner then
        owner.loading = false
        owner.error = self._message
    end
    return self.status, nil
end

---Poll one tick of an async fetch.
---@param fn function returns `data` | `(nil, true)` pending | `(nil, nil)` failed
---@return string status "ok" | "pending" | "failed" | "timeout"
---@return any data the resolved value, only when status is "ok"
function AsyncSlot:poll(fn)
    if type(fn) ~= "function" then return self:_fail("has no fetch to run", "failed") end

    -- Contained on purpose: a binding's `on_tick` runs inside the shell's pcall, but a throw there
    -- skips every OTHER panel refresh in the same tick. A fetch that raises is a failed fetch.
    local ok, data, pending = pcall(fn)
    if not ok then return self:_fail("raised: " .. tostring(data), "failed") end

    if data ~= nil then
        self.status = "ok"
        self.ticks = 0
        self.data = data
        local owner = self.owner
        if owner then
            owner.loading = false
            if owner.error == self._message then owner.error = nil end
        end
        self._message = nil
        return "ok", data
    end

    if pending then
        self.ticks = self.ticks + 1
        if self.ticks > self.max_ticks then
            return self:_fail("timed out after " .. self.max_ticks .. " ticks", "timeout")
        end
        self.status = "pending"
        local owner = self.owner
        if owner then
            -- THE LINE THE WHOLE FILE IS FOR. Without it the binding's `on_tick` returns early next
            -- tick and the answer is never collected.
            owner._dirty = true
            owner.loading = true
        end
        return "pending"
    end

    return self:_fail("failed", "failed")
end

return AsyncSlot
