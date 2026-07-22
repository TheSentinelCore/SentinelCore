# Exploration: browser-editor-ui

**Phase**: sdd-explore | **Date**: 2026-07-22 | **Mode**: hybrid (openspec + engram)

## Problem

ADR-306 mandates an in-game quest profile editor. The Lua implementation (`editor_ui.lua`) failed repeatedly on Sylvannas platform constraints and is broken as written: its entire HTTP layer calls `core.http_get/http_post` synchronously while the Sylvannas API is callback-async, and it calls `core.http_put/http_delete` which do not exist at all. Meanwhile a working Rust editor server already exists on :3031 — the UI simply lives on the wrong side of the split. This change moves the editor UI to the browser, served by that existing Rust server, and amends ADR-306 accordingly.

## Current State

### The failed in-game editor (Lua)

- `sentinel/modules/questing/editor_ui.lua` (2352 lines): three-layer design (EditorClient / EditorProject / QuestingEditor).
  - `EditorClient:_get/_post` (L96–119) call `core.http_get(url)` / `core.http_post(url, body)` synchronously via `pcall` and expect a return value. Sylvannas is callback-only: `core.http_get(url: string, callback: function)` (`Documentation - Project Sylvannas/dev/api/core.md` L872–877). Every call returns nil → the client is dead as written.
  - `EditorClient:_put/_delete` (L121–144) call `core.http_put` / `core.http_delete`, which do not exist in the Sylvannas API at all.
  - UI primitives are `---@stub` markers (header comment L12–14); frame creation was forced into render callbacks, hitting Sylvannas runtime-only registration rules.
- `sentinel/main.lua` wiring: lazy-load + toggle subscription (L27–39), `ensure_frames_created` in render hook (L171–172), `_on_render_window` in render hook (L201–202), destroy (L226–234). This is the **only** place `editor_ui` is referenced — `sentinel/tests/modules/questing/test_runtime_arch_polish.lua` L161–201 explicitly asserts `toggle_editor` does NOT require `editor_ui`, so the module is already decoupled.
- Platform constraints that killed it: runtime-only callback registration, no menu-element creation in render callbacks, mandatory button string ids, no `os` lib, no global `JSON`, async-only HTTP GET/POST.

### The Rust editor server (the actual asset)

- `sentinel-questing/editor/src/server.rs`, `build_router` (L754–788): 21 routes under `/editor/*`, axum 0.8, `CorsLayer::any()` already applied (L755–758). Port from `SENTINEL_EDITOR_PORT`, default 3031 (L796–800). Thin bin at `editor/src/main.rs`.
- **Session model**: `AppState.project_store: Arc<RwLock<HashMap<String, ProjectSession>>>` (L36–38). `handle_load_project` (L202–233) loads from disk into a session; commands operate on the session.
- **CRITICAL GAP — no persistence after commands**: all six command handlers (`handle_add_operation` L369, `handle_remove_operation` L403, `handle_modify_operation` L440, `handle_add_action` L484, `handle_remove_action` L517, `handle_modify_action` L574) call `session.history.execute(...)` and return the project JSON but **never write to disk**. Server restart = silent loss of all edits since last explicit save.
- **Secondary gaps**:
  - `handle_save_project` (L235–276) **resets undo history** — it inserts a fresh `CommandHistory` into the session (L264–271). A browser "full save" would silently kill undo.
  - `history::MoveOperation` (history.rs L122–152) and `history::ModifyProjectMeta` (history.rs L288–309) exist but have **no HTTP endpoint**. MoveOperation is required for timeline drag-reorder.
  - `POST /editor/projects/{name}/rename` (server.rs L768) renames the file on disk but bypasses the command history (not undoable).
  - Command handlers 404 if the project isn't in the session store (e.g. L378–385) — load-first is mandatory.
- Existing deps: `tower-http` with only the `cors` feature (workspace `Cargo.toml` L47); **no** `rust-embed`, **no** tower-http `fs` feature. Notably, `sentinel-editor` already depends on `sentinel-queryclient` (editor `Cargo.toml` L17) — server-side proxying to the QueryServer is nearly free.
- QueryServer (`SentinelQueryServer/src/main.rs` L25–35): 11 routes, all GET/POST (browser-compatible methods) but **no CORS layer** → a page served from :3031 cannot fetch :3030 directly (cross-origin). Needs either a proxy or a CORS layer there.

### Data

- `sentinel-questing/.questing/projects/`: 8 flat Project JSONs (7 batch-imported RestedXP guides). Largest `1-11-Elwynn-Forest.json` = 476K, **326 operations / 1374 actions**.
- Shapes: `Operation = {id, name, enabled, conditions[], actions[]}`, `Action = {id, enabled, type, payload}` — a generic `type`+`payload` discriminated union, ideal for a small per-type form registry in a framework-free UI.
- Repo has **zero** existing frontend tooling (no package.json, no bundler, no node).

## Options Considered

### Q1 — Serving strategy

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **(a) Vanilla JS SPA, embedded via `rust-embed`** | Zero new toolchain (solo Rust+Lua shop); single binary serves UI+API same-origin (CORS moot in prod); dev-mode serves from disk → edit/refresh iteration; small, reviewable diffs; action `type`+`payload` model maps cleanly to a per-type form registry | Hand-rolled state/DOM code; drag-reorder needs a vendored lib (e.g. SortableJS, single file, no build) | Low–Med |
| **(b) Vite+React build, embedded** | Better for highly interactive widgets; ecosystem | Introduces node/npm toolchain + build step + dependency surface to a Rust+Lua repo; review budget pressure; solo maintainer doesn't work in React | Med–High |
| **(c) External dev-server flow** | Fastest iteration | Two processes forever; production story still requires (a) or (b); CORS already `Any` so it "works" but ships nothing | Low (dev only) |

**Recommendation: (a)** — vanilla JS (ES modules, no build step) embedded with `rust-embed` (debug: serve from disk for instant iteration; release: embedded in the binary). Vendored SortableJS for drag-reorder if hand-rolled HTML5 DnD proves fiddly. The UI is CRUD+lists+forms, not a reactive graph — a framework buys little and costs a toolchain. Escape hatch: the API contract is identical for (b), so upgrading later is cheap if v1 proves the ceiling.

### Q2 — Rust API work required (concrete)

All in `sentinel-questing/editor/` unless noted:

1. **Persist-after-command** (the one mandatory fix): after each `session.history.execute(...)` in the six command handlers (server.rs L387–397, 427–434, 467–478, 502–511, 558–568, 607–618), call `EditorApi::save_project(&state.projects_dir, &session.project)`. Extract a helper (e.g. `execute_and_persist`) to avoid six duplications. Without this, the browser editor silently loses work on restart — and `compile`/`validate` (which read from disk, L347–363) operate on stale state.
2. **MoveOperation endpoint**: `POST /editor/projects/{name}/move-operation` `{from, to}` → `history::MoveOperation` (history.rs L122) + persist. Required for timeline reorder.
3. **Static UI serving**: new `GET /` + asset routes serving the embedded SPA (rust-embed; fallback route to `index.html`). New dep `rust-embed`; dev override via env (e.g. `SENTINEL_EDITOR_UI_DIR`) to serve from disk.
4. **QueryServer access**: add proxy routes (e.g. `GET /editor/query/*` → forward to 127.0.0.1:3030) using the already-present `sentinel-queryclient` dependency, OR add a `CorsLayer` to `SentinelQueryServer/src/main.rs`. Proxy preferred: keeps the browser single-origin and avoids touching a second service.
5. **Do NOT reset history on full save**: `handle_save_project` (L264–271) inserts a fresh `CommandHistory`; preserve the existing session's history instead.
6. **POST aliases for save/delete/save-dir: NOT needed** — that was a Lua constraint (no PUT/DELETE in Sylvannas). Browsers speak all methods. Skip unless the v2 in-game launcher must save.
7. **ModifyProjectMeta endpoint: defer** — the existing `POST /rename` covers renaming; making rename undoable via `history::ModifyProjectMeta` is a design question (below), not v1 scope.
8. **OpenAPI/route shape**: no OpenAPI spec exists and none is needed; keep the existing REST-ish shape, additive only. Command handlers already return full updated project JSON — good for UI sync.
9. **CORS**: production is same-origin (UI from the same binary), so the existing `CorsLayer::any()` only matters for dev experiments. Leave as-is; optionally tighten later.

### Q3 — v1 UI scope (ADR-03's 7 panels → the import→review→fix→compile→run loop)

The v1 user loop: 8 imported RestedXP projects exist → review operations/actions → fix issues → validate → compile → runtime JSON hot-reloads in game.

| ADR-03 panel | v1 | v2 |
|---|---|---|
| Project Explorer | **Yes** — project list (list/create/load/rename/duplicate/delete) + operations tree | — |
| Timeline | **Yes** — operations → actions, add/remove/edit, drag-reorder via MoveOperation, enable/disable toggles (`enabled` field exists in model) | multi-select, copy/paste, blueprints (ADR-304) |
| Inspector | **Yes** — per-action-type form registry editing `payload`; changes apply via modify-action | smart capture suggestions |
| Validation | **Yes** — diagnostics list from `POST /validate`, click → select offending op/action | live validation on edit (debounced) |
| Query Browser | **Slim** — search-backed picker fields in Inspector (NPC/quest lookup via proxy) | full panel with one-click import |
| Console | **Slim** — compile button + `CompileResult` display + errors | live runtime log streaming, dry-run output |
| Entity Library | **No** — deferred (Inspector pickers cover the need) | full library panel with roles |

Also v1: undo/redo buttons + history status (`/history` endpoint exists), save indicator, auto-load on first command (or explicit load — open question). Deferred entirely: Area Editor, Travel Recorder, Target Capture, Dry Run, Source Mapping UI (ADR-305), keyboard shortcut map, docking/layout persistence.

### Q4 — v2 draft scope (outline only)

- **In-game slim client**: launcher/status panel (server reachable? which project loaded? runtime status from blackboard) + hot-reload trigger + "open browser" hint. Tiny surface, only GET/POST.
- **Capture overlays** (genuinely need live game state): Target Capture (GUID/entry/position via object_manager → POST to editor), Area/Travel recording (player position stream → polygon/path → POST).
- **Dry-run**: runtime simulates the profile with movement/combat disabled.

### Q5 — Fate of `editor_ui.lua`

**Deprecate fully — delete it, as its own PR slice.** Rationale: the file has never worked (sync-over-async HTTP, nonexistent `http_put/delete`, stubbed UI), 2352 lines of dead weight. The slim launcher is v2 scope and should be written fresh against the slim API, not salvaged from this file. Required `main.lua` changes either way: remove `ensure_editor_wired` (L27–39), the render-hook calls (L171–172, L201–202), destroy wiring (L226–234), and the `_toggle_editor_btn` menu button (L19); repurpose the `questing:toggle_editor` event (module.lua L73) to a status/hint message or drop it until v2. The arch-polish test (test_runtime_arch_polish.lua L161–201) already guards the decoupling and should keep passing.

### Q6 — ADR-306 amendment (what it should say)

Draft direction for the proposal phase (new ADR or amendment section; ADR-306 currently has **no stated rationale**, so this is an amendment with reasons, not a reversal of a argued decision):

> **ADR-306 (amended)**: The primary editor for v1 is a browser-based UI served by the Sentinel Editor server (Rust, :3031). The in-game surface is reduced to runtime execution + hot-reload; v2 adds a slim in-game launcher/status panel and capture overlays (target, area, travel) for the features that require live game state.
> **Rationale**: Sylvannas platform constraints (callback-only async HTTP GET/POST, no PUT/DELETE, runtime-only callback registration, no menu creation in render callbacks, no `os` lib, no global `JSON`) make a full in-game editor impractical — the Lua implementation failed repeatedly on these. The Lua↔Rust split already existed de facto (the Rust server owns persistence, validation, and compilation); the browser UI moves the presentation layer to where the full API is expressible, at zero toolchain cost (embedded static assets, same-origin).

### Delivery forecast (auto-forecast, 400-line budget)

- `Decision needed before apply: Yes` (open questions below, esp. proxy-vs-CORS and UI folder layout)
- `Chained PRs recommended: Yes`
- `400-line budget risk: High` — total work is ~300–400 lines Rust + ~1500+ lines UI + ~2400 deletions Lua. Proposed slices, each with clear start/finish/verification:
  1. **PR1 — API completion**: persist-after-command helper + MoveOperation endpoint + history-preserving save + tests (~300 lines).
  2. **PR2 — UI shell**: rust-embed wiring, `GET /`, project list, load, read-only timeline (~350 lines).
  3. **PR3 — Editing**: inspector forms, add/remove/modify, drag-reorder, undo/redo (~500 lines — may need splitting further at tasks phase).
  4. **PR4 — Loop closure**: validation panel, compile console, query proxy + pickers (~350 lines).
  5. **PR5 — Lua removal + ADR amendment**: delete editor_ui.lua, unwire main.lua, amend ADR-306 (~mostly deletions; authored lines small).

## Open Questions for the proposal phase

1. **Proxy vs CORS for QueryServer** — recommended: proxy `/editor/query/*` via existing `sentinel-queryclient` dep. Confirm QueryServer stays untouched.
2. **Rename undoability** — keep `POST /rename` non-undoable for v1, or route it through `history::ModifyProjectMeta` (which only renames metadata, not the file — semantics need care)?
3. **Auto-load vs explicit load** — should command handlers auto-load a missing session from disk instead of 404ing? (Better browser UX; slightly magic.)
4. **UI source layout** — propose `sentinel-questing/editor/ui/` (static files, embedded at compile time, disk-served in dev). Confirm naming.
5. **Drag-reorder** — hand-rolled HTML5 DnD vs vendored SortableJS (single file, ~40KB, no build). Recommendation: start hand-rolled, vendor if painful.
6. **Concurrency guard** — accept last-writer-wins for v1 (single-user desktop tool), or add a cheap `updated_at`/version check on save?
7. **Compile output & hot-reload path** — compile writes runtime JSON where, and what confirms the in-game runtime picked it up? (module.lua L83 references a temp `_editor_compile.json` path — verify the real flow in design phase.)
8. **ADR mechanics** — amend `03_EDITOR_AND_IMPORTER.md` ADR-306 in place vs new ADR file? (Repo convention: ADRs live inside ADR docs 00–05, not one-file-per-ADR.)

## Risks

1. **Silent data loss (current code)** — commands don't persist; a browser UI makes this user-facing. PR1 must land before any UI work. *Severity: high, effort: low.*
2. **Undo history semantics** — server restart kills undo (acceptable, document); full-save currently resets history (fix in PR1); users will expect browser-refresh to preserve state (it will, via disk, after PR1).
3. **Concurrent editing** — two tabs or browser+game racing one project: `project_store` is last-writer-wins with no version check. Acceptable for a single-user tool; document; optional version guard is open question #6.
4. **Large project round-trips** — every command returns full project JSON (up to 476K). Fine on localhost (~ms), but the UI must handle 326 ops / 1374 actions: render operations collapsed by default, only render the expanded operation's actions; no full-timeline DOM. If that proves insufficient, add a "return summary only" command flag in v2.
5. **Asset embedding pitfalls** — rust-embed debug/release feature flags (must not embed stale assets in dev), correct MIME types, SPA fallback route, and remembering `cargo build` after UI edits in release mode. Mitigation: dev mode serves from disk via env override.
6. **Scope creep into v2 features** — capture overlays, dry-run, and the slim launcher are tempting during UI work; the amendment language must keep v1 strictly browser-only.
7. **Deletion blast radius (PR5)** — editor_ui.lua removal touches main.lua render/menu wiring; the offline test suite (`lua sentinel/tests/run_offline.lua`) must stay green, and any doc references to the in-game editor need updating alongside the ADR amendment.
