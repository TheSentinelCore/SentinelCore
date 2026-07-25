-- kernel/truth.lua
-- The tri-state a predicate returns, and the policy a call site applies to it.
--
-- ADR 07 §5.1.2: "`satisfied()` returns `Truth { True, False, Unknown }`, not `bool`."
-- ADR 08 §9.3: "Without an explicit unavailable value, every unreadable field silently
-- becomes a plausible-looking zero."
--
-- WHY A TYPE AND NOT A CONVENTION.
-- Phase 4 shipped three separate fail-open bugs -- `RuntimeCondition` falling through to
-- `true`, `is_spell_castable` treating "cannot say" as "yes", `execute_vendor` reporting a
-- sale that never happened. Those are not three bugs. They are one missing type, found
-- three times. Each site had a third answer to give ("I could not read that") and only two
-- values to say it with, so each picked a plausible one and moved on.
--
-- HONEST LIMIT -- READ THIS BEFORE TRUSTING THE TYPE.
-- Lua has no `__toboolean` metamethod. `if t then` cannot be intercepted for ANY table
-- value, so this type CANNOT make a careless truthiness test raise. What it can do is
-- refuse to be subtly wrong:
--
--   * If Unknown were `nil`, `if t then` would take the FALSE branch -- indistinguishable
--     from a real False. That is the collapse this type exists to prevent.
--   * Because all three are tables, `if t then` takes the TRUE branch for ALL of them,
--     including Truth.False. A careless test is therefore uniformly, loudly wrong on the
--     very first case a test exercises, instead of correct-looking until the one tick the
--     data goes unreadable.
--
-- Wrong-every-time beats wrong-once-in-a-thousand-ticks, but it is not a guarantee. The
-- guarantee is the static audit (Deliverable 3), which is why that audit exists.
--
-- Everything else here is locked down so the NEAR misses do raise: field access,
-- mutation, calling, arithmetic and concatenation all error.

local Truth = {}

-- ---------------------------------------------------------------------------
-- The three values
-- ---------------------------------------------------------------------------

local function make_value(name)
    local value = {}
    local meta = {
        __index = function(_, key)
            error("Truth." .. name .. " has no field '" .. tostring(key)
                .. "' -- resolve it with Truth.resolve(value, policy) instead", 2)
        end,
        __newindex = function()
            error("Truth." .. name .. " is immutable", 2)
        end,
        __call = function()
            error("Truth." .. name .. " is a value, not a function", 2)
        end,
        __tostring = function() return "Truth." .. name end,
        __len = function() error("Truth." .. name .. " has no length", 2) end,
        __concat = function()
            error("Truth." .. name .. " does not concatenate -- use tostring()", 2)
        end,
        __add = function() error("Truth." .. name .. " is not a number", 2) end,
        -- Protects the singleton from having its own guarantees rewritten underneath it.
        __metatable = "Truth",
    }
    return setmetatable(value, meta)
end

Truth.True = make_value("True")
Truth.False = make_value("False")
Truth.Unknown = make_value("Unknown")

local IS_TRUTH = {
    [Truth.True] = true,
    [Truth.False] = true,
    [Truth.Unknown] = true,
}

---@param value any
---@return boolean
function Truth.is(value)
    -- Indexing IS_TRUTH *by* the value never touches the value's own __index.
    return value ~= nil and IS_TRUTH[value] == true
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

---Lift a readable boolean -- or an unreadable `nil` -- into the tri-state.
---
---`nil` becomes Unknown rather than False. That single mapping is the whole point: a
---sensor that could not read a value has not observed a false one.
---@param value boolean|nil|table
---@return table Truth
function Truth.of(value)
    if value == nil then return Truth.Unknown end
    if IS_TRUTH[value] then return value end
    if value == true then return Truth.True end
    if value == false then return Truth.False end
    -- A number or string arriving here means a predicate handed back raw SDK output
    -- without deciding what it meant. `0` and `-1` are both truthy in Lua (ADR 07 §5.1.2
    -- documents `is_complete == -1` reading as COMPLETE), so coercing would rebuild the
    -- exact bug this type removes.
    error("Truth.of expects a boolean or nil, got " .. type(value)
        .. " -- decide what the value MEANS before lifting it", 2)
end

local function require_truth(value, who, position)
    if not Truth.is(value) then
        error(who .. " expects a Truth value, got " .. type(value)
            .. (position and (" at argument " .. position) or "")
            .. " -- a predicate that returns a raw boolean has not been ported yet", 3)
    end
    return value
end

-- ---------------------------------------------------------------------------
-- Kleene combinators
-- ---------------------------------------------------------------------------
--
-- Strong Kleene three-valued logic. The rule that matters, and the one a boolean port
-- always gets wrong: a KNOWN answer beats an unreadable one when it settles the result.
-- `False and Unknown` is False, because no value of the unreadable conjunct could rescue
-- it. Collapsing that to Unknown would block a decision that was never in doubt.

---@vararg table Truth values
---@return table Truth
function Truth.and_(...)
    local n = select("#", ...)
    local saw_unknown = false
    for i = 1, n do
        local value = require_truth((select(i, ...)), "Truth.and_", i)
        if value == Truth.False then
            return Truth.False -- short-circuits: nothing later can change this
        elseif value == Truth.Unknown then
            saw_unknown = true
        end
    end
    if saw_unknown then return Truth.Unknown end
    return Truth.True -- vacuously true for an empty conjunction
end

---@vararg table Truth values
---@return table Truth
function Truth.or_(...)
    local n = select("#", ...)
    local saw_unknown = false
    for i = 1, n do
        local value = require_truth((select(i, ...)), "Truth.or_", i)
        if value == Truth.True then
            return Truth.True
        elseif value == Truth.Unknown then
            saw_unknown = true
        end
    end
    if saw_unknown then return Truth.Unknown end
    return Truth.False -- vacuously false for an empty disjunction
end

---Negation preserves ignorance: `not Unknown` is Unknown, never a manufactured certainty.
---@param value table Truth
---@return table Truth
function Truth.not_(value)
    require_truth(value, "Truth.not_")
    if value == Truth.True then return Truth.False end
    if value == Truth.False then return Truth.True end
    return Truth.Unknown
end

-- ---------------------------------------------------------------------------
-- Unknown policy (ADR 07 §5.1.2)
-- ---------------------------------------------------------------------------
--
-- Adjacently tagged `{ type, payload }`, matching the Rust `UnknownPolicy` on the wire.
-- This repo has already been burned by an externally-tagged enum crossing into Lua
-- (`RuntimeCondition` shipped as `{"ClassIs":"Mage"}` and every non-unit condition fell
-- through to fail-open true), so the shape is pinned on both sides deliberately.

Truth.Policy = {}

Truth.Policy.Block = { type = "Block", payload = nil }
Truth.Policy.TreatFalse = { type = "TreatFalse", payload = nil }
Truth.Policy.TreatTrue = { type = "TreatTrue", payload = nil }

---@param budget_ticks number Consecutive unreadable ticks tolerated before escalating.
---@return table policy
function Truth.Policy.Defer(budget_ticks)
    if type(budget_ticks) ~= "number" or budget_ticks ~= math.floor(budget_ticks)
        or budget_ticks < 1 then
        error("Truth.Policy.Defer requires a positive integer budget_ticks", 2)
    end
    return { type = "Defer", payload = { budget_ticks = budget_ticks } }
end

local KNOWN_POLICIES = { Block = true, Defer = true, TreatFalse = true, TreatTrue = true }

---Diagnostic sink. Assigned by the host; nil means "nobody is listening yet".
---Only ever invoked for the fail-open direction -- see resolve().
Truth.on_diagnostic = nil

local function emit(diagnostic)
    local sink = Truth.on_diagnostic
    if type(sink) == "function" then
        pcall(sink, diagnostic)
    end
end

---Apply a call site's declared policy to a tri-state.
---
---There is NO default policy. ADR 07 §5.1.2 makes `Treat(True)` "never a default", and the
---cheapest way to guarantee that is to have no default at all -- every site says what it
---wants Unknown to mean, in the open, where a reviewer can see it.
---
---@param value table Truth
---@param policy table One of Truth.Policy.*
---@return boolean|nil decision, string|nil reason  -- decision is nil when the site must not act
function Truth.resolve(value, policy)
    require_truth(value, "Truth.resolve")

    if type(policy) ~= "table" or not KNOWN_POLICIES[policy.type] then
        error("Truth.resolve requires an explicit UnknownPolicy "
            .. "(Block | Defer | TreatFalse | TreatTrue) -- there is no default", 2)
    end

    -- Policy governs Unknown ONLY. A readable answer is never overridden.
    if value == Truth.True then return true, nil end
    if value == Truth.False then return false, nil end

    local kind = policy.type
    if kind == "TreatFalse" then
        return false, nil
    elseif kind == "TreatTrue" then
        -- The fail-open direction. It announces itself EVERY time it is actually taken,
        -- and stays silent when nothing was unknown, so the signal keeps its meaning.
        emit({
            kind = "unknown_treated_as_true",
            detail = "a predicate could not be read and the call site chose to proceed",
        })
        return true, nil
    elseif kind == "Block" then
        return nil, "blocked"
    end
    return nil, "defer"
end

-- ---------------------------------------------------------------------------
-- Defer budget
-- ---------------------------------------------------------------------------
--
-- §5.1.2: Defer "yields this tick, retries next; after `unknown_budget` ticks escalates to
-- `Block`." That escalation needs memory, which `resolve` deliberately does not have --
-- so a gate holds it per call site.

local Gate = {}
Gate.__index = Gate

---@param policy table One of Truth.Policy.*
---@return table gate
function Truth.gate(policy)
    if type(policy) ~= "table" or not KNOWN_POLICIES[policy.type] then
        error("Truth.gate requires an explicit UnknownPolicy", 2)
    end
    return setmetatable({ _policy = policy, _unknown_streak = 0 }, Gate)
end

---@param value table Truth
---@return boolean|nil decision, string|nil reason
function Gate:decide(value)
    require_truth(value, "gate:decide")

    if value ~= Truth.Unknown then
        -- The budget counts CONSECUTIVE unreadable ticks. A readable one clears it --
        -- otherwise a long-lived gate eventually blocks on data that has been fine for
        -- hours, having accumulated stray Unknowns across unrelated loading screens.
        self._unknown_streak = 0
        return Truth.resolve(value, self._policy)
    end

    if self._policy.type ~= "Defer" then
        return Truth.resolve(value, self._policy)
    end

    self._unknown_streak = self._unknown_streak + 1
    if self._unknown_streak > self._policy.payload.budget_ticks then
        -- Escalation is to Block, never to a decision: a spent budget means we still do
        -- not know, and waiting longer stopped being useful. It does not mean "assume".
        return nil, "blocked"
    end
    return nil, "defer"
end

return Truth
