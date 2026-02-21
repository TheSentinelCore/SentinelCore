# SentinelQueryServer Architecture and Overall Design (v1)

## 1. Purpose
SentinelQueryServer is the cmangos-backed query service used by SentinelCore for deterministic world lookups (context resolve, vendors, trainers, quests) under fail-closed constraints.

This document expands implementation architecture beyond endpoint contracts in `API_DESIGN.md`.

## 2. Scope and Boundaries
- In scope (P0 -> P1.5):
  - Context resolution (`ui_map_id + xyz + instance_type -> canonical map_id/zone_id/area_id`)
  - Nearby and zone-scoped vendor queries
  - Trainer and quest lookup endpoints
  - Dataset metadata/version validation
- Out of scope:
  - Runtime nav pathfinding/ranking (owned by SentinelNavClient + SentinelCore)
  - Phase-aware content logic
  - Cross-expansion datasets

## 3. System Context
- Upstream inputs:
  - cmangos extracts / SQL snapshots
  - static map/zone/area relation data
- Downstream consumers:
  - SentinelCore clients (single or multi-client)
- Deployment model:
  - localhost service process, shared by multiple clients on one machine

## 4. Runtime Architecture
```text
SentinelQueryServer
  config/
  http/
    router/
    handlers/
    middleware/
  app/
    services/
    validators/
  domain/
    models/
    value_objects/
  storage/
    repositories/
    sql/
    migrations/
  cache/
    in_memory/
  telemetry/
    logs/
    metrics/
```

Layer rules:
- `http` maps request/response only.
- `app/services` owns query orchestration and fail-closed semantics.
- `domain` has canonical data types and invariants.
- `storage` has zero business logic beyond retrieval/index usage.
- `cache` is optional optimization, never source of truth.

## 5. Core Services
### 5.1 ContextResolveService
- Inputs: `ui_map_id`, `x`, `y`, `z`, `instance_type`.
- Pipeline:
  1. Validate params and ranges.
  2. Map UI identifiers to candidate canonical map contexts.
  3. Resolve zone/area by spatial containment + nearest fallback policy.
  4. Compute diagnostic confidence.
  5. Return resolved/ambiguous/unresolved response.
- Fail-closed outputs:
  - `CTX_UNRESOLVED`
  - `CTX_LOW_CONFIDENCE`

### 5.2 VendorQueryService
- Inputs: canonical map + position + capability/faction filters.
- Responsibilities:
  - same-map enforcement at query boundary
  - capability/faction filtering
  - nearby candidate retrieval (spatial)
- Non-responsibility:
  - no nav reachability/path ranking (client-side only)

### 5.3 TrainerQueryService
- Zone and typed trainer queries (`class`/`profession`).
- Supports detail expansions for trainer spells by trainer id.

### 5.4 QuestQueryService
- Zone-scoped quest list and detail query.
- Supports relation typing (`starter`, `ender`, `both`).

### 5.5 MetaService
- Health and dataset metadata endpoints.
- Emits dataset compatibility metadata used by SentinelCore startup checks.

## 6. Data Storage Design
Primary logical tables:
- `maps`, `zones`, `areas`
- `vendors`, `vendor_items`
- `trainers`, `trainer_spells`
- `quests`, `quest_relations`
- `npc_spawns`
- `dataset_manifest`

Required indexes (minimum):
- `(map_id, zone_id, area_id)`
- spatial index over `(map_id, x, y)` (and z if available)
- `(zone_id, entity_type)`
- `(npc_id)`
- `(vendor_id, item_id)`
- `(trainer_type, class_mask, profession_id)`
- `(quest_id)`

## 7. Request Lifecycle
1. HTTP middleware:
  - request id generation
  - timeout/deadline enforcement
  - structured logging context
2. Input validation:
  - strict type/range/enum checks
3. Service call:
  - deterministic query plan
4. Response shaping:
  - stable JSON contract (`API_DESIGN.md`)
5. Error mapping:
  - uniform payload with `error.code`, `error.message`, `error.details`, `request_id`

## 8. Caching Strategy
- Cache scope:
  - hot read-through cache for frequent nearby/context lookups
  - short TTL, bounded size, explicit eviction
- Key design:
  - include dataset version and all query-shaping params in cache key
- Safety rule:
  - cache miss or cache failure must degrade to storage query, never stale-invalid success

## 9. Determinism and Fail-Closed Rules
- No cross-map leakage for map-scoped endpoints.
- Low-confidence context resolution never returns best-guess as success.
- Unknown dataset version mismatches return explicit error.
- Invalid params return `INVALID_PARAMS` with concrete field details.

## 10. Observability
Structured logs per request:
- `request_id`
- endpoint
- latency_ms
- status
- error_code (if any)
- dataset_version

Metrics:
- request throughput by endpoint
- p50/p95 latency
- cache hit ratio
- context unresolved/low-confidence rate
- vendor query cardinality distribution

## 11. Security and Resource Controls
- Bind localhost only in this phase.
- Enforce hard caps (`limit`, `radius`).
- Endpoint-level rate limiting for multi-client contention.
- Timeout budgets per query class to prevent tail latency collapse.

## 12. Versioning and Migration
- API versioned under `/api/v1`.
- Dataset manifest includes:
  - `dataset_version`
  - `game_version=tbc`
  - `source=cmangos`
- Backward-compatible additions only within `v1` (new optional fields).

## 13. Testing Strategy
- Unit tests:
  - validators
  - context resolver confidence logic
  - error mapping
- Integration tests:
  - handler -> service -> repository paths against fixture DB
- Determinism tests:
  - fixed inputs produce fixed outputs/order
- Contract tests:
  - JSON schema + pagination/error payload checks
- Load tests:
  - nearby vendor/context resolve at multi-client simulated concurrency

## 14. Open Design Decisions
- Final spatial index backend and precision rules for area boundary edges.
- Dataset build pipeline ownership and refresh cadence.
- Whether to expose optional batch endpoints for future multi-query efficiency.
