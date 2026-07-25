-- kernel/intent_queue.lua
-- The commit choke point. Plugins emit intents; the kernel decides what actually happens.
--
-- ================================================================================
-- WHY THE KERNEL COMMITS AND PLUGINS DO NOT (ADR 08 §3.2, justified by §2.6)
-- ================================================================================
-- "core.input.cast_target_spell performs ZERO validation -- no range, no facing, no ready
--  check; it only sends a packet. That is exactly the gap the commit stage exists to fill."
--
-- So every game-affecting action funnels through here: dedupe -> gate -> generation-check
-- -> execute, with a named outcome for every intent that entered.
--
-- ================================================================================
-- PHASE 1 SCOPE
-- ================================================================================
-- Structure and gate hooks ONLY. This file contains NO `core.input.*` call and registers no
-- executors. Real casting arrives with the ControlBroker (Phase 2), because an intent is
-- only authorized by the lease that produced it, and leases do not exist yet. The
-- generation validator seam (ADR 08 §6.1) is present and inert for the same reason.
--
-- ================================================================================
-- THE RULE THAT SHAPES EVERY BRANCH: FAIL CLOSED, AND SAY WHY
-- ================================================================================
-- ADR 08 §12, on LazyBot: "GrindingProfile.LoadFile is eight independent try {} catch {}
-- blocks with EMPTY CATCH BODIES ... so a profile can be 90% broken and still 'load'."
-- Nothing here drops an intent quietly. Every intent that enters `commit` leaves in exactly
-- one bucket -- committed, deduped, rejected or failed -- and the last three carry a reason
-- string. A gate that throws REJECTS; it never fails open.

local Bands = require("kernel/bands")

local IntentQueue = {}
IntentQueue.__index = IntentQueue

-- ADR 08 §6.2 bands live in kernel/bands.lua, which is the single authority. This module
-- re-exports rather than copying: two independent copies of the same table is exactly how
-- gating silently stops agreeing with arbitration.
IntentQueue.BANDS = Bands.BANDS

local IMMEDIATE_MIN_BAND = Bands.IMMEDIATE_MIN_PRIORITY

---Map a Sentinel band onto the injector's own `spell_queue` arbitration (ADR 08 §6.3).
---Delegates to kernel/bands.lua -- see there for why the kernel maps onto the injector's
---convention rather than owning the bottom of the casting stack.
---@param band number
---@return number 1 or 7
function IntentQueue.spell_queue_priority(band)
    return Bands.spell_queue_priority(band)
end

function IntentQueue:new()
    local o = setmetatable({}, IntentQueue)
    o._pending = {}
    o._gates = {}
    o._executors = {}
    o._generation_validator = nil
    o._sequence = 0
    return o
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

---Add a gate. Gates run in registration order; the first refusal short-circuits.
---@param name string Attribution for the rejection record
---@param fn function (intent, snapshot) -> boolean, string|nil
function IntentQueue:add_gate(name, fn)
    self._gates[#self._gates + 1] = { name = name, fn = fn }
end

---@param intent_type string
---@param fn function (intent, snapshot) -> boolean, string|nil
function IntentQueue:register_executor(intent_type, fn)
    self._executors[intent_type] = fn
end

---Install the ControlBroker's lease-generation check (ADR 08 §6.1). Absent in Phase 1.
---@param fn function (intent) -> boolean
function IntentQueue:set_generation_validator(fn)
    self._generation_validator = fn
end

-- ---------------------------------------------------------------------------
-- Submission
-- ---------------------------------------------------------------------------

--- Dedupe identity: the same action, requested twice in one tick, is one action.
--- Owner is deliberately NOT part of the key -- two plugins asking for the same cast is
--- exactly the collision this queue exists to collapse.
local function dedupe_key(intent)
    local parts = { tostring(intent.type) }
    local payload = intent.payload
    if type(payload) == "table" then
        local keys = {}
        for k in pairs(payload) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            parts[#parts + 1] = k .. "=" .. tostring(payload[k])
        end
    end
    return table.concat(parts, "|")
end

---Submit an intent for this tick.
---@param intent table { type, owner, band, payload, immediate?, generation? }
---@return boolean accepted, string|nil reason
function IntentQueue:submit(intent)
    if type(intent) ~= "table" then return false, "not_a_table" end
    if type(intent.type) ~= "string" or intent.type == "" then return false, "missing_type" end
    if type(intent.owner) ~= "string" or intent.owner == "" then return false, "missing_owner" end
    if type(intent.band) ~= "number" then return false, "missing_band" end
    if intent.band < 0 or intent.band > 99 then return false, "band_out_of_range" end
    if intent.immediate and intent.band < IMMEDIATE_MIN_BAND then
        -- ADR 08 §3.2 -- immediate is a latency mitigation for reactive abilities, not a
        -- general-purpose queue-jump.
        return false, "immediate_requires_band_70"
    end

    self._sequence = self._sequence + 1
    intent._sequence = self._sequence
    intent._dedupe_key = dedupe_key(intent)
    self._pending[#self._pending + 1] = intent
    return true
end

function IntentQueue:pending_count()
    return #self._pending
end

-- ---------------------------------------------------------------------------
-- Commit
-- ---------------------------------------------------------------------------

--- Run one gate without letting it escape. A gate that throws REJECTS the intent: the
--- commit stage exists precisely because the raw SDK call validates nothing, so a gate we
--- could not evaluate is a gate we must assume said no.
local function run_gate(gate, intent, snapshot)
    local ok, passed, reason = pcall(gate.fn, intent, snapshot)
    if not ok then
        return false, "gate_error"
    end
    if passed then
        return true, nil
    end
    return false, reason or "gate_rejected"
end

---Dedupe -> gate -> generation-check -> execute. Drains the queue.
---@param snapshot table The tick's frozen snapshot (kernel/snapshot.lua)
---@return table report { committed, deduped, rejected, failed }
function IntentQueue:commit(snapshot)
    local report = { committed = {}, deduped = {}, rejected = {}, failed = {} }
    local pending = self._pending
    self._pending = {}

    -- 1. Dedupe. The highest band wins, because that is the claim with the most authority;
    --    submission order breaks ties so a tick stays deterministic.
    local winners = {}
    local order = {}
    for _, intent in ipairs(pending) do
        local key = intent._dedupe_key
        local incumbent = winners[key]
        if incumbent == nil then
            winners[key] = intent
            order[#order + 1] = key
        elseif intent.band > incumbent.band then
            winners[key] = intent
            report.deduped[#report.deduped + 1] = incumbent
        else
            report.deduped[#report.deduped + 1] = intent
        end
    end

    local queue = {}
    for _, key in ipairs(order) do queue[#queue + 1] = winners[key] end

    -- 2. Order by band, descending; submission sequence breaks ties (ADR 08 §6.2).
    table.sort(queue, function(a, b)
        if a.band ~= b.band then return a.band > b.band end
        return a._sequence < b._sequence
    end)

    for _, intent in ipairs(queue) do
        local rejected = false

        -- 3. Gates: GCD / range / LoS / facing / rate (ADR 08 §3.2). `immediate` intents
        --    go through the same gates -- the flag buys ordering, not impunity.
        for _, gate in ipairs(self._gates) do
            local passed, reason = run_gate(gate, intent, snapshot)
            if not passed then
                report.rejected[#report.rejected + 1] =
                    { intent = intent, gate = gate.name, reason = reason }
                rejected = true
                break
            end
        end

        -- 4. Generation check (ADR 08 §6.1): closes the revocation race where an intent
        --    emitted under a now-dead lease still commits.
        if not rejected and self._generation_validator then
            local ok, valid = pcall(self._generation_validator, intent)
            if not ok or not valid then
                report.rejected[#report.rejected + 1] =
                    { intent = intent, gate = "generation", reason = "stale_generation" }
                rejected = true
            end
        end

        if not rejected then
            -- 5. Execute. An intent type with no registered executor is REFUSED by name --
            --    never dropped on the floor (ADR 08 §12).
            local executor = self._executors[intent.type]
            if executor == nil then
                report.rejected[#report.rejected + 1] =
                    { intent = intent, gate = "executor", reason = "no_executor" }
            else
                local ok, succeeded, reason = pcall(executor, intent, snapshot)
                if not ok then
                    report.failed[#report.failed + 1] =
                        { intent = intent, reason = "executor_error", error = tostring(succeeded) }
                elseif succeeded then
                    report.committed[#report.committed + 1] = intent
                else
                    report.failed[#report.failed + 1] =
                        { intent = intent, reason = reason or "executor_refused" }
                end
            end
        end
    end

    return report
end

return IntentQueue
