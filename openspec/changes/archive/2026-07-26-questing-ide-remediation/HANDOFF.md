# Handoff: questing-ide-remediation

**Written 2026-07-26.** Nine of twelve PR slices are merged to `master`. This document exists
because several load-bearing facts below are **not derivable from the repo** — they came out of
implementation and would otherwise be re-discovered the hard way.

---

## 1. State

`master` carries four `--no-ff` merges, newest first:

| Merge | Brings | Verified |
|---|---|---|
| `e83b65c` | PR11 travel editor + stats dashboard | 2117/0 |
| `ac77e62` | PR9 Properties five context views | 2069/0 |
| `0dda14c` | PR1→PR2→PR3→PR6→PR7 (Lua chain) | 2024/0 |
| `848ef6d` | PR4→PR5 (Rust/data track) | 57/0 rust, 1871/0 lua |

Baseline before this work: `99bb8d7`, 1574/0.

**Current test baselines on `master`:**

```
luajit sentinel/tests/run_offline.lua              # from REPO ROOT → 2117 passed, 0 failed
                                                   # + 21 opaque suites, 21 ok
cd SentinelQueryServer && SENTINEL_DB=../tbcmangos.sqlite cargo test   # → 57 passed, 0 failed
cd SentinelQuesting && cargo test --workspace                         # → 699 passed, 0 failed
cd SentinelQuesting && cargo test -p sentinel-editor                  # → 57 passed, 0 failed
```

Only `luajit` exists — there is no `lua` binary. `fd`/`eza` are not installed; use `rg`/`bat`.

All `qir/*` branches are merged; none are pushed and no PR was ever opened. `qir/pr2a-async-slot`
and `qir/pr2b-panel-rearm` are review-only pointers into PR2's history.

---

## 2. What remains — PR8, PR10, PR12

Unticked tasks in `tasks.md`, by owner:

- **PR8 — tasks 3.14, 3.15.** The remaining stub dispatch branches (condition / inventory /
  add_as_kill). These now have a real `editor_client` to route through. PR9 deliberately shipped the
  *state mutation* for these and left the *persistence call* to PR8 — nothing currently reports a
  write it did not make, and that property must survive.
- **PR10 — tasks 3.18–3.22.** Database measured text, pending-detail fix, spawn scanner, grind
  generator on real `/spawns/nearby` data. Flagged in the original forecast as one of the two
  densest slices; expect to split.
- **PR12 — tasks 4.6, 4.7.** `scripts/smoke_questing_ide.sh` against live `:3030`/`:3031`, and
  running it. **This is the required gate before archive.**

---

## 3. NOTHING HAS BEEN RUN AGAINST A LIVE SERVER OR THE INJECTOR

Every number in this document is offline. Four separate slices deferred live confirmation:

1. **PR1** — the "query server unavailable" render with QueryServer actually down.
2. **PR6, task 3.2 (explicitly left unticked)** — `core.input.is_key_down(16)` and
   `window:block_input_capture()` are *undocumented but real*, proven only by reading
   `SentinelNavClient/lib/AstroUI.lua:2286-2454`. Both are reached behind a `type(...)=="function"`
   check plus `pcall`, and `fake_window` was deliberately **not** given `block_input_capture`, so
   the focus-gated fallback is what offline actually exercises. **The undocumented path has never
   run.**
3. **PR3** — selecting an NPC and confirming the inspector follows; walking in-world to confirm a
   committed waypoint lands at the player.
4. **PR11** — taxi segment behavior against the real server.

This repo has a documented precedent: a permissive fake passed **1,568 green tests** and then
crashed the shell every frame in the injector. Treat offline green as necessary, not sufficient.

---

## 4. Traps that will bite you

### 4.1 Wire shapes — three fields that look wrong if you guess

- **`VendorItem.price == 0` means an `ExtendedCost` currency** (honor / arena points / tokens) with
  no copper equivalent. Render **"special cost"**, never "free".
- **`QuestSummary.zone` is an empty string** when `quest_template.ZoneOrSort <= 0` — mangos
  overloads that column and a non-positive value is a *sort* bucket, not an area id. Render `—`;
  do not invent a zone.
- **`classification` has five values**: `normal | elite | rare elite | boss | rare`. `"rare elite"`
  is mangos `Rank 2` and decomposes into neither.
- `NpcDetail.level` is `creature_template.MinLevel` — a spawn range reports its **floor**. A level
  *range* is not expressible and needs a spec change.

### 4.2 A green suite does not prove your tests ran

Slicing a Lua test file can drop an `end`, nesting later `function test_*()` definitions inside an
earlier one. Nested functions are only defined at call time, so the runner never enumerates them:
**the suite reports `0 failed` while silently running fewer cases.** This happened in PR6 (5 cases
vanished). After any test-file split, check the `passed` delta against the number of `function test_*`
you expect to have added. Same family as the `cargo test` `ok`-only-grep trap — when aggregating
cargo output, match on `FAILED|^error|failures:|panicked`, never on `ok`.

### 4.3 Controls unreachable by construction

PR9 found two Properties controls where `reduce` accepted action ids that `build_plan` never
emitted. A later PR would have gone green wiring a button nothing could press. **Audit: feed every
id `build_plan` emits back through `reduce`.** Do not assert `#plan.items > 0`.

PR11 found the level above it: `StatsDashboard:compute` and `TravelEditorState:load_from_campaign`
were real code with **no caller at all**, covered by tests that called them directly — which is
exactly why nobody noticed.

### 4.4 The `graph` binding in `ide_panels.lua` is deliberately non-local

Resolved by hand during the PR11 merge. `local graph` is forward-declared so the selection
subscriber can close over it; the Graph binding then **assigns without `local`**. Re-declaring it
shadows the subscriber's binding and node selection silently never resolves. There is a comment at
the site saying so — keep it.

---

## 5. Known flake — do not chase it as a regression

`tests/modules/questing/test_recorder.test_generated_ids_are_uuid_shaped_and_unique` fails roughly
2 in 10 full runs. **Root cause: `sentinel/modules/questing/recorder.lua` seeds its private random
stream from `os.time()`, which has one-second resolution**, so two runs inside the same second draw
identical id sequences. Pre-existing, unrelated to this change, deliberately not fixed inside a
remediation slice. Fixing it is a legitimate standalone change.

---

## 6. Open decisions the maintainer still owes

1. **`MaxLevel` is not exposed.** Task 2.2 asked for it; `spec.md:220` gives `NpcDetail` only
   `level: u8`. Implementation followed the spec. A range needs a spec change.
2. **`QuestSummary` has no `faction`.** Task 3.4 asks for a fourth column Lua cannot satisfy. The
   row reads `result.faction` and renders `—`, so it lights up the moment the server carries it.
   Source would be `quest_template.RequiredRaces`.
3. **Vendor `ExtendedCost != 0` prices as 0** — the design raised this as an open question; it is
   now implemented *and* test-pinned that way.
4. **Campaign validation implements only `MISSING_ACCEPT`.** `handle_validate_campaign` previously
   returned an empty Vec unconditionally, which would have shipped a Validate button reporting every
   campaign clean forever. **V2–V11 are still owed** and nothing currently reports them clean.
5. **`questing.Loot` is drawable but not runnable when lowered from `collect`.** `execute_loot`
   reads `object_entry` as a *gameobject*; a collect-generated node carries the item id there plus a
   `source_creatures` list the runtime ignores. The compiler's `collect → Kill(loot=true)` lowering
   does not exist. It was added to the palette anyway on the reasoning that an undrawable node is one
   nobody can find or fix — the breakage is now visible instead of invisible.
6. **`DELETE .../nodes/{id}` and `DELETE .../campaigns/{name}` are unreachable from Lua.**
   `remove_node` is local-only and silently diverges from the server.
7. **`questing.Travel`'s intent carries no map**, so campaign-derived routes are refused rather than
   estimated. Captured waypoints do carry one. Adding `map` is a `graph_state.lua` change.
8. **The stats overlay's XP/duration/distance rows are fixed-constant heuristics** with no server
   source — numbers that look measured and are not. The honest source is `/spawns/nearby`'s
   `xp_reward`.

---

## 7. Conventions this change ran under

- **Budget**: 400 changed lines per PR, force-chained, stacked-to-main. One granted
  `size:exception` — PR5, at 1,595 authored lines (recorded in `tasks.md`). Generated catalog data
  is excluded from authored counts.
- **Split as you go, not retroactively.** PR2 breached at 742 and had to be split after the fact;
  every slice after it split at file-disjoint boundaries mid-flight and verified each staged tree in
  isolation.
- **Never `git add -A`.** 833 untracked files under `SentinelQuesting/.questing/` are imported
  project data, not source. `ide.PNG`/`ide2.PNG`/`ide3.PNG` are likewise excluded. Zero contamination
  across all merged commits — keep it that way.
- Conventional commits. No AI attribution in commit messages.
- `openspec/` artifacts must use **canonical filenames** (`proposal.md`, `specs/<cap>/spec.md`,
  `design.md`, `tasks.md`). Numbered names (`01-proposal.md`) make `gentle-ai sdd-status` report all
  four as missing and block apply, verify **and** archive.

---

## 8. Suggested next step

`sdd-apply` for **PR8** (tasks 3.14–3.15) — smallest remaining slice, and the editor client it needs
is already on `master`. Then PR10, then PR12. Run PR12 before any archive attempt; `sdd-archive`
requires a verify report and every task checkbox closed.
