# Apply Progress — PR9 (Properties: the five context views)

**Change**: `questing-ide-remediation`
**Slice**: PR9 only (tasks 3.16, 3.17)
**Mode**: Standard (`strict_tdd: false`)
**Branch**: `qir/pr9-properties-views`, branched from `qir/pr3-selection-bus`
**Worktree**: `/home/levi/Projects/SentinelCore-worktrees/qir-rust-track`
**Delivery**: force-chained / stacked-to-main, 400 changed lines per commit
**Pushed**: no. **PR opened**: no.

> This file is separate from `apply-progress.md` on purpose: the PR6 agent owns that file
> concurrently in the main checkout.

## Commits

| # | SHA | Subject | +/- | Budget |
|---|-----|---------|-----|--------|
| 1 | `0b12bfe` | `feat(ui): read the NPC inspector off the server's field names` | 268/28 | 296 / 400 |
| 2 | `0aab834` | `fix(ui): make the vendor editor read VendorItem and reach its own toggle` | 161/27 | 188 / 400 |
| 3 | `daf64c6` | `fix(ui): stop the object view rendering fields the server never sends` | 76/14 | 90 / 400 |
| 4 | `ee3fc1e` | `feat(ui): add the node context view with validated payload edits` | 381/0 | 381 / 400 |
| 5 | `f8d0e54` | `feat(ui): hand the selected graph node to the inspector` | 65/1 | 66 / 400 |
| 6 | `eab707f` | `feat(ui): make the condition tree and inventory rules actually mutate` | 330/55 | 385 / 400 |

Every commit is under the 400-line budget. Commits 3–5 are the retroactive split of a single
493-line change, cut at the object/node/supply boundary before it was committed — PR3's discipline,
not PR2's.

## Files changed

| File | Action | What |
|---|---|---|
| `sentinel/ui/panels/properties_state.lua` | Modified | Server-shape projections, condition tree mutation, node payload validation, all five view branches |
| `sentinel/ui/ide_panels.lua` | Modified | Properties binding only: vendor rule state, node-edit dispatch, condition/inventory dispatch, node supply in `install`'s subscriber |
| `sentinel/tests/ui/test_properties_panel.lua` | Modified | Fixtures rewritten to the wire shape; +49 cases across sections 10–17 |
| `openspec/changes/questing-ide-remediation/tasks.md` | Modified | 3.16 / 3.17 ticked, with their deferrals recorded |

`sentinel/ui/widgets.lua` and `sentinel/ui/panels/explorer_state.lua` were NOT touched (PR6 owns
them). Nothing under `/home/levi/Projects/SentinelCore` was touched.

## Evidence

**Focused/full test command**: `luajit sentinel/tests/run_offline.lua` from the worktree root.

| Point | Result |
|---|---|
| Baseline on `qir/pr3-selection-bus` | 1892 passed, 0 failed (+21 opaque, 21 ok) |
| After PR9 | **1937 passed, 0 failed** (+21 opaque, 21 ok) |
| Delta | +45 cases, all new Properties coverage |

**Runtime harness**: N/A per the tasks artifact's work-unit table — "server-shaped fixtures cover
it". The extended `NpcDetail`/`VendorInfo` this consumes land in PR4, which is not in this branch's
ancestry, so a live `:3030` check is PR12's smoke script, not this unit's.

**Mutation proofs (both reverted, both re-verified green):**

| Mutation | Result |
|---|---|
| `vendor_rows` iterates `{}` instead of `info.sells` | **1905 passed, 4 failed** — row count, toggle-id round trip, painted name/price, local rule |
| `set_node(found)` replaced with a no-op in `install`'s subscriber | **1923 passed, 1 failed** — the node-supply test |

**Rollback boundary**: `git revert eab707f f8d0e54 ee3fc1e daf64c6 0aab834 0b12bfe`, or reset to
`eeb47b3`. Nothing outside the Properties panel, its tests, and the Properties-specific lines of
`ide_panels.lua` is touched.

## What each view now does

**npc** — `LootEntry.drop_chance` and `NpcQuestRef.quest_id` are read by their real names. The panel
had read `entry.chance` and `quest.id`, names no type on the wire has ever carried, so the loot and
quest tabs drew a section header and then nothing on every NPC. Loot groups into drop-chance
buckets; quests split into starter/finisher (an NPC that does both appears in both lists);
`classification` maps five ranks, with `rare elite` kept whole and an unknown rank passed through
rather than folded into "Normal"; `level` renders as "Level N (min)" because it is
`creature_template.MinLevel` and no range exists on the wire.

**vendor** — `sells` is read as `Vec<VendorItem{item_entry,name,price}>`. Rows are `list_row`s
carrying `vendor_toggle:<item_entry>`, so the per-item rule toggle is reachable for the first time
(`reduce` had understood that id since the panel was written and nothing ever emitted one). Price 0
renders as **"special cost"**, never "free": it is an `ExtendedCost` row with no copper equivalent.

**object** — `respawn` and `skill` deleted; they had no source on the wire and came from the panel's
own fixture. The single `WorldPos` renders as a spawn section. Object loot is not served and the
view says so rather than leaving a blank that reads as "empty".

**node** — new. Payload fields come from `graph_state`'s `default_intent` for the node's type (not a
copy that would drift), merged under the node's own `intent`, sorted by name so rows do not move
under the cursor. Edits are validated per keystroke against the field's declared kind; a `table`
field (a route, a spell list) is not editable from an inspector row. `commit_node_edit` returns the
change instead of writing it through.

**condition/inventory** — five dispatch branches that answered `true` with a placeholder string are
now real state mutations. Conditions became selectable rows (add/delete are meaningless without a
selection, so the tree could not have worked even once wired), `not`'s single child gained a row,
and every refusal is stated rather than guessed.

## Deviations and dependencies

1. **Task 3.17's "round-trips through the editor client" is HALF-DONE by design.**
   `sentinel/shared/editor_client.lua` is created in PR7 (task 3.8) and task 3.14 [PR8] explicitly
   owns wiring `add_condition:506`, `add_condition_group:508`, `delete_condition:510`,
   `add_inventory_rule:512` through it. PR9 delivers the state-side mutation and its coverage; PR8
   adds the persistence call. Nothing here reports a write it did not make.
2. **The vendor rule toggle is local.** Persisting it is PR7's `save_graph`.
3. **Merge order matters.** This Lua reads the PR4 field names (`drop_chance`, `quest_id`,
   `item_entry`, `classification`, `level`). PR4 MUST land before PR9 or the panel reads fields the
   server does not yet send. The branch is off PR3, not PR5, per the orchestrator's instruction.
4. **No `text_input` dependency was created.** `set_node_draft` is the seam PR6's widget feeds; the
   validation it feeds is here and testable without it.
5. **Object spawns/loot have no server source.** The spec's Properties requirement lists
   "object (type, spawns, loot if lootable)" but PR4 extends only `NpcDetail`, `VendorInfo` and
   `QuestSummary`. Rendering loot for objects needs an `ObjectInfo` extension that is not in any
   task. Flagged, not fabricated.
6. **`NpcDetail.level` cannot express a spawn range.** Labelled "(min)". A range needs a spec change.

## Pre-existing issue found (NOT PR9's, NOT fixed)

`tests/modules/questing/test_recorder.test_generated_ids_are_uuid_shaped_and_unique` fails
intermittently — observed twice in ~10 full runs, always alone, in a file PR9 does not touch.
`sentinel/modules/questing/recorder.lua` seeds its private random stream from `os.time()`, which has
one-second resolution, so two runs inside the same second draw the same id sequence and the
"never reused" assertion trips. Out of scope here; worth its own fix.

## Status

2/2 assigned tasks complete (3.16, 3.17). PR9 done. Remaining across the change: 2.x (PR4/PR5),
3.1–3.15 (PR6–PR8), 3.18–3.22 (PR10), 4.x (PR11/PR12).
