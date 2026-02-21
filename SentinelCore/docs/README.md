# SentinelCore Docs Index

This folder contains planning and execution docs for SentinelCore P0 -> P1.5.

## Files
- `PRD.md`: product scope, requirements, constraints, acceptance gates.
- `TDD.md`: technical design, runtime model, module boundaries, fail-closed policy.
- `DATA_MODEL.md`: canonical cmangos-based entities and indexing model.
- `ARCHITECTURE.md`: system architecture for SentinelCore and SentinelQueryServer integration.
- `NAVCLIENT_PARITY.md`: explicit NavClient-style parity conventions and future mode contract.
- `API_DESIGN.md`: SentinelQueryServer API contract (v1).
- `SENTINEL_QUERY_SERVER_ARCHITECTURE.md`: detailed SentinelQueryServer internal architecture and service design.
- `SCRIPTS_DATA_SCHEMA.md`: persistent file layout/schemas under `scripts_data/SentinelCore`.
- `IMPLEMENTATION_TICKETS.md`: dependency-ordered execution tickets.
- `CODEX_PROMPT.md`: production-ready implementation prompt.
- `smoke/SMOKE_SCENARIOS.md`: scripted smoke scenario list for P0->P1.5 lock.
- `../tests/run_all.lua`: ticket-indexed unit/integration/smoke runner (`SC-001`..`SC-014`).

## Locked Decisions
- TBC only.
- Canonical IDs from cmangos.
- No phased content.
- Fail closed on uncertainty.
- Vendor selection same canonical map_id only.
