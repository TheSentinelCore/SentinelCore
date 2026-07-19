# SentinelCore — Full Completion Plan

## Status Assessment (July 18 2026)

### What Exists and Works

| Component | Status | Notes |
|-----------|--------|-------|
| **Core Engine** (BT, blackboard, event_bus, geometry) | ✅ Complete | Fully tested, production quality |
| **Runtime** (app, sensors, callback_bridge, module_registry) | ✅ Complete | Boots cleanly, dispatches ticks |
| **Combat Framework** | ✅ Complete | Phase B refactor done: condition_library, action_library, shared_subtrees, priority_builder, spell_dispatcher, spell_catalog, target_selector v1+v2, aura_catalog, cooldown_tracker, swing_tracker, chase_controller, combat_zone_detector |
| **Combat Profiles** | ✅ Complete | Mage Frost (8 files), Paladin Retribution (4 files), profile registry |
| **Shared Libraries** | ✅ Complete | aoee_helper, blackboard_keys, compat, constants, humanization, map_ids, queue_priorities, types, UI primitives |
| **Integrations** | ✅ Complete | NavClient adapter, IZI bridge |
| **UI** | ⚠️ Partial | combat_panel, settings_panel, window — basic combat UI only |
| **Schema Crate** (sentinel-schema) | ✅ Complete | All Volume 5 + 7 types, tests pass, compiles clean |
| **QueryServer Crate** | ✅ ~85% Complete | All 17 service modules implemented with real SQL. Routes defined. Compiles clean. Some services may need polish. |
| **Tests** | ⚠️ Partial | ~30 test files across core/combat/runtime/shared. No integration tests. Harness exists. |
| **ADRs** | ✅ Complete | 8 volumes, excellent documentation |
| **Grind/Quest/BG/LFG/Mail modules** | ❌ Deleted | Per REFACTOR_PLAN (out of scope for current phase) |

### What Does NOT Exist

| Component | ADR Reference | Est. Effort |
|-----------|--------------|-------------|
| **Compiler Crate** (sentinel-compiler) | Volume 8 | HIGH —7-stage pipeline, graph algorithms, incremental compilation |
| **Runtime Execution Engine** (Lua) | Volume 2 | HIGH — Profile Manager, Operation Manager, Action Executor, Variable Store, Query Client |
| **In-Game IDE** (Lua) | Volume 3 | VERY HIGH — Explorer, World Map, Inspector, Timeline, Capture panels, Undo/Redo, Search |
| **Profile ↔ Runtime Bridge** | Volume 1/2/8 | MEDIUM — Lua HTTP client for QueryServer, profile JSON I/O, compilation trigger |
| **Lua ↔ Rust Integration** | Implicit | MEDIUM — How compiled profiles reach the Lua runtime |
| **Sylvannas API Integration Layer** | Volume 9 (referenced) | MEDIUM — Overlay rendering, input capture, event binding |
| **Integration Tests** | Implicit | LOW — Full rotation loop, QueryServer end-to-end |
| **Out-of-game Test Harness** | REFACTOR_PLAN | LOW — Mock Sylvannas APIs, run tests via lua CLI |

---

## Phase Map — Ordered by Dependency

### Wave 1: Foundation & Validation (No new features, just solidify what exists)

**1.1 — Verify QueryServer Compiles and Runs**
- `cargo build` the workspace
- Start QueryServer with `tbcmangos.sqlite`
- Hit `/health` and `/api/v1/quests/search?query=wolves` to confirm it serves
- Fix any runtime issues (hardcoded DB path in `lib.rs` → configurable)
- Write integration test: start server, query quest, assert shape

**1.2 — Verify Schema Crate Serialization Round-Trip**
- Add `serde_json::to_string` / `from_str` tests for Profile, Operation, Action
- Ensure a sample profile JSON can round-trip through the schema types
- Write a sample profile JSON file (`profiles/northshire_example.json`) that exercises all action types

**1.3 — Clean Up Lua Test Suite**
- Delete grind/quest tests that reference deleted modules
- Verify all remaining tests pass via `_G.SentinelCore.run_tests()`
- Fill empty `tests/integration/` with at least one combat-vs-dummy test
- Create out-of-game test runner entry point (`tests/run_offline.lua`)

**1.4 — Hardcode Nothing, Configure Everything**
- QueryServer DB path → CLI arg or env var
- QueryServer bind address → CLI arg or env var
- Add `--help` to QueryServer binary
- Add `Cargo.toml` `[[bin]]` entry for the QueryServer

---

### Wave 2: The Compiler (sentinel-compiler crate — Rust)

**2.1 — Create sentinel-compiler Crate**
- Add `crates/sentinel-compiler` to workspace
- Dependencies: `sentinel-schema`, `serde`, `serde_json`, `uuid`, `anyhow`, `thiserror`
- Define crate structure:
  ```
  sentinel-compiler/
  └── src/
      ├── lib.rs            # Public API: compile(Profile, &QueryClient) -> Result<RuntimeProfile>
      ├── stages/
      │   ├── mod.rs
      │   ├── structural.rs      # Stage 1: duplicate IDs, dangling refs, malformed polygons
      │   ├── resolution.rs      # Stage 2: resolve NpcReference/QuestReference via QueryServer
      │   ├── expansion.rs       # Stage 3: Blueprint → primitive Actions
      │   ├── dependency.rs      # Stage 4: Operation dependency graph, topo sort, cycle detect
      │   ├── goal_coverage.rs   # Stage 5: verify actions satisfy declared goals
      │   ├── optimization.rs    # Stage 6: cross-operation merge, route optimization
      │   └── lowering.rs        # Stage 7: emit RuntimeProfile
      ├── runtime_profile.rs     # RuntimeProfile, RuntimeOperation, RuntimeAction, ResolvedActionPayload
      ├── diagnostics.rs         # Diagnostic { severity, code, stage, message, entity, suggested_fix }
      ├── graph.rs               # DependencyGraph: nodes, edges, topo_sort, detect_cycles
      ├── dirty.rs               # DirtyTracker: per-Operation dirty state
      ├── cache.rs               # ResolutionCache, ExpansionCache, CompileCache
      ├── query_client.rs        # HTTP client trait for QueryServer (trait + reqwest impl)
      └── migration.rs           # Schema version migration registry
  ```

**2.2 — Stage 1: Structural Validation**
- Duplicate Action/Operation/NPC/Quest IDs
- Dangling UUID references (Action→Variable, Blueprint→NPC)
- TurnIn with no matching Pickup
- Malformed polygons (<3 vertices, self-intersecting)
- Schema version mismatch
- Error codes: `C-1xxx`

**2.3 — Stage 2: Reference Resolution**
- Resolve every NpcReference, QuestReference, CreatureReference, GameObjectReference against QueryServer
- Embed fully-resolved data (position, roles, faction) into intermediate representation
- Cache by (entry_id, db_version)
- Error codes: `C-2xxx`

**2.4 — Stage 3: Blueprint Expansion**
- Iterate Operation actions; for each Blueprint reference:
  - Resolve parameters (NPC, Quest, Waypoint, etc.)
  - Inject smart defaults from QueryServer (nearest vendor, nearest trainer)
  - Recurse (Blueprints may contain Blueprints)
  - Remove actions for unset optional parameters
  - Tag `generated_from: blueprint_id`
- After expansion: only primitive ActionPayload variants remain
- Error codes: `C-3xxx`

**2.5 — Stage 4: Operation Dependency Resolution**
- Build directed graph: node per Operation, edge per Requires/UnlocksAfter
- Detect cycles → hard error
- Detect ExcludesWith conflicts → hard error (unless entry_conditions make them exclusive)
- Topological sort on Requires/UnlocksAfter
- Tie-break: SoftPrefers → priority → declaration order
- Error codes: `C-4xxx`

**2.6 — Stage 5: Goal Coverage Validation**
- For each required OperationGoal:
  - CompleteQuest(id): must have PickupQuest + TurnInQuest in action list (or sub_operations)
  - CompleteQuestChain(ids): all quest IDs covered
  - ReachLevel(n): informational, passes through
  - UnlockFlightPath(id): must have FlightAction or TalkToNpc resolving to flight master
  - GainXp(n): informational
  - ReachZone/ReachWaypoint: check for matching GoTo action
- Optional goals without actions → warning
- Error codes: `C-5xxx`

**2.7 — Stage 6: Cross-Operation Optimization**
- Walk adjacent Operations in compile order
- Merge trailing Vendor + leading GoTo (if positions within merge distance)
- Collapse adjacent Vendor + Repair into one interaction
- Drop redundant GoTo actions
- Reorder within Operation when `allow_reordering: true` (minimize travel via QueryServer route analysis)
- Optimization never breaks goal coverage (re-validate Stage 5 after each rewrite)
- Error codes: `C-6xxx`

**2.8 — Stage 7: Lowering**
- Convert optimized authoring structures → `RuntimeProfile`
- `RuntimeProfile { schema_version, compiled_at, compiler_version, source_profile_id, source_profile_hash, operations: Vec<RuntimeOperation> }`
- `RuntimeOperation { id, name, entry_conditions, exit_conditions, goals, actions: Vec<RuntimeAction> }`
- `RuntimeAction { id, payload: ResolvedActionPayload, retry_policy, timeout_ms, generated_from }`
- `ResolvedActionPayload` = same enum as `ActionPayload` but all references fully resolved
- Error codes: `C-7xxx`

**2.9 — Incremental Compilation**
- DirtyTracker per Operation (Volume 2 §13)
- Edit one Operation → only that Operation re-runs Stages 1–3
- Stage 4 re-runs only if edit touched dependencies/priority/entry_conditions
- Stage 5 re-runs only for that Operation's goals
- Stage 6 re-runs only for that Operation + immediate neighbors
- Stage 7 re-lowers affected RuntimeOperation entries

**2.10 — Caching**
- ResolutionCache: keyed on (entry_id, db_version) — Stage 2
- ExpansionCache: keyed on (blueprint_id, parameter_hash) — Stage 3
- CompileCache: keyed on source_profile_hash — whole pipeline
- If hash + db_version unchanged → skip entire pipeline

**2.11 — Compiler Diagnostics**
- Structured diagnostic type with stage, error code, message, entity reference, suggested fix
- Error codes namespaced by stage (C-1xxx through C-7xxx)
- Compiler returns `Result<RuntimeProfile, Vec<Diagnostic>>` — never partially emits
- Test suite: compile Northshire example profile → verify output

---

### Wave 3: Runtime Execution Engine (Lua)

**3.1 — Query Client (Lua)**
- HTTP client using `core.http_get` (Sylvannas API) for GET endpoints
- POST support if Sylvannas exposes it (or fall back to file-based profiles)
- Response parsing via `JSON.lua` (already in `lib/`)
- Cache responses locally (avoid redundant network calls)

**3.2 — Profile Manager**
- `load(path)` — Load authoring profile from JSON file
- `save(path)` — Save authoring profile to JSON file
- `compile()` — Send profile to Rust compiler (or run local compiler if compiled to WASM)
- `validate()` — Run structural validation locally
- `activate(profile_id)` — Set as active profile
- `deactivate()` — Stop execution
- Dirty tracking: mark profile dirty on any edit

**3.3 — Runtime Profile Loader**
- Deserialize compiled `RuntimeProfile` JSON
- Store as immutable reference
- Support hot-reload: on file change → recompile → swap profile → continue execution

**3.4 — Operation Scheduler**
- Read `RuntimeProfile.operations`
- Filter by `entry_conditions` (check current character state)
- Skip already-completed/skipped Operations
- Select next Operation by: status=Ready, then priority
- Track current Operation + current Action index

**3.5 — Action Executor**
- Receive `RuntimeAction`
- Switch on `ResolvedActionPayload` variant:
  - `PickupQuest` → interact NPC, select quest, accept
  - `TurnInQuest` → interact NPC, complete quest, select reward
  - `GoTo` → use NavigationAdapter to path to destination
  - `GrindArea` → delegate to combat module with polygon + targets
  - `KillTarget` → target creature, engage combat
  - `Vendor` → interact vendor NPC, sell items, buy configured items
  - `Repair` → interact repair NPC
  - `Train` → interact trainer NPC
  - `FlightPath` → interact flight master, select destination
  - `Hearth` → use hearthstone item
  - `Mailbox` → interact mailbox NPC
  - `Bank` → interact banker NPC
  - `UseItem` → use item from inventory
  - `Wait` → sleep for duration
  - `SetVariable` → update Variable Store
  - `Branch` → evaluate condition, route to true/false actions
  - `DungeonMarker` → flag for dungeon entry detection
  - `DeathSkip` → die, take spirit healer, resume
- Each action returns: Running → Succeeded / Failed
- RetryPolicy governs retry behavior on failure

**3.6 — Variable Store**
- Typed key-value store (Bool, Integer, Float, String, Position)
- Scoped: global (profile-level), operation-level
- Readable by conditions, writable by SetVariable actions
- Persists across Operations within a profile run

**3.7 — Runtime Event Dispatcher**
- Map Sylvannas game events to runtime events:
  - `QUEST_LOG_UPDATE` → QuestAccepted, QuestCompleted, QuestFailed
  - `UNIT_HEALTH` → HealthChanged
  - `BAG_UPDATE` → InventoryChanged
  - `PLAYER_ENTERING_WORLD` → ZoneEntered
  - Combat events → KillEvent, DeathEvent
- Runtime subscribes to these to evaluate exit conditions and update state

**3.8 — Runtime State Machine**
- Per-Operation: `Locked → Ready → Active → Completed / Failed / Aborted / Skipped`
- Per-Profile: `Idle → Ready → Executing → Waiting → Finished → Idle`
- Error recovery: `Recovering → Retry → Executing` or `Failed`

**3.9 — Dry Run Mode**
- Same scheduler, same executor
- Replace real actions with Simulation Adapters:
  - Movement → simulated (check if path exists via QueryServer)
  - Combat → simulated (check if targets exist in polygon)
  - Interaction → simulated (check if NPC exists, quest available)
- Output: step-by-step trace with ✓/⚠/❌

**3.10 — Telemetry**
- Record per-Action: duration, success/failure, retries
- Record per-Operation: total duration, XP gained, gold spent, deaths
- Record per-Profile: total duration, completion rate
- Store in profile-local analytics file
- Feed back to editor: bottleneck detection, success rate trends

---

### Wave 4: In-Game IDE (Lua + Sylvannas UI)

**4.1 — UI Framework Foundation**
- `SentinelWindow` already exists — extend with panel registration system
- Panel system: named panels with visibility toggle, drag/drop docking, layout persistence
- Keyboard shortcut system (Ctrl+S, Ctrl+Z, Ctrl+P, etc.)

**4.2 — Toolbar**
- File: Save, Compile, Validate
- Edit: Undo, Redo
- Tools: Dry Run, Start, Stop
- Capture: NPC, Path, Area
- View: toggle panels
- Settings: compiler settings, runtime settings

**4.3 — Explorer Panel (Project Tree)**
- Hierarchical view: Profile → Operations → Actions
- Expand/collapse
- Drag/drop reorder Operations
- Right-click context menu (rename, delete, duplicate, enable/disable)
- Color coding by status (enabled=normal, disabled=grey, error=red)

**4.4 — Target Capture Panel**
- Read current target via `core.object_manager.GetTarget()`
- Display: name, entry ID, GUID, faction, position
- Role assignment buttons: QuestGiver, Vendor, Trainer, Innkeeper, FlightMaster, Repair, Mailbox, Bank
- QueryServer enrichment (verify NPC exists in database)
- Add to NPC Library

**4.5 — NPC Library Panel**
- Searchable list of captured NPCs
- Select NPC → highlight on map
- Edit roles, position
- Delete NPC (with dependency check)

**4.6 — Quest Browser Panel**
- Search quests via QueryServer (`/api/v1/quests/search`)
- Display: title, level, zone, giver
- Select quest → show objectives, rewards, chain, prerequisites
- Buttons: Add Pickup, Add TurnIn, Preview Chain

**4.7 — World Map Panel**
- Render minimap overlay or in-game map overlay
- Pins for: NPCs (colored by role), Operations, Waypoints
- Polygon rendering for GrindArea actions
- Route rendering for RecordPath actions
- Click to select, right-click context menu
- Drag to create waypoints
- Zoom, pan

**4.8 — Timeline Panel (Action Sequence)**
- Horizontal or vertical list of Actions for selected Operation
- Each action: icon, name, status indicator
- Drag/drop reorder
- Click to select → Inspector updates
- Blueprint nodes: collapsible, show summary
- Color coding by action type

**4.9 — Inspector Panel (Property Editor)**
- Display properties of selected Action
- Common: name, enabled, notes, conditions, retry_policy, timeout
- Type-specific fields (e.g., GrindArea shows polygon, targets, stop_condition)
- Live update on edit
- Condition editor (add/remove conditions)

**4.10 — Action Palette**
- Categorized list of all action types (Movement, Combat, Quest, NPC, Utility)
- Drag onto Timeline to add action
- Blueprint library: pre-built templates

**4.11 — Variables Panel**
- List all profile-level and operation-level variables
- Create, edit, delete variables
- Type selector (Bool, Integer, Float, String, Position)
- Watch variables during execution (display current value)

**4.12 — Validation Panel**
- List all validation errors and warnings
- Click to select offending object
- Color coded: ERROR=red, WARNING=yellow, INFO=blue, SUCCESS=green

**4.13 — Console Panel**
- Tabs: Editor, Compiler, Runtime
- Log messages with timestamps
- Compiler output: stages, duration, diagnostics
- Runtime output: action execution trace

**4.14 — Dry Run Controls**
- Play, Pause, Step, Reset
- Display current action being simulated
- Show step results (✓/⚠/❌)

**4.15 — Path Recorder**
- Start/Stop recording
- Display: distance, points, time
- On stop: simplify path, smooth, save as RecordPath action

**4.16 — Polygon Recorder**
- Start/Stop recording
- Display: vertices, area, NPC density
- On stop: query QueryServer for creatures in area, suggest targets, create GrindArea action

**4.17 — Undo/Redo System**
- Command pattern (Volume 2 §14)
- Commands: AddAction, RemoveAction, MoveAction, EditAction, CaptureNPC, SetVariable
- Unlimited history until save
- Ctrl+Z / Ctrl+Y

**4.18 — Search Everywhere (Ctrl+P)**
- Unified search across: NPCs, Quests, Operations, Actions, Variables, Items
- Results show type + context
- Select → navigate to entity

**4.19 — Multi-Select**
- Ctrl+Click to select multiple actions
- Inspector shows bulk-editable properties
- Bulk: enable/disable, delete, tag, set retry

---

### Wave 5: Profile Format Integration

**5.1 — JSON Profile Schema**
- Serialize sentinel-schema `Profile` type to JSON
- Define file format: `.sentinel-profile.json`
- Version field for migration support
- Include: metadata (created_at, updated_at, compiler_version)

**5.2 — Profile I/O in Lua**
- Load: read JSON file → deserialize into Lua table matching schema
- Save: serialize Lua table → JSON → write file
- Store profiles in Sylvannas scripts_data directory

**5.3 — Compile Trigger**
- Editor "Compile" button → serialize Profile → send to Rust compiler (or run WASM compiler)
- Compiler returns RuntimeProfile JSON
- Lua runtime deserializes RuntimeProfile
- Swap into active execution

**5.4 — Profile Migration**
- Volume 8 §14: Migration Registry
- Ordered list of (from_version, to_version, migration_fn)
- Run before Stage 1 of compilation
- M-xxxx error codes for migration failures

---

### Wave 6: Testing & Polish

**6.1 — Rust Test Suite**
- Schema: round-trip serialization tests for every type
- Compiler: unit tests for each stage
  - Stage 1: sample profiles with deliberate errors → verify diagnostics
  - Stage 2: mock QueryClient → verify resolution
  - Stage 3: sample Blueprint expansion → verify output
  - Stage 4: dependency graph with cycles → verify detection
  - Stage 5: goal coverage with missing actions → verify warnings/errors
  - Stage 6: adjacent Operations → verify merge
  - Stage 7: full Profile → RuntimeProfile → verify structure
- QueryServer: integration tests per endpoint (requires SQLite)

**6.2 — Lua Test Suite**
- Runtime execution engine tests (mock Sylvannas APIs)
- Action executor tests per action type
- Variable store tests
- Operation scheduler tests
- Profile manager tests
- Integration: load Northshire profile → compile → execute → verify action sequence

**6.3 — Out-of-Game Test Harness**
- Mock Sylvannas APIs (core.object_manager, core.input, core.spell, etc.)
- Run tests via `lua tests/run_offline.lua` or `busted tests/unit/`
- CI-friendly

**6.4 — Error Handling & Edge Cases**
- Empty profile → compile → return empty RuntimeProfile
- Profile with 0 Operations → valid, nothing to execute
- NPC not in database → compile error with clear diagnostic
- Circular dependency → compile error with cycle path
- Action timeout → retry per RetryPolicy, then abort/fail
- Network failure → QueryServer unreachable → use cached data or fail gracefully
- Hot-reload during active execution → atomic swap, no partial state

**6.5 — Documentation**
- Update CONTEXT.md with new terms (RuntimeProfile, CompiledAction, etc.)
- Update ADRs with implementation notes
- Write developer guide for adding new action types
- Write developer guide for adding new Blueprint types

---

## Dependency Graph

```
Wave 1 (Foundation)
  │
  ├──► Wave 2 (Compiler — Rust)
  │         │
  │         ├──► Wave 5.3 (Compile Trigger — needs compiler binary)
  │         │
  │         └──► Wave 3 (Runtime Engine — needs compiled profiles)
  │                   │
  │                   └──► Wave 4 (IDE — needs runtime for dry run)
  │
  └──► Wave 5.1-5.2 (Profile Format — can start in parallel with Wave 2)
              │
              └──► Wave 5.3 (Compile Trigger — needs format + compiler)

Wave 6 (Testing & Polish) runs in parallel with Waves 2-5
```

## Estimated Effort

| Wave | Effort | Parallelizable |
|------|--------|----------------|
| Wave 1: Foundation | 1–2 days | No |
| Wave 2: Compiler | 5–8 days | Partially (stages are sequential) |
| Wave 3: Runtime Engine | 5–7 days | Partially (components are independent) |
| Wave 4: IDE | 10–15 days | Yes (panels are independent) |
| Wave 5: Integration | 2–3 days | No (depends on Waves 2+3) |
| Wave 6: Testing | 3–5 days | Yes (tests parallel to implementation) |
| **Total** | **26–40 days** | |

## Priority Ordering

If time is limited, here is the minimum viable path to a usable product:

1. **Wave 1** — Solidify foundation (must do)
2. **Wave 2 + Wave 3** — Compiler + Runtime Engine (core value)
3. **Wave 5** — Profile format integration (glue)
4. **Wave 6.1-6.2** — Critical tests only
5. **Wave 4** — IDE panels incrementally (start with Explorer + Inspector + Timeline + Capture)

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sylvannas API doesn't support HTTP POST | Blocks QueryServer POST endpoints | File-based fallback for write operations |
| Sylvannas UI API limitations | IDE panels may not render as designed | Graceful degradation; ASCII fallback |
| Compiler complexity exceeds estimates | Wave 2 timeline slips | Ship Stage 1+7 first (validate + lower), add intermediate stages later |
| Profile JSON too large for in-game editing | Performance issues | Lazy loading, pagination, profile splitting |
| QueryServer latency in-game | Sluggish IDE | Aggressive caching, pre-fetch on profile load |
| Rust WASM compilation for in-game use | May not be feasible on Sylvannas | Alternative: separate QueryServer process (already planned) |
