
### AI Implementation Roadmap

**Version:** 1.0  
**Status:** Implementation Ready

----------

# 1. Purpose

This document is written for AI coding agents.

Unlike a traditional project plan, this document is dependency-driven rather than milestone-driven.

Every phase produces a working subsystem.

No phase should leave the repository in a broken state.

----------

# 2. Guiding Principles

## Rule 1

Never build UI before the data model exists.

----------

## Rule 2

Never build runtime before compiler.

----------

## Rule 3

Never couple QueryServer to Editor.

----------

## Rule 4

Never edit compiled profiles.

----------

## Rule 5

Projects are always authoritative.

----------

# 3. Repository Layout

```
sentinel-questing/

├── editor/
│
├── importer/
│
├── compiler/
│
├── validator/
│
├── runtime/
│
├── shared/
│
├── queryclient/
│
├── schemas/
│
├── examples/
│
└── tests/
```

----------

# 4. Build Order

The order below is intentional.

```
Shared Models

↓

QueryClient

↓

Project Loader

↓

Importer

↓

Validator

↓

Compiler

↓

Runtime

↓

Editor

↓

Testing

↓

Optimization
```

Nothing should violate this dependency graph.

----------

# Phase 1

# Shared Infrastructure

Goal

Create every shared model.

Nothing graphical.

Nothing runtime.

Deliverables

```
Project

Operation

Action

NPC

Quest

Area

Variable

Position

Enums
```

Acceptance Criteria

-   JSON serialization works.
-   UUID generation works.
-   Schema validation passes.
-   Unit tests complete.

Estimated

⭐⭐

----------

# Phase 2

# QueryClient

Goal

Communicate with QueryServer.

Deliverables

```
HTTP Client

Caching

Retry

Error Handling

Search API

NPC API

Quest API

Object API
```

Acceptance

```
Search Quest

↓

Returns Quest

↓

Search NPC

↓

Returns NPC

↓

Search Object

↓

Returns Object
```

Estimated

⭐⭐⭐

----------

# Phase 3

# Project Loader

Goal

Load modular projects.

Deliverables

```
Load

Save

Create

Rename

Delete

Upgrade Schema
```

Acceptance

Open

↓

Modify

↓

Save

↓

Reload

↓

Identical

Estimated

⭐⭐

----------

# Phase 4

# RestedXP Importer

Largest subsystem.

Pipeline

```
Lexer

↓

Parser

↓

AST

↓

Semantic Validation

↓

Query Resolution

↓

Project Builder
```

Deliverables

Tokenizer

Grammar

Parser

AST

Diagnostics

Source Mapping

Acceptance

Human Guide

↓

Imports Successfully

Estimated

⭐⭐⭐⭐⭐

----------

# Phase 5

# Validator

Checks

Duplicate NPC

Missing NPC

Missing Quest

Circular Conditions

Unused Variables

Broken References

Duplicate Actions

Acceptance

Every error reported with:

```
Severity

Location

Message

Suggested Fix
```

Estimated

⭐⭐⭐

----------

# Phase 6

# Compiler

Pipeline

```
Project

↓

Normalize

↓

Resolve

↓

Optimize

↓

Generate Runtime
```

Deliverables

Reference Resolver

Blueprint Expansion

Coordinate Resolution

Optimization Passes

Serializer

Acceptance

Runtime JSON

Generated

Every Time

Deterministically

Estimated

⭐⭐⭐⭐⭐

----------

# Phase 7

# Runtime Loader

Responsibilities

Load Runtime

Resume

Save Progress

Variables

Conditions

Execution

Acceptance

Runtime executes compiled profile.

Estimated

⭐⭐⭐

----------

# Phase 8

# In-Game Editor

Subtasks

Project Explorer

Timeline

Inspector

Search

Capture

Area Recording

Travel Recording

Validation

Compile

Acceptance

Everything editable.

Estimated

⭐⭐⭐⭐⭐

----------

# Phase 9

# Testing

Tests

Importer

Compiler

Runtime

Serialization

Validation

Regression

Performance

Acceptance

100%

Pass

Estimated

⭐⭐⭐

----------

# Phase 10

# Optimization

Goals

Reduce compile time.

Reduce allocations.

Improve validation.

Improve UI responsiveness.

Acceptance

Large projects remain responsive.

----------

# 5. Parallelization Matrix

Not everything must be sequential.

```
Shared Models
      │
      ├──────────────┐
      │              │
QueryClient     Project Loader
      │              │
      └──────┬───────┘
             │
         Importer
             │
     ┌───────┴────────┐
     │                │
 Validator       Compiler
     │                │
     └───────┬────────┘
             │
         Runtime
             │
         Editor
             │
         Testing
```

Recommended AI agent allocation:

-   **Agent 1:** Shared Models + Project Loader
-   **Agent 2:** QueryClient + QueryServer integration
-   **Agent 3:** RestedXP Importer (lexer/parser/AST)
-   **Agent 4:** Validator + Compiler
-   **Agent 5:** Runtime Loader
-   **Agent 6:** In-Game Editor UI

----------

# 6. Coding Standards

## Rust

-   Stable toolchain only.
-   `serde` for serialization.
-   `uuid` for entity IDs.
-   `thiserror` for error types.
-   `tracing` for logging.

----------

## JSON

-   Pretty-printed in source projects.
-   Compact in compiled runtime.

----------

## Errors

Never return strings.

Always use typed errors.

Example

```
enum CompilerError {
    MissingNpc,
    MissingQuest,
    CircularReference,
    InvalidCoordinate,
}
```

----------

# 7. Performance Targets

Task

Target

Project Load

<100 ms

Save

<100 ms

Compile

<2 s

Validation

<200 ms

Import Human 1–60

<10 s

Search

<50 ms

Hot Reload

<500 ms

----------

# 8. Testing Strategy

## Unit Tests

-   Parser
-   AST
-   Validator
-   Compiler
-   Serialization

----------

## Integration Tests

-   QueryClient ↔ QueryServer
-   Importer ↔ Project Builder
-   Compiler ↔ Runtime Loader

----------

## End-to-End Tests

```
Import Guide

↓

Validate

↓

Compile

↓

Load Runtime

↓

Execute

↓

Finish
```

----------

## Regression Suite

Maintain a library of known RestedXP guides.

Every commit must verify that imported output remains stable unless an intentional compiler change is made.

----------

# 9. Risks & Mitigations

Risk

Mitigation

RestedXP grammar changes

Versioned parser and source mapping

Mangos schema differences

QueryServer abstraction layer

Large projects

Incremental loading and lazy validation

Runtime/editor divergence

Runtime only consumes compiled artifacts

Broken imports

Detailed diagnostics with line mapping

----------

# 10. Definition of Done

A release is considered complete when the following workflow succeeds without manual intervention:

```
Import RestedXP Guide
        │
        ▼
Build Sentinel Project
        │
        ▼
Validate
        │
        ▼
Edit In-Game
        │
        ▼
Compile
        │
        ▼
Hot Reload
        │
        ▼
Execute Successfully
        │
        ▼
Complete Leveling Route
```

Every stage must produce deterministic, repeatable results.

----------

# 11. AI Agent Guidelines

When using AI coding agents:

-   Never ask an agent to work across subsystem boundaries in a single task.
-   Give each agent one bounded responsibility (e.g., "implement QueryClient search endpoints").
-   Require tests with every implementation.
-   Merge only after passing regression tests.
-   Prefer incremental pull requests over large feature branches.

----------

# 12. Future Enhancements (Post-v1)

These are explicitly out of scope for the MVP but should be considered in future iterations:

-   Multi-profile projects (e.g., Alliance + Horde in one workspace)
-   Shared Blueprint marketplace
-   Visual route optimization suggestions
-   Collaborative editing
-   Automated profile benchmarking
-   Analytics dashboards
-   Additional guide importers beyond RestedXP
-   Live profile diffing against updated guide releases

----------

# 13. Final Architecture Summary

```
                  RestedXP Guide
                         │
                  (Importer)
                         │
                         ▼
                Sentinel Project
                         │
          ┌──────────────┴──────────────┐
          │                             │
      In-Game Editor               Validator
          │                             │
          └──────────────┬──────────────┘
                         ▼
                     Compiler
                         │
                         ▼
                 Runtime Profile
                         │
                         ▼
             Project Sylvanas Runtime

               ▲
               │
         QueryServer (HTTP)
               │
               ▼
          tbcmangos.sqlite
```

----------

# Acceptance Criteria

The implementation roadmap is complete when:

-   Every subsystem has a clearly defined build order.
-   Parallel work can proceed without architectural conflicts.
-   AI coding agents can be assigned bounded, dependency-aware tasks.
-   The complete import → edit → validate → compile → execute workflow is covered.
-   Future enhancements can be added without restructuring the core architecture.
