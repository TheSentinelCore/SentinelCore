# ADR 09 — Behavior Authoring Platform Architecture

Status: **Proposed**
Supersedes: ADR 03 (`03_EDITOR_AND_IMPORTER.md`)
Amends: ADR 01 §compile-before-execute; ADR 07 §profile schema

---

## 1. What this is

A **WoW-native behavior authoring platform**. Questing is its first plugin, not its subject.

The core knows `Graph`, `Node`, `Task`, `Condition`, `Variable`, `Overlay`. It does **not** know
what a quest is. Questing, gathering, professions, dungeons, and PvP each register task types into
a data-driven registry.

WoW-native is a deliberate scope decision. `map_id`, `entry`, `quest_id`, `faction`, `zone`, and
`spell_id` are **first-class primitives of the core**, not opaque values behind an abstraction.
There is no game-agnostic layer and no generality tax. The plugin seam is the *behavior domain*,
never the *game*.

The RestedXP import pipeline is retired. The separate compile step is removed.

---

## 2. Decision log

These answer the architectural review directly. Each records the reversal cost, because that —
not apparent profundity — is what decided the ordering.

| # | Question | Decision | Why |
| --- | --- | --- | --- |
| 1 | Graph or linear? | **Graph** | A graph subsumes a list; the reverse is impossible. Costs one runtime branch point (§6.2), not a rewrite. |
| 2 | Quest IDE or behavior platform? | **Platform** | Enforced by the schema-driven registry (§4). Without that enforcement the name is decoration. |
| 3 | Runtime overlays? | **Yes — already exists** | The save file is already an overlay. Formalize the concept, keep the mechanism (§7). |
| 4 | Composable profiles? | **Yes** | Falls out of stable IDs; a merge algorithm, not an architecture (§8). |
| 5 | QueryServer owns lowering? | **No — a library does** | Reversed from the previous draft. HTTP is one transport among CLI, CI, batch (§5). |
| 6 | IDs everywhere? | **Yes, unconditionally** | Cheapest now, most expensive to retrofit. Everything else depends on it (§3.1). |
| 7 | Undo from day one? | **Yes — already exists** | `editor/src/history.rs` has the Command pattern. Risk is losing it, not building it (§9). |
| 8 | Inheritance? | **Yes — same mechanism as #4** | Override layer over ID references (§8). |
| 9 | Simulation phase? | **Phase 1** | `_execute_dry_run` already exists. Edit-then-simulate is the compile loop. |
| 10 | AI as core concern? | **No — as a consequence** | IDs + preserved intent + structured events make it fall out. Designing for it now is guessing at prompts. |
| 11 | Multiplayer authoring? | **No** | The only item expensive *always* rather than expensive *later*. Git over stable IDs gets 90% at 2% (§10). |
| 12 | Observable execution? | **Yes — formalize the schema** | The structured log exists; a stable event contract is the cheap missing piece (§7.2). |
| 13 | Storage format? | **JSON — forced** | The Sylvannas sandbox has no JSON, `io`, or `load`. YAML means hand-writing a YAML parser in Lua. |
| 14 | Five-year goal? | **WoW automation platform** | Sets scope: WoW-native core, domain plugins. |

---

## 3. Core model

```
Campaign ──imports──▶ Campaign
    │
    └─▶ Graph
          ├─▶ Node ──▶ Task { type, intent, resolved }
          └─▶ Edge ──▶ { from, to, guard: Condition? }
```

A **linear route is a graph** where every node has exactly one unguarded outgoing edge. The retired
corpus shape is expressible without special-casing.

### 3.1 Identity

Every entity carries a stable, immutable `id` (UUIDv7 — sortable, so creation order survives
without a separate field): Campaign, Graph, Node, Edge, Task, Condition, Variable, Waypoint,
Diagnostic, ExecutionRun, and each emitted event.

IDs are assigned at creation and never reused or renumbered. This single rule is what makes
composition, inheritance, diffing, replay, AI reference, and mergeable git history possible. It is
also the one decision on this list that cannot be retrofitted cheaply, which is why it is
non-negotiable rather than phased.

### 3.2 Two layers per node

```jsonc
{
  "id": "018f2c...",
  "type": "questing.AcceptQuest",
  "intent":   { "quest": { "ref": "quest:783", "label": "Kobold Camp Cleanup" },
                "from":  { "ref": "npc:823",   "label": "Deputy Willem" } },
  "resolved": {
    "actions": [
      { "type": "Travel",      "payload": { "position": { "map": 0, "world_x": -8933.4, "world_y": -136.4, "world_z": 83.2 }, "tolerance": 5.0 } },
      { "type": "AcceptQuest", "payload": { "quest_id": 783, "npc_entry": 823 } }
    ],
    "resolved_at": "2026-07-26T14:00:00Z",
    "db_fingerprint": "tbcmangos@a1b2c3",
    "resolver_version": "1.0.0"
  }
}
```

`intent` is the source of truth. `resolved` is derived state. **Any conflict re-resolves.**

References are `{ ref, label }` — the `ref` is authoritative, the `label` is a cached display string
so the IDE and `git diff` stay readable without a database round-trip.

| Consumer | Reads |
| --- | --- |
| Lua runtime | `resolved.actions` only |
| IDE display | `intent` |
| Re-resolve / migrate / diff | `intent` |

`db_fingerprint` + `resolver_version` make staleness detectable: a DB or resolver update flags every
node resolved against the old one, and bulk re-resolution is a diffable operation.

---

## 4. The task registry (the platform seam)

A task type is **data**, registered by a domain plugin:

```
TaskType {
  type:     "questing.AcceptQuest"      -- namespaced by domain
  schema:   [ Field { name, kind, entity_type?, required, validation } ]
  lower:    fn(intent, db) -> [Action]  -- pure
  validate: fn(intent, ctx) -> [Diagnostic]
}
```

`Field.kind` drives the IDE widget; `entity_type` drives autocomplete (`npc`, `quest`, `item`,
`object`, `area`, `spell`).

Two rules make this a platform rather than a slogan:

1. **The Properties panel is schema-driven.** It renders widgets from `schema`. Hand-coding a
   Properties panel per task type builds a quest editor permanently, whatever this document is
   called. This is the enforcement point for §2 decision 2.
2. **A task lowers only to existing Action types.** A task needing a *new* Action is a runtime
   change with its own review — it does not arrive through the editor.

Questing registers the first set (`AcceptQuest`, `TurnIn`, `Kill`, `Collect`, `Vendor`, `Trainer`,
`Flight`, `Hearth`, `Gate`, `Travel`), chosen to cover the 48 dropped RestedXP verbs — the real
coverage target. Later domains register their own without touching the core.

---

## 5. Resolution is a library

```
                   ┌──────────────────────┐
                   │ sentinel-resolver    │  intent + DB ─▶ actions + diagnostics
                   │ (pure, offline)      │  PURE: same intent + fingerprint ⇒ byte-identical
                   └───────┬──────────────┘
        ┌──────────────────┼──────────────────┬─────────────────┐
        ▼                  ▼                  ▼                 ▼
   QueryServer          CLI                 CI              batch / AI
   (HTTP /resolve)   (headless)         (regression)      (generation)
        │
        ▼  core.http_post
   Quest IDE (in-game Lua)
```

Reversed from the previous draft. Lowering in an HTTP handler was reasoning from where the DB
connection happened to live. As a crate it is usable headless, testable offline, and callable from
CI and batch generation without a server.

The in-game IDE reaches it over HTTP because the Sylvannas sandbox has no other option. **HTTP is a
transport, not the home of the logic.**

Purity is a hard requirement: same `intent` + same `db_fingerprint` ⇒ byte-identical `resolved`.
That is what makes re-resolution diffable and the whole pipeline testable without a client.

### 5.1 QueryServer additions

Existing: `/quests/search` `/quest/:id` `/npc/search` `/npc/:entry` `/vendor/:entry`
`/trainer/:entry` `/flight/:entry` `/object/:entry` `/item/:item` `/item/:item/sources`
`/creatures/polygon` `/validate` `/travel/estimate`

Needed:

- `/search?q=` — federated fuzzy search across npc/quest/item/object/area, typed results. The
  Smart Search backend.
- `/spawns/:type/:entry` — spawn points for an entry. **This is where `world_z` finally comes
  from**: mangos `creature.position_z` is real ground height, which guide text never carried and
  which left 100% of 38,726 imported Travel positions at `world_z = 0`.
- `/resolve` — batch intent → resolved + diagnostics. Thin wrapper over the crate.

---

## 6. Execution

### 6.1 The runtime is not rebuilt

The measured failures were reading guide text (13,645 dropped directives from 48 verbs) and ground
height (100% `world_z = 0`). Neither is in the runtime, which carries 0 unresolved references
across 107,399 actions and 1,152 green offline cases. Its Action vocabulary is the stable contract
this platform targets.

### 6.2 What graph execution costs

Exactly one branch point. Today:

```lua
-- runtime_profile.lua:2355
elseif op.next_condition == "conditional" and op.condition_id then
    -- For now, advance sequentially. Full conditional branching needs
    -- the editor's condition evaluation integration.
    self._current_operation_idx = self._current_operation_idx + 1
```

The resolver emits an **execution plan**: nodes in topological order with outgoing edge guards
attached. At each node boundary the runtime evaluates outgoing edges to select the next node
instead of incrementing. Unguarded single-edge nodes behave exactly as today.

Route reconciliation is unaffected — it already re-derives position from live quest flags at every
boundary, which is dynamic re-planning the graph model makes explicit rather than replaces.

---

## 7. Overlays and observability

### 7.1 Overlay (already running)

`Profile + Overlay = Execution`. The overlay is already implemented as the save file beside the
profile: `known_flight_paths`, `visited_vendors`, `temporary_variables`, `variables`,
`completed_quests`, and route position. Skips, learned flight paths, deaths, and server events
write there. **The profile is an immutable artifact at runtime.** This ADR names the concept; the
mechanism ships today.

### 7.2 Event contract

The execution log already emits structured entries with `seq`, `event`, `operation`, `state`, and
`timestamp`, ring-buffered at 500. The missing piece is a **stable, versioned event schema** with
`run_id` and `node_id` on every entry.

That contract is cheap now and is the substrate for the debugger, timeline, replay, regression
testing, and analytics. Build the contract in phase 1; build the tooling whenever.

---

## 8. Composition and inheritance

One mechanism, two uses. A campaign imports others and applies an override layer keyed by stable
ID:

```
Campaign "Human Paladin Speedrun"
  imports  Alliance 1-60          (base graphs)
  imports  Combat Defaults, Vendor Rules, Flight Rules
  overrides node:018f2c...        (kill count 10 → 8)
  disables node:018f3a...         (skip elite quest)
```

Overrides never mutate the imported source. Resolution flattens imports into one execution plan,
so the runtime still receives a single resolved graph and gains no new capability.

This is what makes AI-generated *small reusable modules* viable instead of monolithic 1-60 guides.

---

## 9. The IDE

Panels map to primitives verified live against the running client. `ui-menu.md` is incomplete —
`core.menu.text_input` and `combobox_reorderable` exist but are undocumented, and `TEXT_INPUT`
appears only as enum value 10 with no documented constructor. **Probe the client before concluding
a capability is missing.**

| Need | Primitive | Status |
| --- | --- | --- |
| Search box | `core.menu.text_input` → `render`/`get_text`/`set` | undocumented, verified |
| Reorder nodes | `core.menu.combobox_reorderable` | undocumented, verified |
| Autocomplete | `core.menu.combobox` | documented |
| Explorer tree | `tree_node`, `begin_tree`/`end_tree` | documented |
| Panels | `core.menu.window` | documented |
| Properties widgets | `checkbox`, `slider_int/float`, `button`, `color_picker`, `label`, `separator` | documented |
| Graph / map canvas | `core.graphics.*` 2D primitives | documented |
| Click-in-world | `core.graphics.get_cursor_world_position` | documented |

Constraints: windows and menu elements are created in the **tick** callback, never in render. The
menu layer is immediate-mode, so IDE state lives in a plain Lua model and the render layer stays a
pure projection — the same split that makes `runner_state.lua` testable offline. **No decision
logic in the render layer.**

Undo is not new work: `editor/src/history.rs` already implements `CommandHistory` with
`can_undo`/`can_redo`/descriptions. Every IDE mutation goes through a Command. The risk is dropping
this while moving authoring in-game.

Editing needs QueryServer on `127.0.0.1:3030`. **Running a profile does not** — profiles are fully
resolved. That asymmetry is the payoff of resolve-at-author-time.

---

## 10. Explicitly rejected

**Multiplayer authoring.** The only reviewed item that is expensive *always* rather than expensive
*later*: CRDTs or OT, presence, a server owning document state, and every mutation path rewritten
to commute. It would dominate the project. Routes are authored by one person, and git over stable
IDs already gives mergeable profiles and asynchronous collaboration — most of the value at a
fraction of the cost. Revisit only if concurrent editing becomes a demonstrated need.

**Runtime name resolution.** The sandbox has no database; every lookup would become an HTTP
round-trip mid-route, trading compile-time diagnostics for network failures on a moving character.

**A game-agnostic core.** Ruled out by decision 14. WoW primitives are core types.

---

## 11. Phasing

Phase 1 is deliberately headless — every deliverable is offline-testable, which de-risks the UI
before any UI exists.

| Phase | Deliverable | Proves |
| --- | --- | --- |
| 1 | Core model (graph, IDs, intent/resolved); `sentinel-resolver` crate; task registry + questing plugin; QueryServer `/search` `/spawns` `/resolve`; **Recording Mode**; simulation; event contract | Content can be produced and verified with no client and no UI |
| 2 | IDE shell: window, Explorer, schema-driven Properties, Database Browser | The authoring loop closes |
| 3 | Graph canvas with reorder and edge guards; live validation via `/validate` | Graphs are editable, not just representable |
| 4 | Map canvas, click-to-place, Route Assistant | Coordinates disappear |
| 5 | Live Debugger, timeline, replay, diff viewer | Built on the phase-1 event contract |

### 11.1 The content risk

Retiring the importer removes the only bulk content source; the retired corpus was 107,399 actions.
Nobody hand-types `Human 1-60`.

**Recording Mode is therefore the content pipeline, not a feature**, which is why it is in phase 1.
It observes real play through the existing event surface and emits **Tasks, never waypoints**;
movement is regenerated by NavServer at resolve time. That is also why it sidesteps `world_z`
entirely. A human plays a zone once, the platform produces a first-draft graph, the author repairs
it.

---

## 12. Open items

1. **Retired corpus.** 43 MB of compiled profiles and 127 MB of `projects_old_duplicated` remain
   uncommitted. Recommendation: do not commit — git history is permanent and these are generated
   artifacts of a retired pipeline. Archive outside the repo if wanted.
2. **Crates.** Retire `sentinel-importer`. Retire `sentinel-compiler` (logic moves to
   `sentinel-resolver`). **Keep `sentinel-validator`'s rules**, rehost them as the live-validation
   engine behind `/validate`.
3. **Taxi data.** `taxi_nodes`/`taxi_path` are absent from `tbcmangos.sqlite` (mangos keeps taxi in
   DBC). `sentinel/tools/regen_taxi_nodes_catalog.py` exists — confirm coverage of the 727 Flight
   and 189 LearnFlightPath cases before `Flight` tasks can resolve.
4. **Graph UX for linear content.** A 300-node linear zone route is unpleasant as a node canvas.
   The Explorer list stays the primary view for linear stretches; the canvas is for branches.
