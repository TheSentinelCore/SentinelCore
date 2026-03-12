# Prompt: Grinding Module + Mage Rotation

> Paste this into a new Claude Code session opened at `c:\Users\Levi\Desktop\Sylvannas\scripts\`

---

You are implementing two major features for SentinelCore, a WoW TBC bot built on the Sylvannas API. Use the brainstorming skill first, then writing-plans, then TDD for implementation.

## Task

Build a **class-agnostic grinding module** and a **Mage rotation profile** (Frost-focused, levels 1-70 TBC) for SentinelCore.

## Architecture Requirements

### Grinding Module (class-agnostic)

A new module at `sentinel/modules/grind/` that orchestrates the full PvE grinding loop. It must be rotation-agnostic -- any class profile plugs in via the existing combat module.

**Core loop** (behavior tree):

1. **Target acquisition** -- find grindable mobs within a configurable radius, filter by level range (player_level-2 to player_level+1), skip tagged/tapped mobs, avoid elite/rare unless configured
2. **Pull** -- move into pull range, initiate combat (delegates to rotation profile for pull spell)
3. **Combat** -- delegates entirely to the existing combat module + active rotation profile
4. **Loot** -- move to corpse, loot, handle loot errors (corpse moved, already looted)
5. **Rest** -- eat/drink when health/mana below threshold. Mage: conjure food/water first. Other classes: use inventory items. Configurable thresholds (default: eat < 50% HP, drink < 40% mana)
6. **Vendor run** -- when bags are full (configurable free-slot threshold), navigate to nearest vendor via SentinelQueryServer (`GET /api/v1/vendors`), sell junk/grays, repair, return to grind area
7. **Trainer visit** -- on level-up, check if new spells available via DB query, navigate to class trainer via SentinelQueryServer (`GET /api/v1/trainers`), train all available spells, return
8. **Corpse run** -- on death, release spirit, navigate to corpse, resurrect with safety checks (no mobs nearby)
9. **Safety** -- flee if health critical (< 20%), evade if too many mobs (configurable), stuck detection with unstuck movement

**Integration points:**

- Uses `SentinelNavClient` (via existing `NavAdapter` at `sentinel/integrations/nav_client/adapter.lua`) for all pathfinding/movement
- Uses `SentinelQueryServer` for vendor/trainer/NPC lookups
- Uses existing `sentinel/modules/combat/module.lua` for combat -- grind module only handles the OUTER loop
- Uses existing `sentinel/core/blackboard.lua` for state sharing
- Uses existing `sentinel/core/event_bus.lua` for lifecycle events (`grind:started`, `grind:paused`, `grind:mob_pulled`, `grind:vendor_run_started`, etc.)

**Grind zone configuration:**

- Center point (vec3) + radius
- Level range filter
- Mob whitelist/blacklist (by name or entry ID)
- Vendor/trainer override (specific NPC ID or "nearest")

### Mage Rotation Profile

A new rotation profile at `sentinel/modules/combat/profiles/mage/` following the **exact same pattern** as the existing Paladin Retribution profile.

**File structure** (mirror paladin pattern):

```
profiles/mage/
  frost_tbc.lua           -- Main profile: build(), tick_maintenance/off_gcd/gcd, reset
  frost_actions.lua       -- Action functions (queue_frostbolt, queue_blizzard, etc.)
  frost_conditions.lua    -- Condition closures (spell_ready, has_mana_for, ice_barrier_down, etc.)
  maintenance_tree.lua    -- Buff maintenance (Ice Armor, Arcane Intellect, conjure food/water)
  aoe_tree.lua            -- AoE farming sub-tree (Frost Nova + Blizzard + CoC kiting)
```

**Leveling phases** (rotation adapts as spells unlock):

- **1-9**: Frostbolt spam, Fire Blast on runners, Frost Armor upkeep
- **10-19**: Frostbolt, Frost Nova for melee escape, start kiting patterns
- **20-29**: Blizzard unlocked (level 20) -- AoE farming becomes viable. Evocation for mana (level 20). Blink for repositioning.
- **30-39**: Ice Barrier (level 30 talent, deep Frost). Major survivability spike. Cold Snap for emergency double Ice Barrier/block.
- **40-49**: Ice Block. AoE farming fully online: gather 4-8 mobs -> Frost Nova -> Blizzard -> CoC -> repeat. Conjure Water rank upgrades.
- **50-59**: Improved Blizzard slow. Larger pulls possible. Water rank 7 (level 55).
- **60-70**: TBC spells: Ice Lance (level 66), Icy Veins (Frost talent). Water rank 8-9.

**Single-target rotation (all levels):**

1. Frostbolt (main nuke, always)
2. Fire Blast (instant, use on runners or when moving)
3. Frost Nova -> backpedal -> Frostbolt (if mob reaches melee)
4. Cone of Cold (if mob in melee and Frost Nova on CD)
5. Ice Barrier (on cooldown, always maintain)
6. Ice Block (emergency, health < 15%)
7. Evocation (out of combat or with Ice Block up, mana < 15%)
8. Cold Snap (reset Ice Barrier + Frost Nova in emergencies)

**AoE rotation (level 20+, configurable toggle):**

1. Gather phase: body-pull or Fireblast-tag 4-8 mobs, run in circle to stack them
2. Frost Nova (when stacked in melee)
3. Blink out to max range (20+ yards)
4. Blizzard on the pack (channeled, 8 sec)
5. If mobs break free early: Cone of Cold -> Frost Nova (if available) -> Blizzard again
6. Cold Snap to reset Frost Nova if needed
7. Repeat until dead
8. If pull goes bad (too many, resist): Ice Block -> Ice Barrier -> Blink -> run

**Maintenance tree:**

- Keep Frost Armor / Ice Armor active at all times
- Keep Arcane Intellect active
- Conjure Food when stacks < 5 (out of combat)
- Conjure Water when stacks < 5 (out of combat)
- Mana Shield as emergency buffer (optional, configurable)

## Data Research

Use the CMaNGOS-TBC MySQL database to look up exact spell IDs, ranks, level requirements, and mana costs. Do NOT guess spell IDs -- query for them.

```bash
mycli -u root -pascent -h 127.0.0.1 tbcmangos
```

**Queries to run:**

- Mage spell progression: all Frost/Fire/Arcane spells by level requirement
- Spell ranks: every rank of Frostbolt, Blizzard, Cone of Cold, Fire Blast, Frost Nova, Ice Barrier, Ice Block, Blink, Evocation, Arcane Intellect, Frost Armor, Ice Armor, Conjure Food, Conjure Water, Mana Shield, Cold Snap, Ice Lance, Icy Veins, Counterspell
- Trainer data: `npc_trainer` entries for mage spells
- Conjured item IDs: food/water items created by each conjure rank
- Vendor data for grind module: common vendor NPCs and their locations

Build `spell_catalog.lua` entries from actual DB data.

## Codebase Conventions

**MUST follow these patterns** (read these files before writing any code):

1. **Rotation profile pattern**: Read `sentinel/modules/combat/profiles/paladin/retribution_tbc.lua` and all 4 paladin files (`retribution_actions.lua`, `retribution_conditions.lua`, `maintenance_tree.lua`). Your mage profile MUST match this structure exactly: `build()`, 3 BT runners, conditions as closures, actions using dispatcher.

2. **BT construction**: Use `sentinel/core/bt/factory.lua` -- `BT.sequence()`, `BT.selector()`, `BT.condition()`, `BT.action()`, `BT.cooldown()`.

3. **Spell dispatching**: Use `sentinel/modules/combat/spell_dispatcher.lua` -- `queue_target()` / `queue_position()` with priorities from `sentinel/shared/queue_priorities.lua` (INTERRUPT=7, DEFENSIVE=6, UTILITY=5, BURST=4, PRIMARY=3, MAINTENANCE=2, LOW=1).

4. **Blackboard keys**: Register new keys in `sentinel/core/blackboard_schema.lua`. Use `sentinel/shared/blackboard_keys.lua` for constants. Allowed prefixes: system, player, combat, rotation, bg, nav, module.

5. **Event bus**: Publish events through `sentinel/core/event_bus.lua`. Follow existing naming convention: `grind:mob_pulled`, `grind:loot_complete`, `grind:rest_started`, etc.

6. **Navigation**: Use `sentinel/integrations/nav_client/adapter.lua` -- `move_to(position)`, `follow_path(waypoints)`, `poll()`, `stop(reason)`, `is_active()`, `get_state()`.

7. **Sylvannas API only** -- NEVER use WoW Lua APIs. All game interaction through `.api/` stubs: `core.lua` (logging, HTTP, object manager), `game_object.lua` (unit methods), `common/izi_sdk.lua` (extended helpers), `common/modules/spell_queue.lua`, `common/utility/spell_helper.lua`.

8. **require() uses forward slashes**: `require("core/blackboard")` NOT `require("core.blackboard")`. Dots are treated literally.

9. **Module registration**: New modules register through `sentinel/runtime/module_registry.lua`.

10. **Error boundaries**: Wrap module updates with `sentinel/core/error_boundary.lua`.

## Success Criteria

The implementation is complete when:

1. Grinding module starts, finds mobs, pulls, delegates combat, loots, rests, and repeats indefinitely
2. Vendor runs trigger when bags are full and successfully sell + return to grind area
3. Trainer visits trigger on level-up and train all available spells
4. Mage Frost rotation handles single-target combat at any level 1-70
5. AoE farming mode gathers, novas, blizzards, and kites correctly
6. Mage maintenance keeps buffs up and conjures food/water when stacks are low
7. Corpse run works after death (release -> navigate -> resurrect)
8. All new code has tests following the pattern in `sentinel/tests/`
9. Mage profile registers in `sentinel/modules/combat/profiles/registry.lua`
10. UI tab exists for grind module settings (zone center/radius, thresholds, mob filters, AoE toggle)
