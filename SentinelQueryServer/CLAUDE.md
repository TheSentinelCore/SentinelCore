# CLAUDE.md - SentinelQueryServer

> World data query server — SQLite-backed REST API for NPC locations, vendors, trainers, flight masters, and innkeepers.

## Quick Reference

```bash
# Build
cargo build --release

# Test
cargo test

# Run
cargo run --release -- --config config.toml

# Lint
cargo clippy
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  HTTP Layer (Axum 0.8)                    │
│  14 GET endpoints across 8 route modules                 │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│              Service Layer (trait-based DI)               │
│  ContextService, VendorService, TrainerService,          │
│  FlightMasterService, InnkeeperService, EntityService,   │
│  MetaService                                             │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│              Repository Layer                             │
│  Per-entity repositories with cursor pagination          │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│              Storage Layer (SQLite via rusqlite)          │
│  SqliteStore: read-only connection management            │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
SentinelQueryServer/
├── Cargo.toml                          # Dependencies (axum 0.8, rusqlite 0.33, tokio, serde)
├── config.toml                         # Server + importer configuration
├── src/
│   ├── main.rs                         # Entry point (import, init services, start server)
│   ├── lib.rs                          # Library exports
│   ├── blackboard.rs                   # ServerBlackboard (shared state container)
│   ├── config.rs                       # TOML config loading & validation
│   ├── cursor.rs                       # Base64 cursor-based pagination
│   ├── error.rs                        # AppError with 10 error codes → HTTP status mapping
│   ├── models.rs                       # Domain models & request/response types
│   ├── state.rs                        # StartupStatus (Init → Importing → Ready/Failed)
│   ├── telemetry.rs                    # MetricsRegistry & request tracking
│   ├── validation.rs                   # Input validation helpers
│   ├── routes/
│   │   ├── mod.rs                      # Router registration (14 endpoints)
│   │   ├── middleware.rs               # Request tracking middleware
│   │   ├── helpers.rs                  # Route validation helpers
│   │   ├── context.rs                  # GET /api/v1/context/resolve
│   │   ├── entities.rs                 # GET /api/v1/maps/{map_id}/entities/nearby
│   │   ├── vendor.rs                   # Vendor list + nearby endpoints
│   │   ├── trainer.rs                  # Trainer list + nearby + detail + spells
│   │   ├── flight_master.rs            # Flight master list + nearby
│   │   ├── innkeeper.rs                # Innkeeper list + nearby
│   │   ├── health.rs                   # GET /health
│   │   └── meta.rs                     # GET /api/v1/meta/dataset
│   ├── services/                       # Business logic (trait + impl per entity)
│   │   ├── mod.rs, context.rs, vendor.rs, trainer.rs
│   │   ├── flight_master.rs, innkeeper.rs, entity.rs, meta.rs
│   ├── storage/
│   │   ├── mod.rs                      # SqliteStore export
│   │   ├── db.rs                       # SQLite connection lifecycle
│   │   ├── query.rs                    # Query builder utilities
│   │   └── repositories/              # Per-entity SQL repositories
│   │       ├── context.rs, vendor.rs, trainer.rs
│   │       ├── flight_master.rs, innkeeper.rs, entity.rs, meta.rs
│   └── importer/
│       ├── mod.rs                      # Importer exports
│       ├── pipeline.rs                 # DB creation from SQL dump
│       ├── sanitizer.rs                # Data sanitization
│       └── validator.rs                # Data validation
├── tests/
│   ├── api_contract_tests.rs           # API endpoint contracts
│   ├── import_pipeline_tests.rs        # Importer correctness
│   ├── perf_index_tests.rs             # Index performance
│   ├── smoke_tests.rs                  # Basic smoke tests
│   └── telemetry_tests.rs             # Metrics validation
├── sql/
│   └── database/tbcmangos.sql          # TBC database dump (import source)
├── data/
│   ├── world.db                        # Runtime SQLite database
│   └── work/                           # Import working directory
└── docs/                               # Design documentation (PRD, TDD, API, architecture)
```

## API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | Server status |
| `GET /api/v1/meta/dataset` | Dataset manifest/version info |
| `GET /api/v1/context/resolve` | Resolve map/zone/area from position |
| `GET /api/v1/maps/{map_id}/vendors` | List vendors on map |
| `GET /api/v1/maps/{map_id}/vendors/nearby` | Nearby vendors by position |
| `GET /api/v1/maps/{map_id}/trainers` | List trainers on map |
| `GET /api/v1/maps/{map_id}/trainers/nearby` | Nearby trainers by position |
| `GET /api/v1/trainers/{entry}` | Trainer detail |
| `GET /api/v1/trainers/{entry}/spells` | Trainer spell list |
| `GET /api/v1/maps/{map_id}/flight-masters` | List flight masters |
| `GET /api/v1/maps/{map_id}/flight-masters/nearby` | Nearby flight masters |
| `GET /api/v1/maps/{map_id}/innkeepers` | List innkeepers |
| `GET /api/v1/maps/{map_id}/innkeepers/nearby` | Nearby innkeepers |
| `GET /api/v1/maps/{map_id}/entities/nearby` | Unified nearby entity query |

All endpoints are **GET-only** (Lua client limitation — `core.http_get`).

## Configuration (config.toml)

```toml
[server]
host = "0.0.0.0"
port = 47120
max_concurrent_requests = 128

[paths]
source_dump_sql = "sql/database/tbcmangos.sql"
sqlite3_exe = "sql/tools/sqlite3.exe"
runtime_db = "data/world.db"
work_dir = "data/work"

[limits]
max_radius = 5000.0
max_limit = 500

[importer]
schema_version = 1
enable_rtree = false
sqlite_import_timeout_secs = 900
```

## Startup Flow

1. Load config from TOML
2. Run `Importer::ensure_runtime_db()` — creates SQLite from SQL dump if needed
3. Open read-only SQLite store
4. Initialize repositories → services → ServerBlackboard
5. Build Axum router with middleware
6. Start server on `0.0.0.0:47120`

## Key Patterns

- **Trait-based DI**: Each service is a trait (e.g. `VendorService`) with a `Default*Service` impl wrapping a repository
- **Cursor pagination**: Base64-encoded offsets for paginated responses
- **GET-only**: Compatible with Lua `core.http_get`
- **Startup gating**: Health endpoint reports status during import
- **Error codes**: 10 structured codes (InvalidParams, MapNotFound, CtxUnresolved, etc.) → HTTP 400/404/422/500/503

## Code Style

1. **Error handling**: `thiserror` for types, `AppError` with `ErrorCode` enum → HTTP status
2. **Logging**: `tracing` macros (`info!`, `debug!`, `error!`)
3. **Validation**: All inputs validated before queries
4. **Async**: Tokio runtime with Axum handlers
5. **No unwrap**: Use `?` operator in library code

## Dependencies

```toml
axum = "0.8"
tokio = { version = "1.48", features = ["full"] }
rusqlite = { version = "0.33", features = ["bundled"] }
serde = { version = "1.0", features = ["derive"] }
dashmap = "6.1"
parking_lot = "0.12"
tracing = "0.1"
thiserror = "2.0"
tower-http = "0.6"
```
