# SentinelQueryServer Implementation Tickets (v1)

## 1. Ticket Conventions
- ID format: `SQS-###`
- Each ticket includes acceptance criteria.
- Tickets must be implemented in dependency order.

## 2. Dependency Graph
`SQS-001 -> SQS-002 -> SQS-003 -> SQS-004 -> SQS-005 -> SQS-006 -> SQS-007 -> SQS-008 -> SQS-009 -> SQS-010 -> SQS-011 -> SQS-012 -> SQS-013 -> SQS-014`

## 3. Tickets
## SQS-001: Project Skeleton and Config Boot
Deliverables:
- Server skeleton and module layout.
- Typed config loader and validator.
- Startup state machine (`init`, `importing`, `ready`, `failed`).
Acceptance:
- Missing required config fails startup with explicit error.

## SQS-002: MySQL Dump Sanitizer
Deliverables:
- Deterministic sanitizer for `tbcmangos.sql` -> SQLite-compatible SQL.
- Fixture-based transform tests for known MySQL directives.
Acceptance:
- Sanitizer output is accepted by sqlite parser for fixture datasets.

## SQS-003: SQLite CLI Import Pipeline
Deliverables:
- Import runner using `SentinelQueryServer/sql/tools/sqlite3.exe`.
- Temp db generation and atomic swap.
- Import logging and failure propagation.
Acceptance:
- Missing active DB triggers successful build from dump.
- Failed import leaves previous active DB untouched.

## SQS-004: Manifest and Health Metadata
Deliverables:
- `sqs_manifest` and `sqs_import_runs` tables.
- `/health` and `/api/v1/meta/dataset` endpoints.
Acceptance:
- Metadata reflects dump `db_version` + importer schema version.

## SQS-005: Repository Layer and Query Primitives
Deliverables:
- Shared query builder helpers for pagination, sorting, filters.
- Base repository abstractions with parameterized SQL.
Acceptance:
- Deterministic ordering and cursor parsing pass tests.

## SQS-006: Context Resolve Service
Deliverables:
- `GET /api/v1/context/resolve`.
- Resolution states: `exact|partial|unresolved`.
Acceptance:
- No ambiguous/partial context returned as exact.

## SQS-007: Vendor Query APIs
Deliverables:
- `/api/v1/maps/{map_id}/vendors/nearby`
- `/api/v1/maps/{map_id}/vendors`
- Filters: capability + faction.
Acceptance:
- Nearby ordering deterministic by distance then guid.
- Invalid filters fail with explicit code.

## SQS-008: Trainer Query APIs
Deliverables:
- `/api/v1/maps/{map_id}/trainers/nearby`
- `/api/v1/trainers/{entry}`
- `/api/v1/trainers/{entry}/spells`
Acceptance:
- Trainer detail and spell payloads resolve deterministically.

## SQS-009: Flight Master APIs
Deliverables:
- `/api/v1/maps/{map_id}/flight-masters/nearby`
- `/api/v1/maps/{map_id}/flight-masters`
Acceptance:
- Results include only flight master role NPCs.

## SQS-010: Innkeeper APIs
Deliverables:
- `/api/v1/maps/{map_id}/innkeepers/nearby`
- `/api/v1/maps/{map_id}/innkeepers`
Acceptance:
- Results include only innkeeper role NPCs.

## SQS-011: Unified Nearby Endpoint and Error Surface
Deliverables:
- `/api/v1/maps/{map_id}/entities/nearby`
- Uniform error payload implementation across all endpoints.
Acceptance:
- Mixed-type query returns stable merged ordering.

## SQS-012: Performance Indexing Pass
Deliverables:
- Required indexes added.
- Optional RTree helper behind feature flag/config.
- Query plan validation tests.
Acceptance:
- Nearby query p95 meets target in perf test environment.

## SQS-013: Telemetry and Diagnostics
Deliverables:
- Structured logs with request ids.
- Endpoint latency/error metrics.
- Import run telemetry.
Acceptance:
- Diagnostics identify failing endpoint and reason code without code-level debugging.

## SQS-014: End-to-End Smoke and Docs Sync
Deliverables:
- Smoke suite covering startup/import/primary query endpoints.
- Docs sync with implemented API and error codes.
Acceptance:
- Smoke suite passes on clean environment with only dump + sqlite3 binary.

## 4. Test Categories Per Ticket
- Unit tests (pure logic, sanitizer, mappers).
- Integration tests (handlers/services/repositories).
- Contract tests (response schemas and errors).
- Smoke tests (startup/import/readiness/core endpoints).

## 5. Done Definition
- Ticket acceptance criteria met.
- No fail-open path introduced.
- Deterministic ordering and pagination validated.
- Error codes are explicit and documented.
- Relevant tests added and passing.
