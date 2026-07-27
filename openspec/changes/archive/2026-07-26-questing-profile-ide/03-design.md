# Design: Questing Profile IDE

## Technical Approach

The Questing Profile IDE adds 4 in-game panels and 5 shell extensions to the existing IDE shell. Lua panels render via Sylvannas widgets and communicate read-only with QueryServer (:3030) and write via the Editor crate (:3031). Phase 0 extends the Editor crate with Campaign CRUD endpoints reusing the existing `CommandHistory` pattern. All new QueryServer endpoints are SQL queries over `tbcmangos.sqlite`. Panel structure follows the existing Runner pattern: `panel_state.lua` → `panel.lua` → `ide_panels.lua` → `register_panel()`.

## Architecture Decisions

### Decision: Extend editor crate (not a new crate)

| Option | Tradeoff | Decision |
|--------|----------|----------|
| New `sentinel-campaign-editor` crate | Clean separation, separate port | **Rejected** — adds workspace complexity, two HTTP servers to manage |
| Extend `sentinel-editor` with `/editor/campaigns/*` routes | Shared port, shared history pattern | **Chosen** — 4 new Rust files, reuses `CommandHistory` |

### Decision: Campaign storage — single JSON per campaign

| Option | Tradeoff | Decision |
|--------|----------|----------|
| `.questing/campaigns/{slug}.json` | Simple, self-contained, atomic writes | **Chosen** — matches Campaign serde round-trip |
| `.sproject/` directory format | File-per-node, parallel writes | **Rejected** — over-engineered for v1 |
| SQLite | Queryable, concurrent-safe | **Rejected** — no DB dependency in editor crate |

### Decision: Node-type specific editors in Properties panel

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Generic form from Intent schema | Single renderer, non-obvious field meaning | **Rejected** — Kill node shows entity ref instead of "Creature: Wolf" |
| Per-type specialized form | N renderers, explicit UX | **Chosen** — each node type gets dedicated form with labels + validation |

### Decision: Lua panels handle async state via polling

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Blocking HTTP in render | Freezes Sylvannas render callback | **Rejected** — render path must never block |
| Async with on_tick → cache → render | Offline-testable, matches Runner pattern | **Chosen** — identical to Runner's refresh cycle |

## Data Flow

```
  IN-GAME (Lua)

  on_tick          render
  +---------+      +----------+
  | Refresh |      | Panel    |--- command --->
  | State   |      | Render   |
  +----+----+      +----------+
       |
  +----v----+      +--------------+     +--------------+
  |Query    | GET  | QueryServer   |     | Editor Crate  |
  |Client   |----->| (:3030)      |     | (:3031)       |
  |(cached) |      | tbcmangos.sqlite|   | Campaign CRUD |
  +---------+      +--------------+     +-----+--------+
                                               |
                                         +-----v--------+
                                         | .questing/    |
                                         | campaigns/    |
                                         +--------------+
```

**Write path**: Panel dispatch → command queue → on_tick → QueryClient:post() → Editor crate → CommandHistory.execute() → in-memory + persist to `.questing/campaigns/{slug}.json`

**Read path**: Panel on_tick → QueryClient GET → cache 5s → Panel render reads cache

## File Changes

### Phase 0 — Editor Crate (Rust)

| File | Action | Description |
|------|--------|-------------|
| `SentinelQuesting/editor/src/campaign_store.rs` | Create | Campaign session store + filesystem CRUD (parallel to EditorApi) |
| `SentinelQuesting/editor/src/campaign_history.rs` | Create | CampaignCommand trait + node/edge/graph/condition commands |
| `SentinelQuesting/editor/src/campaign_handlers.rs` | Create | Axum handlers for all `/editor/campaigns/*` endpoints |
| `SentinelQuesting/editor/src/server.rs` | Modify | Add campaign routes, `campaign_store` to AppState |
| `SentinelQuesting/editor/src/lib.rs` | Modify | Export new modules |

### Phase 1 — Explorer Panel (Lua)

| File | Action | Description |
|------|--------|-------------|
| `sentinel/ui/panels/explorer_state.lua` | Create | Quest browser view-model: search, filters, selection, chain data |
| `sentinel/ui/panels/explorer.lua` | Create | Render layer — search + quest list + detail pane + Add buttons |
| `sentinel/ui/ide_panels.lua` | Modify | Register explorer panel |

### Phase 2 — Properties Panel (Lua)

| File | Action | Description |
|------|--------|-------------|
| `sentinel/ui/panels/properties_state.lua` | Create | Context-sensitive properties view-model |
| `sentinel/ui/panels/properties.lua` | Create | NPC inspector, vendor editor, condition tree, inventory rules |

### Phase 3 — Graph Panel (Lua)

| File | Action | Description |
|------|--------|-------------|
| `sentinel/ui/panels/graph_state.lua` | Create | Campaign graph view-model |
| `sentinel/ui/panels/graph.lua` | Create | Node list + property forms + add/delete controls |
| `sentinel/ui/panels/escort_recorder.lua` | Create | F15: NPC position polling, timeline generation |

### Phase 4 — Database Panel (Lua)

| File | Action | Description |
|------|--------|-------------|
| `sentinel/ui/panels/database_state.lua` | Create | Spawn scanner + grinding zone view-model |
| `sentinel/ui/panels/database.lua` | Create | Nearby results, spawn list, zone density, actions |

### Phase 5 — Shell / QServer (Lua + Rust)

| File | Action | Description |
|------|--------|-------------|
| `sentinel/ui/panels/spawn_overlay.lua` | Create | F4: Spawn overlay (list fallback) |
| `sentinel/ui/shell.lua` | Modify | F19: validate-on-save hook. F20: stats badge |
| `SentinelQueryServer/src/handlers/quest_chain.rs` | Create | GET /quest/{id}/chain |
| `SentinelQueryServer/src/handlers/quest_objectives.rs` | Create | GET /quest/{id}/objectives |
| `SentinelQueryServer/src/handlers/zone_spawns.rs` | Create | GET /zone/{id}/spawns |
| `SentinelQueryServer/src/handlers/spawn_density.rs` | Create | GET /spawns/density/{zone} |
| `SentinelQueryServer/src/handlers/travel_route.rs` | Create | POST /travel/route |

## Interfaces / Contracts

### Campaign Session (Rust)

```rust
pub struct CampaignSession {
    pub campaign: Campaign,
    pub history: CampaignHistory<Campaign>,
}

pub struct AppState {
    pub projects_dir: PathBuf,
    pub project_store: Arc<RwLock<HashMap<String, ProjectSession>>>,
    pub campaign_store: Arc<RwLock<HashMap<String, CampaignSession>>>,  // NEW
}
```

### CampaignCommand trait

```rust
pub trait CampaignCommand: Send + Sync {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String>;
    fn inverse(&self) -> Box<dyn CampaignCommand>;
    fn description(&self) -> String;
}
```

### Lua Panel State Interface

```lua
-- Every panel exports: create() -> state, build(state, bounds) -> plan, reduce(model, action_id) -> command|nil

-- QueryClient extensions:
--   get_quest_chain(id) -> { prerequisites, follow_ups, chain_depth, branches }
--   get_quest_objectives(id) -> { objectives, objective_text }
--   get_zone_spawns(zone_id) -> { creatures, objects }
--   get_spawn_density(zone) -> { density_regions, safe_spots }
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit (Rust) | Campaign commands, undo/redo cycle | In-crate tests following history.rs pattern |
| Unit (Lua) | Panel build() + reduce() for each panel | Offline via luajit run_offline.lua |
| Integration (Lua) | QueryClient extensions vs mocks | Offline test with mock core.http_get |
| Integration (Rust) | Campaign CRUD handler round-trips | axum::test against in-memory store |
| E2E | Full cycle: quest search → add → validate → compile | Manual in-game |

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary. Panels communicate with editor crate and QueryServer over pre-existing HTTP APIs; no shell commands or subprocesses are constructed.

## Migration / Rollout

No migration required. Old Project model and `/editor/projects/*` endpoints remain untouched. Phase 0 is additive. Each later phase is additive to the Lua UI — revert independently. Existing profiles on disk unaffected.

## Open Questions

- [ ] **F4 Spawn Overlay feasibility**: Does Sylvannas expose a render callback for world-space drawing? Fallback (list-with-distance) is the safe default.
- [ ] **F15 Escort Recorder**: Does existing player position API extend to NPC tracking, or does escort recording need a new publisher?
- [ ] **CampaignHistory trait reuse**: Should `CommandHistory` become generic `<T: Command>` in shared crate, or duplicate for Campaign? Recommend generic to avoid duplication.
