# Design: Browser-Based Quest Editor UI

## Technical Approach

Vanilla-JS ES-module SPA in `sentinel-questing/editor/ui/` (no build), embedded via `rust-embed`, served same-origin by the existing axum server (explore Q1a). Server gaps closed first: persist-after-command, move-operation, history-preserving save, `/editor/query/*` proxy, static SPA routes. Lua IDE surface deleted; ADR-306 amended in place.

## Architecture Decisions

| Decision | Alternatives | Choice | Rationale |
|---|---|---|---|
| Persist-after-command | 6× duplication (drift); EditorApi wrapper (hides session) | `execute_and_persist` helper in `server.rs` | one site; session/history stay in server |
| Move-operation | new command type | reuse tested `history::MoveOperation` | zero new undo logic |
| Full-save history | reset (status quo) | keep session's `CommandHistory`; fresh only if no session | undo survives browser saves |
| Query access | CORS on QueryServer; raw reqwest passthrough | typed proxy via `Arc<dyn QueryClient>` | single origin; `MemoryQueryClient` in tests; inherits 10s timeout/3 retries/GET cache |
| Static UI | tower-http `fs`; hand-rolled | `rust-embed` + `mime_guess` | debug=disk, release=embedded |
| Undo after divergent PUT save | clear history | keep, documented | last-writer-wins already accepted |
| Undo/redo UI buttons | ship in PR3b | excluded (proposal L18) | API exists; UI deferred past v1 — inclusion must be explicit, never silent |
| Library upsert on reference insert | client read-modify-write via PUT (last-writer-wins on the whole project) | new `POST /editor/projects/{name}/add-library-entity` in PR1 | atomic single-entity upsert, persists immediately; no full-project race |
| Proxy payload fidelity | raw reqwest passthrough (already rejected) | typed DTO round-trip + passthrough test | test asserts no field dropped/reshaped vs upstream JSON |

## Data Flow

    SPA ─same-origin→ axum :3031 ─→ EditorApi ─→ .questing/projects/*.json
      │                  ├─ command → history.execute → save_project (NEW)
      │                  └─ /editor/query/* → HttpQueryClient → QueryServer :3030
    compile → profile_json → download/copy → file drop / console paste → hot reload

## Rust Changes (`sentinel-questing/editor/`)

**`server.rs`** — helper used by all six command handlers; handlers keep their 400 bounds/JSON pre-validations:

```rust
async fn execute_and_persist(
    state: &AppState, name: &str, cmd: Box<dyn history::EditorCommand>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)>
```

Body: write-lock → `get_mut` else 404 "not loaded" (extracts the duplicated block) → `history.execute` (`internal_error`→500, post-validation invariant) → `EditorApi::save_project` (`editor_error_to_response`: Io/Serde→500; session/disk divergence documented) → full project JSON.

**Move-operation**: `POST /editor/projects/{name}/move-operation`, DTO `{ from: usize, to: usize }`; 400 unless both `< len`; `from == to` no-op allowed; runs `history::MoveOperation` through the helper.

**Add-library-entity**: `POST /editor/projects/{name}/add-library-entity`, DTO `{ kind: "npc"|"quest"|"object", entity: serde_json::Value }`; upserts into the matching project library (dedup by entry/id), persists via `EditorApi::save_project`; NOT routed through command history in v1 (documented; undo covers structural edits only). 404 unloaded project; 400 invalid kind/entity.

**History-preserving save** (`handle_save_project` L262-272): session exists → assign `session.project = deser` (history untouched); else insert new session. Disk write unchanged.

**Query proxy**: `AppState` gains `query_client: Arc<dyn QueryClient>` (= `HttpQueryClient::new(SENTINEL_QUERY_URL || "http://127.0.0.1:3030")`) and `ui_dir: Option<PathBuf>`. GET routes: `/editor/query/npc/search?q=`, `/npc/{entry}`, `/quests/search?q=`, `/quest/{id}`, `/vendor/{entry}`, `/trainer/{entry}`, `/flight/{entry}`, `/object/{entry}`, `/creatures/polygon?entry=` (v1 pickers never need the two POST endpoints). Responses pass through `sentinel-query-types` DTOs (already `Serialize`) — **fidelity note**: the typed round-trip MUST NOT drop or reshape fields vs upstream; a passthrough integration test compares proxy output against upstream JSON field-by-field. `query_error_to_response()`: `NotFound`→404; `Transport`/`Server`/`Decode`→502 (upstream status in body); reuses `ErrorResponse{error}`.

**rust-embed** (`Cargo.toml` +`rust-embed="8"`, `mime_guess="2"`; dev-dep `tower={version="0.5",features=["util"]}`):

```rust
#[derive(rust_embed::RustEmbed)] #[folder = "ui/"] struct EditorUiAssets;
```

Debug serves from disk (default), release embeds; `SENTINEL_EDITOR_UI_DIR` overrides both via `tokio::fs`. Router: `.fallback(handle_static)` — paths under `/editor` or `/health` → 404; else asset with mime_guess Content-Type, falling back to `index.html` (SPA deep links).

## Web UI (`sentinel-questing/editor/ui/`)

```
index.html · css/app.css
js/main.js    bootstrap + hash router (#/projects #/timeline #/validation #/compile #/query #/console)
js/api.js     fetch client; {error}→throw {status,message}
js/state.js   store + topic pub/sub          js/router.js  hash view switching
js/views/     projects.js (Explorer CRUD) · timeline.js (ops collapsed; only expanded op renders
              actions — 476K project safe) · inspector.js (pane in timeline) · validation.js
              (click→select op/action) · compile.js (CompileResult + Blob download/clipboard) ·
              query.js (search + picker mode) · console.js
js/components/payload-forms.js  form registry keyed by ActionPayload variant
```

Rendering: targeted DOM via `el()` + `view.render(root)`; no framework. Dirty: mutations persist per command, so dirty = unapplied inspector form (Apply/Discard) **or a failed persist request** (persist-failure ⇒ dirty ⇒ beforeunload prompt; successful command ⇒ not dirty — matches web-ui spec). "saved ✓" per response; errors toast + console. Field kinds: `number,text,bool,quest-id,uuid-npc,uuid-object,uuid-area,position,list-number,list-position,variable-value`; `uuid-*` opens query-picker and, on confirm, calls `add-library-entity` then sets the field. **`uuid-object` ruling**: QueryServer has no object text search (detail-by-entry only), so object fields use a numeric entry input with a `/object/{entry}` preview card — no picker search.

All 23 variants (`?` = optional):

| Variant | Fields |
|---|---|
| AcceptQuest | quest:quest-id, npc:uuid-npc?, auto_complete_dialog:bool, optional:bool |
| TurnInQuest | quest:quest-id, npc:uuid-npc?, choose_reward:number?, optional:bool |
| Travel | destination:text, position:position?, tolerance:number, mount:text?, allow_flight:bool, timeout:number? |
| Kill | creature_entries:list-number, quantity:number?, loot:bool, ignore_elites:bool |
| GrindArea | polygon:uuid-area?, targets:list-number, loot:bool, timeout:number?, minimum_kills:number?, maximum_kills:number?, stop_condition:text? |
| LootObject | object:uuid-object, count:number? |
| InteractNPC | npc:uuid-npc, gossip:text? |
| Vendor | npc:uuid-npc, sell_grey:bool, repair:bool, buy_items:list-number, minimum_free_slots:number? |
| Repair, LearnFlightPath, Mailbox, Bank | npc:uuid-npc |
| Train | npc:uuid-npc, trainer_type:text?, minimum_level:number? |
| UseItem | item:number, target:uuid-npc? |
| Flight | npc:uuid-npc, destination:text |
| SetHearth | npc:uuid-npc? |
| Hearth | innkeeper:uuid-npc?, destination:text? |
| Wait | duration:number |
| Escort | npc:uuid-npc, area:uuid-area?, timeout:number? |
| Patrol | area:uuid-area?, waypoints:list-position |
| Condition | expression:text |
| SetVariable | name:text, value:variable-value (`{"Bool"\|"Int"\|"Float"\|"String"\|"QuestId"\|"NpcId": v}`) |
| Comment | text:text |

## Lua Deletion Plan

**Design-phase discoveries** (flagged under proposal OQ#7; `runtime_profile.lua` is outside the proposal's Affected Areas but required by success criterion #3): `core.write_file` and `core.get_file_info` do not exist per the Sylvannas docs — the console-paste compile path and mtime-based hot reload are broken today. Both fixes land in PR5, kept minimal and behind the offline suite.

- **`editor_ui.lua`**: delete (2352 lines).
- **`main.lua`**: remove L19 (menu button), L21-24 (locals), L27-39 (`ensure_editor_wired`), calls at L91, L136-137, editor blocks in `on_update` (L166-183) and `on_render_window` (L198-213) keeping the `app:*` calls, menu callback L216-223 (empty post-removal), editor lines in `on_unload` (L225-237). Keep `toggle_quest_editor` (L147-157) as deprecated no-op logging "editor moved to browser :3031", returns false (protects user binds).
- **`module.lua`**: drop editor docstring line; keep `toggle_editor` (L72-74) unchanged; fix `load_compiled_profile` L84 `core.write_file`→`core.write_data_file` (verified: `write_file`/`get_file_info` absent from Sylvannas docs; `file-io.md` documents only `read/write_data_file` — the guard silently no-ops in-game today).
- **Tests**: `test_runtime_arch_polish.lua` L161-201 untouched, stays green (event still published, `editor_ui` never required); `run_offline.lua` unchanged. Add offline test: `load_compiled_profile` writes temp file via `write_data_file` and enables executor.

## ADR-306 Amendment (`03_EDITOR_AND_IMPORTER.md` §29, replaces L1013-1019)

> ## ADR-306 (amended 2026-07-22)
> The primary v1 editor is a browser-based UI served by the Sentinel Editor server (Rust, :3031). The in-game surface is reduced to runtime execution + hot-reload; v2 adds a slim in-game launcher/status panel and capture overlays. No external desktop IDE required.
> **Rationale**: Sylvannas constraints (callback-only async HTTP GET/POST, no PUT/DELETE, runtime-only callback registration, no menu creation in render callbacks, no `os`, no global `JSON`) made the in-game editor (`editor_ui.lua`) unworkable. The Rust server already owns persistence, validation, and compilation; the browser moves presentation to where the full API is expressible at zero toolchain cost (embedded assets, same-origin).
> **Consequences**: `editor_ui.lua` deleted; `main.lua` unwired; `questing:toggle_editor` kept as no-op event; import→review→fix→compile runs browser-only; capture defers to v2.

## Compile→Hot-Reload Flow (verified)

1. `POST .../compile` returns `profile_json`; server intentionally never writes it. Browser downloads `<name>.runtime.json` or clipboard-copies.
2. **Path A (file drop)**: overwrite the loaded JSON; `_check_hot_reload` (state=="running") swaps on `content_hash` change, preserving variables. **Gap**: mtime source `core.get_file_info` undocumented, `lfs` fallback unproven → if both absent, reload never fires. **Fix** (runtime_profile.lua): when mtime unavailable, poll content every 30 ticks; the existing `content_hash` compare prevents no-op swaps.
3. **Path B (console)**: `_G.Sentinel.questing():load_compiled_profile(json)` → temp `_editor_compile.json` → `initialize()`. Broken today (the `write_file` bug); the same PR5 fix repairs it. Both paths then share the `*_data_file` data-dir root.

## PR Slicing (400-line budget; proposal PR3 split into 3a/3b)

| PR | Goal | Files | ~Lines | Verification | Rollback |
|---|---|---|---|---|---|
| 1 | API completion | server.rs + tests (incl. add-library-entity), Cargo.toml | ~380 | `cargo test -p sentinel-editor`; restart-persistence oneshot test | revert (no consumers) |
| 2 | UI shell | Cargo.toml, server.rs static/fallback, ui shell + api/state/router + projects + read-only timeline | ~380 | oneshot index-fallback test; manual browse | revert |
| 3a | Inspector | payload-forms.js, inspector.js, timeline wiring | ~350 | checklist: 23 forms render+apply | revert |
| 3b | Structure editing | timeline.js DnD + add/remove (no undo/redo UI — excluded) | ~330 | reorder vs `/history`; add/remove round-trip | revert |
| 4 | Loop closure | validation.js, compile.js, query.js pickers | ~350 | success criterion #1, no game client | revert |
| 5 | Lua deletion + ADR + hot-reload fixes | editor_ui.lua deleted; main.lua, module.lua, runtime_profile.lua, ADR; offline test | ~60 (budget counts non-deletion changes; ~2450 deletions excluded) | `run_offline.lua` green; in-game smoke | git revert |

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Rust unit | helper persists; move-op bounds; save keeps history | `server.rs` tests, tempfile `AppState` |
| Rust integration | new routes; command→restart→reload equality; proxy 404/502; static fallback | `tower::ServiceExt::oneshot` on `build_router`; injected `MemoryQueryClient` |
| JS | no toolchain (zero-node repo): per-PR manual checklist; views kept pure | checklist in PR body |
| Lua offline | suite green; arch-polish guard untouched; new `load_compiled_profile` test | `lua sentinel/tests/run_offline.lua` |
| In-game | compile→drop→hot-reload; toggle no-op hint | manual (success criterion #3) |

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary (HTTP endpoints are application routes, not the matrix's agent/tool routing).

## Migration / Rollout

None — project JSONs untouched; PRs 1-4 additive, independently revertible; PR5 via git revert.

## Open Questions

- [ ] Confirm in-game availability of `core.get_file_info`/`lfs` during PR5; if both absent the 30-tick content poll becomes primary (design already covers it).
