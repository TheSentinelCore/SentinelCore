# Design: Questing IDE Remediation — Fix + Finish to Spec

**Change**: questing-ide-remediation | **Phase**: 3 — Design | **Date**: 2026-07-26

## Technical Approach

Foundations first (client wiring, async re-arm, selection bus), then Rust contract extensions, then per-panel remediation, then verification hardening — exactly the proposal's order. One shared async-poll primitive and one shell-level selection bus replace the per-panel one-offs that caused last cycle's freeze. All panel rendering consumes server-shaped data only; fixtures mirror query-types via a shape test.

## SDK Feasibility (verified against `docs/SylvannasAPI/dev/api/`)

| Need | Verdict | API (cited) |
|------|---------|-------------|
| Text input | **Build it** (no chip fallback) | `core.input.is_key_pressed(vk)` + `core.input.is_key_down(16)` shift (input.md §Keyboard); focus via `window:is_rect_clicked` (ui-custom.md:387). Proven in-repo by `SentinelNavClient/lib/AstroUI.lua:2400-2454` — VK 27/13/8/46/37/39/36/35 + VK_CHAR_MAP loop. `window:block_input_capture()` is undocumented but used by that working code; fallback: focus-gated capture only. Offline: same handler path fed injected `{vk}` events. |
| Spawn scan | **Feasible** | `core.object_manager.get_all_objects()` (object-manager.md:40) + per-object `is_unit()`, `get_npc_id()` (entry), `get_name()`, `get_level()`, `get_creature_type()`, `get_position()` (game-object.md); distance via `core/geometry.lua::Geometry.distance`. `get_visible_objects()` is NOT implemented — forbidden. Replaces phantom `dbg.nearby`. |

## Architecture Decisions

### Decision: Single async-poll primitive (`sentinel/ui/async_slot.lua`)

**Choice**: `AsyncSlot.new({label, max_ticks=120})`; `slot:poll(fn)` where `fn` returns `data` | `(nil, true)` pending | `(nil, nil)` failed. While pending it re-arms the owner's `_dirty`; on data it stores + clears; on failure/exhaustion it sets `state.error = "<label> failed"` and clears. Panels hold named slots (`state._slots.detail/scan/grind/search`); all four data bindings route every fetch through it.
**Alternatives**: per-panel re-arm (rejected — the bug was three divergent hand-rolled versions); callback state machine inside QueryClient (rejected — QueryClient stays request-and-cache; polling is the consumer's concern).
**Harness mirror**: mock gains `core.http_get(url, cb)` holding the callback for `mock.pending_ticks` (default 2) harness ticks, then invoking it — the exact runtime shape. One re-arm test per data panel.

### Decision: Selection bus lives on the shell

**Choice**: `shell:publish_selection({panel_id, kind, id})` + `shell:on_selection(fn)` — panel-agnostic (ADR 09b: shell never names panels). `install()` subscribes once: Properties `set_context({selection_type=kind, selection_id=id})`, and when origin ≠ properties, `shell_state:activate(properties_id)` (focus-follow). Explorer `select_quest`, Graph `select_node`, Database `select_entry`/"Open in NPC Inspector" publish from their dispatch wrappers.
**Alternatives**: fan-out inside ide_panels only (rejected — Database→Properties tab focus requires shell tab activation anyway).

### Decision: query_client contract = table

**Choice**: `main.lua` constructs one `QueryClient:new()` + one `EditorClient` and passes both in `deps`; doc comments at ide_panels.lua:312/426/647 change `function():table|nil` → `table|nil`; call sites unchanged (already method-call). Nil client → panel renders "query server unavailable", no fetch attempted.

### Decision: Rust extensions (panels win) + zone fork

**Serde shapes** (all new fields `#[serde(default)]` — wire-compatible):
`QuestSummary.zone: String`; `NpcDetail += level: u8, classification: String, loot: Vec<LootEntry{item:u32,name:String,drop_chance:f32}>, quests: Vec<NpcQuestRef{quest_id:u32,title:String,role:String}>`; `VendorInfo.sells: Vec<VendorItem{item_entry:u32,name:String,price:u32}>` (replaces `Vec<u32>`).

**db.rs queries**: `get_npc` += `MinLevel/MaxLevel/Rank` (creature_template), loot via `creature_loot_template ⋈ item_template` (`ChanceOrQuestChance`), quests via `creature_questrelation` (starter) + `creature_involvedrelation` (finisher) `⋈ quest_template` — the table names in THIS snapshot (FINGERPRINTED_TABLES, db.rs:1179). `get_vendor`: `npc_vendor ⋈ item_template` (name, `BuyPrice`; `ExtendedCost≠0` → price 0). `search_quests`: `ZoneOrSort` → new static TBC area map `zone_names.rs` (only >0; <0 → `""`).

**ZONE FORK (RESOLVED 2026-07-26, user decision)**: spec prescribes `/zone/{id}/spawns` "SQL JOIN … grouped by zone"; `creature` has no zoneId and `creature_zone` is empty (0 rows, verified) — but zone data IS derivable from the in-repo extracted client data at `Emulators/Mangos - Classic TBC/extracted/`: `maps/*.map` tiles (3,586 tiles, MAPS s1.4 headers, verified) carry the area-ID grids the mangos core uses for `Map::GetZoneId`, `dbc/AreaTable.dbc` carries zone names/hierarchy, and the mangos server source in-tree is the format reference. Decision, three parts: (a) **F13 grind query = map + position + radius** — `creature` has map/position columns, 100% of 11,922 spawned entries reachable, simpler SQL; (b) **zone names catalog** — new `sentinel/tools/regen_zone_catalog.py` parses AreaTable.dbc → committed `sentinel/kernel/catalogs/zones.{json,lua}` (mirrors the regen_taxi_paths_catalog.py pattern: catalog committed because the DBC is not); (c) **spawn→zone index** — the ETL also parses map-tile area grids and computes zoneId for all 109,352 creature spawns, committed as a spawn-zone catalog → `/zone/{id}/spawns` **restored at 100% coverage** for zone browsing. **`/spawns/density/{zone}` is NOT built** (position+radius + sample positions suffice for F13 safe-spots; density re-deferred).

**Ripple**: Rust struct literals needing new fields — `compiler/tests/{kernel_combat_policy,kernel_worked_example}.rs`, `importer/src/project_builder.rs`, `importer/tests/{mapper,importer}.rs`, `queryclient/tests/queryclient.rs`, `queryclient/src/memory.rs` (QuestSummary build). `cargo test` both workspaces is the gate.

### Decision: Lua editor client = thin wrapper over QueryClient(:3031)

**Choice**: new `sentinel/shared/editor_client.lua` wrapping `QueryClient:new(host, 3031)`: `list_campaigns`, `create_campaign(name)`, `load_campaign(name)`, `save_graph(name, nodes, edges)`, `add_nodes(name, nodes)`, `update_node(name, id, fields)`, `validate(name)`, `compile(name)`. Mutations add `QueryClient:invalidate(prefix)` (path-keyed cache must not serve stale graphs post-write). Graph binding: `load_campaign` → `graph_state:set_campaign(name)` + load first graph's nodes/edges (ids tostring-safe — server UUIDs); empty state gains `action_label = "New Campaign"`. Save triggers auto-validate → validation bar (F19-R1).

## Data Flow

    main.lua ──deps{query_client(:3030), editor_client(:3031)}──► IdePanels.install
    Panel dispatch ──► shell:publish_selection ──► Properties.set_context + tab focus
    Panel on_tick ──► AsyncSlot.poll ──► QueryClient._get (pending-rearm loop)
    Shell render ctx += player_position (nil-safe, object_manager each frame)

## File Changes (remediation, post-baseline)

| File | Action | Why |
|------|--------|-----|
| `sentinel/ui/async_slot.lua` | Create | Shared poll-until-resolved |
| `sentinel/shared/editor_client.lua` | Create | :3031 campaign client |
| `SentinelQueryServer/src/zone_names.rs` | Create | Static TBC area map |
| `main.lua`, `ide_panels.lua`, `shell.lua`, `shell_state.lua` | Modify | Wiring, bus, ctx.player_position |
| `panels/{explorer,properties,graph,database}_state.lua` + renders | Modify | Slots, stubs→real, measured text |
| `ui/widgets.lua` | Modify | `text_input` widget |
| `query-types/src/lib.rs`, `db.rs`, `handlers.rs`, `main.rs` | Modify | Extensions + 2 endpoints |
| `tests/harness/mocks/sylvannas_api.lua`, fixtures, `scripts/smoke_questing_ide.sh` | Modify/Create | Pending mock, shape test, smoke gate |

## Baseline Plan (Phase 0)

Snapshot first: `git diff > .scratch/qir/pre-baseline.diff`; `git ls-files -o --exclude-standard | tar -czf .scratch/qir/untracked.tar.gz -T -`.
B1 editor Rust (campaign_{handlers,history,store}.rs + lib/main/server.rs) → B2 QueryServer+query-types+query_client.lua → B3 explorer(+test) → B4 graph+escort(+test) → B5 properties(+test) → B6 database(+test) → B7 shell extensions (shell/ide_panels/runner_panel_state, stats/travel/validation, run_offline + 3 modified tests). B3–B6 are orphan modules (unwired until B7) → every commit loadable; suite green per commit.

## PR Split (stacked-to-main, ≤400 lines)

P0 baseline → PR1 wiring/contract/unavailable → PR2 async_slot+harness+re-arm → PR3 bus+player_position → PR4 Rust types+consumers → PR5 endpoints → PR6 text_input+Explorer search → PR7 editor client+Graph lifecycle → PR8 add_*/edit_intent stubs → PR9 Properties views+condition/inventory → PR10 Database render+scanner+grind → PR11 travel/stats/validate+sweep → PR12 smoke+docs.

## Testing Strategy

| Layer | What | How |
|-------|------|-----|
| Unit (Lua) | re-arm per panel; text input keys; measured text; fixture-shape | `luajit sentinel/tests/run_offline.lua` with pending mock |
| Unit (Rust) | extended queries, zone map, both endpoints | `cargo test` (both workspaces) |
| Smoke | live :3030+:3031 checklist | `scripts/smoke_questing_ide.sh` — archive gate |

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary (HTTP to localhost servers only).

## Migration / Rollout

No migration. On-disk profiles/campaigns untouched. Rollback: revert stack in reverse; full abort resets to 99bb8d7 + snapshot restore.

## Open Questions

- [x] **USER SIGNED OFF 2026-07-26**: zone fork resolved — F13 grind = map+position+radius; zone names catalog from AreaTable.dbc (taxi-pattern ETL); spawn→zone index from maps/*.map area grids restores `/zone/{id}/spawns` at 100% coverage
- [ ] `window:block_input_capture()` and `core.input.is_key_down(16)` undocumented — both proven in-repo (AstroUI.lua:2286-2442); confirm in-game during PR6; fallback is focus-gated capture
- [ ] Vendor `ExtendedCost≠0` items price as 0 — acceptable for v1?
