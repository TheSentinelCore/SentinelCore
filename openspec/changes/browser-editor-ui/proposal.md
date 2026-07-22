# Proposal: Browser-Based Quest Editor UI

**Change**: browser-editor-ui | **Date**: 2026-07-22 | **Store**: hybrid (openspec + engram)

## Intent

ADR-306 mandates an in-game editor, but the Lua implementation (`sentinel/modules/questing/editor_ui.lua`, 2352 lines) cannot work: its HTTP layer calls `core.http_get/http_post` synchronously while Sylvannas is callback-async, calls nonexistent `core.http_put/http_delete`, and its UI stubs hit runtime-only registration rules. ADR-306 states **no rationale**, so amending it is a reasoned amendment, not a reversal. The import→review→fix→compile→run loop (PRD §13) is therefore broken at the review/fix step. Meanwhile a working axum editor server already owns persistence, validation, and compilation on :3031 — the UI simply lives on the wrong side of the Lua↔Rust split. Move the editor UI to the browser, served by that server, and complete the server API gaps that the browser will expose (worst: commands never persist to disk).

## Scope

### In Scope (v1)
- **Rust API completion** (`sentinel-questing/editor/`): persist-after-command on all six command handlers (via shared `execute_and_persist` helper); `POST /editor/projects/{name}/move-operation`; history-preserving full save; `GET /editor/query/*` proxy to QueryServer via existing `sentinel-queryclient` dep; static SPA routes (`GET /`, assets, `index.html` fallback) via `rust-embed` with `SENTINEL_EDITOR_UI_DIR` dev override.
- **Browser UI** (`sentinel-questing/editor/ui/`, vanilla JS ES modules, no build step), mapped to ADR-03 panels: project list/CRUD (Project Explorer); operation list with add/remove/reorder (drag) and action list per operation with add/remove/modify (Timeline + Inspector, per-`type` payload form registry); validation view with clickable diagnostics (Validation); compile + download/copy runtime JSON (Console slim); NPC/quest/object search pickers via proxy (Query Browser slim); log/console view.
- **Deletion** of `editor_ui.lua`'s IDE surface — reduce to nothing (file deleted); unwire `main.lua` (L19, L27–39, L171–172, L201–202, L226–234) and `questing:toggle_editor`; keep `test_runtime_arch_polish.lua` (L161–201) green.
- **ADR-306 amendment** (see below).

### Out of Scope (v1)
Docking layouts, drag-drop timeline polish beyond basic reorder, multi-select, copy/paste, undo/redo UI buttons (API exists), live validation, dry-run, all capture features (Target/Area/Travel), source-mapping UI, Entity Library panel, collaborative editing, auth, POST aliases for save/delete, undoable rename.

## Capabilities

### New Capabilities
- `editor-server-api`: HTTP API for project/operation/action CRUD with command history, guaranteed persistence, operation reorder, compile/validate, and QueryServer proxying.
- `editor-web-ui`: browser SPA served by the editor server covering the import→review→fix→validate→compile→download loop.

### Modified Capabilities
None — `openspec/specs/` is empty; no existing requirement text changes. (ADR-306 is doc-level, handled as an amendment, not a spec delta.)

## Approach

Vanilla JS SPA embedded via `rust-embed` (debug: disk; release: embedded), served same-origin from the existing axum server — zero new toolchain, CORS moot in production, API contract reusable if a framework is ever needed later. PR1 (API completion incl. persistence) lands **before** any UI work. QueryServer stays untouched (proxy, not CORS).

**ADR-306 (amended)** — in-place amendment in `03_EDITOR_AND_IMPORTER.md` §29 with rationale appended: *the primary v1 editor is a browser UI served by the Sentinel Editor server (:3031); the in-game surface is reduced to runtime execution + hot-reload; v2 adds a slim in-game launcher/status panel and capture overlays.* Rationale: Sylvannas constraints (async-only GET/POST, no PUT/DELETE, runtime-only callback registration, no `os`, no global `JSON`) make a full in-game editor impractical; the Rust server already owns persistence/validation/compilation, so the browser moves presentation to where the full API is expressible at zero toolchain cost.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `sentinel-questing/editor/src/server.rs` | Modified | persist-after-command, move-operation, save fix, proxy, static routes |
| `sentinel-questing/editor/Cargo.toml` | Modified | add `rust-embed` |
| `sentinel-questing/editor/ui/` | New | SPA static assets |
| `sentinel/modules/questing/editor_ui.lua` | Removed | never worked; 2352 lines deleted |
| `sentinel/main.lua`, `sentinel/modules/questing/module.lua` | Modified | unwire editor UI |
| `sentinel/docs/adr/03_EDITOR_AND_IMPORTER.md` | Modified | ADR-306 amendment |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Silent data loss ships user-facing (commands don't persist) | High (if unordered) | PR1 persistence lands before any UI; hard ordering gate |
| Full save resets undo history | Med | PR1: preserve session `CommandHistory` |
| Large projects (476K, 326 ops/1374 actions) blow up DOM | Med | collapsed-by-default ops; render only expanded op's actions |
| rust-embed staleness/MIME/SPA-fallback pitfalls | Med | dev serves from disk via env override; release checklist |
| Scope creep into v2 (capture, dry-run, launcher) | Med | amendment language locks v1 browser-only |
| Deletion blast radius in `main.lua` | Low | arch-polish test already guards decoupling; offline suite must stay green |
| Concurrent edits (two tabs) last-writer-wins | Low | accept for single-user tool; documented |

## Rollback Plan

PRs 1–4 are additive — revert any slice independently. PR5 (Lua deletion + ADR amendment) reverts via git; ADR amendment is text, reverted with the commit. No data migration exists; project JSONs on disk are untouched by rollback.

## Dependencies

- Existing `sentinel-queryclient` dep (proxy); `rust-embed` (new); vendored SortableJS only if hand-rolled DnD fails.
- `import-guides` flow already produces the 8 test projects.

## Success Criteria

- [ ] Import a RestedXP guide via `import-guides`, open it in the browser, fix an unresolved NPC via the query browser, compile, and download/copy valid runtime JSON — **no game client involved**.
- [ ] Server restart after edits loses nothing (persistence covered by Rust tests).
- [ ] Hot-reload path (compile output → runtime pickup) is exercised in-game and documented.
- [ ] `lua sentinel/tests/run_offline.lua` green after editor_ui.lua removal.
- [ ] PRD §13 loop (import→compile→run→edit→compile→reload) completable in minutes.

## Delivery Strategy (chained PRs — 400-line budget risk: High)

1. **PR1 — API completion** (persist, move-op, save fix, proxy, tests; ~300 lines). **Must precede UI.**
2. **PR2 — UI shell** (rust-embed, routes, project list/load, read-only timeline; ~350).
3. **PR3 — Editing** (inspector forms, add/remove/modify, drag-reorder, undo/redo; ~500 — split further at tasks phase if needed).
4. **PR4 — Loop closure** (validation panel, compile console, query pickers; ~350).
5. **PR5 — Lua deletion + ADR-306 amendment** (mostly deletions).

## Open Questions Resolved

1. **Proxy vs CORS** → proxy `/editor/query/*` via `sentinel-queryclient`; QueryServer untouched.
2. **Rename undoability** → keep `POST /rename` non-undoable in v1; revisit via `ModifyProjectMeta` later.
3. **Auto-load** → explicit load for v1 (load-first 404 semantics retained); auto-load is a v2 UX candidate.
4. **UI dir** → `sentinel-questing/editor/ui/` confirmed.
5. **Drag-reorder** → hand-rolled HTML5 DnD first; vendor SortableJS only if painful.
6. **Concurrency guard** → last-writer-wins, documented; no version check in v1.
7. **Compile output/hot-reload** → verify real flow vs `module.lua` L83 `_editor_compile.json` in design phase; success criterion requires documented path.
8. **ADR mechanics** → amend ADR-306 in place in `03_EDITOR_AND_IMPORTER.md` (repo convention: ADRs inside ADR docs).

## v2 Draft (future change, outline only)

Slim in-game launcher/status panel + hot-reload trigger; capture overlays (Target Capture, Area/Travel recording via object_manager → POST); dry-run mode; blueprint library (ADR-304); auto-load sessions; live validation.
