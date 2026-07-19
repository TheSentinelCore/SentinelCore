# Skill Observations Log

## Observations

### 2026-07-15: Architecture Review for Grinding/Combat UI Improvements
- **Skill used**: improve-codebase-architecture
- **Observation**: The user requested improvements to grinding, grinding/combat UI, and related systems. Created an HTML report with 6 improvement candidates covering state machine unification, target selector deepening, UI consolidation, threat map enhancement, vendor pipeline extraction, and combat profile registry simplification.
- **Type**: Architecture improvement opportunity
- **Action**: User needs to select which candidate to explore further via grilling session

### 2026-07-16: Event-Driven Hierarchical Statechart for Quest Profiles (ADR-0004)
- **Skill used**: grill-with-docs / domain-modeling
- **Observation**: User wants to shift quest module from auto-generated plans to hand-authored declarative profiles. Decided on event-driven hierarchical statechart (SCXML-inspired) as execution model with parallel regions (Questing, Survival, Logistics), hierarchical states, guards, async actions, and history states. Created ADR-0004 and updated CONTEXT.md with new domain terms. Also decided: YAML DSL for authoring, routing policies instead of hardcoded waypoints, objective groups = state hierarchy + metadata, in-game visual editor as primary authoring tool, hybrid action registry (engine methods + inline Lua), Big Bang migration.
- **Type**: Architecture decision (hard to reverse, surprising without context, real trade-off)
- **Action**: Continue grilling on remaining design decisions: action registry details, in-game editor MVP scope, simulator/validation depth, first-profile validation strategy

