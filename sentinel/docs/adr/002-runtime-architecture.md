# Quest Authoring IDE
## Volume 2 — Runtime Architecture

Version: 1.0
Status: Draft

---

# 1. Purpose

This document defines the runtime architecture of the Quest Authoring IDE and
its interaction with the existing Project Sylvanas quest execution system.

This document does **not** define combat, navigation, pathfinding or movement
algorithms.

Instead it defines:

- Runtime data model
- Execution lifecycle
- Action lifecycle
- Validation pipeline
- Hot reload
- Runtime state
- Authoring state
- Dry Run mode
- Interaction with the QueryServer

---

# 2. High-Level Architecture

```
                 Author

                   │

                   ▼

          In-Game Authoring UI

                   │

                   ▼

        Authoring Data Model (Editable)

                   │

            Compile + Validate

                   │

                   ▼

      Runtime Execution Profile (Immutable)

                   │

                   ▼

          Quest Execution Engine

                   │

                   ▼

      Existing Navigation / Combat Layers

                   │

                   ▼

                 World
```

**Key Principle**

The author edits one model.

The runtime executes another.

These are intentionally different.

---

# 3. Runtime Components

The runtime consists of eight major systems.

```
Runtime

├── Profile Manager
├── Operation Manager
├── Action Executor
├── Variable Store
├── Event Dispatcher
├── Validation Service
├── Query Client
└── Debug Console
```

Each component has a single responsibility.

---

# 4. Profile Manager

Responsibilities:

- Load profiles
- Save profiles
- Version migration
- Compile authoring model
- Hot reload
- Maintain active profile

Never executes actions.

Never performs navigation.

---

## Public Interface

```rust
trait ProfileManager {

    fn load(path);

    fn save(path);

    fn compile();

    fn validate();

    fn activate(profile_id);

    fn deactivate();

}
```

---

# 5. Operation Manager

Operations are independent execution blocks.

Example

```
Northshire

↓

Goldshire

↓

Eastvale

↓

Westbrook
```

Each operation owns

- actions
- variables
- local state
- diagnostics

Operations can be executed individually.

This dramatically improves testing.

---

# 6. Action Executor

The Action Executor is intentionally dumb.

Its responsibilities are:

```
Receive Action

↓

Execute

↓

Return Success

or

Return Failure
```

It never asks

"What should happen next?"

That decision already exists in the profile.

---

# 7. Action Lifecycle

Every action follows the same lifecycle.

```
Created

↓

Validated

↓

Compiled

↓

Queued

↓

Running

↓

Succeeded

or

Failed

↓

Completed
```

States are immutable once exited.

---

# Runtime State Machine

```
Idle

↓

Ready

↓

Executing

↓

Waiting

↓

Finished

↓

Idle
```

Errors transition to

```
Recovering

↓

Retry

↓

Executing
```

or

```
Failed
```

---

# 8. Runtime Context

Every executing profile has a Runtime Context.

```
RuntimeContext

Player

Variables

Completed Quests

Known NPCs

Known Objects

Inventory Snapshot

Current Operation

Current Action

Active Conditions

Diagnostics

Statistics
```

The Runtime Context is read-only for most systems.

Only the Variable Store may mutate shared state.

---

# 9. Variable Store

Variables replace hidden runtime flags.

Examples

```
HasFlightPath

BagSlots

VendorNeeded

RepairNeeded

CurrentChapter

Deaths

Gold

Food

Water
```

Variables are strongly typed.

```
Bool

Integer

Float

String

QuestID

NPCID

Position

Enum
```

---

# 10. Events

Everything communicates through events.

```
QuestAccepted

↓

InventoryChanged

↓

QuestCompleted

↓

NPCReached

↓

VendorVisited

↓

FlightLearned

↓

AreaEntered
```

No polling whenever possible.

---

# Event Pipeline

```
Game

↓

Sylvanas API

↓

Event Dispatcher

↓

Subscribers

↓

Runtime
```

---

# 11. Validation Pipeline

Validation occurs continuously.

```
Author edits profile

↓

Dirty Flag

↓

Incremental Validation

↓

Diagnostics

↓

UI Updates
```

No full recompilation after every edit.

Only affected operations are revalidated.

---

Validation Categories

## Structural

Missing IDs

Duplicate IDs

Broken references

---

## Logical

Turn In before Pickup

Impossible branch

Missing target

Unknown variable

---

## Database

NPC missing

Quest missing

Vendor missing

Object missing

---

## Runtime

Unreachable action

Infinite loop

Unused variable

Dead operation

---

# 12. Hot Reload

Hot Reload never interrupts execution immediately.

Pipeline

```
Save

↓

Compile

↓

Validate

↓

Generate Runtime

↓

Swap Profile

↓

Continue Execution
```

If validation fails

Runtime continues using previous compiled version.

---

# 13. Dirty Tracking

Every editable object has

```
Clean

Dirty

Compiled

Invalid
```

Only dirty objects are recompiled.

---

# 14. Undo / Redo

Editor uses command history.

```
Add Action

Move Action

Delete Action

Rename Operation

Capture NPC

Modify Variable
```

Every modification becomes a reversible command.

```
Undo Stack

Redo Stack
```

No snapshot cloning.

Commands are deterministic.

---

# 15. Runtime Scheduler

The scheduler only knows Operations.

```
Operation

↓

Action

↓

Action

↓

Action

↓

Complete
```

Scheduler never sees authoring UI.

---

# 16. Execution Queue

```
Current Action

Queued Actions

Completed Actions

Failed Actions
```

Failures remain visible for diagnostics.

---

# 17. Dry Run Mode

Dry Run uses exactly the same scheduler.

Difference

Movement

Combat

Interaction

are replaced with

Simulation Adapters.

Example

```
Pickup Quest

↓

Quest Exists?

↓

Yes

↓

Success
```

Instead of actually clicking NPCs.

---

# 18. Query Client

The runtime never queries SQLite directly.

Everything goes through QueryServer.

```
Runtime

↓

HTTP Client

↓

QueryServer

↓

SQLite
```

Benefits

- isolation
- caching
- reusable APIs
- easier testing

---

# 19. Diagnostics

Every validation message contains

```
Severity

Error Code

Message

Entity

Operation

Suggested Fix
```

Example

```
ERROR

Q1004

Turn In Quest

references NPC

not present in profile.

Suggested Fix

Capture NPC first.
```

---

# 20. Logging

Three log streams.

```
Editor

Compiler

Runtime
```

Never mixed.

---

# 21. Telemetry

Runtime records

```
Travel Distance

Deaths

Repairs

Vendor Visits

Quest Times

XP/hour

Gold/hour

Action Duration

Compile Time
```

Used for optimization only.

Never required for execution.

---

# 22. Profile States

```
Draft

↓

Validated

↓

Compiled

↓

Executing

↓

Paused

↓

Completed
```

Draft profiles cannot execute.

Only compiled profiles execute.

---

# 23. Failure Recovery

Failure hierarchy

```
Retry

↓

Skip

↓

Abort Operation

↓

Abort Profile
```

Configurable per action.

---

# 24. Threading Model

Recommended

Main Thread

- UI
- Sylvanas API

Worker Thread

- Validation

Worker Thread

- Compilation

Worker Thread

- QueryServer

UI remains responsive.

---

# 25. Lifetime Ownership

```
Workspace

└── Profile

    └── Operations

        └── Actions

            └── Runtime Instance
```

Runtime never mutates authoring objects.

Compiled runtime owns its own immutable copies.

---

# 26. Future Compatibility

This architecture intentionally mirrors a future desktop IDE.

Desktop IDE

↓

Same Compile Pipeline

↓

Same Runtime Profile

↓

Same Execution Engine

The runtime should not know whether a profile was authored
inside WoW or in an external editor.

---

# 27. Design Principles

✔ Immutable runtime

✔ Mutable authoring model

✔ Incremental validation

✔ Hot reload

✔ Strong typing

✔ Event-driven architecture

✔ No direct SQLite access

✔ Deterministic execution

✔ Compiler-owned optimization

✔ Runtime simplicity

---

# End of Volume 2
