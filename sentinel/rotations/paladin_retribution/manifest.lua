-- rotations/paladin_retribution/manifest.lua
-- Retribution Paladin as a plugin (ADR 08 §8.2).
--
-- TIER 2, like the mage, and for the same measured reason: the 13-entry priority LIST ports exactly
-- onto `Sentinel.rotation`, but none of its 30 conditions or 15 actions are expressible in the
-- Tier-1 declarative vocabulary, because that vocabulary does not exist. See 08a_API_GAPS.md §1.
--
-- ================================================================================
-- THIS MANIFEST IS NOT THE LIVE ROUTE, AND SAYING SO IS PART OF THE PORT
-- ================================================================================
-- `PluginRegistry:discover` has exactly two production callers, both in `kernel/api.lua`
-- (`surface.register` and `Api.drain_pending`), and NOTHING in `sentinel/` ever calls
-- `Sentinel.register` or pushes onto `__SentinelPending`. `rotations/mage_frost/manifest.lua` is
-- required by nobody either -- grep finds one hit, its own header comment.
--
-- So this file is a well-formed, validated, currently-unreachable artifact, exactly as the mage's
-- is. The live route stays `modules/combat/profiles/registry.lua` -> `Profile.build`. Wiring
-- discovery is a separate deliverable and must not be smuggled in here: with both routes live the
-- rotation would be built TWICE -- once by `Registry.resolve` and once by `PluginRegistry:activate`
-- -- and two trees ticking one blackboard is a bug that looks like a performance problem.

local API = require("rotations/paladin_retribution/sentinel_api")
local Profile = require("rotations/paladin_retribution/retribution_tbc")

return {
    id = "sentinel.rotation.paladin_retribution",
    kind = "rotation",
    version = "1.0.0",
    -- Gates on the published surface, not on a build number. `^1.0` accepts additive changes and
    -- refuses an incompatible one, which is the only thing keeping the plugin honest when the
    -- kernel moves underneath it.
    api = "^1.0",

    -- Compared against `snapshot:get("player.class")` in `plugin_registry.lua:187`, which
    -- `snapshot_source.lua:108` fills through `ClassNames.resolve(class_id)` -- so the value is the
    -- Title-Case NAME, never the numeric id 2 and never "PALADIN".
    --
    -- §13 risk 4 warns against building multi-spec resolution before there is a second rotation per
    -- class, so `spec` is deliberately absent: `Registry.resolve` ignores `spec_id` today, and
    -- claiming RETRIBUTION would make the plugin ineligible on a character the module happily runs.
    applies_to = { class = "Paladin", min_level = 1, max_level = 70 },

    provides = { "combat_routine" },

    -- Every name here is satisfied by the kernel (`Api.KERNEL_CAPABILITIES`) AND actually reached
    -- by this package. The list is deliberately LONGER than the mage's, which omits `forecast`,
    -- `control`, `snapshot` and `cond` while using all four -- an under-declaration that is
    -- harmless only because nothing validates it. Under-declaring is the failure mode this list
    -- exists to prevent, so it is not copied:
    --
    --   state         -- the blackboard the profile is handed and reads throughout
    --   events        -- `rotation:profile_loaded`
    --   rotation      -- PriorityBuilder, the GCD tree
    --   bt            -- node constructors, Status and Runner
    --   control       -- the CASTING lease every cast is submitted under
    --   units         -- `mint_ref`, which stamps the guid a cast is aimed by
    --   spells        -- castability, line of sight, AoE placement for Consecration
    --   snapshot+cond -- `health_above` reads the frozen snapshot through `Sentinel.cond`
    --   forecast      -- `target_execute` asks `time_to_die` before falling back to HP%
    --   catalogs.aura -- Retribution Aura / Blessing presence checks
    --   catalogs.spell-- rank resolution, and off-GCD corroboration
    --   timing.gcd    -- see `preflight`: the commit gate's GCD check is what stops a double-cast
    requires = {
        "state", "events", "rotation", "bt",
        "control", "units", "spells", "snapshot", "cond", "forecast",
        "catalogs.aura", "catalogs.spell", "timing.gcd",
    },

    -- §6.2. A rotation may declare COMBAT or SURVIVAL only, and the declaration must be NAMED --
    -- `priority = 50` is refused by `validate_priority` with `priority_band_must_be_named`.
    --
    -- Offset 0, matching the mage. The three supported rotations are mutually exclusive by
    -- `applies_to.class`, so they are never eligible at once and there is no collision to
    -- disambiguate; a nonzero offset would be folklore, which is the thing bands exist to abolish.
    priority = { band = "COMBAT", offset = 0 },

    -- ================================================================================
    -- NO `config` BLOCK, AND THAT IS A DELIBERATE DIFFERENCE FROM THE MAGE
    -- ================================================================================
    -- This rotation's four knobs -- `module.combat.twist_mode`, `module.combat.twist_window_ms`,
    -- `module.combat.enable_burst`, `module.combat.preferred_blessing` -- are seeded by
    -- `modules/combat/module.lua`'s STATIC_DEFAULTS and read off the blackboard.
    -- `PluginRegistry:discover` calls `self._config:declare(id, manifest.config)`, so declaring
    -- them here would create a SECOND source of truth for each while the reads stayed on the
    -- blackboard -- a behaviour change smuggled in as a schema. `validate_config` accepts nil, so
    -- omitting the block is legal; it is recorded here so the absence reads as a decision.

    ---Veto activation when the kernel cannot actually support a cast.
    ---
    ---§8.3: preflight exists to REFUSE, not to warn. Both checks apply verbatim to this rotation:
    ---without a spell catalog `Support.spell_id_for` resolves every key to nil and the profile
    ---silently casts nothing, and without a timing service the commit gate's GCD check permits
    ---everything, so the Paladin double-casts through its own global cooldown.
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
