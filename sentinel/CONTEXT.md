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

## Runtime ↔ Editor Event Contract (SENT-8.7/8.8/8.9)

Cross-cutting event vocabulary emitted by `RuntimeEngine` (via EventBus) and
consumed by UI panels. Resolved during the Phase 10/11 grill; shared so the
engine and panels never drift.

- **`validation_failed`** `{ profile_id, errors }` — emitted by
  `RuntimeEngine:validate()` when a dirty operation fails continuous
  validation (SENT-8.7). Engine halts. Side-effect: also publishes
  `validation:clear` then one `validation:add` per error (shape
  `{ severity = "error", code, message, entity_ref = op_id }`) so the existing
  `ValidationPanel` lights up with no panel-side changes.
- **`reload_rejected`** `{ profile_id, errors }` — emitted by
  `RuntimeEngine:reload_profile()` when an incoming hot-reload profile fails
  validation; the old profile is retained (SENT-8.8).
- **`profile_reloaded`** `{ profile_id }` — emitted after a successful hot
  reload (SENT-8.8).
- **`command_history:changed`** `{ can_undo, can_redo }` — emitted by
  `CommandHistory` on execute/undo/redo (SENT-8.9). Toolbar/Inspector Undo/Redo
  buttons subscribe to enable/disable themselves.
- **`validation:add` / `validation:clear` / `validation:updated`** — existing
  `ValidationPanel` contract; the engine republishes `validation_failed`
  errors into this shape to reuse the panel.

**Dogfood Profile** — a real, loadable authoring profile (JSON under
`profiles/authoring/`) covering an end-to-end questing flow (e.g. Human 1–10)
that passes `ProfileManager:prepare` with zero validation errors. Used as the
Phase 11 smoke/sanity profile.