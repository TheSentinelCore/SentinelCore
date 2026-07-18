# Quest Authoring IDE
## Volume 8 — The Compiler

Version: 1.0
Status: Canonical Specification


---

# 1. Overview

Every prior volume has referred to "the compiler" and deferred its actual

design:

```
Volume 1  §7   "Even though editing occurs in-game, the runtime profile
                should never be edited directly" — sketches a 5-step
                pipeline, no detail.


Volume 2  §4   ProfileManager.compile() — signature only.

Volume 6  §27  Blueprint expansion pipeline — covers one Blueprint in
                isolation, not a whole Profile.

Volume 7  §24  Explicitly states the full compiler — Blueprint expansion
                + Operation dependency resolution + optimization +
                execution graph — was never specified.

```

This volume closes that gap. It defines the single pipeline that takes an
authored `Profile` (Volume 5, revised by Volume 7) and produces the
immutable `Runtime Execution Profile` that Volume 2's Action Executor

actually runs.

```
Authoring Profile (mutable, Volume 5/7 schema)


            │

            ▼

         COMPILER


            │


            ▼

Runtime Execution Profile (immutable, this volume)

```

---

# 2. Design Goals

- **Deterministic** — same input Profile + same database state = same
  output, every time. No wall-clock dependence, no random tie-breaking.
- **Incremental** — editing one Operation shouldn't force a full-profile
  recompile (Volume 2 §13, Dirty Tracking).
- **Fail loud, degrade gracefully** — compilation errors block; the
  runtime keeps executing the last good compile (Volume 2 §12, Hot
  Reload).
- **No runtime database access** — everything the runtime needs is
  resolved and embedded at compile time. The runtime never calls
  QueryServer mid-execution for something the compiler could have

  resolved (see §9).
- **Debuggable** — every generated action can be traced back to the
  authored object that produced it.

---

# 3. The Pipeline


Seven stages, always in this order:


```
1. Structural Validation
        │
2. Reference Resolution
        │
3. Blueprint Expansion
        │
4. Operation Dependency Resolution
        │
5. Goal Coverage Validation
        │
6. Cross-Operation Optimization
        │
7. Lowering (emit Runtime Execution Profile)

```

Each stage either passes its output to the next stage or halts the
compile with diagnostics. Stages 1, 2, and 5 can produce warnings that
don't halt compilation. Stages 3, 4, and 7 cannot proceed on an error.

---

# 4. Stage 1 — Structural Validation

The cheapest checks, run first, so a malformed Profile never wastes time
in later stages.


```
- Duplicate Action / Operation / NPC / Quest IDs
- Dangling UUID references (an Action pointing at a variable that
  doesn't exist in scope)
- Turn In referencing a quest with no matching Pickup anywhere in the
  Profile's reachable Operation graph
- Malformed polygons (fewer than 3 vertices, self-intersecting)
- Schema version mismatch (routes to migration, see §14)
```


This is Volume 1 §12 and Volume 2 §11's "Structural" and "Logical"
categories, formalized as compiler passes instead of editor-only
diagnostics — the editor calls this stage on every dirty Operation for
live feedback, and the compiler calls it again over the whole Profile
before emitting anything.

---

# 5. Stage 2 — Reference Resolution

Every `NpcReference`, `QuestReference`, `VendorEntry`, `CreatureReference`
and `GameObjectReference` in the Profile is resolved against QueryServer
(Volume 4) **once**, here, and the result is embedded in the compiled
output.

```
NpcReference { entry: 197, name: "Marshal McBride", ... }

            │  QueryServer lookup


            ▼


Fully resolved: position, roles, faction, current spawn state
```

This is what makes §9's "no runtime database access" guarantee possible.
If an NPC entry doesn't resolve, or a quest ID doesn't exist in the

target database, that's a hard error here — not a runtime surprise three
hours into a leveling session.

Resolution results are cached per database version (§15) so re-resolving
an unchanged NPC library on every recompile is free.

---


# 6. Stage 3 — Blueprint Expansion

This reuses Volume 6 §9's pipeline, but applied recursively across the
whole Profile rather than one Blueprint instance:

```
For each Action in each Operation:

  Is payload a Blueprint reference?

    Yes → Resolve Parameters
            │
          Inject Defaults (smart defaults from QueryServer, Vol 6 §16)
            │
          Recurse (Blueprints may contain Blueprints, Vol 6 §10)
            │
          Remove actions for unset optional parameters (Vol 6 §14)
            │
          Emit primitive Actions, tagged generated_from: <blueprint_id>

    No  → Pass through unchanged
```

Output of this stage: every Operation's action list contains **only**
primitive `ActionPayload` variants from Volume 5 §Action Payload. No
Blueprint references survive past Stage 3.

Expansion order matters for determinism — Blueprints expand in the order
they appear in the timeline, and nested Blueprints expand depth-first.


---

# 7. Stage 4 — Operation Dependency Resolution

This is new work this volume has to define — Volume 7 introduced
`OperationDependency` but never specified how the compiler actually uses
it.

```
1. Build a directed graph: one node per Operation, one edge per

   Requires / UnlocksAfter relationship.

2. Detect cycles. A cycle is a hard compile error — it means two
   Operations require each other, which can never resolve.

3. Detect ExcludesWith conflicts where both sides are eligible for the
   same character (same race/class/faction match) — hard error, unless
   the author has also given each side non-overlapping entry_conditions
   that make them mutually exclusive by construction (e.g. RaceIs(Human)
   vs RaceIs(Dwarf)), in which case it's a redundant declaration and only
   warns.


4. Topologically sort on Requires/UnlocksAfter.

5. Within ties, order by SoftPrefers, then Operation.priority

   (Volume 5/7), then declaration order as a stable fallback.
```

Output: a single linear compile-time ordering of Operations. This is
*not* necessarily the runtime execution order — a character's
entry_conditions still gate which Operations actually go `Ready` at
runtime (Volume 7 §13) — but it's the order the remaining stages process

Operations in, and it's what makes Stage 6's merge pass possible.

---

# 8. Stage 5 — Goal Coverage Validation

For every `OperationGoal` marked `required` (Volume 7 §4), the compiler
checks that the Operation's expanded action list can actually produce
the state the goal describes:

```
GoalType::CompleteQuestChain([33, 34, 35, 36])

    → every quest ID in the chain must have a corresponding
      PickupQuestAction and TurnInQuestAction somewhere in this
      Operation or one of its sub_operations (Volume 7 §17)

GoalType::ReachLevel(5)


    → non-checkable statically; passes through as a runtime-verified
      goal, flagged informational rather than blocking


GoalType::UnlockFlightPath(node_id)

    → must have a FlightAction or a TalkToNpc resolving to that flight
      master's gossip options
```

This is Volume 7 §15/§16's validate/simulate logic, but promoted from an
optional API call into a **mandatory compile stage**. A Profile with an
unreachable required goal does not compile — it doesn't just warn in the

editor and get shipped anyway.

Optional goals that aren't covered by any action produce a warning, not
an error (Volume 7 §16's example — `UnlockFlightPath` goal with no
matching action).

---

# 9. Stage 6 — Cross-Operation Optimization


Using the linear ordering from Stage 4, walk adjacent Operations and
apply merge rules:


```
Operation A ends with:    VendorAction (Brother Danil)
Operation B begins with:  GoToAction (Westbrook Garrison)

If A's vendor position and B's entry waypoint are within merge

distance, and both Operations are enabled for the same character
profile, rewrite:

    A: [..., VendorAction]
    B: [GoToAction, ...]


into:

    A: [..., VendorAction]
    B: [...]                      (leading GoToAction removed —
                                    already satisfied by A's position)

```

This is the same merge concept as Volume 6 §22 (adjacent action merging
inside one Blueprint expansion), applied at Operation boundaries as
described in Volume 7 §18. It only fires between Operations that are
adjacent in the *resolved* compile order from Stage 4 — never
speculatively across the whole graph, since two Operations might never
actually run back-to-back for a given character.

Other optimizations applied here:

```
- Collapse consecutive Vendor + Repair into one interaction
  (already covered for Blueprints in Vol 6 §22; extended here to
  primitive actions that happen to end up adjacent post-expansion)

- Drop redundant GoTo actions where the destination matches the
  player's expected position from the prior action's effect

- Reorder within an Operation when allow_reordering: true
  (Volume 7 §8) to minimize travel, using QueryServer route analysis
  (Volume 4 §17)
```

Optimization never changes goal coverage. Every rewrite is validated
against Stage 5's goal set before being accepted — an optimization that
would break a required goal is rejected and logged as a compiler
diagnostic, not silently applied.

---

# 10. Stage 7 — Lowering

The final stage converts the optimized authoring structures into the
immutable Runtime Execution Profile.

```rust
pub struct RuntimeProfile {


    pub schema_version: String,


    pub compiled_at: DateTime<Utc>,


    pub compiler_version: String,

    pub source_profile_id: Uuid,

    pub source_profile_hash: String,

    pub operations: Vec<RuntimeOperation>,

}
```

```rust
pub struct RuntimeOperation {

    pub id: Uuid,

    pub name: String,

    pub entry_conditions: Vec<Condition>,

    pub exit_conditions: ExitConditions,


    pub goals: Vec<OperationGoal>,

    pub actions: Vec<RuntimeAction>,

}
```

```rust
pub struct RuntimeAction {

    pub id: Uuid,

    pub payload: ResolvedActionPayload,

    pub retry_policy: RetryPolicy,

    pub timeout: Duration,

    pub generated_from: Option<Uuid>,

}
```


`ResolvedActionPayload` mirrors Volume 5's `ActionPayload` enum
one-to-one, except every embedded reference is fully resolved — an

`NpcReference` here carries a concrete position and GUID rather than an

entry ID the runtime would need to look up. This is what Volume 2 §18
means by "the runtime never queries SQLite directly": by the time this
struct exists, it doesn't need to query anything at all.

`generated_from` is Volume 6 §25's runtime metadata field, generalized —
it's populated whenever an action originated from Blueprint expansion
*or* was inserted/rewritten by Stage 6's optimizer, so a debug session
can always answer "why does this action exist."

---


# 11. Incremental Compilation

Full recompiles are wasteful for a single-Operation edit. The compiler
tracks dirty state per Volume 2 §13:

```
Operation edited

    → marked Dirty

    → Stages 1–3 re-run for that Operation only

    → Stage 4 re-runs only if the edit touched dependencies,
      priority, or entry_conditions (anything affecting ordering)


    → Stage 5 re-runs only for that Operation's goals

    → Stage 6 re-runs only for the edited Operation and its
      immediate neighbors in compile order (a merge could only
      ever involve adjacent Operations)

    → Stage 7 re-lowers only the affected RuntimeOperation entries
```

An edit to a single Action inside one Operation, in the common case,
never touches more than that Operation and its two neighbors.

---

# 12. Diagnostics

Compiler diagnostics extend Volume 2 §19's format with stage

attribution:


```
ERROR

C-4002

Stage: Operation Dependency Resolution

"Westbrook Garrison" and "Coldridge Valley" both declare
ExcludesWith against each other, but are both eligible for
RaceIs(Human) characters.

Suggested Fix

Add a mutually exclusive entry_condition to one side, or
remove the ExcludesWith relationship if this is intentional
and should instead be resolved by planner-time scoring.
```

```
WARNING

C-5001

Stage: Goal Coverage Validation


Optional goal "UnlockFlightPath" on Operation "Northshire"
has no corresponding action.

Suggested Fix

Add a Flight blueprint, or remove the goal if it no longer

applies.
```

Error codes are namespaced by stage (`C-1xxx` structural, `C-2xxx`
resolution, `C-3xxx` expansion, `C-4xxx` dependency, `C-5xxx` goal
coverage, `C-6xxx` optimization, `C-7xxx` lowering) so tooling can
filter and route them without string matching on messages.

---

# 13. Compiler Architecture

```

compiler

├── stages
│   ├── structural

│   ├── resolution
│   ├── expansion
│   ├── dependency
│   ├── goal_coverage
│   ├── optimization
│   └── lowering
│
├── graph            (Operation dependency graph, topo sort, cycle detect)
├── diagnostics       (error/warning collection and formatting)
├── cache             (resolution cache, keyed on DB version)
├── dirty             (incremental recompile tracking)

└── query_client      (QueryServer HTTP client, Volume 4)
```

Each stage module takes the previous stage's output type and returns
either the next stage's input type or a `Vec<Diagnostic>`. No stage
reaches backward into an earlier stage's data — if Stage 6 needs
information Stage 2 resolved, that information is carried forward in the
intermediate representation, never re-fetched.

---

# 14. Schema Migration

When `schema_version` on an input Profile doesn't match the compiler's
expected version:

```

Input Profile (v1.0)

    │

    ▼

Migration Registry — ordered list of (from, to, migration_fn)

    │

    ▼

Profile (current version)

    │

    ▼

Stage 1 (Structural Validation) proceeds normally
```

Migrations run before Stage 1, never inside it. A migration that can't

resolve (e.g. a field with no sensible default in the new schema) halts
before validation even starts, with a distinct diagnostic class
(`M-xxxx`) so it's never confused with an authoring error in the
Profile itself.

---


# 15. Caching


```
Resolution Cache   (Stage 2)   — keyed on (entry_id, db_version)
Expansion Cache    (Stage 3)   — keyed on (blueprint_id, parameter_hash)
Compile Cache      (whole)     — keyed on source_profile_hash
```

If `source_profile_hash` and `db_version` are both unchanged since the
last compile, Stage 1–7 are skipped entirely and the previous
`RuntimeProfile` is returned. This is what makes "Save → Compile" feel
instantaneous in the editor for saves that didn't actually change
anything meaningful (e.g. a no-op undo/redo round trip).

---


# 16. Failure Behavior

Per Volume 2 §12:

```
Compile fails


    │

    ▼

Runtime keeps the last successfully compiled RuntimeProfile

    │


    ▼


Editor surfaces diagnostics; execution is unaffected until
the author fixes the error and saves again
```

The compiler never partially emits a `RuntimeProfile`. It's all seven
stages succeeding or nothing — a half-lowered execution graph is worse
than an unavailable one, because the runtime has no way to tell the two
apart without extra bookkeeping this design deliberately avoids.

---

# 17. What Moved Where

A recap, since this volume is where every earlier "the compiler will
handle this" promise actually gets paid off:

```

Authoring-time (author's job)
    Intent: goals, entry/exit conditions, action sequence

Compile-time (this volume's job)
    Reference resolution, Blueprint expansion, dependency ordering,
    goal-coverage proof, cross-operation route optimization


Runtime (Action Executor's job, Volume 2)
    Execute already-resolved, already-ordered, already-optimized
    primitive actions. No decisions. No database calls. No inference.
```

This is the concrete form of Volume 1's founding principle: "the runtime
should never need to infer author intent — the compiler already did
that."

---


# 18. Example — Compiling Northshire

Input: the `Operation` from Volume 7 §21, with its Quest Hub blueprint
actions still unexpanded.

```
Stage 1  Structural       — pass
Stage 2  Resolution       — Marshal McBride (197), Brother Danil (NPC),
                             quests 33/34/35/36 all resolve
Stage 3  Expansion        — Quest Hub blueprint → 9 primitive actions
Stage 4  Dependency        — Northshire has no dependencies; sorts first
Stage 5  Goal Coverage     — CompleteQuestChain([33,34,35,36]): covered
                             ReachLevel(5): informational, passes
Stage 6  Optimization      — trailing Vendor merges with Goldshire's
                             leading GoTo (next Operation in sort order)
Stage 7  Lowering          — RuntimeOperation "Northshire" emitted,
                             11 RuntimeActions, all generated_from
                             traceable to either the source Action or
                             the Quest Hub blueprint instance
```

Output: one `RuntimeOperation`, fully resolved, fully ordered, ready for
the Action Executor — with zero database lookups required at execution
time.

---

# 19. Design Decisions

## Why seven fixed stages instead of a configurable pipeline?


A configurable pipeline invites stage-ordering bugs that only show up on
specific Profiles. Fixed order means every compile is reproducible by
construction, and diagnostics can hard-code which stage produced them.

## Why does optimization run after goal coverage, not before?

Optimizing first would mean re-validating goal coverage against a
rewritten action list anyway — the check has to happen against whatever
the runtime will actually execute. Running coverage first also lets the
optimizer treat goal coverage as an invariant it must preserve, not
something it needs to compute itself.

## Why is Reference Resolution its own stage instead of inline in Lowering?

Blueprint expansion (Stage 3) and Goal Coverage (Stage 5) both need
resolved reference data — a Blueprint's "nearest vendor" default (Volume
6 §16) can't be computed without QueryServer results, and goal coverage
for `UnlockFlightPath` needs to know which NPC a `TalkToNpc` action
actually resolves to. Resolving once, early, and reusing the result
downstream avoids three separate stages independently calling
QueryServer for the same entity.

## Why keep a full RuntimeProfile per compile instead of patching runtime state directly?

Determinism and hot-reload safety (§16). A patch-based approach means
runtime state can drift from what any single compile actually produced,
which makes bugs unreproducible. An immutable, fully-replaced
`RuntimeProfile` on every successful compile means "what's executing
right now" is always exactly one compiler run's output, not an
accumulation of patches.

---


# 20. Before Volume 9

The Compiler assumes the Reference Resolution stage (§5) can always
reach QueryServer, and assumes the editor can always capture NPCs,
positions, and paths from the live game (Volume 3 §8, §19, §20) — but
nothing so far has specified how the editor actually talks to the game

client. Volume 1 explicitly hedged this as "ImGui-style assumed until
Sylvanas Addons API confirms otherwise," and it's been an open
assumption ever since.

Volume 9 should define the Sylvanas Addon API integration layer: how the
overlay renders and receives input inside the WoW client, how target
capture and event hooks (QuestAccepted, NPCReached, etc. from Volume 2
§10) actually bind to Sylvanas API primitives, and where the boundary

sits between "what Sylvanas already exposes" and "what this project has
to build on top of it."

---

End of Volume 8

