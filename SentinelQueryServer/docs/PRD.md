# SentinelQueryServer PRD (v1)

## 1. Purpose
SentinelQueryServer is a read-focused world data service for SentinelCore. It serves deterministic, cmangos-canonical world queries using a local SQLite dataset built from `tbcmangos.sql`.

Primary v1 goal:
- Provide low-latency, deterministic query APIs for context and service NPC discovery (vendors, trainers, flight masters, innkeepers).

## 2. Scope
In scope for v1:
- Dataset import from `SentinelQueryServer/sql/database/tbcmangos.sql` into SQLite.
- API endpoints for:
  - Context resolution/canonicalization.
  - Nearby and list queries for vendors.
  - Nearby and list queries for trainers.
  - Nearby and list queries for flight masters.
  - Nearby and list queries for innkeepers.
- Startup behavior: generate SQLite DB when missing.
- Fail-closed semantics on invalid or uncertain inputs.
- Structured telemetry, health, and dataset metadata.

Out of scope for v1:
- Quest APIs.
- Runtime pathfinding/path-cost logic (owned by SentinelNavServer/SentinelNavClient + SentinelCore).
- Security/authn/authz hardening.
- Live DB connectivity to a running MySQL/cmangos server.
- Non-TBC datasets.

## 3. Hard Constraints
- TBC only.
- Canonical identity uses cmangos IDs (`map_id`, `zone_id`, `area_id`).
- Data source for v1 is only the SQL dump file (`tbcmangos.sql`).
- Storage engine is SQLite only.
- No phased-content logic.
- Fail-closed behavior on uncertainty.
- No locale parameter in API.

## 4. Consumers and Use Cases
Primary consumer:
- SentinelCore via WorldDataAdapter.

Key use cases:
- Resolve runtime world context to canonical IDs.
- Find same-map vendor candidates for inventory maintenance.
- Find nearby trainer/flight master/innkeeper candidates for utility flows.
- Validate dataset health/version compatibility during startup.

## 5. Functional Requirements
### FR-001 Data Import
- On startup, if runtime DB file is missing, import `tbcmangos.sql` into SQLite.
- Import must run through the provided SQLite CLI binary at `SentinelQueryServer/sql/tools/sqlite3.exe`.
- Import process must be atomic:
  - Build into temp file.
  - Validate dataset.
  - Rename to active DB.

### FR-002 Dataset Metadata
- Expose dataset metadata endpoint with:
  - `dataset_version`
  - `game_version=tbc`
  - `source=cmangos`
  - importer schema version
- `dataset_version` must be derived from dump metadata (`db_version`) and importer schema metadata.

### FR-003 Context Endpoint
- Accept runtime context inputs and return canonicalized IDs.
- Must always return canonical `map_id` when resolvable.
- If `zone_id`/`area_id` cannot be resolved from available data, return unresolved/partial context explicitly (never silent best-guess success).

### FR-004 Vendor APIs
- Return vendor candidates with spawn coordinates on requested canonical map.
- Support capability filters (`sell`, `repair`) and faction filter.
- Deterministic sort order.

### FR-005 Trainer APIs
- Return trainer candidates with trainer metadata and location.
- Support class/profession filtering.
- Optional trainer detail endpoint with trainable spells.

### FR-006 Flight Master APIs
- Return nearby/list flight master NPCs.

### FR-007 Innkeeper APIs
- Return nearby/list innkeeper NPCs.

### FR-008 Determinism and Errors
- Uniform structured error model with explicit error codes.
- Identical query inputs against same dataset must produce stable ordering and payload shape.

### FR-009 Operational Endpoints
- Health endpoint with uptime and dataset metadata summary.
- Query diagnostics in logs/metrics for debugging.

## 6. Non-Functional Requirements
- Determinism: stable sorting and stable pagination.
- Reliability: fail-closed for invalid params, ambiguous context, and dataset invalid states.
- Performance targets (single host, local network):
  - p50 <= 15ms for nearby queries.
  - p95 <= 60ms for nearby queries.
- Startup robustness:
  - Service must not expose query endpoints until DB is valid and open.

## 7. Data and Query Model Decisions
- Base schema strategy: mirror cmangos tables from dump.
- Performance strategy:
  - Add targeted indexes and lightweight helper structures only when needed.
  - Avoid broad denormalization unless measured latency requires it.
- QueryServer remains data-only. Path ranking remains outside this service.

## 8. Risks and Mitigations
Risk: MySQL dump syntax is not directly SQLite-compatible in full.
- Mitigation: import preprocessor/sanitizer step before feeding SQL into `sqlite3.exe`.

Risk: `zone_id`/`area_id` may be incomplete from dump-only sources.
- Mitigation: expose explicit partial/unresolved states and require caller fail-closed where full context is mandatory.

Risk: large table scans on nearby queries.
- Mitigation: indexed coordinate filtering and optional RTree helper table.

## 9. Success Criteria
- SentinelCore can reliably query nearby vendors/trainers/flight masters/innkeepers by map and position.
- Service startup is deterministic and self-healing when DB file is missing.
- No fail-open behavior in context resolution or invalid query handling.
- Measured query latency remains within targets under expected local load.
