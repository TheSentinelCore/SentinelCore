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

## Navigation Integration

**NavigationAdapter** — wraps `_G.SentinelNavClient.client` for pathfinding, raycasting, and random point generation via SentinelNavServer.

## Testing Concepts

**TestHarness** — out-of-game Lua test runner (target: busted or custom) that mocks Sylvannas APIs for unit/integration tests.

**InGameTestRunner** — existing `_G.SentinelCore.run_tests()` for in-game validation.