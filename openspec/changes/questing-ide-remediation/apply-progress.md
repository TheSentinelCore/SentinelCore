# Apply Progress: questing-ide-remediation

**Mode**: Standard (strict_tdd false) | **Store**: hybrid | **Delivery**: force-chained, `stacked-to-main`
**Scope so far**: Phase 0 + PR1 (batch 1) + PR2 (batch 2) + PR3 (batch 3) + PR6 (batch 4, Lua/UI track). PR4/PR5 are the concurrent Rust track (`apply-progress-pr4.md` / `-pr5.md`); PR7–PR12 not started.
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

### PR2 — AsyncSlot primitive + pending-mock harness + per-panel re-arm — COMPLETE (4/4)

Branch `qir/pr2-async-slot` off `qir/pr1-query-client-wiring`, two commits.

| Task | Status |
|---|---|
| 1.4 | Done — `sentinel/ui/async_slot.lua` |
| 1.5 | Done for Explorer/Properties/Database; **Graph deferred to PR7** (see Deviations) |
| 1.6 | Done — `core.http_get` in the harness mock, holding the callback for `Mock.http.pending_ticks` |
| 1.7 | Done — one re-arm test per data panel, plus a 10-case slot suite |

| Commit | Subject |
|---|---|
| `20a5915` | feat(ui): add a poll-until-resolved slot and let the harness hold a request |
| `beb17e1` | fix(ui): poll every panel fetch until it resolves instead of once |

**The contract** (`ui/async_slot.lua`): `AsyncSlot.new({ label, owner, max_ticks = 120 })`,
`slot:poll(fn)` → `(status, data)` with status `ok | pending | failed | timeout`. `fn` returns
exactly what `QueryClient:_get` returns. Pending re-arms `owner._dirty` and holds `owner.loading`;
`ok` stores and clears; `failed`/`timeout` write `owner.error` naming the label and clear.
`slot:reset()` abandons a request whose selection was replaced, so the abandoned tick count cannot
expire the fetch that replaced it. A slot only clears an `owner.error` it wrote itself, so two slots
on one state fail independently.

### PR3 — Selection bus + `ctx.player_position` + mock-data sweep — COMPLETE (5/5)

Branch `qir/pr3-selection-bus` off `qir/pr2-async-slot`, two commits.

| Task | Status |
|---|---|
| 1.8 | Done — channel on `shell_state`, render-frame guard on `shell` |
| 1.9 | Done — Explorer/Graph/Database publish from `dispatch` |
| 1.10 | Done — read on the TICK, not in render (see Deviations) |
| 1.11 | Done — 8 cases, not the 2 the task named |
| 1.12 | Done — both fabricators deleted outright |

| Commit | Subject | Lines |
|---|---|---|
| `9c80e41` | feat(ui): route selections through the shell and give panels a position | 384 |
| `dab7e98` | fix(ui): stop the Database inventing scans and grind estimates | 159 |

**The channel** (`ui/shell_state.lua`): `publish_selection({panel_id, kind, id})` fans out to every
`on_selection(fn)` subscriber in registration order; `selection()` holds the last one and
`last_selection_error()` holds the last subscriber throw. It is CONTENT-FREE — the view-model does
not know what a `kind` means — which is what keeps rule 3 of `shell.lua` ("never name a panel")
alive. `ide_panels.install` is the one file allowed to know both ends, so the subscription that
reaches Properties and the focus-follow `activate` live there, not in the shell.

`Shell:publish_selection` adds the one thing the view-model cannot know: it refuses a render frame
(`_in_render`). Every subscriber does real work — `set_context` abandons an in-flight fetch and
re-arms the panel — and that is not allowed inside `register_on_render_window_callback`. The flag
clears through `pcall` around `window:begin` AND at the top of `on_tick`, so a frame that throws
cannot latch the bus shut for the rest of the session.

**The position**: `_poll_player_position()` on the tick, both ctxs carry it, nil-safe through two
pcalls.

### PR6 — `text_input` widget + Explorer search/authoring — COMPLETE except 3.2 (6/7)

Branch `qir/pr6-text-input-explorer` off `qir/pr3-selection-bus`, four commits.

| Task | Status |
|---|---|
| 3.1 | Done — split into `ui/text_input_state.lua` (view-model) + `widgets.lua::text_input` (projection) |
| 3.2 | **NOT DONE — blocked on the injector.** Both undocumented calls are reached behind a type check; both paths asserted offline; live confirmation still owed |
| 3.3 | Done — 34 cases across two suites |
| 3.4 | Done — debounce + `result_meta`; `faction` is absent from `QuestSummary` and renders "—" (see Issues) |
| 3.5 | Done |
| 3.6 | Done — five distinct failure reports, all returning false |
| 3.7 | Done |

**The widget**: Sylvannas has no text entry. ADR 09b §1 lists `text_input`, `ui-custom.md` does not,
and `widgets.lua::element_value` was already probing for an accessor that is never there — so the
Explorer's search box has been an untypeable rectangle since it was drawn. It now reads the keyboard
itself. Every decision that implies lives in `text_input_state`; the widget draws and forwards.

**The undocumented half**: `window:block_input_capture()` and `core.input.is_key_down(16)` are
reached through `type(...) == "function"` plus `pcall`. Absent, the field still types, the keys also
reach the game, and shift reads as not held — the focus-gated fallback the design names. Offline that
IS the default, because `fake_window` was deliberately not given `block_input_capture`; the injector
path is stubbed onto one window instance in the single test that needs it.

**The search**: the tick reads the buffer BEFORE the dirty gate, because typing happens in a render
callback that cannot schedule anything. The gate is the debounce, not `#results == 0` — the old
condition let a panel run exactly one search for its whole life.

**The authoring**: `add_to_profile`/`add_chain` build the subgraph in the view-model and write it
through `editor_client:add_nodes`. Both previously returned **ok** next to "(not yet implemented)".

## Work Unit Evidence — PR6

| Evidence | Value |
|---|---|
| Focused test command / result | `luajit sentinel/tests/run_offline.lua` from repo root — **1958 passed, 0 failed**, 21 opaque suites 21 ok / 0 failed. Pre-PR6 baseline was 1892/0; +66 = 34 text-input cases + 21 Explorer view-model cases + 11 binding cases. |
| Per-commit verification | Each of the four commits was staged and run in isolation before committing: `2c2654f` 1908/0, `ac6758a` 1926/0, `95a501b` 1946/0, `aa817f8` 1958/0. |
| Mutation check 1 (Escape) | Making Escape keep the edited buffer instead of restoring the committed value turns **1 case red** (1925/1): `test_escape_cancels_and_restores_the_prior_value`. The spec's second scenario is held by a test. |
| Mutation check 2 (debounce) | Replacing `search_due`'s elapsed-time comparison with `return true` turns **2 cases red** (1944/2): `test_the_debounce_holds_the_query_for_300ms` and `test_each_keystroke_restarts_the_debounce`. |
| Runtime harness | **Not run — and task 3.2 stays open because of it.** Requires the injector: click the search box, type, confirm characters appear and do NOT reach the game (block_input_capture), confirm shift capitalises (is_key_down), confirm Escape restores. No offline test can close this; the fallback path is what offline exercises. |
| Rollback boundary | Revert `aa817f8` to drop the wiring while keeping the view-model; revert `95a501b` to drop the Explorer half entirely; revert `ac6758a`+`2c2654f` to drop the widget. `ide_panels.lua` is touched only by the last commit. |
| Review budget | `2c2654f` = **428**, `ac6758a` = **373**, `95a501b` = **432**, `aa817f8` = **357**. Two commits are 7-8% over the 400 budget; both are one new module plus its suite, split as the work landed rather than after the fact. Flagged, not absorbed. |

## Files Changed (PR6)

| File | Action | What |
|---|---|---|
| `sentinel/ui/text_input_state.lua` | Created | Buffer, caret, `apply_key`/`apply_keys`, `collect(input)`, `view()` |
| `sentinel/ui/widgets.lua` | Modified | `Widgets.text_input` — the only widget with no stock element behind it |
| `sentinel/ui/panels/explorer_state.lua` | Modified | `search_input`, `sync_search_input`, `search_due`/`mark_search_served`, `result_meta`, `build_quest_subgraph`, `build_chain_subgraph`; the search rect replaced by a `text_input` plan item |
| `sentinel/ui/panels/explorer.lua` | Modified | `text_input` draw handler — the one widget answering with a table, mapped to `<id>_submit`/`<id>_cancel` |
| `sentinel/ui/ide_panels.lua` | Modified | Explorer binding takes `editor_client`/`campaign`/`now`; `_commit_nodes`; buffer sync before the dirty gate; debounced search; both authoring commands |
| `sentinel/tests/ui/test_text_input.lua` | Created | 21 view-model cases |
| `sentinel/tests/ui/test_text_input_widget.lua` | Created | 13 widget cases, both undocumented paths |
| `sentinel/tests/ui/test_explorer_panel.lua` | Modified | +21 cases: debounce, meta line, subgraph builders, new reduce ids |
| `sentinel/tests/ui/test_ide_panels.lua` | Modified | +11 cases: search seam, five authoring failure modes, placeholder audit |
| `sentinel/tests/ui/test_offline_loadable.lua` | Modified | `ui/text_input_state` added to the isolation list |
| `sentinel/tests/run_offline.lua` | Modified | Both new suites registered after `test_widgets` |

## Work Unit Evidence — PR3

| Evidence | Value |
|---|---|
| Focused test command / result | `luajit sentinel/tests/run_offline.lua` from repo root — **1892 passed, 0 failed**, 21 opaque suites 21 ok / 0 failed. Pre-PR3 baseline was 1883/0; +9 = 8 new shell cases + 4 new database cases − 3 replaced scan cases. |
| First commit verified alone | Detached worktree at `9c80e41`: **1891 passed, 0 failed**. The bus and the position stand without the mock sweep; the two commits are independent slices, not halves of one. |
| Mutation check 1 (bus) | Deleting `properties:state():set_context({...})` from the `on_selection` subscriber in `ide_panels.install` turns **2 cases red** (1890/2): `test_a_database_selection_drives_the_properties_inspector` and `test_the_explorer_and_graph_publish_their_own_kinds`. The RG scenario is held by a test, not by a comment. |
| Mutation check 2 (position) | Deleting `player_position = self._player_position` from `_draw_body`'s ctx turns **1 case red** (1891/1): `test_the_render_context_carries_the_players_position`. Note the tick-context case stays green under this mutation — the two supply paths are held independently, which is what lets PR11's `travel_add_waypoint` rely on the dispatch side. |
| Runtime harness | **Not run.** Requires the injector: select an NPC in the Database and confirm the inspector follows and the tab activates; walk in-world and confirm a committed waypoint lands at the player. The offline path drives the REAL `Shell` through `FakeWindow` with a swapped `core.object_manager`, but neither claim is confirmed in-game. Carried forward with PR1's outstanding confirmation. |
| Rollback boundary | Revert `dab7e98` to restore the mock fallbacks without touching the bus; revert `9c80e41` to drop the bus and the position without touching the Database. The two commits share no file. |
| Review budget | `9c80e41` = 359 additions + 25 deletions = **384**; `dab7e98` = 88 + 71 = **159**. Both under the 400 budget. The combined 543 was split at the file-disjoint boundary AS the work landed, not after the fact — PR2's lesson applied. |

## Work Unit Evidence — PR2

| Evidence | Value |
|---|---|
| Focused test command / result | `luajit sentinel/tests/run_offline.lua` from repo root — **1883 passed, 0 failed**, 21 opaque suites 21 ok / 0 failed. Pre-PR2 baseline was 1870/0; +13 = 10 slot cases + 3 panel re-arm cases. |
| First commit verified alone | Detached worktree at `20a5915`: **1880 passed, 0 failed**. The primitive plus its harness stands on its own without the panel routing. |
| Mutation check | Deleting `owner._dirty = true` from `AsyncSlot:poll`'s pending branch turns **5 cases red** (1878/5): `test_a_pending_fetch_re_arms_the_owner_and_leaves_it_loading`, `test_a_slot_driven_by_the_real_client_re_arms_then_resolves`, and one per data panel — explorer, properties, database. The re-arm is held by a test at both the unit and the seam level. |
| Runtime harness | **N/A by design** — the offline pending mock now reproduces the runtime fetch model (held callback, `(nil, true)` first answer). The in-game confirmation still outstanding from PR1 is unchanged. |
| Rollback boundary | Revert `beb17e1` to drop the panel routing while keeping the primitive; revert both to drop PR2 entirely. No file is shared with an unlanded slice. |
| Review budget | **742 changed lines — OVER the 400 budget.** `20a5915` = 435 (async_slot 128 + slot suite 208 + mock 95 + runner 4), `beb17e1` = 307. Split point is the commit boundary: branching at `20a5915` yields two reviewable PRs with zero rework. Flagged, not silently absorbed. |

## Work Unit Evidence — PR1

| Evidence | Value |
|---|---|
| Focused test command / result | `luajit sentinel/tests/run_offline.lua` from repo root — **1870 passed, 0 failed**, 21 opaque suites 21 ok / 0 failed. Baseline before PR1 was 1864 passed, 0 failed. |
| Per-commit baseline verification | Detached worktree at each commit: `99bb8d7`, `c4e99ab`, `b61ef8d`, `d6ea39d`, `b2f9a77`, `5e6ab47`, `48a396d` → `1574 passed, 0 failed` each; `b20c2f0` → `1864 passed, 0 failed`. |
| Mutation check | Deleting `query_client = _ide_query_client` from `main.lua` turns `test_main_installs_the_ide_panels_with_a_live_query_client` **red** (1869/1; suite otherwise green). The guard bites; it is not decoration. |
| Runtime harness | **Not run.** Requires launching the IDE in the injector with QueryServer down and confirming the "query server unavailable" render. The offline path is exercised through the real `Shell` + `FakeWindow`, but the in-game confirmation is outstanding. |
| Rollback boundary | PR1: revert `e2e8b4f` (5 files, none shared with a later slice). Phase 0: reset `master` to `99bb8d7` and restore from the scratchpad snapshot. |
| Review budget | PR1 diff = 271 additions + 10 deletions = **281 changed lines**, under the 400 budget. |

## Files Changed (PR3)

| File | Action | What |
|---|---|---|
| `sentinel/ui/shell_state.lua` | Modified | The selection channel: `on_selection`, `publish_selection`, `selection`, `last_selection_error` |
| `sentinel/ui/shell.lua` | Modified | Forwards the channel + `_in_render` refusal; `_poll_player_position` on the tick; both ctxs carry `player_position`; `window:begin` pcall'd so the guard cannot latch |
| `sentinel/ui/ide_panels.lua` | Modified | `publish_selection` helper; Explorer/Graph/Database dispatch publish; `install` subscribes once with focus-follow |
| `sentinel/ui/panels/database_state.lua` | Modified | `_mock_scan` + `_mock_grind_result` deleted; both absent-source paths now write `state.error` |
| `sentinel/tests/ui/test_shell_extensions.lua` | Modified | +8 cases across the bus and the position |
| `sentinel/tests/ui/test_database_panel.lua` | Modified | 3 fabrication tests replaced by real-source tests; +1 grind error case, +1 no-fabricator guard |

## Files Changed (PR2)

| File | Action | What |
|---|---|---|
| `sentinel/ui/async_slot.lua` | Created | The poll-until-resolved primitive |
| `sentinel/tests/harness/mocks/sylvannas_api.lua` | Modified | `core.http_get` with the live async signature, held callbacks, `Mock.http_advance`, `set_http_response`, `reset_http` |
| `sentinel/tests/ui/test_async_slot.lua` | Created | 10 cases: slot contract + real `QueryClient` over the new mock |
| `sentinel/tests/run_offline.lua` | Modified | Registers the slot suite BEFORE the panels |
| `sentinel/ui/ide_panels.lua` | Modified | Explorer (detail/chain/objectives/search) and Properties (npc/vendor/object) fetches routed through slots |
| `sentinel/ui/panels/explorer_state.lua` | Modified | `_slots` + reset on `select` |
| `sentinel/ui/panels/properties_state.lua` | Modified | `_slots.detail` + reset on `set_context` |
| `sentinel/ui/panels/database_state.lua` | Modified | `_slots` + `execute_scan`/`execute_load_detail`/`execute_grind` gated on resolution |
| `sentinel/tests/ui/test_ide_panels.lua` | Modified | +3 re-arm cases, one per data panel |

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
5. **PR2: Graph excluded from task 1.5's "all four data bindings".** The Graph binding issues no fetch — its `on_tick` dirty branch is `-- In a real deployment, this would refresh from /editor/campaigns/{name}` — and `new_graph` takes no client at all. A slot with nothing behind it cannot be held honest by any test, and PR7 (task 3.9) is where the editor client and the campaign lifecycle arrive together. The three query-server panels are fully routed.
6. **PR2: `owner` is a `new()` option, not a `poll()` argument.** Design pins `AsyncSlot.new({label, max_ticks=120})` and `slot:poll(fn)`. The slot must reach the owner's `_dirty` to re-arm it, so the owner is passed in the same options table rather than widening `poll`'s signature, which keeps the design's call shape exactly.
7. **PR2: `poll` returns a status, not just data.** The design says "on data it stores + clears". A slot that only returned data could not tell a caller apart from `pending` and `failed` — and the Database needs that distinction, because "Entry N not found" is only correct for `failed`. `slot.data` still caches the value.
8. **PR2: over the review budget.** 742 changed lines against a 400 budget. The unit is a primitive plus its only consumers; a primitive with no call sites is not independently reviewable, so the split was made at the commit boundary instead (see PR2 evidence).
9. **PR3: the player position is read on the TICK, not in the render callback.** The spec says `ctx.player_position` is read "each frame" and the design's data-flow line repeats it. Doing that literally would put an object-manager read inside `register_on_render_window_callback`, which `shell.lua`'s own `_poll_combat` names as forbidden ("Read in TICK context, never on the render path", ADR 09b §2.4). The reading is refreshed on the tick that precedes the frame and handed to render from cache — the same arrangement every other SDK reading in this file uses. The spec's requirement ("the render `ctx` MUST include `ctx.player_position`") is met exactly; only the sampling site differs, at a cost of one tick of lag.
10. **PR3: the channel lives on `shell_state`, not `shell`.** Task 1.8 names both files. Subscriber bookkeeping is decision logic and belongs on the testable side of ADR 09b §2.1; `shell.lua` forwards it like every other verb. The one piece that had to stay on `shell` is the render-frame refusal, because the view-model has no idea when a frame is being painted.
11. **PR3: an extra guard the task did not ask for — `publish_selection` refuses a render frame.** Panels are supposed to return a command and let the tick dispatch it, but nothing enforced that for the new channel, and a subscriber runs `set_context`, which abandons an in-flight fetch. Without the guard the bus would be a fresh way to reintroduce exactly the render-side side effect this cycle exists to remove. It is held by a test that also proves the guard does not latch shut.
12. **PR3: `window:begin` is now pcall'd and re-raised.** Required by the guard above: `main.lua` pcalls the whole shell render, so a frame that threw would have left `_in_render` true and disabled the selection bus for the rest of the session. The error is re-raised, not swallowed — `main.lua` still reports it.
13. **PR3: `view_detail` publishes too.** Task 1.9 names `select_entry`/"Open in NPC Inspector". There is no button by that name; the Database's "View NPC Detail" button is it. Both action ids land on the same selection.
14. **PR6: the widget was split into two files.** Task 3.1 names only `widgets.lua`. Everything the control DECIDES — which key inserts, what Escape restores, where the caret is — would then live inside a render callback, which ADR 09b §2.1 and this repo's own panel convention both forbid precisely because no offline test can reach it. `ui/text_input_state.lua` holds the decisions; `widgets.lua` holds the projection and keeps the "a widget remembers nothing" contract in its own header.
15. **PR6: the debounce is expressed in SECONDS.** Tasks say 300ms. `ide_panels.lua::default_clock` reads `core.time()` and every existing interval in that file (`VIEW_INTERVAL_S`, `PROFILE_INTERVAL_S`) is in seconds. `SEARCH_DEBOUNCE_S = 0.30` is the same 300ms in the unit the clock actually answers in; mixing units here is how a 300ms wait becomes a 300s one.
16. **PR6: `search_due` stays true for the whole in-flight fetch.** The obvious reading of "debounce then fire" closes the gate when the request goes out. That would starve `AsyncSlot`'s pending re-arm of the tick that collects the answer — PR2's freeze, reintroduced through a new door. The gate is cleared by `mark_search_served` on resolution instead.
17. **PR6: a `collect` objective lowers to `questing.Loot`, not `questing.Kill`.** The spec's scenario names `Loot(789,5)` for an objective whose item drops from creature 567. The node carries `source_creatures` so the compiler can lower it to a Kill-with-loot without a second lookup. These are authoring nodes a human reviews before compiling (F3-R4/R6), not runtime actions — but see Issues: `questing.Loot` is missing from the Graph palette.
18. **PR6: the Explorer binding takes a `campaign` resolver.** Task 3.6 says "POST via editor client" and names no campaign. The campaign is owned by the Graph panel and changes underneath the Explorer, so it is resolved per call rather than captured. With none open the write is refused by name — there is genuinely nowhere to put the nodes until PR7 lands the lifecycle.

## Issues Found

- **B3–B6 per-commit greenness is vacuous.** The suite holds flat at 1574 across B3–B6 and jumps to 1864 only at B7, because `run_offline.lua` — which registers the new suites — is itself part of B7. Those four commits prove loadability, not coverage. Real, and consistent with the design's orphan-module plan, but it should not be read as four independently verified slices.
- **`PropertiesState:build()` could not report any error before a selection existed.** See Deviation 3. Latent bug found by the new test, fixed here.
- Task 1.1 and task 3.8 are ordered inconsistently in `tasks.md`. Recorded above.
- **PR2: the harness had no `core.http_get` at all.** Confirmed by reading the mock, not inferred. Every offline suite therefore exercised only `QueryClient:_get`'s synchronous-mock fallback; the `(nil, true)` branch the injector always takes first was unreachable dead code. That is the mechanical reason a green suite shipped panels that froze in-game, and it is now closed at the harness, not only at the call sites.
- **PR2: `DatabaseState:execute_grind(nil)` still fabricates a mock result.** Left as-is — task 1.12 (PR3) owns the mock-data sweep, and PR1 already made that branch unreachable from the installed panel by dropping `_pending_grind` when the client is absent.
- **PR2: the Properties inspector could be left spinning on a context nothing fetches.** `set_context` sets `loading = true` for every context kind, but only npc/vendor/object issue a request; node/condition/inventory contexts fell through the `if` chain with `loading` still true. Fixed with an explicit `else` that clears it.

- **PR3: `PropertiesState:set_context` is now reachable for kinds it cannot fetch.** The bus publishes `kind="quest"` and `kind="node"`, and the Properties tick has no branch for either — they fall to the `else` that clears `loading` (added in PR2). The inspector therefore switches context and renders its no-data view rather than spinning. Correct for now; task 3.16 (PR9) is where node/condition/inventory views arrive, and quest is not one of the five spec'd views at all. Flagged so PR9 does not assume the bus only ever sends fetchable kinds.
- **PR3: the two position supply paths are held independently.** Mutating the render ctx leaves the tick-ctx test green and vice versa. That is deliberate — PR11's `travel_add_waypoint` reads the DISPATCH side — but it means neither test alone proves the field is wired.

- **PR6: `QuestSummary` has no `faction` field.** Task 3.4 requires result rows to render "name/level/zone/faction". Verified against `git show qir/pr4-rust-types:SentinelQuesting/query-types/src/lib.rs`: `QuestSummary` is `{ id, title, level, min_level, zone }`, and `QuestDetail` has no faction either — the field lives on `NpcSummary`/`NpcDetail`. The row READS `result.faction` and renders "—" when absent, so it lights up the moment the server carries it, but the requirement is not satisfiable from the Lua side. **Rust-track follow-up**: `quest_template.RequiredRaces` is the source, and the field would need `#[serde(default)]` like the others.
- **PR6: `questing.Loot` is missing from the Graph palette.** `runtime_action.lua:329` dispatches `Loot` to `execute_loot`, and the compiler emits it, but `graph_state.lua::NODE_TYPES` lists 19 types and Loot is not among them. `add_to_profile` therefore generates a node the Graph panel cannot draw an icon or a default intent for. Not fixed here — NODE_TYPES is the Graph panel's, and touching it from PR6 would put a Graph change in an Explorer slice. **PR7/PR8 follow-up.**
- **PR6: the `Loot` intent shape is a compiler contract, not a runtime one.** `execute_loot` reads `{ object_entry, item_id }` and treats `object_entry` as a gameobject. A `collect` node carries the ITEM in both fields plus `source_creatures`, which is correct for authoring and wrong if compiled verbatim. The lowering (collect + source_creatures → Kill with `loot = true`) does not exist yet. Flagged loudly because a node that looks executable and is not is exactly this change's recurring defect.
- **PR6: two commits are over the 400-line budget.** 428 and 432, against 400. Each is one new module plus the suite that holds it; a module with no tests and tests with no module are both worse review units than an 8% overage. The split was made as the work landed, per PR3's lesson, not retrofitted.

## Remaining

Phase 2 (PR4, PR5 — concurrent Rust track), Phase 3 (PR7–PR10), Phase 4 (PR11, PR12), plus the
in-game confirmation owed by task 3.2. The Lua/UI track stopped at PR6 by instruction.

## Chain State

- `master` → `b20c2f0` (baseline) then `6bb1f69` (SDD artifacts)
- `qir/pr1-query-client-wiring` → `e2e8b4f`, `8bf2fbe`
- `qir/pr2-async-slot` → `20a5915`, `beb17e1`, `dcfccfe`, branched off `qir/pr1-query-client-wiring` per `stacked-to-main`
- `qir/pr3-selection-bus` → `9c80e41`, `dab7e98`, `eeb47b3`, branched off `qir/pr2-async-slot`
- `qir/pr6-text-input-explorer` → `2c2654f`, `ac6758a`, `95a501b`, `aa817f8` (+ this docs commit), branched off `qir/pr3-selection-bus`. PR6 precedes PR7 in the chain but follows PR3 on the branch, because PR4/PR5 are Rust-only and share no file with the Lua track.
- Concurrent Rust track in an isolated worktree: `qir/pr4-rust-types`, `qir/pr5-zone-catalog`. No file overlap with the Lua track.
- Nothing pushed. No PR opened.
- PR6 branches from `qir/pr3-selection-bus`.
