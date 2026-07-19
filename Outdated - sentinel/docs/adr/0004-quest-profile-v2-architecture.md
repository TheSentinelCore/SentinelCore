# ADR 0004: Quest Profile v2 — Hand-Authored Declarative Profiles

## Context

The current quest module auto-generates leveling plans from the Mangos database using `QuestPlanner`, `QuestScorer`, `RuleEngine`, and `ObjectivePlanner`. The user proposes replacing this with **hand-authored declarative profiles** that describe *intent* (objective groups, conditions, routing policies) rather than generated waypoint sequences.

This is a **Big Bang migration** — the entire planning layer is replaced in one cutover.

## Decision

### Survive (minimal changes)
- `NavAdapter` — navigation for travel steps
- `QueryClient` — DB access for validation/authoring
- `QuestieAdapter` — runtime quest state
- `Tracker` — active quest tracking
- `Heatmap` — runtime analytics
- `FlightOptimizer` — flight path logic
- `RewardSelector` — quest reward selection

### Repurpose (significant rewrite)
- `Engine` → `PhaseRunner` — executes declarative steps; no longer builds plans
- `QuestPhases` → `StepExecutors` — each phase becomes a reusable executor (`TravelExecutor`, `KillExecutor`, `CollectExecutor`, `InteractExecutor`, `VendorExecutor`, `RepairExecutor`, `TrainExecutor`)

### Delete (replaced entirely)
- `QuestPlanner` — no auto-planning
- `ObjectivePlanner` — profiles declare objective groups + routes by hand
- `QuestScorer` — profiles declare `priority`; no scoring algorithm
- `RuleEngine` — profiles embed their own `conditions`, `rules`, `overrides`
- `QuestProfileManager` — replaced by `ProfileLoader` for v2 format
- `QuestGraph` (graph-building logic) — replaced by `QuestRegistry` (read-only DB cache for validation/authoring)

### New Modules
- `ProfileLoader` — load, parse, validate v2 profile JSON
- `ProfileValidator` — validate against `QuestRegistry` (quest IDs, NPCs, prereqs, no cycles)
- `ConditionEngine` — evaluate declarative conditions (`questAccepted(id)`, `level>=N`, `inventoryFull`, etc.)
- `StateMachine` — generic state machine runner (profile = state machine with states: Initialize, Accept, Travel, Complete, TurnIn, Vendor, Repair, Train, Fly, Grind, Recover, Finished)
- `ProfileExecutor` — orchestrates StateMachine + ConditionEngine + PhaseRunner + StepExecutors

## Consequences

**Positive:**
- Profiles are strategic, not algorithmic — captures "accept now, do later", "skip breadcrumb", "die to spirit rez" optimizations
- Same execution engine improves over time without profile rewrites
- Profiles are validatable, simulatable, auditable
- Authoring tooling (visual editor, simulator) can target the declarative DSL

**Negative:**
- High upfront authoring cost per zone (mitigated by macros, variables, visual editor)
- Migration is all-or-nothing — no gradual zone-by-zone rollout
- Loss of auto-discovery for new/unknown zones (mitigated: authoring tool + QuestRegistry makes it fast)

**Risks:**
- Profile authoring becomes a specialized skill
- Simulation/validation tooling is critical path — without it, profiles will have bugs

## Status

Accepted — proceeding with Big Bang migration.