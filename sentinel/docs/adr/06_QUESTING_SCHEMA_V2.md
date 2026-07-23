# ADR 06 — Questing Schema v2: objective graph with action effects

Status: proposed (revision 2 — supersedes the linear-step model in revision 1)
Scope: **raw questing only** — class quests, professions, dailies, dungeons, grouping, and UI/meta
directives are explicitly out of scope.

> **Revision note.** Revision 1 specified a linear list of steps (`applicability → actions →
> completion`). That model is **withdrawn**: it structurally cannot let one kill credit several
> quests, which is the single most important behaviour of an efficient leveling bot. A design
> review raised the objective-graph alternative and it is correct. This revision adopts it, with
> two deliberate departures noted in §7.

## 1. Evidence

Command census across `A-1-11-Human.lua` + `The Burning Crusade.lua` (~130k commands), scoped to
raw questing:

| Command | Count | In scope | Role |
| --- | ---: | :---: | --- |
| `.goto` | 32,790 | ✅ | navigation (dominates the corpus) |
| `.target` | 11,419 | ✅ | **names the NPC/mob for the following action** |
| `.turnin` / `.accept` | 13,130 | ✅ | quest lifecycle |
| `.mob` | 6,585 | ✅ | kill target, **by name** |
| `.complete` | 6,374 | ✅ | objective completion gate |
| `.isOnQuest` / `.isQuestTurnedIn` / `.isQuestComplete` / `.isQuestAvailable` / `.isNotOnQuest` | 6,339 | ✅ | applicability |
| `.collect` / `.itemcount` / `.collectmultiple` | 4,362 | ✅ | item objectives |
| `.zone` / `.subzone` / `.zoneskip` / `.subzoneskip` | 4,175 | ✅ | route context + skip |
| `.use` | 1,505 | ✅ | use quest item |
| `.fly` / `.bindlocation` / `.hs` / `.fp` | 1,641 | ✅ | travel network |
| `.unitscan` | 674 | ✅ | watch for a specific mob |
| `.waypoint` / `.groundgoto` | 466 | ✅ | navigation variants |
| `.vendor` | 287 | ✅ | sell/repair (bag space for quest items) |
| `.skipgossip` / `.clicknext` / `.gossip` / `.gossipoption` | 341 | ✅ | dialogue |
| `.deathskip` | 28 | ✅ | mechanical travel optimisation (see §7.3) |
| `.train` / `.trainer` / `.skill` / `.cast` / `.usespell` / `.aura` | 3,045 | ❌ | class + profession |
| `.xp` / `.line` / `.link` / `.itemStat` / `.disablecheckbox` | 2,947 | ❌ | UI / meta |
| `.dungeon` / `.group` / `.solo` | 1,136 | ❌ | grouping |
| `.reputation` / `.money` / `.stable` / `.bank*` / `.daily*` | ~800 | ❌ | QoL / dailies |

## 2. The core problem

RestedXP guides are **instructions for a human**:

```
.goto Elwynn Forest,56.7,44.0
.complete 1598,1
```

means *"walk here, then you'll pick up the tome"* — a human sees the object and clicks it. A
literal transcription travels and then **waits forever**, because nothing in it can satisfy the
gate.

Measured on the v1 compiled Elwynn profile (1,393 actions):

- **53 of 53** `Kill` actions had an empty `creature_entries` list (`.mob` is name-based)
  — *fixed: name resolution now yields 0 of 53 empty*
- **0** loot/interact actions existed at all
- **185** Completion gates had no action able to satisfy them
- **522** Travel actions carried zone percentages in world-coordinate fields, paired with a
  continent id

The vocabulary was never the problem. The **lowering** was, and the *structure* prevented the fix.

## 3. Model: objectives subscribe to actions

The inversion that makes the whole thing work:

> **Actions emit effects. Objectives consume them. Objectives never own actions.**

A single `Kill{creature: 299}` emits effects that any number of objectives may consume:

```
Action  Kill Young Wolf (299)
   │
   ├─► kill credit  creature 299        ─► Objective 7-1   (kill 10 Kobold Vermin)   ✗ no match
   ├─► kill credit  creature 299        ─► Objective 107-2 (kill 8 wolves)           ✓ +1
   ├─► loot roll    item 750 @ 80%      ─► Objective 33-1  (collect 8 Tough Wolf Meat) ✓ +1
   └─► xp / vendor trash                ─► (no objective)
```

Under the v1 step model this required three separate kill steps that could not share progress.

### 3.1 Node types

```jsonc
// Guide metadata — preserves author intent and route ordering. NOT executable.
"guide_blocks": [
  { "id": 12, "zone": {"map": 0, "area_id": 1429}, "sequence": 12, "recommended_level": [1, 6] }
]

// Quest node — lifecycle, resolved to entries
"quests": [
  { "id": 7, "accept_npc": 197, "turnin_npc": 197, "min_level": 1, "prerequisites": [783] }
]

// Objective node — what must become true, and what can make it true
"objectives": [
  {
    "id": "7-1",
    "quest_id": 7,
    "type": "KillCredit",
    "required": 10,
    "completion": { "type": "ObjectiveComplete", "payload": [7, 1] },
    "satisfied_by": [ { "effect": "KillCredit", "creature_entries": [6] } ],
    "locations": [ { "map": 0, "x": -8779.0, "y": -173.8, "z": 83.5, "weight": 31 } ],
    "guide_sequence": 12,
    "depends_on": ["quest:7:accepted"]
  }
]

// Action template — the ONLY executable things
"actions": [
  {
    "id": "kill-kobold-vermin",
    "type": "Kill",
    "payload": { "creature_entries": [6], "loot": true },
    "emits": [ { "effect": "KillCredit", "creature_entries": [6] },
               { "effect": "LootRoll", "items": [{ "item": 750, "chance": 0.8 }] } ]
  }
]
```

### 3.2 Executable action set

`Travel`, `Kill`, `Loot`, `InteractNpc`, `UseItem`, `AcceptQuest`, `TurnInQuest`, `Vendor`,
`Flight`, `LearnFlightPath`, `Hearth`, `SetHearth`, `DeathSkip`. Everything else is metadata.

## 4. Invariants

1. **Satisfiability** — every objective MUST have ≥1 action template whose `emits` can satisfy it.
   (Revision 1's invariant, relocated from step to objective. This is the check that fails 185
   times today, and it is enforceable at compile time.)
2. **Resolution** — no names at runtime. All references are numeric entries.
3. **Coordinates** — world XYZ + continent `map`. A guide percentage MUST NOT survive compilation.
4. **No inert executables** — an executable command is lowered or diagnosed, never demoted to a
   `Comment`.
5. **Adjacent tagging** — every enum crossing into the runtime serialises as `{type, payload}`.
6. **Effect provenance** — every `emits` entry records its derivation level (§5), so a route can be
   audited for how much rests on inference.

## 5. Objective derivation — fallback hierarchy

| Level | Source | Example |
| --- | --- | --- |
| 1 | Server DB (`quest_template`, `creature_loot_template`, `gameobject_loot_template`) | quest 7 → kill creature 6 ×10; quest 33 → item 750 from creatures 299/69/704/705 |
| 2 | Creature/GO scripts (`smart_scripts`, `conditions`) | interact → spawn → credit chains |
| 3 | Guide metadata | guide says "click the crate, kill the pirate, loot the map" |
| 4 | Manual override file | genuinely irregular quests (escort, vehicle, timed) |

Level 1 covers the common case; quest 1598's item 6785 has **no** loot row anywhere in the DB and
is a Level 2/3 case. Expect Level 4 to be ~2–5% of quests. Each objective records the level it was
derived at.

## 6. Scheduler

The scheduler answers *"which objectives are executable right now?"* rather than *"what is the next
line?"* — this is what gives recovery after death, disconnect, mob competition, path failure, and
full bags.

**Phasing (deliberate — see §7.1):**

- **Phase 1** — no scheduler. Execute objectives in `guide_sequence` order, skipping any whose
  `depends_on` is unmet or whose completion is already true. Behaviourally equal to the guide, but
  on the graph, and objectives already share progress via effects.
- **Phase 2** — *nearest executable objective, guide order as tiebreak*. Recovers from being out of
  position without re-deriving the route.
- **Phase 3** — scoring (objectives satisfied, travel saved, spawn density, drop chance, respawn),
  adopted **only** where it measurably beats guide order on time-to-level.

## 7. Deliberate departures from the design review

**7.1 Guide order is a prior, not a score term.** RestedXP's routing is hand-optimised over years
and is the main value of the corpus. An eight-term scoring function that treats guide priority as
one input among many will, in its first iterations, produce worse routes than simply following the
guide. Guide order is therefore the default and the scheduler earns deviations.

**7.2 Testability.** A linear route diffs trivially against its guide; a scheduler's behaviour is
emergent. `sentinel/docs/reference-profiles/northshire-1-6.json` (8 steps, real DB coordinates and
entries, 0 empty kill lists, 0 unsatisfiable gates) is retained as a **behavioural gold test**: the
graph must still complete quests 783 → 7 → 5261 → 33 in Northshire.

**7.3 `.deathskip` is kept.** The review groups it with human-judgment tricks, but it is purely
mechanical (die → release → resurrect nearer the destination) and fully executable.

## 8. Runtime contract (what makes this production-grade, not just a plan format)

§1–7 describe a *plan*. A plan alone is not production-ready; these five contracts are what stop an
unattended run from silently wedging or lying about its progress.

### 8.1 Reconcile, never count

**Objective progress is DERIVED from observed world state, never accumulated locally.**

A local counter (`current: 7 of 10`) drifts the moment reality diverges: death mid-fight, a kill
landing during a disconnect, another player tagging the mob, or simply logging in with the quest
already half-done. The bot then believes something false and waits forever — the exact class of
failure the cockpit's quest-log desync panel exists to catch.

Every objective therefore declares how to *observe* itself:

```jsonc
{
  "id": "7-1",
  "observe": { "type": "ObjectiveComplete", "payload": [7, 1] },   // authoritative: the quest log
  "estimate": { "type": "KillCredit", "creature_entries": [6], "required": 10 }
}
```

`observe` is truth and is re-read every tick. `estimate` exists only to *choose* work (scheduling
and ETA) and carries no authority. Where the two disagree, `observe` wins and the divergence is
reported. This is a desired-state/observed-state reconciler, not a script.

### 8.2 World state model

The scheduler reads one explicit, versioned snapshot; nothing reads the game API ad hoc:

```
WorldState {
  player   { position, map, level, class, race, health, in_combat, is_dead }
  quests   { log[], completed[], objective_progress{} }     // authoritative source for 8.1
  bags     { free_slots, items{} }
  travel   { known_flight_paths[], hearth_location }
  time     { now, session_elapsed }
}
```

"Which objectives are executable right now" is defined purely as a function of this snapshot, which
makes scheduling deterministic and unit-testable offline.

### 8.3 Failure taxonomy

Every action failure classifies, and the class determines the response:

| Class | Meaning | Response |
| --- | --- | --- |
| `Transient` | path blocked, mob tapped, target moved | retry with backoff, bounded by attempts + time |
| `Permanent` | quest already turned in, objective already met, item gone | mark satisfied/skip, advance |
| `Blocked` | bags full, level too low, missing prerequisite | resolve the blocker (vendor/level) then resume |
| `Fatal` | profile/schema invalid, unresolvable reference | stop and surface; never spin |

Unclassified failures default to `Transient` with a low attempt cap, so an unknown fault degrades
to a bounded retry rather than an infinite loop.

### 8.4 Humanization is a first-class field

Pacing is part of the plan, not a wrapper bolted on afterwards. Actions carry pacing hints the
runtime applies through `shared/humanization.lua`:

```jsonc
"pacing": { "pre_delay_ms": [80, 240], "post_delay_ms": [120, 400], "path_jitter_yd": 1.5 }
```

Route level: session length, break cadence, and per-action jitter are declared, not hardcoded, so
behaviour is tunable and auditable rather than emergent.

### 8.5 Versioning and telemetry

- **Compatibility.** `schema_version` is semver with a stated policy: a profile whose MAJOR differs
  from the runtime's MUST be rejected loudly at load, never partially executed. MINOR additions are
  backward compatible (unknown fields ignored). `content_hash` continues to invalidate *saved
  progress* only — it is not a schema-compatibility signal, and the two must not be conflated.
- **Telemetry.** Each objective emits `attempts`, `time_spent_s`, `blocked_reason`, and
  `derivation_level` (§5). This is the cockpit's data source and the basis for replaying an
  overnight run from the event log.

## 9. Known open questions

Recorded honestly rather than resolved by assertion:

1. **Spawn locations as centroids.** `locations` currently uses the mean of spawn rows (31 Kobold
   Vermin → one point). If spawns straddle a road or cliff the centroid is a poor waypoint;
   clustering is likely needed, but is unproven.
2. **Exact-vs-family name resolution.** `.mob Young Wolf` resolves to entry 299 only, while quest
   33's item drops from 299/69/704/705. Kill targeting and loot targeting therefore want *different*
   breadths from the same name, and only enrichment can widen it.
3. **Contested objectives.** No model yet for another player farming the same camp; the scheduler
   phase-2 "nearest executable" heuristic may thrash between camps.
4. **Escort/timed/vehicle quests** are assumed to be Level 4 manual overrides; the 2–5% estimate is
   unvalidated against this corpus.

## 10. Build order

1. **Coordinates** — zone% → world XYZ. Nothing can move until this lands. Schema-independent.
2. **Objective graph + effects** — quests/objectives/actions with `emits`/`satisfied_by`.
3. **Level 1 enrichment** — derive `satisfied_by` from the DB. Kills the 185 unsatisfiable gates.
4. **Phase 1 execution** — guide-ordered traversal of the graph. Ship a bot that levels.
5. **Phase 2 scheduler**, then Levels 2–4 enrichment, then Phase 3 scoring if it earns its place.
