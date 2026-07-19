# Quest Authoring IDE
## Volume 10 — Analytics & Telemetry System

Version: 1.0
Status: Draft

---

# 0. Why This Volume Exists

Every prior volume assumes this system exists and none defines it:

```
Volume 2  §21   Telemetry — lists what the runtime records (travel
                distance, deaths, repairs, XP/hour...) but not where
                it goes or how it's used.

Volume 2  §17   Dry Run — "movement, combat, interaction are replaced
                with Simulation Adapters" — never specifies what one
                looks like per action type.

Volume 3  §5    Explorer sidebar has an "Analytics" tree node with
                nothing behind it.

Volume 5        Defines an Analytics struct (average_time, average_xp,
                average_gold, deaths) with no collection mechanism.

Volume 7  §19   Defines OperationAnalytics, including
                bottleneck_actions, with no detection algorithm.

Volume 7  §20   "Telemetry-Driven Authoring Feedback" — describes the
                editor surfacing this data, without saying how it gets
                computed.

Volume 9  §6    The Event Bridge produces exactly the event stream
                this volume needs, but hands off "what happens to them
                after" explicitly to this volume.
```

This volume defines the collection, storage, aggregation, and
presentation pipeline that makes all of the above real.

---

# 1. Design Goals

- **Local-first** — this is a single-player leveling tool. No account
  system, no cloud requirement. Telemetry lives on the author's machine
  unless they explicitly export it.
- **Never blocks execution** — telemetry collection is fire-and-forget
  from the runtime's perspective. A telemetry write failure must never
  fail or stall an Action.
- **Separate from QueryServer** — Volume 4 §5 is explicit that
  QueryServer holds "no runtime state." Telemetry is runtime-generated
  state by definition, so it gets its own service, not a bolt-on to
  QueryServer.
- **Aggregation happens off the hot path** — the runtime writes raw
  events cheaply; rollups (averages, bottleneck detection, trends) are
  computed on read or on a background schedule, never inline during
  execution.
- **Dry runs and real runs share a schema** — a Dry Run's Simulation
  Adapters (§8) produce the same event shape as live execution, so the
  same aggregation and comparison logic covers both without a parallel
  code path.

---

# 2. Data Flow

```
Sylvanas Bridge Event Bridge (Volume 9 §6)

            │  semantic events

            ▼

    Runtime Event Dispatcher (Volume 2 §10)

            │  fan-out

            ▼

    Telemetry Collector  ──────────────────►  AnalyticsServer
    (in-process, runtime)   batched HTTP        (Rust/Axum, local)
                                                       │
                                                       ▼
                                                 SQLite (telemetry.db)
                                                       │
                                                       ▼
                                          Aggregation (on read / scheduled)
                                                       │
                                                       ▼
                                          Editor Analytics Panel (Volume 3 §5)
```

The Telemetry Collector subscribes to the same Runtime Event Dispatcher
every other runtime subsystem uses — it does not get privileged access
to raw Bridge events. If a piece of information isn't already a
semantic event by the time it reaches the Dispatcher, it doesn't belong
in telemetry; that's a modeling gap in Volume 2 §10 or Volume 9 §6, not
something this layer should special-case around.

---

# 3. Telemetry Event Model

```rust
pub struct TelemetryEvent {

    pub id: Uuid,

    pub run_id: Uuid,

    pub timestamp: DateTime<Utc>,

    pub operation_id: Uuid,

    pub action_id: Option<Uuid>,

    pub kind: TelemetryEventKind,

}
```

```rust
pub enum TelemetryEventKind {

    OperationStarted,

    OperationCompleted,

    OperationFailed,

    OperationAborted,

    OperationSkipped,

    ActionStarted,

    ActionCompleted { duration: Duration },

    ActionFailed { error: String },

    ActionRetried { attempt: u32 },

    QuestAccepted(u32),

    QuestTurnedIn(u32, u64),

    PlayerDeath,

    GoldChanged(i64),

    XpGained(u64),

    VendorVisited(u32),

}
```

This is a deliberately flat, append-only event log — no event is ever
mutated or deleted once written (except by retention policy, §7). Every
higher-level metric in this volume is a *view* over this log, never a
separately maintained running total, which is what makes the schema
resistant to drift between "what actually happened" and "what the
dashboard says happened."

---

# 4. Run Model

A **Run** is one execution of a Profile, from start to stop.

```rust
pub struct Run {

    pub id: Uuid,

    pub profile_id: Uuid,

    pub schema_version: String,

    pub compiler_version: String,

    pub started_at: DateTime<Utc>,

    pub ended_at: Option<DateTime<Utc>>,

    pub mode: RunMode,

}
```

```rust
pub enum RunMode {

    Live,

    DryRun,

}
```

Every `TelemetryEvent` belongs to exactly one `Run`. Tagging
`schema_version` and `compiler_version` on the Run — not just the
Profile — is what makes §10's regression detection possible: a
performance change can be correlated to "did the ADR schema change" or
"did the compiler change" as well as "did the Profile's authored
content change."

---

# 5. Storage

```
telemetry.db (SQLite, local, per-workspace)

runs               (id, profile_id, schema_version, compiler_version,
                     started_at, ended_at, mode)

telemetry_events    (id, run_id, timestamp, operation_id, action_id, kind)

rollup_cache        (scope, scope_id, window, computed_at, payload_json)
```

`rollup_cache` exists purely as a performance layer — every value in it
is reproducible from `telemetry_events` alone and can be dropped and
recomputed at any time. Nothing in the system should ever treat a cache
row as a source of truth.

---

# 6. AnalyticsServer

A separate lightweight Rust/Axum service, deliberately structured the
same way as Volume 4's QueryServer, but owning entirely different data:

```
GET  /api/v1/runs
GET  /api/v1/runs/{id}

POST /api/v1/telemetry/events           (batched ingest)

GET  /api/v1/analytics/operations/{id}
GET  /api/v1/analytics/operations/{id}/actions
GET  /api/v1/analytics/operations/{id}/bottlenecks
GET  /api/v1/analytics/operations/{id}/trend?window=30d

GET  /api/v1/analytics/profile/{id}

POST /api/v1/analytics/compare           (two schema/compiler versions)

DELETE /api/v1/telemetry/runs/{id}       (author-initiated purge)
```

## Ingest Example

```json
POST /api/v1/telemetry/events

{
  "run_id": "a1b2...",
  "events": [
    { "kind": "OperationStarted", "operation_id": "northshire", "timestamp": "..." },
    { "kind": "ActionCompleted", "action_id": "grind-kobolds", "duration": "00:01:50", "timestamp": "..." },
    { "kind": "QuestTurnedIn", "quest_id": 34, "xp": 350, "timestamp": "..." }
  ]
}
```

Ingest is batched and sent on a timer (every few seconds) or on
Operation boundaries, not per individual event — a chatty per-event
HTTP call for something as high-frequency as `ActionCompleted` would
violate §1's "never blocks execution" goal under any kind of network
hiccup.

---

# 7. Retention

```
Raw telemetry_events:    90 days, then rolled up and discarded
rollup_cache summaries:  kept indefinitely (small — one row per
                          Operation per day, not per event)
```

Retention is a background job, not something the author has to manage.
The 90-day raw window is enough for §10's regression detection to
compare "this week vs last month," while keeping the local SQLite file
from growing unbounded over months of daily play.

---

# 8. Simulation Adapters

Volume 2 §17 introduced these without defining them. A Simulation
Adapter replaces one category of real interaction during Dry Run, and
must emit the same `TelemetryEventKind` shape a live run would — just
computed instead of observed:

```rust
pub trait SimulationAdapter {

    fn simulate(&self, action: &RuntimeAction) -> SimulatedOutcome;

}
```

```
PickupQuestAction    → SimulationAdapter checks: does the quest exist,
                        is the giver reachable per QueryServer data?
                        Emits ActionCompleted with duration = 0, or
                        ActionFailed if the quest can't resolve.

GrindAreaAction       → SimulationAdapter uses QueryServer's spawn
                        density data (Volume 4 §16) to estimate kill
                        count and duration, rather than actually
                        killing anything. Emits ActionCompleted with
                        an *estimated* duration, flagged as such.

GoToAction            → SimulationAdapter uses QueryServer's route
                        analysis (Volume 4 §17) for estimated travel
                        time. Same estimated-duration flagging.

VendorAction          → SimulationAdapter always succeeds instantly;
                        vendor availability isn't a meaningful failure
                        mode to simulate.
```

Because Dry Run events carry `RunMode::DryRun`, every aggregation query
in this volume can include or exclude simulated runs explicitly — the
Compiler's Goal Coverage validation (Volume 8 §8) and the editor's Dry
Run panel (Volume 3 §18) both consume this data, but a Profile's
*real* `average_duration` should never silently include simulated
numbers unless the caller asks for them.

---

# 9. Aggregation — Operation Level

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

This is Volume 7 §19's struct — now with a concrete computation behind
every field, all derived from `telemetry_events` grouped by
`operation_id` over live runs within the query window:

```
runs             = count(distinct run_id) where OperationStarted
success_rate     = count(OperationCompleted) / runs
skip_rate        = count(OperationSkipped) / (runs + skips)
average_duration = avg(OperationCompleted.timestamp - OperationStarted.timestamp)
average_deaths   = avg(count(PlayerDeath) per run, scoped to this operation's time window)
```

---

# 10. Bottleneck Detection

The algorithm Volume 7 §19 left unspecified:

```
For each Action inside an Operation, across the last N live runs:

  actual_avg = avg(ActionCompleted.duration)

  expected = the Action's authored expectation, if one exists
             (Volume 5's Action has no explicit expected-duration
             field today — this volume adds one, see §13)

  If no authored expectation exists, use the trailing rolling average
  from the prior aggregation window as the baseline instead, so
  bottleneck detection works even for un-tuned Actions.

  If actual_avg exceeds baseline by more than a configurable margin
  (default 25%) across at least 5 runs, flag the Action's id in
  bottleneck_actions.
```

Five runs is a floor, not a target — flagging a bottleneck off one or
two runs risks reacting to noise (a single crowded server, a single bad
death) rather than a structural problem with the route or clustering.

---

# 11. Trend Queries

```
GET /api/v1/analytics/operations/{id}/trend?window=30d
```

```json
{
  "operation": "Northshire",
  "points": [
    { "date": "2026-06-20", "avg_duration": "00:04:52", "runs": 12 },
    { "date": "2026-06-27", "avg_duration": "00:04:38", "runs": 9 },
    { "date": "2026-07-04", "avg_duration": "00:05:10", "runs": 14 }
  ]
}
```

This is what powers the "did my last edit actually help" question —
the single most useful thing telemetry can answer for an author actively
iterating on a Profile, and something none of Volumes 1–9 could
previously express at all.

---

# 12. Cross-Version Regression Detection

```
POST /api/v1/analytics/compare

{
  "operation_id": "northshire",
  "compare": ["schema_version", "compiler_version"],
  "baseline": "1.0.0",
  "candidate": "1.1.0"
}
```

```json
{
  "average_duration": { "baseline": "00:04:30", "candidate": "00:05:40", "delta": "+25.9%" },
  "success_rate": { "baseline": 0.97, "candidate": 0.91, "delta": "-6.2%" },
  "verdict": "regression"
}
```

Because every `Run` is tagged with the schema and compiler versions
active at the time (§4), this comparison doesn't require any special
instrumentation — it's a filtered aggregation over the same
`telemetry_events` table split two ways. This is what catches "the
Compiler's Stage 6 optimizer got smarter but broke a route" before an
author notices manually.

---

# 13. Schema Addition — Expected Duration

To make §10's bottleneck detection meaningful from an Action's first
run rather than only after a rolling baseline exists, this volume adds
one optional field to Volume 5's `Action`:

```rust
pub struct Action {

    // ...existing Volume 5 fields...

    pub expected_duration: Option<Duration>,

}
```

Authored manually, or backfilled automatically from the first
successful Dry Run's simulated estimate (§8) — either way, this is the
only schema change this volume requires anywhere outside its own new
structures.

---

# 14. Editor Analytics Panel

Fleshing out Volume 3 §5's empty tree node:

```
Analytics

▼ Northshire
    97% success · 4:41 avg (target 4:30) · 214 runs
    ⚠ Bottleneck: "Kill Kobolds" (avg 1:50, expected 1:10)

▼ Goldshire
    99% success · 6:02 avg · 180 runs

  Trend (Northshire, 30d)
  [ sparkline chart ]

  [ Compare Versions ]   [ Export Telemetry ]   [ Purge Run Data ]
```

Clicking an Operation drills into its Action-level breakdown; clicking a
flagged bottleneck jumps straight to that Action in the Timeline
(Volume 3 §11) — the same "click diagnostic → select offending object"
pattern the Validation Panel already established in Volume 3 §16, reused
here instead of inventing a new interaction model for a new panel.

---

# 15. Privacy and Export

```
- All telemetry stays in the local telemetry.db by default.
- Export produces a portable JSON/CSV bundle, author-initiated only.
- Purge (DELETE /api/v1/telemetry/runs/{id}) is permanent and
  immediate — no soft-delete, no undo, since this is local diagnostic
  data with no cross-author value to preserve.
```

No telemetry is ever sent anywhere without an explicit author action.
This isn't a compliance requirement so much as a design stance
consistent with Volume 1's whole premise — the author is in full control
of their own authoring environment.

---

# 16. Module Layout

```
analytics-server

├── api
├── ingest
├── aggregation
│   ├── operation_rollup
│   ├── bottleneck_detection
│   └── trend
├── comparison
├── retention
├── sqlite
└── models

sentinel-runtime

└── telemetry_collector    (subscribes to Event Dispatcher, batches,
                             pushes to analytics-server)
```

`telemetry_collector` lives in the runtime crate, not in
`analytics-server` itself — it's a client of this service, not part of
it, matching the same client/server separation Volume 4 established
between the editor and QueryServer.

---

# 17. Design Decisions

## Why a separate service instead of folding this into QueryServer?

Volume 4 §5 states QueryServer holds no runtime state as a hard design
principle, specifically so its caching and versioning story stays
simple ("stateless, cacheable, deterministic"). Telemetry is runtime
state by definition — mixing them would force QueryServer to solve
cache invalidation and write-concurrency problems it doesn't otherwise
have.

## Why is aggregation computed on read/schedule instead of maintained incrementally?

An append-only raw event log with derived rollups means a bug in
aggregation logic is always fixable by recomputing from source — an
incrementally-maintained running average that drifts from reality has
no such recovery path short of a full data audit.

## Why do Dry Run and Live runs share one schema instead of separate telemetry paths?

Because §12's regression detection and §9's Operation Analytics need to
answer "is this Profile actually getting better" regardless of whether
the most recent test was a live playthrough or a Dry Run — and because
maintaining two parallel event schemas is exactly the kind of
duplicated-logic problem this whole ADR series has been trying to design
away since Volume 1.

## Why is bottleneck detection a fixed threshold instead of something learned/adaptive?

A fixed, visible threshold (25% over 5+ runs) is auditable — an author
can understand exactly why something got flagged. Volume 1's original
research doc floated a "Learning Layer" for the bot's runtime decisions;
this is deliberately not that. Analytics here reports what happened; it
doesn't quietly start making authoring decisions on the author's behalf.

---

# 18. Before Volume 11

With Volumes 1 through 10, every part of the system that lives in
memory — schema, compiler, blueprints, operations, the live game bridge,
and now telemetry — is specified. The one piece still missing is the
most basic one: what an authored Profile actually looks like sitting on
disk.

The original analysis at the start of this whole project praised
splitting a profile into separate files (routes, objective groups,
conditions, events) instead of one monolithic blob — but nothing since
has defined that layout, how Profile Manager's `load()`/`save()`
(Volume 2 §4) reassembles it, or how it interacts with version control.

Volume 11 should define the Profile Storage & File Format.

---

End of Volume 10
