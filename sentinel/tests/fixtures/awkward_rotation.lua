-- tests/fixtures/awkward_rotation.lua
-- A DELIBERATELY AWKWARD plugin that exercises every field of ADR 08 §8.2's manifest.
--
-- WHY THIS EXISTS. A plugin contract designed against no consumer fits no consumer. Phase 4 ports
-- the frost mage for exactly that reason -- "if the public API can express a frost rotation it can
-- express anything else... Finding the API inadequate at Phase 4 is cheap; finding it at Phase 6 is
-- not" (§12) -- and the same logic applies one phase earlier to the MANIFEST.
--
-- This is a STUB, not a rotation. It casts nothing. Its whole job is to be hard to satisfy:
--
--   * multiple `requires`, one of which the kernel provides and one of which another plugin must
--   * a `conflicts` entry
--   * an `applies_to` that is FALSE at first and becomes true (level gate)
--   * a `preflight` that vetoes on the first attempt and passes afterwards
--   * a `config` block using every supported type
--   * BOTH `build` and `tick`
--   * a `tick` that returns each Status in turn, including BLOCKED with a reason
--
-- EXPECT PHASE 4 TO BREAK THIS. That is the point: a fixture that survives contact with a real
-- rotation unchanged would mean the fixture was too easy.

local Fixture = {}

--- Build a fresh fixture. State lives on the returned table so tests can drive it.
---@param overrides table|nil fields merged into the manifest, for negative tests
function Fixture.new(overrides)
    local self = {
        preflight_calls = 0,
        build_calls = 0,
        tick_calls = 0,
        ticked_with = {},
        -- The awkward part: refuses the first preflight, accepts later ones. A plugin whose
        -- eligibility and whose readiness differ is exactly the case ELIGIBLE-vs-ACTIVE exists for.
        veto_first_preflight = true,
        -- Drives the tick return value, so a test can walk the whole Status enum.
        next_status = "RUNNING",
        next_reason = nil,
    }

    self.manifest = {
        id = "sentinel.rotation.awkward",
        kind = "rotation",
        version = "0.3.1",
        api = "^1.0",

        -- False on a level-1 character, true once the level gate is passed.
        applies_to = { class = "Mage", min_level = 20, max_level = 70 },

        provides = { "combat_routine", "awkward_diagnostics" },
        -- "control" is kernel-provided; "target_selection" must come from another plugin. That
        -- split is deliberate: it exercises both arms of capability resolution.
        requires = { "control", "state", "target_selection" },
        conflicts = { "sentinel.rotation.mage_generic" },

        priority = { band = "COMBAT", offset = 5 },

        config = {
            { key = "use_water_elemental", type = "bool", default = true },
            { key = "blink_threshold", type = "int", default = 35, min = 0, max = 100 },
            { key = "leash_yards", type = "float", default = 12.5, min = 0, max = 40 },
            { key = "label", type = "string", default = "awkward" },
            { key = "stance", type = "enum", default = "objective",
              values = { "objective", "aggressive", "passive" } },
        },

        preflight = function(ctx)
            self.preflight_calls = self.preflight_calls + 1
            if self.veto_first_preflight and self.preflight_calls == 1 then
                -- A veto with a reason, so the diagnostic report has something to show.
                return false, "water elemental on cooldown"
            end
            return true
        end,

        build = function(ctx)
            self.build_calls = self.build_calls + 1
            -- A declarative plugin returns a tree; a stub returns something tree-shaped so the
            -- host has a value to hold without pretending it is a real behaviour tree.
            return { kind = "stub_tree", owner = "sentinel.rotation.awkward" }
        end,

        tick = function(ctx)
            self.tick_calls = self.tick_calls + 1
            self.ticked_with[#self.ticked_with + 1] = {
                tick_index = ctx and ctx.tick_index or nil,
                had_snapshot = ctx ~= nil and ctx.snapshot ~= nil,
            }
            if self.next_status == "BLOCKED" then
                return "BLOCKED", self.next_reason or "waiting for target_selection"
            end
            return self.next_status
        end,
    }

    for key, value in pairs(overrides or {}) do
        self.manifest[key] = value
    end
    return self
end

--- The other half of the fixture's `requires`: a minimal strategy plugin providing
--- `target_selection`, so the awkward rotation can be loaded rather than only refused.
function Fixture.target_strategy()
    return {
        id = "sentinel.strategy.dummy_targeting",
        kind = "strategy",
        version = "1.0.0",
        api = "^1.0",
        -- No `priority`: §5.3 strategies choose rather than act, and Bands grants the strategy tier
        -- no band at all.
        provides = { "target_selection" },
        tick = function() return "DONE" end,
    }
end

--- The plugin the awkward rotation conflicts with, for the bidirectional-conflict test.
function Fixture.conflicting_rotation()
    return {
        id = "sentinel.rotation.mage_generic",
        kind = "rotation",
        version = "1.0.0",
        api = "^1.0",
        priority = { band = "COMBAT", offset = 0 },
        provides = { "combat_routine" },
        tick = function() return "DONE" end,
    }
end

return Fixture
