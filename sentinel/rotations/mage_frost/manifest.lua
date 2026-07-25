-- rotations/mage_frost/manifest.lua
-- The frost mage as a plugin (ADR 08 §8.2).
--
-- This is the first real consumer of the plugin contract, and the whole point of Phase 4: if a
-- mature 2,000-line rotation cannot be expressed here without reaching past the public API, the API
-- is not adequate -- and `tests/kernel/test_plugin_require_audit.lua` enforces that mechanically
-- rather than by inspection.
--
-- TIER 2, not Tier 1, and that is a finding rather than a shortcut. §8.4 assumes Tier 1 declarative
-- authoring covers ~90% of rotations. Measured against this profile: the 25-entry priority LIST
-- ports exactly onto `Sentinel.rotation`, but none of its 37 conditions or 32 actions are
-- expressible in the declarative vocabulary, because that vocabulary does not exist. See
-- 08a_API_GAPS.md §1.

local API = require("rotations/mage_frost/sentinel_api")
local Profile = require("rotations/mage_frost/frost_tbc")

return {
    id = "sentinel.rotation.mage_frost",
    kind = "rotation",
    version = "1.0.0",
    -- Gates on the published surface, not on a build number. `^1.0` accepts additive changes and
    -- refuses an incompatible one, which is the only thing keeping the plugin honest when the kernel
    -- moves underneath it.
    api = "^1.0",

    -- §13 risk 4 warns against building multi-spec resolution before there is a second rotation, so
    -- `spec` is deliberately absent: this is the only Mage rotation, and claiming FROST would make
    -- the plugin ineligible on a character the module happily runs today.
    applies_to = { class = "Mage", min_level = 1, max_level = 70 },

    provides = { "combat_routine" },

    -- Every one of these is satisfied by the kernel (`Api.KERNEL_CAPABILITIES`). Four of them --
    -- `rotation`, `units`, `spells`, `catalogs.spell` -- did not exist before this port needed them.
    requires = {
        "state", "events", "rotation", "bt",
        "units", "spells", "catalogs.aura", "catalogs.spell", "timing.gcd",
    },

    -- §6.2. A rotation may declare COMBAT or SURVIVAL; its defensive entries (Ice Block, Mana
    -- Shield, emergency Blink) are the reason the tier is permitted both.
    priority = { band = "COMBAT", offset = 0 },

    config = {
        { key = "use_water_elemental", type = "bool", default = true },
        { key = "blink_threshold", type = "int", default = 35, min = 0, max = 100 },
        { key = "use_aoe", type = "bool", default = true },
    },

    ---Veto activation when the kernel cannot actually support a cast.
    ---
    ---§8.3: preflight exists to REFUSE, not to warn. A rotation that activates without a spell
    ---catalog resolves every spell key to nil and silently casts nothing -- which looks exactly like
    ---a broken rotation and is far harder to diagnose than a refusal at load.
    preflight = function(ctx)
        local S = ctx and ctx.api or API
        if S.catalogs == nil or S.catalogs.spell == nil then
            return false, "no spell catalog: rank resolution would return nil for every spell"
        end
        if S.timing == nil then
            return false, "no timing service: the rotation would double-cast through the GCD"
        end
        return true
    end,

    ---Build the behaviour tree. Called once on activation, not per tick.
    build = function(ctx)
        return Profile.build(ctx.blackboard, ctx.event_bus)
    end,
}
