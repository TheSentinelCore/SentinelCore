# SentinelCore Architecture Overview

## Directory Structure

```
sentinel/
├── core/              # Behavior Tree engine and state management
├── modules/           # Feature modules (combat, grind, quest, mail, lfg, battleground)
├── runtime/           # Application lifecycle and sensors
├── integrations/      # External service wrappers (IZI, NavClient)
├── shared/            # Shared utilities, constants, types
├── ui/                # Tab-based settings window
├── lib/               # External libraries (JSON)
├── data/              # Static data (quests, profiles)
├── tests/             # Unit tests
├── header.lua         # Plugin metadata
└── main.lua           # Entry point
```

## Core Layer (`core/`)

### Behavior Tree Framework (`core/bt/`)

The behavior tree engine provides a tree-based execution model for game actions.

| File | Description |
|------|-------------|
| `node.lua` | Base node class. All nodes implement `tick()` returning Status and `reset()` for cleanup. |
| `status.lua` | Status constants: `SUCCESS`, `FAILURE`, `RUNNING`. Used to determine tree execution flow. |
| `factory.lua` | Factory functions create nodes: `BT.condition()`, `BT.action()`, `BT.sequence()`, `BT.selector()`, `BT.priority_selector()`. |
| `runner.lua` | Executes a root node each tick, wraps in error boundary, handles RUNNING state persistence. |
| `composites.lua` | `Sequence`: all children must succeed. `Selector`: first success. `PrioritySelector`: re-evaluates each tick. `Parallel`: runs multiple children simultaneously. |
| `decorators.lua` | Wraps child nodes: `Cooldown` (rate limit), `UntilFailure` (loop while failing), `RepeatUntilFailure` (retry). |
| `leaves.lua` | `Condition` node wraps function returning boolean. `Action` node wraps function returning Status. |

**Key Pattern:** Nodes receive blackboard and return Status. RUNNING persists across ticks.

### State Management

| File | Description |
|------|-------------|
| `blackboard.lua` | Key-value store with optional schema validation. Modules read/write shared state. Accessed via `bb:get(key, default)`, `bb:set(key, value)`. |
| `event_bus.lua` | Pub/sub with priority subscriptions. `subscribe(event, priority, fn)` returns token. `publish(event, data)`. |
| `error_boundary.lua` | Wraps function calls in `pcall`. Returns success status and prevents module crashes. |

### Blackboard Keys

Common keys (defined in `shared/blackboard_keys.lua` and `shared/constants.lua`):
- `player.*` - Health, mana, position, combat state, target
- `combat.*` - Target, enemy counts, swing timer, cooldowns, state
- `module.*` - Per-module state (combat, grind, quest, mail, lfg)
- `server.*` - Nav server status, last success timestamp

## Modules Layer (`modules/`)

### Combat Module (`modules/combat/`)

Automated combat rotation using behavior trees and spell queue.

#### State Machine (`state_machine.lua`)
States: `IDLE` → `ENGAGING` → `CASTING` → `KILLING` → `LEAVING_COMBAT` → `IDLE`. Triggered by combat events and sensor input.

#### Spell System
| File | Description |
|------|-------------|
| `spell_catalog.lua` | Spell definitions: `id`, `ranks`, `category`, `gcd_group`. Resolves best/lowest rank. |
| `spell_dispatcher.lua` | Queues spells via `spell_queue.queue_spell_target()`. Handles seal twist timing. |
| `cooldown_tracker.lua` | Tracks spell cooldown expiration. Checks via blackboard `module.combat.cooldowns`. |
| `swing_tracker.lua` | Auto-attack timer. Used for seal twist and melee logic. |

#### Target Selection
| File | Description |
|------|-------------|
| `target_selector.lua` | Validates targets: range, line of sight, enemy classification. |
| `pvp_target_selector.lua` | PvP-aware: priority to healers, avoids overextended targets. |
| `chase_controller.lua` | Navigates toward target in combat. Uses SentinelNavClient. |

#### Rotation DSL
| File | Description |
|------|-------------|
| `condition_library.lua` | 50+ reusable conditions. Health/mana thresholds, buff/debuff checks, spell ready checks, enemy count, combat state. |
| `action_library.lua` | Reusable actions. `cast_target()`, `cast_self()`, `interrupt()`, `use_item()`, `loot_target()`. |
| `priority_builder.lua` | DSL builder. `PriorityBuilder:add_priority(name, conditions, action, priority)`. Builds selector-based tree. |
| `shared_subtrees.lua` | Composable subtrees. Interrupt, defensive, execute, AoE patterns. |

#### Profiles
Profiles in `modules/combat/profiles/{class}/{spec}.lua` export:
- `build(blackboard, event_bus)` - Returns profile with `_maintenance`, `_off_gcd`, `_gcd` runners
- Conditions/actions in same folder for class-specific logic

### Grind Module (`modules/grind/`)

Dynamic grinding with hotspot navigation and profile support.

#### Master Tree (`grind_tree.lua`)
Priority selector with 8 phases (each is a subtree):
1. **safety.lua** - Flee when outnumbered or health critical
2. **corpse_run.lua** - Ghost → corpse navigation and resurrection
3. **rest.lua** - Food/drink consumption at campfires
4. **loot.lua** - Corpse looting with quality filters
5. **vendor.lua** - Selling, repairing, training
6. **combat.lua** - Combat engagement
7. **pull.lua** - Pull mobs to safe positions
8. **acquire.lua** - Target acquisition

#### Profile System
| File | Description |
|------|-------------|
| `module.lua` | Grind orchestration. Initializes sensors, loads profiles. |
| `profile_manager.lua` | Loads/grinds profiles. Tracks current profile. |
| `autoloader.lua` | Auto-selects profile based on level/zone. |
| `profile_validator.lua` | Validates profile structure. |

#### Support
| File | Description |
|------|-------------|
| `target_filter.lua` | Filters targets: blacklists, level, distance ranges. |
| `stuck_detector.lua` | Detects navigation stuck states. |
| `durability_tracker.lua` | Monitors equipment durability. |
| `telemetry.lua` | Tracks kills, deaths, gold per hour. |
| `threat_map.lua` | Maps death locations to avoid loops. |

### Battleground Module (`modules/battleground/`)

Full PvP automation for AV, WSG, AB, EOTS.

#### Structure
```
battleground/
├── module.lua           # Main BG module
├── data/                # Maps, routes, GO IDs
│   ├── bg_catalog.lua   # BG/map definitions
│   ├── gate_positions.lua # Spawn gates
│   ├── objectives/      # AV/WSG/AB/EOTS objectives
│   └── routes/          # Precomputed navigation routes
├── states/              # State machines per BG
├── strategies/          # Strategy evaluation per BG
└── queue_manager.lua    # BG queue joining
```

### Quest Module (`modules/quest/`)

Quest tracking and automation via dual-path: Questie addon + database.

#### Files
| File | Description |
|------|-------------|
| `module.lua` | Module lifecycle. Subscribes to `QUEST_LOG_UPDATE`. |
| `tracker.lua` | Parses `core.quests.*` APIs. Stores on blackboard. |
| `engine.lua` | Route planning. `get_quest_givers()`, `get_quest_turnins()`, `can_turn_in()`. |
| `questie_adapter.lua` | Wraps `core.addons.questie.*`. Provides live quest state. |
| `query_client.lua` | HTTP client for SentinelQueryServer. Uses `core.http_get`. |
| `interactions.lua` | Gossip interaction: accept, complete, close. |

### Mail Module (`modules/mail/`)

Inbox automation.

| File | Description |
|------|-------------|
| `module.lua` | Processes mail: takes gold/items, deletes spam. |
| `settings.lua` | Config: `AUTO_TAKE_GOLD`, `AUTO_LOOT_ITEMS`, `SPAM_KEYWORDS`. |

### LFG Module (`modules/lfg/`)

Dungeon queue automation.

| File | Description |
|------|-------------|
| `module.lua` | Searches, applies, accepts invites. Role-based filtering. |
| `settings.lua` | Config: auto-accept, role preferences. |

## Runtime Layer (`runtime/`)

### App Orchestration (`app.lua`)
Creates `SentinelApp` with all modules wired together. Lifecycle:
- `initialize()` - Creates modules, registers sensors
- `on_pre_tick()` / `on_update()` - Runs all modules
- `on_render()` / `on_render_menu()` - Renders UI
- `get_module(name)` - Access by name

### Module Registry (`module_registry.lua`)
Simple lookup table: `register(name, module)`, `get(name)`.

### Sensors (`sensor_hub.lua` + `sensors/`)
Eight sensor types run each tick:
1. `system_sensor.lua` - Game time, map ID, instance
2. `player_sensor.lua` - Position, health, mana, casting
3. `death_sensor.lua` - Death/ghost detection
4. `proximity_sensor.lua` - Enemy/ally counts in 10yd/30yd
5. `battleground_sensor.lua` - BG detection
6. `transition_detector.lua` - State changes
7. `aura_sensor.lua` - Seal tracking
8. `generic_sensor.lua` - Generic updates

### Callback Bridge (`callback_bridge.lua`)
Maps Sylvannas callbacks to EventBus:
- `PLAYER_REGEN_DISABLED` → `game:entered_combat`
- `PLAYER_REGEN_ENABLED` → `game:exited_combat`
- `MAIL_SHOW` → `game:mail_show`
- `QUEST_LOG_UPDATE` → `game:quest_log_update`

## Integrations (`integrations/`)

| File | Description |
|------|-------------|
| `izi_bridge.lua` | Bridge to IZI SDK: damage prediction, time-to-die, spell prediction. |
| `nav_client/adapter.lua` | Wraps SentinelNavClient. Provides `move_to()`, `path_gen()`. |

## Shared (`shared/`)

| File | Description |
|------|-------------|
| `constants.lua` | Aggregates all constants: map_ids, blackboard_keys, queue_priorities. |
| `blackboard_keys.lua` | Central key definitions. |
| `queue_priorities.lua` | Priority levels: `LOW=1` to `INTERRUPT=7`. |
| `compat.lua` | Compatibility helpers. |
| `humanization.lua` - Random delays, natural movement patterns. |
| `aoe_helper.lua` | Ground-target optimal positioning via spell_prediction. |

## UI (`ui/`)

Tab-based settings window using `SENTINEL` theme.

| File | Description |
|------|-------------|
| `window.lua` | Creates tabs, syncs settings. |
| `lib/sentinel_ui.lua` | AstroUI-derived UI library. |
| `tabs/` | Combat, Grind, BG, Dashboard, Debug, Profile Editor tabs. |

## Library (`lib/`)

| File | Description |
|------|-------------|
| `JSON.lua` | JSON encode/decode. Used for profiles. |

## Data (`data/`)

| Directory | Contents |
|-----------|----------|
| `quests/` | Quest data packs: `human_1_10.json`. |
| `profiles/` | Grinding profiles (autoloaders). |

## Tests (`tests/`)

Test runner: `run_all.lua` → `test_util.lua`. Each test file has `run()` function.