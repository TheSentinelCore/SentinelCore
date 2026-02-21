# SentinelCore Warlock Affliction (TBC) Implementation Plan

Last updated: 2026-02-21
Scope: SentinelCore rotation framework; TBC Classic Warlock Affliction provider; zero-manual-config behavior from level 1 through 70; compatibility with solo/dungeons/raids/PvP contexts.

## 1. Objectives and Acceptance Criteria

### 1.1 Primary Objectives
- Implement a production-quality Warlock Affliction provider using SentinelCore’s existing framework-first architecture.
- Mirror the existing Retribution provider structure and conventions so the class implementation remains a reusable template for future providers.
- Ensure operation from level 1 to level 70 with no manual setup.
- Resolve spell ranks dynamically through `SpellbookResolver:best_rank(name, fallback_ids)` and skip unlearned spells safely.
- Cover Warlock combat subsystems:
  - Pet management (summon, attack command, pet sustain)
  - Soul shard handling (counting, summon gating, Drain Soul replenishment path)
  - DoT maintenance
  - Mana sustain (Dark Pact/Life Tap)
  - Proc handling (Nightfall/Backlash)

### 1.2 Non-Goals (v1)
- No engine-level action type additions (for example, no new `cast_spell_position` action in `ActionBuilder`).
- No UI editor panel additions for Warlock policy values in `SentinelCore/ui/window.lua` (defaults + runtime policy plumbing already support zero-manual-config operation).
- No pet spell micromanagement (for example, Felhunter Spell Lock AI) in v1.

### 1.3 Exit Criteria
- Warlock class (ID 9) resolves a provider and generates valid plans.
- All provider phases return deterministic action tables sorted by priority through existing PlanComposer behavior.
- Rotation skips unlearned spells without hardcoded level gates.
- Early levels correctly support Imp summon behavior (including level 1).
- Soul shard logic prevents repeated invalid summons and supports replenishment via Drain Soul.
- Existing Paladin behavior remains backward-compatible.
- Config/runtime validation and tests remain green after class 9 introduction.

## 2. Confirmed Decisions (from review)

### 2.1 Decision 8: Include additional framework hardening
Confirmed: **Yes**.
- Include `Config.lua` runtime rotation validation updates for Warlock policy bounds.
- Update tests expecting class 9 to be unsupported.

### 2.2 Decision 9: Include explicit shard generation path
Confirmed: **Yes**.
- Include `Drain Soul` in spell catalog and provider logic.
- Use shard-count-based condition for execute/replenishment window.

### 2.3 Decision 10: Rain of Fire framework compromise
Confirmed: **Yes**.
- Use current framework constraints (`self_spell` + `max_target_distance`) as interim behavior.
- Defer true position-cast implementation to a future engine enhancement.

## 3. Architectural Constraints and Conformance

### 3.1 Provider pattern parity with Retribution
The new provider must follow the same method ordering and helper conventions used in:
- `SentinelCore/rotations/paladin/Retribution.lua`

Conformance points:
- Same imports (`ActionBuilder`, `ConsumableCatalog`, `SpellCatalog`, `AuraCatalog`, `RankPolicy`)
- Same helper styles (`spell_id`, `resolve_spell`, `is_learned`, `policy`, `target_spell`, `self_spell`, `has_any_aura`)
- Same provider contract (`id`, `class_id`, `spec_id`, `spec`, `can_run`, phase methods)

### 3.2 Runtime APIs (Sylvannas)
Only documented APIs are used:
- `player:get_pet()`
- `core.input.pet_attack(target)`
- existing spell/inventory/unit APIs already used by SentinelCore modules

### 3.3 No hardcoded level checks
Spell availability is inferred exclusively from dynamic rank resolution + learned checks.

## 4. File-by-File Change Plan

### 4.1 Create: `SentinelCore/rotations/warlock/Affliction.lua`
Purpose: Full Warlock Affliction provider with framework-first composition.

Planned structure:
1. Module declaration + imports + class/spec constants
2. Spell/Aura local bindings
3. Policy defaults
4. Helper section
   - spell resolution/cache helpers
   - learned checks
   - aura helpers
   - armor/pet/shard helpers
   - pet attack side-effect helper
5. Provider identity methods
6. Phase methods (`precombat`, `maintenance`, `should_hold_maintenance`, `defensive`, `interrupt`, `utility`, `combat`, `aoe`)
7. Pull profile
8. Module return

### 4.2 Modify: `SentinelCore/rotations/framework/SpellCatalog.lua`
Add `SpellCatalog.WARLOCK.AFFLICTION` with complete rank lists.

Includes:
- Core damage toolkit, utility/defensive spells, armor buffs, pet summons, misc (wand).
- **Drain Soul added** for shard subsystem.
- Correct highest->lowest rank ordering for each spell.

### 4.3 Modify: `SentinelCore/rotations/framework/AuraCatalog.lua`
Add `AuraCatalog.WARLOCK.AFFLICTION` with:
- target DoT debuff lists
- armor buff lists
- proc aura IDs (`SHADOW_TRANCE`, `BACKLASH`)
- defensive passive auras used by checks

### 4.4 Modify: `SentinelCore/rotations/framework/CombatContext.lua`
Enhance context payload with:
- `target_has_aura(spec)`
- `pet`
- `pet_health_pct`

Implementation details:
- Reuse existing `unit_has_aura` closure.
- Pet considered valid only if object is valid and not dead.
- `pet_health_pct` via existing normalized helper path.

### 4.5 Modify: `SentinelCore/rotations/Providers.lua`
Register class 9 provider in current class-catalog format.

### 4.6 Modify: `SentinelCore/core/Defaults.lua`
Add `Defaults.rotation.warlock.affliction` policy defaults.

### 4.7 Modify (hardening): `SentinelCore/core/Config.lua`
Extend strict runtime rotation policy validation:
- add bounds table for `warlock.affliction`
- validate all numeric threshold fields in `[0.0, 1.0]`
- keep existing paladin validation intact

### 4.8 Modify (test maintenance): `SentinelCore/tests/test_sc008_rotation_engine.lua`
Update class-9 unsupported assertion to a truly unsupported class after provider registration.

### 4.9 Create (regression coverage): `SentinelCore/tests/test_rotation_warlock_affliction_regressions.lua`
Add direct provider regression tests similar to Retribution tests:
- can_run for class 9
- spell selection skips unlearned actions
- maintenance emits food/water + summon behavior
- combat includes DoT/filler/wand lanes
- proc-triggered instant shadow bolt priorities
- shard-based summon fallback logic

### 4.10 Modify: `SentinelCore/tests/run_all.lua`
Include new Warlock regression suite.

## 5. Spell Registry (Final Planned Contents)

## 5.1 SpellCatalog entries (`WARLOCK.AFFLICTION`)
Damage:
- SHADOW_BOLT
- CORRUPTION
- CURSE_OF_AGONY
- IMMOLATE
- SIPHON_LIFE
- UNSTABLE_AFFLICTION
- DRAIN_LIFE
- DRAIN_SOUL
- SEED_OF_CORRUPTION
- RAIN_OF_FIRE
- INCINERATE
- SEARING_PAIN

Defensive/Utility:
- DEATH_COIL
- FEAR
- HOWL_OF_TERROR
- LIFE_TAP
- DARK_PACT
- HEALTH_FUNNEL

Armor:
- DEMON_SKIN
- DEMON_ARMOR
- FEL_ARMOR

Pet Summons:
- SUMMON_IMP
- SUMMON_VOIDWALKER
- SUMMON_SUCCUBUS
- SUMMON_FELHUNTER
- SUMMON_FELGUARD

Misc:
- CREATE_HEALTHSTONE
- SHOOT

Notable correction:
- `UNSTABLE_AFFLICTION.ids` ordered highest-first as `{ 30405, 30404, 30108 }`.

## 5.2 AuraCatalog entries (`WARLOCK.AFFLICTION`)
Target debuffs:
- CORRUPTION
- CURSE_OF_AGONY
- IMMOLATE
- SIPHON_LIFE
- UNSTABLE_AFFLICTION
- SEED_OF_CORRUPTION

Player buffs:
- DEMON_SKIN
- DEMON_ARMOR
- FEL_ARMOR
- SOUL_LINK

Procs:
- SHADOW_TRANCE
- BACKLASH

## 6. Provider Policy Model

### 6.1 Defaults
```lua
{
  drink_mana_pct            = 0.40,
  eat_health_pct            = 0.65,
  life_tap_min_health_pct   = 0.50,
  life_tap_max_mana_pct     = 0.60,
  life_tap_ooc_max_mana_pct = 0.85,
  death_coil_hp_pct         = 0.25,
  drain_life_hp_pct         = 0.45,
  health_funnel_pet_hp_pct  = 0.30,
  health_potion_hp_pct      = 0.25,
  mana_potion_mana_pct      = 0.15,
  mana_potion_min_hp_pct    = 0.35,
  wand_mana_pct             = 0.08,
}
```

### 6.2 Resolution
`ctx.routine_policy.warlock.affliction` overrides defaults with the same merge semantics used by Retribution.

## 7. Helper Function Plan (Affliction.lua)

### 7.1 Core spell helpers
- `spell_id(value)`
- `resolve_spell(ctx, spec, fallback)`
  - resolves via `ctx.resolve_spell_id(name, fallback_ids)`
  - returns `nil` when unresolved or unlearned
  - uses per-context cache to avoid repeated rank lookups
- `is_learned(spell)`

### 7.2 Policy helper
- `policy(ctx)` -> merged policy table

### 7.3 Action wrappers
- `target_spell(spec, priority, opts)`
- `self_spell(spec, priority, opts)`

### 7.4 Aura helpers
- `has_any_aura(ctx, ids)`
- `target_missing_aura(ctx, ids)` helper for DoT checks

### 7.5 Armor/pet helpers
- `has_armor_buff(ctx)`
- `best_armor_spell(ctx)` (Fel > Demon Armor > Demon Skin)
- `soul_shard_count(ctx)`
- `has_soul_shard(ctx)`
- `best_summon_spell(ctx)` (Felguard > Voidwalker > Imp, shard-aware)
- `ensure_pet_attack(ctx)`

### 7.6 Channel/cast safety helpers
- `player_is_channeling(ctx)`
- `player_is_casting(ctx)`
- `rotation_unlocked(ctx)` for non-emergency clipping control

## 8. Phase-by-Phase Priority Plan

## 8.1 `maintenance(ctx)`
1. Prio 980: Drink water (OOC, stationary, not already drinking/eating)
2. Prio 970: Eat food (OOC, stationary, not already drinking/eating)
3. Prio 260: Apply best armor buff when missing
4. Prio 255: Summon best available pet when no living pet, OOC, stationary
5. Prio 250: OOC Life Tap with safe HP gate
6. Prio 245: Create Healthstone when missing one and shard is available (OOC utility)

## 8.2 `should_hold_maintenance(ctx)`
Returns true when:
- currently eating/drinking
- HP below eat threshold
- Mana below drink threshold

## 8.3 `defensive(ctx)`
1. Prio 1000: Death Coil emergency
2. Prio 995: Best health potion
3. Prio 945: Drain Life sustain cast
4. Prio 620: Best mana potion (with HP guard)

## 8.4 `interrupt(ctx)`
1. Prio 760: Death Coil with `target_must_be_casting = true`, 30y

## 8.5 `utility(ctx)`
- Top side-effect: `ensure_pet_attack(ctx)`
1. Prio 690: Armor rebuff if missing
2. Prio 680: Health Funnel when pet low and player healthy
3. Prio 650: Dark Pact at low mana
4. Prio 640: Life Tap fallback at low mana with safe HP

## 8.6 `combat(ctx)` (single target)
1. Prio 570: Shadow Bolt on Nightfall proc
2. Prio 565: Shadow Bolt on Backlash proc
3. Prio 555: Corruption refresh
4. Prio 550: Curse of Agony refresh
5. Prio 545: Siphon Life refresh (if learned)
6. Prio 540: Unstable Affliction refresh (if learned)
7. Prio 535: Immolate refresh
8. Prio 530: Drain Soul execute/replenish window when shard count low
9. Prio 520: Shadow Bolt filler above wand mana threshold
10. Prio 510: Shoot/wand fallback

## 8.7 `aoe(ctx)` (3+ enemies)
1. Prio 580: Seed of Corruption when missing
2. Prio 560: Rain of Fire (framework compromise)
3. Prio 555: Corruption spread
4. Prio 520: Shadow Bolt filler
5. Prio 510: Shoot/wand fallback

## 9. Pull Profile Plan

- Prefer best-rank Shadow Bolt with 30y pull range.
- Fallback to best-rank Immolate with 30y pull range.

## 10. CombatContext Change Details

Implementation insertion points:
- Add `target_has_aura` closure adjacent to `player_has_aura` closure.
- Resolve pet object from player and validate alive/valid.
- Add `pet` and `pet_health_pct` to returned context table.

Backward compatibility:
- Additive fields only.
- Existing providers unaffected.

## 11. Edge Case Matrix and Handling Path

1. Level 1 Warlock with Imp available:
- `best_summon_spell` resolves Imp and maintenance summon action executes when no pet.

2. Low-level without shard-capable summons:
- Summon path remains valid via Imp fallback.

3. No shard available but Voidwalker/Felhunter/Felguard learned:
- Summon helper skips shard-required pets and falls back to Imp.

4. Movement during combat:
- Instant DoTs marked `allow_movement = true`; cast-time spells remain movement-blocked.

5. OOM:
- Utility phase Dark Pact/Life Tap first, then wand fallback in combat/aoe.

6. Nightfall proc:
- Aura check triggers prio-570 instant Shadow Bolt.

7. Backlash proc:
- Aura check triggers prio-565 instant Shadow Bolt.

8. Pet low HP:
- Health Funnel utility action with dual HP gate.

9. Pet dead or missing:
- OOC maintenance summon path.

10. Missing armor buff:
- Both maintenance and utility can rebuff.

11. Unlearned spell:
- `resolve_spell` returns `nil`; action is blocked before execution.

12. Channel clipping:
- Non-emergency rotational actions gated by channel/cast helper checks; emergency Death Coil remains top-priority.

13. Non-affliction talent setup on class 9:
- Class-only run gate + learned-spell checks keep behavior safe.

14. Soul shard sustain:
- Drain Soul execute lane plus shard-aware summon/create-healthstone gating.

## 12. Config and Validation Plan

`SentinelCore/core/Config.lua` updates:
- Add `AFFLICTION_POLICY_BOUNDS` table with all fields in `[0,1]`.
- Extend `validate_rotation_policy(rotation_cfg)`:
  - require `rotation_cfg.warlock.affliction` table
  - validate all affliction keys through bounds table
  - keep existing Paladin checks untouched

Reason:
- Runtime/profile saves remain fail-closed and schema-safe for added class policy.

## 13. Testing Plan

### 13.1 Regression update
- Update `test_sc008_rotation_engine.lua` class-9 unsupported assertion to another unsupported class.

### 13.2 New warlock provider regression suite
Create `test_rotation_warlock_affliction_regressions.lua`:
- provider class gate checks
- maintenance action presence
- summon fallback behavior with and without shards
- proc action inclusion
- DoT action guards using `target_has_aura`
- filler/wand behavior

### 13.3 Full suite
- Add new test to `tests/run_all.lua`
- Run SentinelCore test harness and verify no regressions.

## 14. Implementation Sequence

1. Create plan doc (this document).
2. Implement framework/catalog/context/provider registration/defaults.
3. Implement Affliction provider.
4. Apply config validation hardening.
5. Add/update tests.
6. Execute tests.
7. Summarize changed files + results.

## 15. Risk Register

1. Risk: rank fallback returns unlearned IDs in resolver edge cases.
- Mitigation: provider-level `is_learned` enforcement in `resolve_spell`.

2. Risk: pet_attack spam concerns.
- Mitigation: command is idempotent; keep guarded by combat/target/pet validity.

3. Risk: Rain of Fire targeting precision.
- Mitigation: accepted interim compromise until position-cast action exists.

4. Risk: strict config validation could reject malformed persisted profiles.
- Mitigation: bounds mirror Defaults exactly; validation remains deterministic and explicit.

## 16. Deliverables Checklist
- [ ] `rotations/warlock/Affliction.lua` created
- [ ] `SpellCatalog.lua` Warlock block added
- [ ] `AuraCatalog.lua` Warlock block added
- [ ] `CombatContext.lua` target aura + pet fields added
- [ ] `Providers.lua` class 9 provider registration added
- [ ] `Defaults.lua` warlock.affliction defaults added
- [ ] `Config.lua` warlock validation added
- [ ] rotation engine test for class 9 expectation updated
- [ ] warlock regression tests added
- [ ] test suite run and results captured
