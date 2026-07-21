
# 01_ARCHITECTURE.md

## Sentinel Questing

### System Architecture Specification

**Version:** 1.0 Draft  
**Status:** Architecture Approved (Draft)

----------

# 1. Purpose

This document defines the complete software architecture for Sentinel Questing.

It serves as the single source of truth for:

-   System boundaries
    
-   Component responsibilities
    
-   Data flow
    
-   Runtime lifecycle
    
-   Public interfaces
    
-   Ownership
    
-   Dependencies
    
-   Compiler pipeline
    
-   Import pipeline
    

This document intentionally contains **no UI implementation details** (see `03_EDITOR_AND_IMPORTER.md`) and **no schema definitions** (see `02_DATA_MODEL.md`).

----------

# 2. High-Level Architecture

Sentinel follows a **compile-before-execute** architecture.

Nothing is executed directly from imported guides.

```text
                    RestedXP Guide
                           │
                           ▼
                  Import Pipeline
                           │
                           ▼
                  RestedXP AST
                           │
                           ▼
                Semantic Validation
                           │
                           ▼
                   QueryServer
                           │
                           ▼
                 Sentinel Project
                           │
                           ▼
                  Project Validator
                           │
                           ▼
                     Compiler
                           │
                           ▼
                 Runtime Profile
                           │
                           ▼
             Project Sylvanas Runtime

```

----------

# 3. Architectural Principles

----------

## 3.1 Single Source of Truth

There is only one editable representation.

```
Sentinel Project

```

Everything else is generated.

Never edit:

-   Runtime JSON
    
-   AST
    
-   Import metadata
    

----------

## 3.2 Compile Everything

Execution never consumes authoring data.

```
Author

↓

Project

↓

Compile

↓

Runtime

```

----------

## 3.3 Deterministic Runtime

The runtime never asks questions.

It simply executes.

No:

-   SQL
    
-   SQLite
    
-   Route generation
    
-   Quest optimization
    
-   NPC discovery
    

Those happen earlier.

----------

## 3.4 QueryServer Owns Game Knowledge

Editor

↓

HTTP

↓

QueryServer

↓

SQLite

Nothing except QueryServer understands the database schema.

----------

# 4. System Components

The system is divided into eight major subsystems.

```
Importer

QueryServer

Project

Compiler

Validator

Editor

Runtime

Persistence

```

----------

# 5. Component Responsibilities

----------

# 5.1 Importer

Purpose

Convert RestedXP guides into Sentinel Projects.

Responsibilities

-   Parse guide
    
-   Build AST
    
-   Validate syntax
    
-   Resolve directives
    
-   Preserve source mapping
    
-   Generate project
    

Inputs

```
RestedXP Guide

```

Outputs

```
Sentinel Project

```

Dependencies

QueryServer

Never depends on Runtime.

----------

# 5.2 QueryServer

Purpose

Provide semantic game information.

Responsibilities

Quest lookup

NPC lookup

Creature lookup

Trainer lookup

Vendor lookup

GameObject lookup

Spawn lookup

Quest chains

Quest prerequisites

Coordinates

Flight paths

Validation

Travel estimation

Future optimization

Data Source

```
tbcmangos.sqlite

```

Public Interface

REST API

No SQL exposed.

----------

# 5.3 Project

Purpose

Canonical editable representation.

Contains

Operations

NPC Library

Variables

Validation

Import metadata

Runtime settings

Compiled output reference

Every subsystem operates on Project.

----------

# 5.4 Validator

Purpose

Guarantee project correctness.

Validation occurs continuously.

Checks include

Duplicate NPCs

Duplicate Quests

Broken references

Circular conditions

Unknown variables

Missing coordinates

Quest chain errors

Invalid operation order

Unused assets

Validation never modifies data.

Only reports diagnostics.

----------

# 5.5 Compiler

Purpose

Generate runtime profile.

Responsibilities

Resolve references

Flatten operations

Expand blueprints

Normalize actions

Resolve coordinates

Optimize travel

Merge interactions

Remove editor metadata

Generate runtime JSON

Compiler owns optimization.

Runtime never optimizes.

----------

# 5.6 Runtime

Purpose

Execute compiled profile.

Runtime responsibilities

Load

Execute

Track progress

Resume

Variables

Conditions

Recovery

Hot reload

Runtime does NOT

Import

Validate

Optimize

Query SQLite

Discover NPCs

Generate routes

----------

# 5.7 Editor

Purpose

Human authoring environment.

Responsibilities

Import

Editing

Validation

Testing

Compilation

Preview

Project management

Editor never executes gameplay.

----------

# 5.8 Persistence

Stores

Projects

Compiled runtime

Import cache

Diagnostics

Settings

Session state

Everything serialized as JSON.

----------

# 6. Import Pipeline

```
Guide

↓

Lexer

↓

Tokens

↓

Parser

↓

AST

↓

Semantic Validation

↓

QueryServer Resolution

↓

Project Builder

↓

Project Validator

↓

Sentinel Project

```

----------

## Import Stages

### Stage 1

Lexical analysis

Converts text into tokens.

----------

### Stage 2

Parsing

Produces AST.

No database access.

----------

### Stage 3

Semantic Analysis

Checks

Labels

Branches

Conditions

Variables

Quest references

----------

### Stage 4

Query Resolution

Calls QueryServer.

Resolves

NPC

Quest

Coordinates

Spawn

Objectives

----------

### Stage 5

Project Generation

Creates normalized project.

----------

# 7. Compile Pipeline

```
Project

↓

Validation

↓

Reference Resolution

↓

Optimization

↓

Runtime Generation

↓

Runtime JSON

```

----------

## Optimization Passes

Pass 1

Reference resolution

----------

Pass 2

Coordinate expansion

----------

Pass 3

Merge travel

----------

Pass 4

Merge NPC interactions

----------

Pass 5

Expand blueprints

----------

Pass 6

Dead action removal

----------

Pass 7

Final validation

----------

Pass 8

Serialize runtime

----------

# 8. Runtime Pipeline

```
Load Runtime

↓

Initialize Variables

↓

Operation 1

↓

Action

↓

Condition

↓

Next Action

↓

Operation Complete

↓

Next Operation

↓

Profile Complete

```

Runtime executes only compiled actions.

----------

# 9. Data Ownership

Data

Owner

Quest Metadata

QueryServer

NPC Metadata

QueryServer

Coordinates

QueryServer

Import Metadata

Importer

Project

Editor

Runtime JSON

Compiler

Variables

Runtime

Progress

Runtime

Diagnostics

Validator

Ownership is exclusive.

No duplication.

----------

# 10. QueryServer Contract

The editor never queries SQLite directly.

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

Required endpoints

```
GET /quests/search

GET /quest/{id}

GET /npc/{entry}

GET /npc/search

GET /vendor/{entry}

GET /trainer/{entry}

GET /flight/{entry}

GET /object/{entry}

GET /creatures/polygon

POST /validate

POST /travel/estimate

```

Future endpoints

```
POST /route/optimize

POST /profile/analyze

GET /zone/{id}

```

----------

# 11. Runtime Lifecycle

```
Load

↓

Initialize

↓

Resume State

↓

Execute

↓

Save Progress

↓

Pause

↓

Resume

↓

Finish

```

No recompilation occurs.

----------

# 12. Threading Model

Importer

Background

Compiler

Background

Validator

Background

Editor

Main thread

Runtime

Runtime thread

QueryServer

HTTP worker threads

Editor never blocks.

----------

# 13. Error Handling

Importer

Recover when possible.

----------

Compiler

Fail compilation.

Never emit invalid runtime.

----------

Runtime

Stop current action.

Attempt recovery.

Never modify project.

----------

# 14. Hot Reload

```
Compile

↓

Replace Runtime

↓

Preserve Progress

↓

Resume

```

Supported

Variables

Completed quests

Completed operations

Current operation

Current action

Unsupported

Changing schema version

Changing action IDs

Breaking operation references

Those require restart.

----------

# 15. Logging

Subsystem-specific logs

Importer

Compiler

Validator

Editor

Runtime

QueryServer

Structured JSON logging.

Correlation IDs shared across subsystems.

----------

# 16. Extension Points

Designed for future support of:

-   Additional guide importers (while RestedXP is the only initial implementation)
    
-   Dungeon routing
    
-   Profession workflows
    
-   Gathering profiles
    
-   Blueprint libraries
    
-   Additional QueryServer data providers
    

These extensions must integrate through existing interfaces rather than bypassing the architecture.

----------

# 17. Architecture Decision Records (ADR)

### ADR-101

Importer outputs Projects.

Never Runtime.

----------

### ADR-102

Compiler owns optimization.

----------

### ADR-103

Runtime owns execution only.

----------

### ADR-104

QueryServer owns world knowledge.

----------

### ADR-105

Projects are immutable during execution.

Runtime maintains separate execution state.

----------

### ADR-106

Compiled Runtime Profiles are disposable artifacts.

Projects are the authoritative source and can always regenerate runtime output.

----------

# 18. Acceptance Criteria

The architecture is considered complete when:

-   A RestedXP guide can be imported into a valid Sentinel Project.
    
-   All game metadata is resolved exclusively through the QueryServer.
    
-   The Project can be validated independently of execution.
    
-   The Compiler produces a deterministic Runtime Profile.
    
-   The Runtime executes without requiring SQLite or guide parsing.
    
-   Hot reload replaces only the Runtime Profile while preserving execution state.
    
-   Every subsystem has a clearly defined ownership boundary with no overlapping responsibilities.
    

----------

**End of Document – `01_ARCHITECTURE.md`**

The next document, **`02_DATA_MODEL.md`**, will define the complete Project schema, every entity (Project, Operation, Action, NPCReference, QuestReference, Variables, Conditions, Blueprints), relationships, invariants, enums, and a full Human 1–5 example.
