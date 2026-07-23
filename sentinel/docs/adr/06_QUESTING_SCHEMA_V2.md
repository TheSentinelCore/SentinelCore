# ADR 06 — Questing Runtime Schema v2 (raw questing)

Status: proposed
Scope: **raw questing only** — class quests, professions, dailies, dungeons, grouping, and UI/meta
directives are explicitly out of scope.

## 1. Evidence

Command census across `A-1-11-Human.lua` + `The Burning Crusade.lua` (~130k commands):

| Command | Count | In scope | Role |
| --- | ---: | :---: | --- |
| `.goto` | 32,790 | ✅ | navigation (dominates the corpus) |
| `.target` | 11,419 | ✅ | **names the NPC/mob for the following action** |
| `.turnin` | 6,658 | ✅ | quest turn-in |
| `.mob` | 6,585 | ✅ | kill target, **by name** |
| `.accept` | 6,472 | ✅ | quest accept |
| `.complete` | 6,374 | ✅ | objective completion gate |
| `.isOnQuest` / `.isQuestTurnedIn` / `.isQuestComplete` / `.isQuestAvailable` / `.isNotOnQuest` | 6,339 | ✅ | applicability gates |
| `.collect` / `.itemcount` / `.collectmultiple` | 4,362 | ✅ | item objective gates |
| `.zoneskip` / `.zone` / `.subzone` / `.subzoneskip` | 4,175 | ✅ | route context + skip |
| `.use` | 1,505 | ✅ | use quest item |
| `.fly` / `.bindlocation` / `.hs` / `.fp` | 1,641 | ✅ | travel network |
| `.unitscan` | 674 | ✅ | watch for a specific/rare mob |
| `.waypoint` / `.groundgoto` | 466 | ✅ | navigation variants |
| `.vendor` | 287 | ✅ | sell/repair (keeps bags open for quest items) |
| `.skipgossip` / `.clicknext` / `.gossip` / `.gossipoption` | 341 | ✅ | dialogue interaction |
| `.deathskip` | 28 | ✅ | intentional-death travel |
| `.train` / `.trainer` / `.skill` / `.cast` / `.usespell` / `.aura` | 3,045 | ❌ | class + profession |
| `.xp` / `.line` / `.link` / `.itemStat` / `.disablecheckbox` | 2,947 | ❌ | UI / meta |
| `.dungeon` / `.group` / `.solo` | 1,136 | ❌ | grouping |
| `.reputation` / `.money` / `.stable` / `.bank*` / `.daily*` | ~800 | ❌ | QoL / dailies |

## 2. The core problem this schema fixes

RestedXP guides are **instructions for a human**. A step that reads

```
.goto Elwynn Forest,56.7,44.0
.complete 1598,1
```

means *"walk here, then you'll pick up the tome"* — the human sees the object and clicks it. A
literal transcription produces a step that travels and then **waits forever**, because nothing in
it can satisfy the gate.

Measured on the v1 compiled Elwynn profile (1,393 actions):

- **53 of 53** `Kill` actions had an **empty** `creature_entries` list (`.mob` is name-based)
- **0** loot/interact actions existed at all
- **185** Completion gates had no preceding action that could satisfy them
- **522** Travel actions carried *zone percentages* in world-coordinate fields, paired with a
  *continent id* — two incompatible coordinate systems in one struct

The schema vocabulary was not the problem; the **lowering** was. v2 therefore specifies both the
shape *and* the invariants a profile must satisfy to be executable.

## 3. Invariants (a profile is invalid without these)

1. **Satisfiability** — every `Completion` gate MUST be preceded, within the same step, by at least
   one action that can satisfy it (`Kill`, `Loot`, `UseItem`, `InteractNpc`, `AcceptQuest`).
2. **Resolution** — no names at runtime. Every reference is a numeric entry
   (`npc_entry`, `creature_entries[]`, `item_id`, `quest_id`, `object_entry`). Name→entry
   resolution happens at compile time, against the game DB.
3. **Coordinates** — `position` is always a **world** coordinate triple plus the **continent**
   `map` id (Eastern Kingdoms `0`, Kalimdor `1`, Outland `530`). Guide percentages are converted at
   compile time; a percentage MUST NOT survive into a profile.
4. **No inert executables** — a command with executable meaning is either lowered to a typed action
   or recorded as a diagnostic. It is never silently demoted to a `Comment`.
5. **Adjacent tagging** — every enum crossing into the runtime serializes as `{type, payload}`,
   because the Lua runtime dispatches on `.type`.

## 4. Schema

```jsonc
{
  "schema_version": "2.0.0",
  "name": "Human 1-11",
  "game": "2.4.3",
  "content_hash": "…",          // invalidates saved progress when the route changes
  "faction": "Alliance",         // route-level applicability
  "level_range": [1, 11],
  "steps": [
    {
      "id": 42,
      "name": "Kobold Camp Cleanup",
      "zone": { "map": 0, "area_id": 1429, "name": "Elwynn Forest" },
      "quest_id": 7,             // the quest this step advances (nullable for pure travel)
      "applicability": {          // evaluated ONCE on entry; false ⇒ skip whole step
        "type": "All",
        "payload": [
          { "type": "QuestAccepted", "payload": 7 },
          { "type": "Not", "payload": { "type": "QuestRewarded", "payload": 7 } }
        ]
      },
      "actions": [ /* … */ ],
      "completion": {             // step is done when this is true
        "type": "ObjectiveComplete", "payload": [7, 1]
      },
      "on_failure": "skip",      // skip | abort | retry
      "budget_s": 900             // hard cap; prevents an unattended wedge
    }
  ]
}
```

### 4.1 Why `steps` replace flat `operations`

v1 emitted one operation per guide line, so a single logical objective spread across many
operations and the *gate* landed in a different operation than the *action* that satisfies it —
structurally guaranteeing invariant 1 could not hold. A step is the atomic unit of intent:
**applicability → actions → completion**, with a time budget.

### 4.2 Action set (raw questing)

| Action | Payload | Lowered from |
| --- | --- | --- |
| `Travel` | `{position{map,x,y,z}, tolerance, allow_flight}` | `.goto`, `.groundgoto`, `.waypoint` |
| `AcceptQuest` | `{quest_id, npc_entry, auto_complete_dialog}` | `.accept` (+`.target`) |
| `TurnInQuest` | `{quest_id, npc_entry, choose_reward}` | `.turnin` (+`.target`) |
| `Kill` | `{creature_entries[], quantity, loot, ignore_elites}` | `.mob`, `.unitscan` |
| `Loot` | `{object_entry \| item_id, quantity}` | derived from objective |
| `UseItem` | `{item_id, target_entry?}` | `.use` |
| `InteractNpc` | `{npc_entry, gossip_path[]}` | `.gossip`, `.clicknext`, `.skipgossip` |
| `Vendor` | `{npc_entry, sell_grey, repair, buy_items[]}` | `.vendor` |
| `Flight` | `{npc_entry, destination_node}` | `.fly` |
| `LearnFlightPath` | `{npc_entry}` | `.fp` |
| `Hearth` | `{}` / `SetHearth {npc_entry}` | `.hs` / `.bindlocation` |
| `DeathSkip` | `{target_position}` | `.deathskip` |

### 4.3 Condition set

`QuestAccepted`, `QuestCompleted`, `QuestRewarded`, `ObjectiveComplete[quest,idx]`,
`ItemCountAtLeast[item,n]`, `HasItem`, `LevelAtLeast`, `LevelBelow`, `ZoneIs`, `ClassIs`, `RaceIs`,
`FactionIs`, plus `All` / `Any` / `Not`. All adjacently tagged.

## 5. Required compiler passes (this is the work)

1. **Name resolution** — `.target <name>` and `.mob <name>` → entries via `creature_template`.
   This alone fixes all 53 empty kill lists. Ambiguous names resolve by proximity to the step's
   zone; unresolved names become a blocking diagnostic, never an empty list.
2. **Objective enrichment** — for each `.complete q,i` / `.collect item,n`, read the quest's real
   requirement from `quest_template` (`ReqCreatureOrGOId*`, `ReqItemId*`) and **synthesize the
   satisfying action**. Example: quest 7 → `Kill{creature_entries:[6], quantity:10}`; quest 33 →
   item 750 ×8, which `creature_loot_template` attributes to creatures 299/69/704/705 → a `Kill`
   on those with `loot:true`.
3. **Coordinate conversion** — zone percentage + zone → world XYZ. Two verified sources agree to
   ~1 yard: the client API `core.game_ui.get_world_pos_from_map_pos(1429,{x,y})` returned
   `(-8932.5,-137.5)` for `48.2,42.9`, and the DB has Deputy Willem at `(-8933.5,-136.5)`.
   Prefer DB spawn coordinates for NPC/creature targets; use conversion for open-world waypoints.
4. **Step assembly** — group guide lines into steps so the gate and its satisfying action land
   together, then assert invariant 1 at compile time.
5. **Zone-context tracking** — carry `.zone`/`.subzone` so `.zoneskip`/`.subzoneskip` lower to
   `ZoneIs` applicability rather than being dropped.

## 6. Validation

`sentinel/docs/reference-profiles/northshire-1-6.json` is the hand-authored gold reference for
Human 1–6: 8 steps, real DB world coordinates, real creature entries, **0 empty kill lists and 0
unsatisfiable gates**. It is the executable target the compiler must reproduce; a compiler change
is "done" when its output for the same guide range is behaviourally equivalent to this file.
