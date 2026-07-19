# Sentinel — Implementation Tickets

Version: 1.0
Status: Draft
Source: docs/adr/001 through docs/adr/011

---

# How to Read This Document

Every ticket follows the same shape:

```
SENT-<phase>.<seq> — Title
ADR: <volume> §<section> (the ground-truth this ticket implements)
Depends: <other ticket IDs>
Description: one to two sentences
Acceptance Criteria: the concrete, checkable definition of done
Estimate: hours
```

Tickets are grouped into 12 phases, ordered by actual dependency, not by
ADR volume number — several phases (Storage, QueryServer, Bridge) can
run in parallel once their own prerequisites are met; the Dependency
Overview in §2 shows which.

**Global Definition of Done**, on top of each ticket's own Acceptance
Criteria:

```
- cargo build --workspace and cargo test --workspace both pass
- No clippy warnings under default lints
- Every new public struct/enum has a doc comment citing its ADR
  volume and section, per the citation convention this whole spec
  suite has followed since Volume 5
- No ticket is "done" on partial acceptance criteria — split it
  instead of marking it complete early
```

---

# 1. Phase Summary

| Phase | Focus | ADR Volumes | Tickets | Hours |
|---|---|---|---|---|
| 0 | Foundations & Scaffolding | — | 6 | 21 |
| 1 | Canonical Schema | 005, 007 | 10 | 41 |
| 2 | Profile Storage & File I/O | 011 | 11 | 51 |
| 3 | QueryServer | 004 | 13 | 66 |
| 4 | Blueprint System | 006 | 9 | 45 |
| 5 | Operation System Logic | 007 | 7 | 34 |
| 6 | The Compiler | 008 | 12 | 74 |
| 7 | Sylvanas Bridge | 009 | 8 | 48 |
| 8 | Runtime Execution Engine | 002 | 11 | 67 |
| 9 | Analytics & Telemetry | 010 | 9 | 49 |
| 10 | Editor UI | 003, 006, 010 | 18 | 121 |
| 11 | Integration, Hardening & Release | all | 7 | 56 |
| **Total** | | | **121** | **673** |

673 hours is a large number for a solo project — see §17 for a
suggested MVP subset that cuts this substantially without abandoning
the architecture.

---

# 2. Dependency Overview

```
P0 Foundations
  │
  ├──────────────► P1 Schema ─────────────┐
  │                    │                    │
  │                    ▼                    ▼
  ├──────────────► P3 QueryServer      P2 Storage
  │                    │                    │
  └──────────────► P7 Bridge (mock)         │
                       │                    │
        P1 + P3 ───────┤                    │
             │          ▼                    │
             └──► P4 Blueprints              │
             │          │                    │
             └──► P5 Operation Logic         │
                        │                    │
                P4+P5+P2+P3 ─────────────────┤
                        │                    │
                        ▼                    │
                   P6 Compiler ◄──────────────┘
                        │
             P6 + P7 ───┤
                        ▼
                   P8 Runtime
                        │
              ┌─────────┴─────────┐
              ▼                   ▼
        P9 Analytics         P10 Editor UI
              │                   │
              └─────────┬─────────┘
                        ▼
              P11 Integration & Release
```

P3 (QueryServer) and P7 (Bridge, mock-backed) can start immediately
after P0 in parallel with P1/P2 — neither has a hard dependency on the
canonical schema being finished, only on their own fixture data (P3) or
trait definitions (P7).

---

# 3. Risk Register

| Risk | Affects | Notes |
|---|---|---|
| Sylvanas API function/event names, identity model, and threading constraints are unverified (Vol 9 §16) | SENT-7.8, SENT-11.6, possibly SENT-8.11 | Do not start SENT-7.8 until the live API reference has been checked line-by-line against §16's list |
| Overlay rendering backend (ImGui-style vs native Frame/XML) unresolved (Vol 9 §7) | SENT-7.3, all of Phase 10 | Mitigated by design — RenderSurface abstraction means Phase 10 can build/test headless regardless |
| Stage 6 cross-Operation optimizer (SENT-6.6, SENT-6.7) is the single largest concentration of compiler complexity | Phase 6 timeline | Consider shipping adjacency-merge only (SENT-6.6) first; reordering (SENT-6.7) is separable and lower-value per Operation authored |
| 673-hour total is a large solo-developer undertaking | Whole project | See §17 for a scoped-down MVP path |
| Fixture Mangos DB (SENT-0.5) may not represent real production DB edge cases (unusual quest chains, multi-role NPCs, sparse zones) | All of Phase 3, indirectly Phase 6 | Budget time to re-test Phase 3 tickets against a real Mangos TBC DB before Phase 11 |

---

# Phase 0 — Foundations & Scaffolding

**Goal:** a buildable, testable, documented skeleton before any ADR
volume's actual logic gets written.

### SENT-0.1 — Cargo Workspace Initialization
ADR: — (project convention)
Depends: none
Description: Stand up the top-level Cargo workspace with stub crates
for every major subsystem identified across the ADR suite.
Acceptance Criteria:
- [ ] Workspace builds with `cargo build --workspace`
- [ ] Stub crates exist: sentinel-common, sentinel-schema,
      sentinel-profile-io, sentinel-queryserver, sentinel-blueprints,
      sentinel-compiler, sentinel-bridge, sentinel-runtime,
      sentinel-analytics-server, sentinel-editor
- [ ] Each crate's Cargo.toml doc-comment states its owning ADR volume(s)
Estimate: 3h

### SENT-0.2 — CI Pipeline
ADR: —
Depends: SENT-0.1
Acceptance Criteria:
- [ ] fmt check, clippy, build, and test all run on every push
- [ ] CI status badge added to README
- [ ] A deliberately broken PR is used once to confirm the pipeline
      actually fails red
Estimate: 4h

### SENT-0.3 — Shared Common Crate
ADR: — (supports 005, 007's DateTime/Duration/Uuid usage throughout)
Depends: SENT-0.1
Acceptance Criteria:
- [ ] Uuid, DateTime<Utc>, Duration serde helpers implemented once,
      reused everywhere rather than reimplemented per crate
- [ ] Round-trip serialization tests for each helper
Estimate: 3h

### SENT-0.4 — ADR Citation Lint
ADR: — (project convention established in the companion agent-build prompt)
Depends: SENT-0.2
Acceptance Criteria:
- [ ] CI script flags a new `pub struct`/`pub enum` lacking a doc
      comment citing an ADR volume/section
- [ ] Script documented in CONTRIBUTING.md
- [ ] Verified to actually fail on a deliberately uncited test struct
Estimate: 4h

### SENT-0.5 — Mangos TBC Fixture Database
ADR: — (supports Phase 3 and Phase 6 testing)
Depends: SENT-0.1
Acceptance Criteria:
- [ ] Checked-in SQLite fixture covering at minimum the Northshire /
      Goldshire quest chain used in Volume 7 §21 and Volume 8 §18
- [ ] Schema documented in a fixture README
- [ ] Fixture loads in under 50ms
Estimate: 5h

### SENT-0.6 — Developer Environment Documentation
ADR: — (supports Volume 1 §15's authoring-focused success criteria by making the dev side equally frictionless)
Depends: SENT-0.1 through 0.5
Acceptance Criteria:
- [ ] README covers build, fixture DB usage, and running each service locally
- [ ] Links to all 11 ADR volumes with a one-line summary of each
Estimate: 2h

**Phase 0 total: 21h**

---

# Phase 1 — Canonical Schema

**Goal:** every struct Volume 5 and Volume 7 define, implemented,
serializable, and unit-tested — nothing else in the project can start
in earnest without this.

### SENT-1.1 — Root Profile, Metadata, ProfileSettings
ADR: 005 (Root Profile, Metadata, Profile Settings)
Depends: SENT-0.3
Acceptance Criteria:
- [ ] Profile, Metadata, ProfileSettings structs implemented with serde
- [ ] GameVersion, Faction, Race, Class, LevelRange types implemented
- [ ] Round-trip serialization test
Estimate: 4h

### SENT-1.2 — Revised Operation Struct
ADR: 007 §3 (supersedes 005's flat Operation)
Depends: SENT-1.1
Acceptance Criteria:
- [ ] Operation implements all nine fields from 007 §3
- [ ] `analytics` field marked `#[serde(skip)]` per 011 §15
- [ ] Unit test constructs a minimal Operation and round-trips every
      non-skipped field
Estimate: 5h

### SENT-1.3 — OperationGoal & GoalType
ADR: 007 §4
Depends: SENT-1.2
Acceptance Criteria:
- [ ] All 11 GoalType variants implemented
- [ ] OperationGoal (weight, required) implemented
- [ ] Serde tagging strategy documented and matches the `type:` shape
      shown in Volume 11 §6's example YAML
Estimate: 3h

### SENT-1.4 — Entry/Exit Conditions & Condition Enum
ADR: 005 (Conditions), 007 §6–7
Depends: SENT-1.2
Acceptance Criteria:
- [ ] Condition enum includes both 005's original variants and 007
      §6's additions (OperationCompleted, FactionIs, RaceIs, etc.)
- [ ] ExitConditions (success/failure/abort) implemented
- [ ] Exhaustive-match test ensures no variant is silently unhandled
Estimate: 5h

### SENT-1.5 — OptimizationPolicy & CompletionMetrics
ADR: 007 §8–9
Depends: SENT-1.2
Acceptance Criteria:
- [ ] Both structs implemented
- [ ] Defaults match the Northshire example values in 007 §21
Estimate: 2h

### SENT-1.6 — OperationDependency & DependencyType
ADR: 007 §10
Depends: SENT-1.2
Acceptance Criteria:
- [ ] Struct + all four DependencyType variants implemented
- [ ] Unit test per variant
Estimate: 2h

### SENT-1.7 — Action, ActionPayload & Primitive Payload Structs
ADR: 005 (Action, Action Payload, and every per-action struct)
Depends: SENT-1.1
Acceptance Criteria:
- [ ] Action struct + RetryPolicy implemented
- [ ] All 23 ActionPayload variants implemented
- [ ] Every payload struct (PickupQuestAction through DeathSkip)
      implemented with at least one construction unit test each
Estimate: 10h

### SENT-1.8 — Reference & Value Types
ADR: 005 (NPC Reference, Quest Reference, Vendor Entry, Waypoint, Path, Polygon, Variable, VariableValue)
Depends: SENT-1.1
Acceptance Criteria:
- [ ] All eight types implemented
- [ ] Waypoint includes a distance-to helper
- [ ] Polygon includes a point-in-polygon helper (needed by SENT-3.8
      and SENT-6.6/6.7 later)
Estimate: 5h

### SENT-1.9 — Analytics & OperationAnalytics Structs
ADR: 005 (Analytics), 007 §19
Depends: SENT-1.2, SENT-1.8
Acceptance Criteria:
- [ ] Both structs implemented, both marked `#[serde(skip)]` on their
      owning parent per 011 §15
- [ ] Load-time hydration hook point stubbed for Phase 9 to fill in
Estimate: 2h

### SENT-1.10 — Schema Version Constants & Migration Registry Skeleton
ADR: 005 (Schema Versioning), 008 §14, 011 §12
Depends: SENT-1.1
Acceptance Criteria:
- [ ] schema_version constant defined
- [ ] Empty MigrationRegistry implemented, ready for Phase 2 to
      populate real migrations against
Estimate: 3h

**Phase 1 total: 41h**

---

# Phase 2 — Profile Storage & File I/O

**Goal:** an authored Profile can be written to and read back from disk
exactly as Volume 11 specifies, with dirty-tracked partial saves.

### SENT-2.1 — YAML Serialization Adapter Layer
ADR: 011 §2
Depends: SENT-1.1 through 1.10
Acceptance Criteria:
- [ ] YAML (de)serialization wired for every Phase 1 schema type
- [ ] Golden-file test serializes the Volume 7 §21 Northshire example
      and diffs against a checked-in fixture
Estimate: 4h

### SENT-2.2 — Tier 1 On-Disk Reference Types
ADR: 011 §8
Depends: SENT-2.1
Acceptance Criteria:
- [ ] Lightweight `{ entry: u32 }`-style reference shapes implemented
      separately from the Tier 2 (Volume 5) shapes
- [ ] Documented as the authored, on-disk representation
Estimate: 3h

### SENT-2.3 — Workspace & Manifest Read/Write
ADR: 011 §3, §5
Depends: SENT-2.1
Acceptance Criteria:
- [ ] workspace.yaml and profile.yaml read/write match 011 §5's example
- [ ] Round-trip test
Estimate: 4h

### SENT-2.4 — Operation File Read/Write
ADR: 011 §6
Depends: SENT-2.2, SENT-2.3
Acceptance Criteria:
- [ ] One-file-per-Operation read/write implemented
- [ ] Filename derives from a slug of the Operation's name at creation,
      stable across renames of the Operation itself
- [ ] Round-trip test against the full Northshire example in 011 §6
Estimate: 5h

### SENT-2.5 — Shared Library Files
ADR: 011 §7
Depends: SENT-2.2
Acceptance Criteria:
- [ ] npc_library.yaml, quest_library.yaml, vendor_library.yaml
      read/write implemented
- [ ] Both single-file and directory-per-entry forms supported per
      011 §14's scale escape hatch, transparently interchangeable
Estimate: 5h

### SENT-2.6 — Blueprint Library File I/O
ADR: 011 §3, 006 §6–8
Depends: SENT-2.3
Acceptance Criteria:
- [ ] Workspace-level blueprints/ directory read/write implemented
- [ ] Blueprint struct (stubbed if Phase 4 not yet started) serializes
      cleanly
Estimate: 3h

### SENT-2.7 — Tier 1 → Tier 2 Reference Resolution (Load)
ADR: 011 §8, §10
Depends: SENT-2.4, SENT-2.5
Acceptance Criteria:
- [ ] Load pipeline resolves every on-disk reference against loaded
      libraries into full Tier 2 structs
- [ ] An unresolvable reference produces a clear error at load time,
      before any Compiler stage runs
Estimate: 6h

### SENT-2.8 — Tier 2 → Tier 1 Lowering (Save)
ADR: 011 §8, §11
Depends: SENT-2.7
Acceptance Criteria:
- [ ] Save pipeline lowers hydrated structs back to on-disk shape
      without data loss
- [ ] load → save → load on an unmodified Profile produces
      byte-identical files
Estimate: 5h

### SENT-2.9 — Dirty Tracking & Partial Save
ADR: 002 §13, 011 §11
Depends: SENT-2.8
Acceptance Criteria:
- [ ] Only dirty Operations/libraries/manifest are rewritten on save
- [ ] Test confirms an untouched Operation's file mtime and content
      are unchanged after saving an edit to a different Operation
Estimate: 5h

### SENT-2.10 — Atomic Writes & Advisory Locking
ADR: 011 §11, §13
Depends: SENT-2.8
Acceptance Criteria:
- [ ] Writes go through temp-file-then-rename
- [ ] Simulated crash mid-write never leaves a corrupt file
- [ ] `.profile.lock` implemented with stale-lock timeout
Estimate: 5h

### SENT-2.11 — Per-File Schema Migration Engine
ADR: 008 §14, 011 §12
Depends: SENT-2.7, SENT-1.10
Acceptance Criteria:
- [ ] Migration runs per-file against each file's own declared (or
      inherited) schema_version
- [ ] One no-op migration and one real test migration exercised
      end-to-end
Estimate: 6h

**Phase 2 total: 51h**

---

# Phase 3 — QueryServer

**Goal:** every endpoint Volume 4 specifies, backed by the fixture DB,
meeting the stated performance targets.

### SENT-3.1 — Axum Service Scaffold & API Versioning
ADR: 004 §1, §5, §6
Depends: SENT-0.1
Acceptance Criteria:
- [ ] `/api/v1/` routing scaffold, health check endpoint
- [ ] Response envelope conventions documented
Estimate: 3h

### SENT-3.2 — SQLite Read Layer
ADR: 004 §28
Depends: SENT-3.1, SENT-0.5
Acceptance Criteria:
- [ ] Prepared-statement query layer over the fixture DB
- [ ] Connection pooling
- [ ] No raw SQL used outside the sqlite module, per 004 §28
Estimate: 5h

### SENT-3.3 — Quest Endpoints
ADR: 004 §7
Depends: SENT-3.2
Acceptance Criteria:
- [ ] Search, Details, Chain, Near all implemented matching 004 §7's examples
- [ ] Integration tests against the fixture DB
Estimate: 6h

### SENT-3.4 — NPC Endpoints
ADR: 004 §8
Depends: SENT-3.2
Acceptance Criteria:
- [ ] Lookup, Search, Near implemented
- [ ] Multi-role NPC aggregation tested
Estimate: 5h

### SENT-3.5 — Creature Endpoints & Spawn Locations
ADR: 004 §9
Depends: SENT-3.2
Acceptance Criteria:
- [ ] Search + spawn location endpoints implemented
- [ ] Density/respawn/average-count computation tested against fixture
Estimate: 5h

### SENT-3.6 — Vendor & Trainer Endpoints
ADR: 004 §10–11
Depends: SENT-3.2
Acceptance Criteria:
- [ ] Both endpoints implemented and verified against fixture data
Estimate: 4h

### SENT-3.7 — Flight Master, Mailbox, Inn Endpoints
ADR: 004 §12–14
Depends: SENT-3.2
Acceptance Criteria:
- [ ] All three endpoints implemented
Estimate: 3h

### SENT-3.8 — Area Query & Polygon Analysis
ADR: 004 §15–16
Depends: SENT-3.2, SENT-1.8
Acceptance Criteria:
- [ ] POST /areas/query implemented
- [ ] Density/respawn/unique-creature/elite/aggro-risk computation
      implemented per 004 §16
- [ ] Tested against a hand-drawn fixture polygon
Estimate: 8h

### SENT-3.9 — Route Analysis
ADR: 004 §17
Depends: SENT-3.2
Acceptance Criteria:
- [ ] Distance/travel-time/zone-crossing computation implemented
- [ ] Output shape consumed cleanly by SENT-4.5 and SENT-6.6 later
Estimate: 5h

### SENT-3.10 — Quest Hub Analysis & Blueprint/Grind Suggestions
ADR: 004 §18, §21–22
Depends: SENT-3.3, SENT-3.4, SENT-3.6, SENT-3.7
Acceptance Criteria:
- [ ] Hub analysis aggregates nearby services per 004 §18
- [ ] Blueprint and grind suggestion endpoints implemented per 004 §21–22
Estimate: 6h

### SENT-3.11 — Loot Lookup & World Graph
ADR: 004 §23–24
Depends: SENT-3.2
Acceptance Criteria:
- [ ] Both endpoints implemented
- [ ] World graph traversal tested for a 3-hop chain (quest → NPC → vendor)
Estimate: 5h

### SENT-3.12 — Search Everywhere & Validation API
ADR: 004 §19–20
Depends: SENT-3.3 through 3.11
Acceptance Criteria:
- [ ] Unified search endpoint implemented
- [ ] POST /validate implemented, returning the shape the Compiler
      (Phase 6) will consume directly
Estimate: 5h

### SENT-3.13 — Caching Layer & Performance Verification
ADR: 004 §25–26
Depends: all prior Phase 3 tickets
Acceptance Criteria:
- [ ] LRU cache with 60s TTL wired across all endpoints
- [ ] Benchmark suite verifies every 004 §26 target against the
      fixture DB: NPC lookup <5ms, quest search <10ms, polygon query
      <40ms, spawn density <20ms, route analysis <20ms
Estimate: 6h

**Phase 3 total: 66h**

---

# Phase 4 — Blueprint System

**Goal:** every standard Blueprint from Volume 6 §32, fully expandable
in isolation.

### SENT-4.1 — Blueprint Struct & Parameter Types
ADR: 006 §6, §13
Depends: SENT-1.7
Acceptance Criteria:
- [ ] Blueprint struct implemented
- [ ] All parameter types from 006 §13 implemented, with required/optional flag
Estimate: 4h

### SENT-4.2 — Blueprint Definitions: Quest / Travel
ADR: 006 §5, §32
Depends: SENT-4.1
Acceptance Criteria:
- [ ] Quest Hub, Single Quest, Quest Chain, Turn-in Cluster, Travel
      Hub, Flight Unlock, Hearth Setup, Route Transition all defined
      as data matching 006 §32
Estimate: 6h

### SENT-4.3 — Blueprint Definitions: Combat / NPC Services
ADR: 006 §32
Depends: SENT-4.1
Acceptance Criteria:
- [ ] Grind Area, Named Mob Hunt, Rare Spawn Camp, Escort, Patrol,
      Vendor Stop, Trainer Stop, Repair Stop, Mailbox Stop, Bank Stop
      all defined as data
Estimate: 6h

### SENT-4.4 — Blueprint Definitions: Recovery / Utility
ADR: 006 §32
Depends: SENT-4.1
Acceptance Criteria:
- [ ] Death Skip, Corpse Recovery, Stuck Recovery Marker, Set
      Variable, Conditional Branch, Wait, Use Item, Gossip Sequence
      all defined as data
Estimate: 4h

### SENT-4.5 — Parameter Resolution & Smart Defaults
ADR: 006 §7, §16
Depends: SENT-4.1, SENT-3.4, SENT-3.6, SENT-3.7, SENT-3.9
Acceptance Criteria:
- [ ] Nearest vendor/trainer/flight master defaults resolve via
      QueryServer
- [ ] "Current target" default resolves via a stubbed Bridge call
      (real implementation deferred to Phase 7)
Estimate: 6h

### SENT-4.6 — Conditional Expansion
ADR: 006 §14–15
Depends: SENT-4.5
Acceptance Criteria:
- [ ] An unset optional parameter (e.g. Repair) results in the
      corresponding action being fully omitted from expansion output
- [ ] Test covers Quest Hub with Repair unset
Estimate: 3h

### SENT-4.7 — Nested Blueprint Composition
ADR: 006 §10, §26
Depends: SENT-4.2 through 4.6
Acceptance Criteria:
- [ ] A Blueprint composed of other Blueprints expands recursively,
      depth-first
- [ ] Cycle detection enforces a recursion depth limit with a clear error
Estimate: 6h

### SENT-4.8 — Blueprint Expansion Pipeline (Single Instance)
ADR: 006 §9, §27
Depends: SENT-4.7
Acceptance Criteria:
- [ ] Full pipeline implemented: Validate → Resolve References →
      Inject Runtime Actions → Optimize → Execution Graph
- [ ] `generated_from` provenance tagging implemented per 006 §25
Estimate: 6h

### SENT-4.9 — Blueprint Validation
ADR: 006 §17
Depends: SENT-4.8
Acceptance Criteria:
- [ ] All six checks from 006 §17 implemented: missing NPC, duplicate
      quest, unknown quest, no polygon, invalid target, missing vendor
Estimate: 4h

**Phase 4 total: 45h**

---

# Phase 5 — Operation System Logic

**Goal:** the behavioral half of Volume 7 — everything beyond the
struct definitions already covered in Phase 1.

### SENT-5.1 — Goal Coverage Checking (Static)
ADR: 007 §4–5, §15
Depends: SENT-1.3, SENT-1.7
Acceptance Criteria:
- [ ] Statically checkable goal types (CompleteQuest,
      CompleteQuestChain, AcquireItem, KillCount, UnlockFlightPath,
      LearnSpell) verified against an action list per 007 §15
- [ ] Non-checkable goals (ReachLevel, GainXp) flagged informational,
      not blocking
Estimate: 6h

### SENT-5.2 — Entry/Exit Condition Evaluation Engine
ADR: 007 §6–7
Depends: SENT-1.4
Acceptance Criteria:
- [ ] Condition tree evaluator implemented against a stubbed
      RuntimeContext-shaped input
- [ ] All Condition variants handled exhaustively
Estimate: 5h

### SENT-5.3 — Operation Dependency Graph Construction
ADR: 007 §10–11
Depends: SENT-1.6
Acceptance Criteria:
- [ ] Graph builder produces a directed graph from Operations'
      OperationDependency lists
- [ ] Test reproduces the Northshire→Goldshire→Westbrook/Eastvale
      example from 007 §11
Estimate: 5h

### SENT-5.4 — Cycle Detection & ExcludesWith Conflict Detection
ADR: 007 §10, 008 §7 (steps 2–3)
Depends: SENT-5.3
Acceptance Criteria:
- [ ] Cycle detection implemented as a hard error
- [ ] ExcludesWith conflict detection implemented, including the
      entry-condition-disjointness exception from 008 §7 step 3
Estimate: 5h

### SENT-5.5 — Topological Sort with Priority Tie-Breaking
ADR: 007 §10, 008 §7 (steps 4–5)
Depends: SENT-5.4
Acceptance Criteria:
- [ ] Sort implemented per 008 §7's ordering rules
- [ ] Deterministic across repeated runs on identical input
Estimate: 4h

### SENT-5.6 — Operation Lifecycle State Machine
ADR: 007 §13–14
Depends: SENT-5.2
Acceptance Criteria:
- [ ] OperationStatus transitions implemented
      (Locked→Ready→Active→{Completed,Failed,Aborted,Skipped})
- [ ] Skip reasons distinguished per 007 §14
Estimate: 5h

### SENT-5.7 — Sub-Operation Composition
ADR: 007 §17
Depends: SENT-5.1
Acceptance Criteria:
- [ ] A parent Operation's required-goal coverage computed as the
      union of its sub_operations' required goals
- [ ] Test covers a two-level Northshire split example
Estimate: 4h

**Phase 5 total: 34h**

---

# Phase 6 — The Compiler

**Goal:** all seven stages from Volume 8, in fixed order, producing a
verified-deterministic RuntimeProfile.

### SENT-6.1 — Stage 1: Structural Validation
ADR: 008 §4
Depends: SENT-1.7
Acceptance Criteria:
- [ ] All five checks from 008 §4 implemented
- [ ] Diagnostic codes namespaced C-1xxx per 008 §12
Estimate: 5h

### SENT-6.2 — Stage 2: Reference Resolution
ADR: 008 §5
Depends: SENT-3.3, SENT-3.4, SENT-3.6
Acceptance Criteria:
- [ ] Every reference type resolved against QueryServer exactly once
- [ ] Resolution cache implemented (keyed on entry_id + db_version)
- [ ] C-2xxx diagnostics on unresolvable references
Estimate: 7h

### SENT-6.3 — Stage 3: Blueprint Expansion (Profile-Wide)
ADR: 008 §6
Depends: SENT-4.8, SENT-6.2
Acceptance Criteria:
- [ ] Recursive expansion applied across every Operation in a Profile
- [ ] Expansion order determinism test (timeline order, depth-first nesting)
- [ ] C-3xxx diagnostics
Estimate: 6h

### SENT-6.4 — Stage 4: Operation Dependency Resolution
ADR: 008 §7
Depends: SENT-5.3, SENT-5.4, SENT-5.5
Acceptance Criteria:
- [ ] Dependency resolution wired as a Compiler stage on top of
      Phase 5's graph logic
- [ ] C-4xxx diagnostics for cycles and ExcludesWith conflicts
Estimate: 4h

### SENT-6.5 — Stage 5: Goal Coverage Validation
ADR: 008 §8
Depends: SENT-5.1, SENT-6.3
Acceptance Criteria:
- [ ] Mandatory goal coverage check wired as a Compiler stage
- [ ] Required-goal failure halts compilation
- [ ] Optional-goal gap produces a C-5xxx warning per 008 §8's example
Estimate: 5h

### SENT-6.6 — Stage 6: Cross-Operation Optimization — Adjacency Merge
ADR: 008 §9
Depends: SENT-6.4, SENT-3.9
Acceptance Criteria:
- [ ] Trailing/leading action merge implemented between adjacent
      Operations per 008 §9's Vendor/GoTo example
- [ ] Merge fires only between actually-adjacent Operations in compile
      order, never speculatively
Estimate: 8h

### SENT-6.7 — Stage 6: Cross-Operation Optimization — Reordering & Redundancy Removal
ADR: 008 §9
Depends: SENT-6.6
Acceptance Criteria:
- [ ] Consecutive Vendor+Repair collapse implemented
- [ ] Redundant GoTo removal implemented
- [ ] In-Operation reordering under `allow_reordering: true`
      implemented using route analysis
- [ ] Every rewrite re-validated against Stage 5's goal set
Estimate: 8h

### SENT-6.8 — Stage 7: Lowering to RuntimeProfile
ADR: 008 §10
Depends: SENT-6.7
Acceptance Criteria:
- [ ] RuntimeProfile / RuntimeOperation / RuntimeAction implemented
- [ ] `generated_from` provenance carried through from both Blueprint
      expansion and optimizer rewrites
- [ ] C-7xxx diagnostics
Estimate: 7h

### SENT-6.9 — Diagnostics System
ADR: 008 §12, 002 §19
Depends: SENT-6.1 through 6.8
Acceptance Criteria:
- [ ] Diagnostic format matches 002 §19, extended with stage
      attribution per 008 §12
- [ ] Severity levels enforced consistently across all seven stages
Estimate: 4h

### SENT-6.10 — Incremental Compilation & Dirty-Scoped Recompile
ADR: 008 §11, 002 §13
Depends: SENT-6.8, SENT-2.9
Acceptance Criteria:
- [ ] Editing a single Operation re-runs only the affected stages per
      008 §11's rules
- [ ] Benchmark shows recompile time scales with edit scope, not
      Profile size
Estimate: 8h

### SENT-6.11 — Compile Caching & Determinism Verification
ADR: 008 §15, §19
Depends: SENT-6.10
Acceptance Criteria:
- [ ] source_profile_hash-keyed compile cache implemented
- [ ] Property test verifies identical input + identical DB state
      always produces byte-identical RuntimeProfile output
Estimate: 6h

### SENT-6.12 — Integration Test: Northshire End-to-End
ADR: 008 §18
Depends: all prior Phase 6 tickets, SENT-0.5
Acceptance Criteria:
- [ ] The exact trace from 008 §18 implemented as a passing automated
      test (all seven stages, Northshire example)
- [ ] Asserts final action count, goal coverage, and at least one
      Stage 6 merge with Goldshire
Estimate: 6h

**Phase 6 total: 74h**

---

# Phase 7 — Sylvanas Bridge

**Goal:** the full trait surface from Volume 9, mock-backed and fully
testable, with real API binding clearly gated behind verification.

### SENT-7.1 — QuestClient Trait & Mock Implementation
ADR: 009 §4, §11
Depends: SENT-0.1
Acceptance Criteria:
- [ ] Trait implemented with placeholder types flagged pending
      verification (NpcHandle etc.)
- [ ] MockBridge quest-side implementation complete per 009 §11
Estimate: 5h

### SENT-7.2 — AddonsClient Trait & Mock Implementation
ADR: 009 §5, §11
Depends: SENT-0.1
Acceptance Criteria:
- [ ] Trait implemented
- [ ] MockBridge addons-side implementation with scripted
      position/target responses
Estimate: 5h

### SENT-7.3 — RenderSurface Trait (Abstract)
ADR: 009 §7
Depends: SENT-0.1
Acceptance Criteria:
- [ ] Trait implemented with a headless/no-op CI implementation
- [ ] Documented as blocked-pending-verification for the real backend
Estimate: 3h

### SENT-7.4 — Event Bridge Translation Table
ADR: 009 §6
Depends: SENT-7.2
Acceptance Criteria:
- [ ] Raw-to-semantic translation implemented for every mapping in
      009 §6
- [ ] Unit test per semantic event type
Estimate: 6h

### SENT-7.5 — Quest Log Diffing
ADR: 009 §6
Depends: SENT-7.1, SENT-7.4
Acceptance Criteria:
- [ ] Two-snapshot diffing disambiguates QuestAccepted vs
      QuestCompleted from a raw update signal
- [ ] Test covers simultaneous accept + complete-of-different-quest in
      one tick
Estimate: 5h

### SENT-7.6 — BridgeError Handling & Retry Semantics
ADR: 009 §10
Depends: SENT-7.1, SENT-7.2
Acceptance Criteria:
- [ ] BridgeError implemented
- [ ] ApiUnavailable routes to Operation-halt rather than blind retry
- [ ] Other errors route through the Action's RetryPolicy
Estimate: 4h

### SENT-7.7 — API Versioning & Drift Detection
ADR: 009 §12
Depends: SENT-7.1, SENT-7.2
Acceptance Criteria:
- [ ] SylvanasApiVersion trait implemented
- [ ] Startup version-mismatch check produces the exact actionable
      error format from 009 §12
Estimate: 4h

### SENT-7.8 — Real Sylvanas API Binding (BLOCKED)
ADR: 009 §16
Depends: SENT-7.1 through 7.7, external verification against
docs.project-sylvanas.net
Acceptance Criteria:
- [ ] Every item in 009 §16's checklist verified against the live API
      reference
- [ ] QuestClient/AddonsClient real implementations written against
      confirmed, not assumed, signatures
- [ ] **Do not start this ticket until §16 is resolved**
Estimate: 16h (rough floor — genuinely uncertain until §16 is closed)

**Phase 7 total: 48h**

---

# Phase 8 — Runtime Execution Engine

**Goal:** everything Volume 2 defines, wired to the Compiler's output
(Phase 6) and the Bridge (Phase 7).

### SENT-8.1 — Profile Manager
ADR: 002 §4
Depends: SENT-2.7, SENT-2.8, SENT-6.11
Acceptance Criteria:
- [ ] load/save/compile/validate/activate/deactivate all implemented,
      wiring Phase 2's storage to Phase 6's compiler
Estimate: 6h

### SENT-8.2 — Runtime Context & Variable Store
ADR: 002 §8–9
Depends: SENT-1.8
Acceptance Criteria:
- [ ] RuntimeContext implemented
- [ ] Variable Store is the sole mutator of shared runtime state, per 002 §8
Estimate: 5h

### SENT-8.3 — Event Dispatcher
ADR: 002 §10
Depends: SENT-7.4
Acceptance Criteria:
- [ ] Dispatcher consumes Bridge semantic events
- [ ] No-polling subscriber model implemented
Estimate: 5h

### SENT-8.4 — Operation Manager & Runtime Scheduler
ADR: 002 §5, §15–16
Depends: SENT-8.1, SENT-5.6
Acceptance Criteria:
- [ ] Operations execute independently per 002 §5
- [ ] Scheduler consumes only Operation/Action structures, never
      authoring UI concepts, per 002 §15
Estimate: 6h

### SENT-8.5 — Action Executor
ADR: 002 §6–7, 009 §9
Depends: SENT-8.3, SENT-7.1
Acceptance Criteria:
- [ ] Executor dispatches RuntimeAction payloads per 009 §9's mapping
- [ ] GoTo/KillTarget correctly handed off as goals, not executed
      directly, per 009 §9's explicit boundary
- [ ] Full Action Lifecycle implemented (Created through Completed)
Estimate: 8h

### SENT-8.6 — Runtime State Machine & Failure Recovery
ADR: 002 §7, §23
Depends: SENT-8.5
Acceptance Criteria:
- [ ] Idle/Ready/Executing/Waiting/Finished states implemented
- [ ] Recovering/Retry/Failed path implemented
- [ ] Failure hierarchy (Retry→Skip→Abort Operation→Abort Profile)
      implemented, configurable per Action
Estimate: 6h

### SENT-8.7 — Continuous Validation Service
ADR: 002 §11, 001 §12
Depends: SENT-6.1, SENT-8.1
Acceptance Criteria:
- [ ] Incremental validation revalidates only dirty Operations
- [ ] All four validation categories surfaced with 002 §19's format
Estimate: 6h

### SENT-8.8 — Hot Reload
ADR: 002 §12, 001 §5
Depends: SENT-8.1, SENT-8.7
Acceptance Criteria:
- [ ] Save→Compile→Validate→Generate→Swap pipeline implemented
- [ ] A failed validation leaves the previous compiled RuntimeProfile
      executing uninterrupted
Estimate: 6h

### SENT-8.9 — Undo/Redo Command Stack
ADR: 002 §14
Depends: SENT-1.7
Acceptance Criteria:
- [ ] Command-based (not snapshot-based) undo/redo implemented for
      every operation listed in 002 §14
- [ ] Unlimited history until save
Estimate: 6h

### SENT-8.10 — Dry Run Mode Integration
ADR: 002 §17, 010 §8
Depends: SENT-8.5, SENT-3.5, SENT-3.9
Acceptance Criteria:
- [ ] Dry Run scheduler path reuses the real Action Executor with
      Simulation Adapters substituted per 010 §8
- [ ] RunMode::DryRun tagged through to the Event Dispatcher
Estimate: 7h

### SENT-8.11 — Threading Model & Logging Streams
ADR: 002 §24, §20
Depends: SENT-8.1 through 8.10
Acceptance Criteria:
- [ ] Main/UI thread kept free of blocking work
- [ ] Separate worker threads for Validation, Compilation, QueryServer
      calls per 002 §24
- [ ] Three distinct, never-mixed log streams implemented
Estimate: 6h

**Phase 8 total: 67h**

---

# Phase 9 — Analytics & Telemetry

**Goal:** the full pipeline from Volume 10, from raw event ingest
through bottleneck detection and cross-version comparison.

### SENT-9.1 — Telemetry Event Model & SQLite Schema
ADR: 010 §3–5
Depends: SENT-0.3
Acceptance Criteria:
- [ ] TelemetryEvent / Run structs implemented
- [ ] runs, telemetry_events, rollup_cache tables created per 010 §5
Estimate: 4h

### SENT-9.2 — AnalyticsServer Scaffold & Ingest Endpoint
ADR: 010 §6
Depends: SENT-9.1
Acceptance Criteria:
- [ ] Axum service scaffold
- [ ] Batched POST /telemetry/events implemented matching 010 §6's
      example payload
Estimate: 5h

### SENT-9.3 — Telemetry Collector (Runtime-Side)
ADR: 010 §2, §16
Depends: SENT-8.3, SENT-9.2
Acceptance Criteria:
- [ ] Collector subscribes to the same Event Dispatcher every other
      subsystem uses, no privileged access
- [ ] Batches on timer + Operation boundaries
- [ ] A failed telemetry write never blocks Action execution
Estimate: 6h

### SENT-9.4 — Operation-Level Aggregation Queries
ADR: 010 §9
Depends: SENT-9.2
Acceptance Criteria:
- [ ] All seven OperationAnalytics fields computed correctly against a
      seeded fixture run set
Estimate: 6h

### SENT-9.5 — Bottleneck Detection
ADR: 010 §10
Depends: SENT-9.4, SENT-1.9
Acceptance Criteria:
- [ ] Algorithm matches 010 §10 exactly (25% margin, 5-run floor,
      authored-expectation-or-rolling-baseline fallback)
- [ ] Test confirms a synthetic bottleneck IS flagged and a 2-run
      anomaly is NOT
Estimate: 5h

### SENT-9.6 — Trend & Cross-Version Comparison Queries
ADR: 010 §11–12
Depends: SENT-9.4
Acceptance Criteria:
- [ ] Trend and Compare endpoints implemented matching 010 §11–12
- [ ] Comparison correctly filters by schema_version/compiler_version
Estimate: 6h

### SENT-9.7 — Retention & Rollup Background Job
ADR: 010 §7
Depends: SENT-9.1
Acceptance Criteria:
- [ ] 90-day raw retention with rollup-then-discard implemented
- [ ] rollup_cache rows verified reproducible from source
Estimate: 5h

### SENT-9.8 — Simulation Adapters (Per Action Type)
ADR: 010 §8
Depends: SENT-8.10, SENT-3.5, SENT-3.9
Acceptance Criteria:
- [ ] Adapters implemented for at minimum PickupQuestAction,
      GrindAreaAction, GoToAction, VendorAction, per 010 §8's examples
- [ ] Estimated-duration flagging distinguishes simulated from
      observed values
Estimate: 8h

### SENT-9.9 — Export & Purge Endpoints
ADR: 010 §15
Depends: SENT-9.2
Acceptance Criteria:
- [ ] JSON/CSV export implemented
- [ ] Purge is immediate and permanent
- [ ] No telemetry transmitted without explicit author action
Estimate: 4h

**Phase 9 total: 49h**

---

# Phase 10 — Editor UI

**Goal:** every panel from Volume 3, built and tested against the
headless RenderSurface, wired to every backing system from Phases 3–9.

### SENT-10.1 — Docking Layout Framework
ADR: 003 §3
Depends: SENT-7.3
Acceptance Criteria:
- [ ] Dockable, hideable, persisted-layout panel framework
- [ ] Default layout matches 003 §3
Estimate: 8h

### SENT-10.2 — Toolbar
ADR: 003 §4
Depends: SENT-10.1
Acceptance Criteria:
- [ ] All buttons wired to their subsystems (Save→SENT-8.1,
      Compile→Phase 6, Validate→SENT-8.7, Dry Run→SENT-8.10)
Estimate: 4h

### SENT-10.3 — Explorer Panel
ADR: 003 §5
Depends: SENT-10.1, SENT-2.3
Acceptance Criteria:
- [ ] Project tree implemented
- [ ] Drag/drop reordering updates the manifest's declarative list
      without affecting compile order
Estimate: 6h

### SENT-10.4 — World Map Rendering & Icons
ADR: 003 §6
Depends: SENT-10.1, SENT-7.2
Acceptance Criteria:
- [ ] Map surface with all icon types from 003 §6
- [ ] Player position sourced live via AddonsClient
Estimate: 8h

### SENT-10.5 — Map Interaction
ADR: 003 §7
Depends: SENT-10.4
Acceptance Criteria:
- [ ] All interaction modes implemented (select, multi-select,
      context menu, drag, duplicate, zoom, pan)
Estimate: 6h

### SENT-10.6 — Target Capture Panel
ADR: 003 §8, 009 §8
Depends: SENT-10.4, SENT-7.1, SENT-7.2, SENT-3.4
Acceptance Criteria:
- [ ] Full capture flow from 009 §8 implemented end-to-end
- [ ] "Already Exists" detection implemented
Estimate: 8h

### SENT-10.7 — NPC Library & Quest Browser Panels
ADR: 003 §9–10
Depends: SENT-10.6, SENT-3.3
Acceptance Criteria:
- [ ] Both panels implemented
- [ ] Add Pickup / Turn In / Both / Preview Chain wired to Action creation
Estimate: 8h

### SENT-10.8 — Timeline & Action Palette
ADR: 003 §11–12
Depends: SENT-10.1
Acceptance Criteria:
- [ ] Drag/drop/duplicate/delete/collapse/expand/color-coding on Timeline
- [ ] Full Action Palette per 003 §12's categories
Estimate: 10h

### SENT-10.9 — Inspector & Property Editors
ADR: 003 §13–14
Depends: SENT-10.8
Acceptance Criteria:
- [ ] Common property editor implemented
- [ ] A specific property editor exists for every ActionPayload variant
Estimate: 12h

### SENT-10.10 — Variables Panel
ADR: 003 §15
Depends: SENT-8.2
Acceptance Criteria:
- [ ] Create/delete/rename/watch implemented against the live
      Variable Store
Estimate: 3h

### SENT-10.11 — Validation Panel
ADR: 003 §16
Depends: SENT-8.7, SENT-6.9
Acceptance Criteria:
- [ ] Compiler and runtime diagnostics both surfaced
- [ ] Clicking a diagnostic selects the offending object in
      Explorer/Timeline/Map as appropriate
Estimate: 5h

### SENT-10.12 — Console (Editor/Compiler/Runtime Tabs)
ADR: 003 §17, 002 §20
Depends: SENT-8.11
Acceptance Criteria:
- [ ] Three separate, never-mixed log tabs implemented
Estimate: 3h

### SENT-10.13 — Dry Run Panel
ADR: 003 §18
Depends: SENT-8.10
Acceptance Criteria:
- [ ] Play/Pause/Step/Reset controls
- [ ] Per-Action success/simulated/skipped display
Estimate: 5h

### SENT-10.14 — Path Recorder & Polygon Recorder
ADR: 003 §19–20
Depends: SENT-10.4, SENT-3.8
Acceptance Criteria:
- [ ] Both recorders implemented
- [ ] Polygon recorder's stop-and-suggest flow implemented per 003 §20
Estimate: 8h

### SENT-10.15 — Context Menus
ADR: 003 §21
Depends: SENT-10.4, SENT-10.6
Acceptance Criteria:
- [ ] Both map and NPC context menus implemented
Estimate: 3h

### SENT-10.16 — Blueprint Library Panel
ADR: 003 §22, 006 §11, §18–21
Depends: SENT-4.1 through 4.9
Acceptance Criteria:
- [ ] Drag-to-timeline implemented
- [ ] Collapsed/expanded/greyed generated-action display per 006 §18
- [ ] Double-click-to-inspector editing per 006 §19–20; generated
      actions never directly editable, per 006 §21
Estimate: 8h

### SENT-10.17 — Multi-Select, Undo/Redo Wiring, Search Everywhere, Hotkeys
ADR: 003 §23–26
Depends: SENT-10.8, SENT-8.9
Acceptance Criteria:
- [ ] Bulk edit implemented
- [ ] Undo/Redo UI wired to the runtime command stack
- [ ] Ctrl+P search across NPCs/quests/vendors/waypoints/variables/operations
- [ ] All hotkeys from 003 §26 bound
Estimate: 8h

### SENT-10.18 — Analytics Panel
ADR: 010 §14, 003 §5
Depends: SENT-9.4, SENT-9.5, SENT-9.6
Acceptance Criteria:
- [ ] Operation list with live metrics per 010 §14's mockup
- [ ] Drill-down to Action-level bottleneck, jumping to the flagged
      Action in Timeline
- [ ] Compare Versions and Export/Purge wired to SENT-9.6 / SENT-9.9
Estimate: 8h

**Phase 10 total: 121h**

---

# Phase 11 — Integration, Hardening & Release

**Goal:** prove the whole system works together, then close out every
open risk.

### SENT-11.1 — Full End-to-End Integration Test Suite
ADR: all volumes
Depends: all prior phases
Acceptance Criteria:
- [ ] A multi-Operation Profile (Northshire + Goldshire minimum)
      authored, saved, loaded, compiled, and Dry Run end-to-end as one
      automated test
- [ ] Covers Stage 6 cross-Operation merging observably taking effect
Estimate: 12h

### SENT-11.2 — Performance Benchmarking Pass
ADR: 004 §26, 008, 006 §22–23
Depends: SENT-11.1
Acceptance Criteria:
- [ ] Full-workspace benchmark suite covering QueryServer targets,
      incremental compile time, and UI responsiveness under a
      realistic Profile (50+ Operations)
Estimate: 8h

### SENT-11.3 — Diagnostics & Error Message UX Pass
ADR: 002 §19, 008 §12
Depends: SENT-11.1
Acceptance Criteria:
- [ ] Every diagnostic code in the system reviewed for clarity and an
      actionable Suggested Fix field
Estimate: 6h

### SENT-11.4 — Module-Level CLAUDE.md Documentation
ADR: — (project convention)
Depends: SENT-11.1
Acceptance Criteria:
- [ ] Each crate has a CLAUDE.md summarizing purpose, owning ADR
      volume(s), and key invariants
Estimate: 6h

### SENT-11.5 — Dogfood Profile: Human 1–10
ADR: 001 §15
Depends: SENT-10.1 through 10.18
Acceptance Criteria:
- [ ] A complete Human 1–10 leveling Profile authored entirely through
      the editor, zero manual JSON/YAML/coordinate editing — satisfying
      Volume 1 §15's literal success criterion
Estimate: 10h

### SENT-11.6 — Real Sylvanas API Verification & Reconciliation
ADR: 009 §16
Depends: SENT-7.8
Acceptance Criteria:
- [ ] Every placeholder from 009 §16 replaced with confirmed values
- [ ] Any wrong architectural assumption documented as an addendum,
      not silently patched over
Estimate: 8h (plus whatever SENT-7.8 surfaces)

### SENT-11.7 — Release Readiness Review
ADR: all volumes
Depends: all prior tickets
Acceptance Criteria:
- [ ] Every ticket's acceptance criteria re-verified in one pass
- [ ] Every open item in §3's Risk Register re-assessed and either
      resolved or explicitly accepted
Estimate: 6h

**Phase 11 total: 56h**

---

# 17. Suggested MVP Sequencing

673 hours is the full architecture. If the goal is a working vertical
slice sooner, this subset preserves every architectural boundary while
deferring breadth:

```
Full Phase 0, 1          — non-negotiable, everything depends on these
Phase 2, trimmed          — single-file profile only, skip the
                            directory-per-entry escape hatch (§14)
Phase 3, trimmed          — Quest/NPC/Vendor endpoints only; defer
                            grind suggestions, world graph, blueprint
                            suggestions
Phase 4, trimmed          — Quest Hub + Vendor Stop blueprints only
Full Phase 5               — needed for Compiler correctness regardless
                            of scope
Phase 6, trimmed          — ship Stage 6 with adjacency-merge
                            (SENT-6.6) only; defer reordering
                            (SENT-6.7)
Phase 7, mock-only         — defer SENT-7.8 (real API binding) until
                            after §16 is independently verified
Full Phase 8               — the runtime engine doesn't have a
                            meaningful smaller version
Phase 9, deferred entirely — ship without analytics first; the system
                            is fully functional without it
Phase 10, trimmed         — Explorer, World Map, Capture, Timeline,
                            Inspector, Validation panel only; defer
                            Analytics panel, Search Everywhere, and
                            bulk-edit polish
Phase 11, trimmed         — integration test + dogfood profile only;
                            defer the performance pass until scope is
                            closer to final
```

This roughly halves the ticket count and total hours while still
proving every layer of the architecture end to end — the deferred
pieces (Analytics, real Sylvanas binding, full UI polish, Stage 6
reordering) are all additive on top of a working core, not structural
prerequisites for it.

---

End of Implementation Tickets
