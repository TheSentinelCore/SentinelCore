# SentinelCore Refactor Plan — Bare Minimum (UI + Combat Engine Only)

## Goal
Reduce SentinelCore to the bare minimum: **UI** + **Combat Engine** running against a target dummy. Remove everything else (grind, quest, battleground, lfg, mail, quest authoring IDE, quest compiler). Invest in an out-of-game test harness.

---

## Current Structure (sentinel/)

```
sentinel/
├── core/                 # KEEP — BT, blackboard, event_bus, geometry, error_boundary
├── integrations/         # KEEP — nav_client adapter
├── lib/                  # KEEP — JSON.lua
├── modules/
│   ├── combat/           # KEEP — rotation, spell_dispatcher, target_selector, action_library, class_profiles
│   ├── grind/            # DELETE ENTIRELY
│   └── quest/            # DELETE ENTIRELY (remake from scratch later)
├── runtime/              # KEEP — app, sensor_hub, callback_bridge, module_registry, sensors/
├── shared/               # KEEP — REVIEW: move ui/lib here or to core
├── ui/
│   ├── lib/              # MOVE → shared/ or core/
│   └── window.lua        # KEEP
├── tests/                # PURGE — most are grind/quest tests; keep only combat/core tests
├── docs/adr/             # KEEP — add new ADRs
├── main.lua              # KEEP — slim down entry point
└── CONTEXT.md            # UPDATED ✓
```

---

## Target Structure (sentinel/)

```
sentinel/
├── core/                          # Core engine (unchanged)
│   ├── bt/                        # Behavior tree composites
│   ├── blackboard.lua
│   ├── blackboard_schema.lua
│   ├── error_boundary.lua
│   ├── event_bus.lua
│   └── geometry.lua
│
├── integrations/
│   └── nav_client/                # NavigationAdapter wrapper
│
├── lib/
│   └── JSON.lua
│
├── shared/                        # Cross-cutting libraries (NEW HOME for ui/lib)
│   ├── aoe_helper.lua
│   ├── blackboard_keys.lua
│   ├── capability_registry.lua
│   ├── compat.lua
│   ├── constants.lua
│   ├── humanization.lua
│   ├── map_ids.lua
│   ├── queue_priorities.lua
│   ├── types.lua
│   └── ui/                        # ← MOVED from ui/lib
│       └── sentinel_ui.lua
│
├── modules/
│   └── combat/                    # Combat Engine (KEEP ALL)
│       ├── action_library.lua
│       ├── rotation_engine.lua
│       ├── spell_dispatcher.lua
│       ├── target_selector.lua
│       ├── spell_catalog.lua
│       └── profiles/
│           ├── base.lua
│           ├── mage_frost.lua
│           ├── paladin_ret.lua
│           └── ...
│
├── runtime/
│   ├── app.lua                    # Slimmed entry point
│   ├── callback_bridge.lua
│   ├── module_registry.lua
│   ├── sensor_hub.lua
│   └── sensors/
│       ├── player_sensor.lua
│       ├── target_sensor.lua
│       ├── unit_sensor.lua
│       └── spell_sensor.lua
│
├── ui/
│   ├── window.lua                 # SentinelWindow
│   ├── combat_panel.lua           # Combat module UI
│   └── settings_panel.lua         # Settings UI
│
├── tests/                         # REBUILD — out-of-game test harness
│   ├── harness/                   # Test framework (busted-based or custom)
│   │   ├── mocks/
│   │   │   ├── sylvannas_api.lua
│   │   │   ├── spell_queue.lua
│   │   │   └── object_manager.lua
│   │   ├── busted.lua             # or custom runner
│   │   └── test_helpers.lua
│   ├── unit/
│   │   ├── core/
│   │   │   ├── test_blackboard.lua
│   │   │   ├── test_event_bus.lua
│   │   │   └── test_geometry.lua
│   │   ├── combat/
│   │   │   ├── test_spell_dispatcher.lua
│   │   │   ├── test_rotation_engine.lua
│   │   │   ├── test_target_selector.lua
│   │   │   └── test_spell_catalog.lua
│   │   └── shared/
│   │       └── test_geometry.lua
│   └── integration/
│       └── test_combat_dummy.lua  # Full rotation vs dummy
│
├── docs/adr/                      # ADRs for architectural decisions
├── main.lua                       # Minimal entry: register combat module, start runtime
└── CONTEXT.md                     # Updated ✓
```

---

## Deletion List (DELETE ENTIRELY)

### Modules
- `sentinel/modules/grind/` — **entire directory**
- `sentinel/modules/quest/` — **entire directory**
- `sentinel/modules/battleground/` — already gone in current `sentinel/`
- `sentinel/modules/lfg/` — already gone
- `sentinel/modules/mail/` — already gone

### Runtime sensors (grind-specific)
- `sentinel/runtime/sensors/loot_sensor.lua` (if exists)
- `sentinel/runtime/sensors/vendor_sensor.lua` (if exists)
- `sentinel/runtime/sensors/corpse_sensor.lua` (if exists)

### Shared (grind-specific)
- `sentinel/shared/blackboard_keys.lua` — **REVIEW**: remove grind keys, keep combat/core keys
- `sentinel/shared/queue_priorities.lua` — **REVIEW**: keep if combat uses it

### Tests (PURGE)
- `sentinel/tests/test_grind_*.lua`
- `sentinel/tests/test_quest_*.lua`
- `sentinel/tests/test_vendor_*.lua`
- Keep only: `test_core_*.lua`, `test_combat_*.lua`, `test_events.lua`

### Root-level (if any grind/quest files)
- `sentinel/main.lua` — **REWRITE** to only bootstrap combat + UI

---

## Move/Restructure

| From | To | Reason |
|------|-----|--------|
| `sentinel/ui/lib/sentinel_ui.lua` | `sentinel/shared/ui/sentinel_ui.lua` | Shared UI primitives belong in shared |
| `sentinel/ui/lib/` (if other files) | `sentinel/shared/ui/` | Consolidate |

---

## New: Out-of-Game Test Harness

### Goal
Run unit/integration tests **outside the game** via `lua` or `busted` CLI, mocking Sylvannas APIs.

### Structure
```
tests/
├── harness/
│   ├── mocks/
│   │   ├── sylvannas_api.lua      # Mocks _G.core.*, _G.ObjectManager, etc.
│   │   ├── spell_queue.lua        # Mocks spell queue API
│   │   └── nav_client.lua         # Mocks SentinelNavClient
│   ├── busted.lua                 # Or minimal custom runner
│   └── test_helpers.lua           # Common assertions, factories
├── unit/
│   ├── core/
│   ├── combat/
│   └── shared/
└── integration/
    └── test_combat_dummy.lua      # Full rotation loop vs mocked target dummy
```

### Sylvannas API Surface to Mock
Reference: `Documentation - Project Sylvannas/dev/api/`
- `core.object_manager` — `GetPlayer()`, `GetTarget()`, `GetUnitsInRange()`
- `core.input` — `CastSpell()`, `CastSpellAt()`, `Interact()`
- `core.spell` — `GetSpellCooldown()`, `IsSpellKnown()`, `GetSpellCharges()`
- `core.unit` — `GetHealth()`, `GetMaxHealth()`, `GetPower()`, `GetPosition()`, `GetDistance()`
- `core.player` — `GetClass()`, `GetLevel()`, `IsMoving()`, `GetPosition()`
- `core.spell_queue` — `QueueSpell()`, `ClearQueue()`
- `_G.SentinelNavClient` — path, raycast, random points

### Test Runner
```bash
# Run from project root
lua tests/harness/busted.lua tests/unit/...
# or if using busted directly:
busted tests/unit/...
```

---

## Module Registry — New Minimal Config

```lua
-- runtime/module_registry.lua
local ModuleRegistry = {}

ModuleRegistry.modules = {
    combat = {
        enabled = true,
        priority = 10,
        dependencies = {"core", "shared"},
    },
    ui = {
        enabled = true,
        priority = 5,
        dependencies = {"core", "shared"},
    },
}
```

Main.lua boots registry → sensors → event bus → combat module tick → UI tick.

---

## Main.lua — Minimal Entry Point

```lua
-- main.lua
local ModuleRegistry = require("runtime.module_registry")
local SensorHub = require("runtime.sensor_hub")
local EventBus = require("core.event_bus")
local CombatModule = require("modules.combat.init")
local UI = require("ui.window")

-- 1. Initialize core systems
EventBus.init()
SensorHub.init()

-- 2. Register modules
ModuleRegistry.register_all()

-- 3. Main tick (called from Sylvannas OnUpdate)
_G.SentinelCore = {
    tick = function(delta)
        SensorHub.update(delta)
        ModuleRegistry.tick_all(delta)
        UI.tick(delta)
    end,
    run_tests = function() ... end,  -- delegates to test harness
}
```

---

## Combat Module — Target Dummy Mode

### RotationEngine Addition
```lua
-- modules/combat/rotation_engine.lua
function RotationEngine:set_target_dummy_mode(enabled)
    self.target_dummy_mode = enabled
end

function RotationEngine:select_target()
    if self.target_dummy_mode then
        return ObjectManager:GetTargetDummy() -- or nearest attackable unit
    end
    return TargetSelector.select()
end
```

### SpellDispatcher — Target Dummy
SpellDispatcher already uses `spell_queue` API. Target dummy just means target selection returns the dummy unit.

---

## ADRs to Write

1. **ADR-001**: Remove grind/quest/battleground modules — scope to UI + Combat only
2. **ADR-002**: Move `ui/lib` → `shared/ui` — shared UI primitives belong in shared
3. **ADR-003**: Out-of-game test harness with Sylvannas mocks — enable CI/CD
4. **ADR-004**: Module registry as explicit config table — declarative module loading
5. **ADR-005**: Combat rotation target dummy mode — first integration test target

---

## Execution Order (Waves)

### Wave 1: Delete & Move (no code changes, just file ops)
1. Delete `modules/grind/`, `modules/quest/`
2. Move `ui/lib/` → `shared/ui/`
3. Purge `tests/` — keep only `test_core_*.lua`, `test_combat_*.lua`, `test_events.lua`
4. Clean `shared/` — remove grind-specific keys from `blackboard_keys.lua`, keep combat/core

### Wave 2: Slim Runtime & Main
5. Rewrite `main.lua` — minimal bootstrap (combat + UI only)
6. Update `module_registry.lua` — only combat, ui modules
7. Prune `sensor_hub.lua` sensors — keep player, target, unit, spell

### Wave 3: Test Harness
8. Create `tests/harness/` with Sylvannas mocks
9. Write `tests/unit/core/test_blackboard.lua`, `test_event_bus.lua`, `test_geometry.lua`
10. Write `tests/unit/combat/test_spell_dispatcher.lua`, `test_rotation_engine.lua`, `test_target_selector.lua`
11. Write `tests/integration/test_combat_dummy.lua` — full rotation loop

### Wave 4: Verify & Document
12. Run test harness — all unit tests pass
13. Run in-game — combat module loads, UI opens, rotation fires on dummy
14. Write ADRs 001–005

---

## Out of Scope (Future)
- Quest module rewrite
- Grind module rewrite (if ever needed)
- Battleground/LFG/Mail modules
- Quest Authoring IDE
- Quest compiler
- NavServer integration tests (requires running NavServer)

---

## Acceptance Criteria

1. ✅ `sentinel/` contains only: `core/`, `integrations/`, `lib/`, `modules/combat/`, `runtime/`, `shared/`, `ui/`, `tests/`, `docs/adr/`, `main.lua`, `CONTEXT.md`
2. ✅ `modules/grind/` and `modules/quest/` deleted
3. ✅ `ui/lib/` moved to `shared/ui/`
4. ✅ `main.lua` boots only combat + UI modules
5. ✅ `tests/harness/` exists with Sylvannas mocks
6. ✅ `busted tests/unit/` passes (or `lua tests/harness/busted.lua tests/unit/`)
7. ✅ In-game: `/reload` → SentinelCore loads → Combat panel opens → Target dummy → rotation fires spells
8. ✅ ADRs 001–005 written to `docs/adr/`