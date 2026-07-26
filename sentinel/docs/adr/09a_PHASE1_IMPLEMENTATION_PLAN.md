# ADR 09a — Phase 1 Implementation Plan

Companion to `09_BEHAVIOR_AUTHORING_PLATFORM.md`. Phase 1 is **headless**: every deliverable is
verifiable offline, with no WoW client and no UI.

---

## 1. The contract

Everything in this phase codes against the shapes below. They are fixed here so work units can
proceed in parallel without waiting on each other's types.

### 1.1 Identity

`uuid::Uuid` v7 (time-sortable). Assigned at creation, never reused, never renumbered. Serialized
as a lowercase hyphenated string.

### 1.2 Entity reference

Every pointer from authored intent to a game entity:

```jsonc
{ "ref": "npc:823", "label": "Deputy Willem" }
```

- `ref` — `<kind>:<id>`, authoritative. Kinds: `npc` `quest` `item` `object` `area` `spell` `map`.
- `label` — cached display string. Never authoritative; refreshed on resolve so `git diff` and the
  IDE read without a database round-trip.

### 1.3 Campaign / Graph / Node / Edge

```jsonc
{
  "schema_version": 3,
  "id": "018f...", "name": "Human 1-60",
  "imports": [ { "campaign": "018f...", "overrides": [], "disabled_nodes": [] } ],
  "variables": [ { "id": "018f...", "name": "hearth_set", "type": "bool", "default": false } ],
  "conditions": [ { "id": "018f...", "type": "LevelAtLeast", "payload": 10 } ],
  "graphs": [
    {
      "id": "018f...", "name": "Elwynn Forest",
      "entry_node": "018f...",
      "nodes": [
        {
          "id": "018f...",
          "type": "questing.AcceptQuest",
          "intent":   { "quest": { "ref": "quest:783", "label": "Kobold Camp Cleanup" },
                        "from":  { "ref": "npc:823",   "label": "Deputy Willem" } },
          "resolved": {
            "actions": [ { "type": "Travel", "payload": { } },
                         { "type": "AcceptQuest", "payload": { "quest_id": 783, "npc_entry": 823 } } ],
            "resolved_at": "2026-07-26T14:00:00Z",
            "db_fingerprint": "tbcmangos@a1b2c3",
            "resolver_version": "1.0.0"
          }
        }
      ],
      "edges": [ { "id": "018f...", "from": "018f...", "to": "018f...", "guard": null } ]
    }
  ]
}
```

**`intent` is the source of truth. `resolved` is derived. Any conflict re-resolves.**

A linear route is a graph where every node has exactly one outgoing edge with `guard: null`.
`guard` is a condition id when present.

### 1.4 Execution plan (resolver output → runtime input)

```jsonc
{
  "schema_version": 3,
  "campaign_id": "018f...", "graph_id": "018f...",
  "db_fingerprint": "tbcmangos@a1b2c3",
  "content_hash": "…",
  "operations": [
    { "node_id": "018f...", "actions": [ /* runtime Action objects, unchanged vocabulary */ ],
      "next": [ { "to_index": 4, "guard": null } ] }
  ]
}
```

`operations` are in topological order. `next` with a single `guard: null` entry is today's
sequential advance. The runtime's existing Action vocabulary is unchanged — this is the
**stable contract** and no work unit may extend it.

### 1.5 Event contract

Every runtime event:

```jsonc
{ "schema_version": 1, "seq": 42, "run_id": "018f...", "node_id": "018f...",
  "event": "action_success", "timestamp": 1204.83, "state": "running", "data": { } }
```

`run_id` is minted once per profile start. `node_id` is null for profile-scoped events.

---

## 2. Work units

Ownership is **disjoint by file** so units run concurrently without collision. A unit that needs a
file it does not own must stop and report rather than edit it.

| # | Unit | Owns | Depends on |
| --- | --- | --- | --- |
| W1 | Core model | `SentinelQuesting/shared/src/platform/**` | — |
| W2 | Resolver crate | `SentinelQuesting/resolver/**` | W1 |
| W3 | QueryServer search + spawns | `SentinelQueryServer/src/**` | — |
| W4 | Event contract | `sentinel/core/event_schema.lua`, `_log_event` in `runtime_profile.lua` | — |
| W5 | Recording Mode | `sentinel/modules/questing/recorder.lua` (new, additive only) | — |
| W6 | `/resolve` + simulation | `resolver` HTTP wiring, `_execute_dry_run` | W1, W2 |

Workspace `Cargo.toml` (member list, `uuid` v7 feature) is edited once up front, by nobody else.

### W1 — Core model
`sentinel-models::platform`: `Campaign`, `Graph`, `Node`, `Edge`, `EntityRef`, `Intent`,
`Resolved`, `ExecutionPlan`, `Variable`, `ConditionDef`. Serde round-trip tests against §1.
Adjacent tagging (`{type, payload}`) on every enum crossing into the runtime — externally-tagged
enums silently fail open in Lua (see `CLAUDE.md` known state).

### W2 — Resolver crate
`sentinel-resolver`: `TaskType { type, schema, lower, validate }` registry; the questing task set
(`AcceptQuest` `TurnIn` `Kill` `Collect` `Vendor` `Trainer` `Flight` `Hearth` `Gate` `Travel`);
`resolve(campaign, db) -> (ExecutionPlan, Vec<Diagnostic>)`. **Purity is a hard requirement**: same
intent + same `db_fingerprint` ⇒ byte-identical output. Test it explicitly.

### W3 — QueryServer search + spawns
- `GET /search?q=` — federated fuzzy across npc/quest/item/object/area, typed results, ranked.
- `GET /spawns/:type/:entry` — spawn points from `creature` / `gameobject`. **Returns real
  `position_z`.** This is the fix for 100% of 38,726 imported Travel positions carrying
  `world_z = 0`.

### W4 — Event contract
Versioned event schema with `run_id` and `node_id`. `_log_event` emits it; the ring buffer and
existing consumers (`runner_state.lua`, save file) keep working. Pure addition — no event removed
or renamed.

### W5 — Recording Mode
Subscribes to the existing event bus and emits **Tasks, never waypoints** — movement is regenerated
at resolve time, which is why recording sidesteps `world_z` entirely. Observes quest accepted /
turned in / vendor / trainer / taxi / objective progress. Writes a Campaign JSON per §1.3 with
`resolved` omitted. **Additive only**: new file plus new tests, no edits to existing runtime files.

### W6 — `/resolve` + simulation
`POST /resolve` wrapping W2. Extend `_execute_dry_run` to consume an ExecutionPlan and report
blocked operations, failed actions, and unmet guards without a client.

---

## 3. Verification

| Layer | Command | Current baseline |
| --- | --- | --- |
| Lua | `luajit sentinel/tests/run_offline.lua` | 1152 passed, 0 failed |
| Questing crates | `cd SentinelQuesting && cargo test` | — |
| QueryServer | `cd SentinelQueryServer && cargo test` | — |

Strict TDD: a failing test before the implementation, in the same work unit as the behavior it
covers.

---

## 4. Retirement (after W6 lands, not before)

`sentinel-importer` delete. `sentinel-compiler` delete — logic lives in `sentinel-resolver`.
`sentinel-validator` keep the rules, rehost behind `/validate`.
