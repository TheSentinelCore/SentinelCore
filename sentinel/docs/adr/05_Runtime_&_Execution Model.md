
# 05 Runtime & Execution Model

## ADR-500

Purpose

Defines the complete execution model for Sentinel Questing.

This document is the contract between:

-   Editor
-   Importer
-   Validator
-   Compiler
-   Runtime
-   QueryServer
-   Project Sylvanas

No implementation may violate this document.

----------

# Part 1

Execution Boundary

This answers ambiguity D.

Define:

```
Rust

↓

Sentinel Project

↓

Compiler

↓

Runtime JSON

↓

Lua Runtime

↓

Project Sylvanas APIs
```

Explicitly state:

-   Rust NEVER executes quests.
-   Rust NEVER calls Sylvanas.
-   Rust NEVER knows runtime state.
-   Lua NEVER edits projects.
-   Lua NEVER compiles.
-   Lua NEVER validates.

Only Runtime JSON crosses the boundary.

----------

# Part 2

Runtime Profile Schema

Define:

```
RuntimeProfile

RuntimeOperation

RuntimeAction

RuntimeVariable

RuntimeCondition

RuntimeArea

RuntimeNPC

RuntimeQuest

RuntimeWaypoint
```

Every ID already resolved.

No strings.

No references.

No compiler metadata.

No editor metadata.

No comments.

No diagnostics.

Pure execution.

----------

# Part 3

Compiler Lowering Rules

This answers ambiguity A.

Every Project Action becomes one Runtime Action.

Example

```
AcceptQuestAction

↓

RuntimeAcceptQuest
```

Travel

↓

RuntimeTravel

Blueprint

↓

Expanded Actions

Condition

↓

RuntimeCondition

Quest Reference

↓

QuestID

NPC Reference

↓

EntryID

Area

↓

RuntimePolygon

Everything resolved.

----------

# Part 4

Complete Runtime Actions

This answers ambiguity B.

Define payloads for all actions.

Instead of only nine.

For example:

```
RuntimeTravel

RuntimeAcceptQuest

RuntimeTurnInQuest

RuntimeVendor

RuntimeRepair

RuntimeTrain

RuntimeInteractNPC

RuntimeUseItem

RuntimeMailbox

RuntimeBank

RuntimeWait

RuntimeEscort

RuntimePatrol

RuntimeCondition

RuntimeSetVariable

RuntimeComment

RuntimeGrind

RuntimeKill

RuntimeLoot

RuntimeFlight

RuntimeHearth

RuntimeLearnFlightPath

RuntimeDeathSkip

RuntimeDungeonMarker
```

Each gets:

```
Fields

Validation

Execution semantics

Failure behavior

Retry policy
```

No ambiguity.

----------

# Part 5

QueryServer Responsibilities

This answers ambiguity C.

Define:

QueryServer IS part of Sentinel.

Not optional.

Workspace becomes

```
sentinel-questing/

queryserver/

queryclient/
```

QueryServer owns

-   SQLite
-   indexes
-   caching
-   world graph
-   coordinate conversion
-   quest chain resolution
-   spawn lookups
-   vendors
-   trainers
-   validation helpers

Editor

Compiler

Importer

Runtime

must NEVER read SQLite.

Only QueryServer.

----------

# Part 6

Execution State

Define runtime save data.

For example

```
Current Operation

Current Action

Completed Quests

Runtime Variables

Temporary Variables

Visited Vendors

Flight Paths

Known Hearth

Execution History
```

Not part of Project.

Not part of Runtime Profile.

Separate save file.

----------

# Part 7

Hot Reload

Define exactly what happens.

Compile

↓

Generate Runtime JSON

↓

Lua detects change

↓

Validate version

↓

Swap profile

↓

Preserve variables

↓

Continue execution

No restart.

----------

# Part 8

Failure Model

Every RuntimeAction returns

```
Success

Retry

Blocked

Failed

Skipped
```

Compiler doesn't care.

Lua runtime handles.

----------

# Part 9

State Machine

Define

```
Idle

↓

Load

↓

Initialize

↓

Run

↓

Wait

↓

Run

↓

Pause

↓

Resume

↓

Finished

↓

Unload
```

----------

# Part 10

Acceptance Criteria

Exactly define what constitutes a valid runtime.

----------

## One thing I would **change** from the coding agent's recommendation

I would **not** extend `02_DATA_MODEL.md`.

Keep it as the **authoring model**.

Instead:

```
02_DATA_MODEL.md

↓

Authoring Model

(Editor)

---------------------

05_RUNTIME_AND_EXECUTION_MODEL.md

↓

Execution Model

(Runtime)
```

This mirrors how compilers work:

```
Source AST

↓

IR

↓

Machine Code
```

Your system becomes:

```
RestedXP

↓

Importer

↓

Project Model

↓

Compiler

↓

Runtime Model

↓

Lua Executor
```

That's an extremely clean architecture and one that's familiar to compiler engineers.

## After this

Your ADR set is complete:

```
00_PRD.md

Product requirements

----------------------------

01_ARCHITECTURE.md

High-level architecture

----------------------------

02_DATA_MODEL.md

Authoring schema

----------------------------

03_EDITOR_AND_IMPORTER.md

Authoring UX

----------------------------

04_IMPLEMENTATION_PLAN.md

Build order

----------------------------

05_RUNTIME_AND_EXECUTION_MODEL.md

Execution contract
```
