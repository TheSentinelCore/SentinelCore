# SentinelQueryServer Technical Design Document (TDD) v1

## 1. Objective
Define implementation-level design, test strategy, and acceptance behavior for SentinelQueryServer v1.

## 2. Implementation Assumptions
- Runtime language/framework follows existing project stack preferences.
- SQLite is the sole runtime datastore.
- SQL dump import is executed via CLI at:
  - `SentinelQueryServer/sql/tools/sqlite3.exe`

## 3. Configuration Contract
Required config keys:
- `server.host`
- `server.port`
- `paths.source_dump_sql`
- `paths.sqlite3_exe`
- `paths.runtime_db`
- `paths.work_dir`
- `limits.max_radius`
- `limits.max_limit`

Validation:
- Missing/invalid config => startup failure.

## 4. Import Design
## 4.1 Sanitizer
Responsibilities:
- Remove MySQL-only statements.
- Normalize DDL to SQLite-compatible forms.
- Preserve data inserts and key semantics required by query endpoints.

## 4.2 Import Runner
- Executes sqlite CLI with bounded timeout.
- Captures stdout/stderr for structured logs.

## 4.3 Post Import
- Create required indexes/views/helper tables.
- Insert `sqs_manifest` and import run metadata.

## 4.4 Atomicity
- Import into temp db file.
- Validate.
- Atomic rename to active db path.

## 5. Repository Design
Repositories:
- `ContextRepository`
- `VendorRepository`
- `TrainerRepository`
- `FlightMasterRepository`
- `InnkeeperRepository`
- `MetaRepository`

Common repository requirements:
- Parameterized SQL only.
- Explicit deterministic `ORDER BY`.
- Cursor-aware query clauses.

## 6. Service Design
## 6.1 ContextService
Returns `exact|partial|unresolved` only.
No hidden fallback to exact.

## 6.2 VendorService
- Capability filter logic:
  - sell
  - repair
- Faction filtering via `faction_store` join when available.

## 6.3 TrainerService
- Trainer classification from template fields.
- Spell list resolution from trainer tables.

## 6.4 FlightMasterService and InnkeeperService
- Role derived from `NpcFlags`.

## 7. Pagination Design
Cursor contains:
- endpoint discriminator
- sort keys (distance/guid or entry/guid)
- dataset_version

Invalid cursor:
- return `PAGINATION_INVALID`.

## 8. Test Strategy
## 8.1 Unit Tests
- Config validation.
- Sanitizer transforms.
- Cursor encode/decode.
- Error mapping.
- Role classification bit logic.

## 8.2 Integration Tests
- Import pipeline on fixture dump.
- Handler -> service -> repository flows.
- Nearby query determinism.
- Manifest health contract.

## 8.3 Contract Tests
- JSON schema checks per endpoint.
- Error payload shape checks.
- Pagination behavior and deterministic ordering.

## 8.4 Performance Tests
- Nearby queries over representative dataset.
- p50/p95 target validation.

## 8.5 Smoke Tests
1. Startup with missing DB triggers import and service readiness.
2. Startup with invalid dump fails closed.
3. Context resolve returns partial/unresolved explicitly.
4. Vendor nearby query returns deterministic ordered results.
5. Trainer detail includes spell payload when requested.
6. Flight master/innkeeper endpoints return stable pagination.

## 9. Failure Semantics
- Invalid params: reject with `INVALID_PARAMS`.
- DB not present/invalid: service not ready (`DATASET_NOT_READY` / startup fail).
- Context unresolved: `CTX_UNRESOLVED` or `CTX_PARTIAL` semantics.
- Unexpected exceptions: `INTERNAL_ERROR` with request id.

## 10. Telemetry Contract
Per request log fields:
- request_id
- endpoint
- status_code
- latency_ms
- error_code
- dataset_version

Import telemetry fields:
- run_id
- source_dump
- duration_ms
- status
- error_code (if failed)

## 11. Migration and Compatibility
- `importer_schema_version` increments when helper schema changes.
- Backward-compatible API additions allowed within `/api/v1`.
- Breaking changes require `/api/v2`.

## 12. Release Readiness Checklist
- All required endpoints implemented.
- Import pipeline deterministic and atomic.
- Contract tests pass.
- Smoke tests pass.
- Documented error codes and payloads verified.
