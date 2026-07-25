-- tests/kernel/test_capabilities.lua
-- ADR 08 §8.2: "`provides` / `requires` are what make this genuinely modular: the kernel
-- resolves the dependency graph at load and REFUSES TO LOAD A PLUGIN WHOSE REQUIREMENTS ARE
-- UNMET."
--
-- Note §8.2's own caveat: "today ModuleRegistry's `capabilities` field is DECLARED BUT NEVER
-- CONSUMED outside tests -- capability resolution is new work, not existing." This is that work.
--
-- The refusal must NAME the unmet requirement. ADR §12 is explicit about why: RXPGuides ships
-- without a validator, so an unresolved `#completewith foo` silently never fires; LazyBot's
-- loader is eight empty `catch {}` blocks, so a 90%-broken profile still "loads". A validator
-- that refuses anonymously is barely better than one that fails open, because the whole value of
-- failing closed is the diagnostic.
--
-- DETERMINISTIC ORDER, and a rule the ADR does not state. §8.2 gives `provides`/`requires`, which
-- constrains order only between dependent plugins. Independent plugins need a tie-break and the
-- ADR names none, so this implementation sorts by `id` lexicographically. Documented as an
-- invention rather than a derivation.

local Capabilities = require("kernel/capabilities")
local T = require("tests/test_util")

local M = {}

local function manifest(id, spec)
    spec = spec or {}
    return {
        id = id,
        kind = spec.kind or "rotation",
        provides = spec.provides,
        requires = spec.requires,
        conflicts = spec.conflicts,
    }
end

local function rejection_for(result, id)
    for _, r in ipairs(result.rejected) do
        if r.id == id then return r end
    end
    return nil
end

local function index_of(list, id)
    for i, v in ipairs(list) do if v == id then return i end end
    return nil
end

-- ---------------------------------------------------------------------------
-- Basic resolution
-- ---------------------------------------------------------------------------

function M.test_a_plugin_with_no_requirements_loads()
    local result = Capabilities.resolve({ manifest("a.plugin") })
    T.assert_equal(#result.order, 1)
    T.assert_equal(result.order[1], "a.plugin")
    T.assert_equal(#result.rejected, 0)
end

function M.test_a_requirement_met_by_the_kernel_loads()
    local result = Capabilities.resolve(
        { manifest("a.plugin", { requires = { "nav" } }) },
        { kernel_provides = { nav = true } })
    T.assert_equal(#result.order, 1)
    T.assert_equal(#result.rejected, 0)
end

--- The named exit criterion.
function M.test_an_unmet_requirement_is_refused_naming_the_capability()
    local result = Capabilities.resolve(
        { manifest("a.plugin", { requires = { "nav", "catalogs.spell" } }) },
        { kernel_provides = { nav = true } })

    T.assert_equal(#result.order, 0)
    local rejection = rejection_for(result, "a.plugin")
    T.assert_not_nil(rejection)
    T.assert_equal(rejection.reason, "requires_unmet")
    T.assert_equal(rejection.detail, "catalogs.spell",
        "the refusal must name WHICH requirement is unmet")
end

function M.test_a_requirement_met_by_another_plugin_loads_both_in_dependency_order()
    local result = Capabilities.resolve({
        manifest("z.consumer", { requires = { "target_selection" } }),
        manifest("a.provider", { provides = { "target_selection" } }),
    })

    T.assert_equal(#result.rejected, 0)
    T.assert_equal(#result.order, 2)
    T.assert_true(index_of(result.order, "a.provider") < index_of(result.order, "z.consumer"),
        "a provider must load before its consumer")
end

--- The cascade: if the provider is rejected, everything that depended on it must be too --
--- otherwise a consumer loads against a capability that is not there.
function M.test_rejection_cascades_to_dependents()
    local result = Capabilities.resolve({
        manifest("a.provider", { provides = { "cap.x" }, requires = { "missing.thing" } }),
        manifest("b.consumer", { requires = { "cap.x" } }),
    })

    T.assert_equal(#result.order, 0, "neither may load")
    T.assert_equal(rejection_for(result, "a.provider").reason, "requires_unmet")
    T.assert_equal(rejection_for(result, "b.provider"), nil)
    local consumer = rejection_for(result, "b.consumer")
    T.assert_equal(consumer.reason, "requires_unmet")
    T.assert_equal(consumer.detail, "cap.x", "the cascade must still name the capability")
end

function M.test_a_deep_chain_orders_correctly()
    local result = Capabilities.resolve({
        manifest("c.top", { requires = { "cap.b" } }),
        manifest("b.mid", { provides = { "cap.b" }, requires = { "cap.a" } }),
        manifest("a.base", { provides = { "cap.a" } }),
    })
    T.assert_equal(#result.rejected, 0)
    T.assert_equal(result.order[1], "a.base")
    T.assert_equal(result.order[2], "b.mid")
    T.assert_equal(result.order[3], "c.top")
end

-- ---------------------------------------------------------------------------
-- Conflicts -- BIDIRECTIONAL
-- ---------------------------------------------------------------------------

--- "conflicts is bidirectional: if A conflicts B, loading B after A must also fail."
function M.test_conflicts_refuses_in_the_declared_direction()
    local result = Capabilities.resolve({
        manifest("a.first", { conflicts = { "b.second" } }),
        manifest("b.second"),
    })
    T.assert_equal(#result.order, 1)
    T.assert_equal(result.order[1], "a.first")
    local rejection = rejection_for(result, "b.second")
    T.assert_equal(rejection.reason, "conflicts")
    T.assert_equal(rejection.detail, "a.first", "the refusal must name the other party")
end

--- The direction that is easy to get wrong: the LATER plugin declares the conflict, so a naive
--- implementation that only reads the incumbent's list misses it entirely.
function M.test_conflicts_refuses_in_the_reverse_direction()
    local result = Capabilities.resolve({
        manifest("a.first"),
        manifest("b.second", { conflicts = { "a.first" } }),
    })
    T.assert_equal(#result.order, 1)
    T.assert_equal(result.order[1], "a.first", "the first in deterministic order wins")
    local rejection = rejection_for(result, "b.second")
    T.assert_equal(rejection.reason, "conflicts")
    T.assert_equal(rejection.detail, "a.first")
end

--- Which one survives must not depend on the order they were handed in, or "who wins" becomes a
--- function of directory iteration order.
function M.test_conflict_resolution_is_independent_of_input_order()
    local forward = Capabilities.resolve({
        manifest("a.first"), manifest("b.second", { conflicts = { "a.first" } }),
    })
    local backward = Capabilities.resolve({
        manifest("b.second", { conflicts = { "a.first" } }), manifest("a.first"),
    })
    T.assert_equal(forward.order[1], backward.order[1],
        "the same conflict pair must resolve the same way regardless of input order")
    T.assert_equal(forward.order[1], "a.first")
end

function M.test_a_conflict_against_an_absent_plugin_is_harmless()
    local result = Capabilities.resolve({ manifest("a.plugin", { conflicts = { "not.present" } }) })
    T.assert_equal(#result.order, 1)
    T.assert_equal(#result.rejected, 0)
end

function M.test_a_conflict_rejection_also_cascades()
    local result = Capabilities.resolve({
        manifest("a.first", { conflicts = { "b.second" } }),
        manifest("b.second", { provides = { "cap.x" } }),
        manifest("c.consumer", { requires = { "cap.x" } }),
    })
    T.assert_equal(rejection_for(result, "b.second").reason, "conflicts")
    T.assert_equal(rejection_for(result, "c.consumer").reason, "requires_unmet",
        "a capability lost to a conflict must take its consumers with it")
end

-- ---------------------------------------------------------------------------
-- Cycles
-- ---------------------------------------------------------------------------

--- "Detect cycles in the requires graph and refuse BY NAME rather than recursing."
function M.test_a_two_node_cycle_is_refused_by_name()
    local result = Capabilities.resolve({
        manifest("a.one", { provides = { "cap.a" }, requires = { "cap.b" } }),
        manifest("b.two", { provides = { "cap.b" }, requires = { "cap.a" } }),
    })

    T.assert_equal(#result.order, 0, "a cycle cannot be loaded in any order")
    T.assert_equal(rejection_for(result, "a.one").reason, "requires_cycle")
    T.assert_equal(rejection_for(result, "b.two").reason, "requires_cycle")
    T.assert_not_nil(rejection_for(result, "a.one").detail, "the cycle must be described")
end

function M.test_a_three_node_cycle_is_refused_without_recursing()
    local result = Capabilities.resolve({
        manifest("a", { provides = { "ca" }, requires = { "cc" } }),
        manifest("b", { provides = { "cb" }, requires = { "ca" } }),
        manifest("c", { provides = { "cc" }, requires = { "cb" } }),
    })
    T.assert_equal(#result.order, 0)
    T.assert_equal(#result.rejected, 3)
    for _, r in ipairs(result.rejected) do
        T.assert_equal(r.reason, "requires_cycle")
    end
end

--- A self-cycle: a plugin requiring what it provides. Harmless in principle, but it must not
--- deadlock the sort.
function M.test_a_self_satisfying_requirement_loads()
    local result = Capabilities.resolve({
        manifest("a.plugin", { provides = { "cap.x" }, requires = { "cap.x" } }),
    })
    T.assert_equal(#result.order, 1, "a plugin may satisfy its own requirement")
end

--- A cycle must not take unrelated plugins down with it.
function M.test_a_cycle_does_not_reject_independent_plugins()
    local result = Capabilities.resolve({
        manifest("a.one", { provides = { "cap.a" }, requires = { "cap.b" } }),
        manifest("b.two", { provides = { "cap.b" }, requires = { "cap.a" } }),
        manifest("z.independent"),
    })
    T.assert_equal(#result.order, 1)
    T.assert_equal(result.order[1], "z.independent")
end

-- ---------------------------------------------------------------------------
-- Determinism
-- ---------------------------------------------------------------------------

--- "Two runs over the same manifest set must load in the same order."
function M.test_resolution_order_is_deterministic_across_runs()
    local function build()
        return {
            manifest("m.four", { requires = { "cap.one" } }),
            manifest("a.one", { provides = { "cap.one" } }),
            manifest("z.five"),
            manifest("b.two"),
            manifest("c.three", { requires = { "cap.one" } }),
        }
    end

    local first = Capabilities.resolve(build()).order
    for _ = 1, 20 do
        local again = Capabilities.resolve(build()).order
        T.assert_equal(#again, #first)
        for i = 1, #first do
            T.assert_equal(again[i], first[i], "position " .. i .. " must be stable across runs")
        end
    end
end

--- ...and stable under a shuffled input, since directory iteration order is not guaranteed.
function M.test_resolution_order_is_independent_of_input_order()
    local a = manifest("a.one", { provides = { "cap.one" } })
    local b = manifest("b.two")
    local c = manifest("c.three", { requires = { "cap.one" } })

    local forward = Capabilities.resolve({ a, b, c }).order
    local backward = Capabilities.resolve({ c, b, a }).order
    local mixed = Capabilities.resolve({ b, c, a }).order

    for i = 1, #forward do
        T.assert_equal(backward[i], forward[i], "reversed input must yield the same order")
        T.assert_equal(mixed[i], forward[i], "shuffled input must yield the same order")
    end
end

--- The stated tie-break: independent plugins load in lexicographic id order.
function M.test_independent_plugins_load_in_lexicographic_id_order()
    local order = Capabilities.resolve({
        manifest("zebra"), manifest("alpha"), manifest("mango"),
    }).order
    T.assert_equal(order[1], "alpha")
    T.assert_equal(order[2], "mango")
    T.assert_equal(order[3], "zebra")
end

-- ---------------------------------------------------------------------------
-- Duplicates and shape
-- ---------------------------------------------------------------------------

function M.test_a_duplicate_id_is_refused()
    local result = Capabilities.resolve({ manifest("same.id"), manifest("same.id") })
    T.assert_equal(#result.order, 1)
    T.assert_equal(rejection_for(result, "same.id").reason, "duplicate_id")
end

--- Two plugins providing the same capability is legitimate (a default and an override), and the
--- resolver must not treat it as a conflict -- only an explicit `conflicts` entry does that.
function M.test_two_providers_of_one_capability_both_load()
    local result = Capabilities.resolve({
        manifest("a.default", { provides = { "target_selection" } }),
        manifest("b.override", { provides = { "target_selection" } }),
    })
    T.assert_equal(#result.order, 2)
    T.assert_equal(#result.rejected, 0)
end

function M.test_an_empty_manifest_set_resolves_to_nothing()
    local result = Capabilities.resolve({})
    T.assert_equal(#result.order, 0)
    T.assert_equal(#result.rejected, 0)
end

function M.test_the_provider_index_is_reported_for_diagnostics()
    local result = Capabilities.resolve({
        manifest("a.provider", { provides = { "cap.x" } }),
    }, { kernel_provides = { nav = true } })

    T.assert_equal(result.providers["cap.x"][1], "a.provider")
    T.assert_equal(result.providers["nav"][1], "<kernel>",
        "kernel-provided capabilities must be attributable too")
end

return M
