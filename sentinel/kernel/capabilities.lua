-- kernel/capabilities.lua
-- `provides` / `requires` / `conflicts` resolution, producing a deterministic load order.
--
-- ADR 08 §8.2: "`provides` / `requires` are what make this genuinely modular: the kernel resolves
-- the dependency graph at load and REFUSES TO LOAD A PLUGIN WHOSE REQUIREMENTS ARE UNMET."
--
-- ================================================================================
-- EVERY REFUSAL NAMES ITS CAUSE
-- ================================================================================
-- ADR 08 §12: RXPGuides ships without a validator, so an unresolved `#completewith foo` silently
-- never fires; LazyBot's `GrindingProfile.LoadFile` is eight `try {} catch {}` blocks with EMPTY
-- CATCH BODIES, so a 90%-broken profile still "loads". The entire value of failing closed is the
-- diagnostic -- refusing anonymously is barely better than failing open. So a rejection carries
-- `{ id, reason, detail }` and `detail` names the specific capability, conflicting id, or cycle.
--
-- ================================================================================
-- DETERMINISTIC ORDER -- A RULE THE ADR DOES NOT STATE
-- ================================================================================
-- §8.2 gives `provides`/`requires`, which constrains order only BETWEEN dependent plugins.
-- Independent plugins are unordered by the ADR, and "unordered" in Lua means `pairs()` order,
-- which is not stable. So:
--
--   TIE-BREAK: lexicographic by `id`.
--
-- That is an INVENTION, not a derivation. It is arbitrary but it is total, stable across runs,
-- independent of input order, and independent of directory iteration -- which are the properties
-- that actually matter. It also makes "who wins a conflict" predictable rather than a function of
-- how the loader happened to enumerate files.

local Capabilities = {}

local function sorted_ids(map)
    local out = {}
    for id in pairs(map) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function as_list(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return {} end
    return value
end

---Resolve a manifest set into a load order.
---@param manifests table array of manifests (already schema-validated)
---@param opts table|nil { kernel_provides = { ["nav"] = true, ... } }
---@return table result { order, loaded, rejected, providers }
function Capabilities.resolve(manifests, opts)
    opts = opts or {}
    local kernel_provides = opts.kernel_provides or {}

    local result = { order = {}, loaded = {}, rejected = {}, providers = {} }

    local function reject(id, reason, detail)
        result.rejected[#result.rejected + 1] = { id = id, reason = reason, detail = detail }
    end

    -- ---------------------------------------------------------------------
    -- 1. Deduplicate, and establish the deterministic processing order.
    -- ---------------------------------------------------------------------
    local candidates = {}
    local seen_order = {}
    for _, m in ipairs(manifests or {}) do
        if type(m) == "table" and type(m.id) == "string" then
            if candidates[m.id] then
                -- A duplicate id would make `provides` ambiguous and `conflicts` unresolvable.
                reject(m.id, "duplicate_id", m.id)
            else
                candidates[m.id] = m
                seen_order[#seen_order + 1] = m.id
            end
        end
    end
    local order_of_consideration = sorted_ids(candidates)

    -- ---------------------------------------------------------------------
    -- 2. Conflicts, evaluated BIDIRECTIONALLY.
    --
    -- A conflict is symmetric whether or not both sides declare it, so both lists are consulted.
    -- Reading only the incumbent's list is the natural implementation and misses the case where
    -- the LATER plugin is the one that declared the conflict.
    --
    -- Processed in lexicographic order, so the survivor is a property of the manifest set rather
    -- than of how the loader enumerated it.
    -- ---------------------------------------------------------------------
    local accepted = {}
    for _, id in ipairs(order_of_consideration) do
        local m = candidates[id]
        local blocker = nil
        for _, other_id in ipairs(sorted_ids(accepted)) do
            local other = accepted[other_id]
            for _, c in ipairs(as_list(m.conflicts)) do
                if c == other_id then blocker = other_id break end
            end
            if not blocker then
                for _, c in ipairs(as_list(other.conflicts)) do
                    if c == id then blocker = other_id break end
                end
            end
            if blocker then break end
        end
        if blocker then
            reject(id, "conflicts", blocker)
        else
            accepted[id] = m
        end
    end

    -- ---------------------------------------------------------------------
    -- 3. Prune unmet requirements to a fixed point.
    --
    -- Iterative rather than single-pass because rejection CASCADES: dropping a provider can leave
    -- its consumers unsatisfied, and dropping those can leave further consumers unsatisfied. A
    -- single pass would admit a consumer whose provider was removed later in the same pass.
    -- ---------------------------------------------------------------------
    local function provider_exists(capability, pool)
        if kernel_provides[capability] then return true end
        for _, m in pairs(pool) do
            for _, p in ipairs(as_list(m.provides)) do
                if p == capability then return true end
            end
        end
        return false
    end

    local changed = true
    while changed do
        changed = false
        for _, id in ipairs(sorted_ids(accepted)) do
            local m = accepted[id]
            for _, requirement in ipairs(as_list(m.requires)) do
                if not provider_exists(requirement, accepted) then
                    accepted[id] = nil
                    reject(id, "requires_unmet", requirement)
                    changed = true
                    break
                end
            end
        end
    end

    -- ---------------------------------------------------------------------
    -- 4. Topological sort with a lexicographic tie-break.
    --
    -- Kahn's algorithm rather than recursive DFS: a cycle must be REPORTED, not hit the C stack.
    -- Whatever remains unemitted when no zero-indegree node is left is exactly the cyclic set.
    -- ---------------------------------------------------------------------
    local dependencies = {}   -- id -> set of ids it must load after
    for _, id in ipairs(sorted_ids(accepted)) do
        dependencies[id] = {}
        local m = accepted[id]
        for _, requirement in ipairs(as_list(m.requires)) do
            -- A requirement the kernel satisfies imposes no ordering between plugins.
            if not kernel_provides[requirement] then
                for _, other_id in ipairs(sorted_ids(accepted)) do
                    if other_id ~= id then
                        for _, p in ipairs(as_list(accepted[other_id].provides)) do
                            if p == requirement then
                                dependencies[id][other_id] = true
                            end
                        end
                    end
                end
            end
        end
    end

    local remaining = {}
    for id, m in pairs(accepted) do remaining[id] = m end
    local emitted = {}

    while next(remaining) ~= nil do
        local ready = {}
        for _, id in ipairs(sorted_ids(remaining)) do
            local satisfied = true
            for dep in pairs(dependencies[id]) do
                if remaining[dep] ~= nil and not emitted[dep] then
                    satisfied = false
                    break
                end
            end
            if satisfied then ready[#ready + 1] = id end
        end

        if #ready == 0 then
            -- Everything left is in, or downstream of, a cycle.
            local cyclic = sorted_ids(remaining)
            local description = table.concat(cyclic, " -> ")
            for _, id in ipairs(cyclic) do
                reject(id, "requires_cycle", description)
                remaining[id] = nil
            end
            break
        end

        -- `ready` is already lexicographic because it was built from sorted_ids.
        for _, id in ipairs(ready) do
            result.order[#result.order + 1] = id
            result.loaded[id] = accepted[id]
            emitted[id] = true
            remaining[id] = nil
        end
    end

    -- ---------------------------------------------------------------------
    -- 5. Provider index, for the load-time diagnostic report.
    -- ---------------------------------------------------------------------
    for capability in pairs(kernel_provides) do
        result.providers[capability] = { "<kernel>" }
    end
    for _, id in ipairs(result.order) do
        for _, p in ipairs(as_list(result.loaded[id].provides)) do
            result.providers[p] = result.providers[p] or {}
            table.insert(result.providers[p], id)
        end
    end

    return result
end

return Capabilities
