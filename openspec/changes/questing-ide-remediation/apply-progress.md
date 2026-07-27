# Apply Progress: questing-ide-remediation

**Mode**: Standard (strict_tdd false) | **Store**: hybrid | **Delivery**: force-chained, `stacked-to-main`
**Scope of this run**: Phase 0 (B5–B7) + PR1 only. PR2–PR12 not started.
**Base**: `99bb8d7` (pre-existing HEAD before any of this work)

## Completed

### Phase 0 — Baseline [P0] — COMPLETE (9/9)

Seven `baseline:` commits on `master`, landing pre-existing uncommitted work with no logic change.

| Task | Commit | Subject |
|---|---|---|
| 0.2 | `c4e99ab` | baseline: editor rust |
| 0.3 | `b61ef8d` | baseline: query layer |
| 0.4 | `d6ea39d` | baseline: explorer panel |
| 0.5 | `b2f9a77` | baseline: graph panel |
| 0.6 | `5e6ab47` | baseline: properties panel |
| 0.7 | `48a396d` | baseline: database panel |
| 0.8 | `b20c2f0` | baseline: shell extensions |
| — | `6bb1f69` | docs(sdd): land questing-ide-remediation artifacts and archive the prior cycle |

- **0.1** — snapshot written to the session scratchpad (`qir/pre-baseline.diff`, `qir/untracked.tar.gz`), NOT `.scratch/` in-repo. Snapshots must never enter the tree, and 833 of the 866 untracked files are `SentinelQuesting/.questing/` data.
- **0.9** — the suite was run at every one of the eight commits in a detached worktree, not just at the tip.

### PR1 — QueryClient wiring / contract / unavailable state — COMPLETE (3/3)

Branch `qir/pr1-query-client-wiring` off `master`, one commit `e2e8b4f`.

| Task | Status |
|---|---|
| 1.1 | Done for `query_client`; `editor_client` half deferred to PR7 (see Deviations) |
| 1.2 | Done |
| 1.3 | Done, plus a host-side guard the task did not ask for |

## Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test command / result | `luajit sentinel/tests/run_offline.lua` from repo root — **1870 passed, 0 failed**, 21 opaque suites 21 ok / 0 failed. Baseline before PR1 was 1864 passed, 0 failed. |
| Per-commit baseline verification | Detached worktree at each commit: `99bb8d7`, `c4e99ab`, `b61ef8d`, `d6ea39d`, `b2f9a77`, `5e6ab47`, `48a396d` → `1574 passed, 0 failed` each; `b20c2f0` → `1864 passed, 0 failed`. |
| Mutation check | Deleting `query_client = _ide_query_client` from `main.lua` turns `test_main_installs_the_ide_panels_with_a_live_query_client` **red** (1869/1; suite otherwise green). The guard bites; it is not decoration. |
| Runtime harness | **Not run.** Requires launching the IDE in the injector with QueryServer down and confirming the "query server unavailable" render. The offline path is exercised through the real `Shell` + `FakeWindow`, but the in-game confirmation is outstanding. |
| Rollback boundary | PR1: revert `e2e8b4f` (5 files, none shared with a later slice). Phase 0: reset `master` to `99bb8d7` and restore from the scratchpad snapshot. |
| Review budget | PR1 diff = 271 additions + 10 deletions = **281 changed lines**, under the 400 budget. |

## Files Changed (PR1)

| File | Action | What |
|---|---|---|
| `sentinel/main.lua` | Modified | Constructs one `QueryClient:new("127.0.0.1", 3030)` and passes it as `deps.query_client` |
| `sentinel/ui/ide_panels.lua` | Modified | `QUERY_SERVER_UNAVAILABLE` + `mark_query_client_unavailable`; three doc comments corrected; three `on_tick` nil-client branches |
| `sentinel/ui/panels/properties_state.lua` | Modified | No-context view carries `error`/`loading`; the empty state renders it |
| `sentinel/tests/ui/test_ide_panels.lua` | Modified | +5 cases covering the install seam |
| `sentinel/tests/test_main_diagnostics.lua` | Modified | +1 case: real `main.lua` loaded behind a spy on `IdePanels.install` |

## Deviations from Design

1. **`editor_client` deferred from PR1 to PR7.** Task 1.1 asks main.lua to construct an `EditorClient`; task 3.8 creates `sentinel/shared/editor_client.lua` in PR7. The module does not exist yet. Passing a `deps.editor_client` that resolves to nil, or a bare `QueryClient` at :3031 carrying none of `list_campaigns`/`load_campaign`/`validate`, would reproduce the silent-nil contract this whole change exists to delete. PR7 adds the main.lua line next to the module it needs.
2. **Database scan exempted from the unavailable gate.** The spec's unavailable state is about the query server. `execute_scan` reads the object manager, an unrelated source, so gating it on a missing HTTP client would be false. Its `_pending_detail`/`_pending_grind` ARE dropped, which also makes `_mock_grind_result` unreachable from the installed panel ahead of the PR3 mock-data sweep (task 1.12).
3. **`properties_state.lua` touched in PR1.** Not in the task text. Task 1.2's requirement ("panels MUST render an explicit unavailable state") was unsatisfiable for Properties without it: `build()` hard-coded `error = nil` whenever nothing was selected, and `build_plan`'s no-context branch returned before the error check. Found by the test in 1.3, which failed on Properties alone.
4. **Extra test file.** `test_main_diagnostics.lua` is outside task 1.3's named file. A test that only drives `IdePanels` cannot see the original defect, because the defect was in the caller.

## Issues Found

- **B3–B6 per-commit greenness is vacuous.** The suite holds flat at 1574 across B3–B6 and jumps to 1864 only at B7, because `run_offline.lua` — which registers the new suites — is itself part of B7. Those four commits prove loadability, not coverage. Real, and consistent with the design's orphan-module plan, but it should not be read as four independently verified slices.
- **`PropertiesState:build()` could not report any error before a selection existed.** See Deviation 3. Latent bug found by the new test, fixed here.
- Task 1.1 and task 3.8 are ordered inconsistently in `tasks.md`. Recorded above.

## Remaining

Phase 1 tasks 1.4–1.12 (PR2, PR3), Phase 2 (PR4, PR5), Phase 3 (PR6–PR10), Phase 4 (PR11, PR12). Nothing after PR1 was started.

## Chain State

- `master` → `b20c2f0` (baseline) then `6bb1f69` (SDD artifacts)
- `qir/pr1-query-client-wiring` → `e2e8b4f`, one commit ahead of `master`
- Nothing pushed. No PR opened.
- PR2 branches from `qir/pr1-query-client-wiring` per `stacked-to-main`.
