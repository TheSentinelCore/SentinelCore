# SentinelQueryServer Architecture and Overall Design (v1)

## 1. Overview
SentinelQueryServer is a local read API over cmangos world data for TBC. It is optimized for deterministic, fail-closed queries used by SentinelCore.

Design principles:
- Data-only service.
- Deterministic outputs.
- Fail-closed uncertainty handling.
- SQLite runtime with startup import from SQL dump.

## 2. Scope Boundaries
In scope:
- Context canonicalization.
- Vendor/trainer/flight master/innkeeper lookup.
- SQLite import/build pipeline from dump.
- Health, metadata, telemetry.

Out of scope:
- Pathfinding and path-cost ranking.
- Quest APIs.
- Security/auth hardening.
- Live MySQL runtime dependencies.

## 3. Runtime Topology
```text
SentinelCore ----HTTP----> SentinelQueryServer ----SQLite----> world.db
                       ^
                       | startup build (if missing)
                       +---- tbcmangos.sql + sqlite3.exe
```

## 4. Component Architecture
```text
SentinelQueryServer
  cmd/
    server_main
  config/
  http/
    router
    handlers
    middleware
  app/
    services
      context_service
      vendor_service
      trainer_service
      flight_master_service
      innkeeper_service
      meta_service
  storage/
    sqlite_pool
    repositories
    query_builder
  importer/
    mysql_dump_sanitizer
    sqlite_cli_runner
    manifest_builder
    validator
  telemetry/
    logger
    metrics
```

Layer rules:
- `http` handles transport only.
- `app/services` own business semantics and fail-closed behavior.
- `storage/repositories` own SQL.
- `importer` owns all conversion/build logic.

## 5. Startup and DB Build Lifecycle
### 5.1 Boot Sequence
1. Load config.
2. Check active DB path.
3. If missing: run import pipeline.
4. Validate DB schema/manifest.
5. Open SQLite pool.
6. Start HTTP listener.

### 5.2 Import Pipeline
Inputs:
- `SentinelQueryServer/sql/database/tbcmangos.sql`
- `SentinelQueryServer/sql/tools/sqlite3.exe`

Pipeline:
1. Pre-sanitize MySQL dump to SQLite-compatible SQL:
  - Drop MySQL-only directives (`LOCK TABLES`, engine options, disable/enable keys, etc.).
  - Normalize DDL where needed.
2. Create temp db: `world.tmp.db`.
3. Execute import via sqlite CLI:
  - `sqlite3.exe world.tmp.db ".read sanitized.sql"`
4. Build required indexes/helper tables.
5. Build/insert manifest metadata.
6. Validation checks:
  - Required tables exist.
  - `db_version` present and readable.
  - Required query views/indexes present.
7. Atomic rename `world.tmp.db -> world.db`.

Failure policy:
- Any step failure aborts startup (fail-closed).

## 6. Core Services
### 6.1 ContextService
Responsibility:
- Canonicalize context inputs into cmangos identity.

Input priority:
1. `map_id` directly from client (preferred).
2. `ui_map_id` mapping table fallback if configured.
3. Position-only fallback is best-effort and can yield unresolved.

Output states:
- `exact`: map/zone/area resolved.
- `partial`: map resolved, zone/area unresolved.
- `unresolved`: no canonical map.

Rule:
- Never fabricate zone/area from weak inference.

### 6.2 VendorService
- Query vendor NPCs on same requested `map_id`.
- Apply capability filters (`sell`, `repair`) and faction filters.
- Return deterministic ordering.

### 6.3 TrainerService
- Query trainer NPCs by map/position and type/class/profession constraints.
- Resolve trainer spells from `npc_trainer` and template linkage.

### 6.4 FlightMasterService
- Query NPCs with flight master role from `NpcFlags` and spawn data.

### 6.5 InnkeeperService
- Query NPCs with innkeeper role from `NpcFlags` and spawn data.

### 6.6 MetaService
- Health and dataset metadata.
- Exposes importer and dataset signature metadata.

## 7. Storage Design
Primary source tables (mirrored):
- `creature`
- `creature_template`
- `npc_vendor`
- `npc_trainer`
- `npc_trainer_template`
- `faction_store`
- `db_version`

Internal tables:
- `sqs_manifest`
- `sqs_import_runs`
- `sqs_config`

Optional helper structures:
- `sqs_creature_rtree` for nearby query acceleration.
- role-specific views (`v_vendor_npc`, `v_trainer_npc`, `v_flight_master_npc`, `v_innkeeper_npc`).

## 8. Query Strategy
Nearby queries:
- Restrict by `map_id` first.
- Apply bounding box by radius in SQL.
- Compute exact planar distance and sort by:
  1) distance ascending
  2) guid ascending

Determinism:
- Every list endpoint has explicit `ORDER BY`.
- Cursor tokens encode ordering keys.

## 9. Error and Fail-Closed Semantics
Uniform error payload:
- `error.code`
- `error.message`
- `error.details`
- `request_id`

Fail-closed examples:
- Unknown `map_id` -> error.
- Invalid numeric ranges -> error.
- Ambiguous/unresolved context -> explicit context error.
- Missing/invalid dataset manifest -> service not ready.

## 10. Observability
Logs per request:
- request_id
- endpoint
- params hash
- status
- latency_ms
- error_code
- dataset_version

Metrics:
- request throughput by endpoint
- p50/p95 latency
- unresolved context rate
- importer run duration and failure counts

## 11. Configuration
Required config:
- host
- port
- paths:
  - source dump path
  - sqlite3 exe path
  - runtime db path
  - working temp dir
- query limits:
  - max radius
  - max limit

No security/auth config required in v1.

## 12. Reliability Guarantees
- DB generation is atomic.
- API serves only validated DB.
- No cross-map leakage in map-scoped endpoints.
- Partial context is explicit and never silently treated as exact.

## 13. Evolution Plan
After v1:
- Add optional denormalized read models only if measured performance requires it.
- Add optional batch endpoints for multi-query efficiency.
- Add optional auth/rate controls if deployment model expands.
