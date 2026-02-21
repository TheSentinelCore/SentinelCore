# SentinelCore Combat Framework + Retribution Routine Implementation Plan

Last updated: 2026-02-21
Scope: TBC Sylvanas runtime, SentinelCore combat framework improvements, Paladin Retribution routine hardening, reusable architecture for future class/spec routines.

## 1. Goals and Success Criteria

### 1.1 Primary Goals
- Build a reusable combat-routine framework suitable for all future classes/specs.
- Make Paladin Retribution the production-quality reference implementation.
- Eliminate known behavior defects:
  - Incorrect health/mana threshold interpretation (mixed unit scale).
  - Unreliable reseal after Judgement.
  - Non-deterministic or weak downranking behavior.
  - Missing/late potion usage.
  - Missing eat/drink maintenance behavior.

### 1.2 Non-Goals
- No quest/PvP additions.
- No cross-expansion compatibility work.
- No broad movement/pathfinding changes in this plan.

### 1.3 Exit Criteria
- Rotation behavior deterministic for identical context.
- Consumables (health/mana potions, food, drink) operate with explicit policy gates.
- Reseal cycle enforced with strict combat/maintenance logic.
- Downranking is policy-driven and reusable, not hardcoded ad hoc.
- All added behavior has regression tests.

## 2. Current State Findings (Baseline)

### 2.1 Strengths
- Existing `RotationEngine` supports provider contract, guard filters, queue-first execution.
- Existing `ActionBuilder` has reusable action primitives.
- Existing Ret provider already includes maintenance/defensive/combat separation and item actions.

### 2.2 Key Gaps
- Context percentages may be mixed between `0..1` and `0..100` depending on helper source.
- Spell rank resolution uses highest spell ID heuristic, which is not a robust rank-policy system.
- Reseal behavior is embedded and not framework-backed.
- Consumable policy exists but lacks a reusable manager for all future routines.

## 3. Target Architecture (Incremental)

### 3.1 New/Upgraded Framework Components
- `rotations/framework/CombatContext.lua`
  - Single source for normalized context values (health/mana/target health in `0..1`).
- `rotations/framework/RankPolicy.lua`
  - Reusable rank-selection policy (max rank, fallback rank, low-mana downrank).
- `rotations/framework/SpellCatalog.lua`
  - Shared spell name + fallback rank metadata for routine authors.
- `rotations/framework/AuraCatalog.lua`
  - Shared aura groups for buff/debuff detection.
- `rotations/framework/PlanComposer.lua`
  - Deterministic phase append/sort utility for provider plans.

### 3.2 RotationEngine Integration
- `RotationEngine` delegates context assembly to `CombatContext`.
- `RotationEngine` uses `PlanComposer` for phase ordering consistency.
- Existing guard/execute semantics remain fail-closed.

### 3.3 Retribution Routine Structure
- Keep provider interface stable.
- Internalize policy usage through framework modules:
  - Seal/aura checks via `AuraCatalog`.
  - Spell ranks via `SpellCatalog` + `RankPolicy`.
  - Healing thresholds explicit and deterministic.

## 4. Detailed Work Plan

## Phase A: Foundation and Contracts

### A1. Add normalized combat-context module
Files:
- `SentinelCore/rotations/framework/CombatContext.lua` (new)
- `SentinelCore/services/RotationEngine.lua` (refactor context builder)

Tasks:
- Build helper functions:
  - `normalize_pct(value)` -> converts `0..100` inputs to `0..1`.
  - Robust fallback derivation from raw health/max health and power/max power.
- Expose context fields currently used by providers, preserving compatibility.

Acceptance:
- Any helper path returns normalized `player_health_pct`, `player_mana_pct`, `target_health_pct` in `0..1`.
- No provider changes required for basic compatibility.

### A2. Add rank-policy framework
Files:
- `SentinelCore/rotations/framework/RankPolicy.lua` (new)

Tasks:
- Implement:
  - `select_max_rank(ctx, spell_name, fallback_ids)`
  - `select_downrank(ctx, spell_name, fallback_ids, preferred_rank_ids)`
  - `select_by_mana_policy(ctx, config)`
- Keep API provider-friendly and generic.

Acceptance:
- Rank selection deterministic and testable with mocked spellbook states.

### A3. Add spell/aura catalogs for reuse
Files:
- `SentinelCore/rotations/framework/SpellCatalog.lua` (new)
- `SentinelCore/rotations/framework/AuraCatalog.lua` (new)

Tasks:
- Add initial Paladin Ret entries used today.
- Keep schema generic for future class/spec extensions.

Acceptance:
- Ret provider no longer hardcodes repeated fallback lists where catalog entry exists.

## Phase B: Rotation Engine Determinism and Reuse

### B1. Add plan composer
Files:
- `SentinelCore/rotations/framework/PlanComposer.lua` (new)
- `SentinelCore/services/RotationEngine.lua` (update plan construction)

Tasks:
- Provide deterministic phase append + priority sort wrapper.
- Keep phase order contract explicit:
  - defensive
  - interrupt
  - utility
  - aoe/combat branch

Acceptance:
- Generated plans are stable for identical contexts.

### B2. Preserve fail-closed behavior
Files:
- `SentinelCore/services/RotationEngine.lua`

Tasks:
- Keep guarded execution as-is.
- Ensure unresolved dynamic spell/item resolution remains blocked with explicit error code.

Acceptance:
- No fail-open paths introduced.

## Phase C: Retribution Routine Hardening

### C1. Migrate Ret spell/aura resolution to framework
Files:
- `SentinelCore/rotations/paladin/Retribution.lua`

Tasks:
- Use `SpellCatalog`/`AuraCatalog` references.
- Route healing rank choices through `RankPolicy`.

Acceptance:
- Ret behavior preserved/improved with less ad hoc logic.

### C2. Reseal cycle guarantees
Files:
- `SentinelCore/rotations/paladin/Retribution.lua`

Tasks:
- Ensure post-Judgement reseal action remains in top combat priorities.
- Ensure maintenance reseal when out-of-combat and no seal present.

Acceptance:
- Judgement only cast when seal present.
- Reseal plan action emitted whenever seal missing and spell available.

### C3. Healing/downranking policy
Files:
- `SentinelCore/rotations/paladin/Retribution.lua`
- `SentinelCore/core/Defaults.lua` (new routine policy defaults)
- `SentinelCore/core/Config.lua` (runtime setting support)

Tasks:
- Add threshold policy knobs (defaults + runtime support):
  - emergency heal HP threshold
  - efficient heal HP threshold
  - low-mana downrank band
  - potion HP/MP thresholds
- Use max rank by default; only downrank in defined low-mana band.

Acceptance:
- Low-rank heal only used when policy conditions explicitly match.

### C4. Consumable and rest reliability
Files:
- `SentinelCore/rotations/paladin/Retribution.lua`
- `SentinelCore/rotations/framework/ConsumableCatalog.lua` (if expansion needed)

Tasks:
- Keep health/mana potion actions in defensive phase.
- Ensure eat/drink maintenance conditions remain strict and deterministic.

Acceptance:
- Combat plan includes potion actions.
- Maintenance plan includes food/water actions when policy allows.

## Phase D: UI + Settings Surface (Operator Control)

### D1. Expose routine policy settings
Files:
- `SentinelCore/ui/window.lua`
- `SentinelCore/core/Defaults.lua`
- `SentinelCore/core/Config.lua`
- `SentinelCore/core/Client.lua`

Tasks:
- Add settings controls for new retri policy knobs.
- Persist to active profile via existing save path.

Acceptance:
- Values survive reload via profile save/load.

## Phase E: Test and Validation

### E1. Add framework tests
Files:
- `SentinelCore/tests/test_rotation_context_normalization.lua` (new)
- `SentinelCore/tests/test_rotation_rank_policy.lua` (new)

Acceptance:
- Context normalization always yields `0..1`.
- Rank policy chooses expected IDs across mana scenarios.

### E2. Add Ret regression tests
Files:
- `SentinelCore/tests/test_rotation_retribution_regressions.lua` (new)
- `SentinelCore/tests/test_sc008_rotation_engine.lua` (extend)

Acceptance:
- Detects reseal-after-judgement behavior.
- Detects potion action presence.
- Detects maintenance eat/drink action presence.

### E3. Keep ticket runner inclusion up to date
Files:
- `SentinelCore/tests/run_all.lua` (if needed)

Acceptance:
- New tests are runnable from suite.

## 5. Risks and Mitigations

- Risk: helper API return-unit ambiguity (`0..1` vs `0..100`).
  - Mitigation: explicit normalization in `CombatContext`.
- Risk: rank selection regressions for unknown spellbooks.
  - Mitigation: safe fallback order, explicit tests.
- Risk: overfitting Ret logic to one environment.
  - Mitigation: reusable framework modules and clear contracts.

## 6. Implementation Sequence (Execution Order)
1. Add framework modules (`CombatContext`, `RankPolicy`, catalogs, `PlanComposer`).
2. Refactor `RotationEngine` to consume framework modules.
3. Refactor Retribution provider to framework modules + policy thresholds.
4. Wire settings defaults/config/UI.
5. Add tests and run available suite.

## 7. Deliverables Checklist
- [ ] New framework modules added.
- [ ] RotationEngine context builder replaced with normalized module.
- [ ] Retribution routine uses framework spell/aura/rank policy.
- [ ] Config/UI support for routine knobs.
- [ ] Regression and framework tests added.
- [ ] Test run report captured.
