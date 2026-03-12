# Production Codex Prompt (SentinelQueryServer v1)

Use this prompt verbatim when implementing SentinelQueryServer.

```text
You are implementing SentinelQueryServer in this repository.

Scope lock:
- Implement SentinelQueryServer v1 only.
- Include only:
  - context
  - vendors
  - trainers
  - flight masters
  - innkeepers
- Do not implement quest APIs.

Hard constraints:
- TBC only.
- Canonical world identity uses cmangos IDs (`map_id`, `zone_id`, `area_id`).
- SQLite only.
- Source data is only `SentinelQueryServer/sql/database/tbcmangos.sql`.
- Startup must generate runtime DB if missing.
- Use sqlite CLI binary at `SentinelQueryServer/sql/tools/sqlite3.exe` for import execution.
- Fail-closed behavior for uncertainty and invalid contexts.
- No security/auth hardening in this phase.
- No locale parameter in API.
- Service is data-only; no pathfinding/path-cost logic.

Repository docs to follow as source of truth:
- `SentinelQueryServer/docs/PRD.md`
- `SentinelQueryServer/docs/TDD.md`
- `SentinelQueryServer/docs/DATA_MODEL.md`
- `SentinelQueryServer/docs/SENTINEL_QUERY_SERVER_ARCHITECTURE.md`
- `SentinelQueryServer/docs/API_DESIGN.md`
- `SentinelQueryServer/docs/IMPLEMENTATION_TICKETS.md`

Delivery requirements:
1. Implement tickets in dependency order from `SQS-001` through `SQS-014`.
2. Keep modules cohesive and testable.
3. Emit structured logs, metrics, and explicit error codes.
4. Ensure no fail-open critical path remains.
5. Add/update tests for every completed ticket.
6. Maintain deterministic ordering and pagination semantics.

Importer requirements:
- Sanitize MySQL dump syntax to SQLite-compatible SQL.
- Build into temp db and atomically swap.
- Validate required tables and manifest before marking service ready.

API requirements:
- Implement `/health` and `/api/v1/meta/dataset`.
- Implement context resolve endpoint with explicit `exact|partial|unresolved` semantics.
- Implement nearby/list endpoints for vendors/trainers/flight masters/innkeepers.
- Implement unified nearby endpoint for mixed entity types.

Quality gates:
- Deterministic responses for identical inputs and dataset.
- Clear fail-closed responses for invalid params and unresolved context.
- Startup should fail fast on invalid dataset/import errors.

Output format:
- Show ticket-by-ticket progress.
- For each ticket: files changed, tests added, acceptance criteria status.
- End with open risks and next recommended ticket.
```
