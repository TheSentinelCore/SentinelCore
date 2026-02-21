# SentinelQueryServer API Design (v1)

This document defines external API contracts for SentinelQueryServer.

Architecture reference:
- `SentinelQueryServer/docs/SENTINEL_QUERY_SERVER_ARCHITECTURE.md`

## 1. API Goals
- Deterministic cmangos-canonical world lookups.
- Query-focused payloads for SentinelCore.
- Explicit fail-closed error model.
- No silent best-guess behavior.

## 2. Base and Versioning
- Base URL: `http://<host>:<port>`
- Version prefix: `/api/v1`
- Content type: `application/json`

## 3. Common Query Parameters
- `limit` (default 50, max 500)
- `cursor` (opaque cursor)
- `fields` (comma-separated projections)

Removed from API:
- `locale`

## 4. Health and Metadata
### `GET /health`
Response:
- `status` (`ok|degraded|failed`)
- `version`
- `uptime_secs`
- `dataset_version`
- `game_version` (`tbc`)

### `GET /api/v1/meta/dataset`
Response:
- `dataset_version`
- `source` (`cmangos`)
- `game_version` (`tbc`)
- `db_version_string`
- `importer_schema_version`
- `built_at_utc`

## 5. Context Endpoint
### `GET /api/v1/context/resolve`
Query params:
- `map_id` (optional, preferred when available)
- `ui_map_id` (optional)
- `x` (optional)
- `y` (optional)
- `z` (optional)
- `instance_id` (optional)
- `instance_type` (optional)

Response:
- `canonical_map_id` (number or null)
- `map_id` (number or null)
- `zone_id` (number or null)
- `area_id` (number or null)
- `resolved` (bool)
- `ambiguous` (bool)
- `diagnostic_confidence` (0.0..1.0)
- `resolution` (`exact|partial|unresolved`)
- `source` (`direct_map|ui_map_map|position_inference|none`)
- `warnings` (array)

Rules:
- `exact`: map/zone/area all resolved.
- `partial`: map resolved, zone/area unavailable.
- `unresolved`: map unresolved.
- Service never promotes `partial` to `exact`.

## 6. Vendor Endpoints
### `GET /api/v1/maps/{map_id}/vendors/nearby`
Params:
- `x` (required)
- `y` (required)
- `z` (optional)
- `radius` (required)
- `require_sell` (optional bool)
- `require_repair` (optional bool)
- `faction` (optional: `alliance|horde|neutral`)
- `limit`, `cursor`

Response:
- `items[]` with fields:
  - `guid`
  - `entry`
  - `name`
  - `map_id`
  - `x`,`y`,`z`
  - `distance`
  - `npc_flags`
  - `can_sell`
  - `can_repair`
  - `faction_id`
  - `faction_team` (nullable)
- `next_cursor`
- `count`

### `GET /api/v1/maps/{map_id}/vendors`
List/paged without distance ordering requirement.

## 7. Trainer Endpoints
### `GET /api/v1/maps/{map_id}/trainers/nearby`
Params:
- `x`,`y`,`radius` required
- `trainer_type` optional (`class|profession|any`)
- `class_id` optional
- `profession_id` optional
- `limit`,`cursor`

Response item fields:
- `guid`,`entry`,`name`,`map_id`,`x`,`y`,`z`,`distance`
- `trainer_type`
- `trainer_class`
- `trainer_race`
- `faction_id`,`faction_team`

### `GET /api/v1/maps/{map_id}/trainers`
List/paged endpoint with deterministic ordering by `entry`, then `guid`.
Supports:
- `trainer_type` optional (`class|profession|any`)
- `class_id` optional
- `profession_id` optional
- `limit`,`cursor`

### `GET /api/v1/trainers/{entry}`
Returns trainer detail and optional spells.

### `GET /api/v1/trainers/{entry}/spells`
Returns trainable spell rows from trainer tables.

## 8. Flight Master Endpoints
### `GET /api/v1/maps/{map_id}/flight-masters/nearby`
Params:
- `x`,`y`,`radius` required
- `limit`,`cursor`

Response item fields:
- `guid`,`entry`,`name`,`map_id`,`x`,`y`,`z`,`distance`
- `faction_id`,`faction_team`

### `GET /api/v1/maps/{map_id}/flight-masters`
List/paged endpoint.

## 9. Innkeeper Endpoints
### `GET /api/v1/maps/{map_id}/innkeepers/nearby`
Params:
- `x`,`y`,`radius` required
- `limit`,`cursor`

Response item fields:
- `guid`,`entry`,`name`,`map_id`,`x`,`y`,`z`,`distance`
- `faction_id`,`faction_team`

### `GET /api/v1/maps/{map_id}/innkeepers`
List/paged endpoint.

## 10. Unified Nearby Endpoint
### `GET /api/v1/maps/{map_id}/entities/nearby`
Params:
- `x`,`y`,`radius` required
- `types` required (csv subset of `vendor,trainer,flight_master,innkeeper`)
- type-specific filters are optional.

Purpose:
- Reduce round trips when caller needs multiple utility entity classes.

## 11. Determinism Rules
- Nearby endpoints sort by:
  1) `distance` ascending
  2) `guid` ascending
- List endpoints sort by:
  1) `entry` ascending
  2) `guid` ascending
- Cursor encoding preserves sort key continuity.

## 12. Error Model
Payload:
```json
{
  "error": {
    "code": "INVALID_PARAMS",
    "message": "radius must be > 0",
    "details": {"field":"radius"}
  },
  "request_id": "..."
}
```

Standard codes:
- `INVALID_PARAMS`
- `CTX_UNRESOLVED`
- `CTX_PARTIAL`
- `MAP_NOT_FOUND`
- `ENTITY_NOT_FOUND`
- `FACTION_FILTER_UNSUPPORTED`
- `DATASET_NOT_READY`
- `DATASET_INVALID`
- `PAGINATION_INVALID`
- `INTERNAL_ERROR`

## 13. Limits
- Hard caps:
  - `limit <= 500`
  - `radius <= configured_max_radius`
- Invalid caps are rejected with `INVALID_PARAMS`.

## 14. Compatibility Notes
- Zone and area resolution quality depends on data available in the dump.
- Consumers that require full canonical triple (`map_id`,`zone_id`,`area_id`) must treat `resolution=partial` as fail-closed.
