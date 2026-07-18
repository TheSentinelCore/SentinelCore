# Quest Authoring IDE
## Volume 7 — Operation System

Version: 1.0
Status: Canonical Specification

---


# 0. Terminology Note

This volume deliberately does not use the word "Mission."

WoW already has a Mission Table (Garrison missions, Order Hall missions,
Command Table). Reusing "Mission" for this system would collide with an
actual in-game feature and confuse authors immediately.

The vocabulary is:

```
Operation   → the self-contained authoring/execution unit
Quest       → the WoW quest, exactly as the game calls it
Action      → a primitive step inside an Operation
Blueprint   → a composite Action (Volume 6)

```

An Operation is not a quest. An Operation is a container that gets a
character through a phase of content — which usually means completing a
cluster of quests, but may also include pure grinding, a flight unlock,

or a vendor run with no quest involved at all. "Operation" describes the
container's job, not its contents.

---

# 1. Overview

Volume 5 defined Operation as a flat container:

```rust
pub struct Operation {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub enabled: bool,
    pub level_range: LevelRange,
    pub priority: u32,
    pub tags: Vec<String>,
    pub conditions: Vec<Condition>,
    pub variables: Vec<Variable>,
    pub actions: Vec<Action>,

}
```

That was correct as a first pass, but it treats an Operation the same

way Honorbuddy treated a profile section — a bag of steps with a name on
it. It has no concept of:

- what it's actually trying to achieve
- whether it's even eligible to run
- what counts as done, failed, or worth bailing out of
- how it should be optimized internally
- how it relates to other Operations
- how well it performed historically

This volume replaces the flat Operation with a structured one. Everything

below supersedes the Volume 5 definition.


---

# 2. Design Goals


An Operation should be:


- **Self-describing** — its purpose is data, not a comment
- **Independently validatable** — the compiler can check it in isolation
- **Independently simulatable** — a dry run estimates outcome before execution
- **Independently skippable** — the planner can bypass it without breaking the profile
- **Composable** — Operations can depend on, exclude, or nest other Operations
- **Measurable** — every run produces data that feeds back into authoring

If a system can't answer "did this Operation succeed, and why," it isn't
a first-class unit — it's a folder.

---

# 3. Revised Operation Structure


```rust
pub struct Operation {


    pub id: Uuid,

    pub name: String,

    pub description: String,

    pub enabled: bool,

    pub level_range: LevelRange,

    pub priority: u32,

    pub tags: Vec<String>,


    pub goals: Vec<OperationGoal>,

    pub entry_conditions: Vec<Condition>,

    pub exit_conditions: ExitConditions,


    pub dependencies: Vec<OperationDependency>,


    pub optimization_policy: OptimizationPolicy,

    pub completion_metrics: CompletionMetrics,

    pub variables: Vec<Variable>,

    pub actions: Vec<Action>,

    pub sub_operations: Vec<Uuid>,

    pub analytics: OperationAnalytics,

}
```

Nine new fields. Each one earns its place below.

---

# 4. Goals

A Goal states what the Operation is *for*, independent of how it's
achieved.


```rust
pub struct OperationGoal {

    pub id: Uuid,

    pub description: String,

    pub goal_type: GoalType,


    pub required: bool,

    pub weight: f32,

}
```

```rust
pub enum GoalType {

    CompleteQuest(u32),

    CompleteQuestChain(Vec<u32>),

    ReachLevel(u8),

    GainXp(u64),

    ReachZone(String),

    ReachWaypoint(Waypoint),

    AcquireItem(u32, u32),


    KillCount(u32, u32),

    UnlockFlightPath(u32),

    LearnSpell(u32),

    Custom(String),

}
```


An Operation can have multiple goals with different weights. Example —
"Northshire":


```
Required:
  CompleteQuestChain([33, 34, 35, 36])   weight 1.0

Optional:
  ReachLevel(5)                          weight 0.4
  UnlockFlightPath(NorthshireValley)     weight 0.2
```


Required goals gate `Completed` status. Optional goals influence scoring
and analytics but don't block completion.


---

# 5. Why Goals Are Separate From Actions

Actions describe *how*. Goals describe *why*.

This separation is what makes simulation possible. The compiler can ask
"does this action list actually satisfy the stated goals?" without
executing anything — a class of validation that's impossible when intent
only exists in the author's head.

It also makes an Operation swappable. Two completely different action

lists — one questing, one pure grinding — can satisfy the same
`GainXp(4000)` goal. The planner can pick whichever is cheaper right now.

---

# 6. Entry Conditions

Entry conditions gate eligibility. They extend the `Condition` enum from
Volume 5 with Operation-aware variants:

```rust
pub enum Condition {


    // ...existing Volume 5 variants...

    OperationCompleted(Uuid),

    OperationSkipped(Uuid),

    OperationFailed(Uuid),

    FactionIs(Faction),

    RaceIs(Race),

    ClassIs(Class),

    ZoneEntered(String),


}
```

An Operation with unmet entry conditions is never `Ready`. It sits at
`Locked` and the planner ignores it entirely — this is different from
skipping, which is an explicit runtime decision (see §14).

Example — "Northshire" only makes sense for Humans:

```
entry_conditions:

  RaceIs(Human)
  LevelBelow(6)
```

---

# 7. Exit Conditions

Where Volume 5 had one flat `conditions` list, exit conditions split into
three distinct outcomes:

```rust
pub struct ExitConditions {

    pub success: Vec<Condition>,

    pub failure: Vec<Condition>,

    pub abort: Vec<Condition>,

}
```

- **Success** — the goals were met. Normal completion.
- **Failure** — the Operation ran but couldn't reach its goals (quest
  became unobtainable, prerequisite broke, item vendor'd by mistake).
- **Abort** — something outside the Operation's control makes continuing
  a bad idea (death count exceeded, dangerous zone state, player

  manually intervened).

These are evaluated independently, and by design they can overlap in
priority — abort conditions are checked first, then failure, then
success, on every event tick.

```
success:
  QuestRewarded(33)
  QuestRewarded(34)
  QuestRewarded(35)


failure:
  QuestFailed(33)

abort:
  DeathsExceed(3)
```

---


# 8. Optimization Policy

Every Operation carries its own tuning, instead of inheriting one global
policy for the whole profile.

```rust
pub struct OptimizationPolicy {

    pub travel_weight: f32,

    pub xp_weight: f32,


    pub time_weight: f32,

    pub risk_weight: f32,

    pub cluster_objectives: bool,


    pub allow_reordering: bool,

    pub grind_fallback: bool,

    pub max_deaths: Option<u32>,

}
```


This is what the Objective Planner (see the earlier design doc) actually

consumes when it scores and clusters objectives *inside* this Operation.
A safe low-level zone and a late-game elite gauntlet should not share a
risk tolerance.

```
Northshire:
  risk_weight: 0.1
  cluster_objectives: true
  allow_reordering: true

Blackrock Depths lead-in:
  risk_weight: 0.8

  cluster_objectives: false

  allow_reordering: false
```

`allow_reordering: false` matters for escort chains and quest lines where
step order is not actually optional even though it looks like a flat
action list.

---

# 9. Completion Metrics

Metrics are the *targets* an Operation is authored against. They aren't
pass/fail gates (that's what exit conditions are for) — they're the
yardstick analytics compares real runs to.

```rust

pub struct CompletionMetrics {

    pub target_duration: Option<Duration>,

    pub target_xp: Option<u64>,

    pub min_success_rate: Option<f32>,

    pub max_acceptable_deaths: Option<u32>,


}
```

If an Operation is authored to take 4 minutes and it's consistently
taking 11, that's a signal the route, clustering, or difficulty
assumptions are wrong — long before a human notices.

---


# 10. Operation Dependencies

Operations form a graph, not a list.


```rust
pub struct OperationDependency {

    pub operation_id: Uuid,

    pub relationship: DependencyType,


}
```

```rust

pub enum DependencyType {

    Requires,

    SoftPrefers,

    ExcludesWith,

    UnlocksAfter,


}
```

- **Requires** — hard prerequisite. Not eligible until satisfied.

- **SoftPrefers** — the planner should sequence this after the target if
  possible, but it isn't blocking.
- **ExcludesWith** — mutually exclusive (e.g. a Horde-side Operation
  covering the same zone).
- **UnlocksAfter** — becomes visible/eligible only after the target, but
  isn't otherwise dependent on its outcome.

```
Goldshire:
  Requires(Northshire)


Westbrook Garrison:
  SoftPrefers(Goldshire)

Coldridge Valley:
  ExcludesWith(Northshire)
```

---

# 11. Dependency Graph Example

```

Northshire
   │
   ▼
Goldshire ───────► Westbrook Garrison
   │
   ▼
Eastvale Logging Camp
```

The planner performs a topological sort constrained by `Requires` and
`ExcludesWith`, then breaks ties using `SoftPrefers`, geographic
proximity, and Operation priority. This is the Operation-level analogue
of the quest dependency DAG from the original bot design — same idea,
one abstraction layer up.

---

# 12. Operation Branching

Branching at the Operation level means choosing *between* Operations that
achieve equivalent goals — not the in-Operation `Branch` action from
Volume 5, which handles conditional logic *within* one Operation.

Example: two Operations both satisfy `GainXp(2000)` in the same level

range —

```
"Westfall Questing"     goal: GainXp(2000)   risk: low
"Westfall Grind Camp"   goal: GainXp(2000)   risk: medium, faster
```

If quest competition is detected (crowded server, contested spawns), the
planner can substitute one Operation for the other without the author
hand-coding a fallback path. This only works because goals are declared

independently of actions (§5) — the planner is matching on intent, not
on scripted steps.


---

# 13. Operation Lifecycle

```
Locked
  │  entry conditions satisfied

  ▼
Ready
  │  selected by planner
  ▼

Active
  │

  ├──► Completed   (success conditions met)
  │
  ├──► Failed      (failure conditions met)

  │
  ├──► Aborted     (abort conditions met)
  │
  └──► Skipped     (entry unmet elsewhere, or goals already satisfied)
```


```rust
pub enum OperationStatus {

    Locked,

    Ready,


    Active,

    Completed,

    Failed,

    Aborted,

    Skipped,

}
```

This status is per-character, per-run — it lives in runtime state, not
in the authored schema. The authored Operation is the same regardless of
outcome; the status is what happened this time.

---

# 14. Skipping


Skipping is distinct from failing. An Operation is skipped when:

- entry conditions are unreachable for this character (wrong race/class)
- all required goals are already satisfied (quest already turned in from
  a prior session, or completed via a different Operation)
- the author explicitly disabled it (`enabled: false`)
- the planner substituted an equivalent Operation (§12)

Skipped Operations still record analytics — skip rate is itself a useful
signal. An Operation that gets skipped 40% of the time because its goals
are usually already satisfied elsewhere is a sign the dependency graph
needs adjusting, not a bug.


---

# 15. Validation

```
POST /api/v1/operations/validate
```

The compiler checks an Operation in isolation:

```
- Do the actions actually reach the stated goals?
- Are entry and exit conditions contradictory?

- Are there dependency cycles?
- Do referenced NPCs/quests/creatures resolve in the database?
- Is allow_reordering=false compatible with the action list
  (i.e. no clustering annotations that assume free reordering)?
- Are ExcludesWith relationships symmetric?

```

This reuses the QueryServer validation surface from Volume 4, extended
with goal-satisfaction checking, which requires walking the action list

against the quest chain data rather than just checking ID existence.

---

# 16. Simulation

```
POST /api/v1/operations/simulate
```


A dry run estimates outcome using QueryServer data — average spawn
density, quest XP, travel distance — without executing anything.


```json
{
  "operation": "Northshire",
  "estimated_duration": "00:04:30",
  "estimated_xp": 1850,
  "estimated_deaths": 0.1,
  "goal_coverage": {

    "required": "3/3",
    "optional": "1/2"
  },
  "warnings": [

    "UnlockFlightPath goal has no corresponding action"
  ]
}
```


That last warning is the payoff: simulation catches an author who added a
goal but forgot the action that achieves it — a mistake a flat action
list has no way to detect, because there was nothing to check it against.


---

# 17. Sub-Operations

Large zones sometimes need to be broken into phases without fragmenting
them into unrelated top-level Operations.

```rust
pub sub_operations: Vec<Uuid>,
```


```
Northshire
  ├── Northshire — Abbey Grounds
  └── Northshire — Valley Sweep
```


A parent Operation's goals are the union of its sub-operations' required

goals. This is composition, not inheritance — a sub-operation is a full
Operation in its own right and can be reused or validated independently.

---


# 18. Cross-Operation Compiler Optimization

Once Operations declare dependencies and geography, the compiler can
optimize *across* them, not just within one:

```
Goldshire ends at:      Vendor (Brother Danil)
Westbrook begins at:    Travel to Westbrook Garrison

If Westbrook's entry point is near Goldshire's vendor stop,
merge the trailing Vendor action of Goldshire with the leading

Travel action of Westbrook — one continuous route instead of
two independent ones.
```

This is the same merge pass described for Blueprints in Volume 6,
applied one level up. Individually-authored Operations end up executing
as a single optimized route, without the author manually stitching zones

together.

---


# 19. Operation Analytics

```rust
pub struct OperationAnalytics {

    pub runs: u32,

    pub average_duration: Duration,

    pub average_xp: f64,

    pub average_gold: f64,


    pub average_deaths: f32,

    pub success_rate: f32,

    pub skip_rate: f32,


    pub last_run: Option<DateTime<Utc>>,


    pub bottleneck_actions: Vec<Uuid>,

}
```


`bottleneck_actions` is populated by the runtime flagging any action

whose actual duration exceeds its expected duration by a configurable

margin across multiple runs — this is how the system finds its own dead
weight (a camped spawn, a bad travel path, a quest giver that moved)
without a human reviewing logs.


---

# 20. Telemetry-Driven Authoring Feedback

Analytics don't just sit there — they feed back into the editor:

```
Northshire
  Runs: 214
  Success Rate: 97%
  Avg Duration: 4:41 (target: 4:30)
  Bottleneck: "Kill Kobolds" action (avg 1:50, expected 1:10)
```

The editor surfaces this directly on the Operation card. An author
looking at a 40-second overrun on one action knows exactly where to
adjust the polygon or clustering policy — the same feedback loop
described in the original bot design's "Learning Layer," now scoped to
something concrete and inspectable instead of an opaque global heuristic.

---

# 21. Example — Northshire, Fully Specified


```
Operation: Northshire

level_range: 1–5
priority: 100

goals:
  required:
    CompleteQuestChain([33, 34, 35, 36])
  optional:
    ReachLevel(5)          weight 0.4
    UnlockFlightPath(0)    weight 0.2   (none in Northshire — placeholder)

entry_conditions:
  RaceIs(Human)
  LevelBelow(6)

exit_conditions:
  success:
    QuestRewarded(33)
    QuestRewarded(34)
    QuestRewarded(35)
    QuestRewarded(36)
  failure:

    QuestFailed(33)
  abort:
    DeathsExceed(3)


dependencies:
  (none — starting zone)

optimization_policy:
  travel_weight: 0.6
  xp_weight: 0.3
  risk_weight: 0.1
  cluster_objectives: true
  allow_reordering: true
  grind_fallback: false

completion_metrics:
  target_duration: 00:04:30
  target_xp: 1800
  min_success_rate: 0.95

actions:
  [Quest Hub blueprint: Marshal McBride]
  [Grind Area: Kobolds]
  [Grind Area: Wolves]
  [Quest Hub blueprint: turn-in + Goldshire pointer]
```


One authored object. Fully validated, simulatable, skippable, and
measured — without the author writing a single coordinate by hand.

---

# 22. Design Decisions

## Why split Goals from Actions?

Because "did it work" has to be answerable without executing the
Operation. Flat action lists conflate intent and implementation; you
can't validate a goal that was never written down.

## Why three exit categories instead of one condition list?

Success, failure, and abort require different runtime responses.
Collapsing them into one list is how Volume 5's original design would
have forced the runtime to guess which kind of "done" it was looking at.

## Why per-Operation optimization policy instead of one global policy?


A leveling zone and a dungeon lead-in are not the same risk profile.

Honorbuddy-style bots that applied one aggression/safety setting
globally were exactly the profiles that either played too cautiously in
safe zones or died repeatedly in dangerous ones.

## Why dependencies as a typed relationship instead of a plain "requires" list?

`ExcludesWith` and `SoftPrefers` are common cases that a single
`requires` list can't express, and modeling them explicitly means the
planner doesn't need special-cased logic scattered through the codebase
to infer them from naming conventions or zone metadata.

## Why does skipping produce analytics?

A high skip rate is diagnostic. It usually means the dependency graph or
entry conditions are miscalibrated, not that the Operation is unused.

---

# 23. Beyond Existing Tools

Honorbuddy and its contemporaries had no concept of a profile section
"succeeding" versus "failing" versus being "not applicable" — a section
either ran top to bottom or it broke, and breaking looked identical
whether the cause was a dead quest giver or a torn ACL on the wrong
faction.

Treating Operations as validated, simulatable, dependency-aware units
with their own goals and metrics is closer to how a mission designer in
a AAA game engine thinks about a quest node than how a WoW bot profile
has ever been built. That was the instinct behind the original
observation — this volume is what makes it concrete enough to compile.

---


# 24. Before Volume 8

Everything in Volumes 4–7 now assumes a compiler that:

- expands Blueprints (Volume 6) into primitive Actions
- checks Operation goal-coverage (§15)
- estimates Operation outcomes (§16)
- merges trailing/leading actions across dependent Operations (§18)
- resolves the whole dependency graph into a runnable order (§10–11)

None of that compiler has actually been specified yet — Volume 6 admitted
this outright ("the compiler is where the hard engineering lives") and
Volume 4 only covers the read-only query surface it depends on.

Volume 8 should define the Compiler itself: the pipeline from authored
Profile → validated → macro-expanded → dependency-resolved → optimized

→ compiled execution graph, including where it's allowed to fail loudly
versus where it should degrade gracefully at runtime.

---

End of Volume 7

