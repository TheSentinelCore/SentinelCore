# SentinelCore Domain Model

## Combat Module Concepts

**SpellDispatcher** — queues spells via the spell_queue system, handling target and position-based spell casting with signature deduplication.

**ActionLibrary** — factory of behavior tree leaf actions that delegate to SpellDispatcher.

**TargetSelector** — evaluates and prioritizes valid targets based on range, threat, health, and class-specific logic.

**RotationEngine** — core combat loop that selects the next action from the priority list, manages GCD tracking, and coordinates with SpellDispatcher.

**ClassProfile** — per-class rotation definition (e.g., MageFrost, PaladinRetribution) containing spell priorities, conditions, and cooldown management.

**SpellCatalog** — registry of spell definitions (ID, name, cooldown, GCD, range, requirements) used by SpellDispatcher and RotationEngine.

## UI Module Concepts

**SentinelWindow** — top-level UI window container managing frame lifecycle, positioning, and visibility.

**SentinelUI** — shared UI primitives (frames, textures, fonts, input handling) built on Sylvannas UI APIs.

**ModulePanel** — per-module UI panel that registers with the main window (e.g., CombatPanel, SettingsPanel).

## Spatial Concepts

**Distance** — 3D distance between coordinates, with nil-safe handling returning infinity for invalid inputs.

**Away From** — computes a position at a given distance "away from" a center point, used for flee behavior.

## Core Engine Concepts

**BehaviorTree** — composite pattern implementation (sequences, selectors, parallels) with tick-based execution.

**Blackboard** — shared key-value state store with typed schema validation, scoped by domain (`player.*`, `combat.*`, `module.*`).

**EventBus** — decoupled publish/subscribe for cross-module communication (death, kill, engage, stuck events).

**Geometry** — math utilities for 3D positions, vectors, facing, and movement calculations.

**ModuleRegistry** — manages module lifecycle (init, enable, disable, tick) and dependency resolution.

**SensorHub** — aggregates game state sensors (player, target, nearby units, bags, spells) into blackboard updates.

**CallbackBridge** — bridges Sylvannas event callbacks into the EventBus.

**SentinelBridge** — seam layer between Sentinel and Sylvanas APIs. Provides:
- **QuestBridge** — wraps `core.quests.*` for quest dialogs, gossip, trainer interaction
- **AddonsBridge** — wraps `core.*` and `core.graphics.*` for unit queries, position, rendering
- **EventBridge** — translates Sylvanas game events to Sentinel semantic events (QuestAccepted, QuestCompleted, etc.)
- **RenderBridge** — immediate-mode overlay rendering via `register_on_render_callback`

## Runtime Model (one-tier, ADR 014)

**RuntimeAction** — the single canonical action model. Authored *and*
executed directly; there is no separate compiled form. Flat shape:
`{ action_type = "pickup_quest", ...params, retry_policy?, timeout_ms? }`.
`action_type` is snake_case. Consumed by exactly one executor
(`runtime/action_executor.lua`).

**Blueprint (editor macro)** — an authoring helper in
`runtime/blueprint_registry.lua` that **eagerly expands** to a list of
RuntimeActions when inserted in the editor. Not a compile-time stage; once
expanded the actions are ordinary authored actions (no `generated_from`
provenance, no generated-action lock).

**Prepare pass** — the thin pre-activation step that replaces the old
7-stage compiler: validate (structural / goal-coverage / dependency) →
confirm references already resolved → cross-Operation merge (adjacency
merge + reordering). Runs `profile_manager:prepare(profile)` then activate.

**Compile (deprecated term)** — historically the 7-stage ADR 008 pipeline
lowering an authoring Profile to a RuntimeProfile. Retired by ADR 014; do
not add new compile-tier logic. Reference resolution now happens at
author/save time (editor calls QueryServer), not at a compile step.

## Navigation Integration

**NavigationAdapter** — wraps `_G.SentinelNavClient.client` for pathfinding, raycasting, and random point generation via SentinelNavServer.

## Testing Concepts

**TestHarness** — out-of-game Lua test runner (target: busted or custom) that mocks Sylvannas APIs for unit/integration tests.

**InGameTestRunner** — existing `_G.SentinelCore.run_tests()` for in-game validation.