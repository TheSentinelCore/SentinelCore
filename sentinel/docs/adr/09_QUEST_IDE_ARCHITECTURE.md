# ADR 09 — Quest IDE Architecture

Status: **Proposed**
Supersedes: ADR 03 (`03_EDITOR_AND_IMPORTER.md`) — the importer half entirely, the editor half in
its HTTP-service form.
Amends: ADR 01 §compile-before-execute.

---

## 1. Decision

Questing authoring is rebuilt as an **in-game Quest IDE** backed by the mangos database. The
RestedXP import pipeline is retired. The separate compile step is removed: **the editor performs
resolution at author time.**

Three commitments follow from that, and everything else in this document is a consequence:

1. **The author works in intent.** `Travel → Marshal McBride`, never `map 0, x, y, tolerance`.
2. **The editor resolves, the runtime does not.** Names become entry IDs and coordinates the
   moment they are authored, not while the bot is running.
3. **The runtime is not rebuilt.** It is the part that works.

---

## 2. Why the runtime survives

The instinct to rebuild questing "from scratch" should stop at the authoring boundary. Measured
on the current corpus:

| Layer | Evidence |
| --- | --- |
| Reference resolution | 0 unresolved `quest_id`/`npc_entry` across 6,793 AcceptQuest + 7,362 TurnInQuest in 277 profiles |
| Runtime execution | 1,152 offline cases green; two live-caught defects fixed and pinned this cycle |
| Directive coverage | **13,645 dropped instances from 48 verbs** — 84% of all Comment actions |
| Coordinates | **100% of 38,726 Travel positions carry `world_z = 0`** |

The failures are concentrated in *reading guide text* and *ground height*. Neither lives in the
runtime. Rebuilding `runtime_profile.lua`, `runtime_action.lua`, navigation, combat handoff, and
the recovery state machine would discard the only components with a live-validated track record.

**The runtime's action vocabulary is therefore the stable contract.** The IDE targets it.

---

## 3. The central move: the editor *is* the compiler

Removing the compiler does not remove resolution — it relocates it to the only process that can
legally perform it.

```
OLD   guide text ─importer→ Project JSON (UUIDs) ─compiler→ Runtime Profile ─→ Lua runtime
NEW   Quest IDE (in-game, DB-backed) ───────────────────────→ Runtime Profile ─→ Lua runtime
```

This is non-negotiable and is why "resolve names at runtime" must be rejected: the Sylvannas
sandbox has no database, no sqlite, and no filesystem access beyond `core.read_data_file`. Every
runtime lookup would become an HTTP round-trip to QueryServer *mid-route*, trading compile-time
diagnostics for network failures on a moving character. CLAUDE.md already forbids it.

The editor has `core.http_get`/`core.http_post`. It resolves once, at author time, and bakes.

### 3.1 One file, two layers

Baking alone would destroy the two benefits that motivated semantic authoring in the first place:
readable version control and resilience to schema change. So a profile stores **both** layers in
the same document.

```jsonc
{
  "task": "AcceptQuest",
  "intent":   { "quest": "Kobold Camp Cleanup", "from": "Deputy Willem" },
  "resolved": {
    "actions": [
      { "type": "Travel",      "payload": { "position": { "map": 0, "world_x": -8933.4, "world_y": -136.4, "world_z": 83.2 }, "tolerance": 5.0 } },
      { "type": "AcceptQuest", "payload": { "quest_id": 783, "npc_entry": 823 } }
    ],
    "resolved_at": "2026-07-26T14:00:00Z",
    "db_fingerprint": "tbcmangos@a1b2c3"
  }
}
```

| Consumer | Reads | Never reads |
| --- | --- | --- |
| Lua runtime | `resolved.actions` | `intent` |
| IDE display / editing | `intent` | — |
| Re-resolve, diff, migrate | `intent` | — |

Consequences:

- The runtime stays exactly as dumb as it is today. No new capability, no HTTP, no DB.
- `git diff` shows `quest: Kobold Camp Cleanup → Wolves Across the Border`, not an integer churn.
- A DB update or schema change is handled by **re-resolving every task from `intent`** — a bulk
  operation the IDE can run and diff, not a hand migration.
- `db_fingerprint` makes staleness detectable: the IDE flags tasks resolved against an older DB.

**Rule: `resolved` is derived state. `intent` is the source of truth. Any conflict re-resolves.**

---

## 4. Task vocabulary and lowering

Authors manipulate **Tasks**. The runtime executes **Actions**. Lowering happens in the editor at
author time, alongside resolution.

```
Task: Quest/Accept "Kobold Camp Cleanup"
  ↓ lower + resolve
Action: Travel      { position: <Deputy Willem spawn>, tolerance: 5 }
Action: AcceptQuest { quest_id: 783, npc_entry: 823 }
```

Initial Task set — chosen to cover the 48 dropped RestedXP verbs, which is the real coverage
target:

| Task | Lowers to | Resolution source |
| --- | --- | --- |
| `Travel` | Travel | `creature`/`gameobject` spawn, POI, or explicit point |
| `Quest/Accept` | Travel + AcceptQuest | `creature_questrelation` |
| `Quest/TurnIn` | Travel + TurnInQuest | `creature_involvedrelation` |
| `Quest/Abandon` | AbandonQuest | — |
| `Combat/Kill` | Travel + Kill + Condition(ObjectiveComplete) | `creature` spawns for the entry |
| `Gather/Collect` | Travel + Kill/Loot/UseItem + Condition | `item_loot_template`, `/item/:id/sources` |
| `Vendor` | Travel + Vendor | `npc_vendor` |
| `Trainer` | Travel + Train | `npc_trainer` |
| `Flight` | Travel + Flight | taxi catalog (see §7.4) |
| `Hearth` / `Bind` | Hearth / SetHearth | innkeeper spawns |
| `Wait` / `Gate` | Condition | level / xp / reputation / money / item |
| `Custom` | verbatim Actions | escape hatch |

Two rules keep this honest:

- **A Task lowers to existing Action types only.** If a Task needs a new Action, that is a runtime
  change and gets its own review — it does not sneak in through the editor.
- **Lowering is pure.** Same intent + same DB fingerprint ⇒ byte-identical `resolved`. This makes
  re-resolution diffable and the whole pipeline testable offline.

---

## 5. Components

```
┌─────────────────────────────────────────────┐
│ Quest IDE            (Lua, in WoW client)   │  ← NEW
│  Explorer │ Graph │ Properties │ DB │ Runtime│
└───────┬─────────────────────────────┬───────┘
        │ core.http_get/post          │ core.write_data_file
        ▼                             ▼
┌──────────────────────┐      ┌──────────────────────┐
│ SentinelQueryServer  │      │ Profile JSON         │
│ (extended)           │      │ intent + resolved    │
│  tbcmangos.sqlite    │      └──────────┬───────────┘
└──────────────────────┘                 │
                                          ▼
                              ┌──────────────────────┐
                              │ Lua questing runtime │  ← UNCHANGED
                              │ + NavServer, combat  │
                              └──────────────────────┘
```

### 5.1 QueryServer is already most of the IntelliSense backend

Existing routes cover the majority of §2 "database-first":

```
/quests/search   /quest/:id      /npc/search    /npc/:entry
/vendor/:entry   /trainer/:entry /flight/:entry /object/:entry
/item/:item      /item/:item/sources           /creatures/polygon
/validate        /travel/estimate
```

Additions needed:

- `/search?q=` — one federated fuzzy endpoint across NPC / quest / item / object / area, returning
  typed results. This is the Smart Search backend.
- `/spawns/:type/:entry` — spawn points for an entry, so `Travel → Marshal McBride` can pick the
  nearest or the canonical spawn. **This is also where `world_z` finally comes from**: mangos
  `creature.position_z` is a real ground height, which is what the guide text never had.
- `/resolve` — batch: take N intents, return N resolved payloads plus diagnostics. Powers
  bulk re-resolution and keeps lowering server-side and testable.

### 5.2 The IDE panels map to verified primitives

Every panel in the proposal is buildable. Probed live against the running client:

| Need | Primitive | Status |
| --- | --- | --- |
| Search box (type a name) | `core.menu.text_input` → `render` / `get_text` / `set` | **undocumented, verified live** |
| Autocomplete list | `core.menu.combobox` | documented |
| Drag-to-reorder steps | `core.menu.combobox_reorderable` | **undocumented, verified live** |
| Explorer tree | `core.menu.tree_node`, `begin_tree`/`end_tree` | documented |
| Multi-panel IDE | `core.menu.window` | documented |
| Properties widgets | `checkbox`, `slider_int/float`, `button`, `color_picker`, `label`, `separator` | documented |
| Map canvas + markers | `core.graphics.*` 2D text/line/rect/circle/triangle | documented |
| Click-in-world to place | `core.graphics.get_cursor_world_position` | documented |
| Live runtime panel | existing blackboard + `runner_state.lua` view-model | exists |

**`ui-menu.md` is incomplete.** `text_input` appears only as enum value 10 in `enums.md` and has no
documented constructor, yet `core.menu.text_input`, `input_text`, `input_string`, and
`new_text_input` all exist. Probe the live client before concluding a capability is missing.

### 5.3 Constraints inherited from Sylvannas

- Windows and menu elements are created in the **tick** callback, never in a render callback.
- The menu layer is **immediate-mode**: panels re-render each frame. IDE state lives in a plain Lua
  model owned by the module; the render layer stays a pure projection of it — the same split that
  makes `runner_state.lua` testable offline today. Decision logic in the render layer is untestable
  and is not permitted.
- Editing requires QueryServer on `127.0.0.1:3030`. **Running a profile does not** — profiles are
  fully baked. This asymmetry is the payoff of resolve-at-author-time.

---

## 6. The content problem (the largest risk)

Retiring the importer removes the only bulk source of route content. The Explorer mockup says
`Human 1-60`; the retired corpus was **107,399 actions across 277 profiles**. Nobody is hand-typing
that.

**Therefore Recording Mode is not a feature — it is the content pipeline, and it is required in
phase 1, not phase 4.**

Intent recording, as proposed, is the right shape:

- The recorder observes real play through the existing event surface (quest accepted, turned in,
  vendor opened, trainer used, taxi taken, objective progressed) and emits **Tasks**, not waypoints.
- Movement is *not* recorded. It is regenerated by NavServer at resolve time. This is what makes
  recordings short, diffable, and immune to the `world_z = 0` problem.
- A human plays a zone once; the IDE produces a first-draft route; the author repairs it in the
  Graph/Properties panels.

Without this, the IDE is an excellent tool with no content to edit.

---

## 7. Open items

1. **Scope of "from scratch".** This ADR rebuilds authoring and keeps the runtime. Confirm.
2. **Retired corpus.** 43 MB of compiled profiles and 127 MB of `projects_old_duplicated` are
   uncommitted. Recommendation: do not commit — git history is permanent, and these are generated
   artifacts of a retired pipeline. Archive outside the repo if wanted for reference.
3. **Crates to retire.** `sentinel-importer` (delete), `sentinel-compiler` (delete — logic moves to
   QueryServer `/resolve`), `sentinel-validator` (**keep the rules, relocate the host** — they
   become the live-validation engine behind `/validate`).
4. **Taxi data.** `taxi_nodes` and `taxi_path` are absent from `tbcmangos.sqlite` (mangos keeps taxi
   in DBC). `sentinel/tools/regen_taxi_nodes_catalog.py` exists — confirm it covers the 727 Flight
   and 189 LearnFlightPath cases before `Flight` Tasks can resolve.
5. **Ground height.** `/spawns` returns real `position_z`, which fixes authored destinations. The
   runtime's `resolve_ground_z` fallback stays for waypoints that are still author-placed.

---

## 8. Phasing

| Phase | Deliverable | Proves |
| --- | --- | --- |
| 1 | Profile schema v3 (intent + resolved); QueryServer `/search`, `/spawns`, `/resolve`; **Recording Mode** | Content can be produced at all |
| 2 | IDE shell: window, Explorer, Properties, Database Browser + search | Authoring loop closes |
| 3 | Graph view with reorder; live validation surfacing `/validate` | Editing is pleasant |
| 4 | Map canvas, click-to-place, Route Assistant | Coordinates disappear |
| 5 | Scenario Simulator (seeded by existing `_execute_dry_run`), Live Debugger (seeded by the lx-debug bridge + 500-entry execution log), Diff viewer | Debugging surpasses existing tools |

Phase 5's two headline features are the closest to done — both already have working substrates.
