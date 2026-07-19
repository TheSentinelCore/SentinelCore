---
id: 10
title: "Cleanup — Delete Old Planning Layer (QuestPlanner, ObjectivePlanner, QuestScorer, RuleEngine, QuestProfileManager, QuestGraph Builder)"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:medium", "size:medium"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

# Cleanup — Delete Old Planning Layer

## Description

Remove the auto-planning modules that are replaced by hand-authored profiles + statechart executor. This is the "Big Bang" cutover.

## Modules to DELETE

| Module | Replaced By |
|--------|-------------|
| `sentinel/modules/quest/quest_planner.lua` | Hand-authored profile (`Questing` region) |
| `sentinel/modules/quest/objective_planner.lua` | Profile's `CompleteObjectives` hierarchy |
| `sentinel/modules/quest/quest_scorer.lua` | No scoring — profile declares priority |
| `sentinel/modules/quest/rule_engine.lua` | Profile embeds conditions/rules/overrides |
| `sentinel/modules/quest/quest_profile_manager.lua` | `ProfileLoader` (loads compiled profiles) |
| `sentinel/modules/quest/quest_graph.lua` (graph-building logic) | `QuestRegistry` (on-demand query) |

**Keep** `QuestGraph` as read-only data accessor if used by `QuestRegistry`, or merge into `QuestRegistry`.

## Modules to REPURPOSE

| Old Module | New Module | Changes |
|------------|------------|---------|
| `sentinel/modules/quest/engine.lua` | `sentinel/modules/quest/phase_runner.lua` | Remove `build_plan`, `get_available_quests`, `get_quest_chain`, `get_overlapping_quests`. Keep: `get_quest_givers`, `get_quest_turnins`, `get_quest_data`, `can_turn_in`, `get_active_quests`, `get_active_quest_ids`, `is_on_quest`, `acceptQuest`, `turnInQuest`, `selectBestReward`. |
| `sentinel/modules/quest/quest_phases.lua` | `sentinel/modules/quest/step_executors/*.lua` | Split into: `TravelExecutor`, `InteractExecutor`, `KillExecutor`, `CollectExecutor`, `EscortExecutor`, `VendorExecutor`, `RepairExecutor`, `TrainExecutor`, `FlyExecutor`, `GrindExecutor`, `RecoverExecutor`. Each is a stateless function: `executor:execute(step, ctx)` → returns coroutine. |

## Module to UPDATE

| Module | Changes |
|--------|---------|
| `sentinel/modules/quest/module.lua` | Remove `QuestPlanner`, `QuestScorer`, `RuleEngine`, `ObjectivePlanner`, `QuestProfileManager`, `QuestGraph` (builder) instantiation. Add `ProfileLoader`, `ProfileExecutor` (wraps `StatechartExecutor`), `PhaseRunner`, `StepExecutors`. Wire `Quest` module to start `ProfileExecutor` on enable. |

## File Operations

1. **Delete** (after verifying no external deps):
   - `sentinel/modules/quest/quest_planner.lua`
   - `sentinel/modules/quest/objective_planner.lua`
   - `sentinel/modules/quest/quest_scorer.lua`
   - `sentinel/modules/quest/rule_engine.lua`
   - `sentinel/modules/quest/quest_profile_manager.lua`
   - `sentinel/modules/quest/quest_graph.lua` (or keep as data accessor, rename to `quest_data.lua`)

2. **Rename + Refactor**:
   - `engine.lua` → `phase_runner.lua` (strip planning, keep execution helpers)
   - `quest_phases.lua` → `step_executors/init.lua` + individual executor files

3. **Create New**:
   - `sentinel/modules/quest/profile_loader.lua` — loads compiled profiles from `scripts_data/quest_profiles/`
   - `sentinel/modules/quest/profile_executor.lua` — wraps `StatechartExecutor` + `PhaseRunner`
   - `sentinel/modules/quest/step_executors/*.lua` — 11 executor files

## Acceptance Criteria

- [ ] All deleted files removed from disk and `require` calls
- [ ] No `require("modules/quest/quest_planner")` etc. anywhere in codebase
- [ ] `PhaseRunner` executes steps without planning logic
- [ ] `StepExecutors` cover all step types used in first profile
- [ ] `ProfileLoader` loads compiled profile from `scripts_data/quest_profiles/<id>.json`
- [ ] `Quest` module starts `ProfileExecutor` when enabled
- [ ] Old BT phases no longer used for questing (grind phases unchanged)
- [ ] All tests pass (or tests updated for new architecture)
- [ ] No Lua errors on module load

## Blocked by

- **01-profile-compiler** through **09-ingame-editor-mvp** — all v2 runtime must work before cleanup

## Files to Modify

- `sentinel/modules/quest/module.lua` — major refactor
- `sentinel/modules/quest/engine.lua` → `phase_runner.lua` (rename + strip)
- `sentinel/modules/quest/quest_phases.lua` → `step_executors/` (split)
- Delete files listed above