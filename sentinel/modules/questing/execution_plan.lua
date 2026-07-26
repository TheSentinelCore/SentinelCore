--- ExecutionPlan loader — resolver output (ADR 09a §1.4) in the shape the executor already reads.
---
--- WHY THIS IS A SEPARATE MODULE AND NOT A BRANCH IN runtime_profile.lua
--- ADR 09 §6.2 budgets graph execution at exactly ONE branch point in the runtime. Everything the
--- graph costs that ISN'T that branch point — index rebasing, guard resolution, telling a plan
--- from a compiled profile — is normalization, and normalization that lives next to a recovery
--- state machine is normalization nobody can test in isolation. This module touches no Sylvannas
--- API and holds no state, so an editor, a test, or a future headless simulator can load a plan
--- without a client.
---
--- THE OFF-BY-ONE THIS MODULE EXISTS TO PREVENT
--- `to_index` is a Rust `Vec` position (resolver `lower_graph` builds `index_of` from
--- `order.iter().enumerate()`), so it is 0-BASED. `RuntimeProfile.operations` is a Lua array, so it
--- is 1-based. An unrebased plan does not crash and does not fail a hash check — every branch just
--- lands one operation early, which reads as a content bug in a 700-step guide rather than as an
--- arithmetic one. It is rebased once, here, at the only place a plan enters the runtime.

local ExecutionPlan = {}

--- The schema version this loader was written against (ADR 09a §1.4 / PLATFORM_SCHEMA_VERSION).
--- Not enforced: a plan from a newer resolver whose operations still look like operations is more
--- useful loaded than refused, and the resolver already gates real incompatibility behind the
--- content hash and the db fingerprint.
ExecutionPlan.SCHEMA_VERSION = 3

--- Is this decoded JSON an ExecutionPlan rather than a compiled RuntimeProfile?
---
--- The discriminator must be exact in BOTH directions. A plan misread as a profile keeps 0-based
--- `to_index` values and reroutes the guide; a profile misread as a plan gets every operation
--- treated as terminal (no `next`) and stops dead at operation 1. So: a plan is a table with
--- operations whose FIRST operation carries the two fields the compiler never emitted —
--- `node_id` and `next`.
function ExecutionPlan.is_plan(decoded)
    if type(decoded) ~= "table" then return false end
    local operations = decoded.operations
    if type(operations) ~= "table" then return false end
    local first = operations[1]
    if type(first) ~= "table" then return false end
    return first.node_id ~= nil and type(first.next) == "table"
end

--- Build `id -> RuntimeCondition` from whichever shape the producer used.
---
--- `ConditionDef` serializes with `#[serde(flatten)]` over an adjacently-tagged RuntimeCondition,
--- so a list entry is `{ id, type, payload }` — the id and the condition share one table. A map
--- keyed by id is accepted too because it is the obvious hand-authored shape and costs one branch.
local function index_conditions(conditions)
    local by_id = {}
    if type(conditions) ~= "table" then return by_id end
    for _, entry in ipairs(conditions) do
        if type(entry) == "table" and entry.id then
            by_id[entry.id] = { type = entry.type, payload = entry.payload }
        end
    end
    for key, value in pairs(conditions) do
        if type(key) == "string" and type(value) == "table" and by_id[key] == nil then
            by_id[key] = value
        end
    end
    return by_id
end

--- Resolve one wire transition into an executor transition.
---
--- `guard: null` decodes to nil through `core/JSON` (its parser returns nil for the null literal),
--- so an absent `guard` key IS the unguarded case — there is no null sentinel to unwrap.
local function normalize_transition(transition, conditions)
    if type(transition) ~= "table" then return nil end
    local to_index = tonumber(transition.to_index)
    if not to_index then return nil end

    local out = { to_index = to_index + 1 } -- 0-based Rust Vec position -> 1-based Lua array

    local guard = transition.guard
    if guard == nil then
        return out
    end
    if type(guard) == "table" then
        -- Already a RuntimeCondition. Not what §1.4 puts on the wire, but accepting it keeps the
        -- runtime indifferent to whether conditions travel inline or in a side table.
        out.guard = guard
        return out
    end

    out.guard_id = tostring(guard)
    local condition = conditions[out.guard_id]
    if condition then
        out.guard = condition
    else
        -- The resolver keeps an edge whose guard names no condition (it emits
        -- `resolver.guard.unknown_condition` rather than dropping the edge, because dropping it
        -- would rewrite the route's shape). The runtime therefore has to expect one, and it
        -- refuses to take it — see `select_transition`.
        out.unresolved = true
    end
    return out
end

--- Convert an ExecutionPlan into the table `RuntimeProfile` already executes.
---
--- The point is that AFTER this call there is one shape, not two: an operation is
--- `{ id, actions, ... }` whether it came from the compiler or the resolver, and the only thing
--- that tells them apart downstream is whether `next` is present. That is deliberate — it is what
--- keeps the executor's legacy path literally unchanged instead of merely equivalent.
function ExecutionPlan.normalize(plan)
    if type(plan) ~= "table" then return plan end

    local conditions = index_conditions(plan.conditions)

    local profile = {}
    for key, value in pairs(plan) do
        if key ~= "operations" then profile[key] = value end
    end

    local operations = {}
    for index, operation in ipairs(plan.operations or {}) do
        local next_transitions = {}
        for _, transition in ipairs(operation.next or {}) do
            local normalized = normalize_transition(transition, conditions)
            if normalized then next_transitions[#next_transitions + 1] = normalized end
        end
        operations[index] = {
            -- `_execute_running` keys its per-action retry reset on `op.id`. Plan operations have
            -- a node_id, not an id, and node ids are strings — the ordinal keeps that identity
            -- comparison on the same type it has always had.
            id = index,
            node_id = type(operation.node_id) == "string" and operation.node_id or nil,
            actions = operation.actions or {},
            next = next_transitions,
        }
    end
    profile.operations = operations

    return profile
end

--- Does this profile carry graph transitions, or is it pre-plan content?
function ExecutionPlan.has_transitions(profile)
    local operations = profile and profile.operations
    if type(operations) ~= "table" then return false end
    for _, operation in ipairs(operations) do
        if type(operation.next) == "table" then return true end
    end
    return false
end

--- THE branch point (ADR 09 §6.2). Pick the successor of `operation`.
---
--- Outgoing transitions are evaluated IN ORDER and the first satisfied one wins, so a plan
--- expresses "otherwise" as a trailing unguarded edge. A lone unguarded edge is exactly the
--- `_current_operation_idx + 1` this replaces.
---
--- @param operation table   a normalized operation (or a legacy one, which has no `next`)
--- @param evaluate  function(condition) -> boolean, the caller's condition evaluator
--- @return number|nil next operation index (1-based), nil when there is no successor
--- @return string outcome: "linear" (pre-plan op, caller keeps its own advance) | "sequential" |
---         "guarded" | "terminal" (`next: []`) | "dead_end" (edges exist, none satisfiable)
--- @return table|nil detail { guard_id, unmet, guards, transitions }
function ExecutionPlan.select_transition(operation, evaluate)
    local transitions = operation and operation.next
    if type(transitions) ~= "table" then
        return nil, "linear", nil
    end
    if #transitions == 0 then
        return nil, "terminal", { transitions = 0, unmet = 0 }
    end

    local unmet = 0
    local refused = {}

    for _, transition in ipairs(transitions) do
        local satisfied
        if transition.unresolved then
            -- Fail CLOSED, unlike `RuntimeAction.evaluate_condition`'s unknown-TYPE fail-open.
            -- Those two look alike and are not: an unrecognised condition type means a newer
            -- compiler emitted something this runtime does not know, and blocking on it would
            -- stall a working guide. A guard id with no definition behind it means the plan is
            -- broken, and taking the edge would run a stretch of route the author gated off.
            satisfied = false
        elseif transition.guard == nil then
            satisfied = true
        else
            local ok, met = pcall(evaluate, transition.guard)
            satisfied = ok and met == true
        end

        if satisfied then
            local outcome = transition.guard == nil and "sequential" or "guarded"
            return transition.to_index, outcome, {
                guard_id = transition.guard_id,
                unmet = unmet,
                guards = refused,
                transitions = #transitions,
            }
        end

        unmet = unmet + 1
        refused[#refused + 1] = transition.guard_id or "inline"
    end

    return nil, "dead_end", { unmet = unmet, guards = refused, transitions = #transitions }
end

return ExecutionPlan
