# SentinelCore Domain Model

## Grind Module Concepts

**ConsumeManager** — manages consumable item consumption with verification. Hides the state machine for tracking eating/drinking attempts, measuring resource recovery, and handling retries when consumption stalls.

**Rest Phase** — behavior tree phase that consumes food/water until health/mana recovery thresholds are met, then signals completion.

**Vendor Phase** — behavior tree phase that delegates to VendorStateMachine for navigating to vendor, repairing gear, selling unwanted items, and purchasing consumables.

**VendorStateMachine** — encapsulates the multi-state vendor interaction lifecycle (traveling, interacting, repairing, selling, buying consumables). Owns its state internally; callers only see `tick()`, `reset()`, and `is_running()`.

**ThreatType** — a descriptor for a category of threat (DEATH, PVP_PLAYER, DANGEROUS_MOB, STUCK) with a default weight and half-life. Replaces raw string + weight pairs in ThreatMap calls.

**ThreatMap** — spatial heat map of dangerous locations, accumulating threat entries from deaths, PvP players, and stuck events.

**Flee Point** — a position computed as "away from threat center" used during safety flee behavior.

**Attack Neutral** — a grind module setting (`module.grind.attack_neutral`) that when enabled allows the bot to target and attack neutral (yellow) mobs in addition to hostile (red) mobs. Used by level 1 characters who can only auto-attack, since neutral mobs become attackable when targeted.

## Combat Module Concepts

**SpellDispatcher** — queues spells via the spell_queue system, handling target and position-based spell casting with signature deduplication.

**ActionLibrary** — factory of behavior tree leaf actions that delegate to SpellDispatcher.

**CombatZone** — state in battleground module tracking whether the player is in an active combat area (tier 2/3 detection).

## Spatial Concepts

**Distance** — 3D distance between coordinates, with nil-safe handling returning infinity for invalid inputs.

**Away From** — computes a position at a given distance "away from" a center point, used for flee behavior.

## Quest Authoring IDE Concepts

**Project** — the top-level authoring unit (e.g., "Elwynn Forest"), containing zones, operations, blueprints, and compiler settings.

**Zone** — a geographic region within the project (e.g., "Northshire", "Goldshire") that groups related operations.

**Operation** — a linear sequence of author intent representing a chapter of gameplay (e.g., "Northshire Cleanup"). Contains actions arranged on a timeline.

**Action** — an atomic unit of author intent (e.g., "Pickup Quest", "Kill Target", "Travel", "Turn In", "Vendor", "Repair"). Actions are parameterized and may reference database entities.

**Blueprint** — a reusable, parameterized action template that expands into a subgraph of actions (e.g., "QuestHub" expands to Travel + Accept + Vendor + Repair + Train + Hearth + TurnIn + AcceptFollowUps). Blueprints enable DRY authoring.

**Compiler Level** — a semantic transformation pass in the compiler pipeline:
- **Level 1**: Resolve NPC/quest/item IDs from Mangos DB, inject coordinates
- **Level 2**: Insert implied actions (loot after kill, interact after pickup, turn-in after completion)
- **Dead Code Elimination**: Skip quests obsoleted by higher quests in same operation (deterministic DB lookup)
- **Level 3**: Merge/reorder objectives for efficiency (requires analytics, interface-only in v1)
- **Level 4**: Human-approval optimizations (death-skip, delay breadcrumb, skip quest) — deferred

**Compiled Profile** — the JSON output of the compiler, consumed by the StatechartExecutor. Contains resolved actions with full execution semantics (transitions, guards, actions, variables). Zero Mangos field names appear in this format.

**Execution Graph** — the fully expanded state machine (debug-only view). Not persisted in v1; maintained as in-memory compiler artifact.

**Design** — the source authoring layer (YAML files with .operation.yaml and .blueprint.yaml extensions) that the compiler consumes.

**Profile Variable** — a named, typed slot in the profile's data model, optionally bound to a blackboard path for reactive updates (e.g., `bagSlotsFree: {type: "number", bind: "inventory.freeSlots"}`).

**Routing Policy** — a declarative specification for dynamic pathfinding (strategy, avoidance, preferences) resolved at runtime by NavServer. Replaces hardcoded waypoint lists.

**Action Registry** — hybrid: core actions = engine methods (global, stable API); profile actions = inline Lua in YAML, compiled to bytecode per-blueprint/action.

### IDE Architecture and Location

The Quest Authoring IDE is an **in-game Sylvannas UI module** located within the SentinelCore codebase (e.g., `sentinel/ui/quest_authoring/`). It interacts with the quest system as follows:

- **Source Files**: Edits YAML files in project directories (e.g., `sentinel/data/profiles/quests/elwynn/`)
- **Compiler Integration**: Invokes the SentinelCore compiler (a library in `sentinel/modules/quest/`) to transform YAML → JSON
- **Hot Reload**: Watches for file changes and notifies the StatechartExecutor to hot-swap updated profiles
- **World Selection**: Uses Sylvannas input APIs to allow clicking NPCs/objects in-game to populate action fields directly
- **UI Framework**: Built with Sylvannas UI APIs (frames, textures, fonts, input handling) running inside the game client

This approach provides:
- True in-game world selection capabilities
- Immediate feedback within the actual game environment
- No context switching between external IDE and game
- Direct integration with existing SentinelCore systems