-- rotations/warlock_affliction/manifest.lua
-- The Affliction warlock as a plugin (ADR 08 §8.2).
--
-- ================================================================================
-- THIS MANIFEST IS NOT REACHED AT RUNTIME TODAY. READ THIS BEFORE TRUSTING IT.
-- ================================================================================
-- `PluginRegistry:discover` has exactly two production callers, both in kernel/api.lua:
-- `surface.register` and `Api.drain_pending`. Nothing in `sentinel/` ever calls `Sentinel.register`
-- or pushes onto `_G.__SentinelPending`, so no rotation manifest is ever discovered. The live path
-- is still `modules/combat/profiles/registry.lua` -> `Profile.build(blackboard, event_bus)`, exactly
-- as it is for the mage, whose manifest is likewise required by nobody.
--
-- So this file is a well-formed, validated, currently-unreachable artefact -- and it is written
-- anyway, for the same reason the mage's is: it is the declaration the registry will read when
-- discovery is wired, and writing it now is what proves the plugin contract can express this
-- rotation. Wiring discovery is a separate task, and doing it here would DOUBLE-DRIVE the rotation,
-- because `Registry.resolve` and `PluginRegistry:activate` would each build a tree.
--
-- TIER 2, not Tier 1, and that is a finding rather than a shortcut. §8.4 assumes Tier 1 declarative
-- authoring covers ~90% of rotations. Measured against this profile: the 9-entry priority LIST ports
-- exactly onto `Sentinel.rotation`, but none of its 13 conditions or 10 actions are expressible in
-- the declarative vocabulary, because that vocabulary does not exist. See 08a_API_GAPS.md §1.

local API = require("rotations/warlock_affliction/sentinel_api")
local Profile = require("rotations/warlock_affliction/affliction_tbc")

return {
    id = "sentinel.rotation.warlock_affliction",
    kind = "rotation",
    version = "1.0.0",
    -- Gates on the published surface, not on a build number. `^1.0` accepts additive changes and
    -- refuses an incompatible one, which is the only thing keeping the plugin honest when the kernel
    -- moves underneath it.
    api = "^1.0",

    -- §13 risk 4 warns against building multi-spec resolution before there is a second rotation, so
    -- `spec` is deliberately absent: this is the only Warlock rotation, and `Registry.resolve`
    -- ignores `spec_id` anyway, so claiming AFFLICTION would make the plugin ineligible on a
    -- character the module happily runs today.
    --
    -- `class` is the Title-Case NAME, not the numeric id: `plugin_registry.lua:187` compares it
    -- against `snapshot:get("player.class")`, which `snapshot_source.lua:108` fills through
    -- `ClassNames.resolve(class_id)` -- `[9] = "Warlock"`.
    applies_to = { class = "Warlock", min_level = 1, max_level = 70 },

    provides = { "combat_routine" },

    -- Every one of these is satisfied by the kernel (`Api.KERNEL_CAPABILITIES`) AND actually reached
    -- by this package. The list is deliberately not a copy of the mage's:
    --
    --   `control` and `cond` are declared here and are ABSENT from the mage's manifest even though
    --   it reaches both -- an under-declaration that is harmless only because nothing validates the
    --   other direction (api.lua's own header records that gap). Copying the omission would have
    --   propagated it.
    --
    --   `log` and `forecast` are NOT declared, because nothing in this package reads them. A
    --   capability claimed and unused is the same defect pointing the other way.
    requires = {
        "state", "events", "control", "rotation", "bt", "snapshot", "cond",
        "units", "spells", "catalogs.aura", "catalogs.spell", "timing.gcd",
    },

    -- §6.2. A rotation may declare COMBAT or SURVIVAL. Affliction has no defensive cooldown -- Drain
    -- Life is a GCD spell on the ordinary priority list, not a panic button -- so COMBAT is the only
    -- band it ever needs, and `offset = 0` because the three rotations are mutually exclusive by
    -- `applies_to.class` and there is nothing to disambiguate. A nonzero offset would be folklore,
    -- which is the thing bands exist to abolish.
    priority = { band = "COMBAT", offset = 0 },

    -- NO `config` BLOCK, and that is a deliberate difference from the mage.
    --
    -- `PluginRegistry:discover` calls `self._config:declare(id, manifest.config)`, so a declared key
    -- becomes a SECOND source of truth for a knob the combat module already seeds on the blackboard
    -- (`STATIC_DEFAULTS` in modules/combat/module.lua). This rotation reads no such knob today;
    -- declaring one to match the mage's shape would create the divergence rather than describe it.

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
