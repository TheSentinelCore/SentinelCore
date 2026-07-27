# Apply Progress — PR4 (Rust/data track)

**Change**: questing-ide-remediation | **Slice**: PR4 only | **Mode**: Standard (`strict_tdd: false`)
**Branch**: `qir/pr4-rust-types` (worktree `/home/levi/Projects/SentinelCore-worktrees/qir-rust-track`, based on `6bb1f69`)
**Delivery**: force-chained, stacked-to-main | **Date**: 2026-07-26

This file is PR4-only on purpose. The Lua/UI track writes `apply-progress.md`; the orchestrator merges.

## Completed Tasks

- [x] 2.1 [PR4] `query-types/src/lib.rs` — `QuestSummary.zone`, `NpcDetail += level/classification/loot/quests`, `VendorInfo.sells: Vec<VendorItem>`, plus `LootEntry`/`NpcQuestRef`/`VendorItem`
- [x] 2.2 [PR4] `SentinelQueryServer/src/db.rs` — extended `get_npc`, `get_vendor`, `search_quests`; new `zone_names.rs`
- [x] 2.3 [PR4] Ripple call sites updated
- [x] 2.4 [PR4] `cargo test` green in both workspaces

## Commits

| Hash | Subject |
|---|---|
| `65eebd9` | `feat(query): extend NpcDetail, QuestSummary and VendorInfo to what the panels render` |

## Files Changed

| File | Action | What |
|---|---|---|
| `SentinelQuesting/query-types/src/lib.rs` | Modified | 3 new DTOs; 6 new fields; `sells` retyped; `Default` derived on the 3 extended structs |
| `SentinelQueryServer/src/zone_names.rs` | Created | Generated `(area_id, name)` table (139 rows) + `zone_name()` + 3 tests |
| `SentinelQueryServer/src/db.rs` | Modified | `get_npc` loot/quest/rank joins, `get_vendor` item join, `search_quests` zone, `classification_from_rank`, 4 new tests |
| `SentinelQueryServer/src/main.rs` | Modified | `mod zone_names;` |
| `SentinelQuesting/queryclient/src/memory.rs` | Modified | `QuestSummary.zone` built explicitly |
| `SentinelQuesting/queryclient/tests/queryclient.rs` | Modified | 1 fixture |
| `SentinelQuesting/compiler/tests/kernel_combat_policy.rs` | Modified | 1 fixture |
| `SentinelQuesting/compiler/tests/kernel_worked_example.rs` | Modified | 1 fixture |
| `SentinelQuesting/importer/tests/importer.rs` | Modified | 4 fixtures |
| `SentinelQuesting/importer/tests/mapper.rs` | Modified | 5 fixtures |

## Consumer Ripple: predicted vs. found

The design listed 6 ripple files. Compiler-verified reality:

| Design predicted | Actually needed | Note |
|---|---|---|
| `compiler/tests/kernel_combat_policy.rs` | Yes (1 site) | |
| `compiler/tests/kernel_worked_example.rs` | Yes (1 site) | |
| `importer/tests/mapper.rs` | Yes (5 sites) | design said "1", there are 5 literals |
| `importer/tests/importer.rs` | Yes (4 sites) | design said "1", there are 4 literals |
| `queryclient/tests/queryclient.rs` | Yes (1 site) | `VendorInfo.sells: vec![]` needed no edit — empty vec retypes cleanly |
| `queryclient/src/memory.rs` | Yes (1 site) | `QuestSummary` build, as predicted |
| `importer/src/project_builder.rs` | **No** | `npc_from_detail` only *reads* `NpcDetail`; it constructs an `NPCReference`. Design overcounted. |
| — | `SentinelQueryServer/src/main.rs` | **not predicted** — new module declaration |

Nothing else in the tree constructs these three types; `queryclient/src/models.rs` re-exports `sentinel_query_types::*` by glob, so no export list needed touching. Lua readers of `sells` live in `sentinel/ui/**` (PR9, other track) and already expect objects.

## Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test command | `cd SentinelQueryServer && SENTINEL_DB=<repo>/tbcmangos.sqlite cargo test` → **44 passed, 0 failed**, exit 0 |
| Focused test command | `cd SentinelQuesting && cargo test --workspace` → **699 passed, 0 failed** across 58 suites, exit 0 |
| Failure-matched aggregation | `rg 'FAILED\|^error\|failures:\|panicked at'` over both logs → no matches (not an `ok`-only grep) |
| Runtime harness | N/A — Rust unit tests against the real `tbcmangos.sqlite` snapshot are the boundary; the live-server smoke gate is PR12 |
| Rollback boundary | `git revert 65eebd9`. Self-contained: no other PR depends on these types yet. |

New db.rs tests are pinned to real snapshot rows, not synthetic fixtures:
Hogger (448, elite, 30 loot rows, `-100.0` quest drop), Deputy Willem (823, normal, 5 starter + 2 finisher),
Coreiel (21474, 7 items, 2 `ExtendedCost`), quest 54 (`ZoneOrSort 9` → "Northshire Valley") vs quest 26 (`-263` → `""`).

## Review Budget

| Bucket | Lines |
|---|---|
| Tracked diff | 264 insertions + 10 deletions = 274 |
| `zone_names.rs` — authored (doc, lookup fn, tests) | 66 |
| `zone_names.rs` — generated data table | 139 (excluded per the guard's generated-golden rule) |
| **Authored total** | **340** — within the 400 budget |

Raw snapshot size is 479 lines. Flagging explicitly rather than letting it pass silently: the 139-row
table is mechanically derived from `AreaTable.dbc` and documented as generated, which is the guard's
stated exclusion. If the reviewer disagrees, the table is the natural split point.

## Deviations from Design

1. **`Default` derive + `..Default::default()` at fixture sites.** Design named the ripple files but not
   the edit form. Deriving `Default` on the three extended structs (wire-shape-neutral) and using
   `..Default::default()` in 12 of the 13 fixture literals keeps the diff about the fields the tests
   actually assert on. Production sites in `db.rs` remain fully explicit.
2. **`MaxLevel` is read but not exposed.** Task 2.2 names `MinLevel/MaxLevel/Rank`; the spec's field
   table (`spec.md:220`) gives `NpcDetail` only `level: u8`. Followed the spec: `level = MinLevel`, and
   `MaxLevel` is not selected at all rather than fetched and dropped. A level *range* needs a second
   field and a spec change.
3. **`classification` has 5 values, not 4.** Spec says "(normal/elite/rare/boss)"; mangos `Rank` also
   has `2 = rare elite`, which collapses to neither. Emitting `"rare elite"` rather than lying.
4. **`zone_names.rs` generator not committed.** The extraction is documented in the module header
   (DBC path, mangos fmt string, field indices) so it is reproducible, but PR5's
   `sentinel/tools/regen_zone_catalog.py` subsumes it and committing a throwaway generator now would
   be dead code in one PR's time. Called out so PR5 can fold the check in.

## Issues Found

- The design's ripple list undercounted `importer/tests/{mapper,importer}.rs` (1 file each, but 5 and 4
  literals) and overcounted `importer/src/project_builder.rs` (read-only consumer). The forecast hazard
  was real but caught at compile time, not CI — `cargo build --workspace --tests` surfaced every site.
- `SentinelQueryServer` tests default to `../tbcmangos.sqlite`, which does not exist in a worktree
  (the DB is gitignored and lives only in the primary checkout). `SENTINEL_DB` must be set to run them
  outside the main checkout. Pre-existing, not introduced here, but it will bite CI and PR5.
- Open design question "vendor `ExtendedCost != 0` items price as 0 — acceptable for v1?" is now
  implemented as `price: 0` and pinned by a test. Still awaiting the maintainer's answer; if the
  answer is no, the fix is one branch in `get_vendor` plus a new field.

## Remaining in this change

PR5–PR12 plus PR1–PR3 (Lua/UI track). Nothing in PR4 is outstanding.
