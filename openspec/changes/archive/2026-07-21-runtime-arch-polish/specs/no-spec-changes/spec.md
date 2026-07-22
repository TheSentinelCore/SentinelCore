# Delta for No Spec Changes — Runtime Architecture Polish

## Statement

This change is a **pure architecture/implementation refactor** covering ADR-017 Wave 4 (Tickets 15–18). It introduces **no new behavioral requirements** and **modifies no existing behavioral requirements**. The runtime contract as observable by callers remains unchanged.

| Ticket | Scope | Spec Impact |
|--------|-------|-------------|
| 15 | Extract `editor_ui.lua` from questing module | None — `toggle_editor()` API preserved; editor loads from separate subsystem path |
| 16 | File-watcher hot reload for profile JSON | None — opt-in behavior with no-observable-difference default |
| 17 | Variable init from profile JSON + SetVariable mapping | None — runtime internal plumbing; caller-facing contract unchanged |
| 18 | Complete `_serialize_state()` / `_load_save()` fields | None — persistence schema extension only; version 1 save files still load gracefully |

## Rationale

The four tickets address architectural violations (ADR-500 Part 1 — editor embedded in runtime), internal runtime hygiene (variable initialization, persistence completeness), and a quality-of-life feature (hot reload). None alter the observable behavior of any existing requirement: every existing scenario continues to pass without modification, and no new scenarios are needed.

## ADDED Requirements

None.

## MODIFIED Requirements

None.

## REMOVED Requirements

None.

## RENAMED Requirements

None.
