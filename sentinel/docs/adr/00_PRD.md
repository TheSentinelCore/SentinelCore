
# 00_PRD.md

## Sentinel Questing

### Product Requirements Document (PRD)

**Version:** 1.0 Draft  
**Status:** Architecture Approved (Draft)  
**Target:** Project Sylvanas (TBC 2.4.3)

----------

# 1. Executive Summary

Sentinel Questing is an intelligent questing framework for Project Sylvanas.

Unlike Honorbuddy, Zygor, or RestedXP, Sentinel does **not** execute guide scripts directly.

Instead it introduces a project-based workflow:

```
RestedXP Guide

↓

Importer

↓

Sentinel Project

↓

Validation

↓

Compile

↓

Runtime Profile

↓

Project Sylvanas Executor

```

The author edits projects.

The bot executes compiled runtime profiles.

This separation is the foundation of the entire architecture.

----------

# 2. Vision

## Mission

Create the easiest questing profile ecosystem ever built.

Not merely another leveling bot.

Not merely another guide parser.

Instead:

> A complete authoring ecosystem capable of importing, validating, editing, compiling, testing and executing optimized leveling strategies.

The project should eventually support:

-   RestedXP importing
    
-   Manual editing
    
-   Runtime validation
    
-   QueryServer enrichment
    
-   Fast iteration
    
-   Hot reloading
    
-   Future expansion
    

without changing the runtime.

----------

# 3. Product Philosophy

Sentinel follows five core principles.

----------

## Principle 1

### Intent over implementation

Authors should describe:

```
Accept Quest

Travel

Kill Wolves

Turn In

```

Never

```
Waypoint

Waypoint

Waypoint

Waypoint

Waypoint

```

Navigation belongs to SentinelNav.

----------

## Principle 2

### Projects, not profiles

The smallest unit is NOT a profile.

It is a Project.

Example

```
Alliance Human

├── Operations

├── NPC Library

├── Variables

├── Import Metadata

├── Validation

├── Runtime Output

```

----------

## Principle 3

### Compile everything

Nothing executes directly.

Everything compiles.

```
Source

↓

Project

↓

Compile

↓

Runtime

```

----------

## Principle 4

### QueryServer owns game knowledge

SQLite never leaks into the editor.

Instead:

```
Editor

↓

HTTP

↓

QueryServer

↓

SQLite

```

The editor knows nothing about SQL.

----------

## Principle 5

### Runtime stays dumb

Runtime should not decide.

Runtime should execute.

All intelligence belongs inside:

Importer

Compiler

Validator

QueryServer

----------

# 4. Goals

## Primary Goals

✔ Import RestedXP guides

✔ Edit imported guides

✔ Validate profiles

✔ Compile runtime profiles

✔ Execute via Sylvanas

✔ Zero manual coordinate editing

✔ Fast iteration

✔ Hot reload

----------

## Secondary Goals

Support future:

Dungeon profiles

Profession profiles

Escort profiles

Grinding profiles

PvP routes

Gathering

----------

## Non Goals

The following are intentionally excluded.

❌ AI generated routes

❌ Dynamic pathfinding

❌ Navmesh editing

❌ Combat scripting

❌ Packet manipulation

❌ Memory editing

❌ WoW API dependence

These belong elsewhere.

----------

# 5. User Personas

## Profile Author

Creates leveling routes.

Imports RestedXP.

Edits operations.

Validates.

Compiles.

----------

## Advanced Author

Optimizes routes.

Creates custom operations.

Adds conditions.

Creates reusable blueprints.

----------

## Runtime User

Loads compiled profile.

Clicks Start.

Never edits anything.

----------

# 6. Existing Problems

## Honorbuddy

Problems

Huge XML

Hardcoded coordinates

Repeated NPCs

Impossible to maintain

No compiler

Weak validation

----------

## RestedXP

Strengths

Excellent routing

Years of optimization

Readable DSL

Weaknesses

Not designed for automation.

Not normalized.

No reusable assets.

No validation.

----------

## Zygor

Strengths

Massive guide library.

Weaknesses

Too dynamic.

Parser complexity.

Less deterministic.

----------

# 7. Sentinel Solution

Sentinel introduces:

Projects

↓

Operations

↓

Actions

↓

Compile

↓

Runtime

Instead of

Guide

↓

Execute

----------

# 8. High Level Workflow

```
Import RestedXP

↓

Parse

↓

AST

↓

QueryServer

↓

Validation

↓

Optimization

↓

Sentinel Project

↓

Edit

↓

Compile

↓

Runtime JSON

↓

Project Sylvanas

```

----------

# 9. Functional Requirements

## Importing

Must import:

Accept

Turn In

Goto

Complete

Kill

Loot

Trainer

Vendor

Repair

Flight Path

Use Item

Note

Sticky

Labels

Conditions

Class restrictions

Race restrictions

Level restrictions

----------

## Editing

Must support

Undo

Redo

Multi-select

Copy

Paste

Drag reorder

Search

Filter

Validation

Hot reload

----------

## Runtime

Must support

Operations

Variables

Conditions

Quest Actions

Travel

Interaction

Grind Areas

NPC references

----------

## Validation

Must detect

Missing NPC

Duplicate NPC

Missing Quest

Invalid order

Circular references

Unknown item

Broken chain

Unused variable

Impossible condition

----------

# 10. Non Functional Requirements

Startup

< 2 seconds

Import

Human 1-60

< 10 seconds

Compile

< 2 seconds

Memory

< 250MB

Hot Reload

< 500ms

----------

# 11. UX Goals

The editor should feel closer to:

Visual Studio

Unity

Rider

than

Notepad

or XML editing.

The author should rarely type IDs.

Everything should be searchable.

Everything should autocomplete.

----------

# 12. QueryServer Responsibilities

QueryServer owns

Quest lookup

NPC lookup

Object lookup

Vendor lookup

Trainer lookup

Creature lookup

Spawn lookup

Quest chains

Coordinates

Validation

Travel estimates

Future optimization

----------

# 13. Success Metrics

A successful implementation allows an author to:

Import Human 1–60

↓

Compile

↓

Run

↓

Edit Goldshire

↓

Compile

↓

Reload

↓

Continue

within minutes.

----------

# 14. MVP

Version 1 ships with

✔ RestedXP importer

✔ Human Alliance leveling

✔ Editor

✔ QueryServer

✔ Runtime compiler

✔ Runtime loader

----------

# 15. Future Versions

Version 2

Dungeon profiles

Escort editor

Blueprint library

Shared assets

----------

Version 3

Profession support

Gathering

Dynamic routing

Analytics

----------

# 16. Risks

Importer complexity

Mitigation

AST architecture

----------

SQLite schema changes

Mitigation

QueryServer abstraction

----------

Runtime divergence

Mitigation

Compiler ownership

----------

Guide updates

Mitigation

Source mapping

----------

# 17. Architecture Decision Records (ADR)

## ADR-001

Projects replace profiles.

**Reason**

Profiles become maintainable.

----------

## ADR-002

RestedXP is import-only.

**Reason**

Sentinel owns execution.

----------

## ADR-003

QueryServer owns world knowledge.

**Reason**

Editor stays independent of SQLite.

----------

## ADR-004

Runtime profiles are compiled artifacts.

**Reason**

Deterministic execution.

----------

## ADR-005

Runtime performs no optimization.

**Reason**

Compile-time optimization is easier to debug.

----------

## ADR-006

World coordinates are stored in compiled profiles.

**Reason**

The runtime should not resolve map coordinates or query world data during execution.

----------

## ADR-007

Operations are the primary authoring unit.

**Reason**

They mirror how humans think about leveling ("Northshire", "Goldshire", "Westfall") rather than individual guide steps.

----------

# 18. Acceptance Criteria

The project is considered successful when it can:

-   Import a RestedXP Human 1–5 guide into a Sentinel Project.
    
-   Resolve quests, NPCs, and world coordinates through the QueryServer.
    
-   Validate the imported project and surface any issues.
    
-   Allow the author to modify operations and actions in the in-game editor.
    
-   Compile the project into a deterministic runtime profile.
    
-   Execute the compiled profile using only the Project Sylvanas APIs.
    
-   Support hot-reloading of the compiled profile without restarting the client.
    

----------

**End of Document – 00_PRD.md**

The next document, **`01_ARCHITECTURE.md`**, will define every subsystem (Importer, QueryServer, Editor, Compiler, Runtime), their interfaces, data flow, and lifecycle in implementation-level detail.
