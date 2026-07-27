# Proposal: Questing IDE Remediation — Fix + Finish to Spec

**Change**: questing-ide-remediation | **Date**: 2026-07-26 | **Store**: hybrid (openspec + engram)
**Context**: archived `2026-07-26-questing-profile-ide` was archived prematurely — IDE broken in-game, implementation uncommitted.

## Problem Statement

The archived change passed offline verification (1,864 Lua tests) yet fails in-game: panels were never connected to backends (engram obs #222). Root causes: (1) `main.lua:266` installs panels without `query_client`, and the contract is self-contradictory (documented as resolver fn, used as table); (2) async pending model broken — panels clear `_dirty`/`_pending` before fetch and never re-arm, synchronous offline mocks masked it; (3) phantom APIs (`dbg.nearby`, unsupplied `ctx.player_position`, silent mock grind data); (4) contract drift — panels render fields Rust types lack; (5) Graph campaign create/open never implemented in Lua though the Rust side (:3031) is complete; (6) 8 stub handlers; (7) work left uncommitted. User scope decision: **fix + finish to the original spec** — the Discover → Auto-fill → Adjust → Save loop must work end-to-end in-game.

## Scope

### In Scope
- Phase 0 baseline: land uncommitted work (~11k lines: 14 modified files + ~4.1k panel Lua + ~3.5k tests + ~1.9k editor Rust) as labeled baseline commits
- Foundational repairs: query_client wiring + contract unification; async pending re-arm; cross-panel selection bus; `ctx.player_position` supply; phantom-API and mock-fallback removal
- Rust contract extensions (panels win per arbitration): `NpcDetail.level/classification/loot/quests`, `QuestSummary.zone`, `VendorInfo.sells` as objects
- Missing endpoints: `GET /zone/{id}/spawns`, `POST /travel/route`
- All 8 stub handlers implemented; Graph campaign lifecycle in Lua
- Test-harness hardening: async-pending mock mode, server-shaped fixtures, real-server smoke test

### Out of Scope
- Anything beyond archived spec F1–F20 (F5/F8/F21 remain deferred)
- Canvas graph editor, 3D spawn overlay (F4 stays list-fallback), v2 UX polish
- Reworking committed shell/runner architecture (≤99bb8d7) beyond the query_client wiring fix

## Capabilities

### New Capabilities
- `questing-ide`: in-game IDE panels (Explorer, Graph, Properties, Database) + shell extensions
- `query-server`: QueryServer (:3030) HTTP contract and response types
- `questing-editor`: Editor crate (:3031) campaign CRUD/validate/compile contract

### Modified Capabilities
- None (no `openspec/specs/` exists yet; archived spec is the requirements baseline)

## Remediation Map (archived F-numbers)

| F | Feature | Remediation |
|---|---------|-------------|
| — | Foundations | Wire `query_client` (main.lua:266); unify contract (table, update doc); async pending re-arm (query_client.lua:51-57, ide_panels.lua:337-338, database_state.lua:161-162); selection bus wiring `set_context`; supply `ctx.player_position` (shell.lua:531); remove mock fallbacks |
| F1 | Quest Browser | Build shared key-capture text-input widget (SDK has none); `set_query` in reduce + dispatch; `QuestSummary.zone` via Rust extension |
| F2 | Chain Viz | Implement `add_chain` via editor client |
| F3 | Objective Generator | Implement `add_to_profile` via editor client |
| F4 | Spawn Overlay | List-fallback only; wire real data sources |
| F6 | Waypoint Editor | Position capture works via supplied `ctx.player_position` |
| F7 | Behavior Nodes | Implement `edit_intent` |
| F9 | Spawn Scanner | `core.object_manager` scan replaces phantom `dbg.nearby`; `add_as_kill` implemented; production never serves mock data |
| F10 | NPC Inspector | Selection bus + Rust `NpcDetail` extension |
| F11 | Vendor Editor | `VendorInfo.sells` as objects (Rust) matching panel expectation |
| F12 | Travel Editor | `POST /travel/route` + real client wiring |
| F13 | Grind Generator | `GET /spawns/nearby` (map+position+radius, amended 2026-07-26); real `execute_grind` path (errors surface in `state.error`); `edit_grind_*` implemented |
| F14 | Loot Object Editor | Verify against server types post-bus |
| F15 | Escort Recorder | Verify end-to-end wiring |
| F16/F17 | Condition / Inventory | Loaders + dispatch handlers (stub today, ide_panels.lua:505-515) |
| F18 | Combat Area | Verify node-metadata persistence |
| F19 | Auto Validation | `validate_graph` → `POST /editor/campaigns/{name}/validate` (Rust exists) |
| F20 | Profile Statistics | Wire stats dashboard to real campaign data |
| Graph | Campaign lifecycle | Lua create/open/list commands + `new_graph(client)` + editor :3031 client; empty_state `action_label` (Rust CRUD complete, zero Lua callers) |
| DB panel | Render bugs | `fit_label` px/char unit fix; `view_detail` no-op fix; pending→"Entry N not found" fix; real text measurement via `shell.get_text_size` (replaces 7px/char approx and capped chip widths) |

## Approach

Foundations first (one broken assumption poisons every panel), then Rust contract extensions (unblock panels), then per-panel remediation, then stubs/endpoints, then verification hardening. Lua fixtures reshaped to SERVER types; harness gains an async-pending mock mode so the offline suite reproduces the runtime fetch model — the gap that produced false confidence last cycle.

**Baseline decision (arbitrated open question): adopt baseline-first.** Land existing work as 7 labeled `baseline:` work-unit commits — B1 editor Rust, B2 QueryServer/query-types/query-client, B3–B6 per panel + tests, B7 shell extensions — exempt from review ceremony per preflight, then remediation stacks as reviewable ≤400-line PRs. Justification: (a) mixed baseline+fix diffs are unreviewable and blow the 400-line budget; (b) chained PRs need a committed base to stack on; (c) crisp before/after audit trail — this change exists because the last cycle confused "tests green" with "works in-game"; (d) enables bisection (original bug vs remediation regression). Alternative (remediate-then-commit-everything) rejected: entangles old and new, no stable stack base, no bisection. Safety: snapshot the working tree (`git diff` + untracked tar) before Phase 0.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `sentinel/main.lua` | Modified | Pass `query_client` to `IdePanels.install` |
| `sentinel/ui/ide_panels.lua` | Modified | Contract fix, dispatch stubs, pending re-arm |
| `sentinel/ui/panels/*` | Modified | Per-panel remediation (F-map above) |
| `sentinel/ui/widgets.lua` + new input widget | Modified/New | Key-capture text input; real text measurement |
| `sentinel/shared/query_client.lua` | Modified | Contract unification |
| `sentinel/tests/**` | Modified | Async-pending mocks; server-shaped fixtures |
| `SentinelQuesting/query-types/src/lib.rs` | Modified | NpcDetail/QuestSummary/VendorInfo extensions |
| `SentinelQueryServer/src/*` | Modified | Extended handlers; `/zone/{id}/spawns`, `/travel/route` |
| `SentinelQuesting/editor/src/campaign_*.rs` | Baseline→Modified | Wire 6 placeholder commands; Lua client |

## Review Workload Forecast

| Phase | Content | Est. lines | PRs |
|-------|---------|-----------|-----|
| 0 | Baseline commits (exempt from 400 budget) | ~11,000 | 7 baseline commits |
| 1 | Foundations: client wiring; async model; selection bus | ~800 | 3 |
| 2 | Rust: type extensions; 2 missing endpoints | ~650 | 2 |
| 3 | Explorer: text-input widget; search + add_* | ~650 | 2 |
| 4 | Graph: campaign lifecycle + editor client; edit_intent/validate/compile | ~650 | 2 |
| 5 | Properties: inspector/vendor fields; condition+inventory editors | ~750 | 2 |
| 6 | Database: render fixes; spawn scanner + grind real data | ~650 | 2 |
| 7 | Shell: travel/validation/stats wiring; stub sweep | ~550 | 2 |
| 8 | Smoke-test harness + docs | ~200 | 1 |

Stacked-to-main; each remediation PR ≤400 lines (split further on overflow). `Decision needed before apply: No` (delivery pre-resolved: force-chained). `Chained PRs recommended: Yes`. `400-line budget risk: Medium` (Graph/Properties densest).

## Success Criteria

- [ ] In-game end-to-end authoring loop: discover quest (Explorer against live QueryServer) → auto-fill objectives → adjust in Graph/Properties → save via :3031 with validation toast → run in Runner — **zero JSON hand-editing**
- [ ] `luajit sentinel/tests/run_offline.lua` green after every phase
- [ ] Smoke test passes against REAL running QueryServer (:3030) and Editor (:3031) — the check the previous cycle never ran
- [ ] `cargo test` green in `SentinelQueryServer/` and `sentinel-questing/`
- [ ] No phantom APIs (zero `dbg.nearby` refs); no silent mock data in production paths; fixtures match server types
- [ ] Every archived F1–F20 requirement (minus deferred F5/F8/F21) verified in-game or explicitly re-deferred with user sign-off

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Offline suite gives false confidence again | High | Async-pending mock mode + real-server smoke gate as required criterion |
| Key-capture input infeasible via `core.input` | Med | Fallback: curated filter chips; decision point in design phase |
| query-types extensions ripple to other consumers | Med | `cargo test` both workspaces; grep consumers first |
| Graph/Properties phases overflow 400 lines | Med | Auto-chain into thinner slices |
| Baseline commits read as "working code" | Low | Label `baseline:`; remediation stacks immediately on top |

## Rollback Plan

Per-PR revert in reverse stack order. Full abort: reset to 99bb8d7 (pre-Phase-0 tip); the pre-Phase-0 working-tree snapshot (diff + untracked tar) restores the as-found state. No data migration; on-disk profiles untouched by any phase.

## Dependencies

- QueryServer (:3030) and Editor (:3031) running for smoke tests
- Sylvannas `core.input` + `core.object_manager` capabilities confirmed against `docs/SylvannasAPI/` during design
- Archived `02-spec.md` is the requirements baseline for the spec phase

## Proposal Question Round (auto-mode record)

Preflight resolved scope (fix + finish), design forks (search widget, object_manager scan, panels-win contracts), and delivery (force-chained, stacked-to-main). Assumptions open to user correction: (1) baseline commits exempt from the 400-line budget and review ceremony; (2) F4 remains list-fallback; (3) Rust extensions land in existing crates — no new crate.
