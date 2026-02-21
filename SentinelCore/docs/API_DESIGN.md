# SentinelQueryServer API Design (v1)

This document defines the external API contract.
For internal server architecture, see `SENTINEL_QUERY_SERVER_ARCHITECTURE.md`.

## 1. API Goals
- Deterministic cmangos-canonical data lookup.
- Small, query-focused payloads.
- Robust support for zone-wide lists and nearby selection.
- Same-map vendor selection support.
- Fail-closed friendly error model.

## 2. Base and Versioning
- Base URL: `http://127.0.0.1:<port>`
- Version prefix: `/api/v1`
- Content type: `application/json`

## 3. Common Query Params
- `limit` (default 50, hard max 500)
- `cursor` (opaque pagination cursor)
- `fields` (comma-separated projection)
- `locale` (default `enUS`)

## 4. Health and Meta
### `GET /health`
Response:
- `status`
- `version`
- `dataset_version`
- `uptime_secs`

### `GET /api/v1/meta/dataset`
Response:
- `dataset_version`
- `game_version` (`tbc`)
- `source` (`cmangos`)

## 5. Context Resolution
### `GET /api/v1/context/resolve`
Params:
- `ui_map_id`
- `x`
- `y`
- `z`
- `instance_type`

Response:
- `canonical_map_id`
- `zone_id`
- `area_id`
- `resolved` (bool)
- `ambiguous` (bool)
- `diagnostic_confidence` (optional, informational only)

Fail behavior:
- unresolved or ambiguous -> error response

## 6. Vendor Endpoints
### `GET /api/v1/maps/{map_id}/vendors/nearby`
Params:
- `x`
- `y`
- `z` (optional)
- `radius`
- `require_sell` (bool)
- `require_repair` (bool)
- `faction` (optional)

Response:
- `vendors[]` (sorted by spatial distance only)

Note:
- SentinelCore performs nav reachability/path ranking after this response.

### `GET /api/v1/zones/{zone_id}/vendors`
Zone-wide strict list, paged/filterable.

## 7. Trainer Endpoints
### `GET /api/v1/zones/{zone_id}/trainers`
Params:
- `trainer_type` (`class`, `profession`)
- `class_id` (optional)
- `profession_id` (optional)

### `GET /api/v1/trainers/{trainer_id}`
Returns trainer + spells (optional include).

## 8. Quest Endpoints
### `GET /api/v1/zones/{zone_id}/quests`
Params:
- `relation_type` (`starter`, `ender`, `both`)
- `min_level`
- `max_level`

### `GET /api/v1/quests/{quest_id}`
Returns full quest metadata and relations.

## 9. Generic Entity Search
### `GET /api/v1/entities/nearby`
Params:
- `map_id`
- `x`
- `y`
- `radius`
- `type` (`vendor`, `trainer`, `quest_starter`, `quest_ender`)

## 10. Error Model
Uniform error payload:
- `error.code`
- `error.message`
- `error.details`
- `request_id`

Standard codes:
- `CTX_UNRESOLVED`
- `CTX_LOW_CONFIDENCE`
- `MAP_NOT_SUPPORTED`
- `ZONE_NOT_FOUND`
- `ENTITY_NOT_FOUND`
- `INVALID_PARAMS`
- `DATASET_VERSION_MISMATCH`
- `INTERNAL_ERROR`

## 11. Pagination Contract
- Cursor-based only.
- Response:
  - `items`
  - `next_cursor` (null if no next page)
  - `count`

## 12. Deterministic Semantics
- Zone endpoints: strict `zone_id` scope.
- Nearby endpoints: spatial within specified `map_id`.
- No cross-map results for P0-P1.5.

## 13. Security and Limits
- Localhost-only deployment for this phase.
- Per-endpoint rate caps to protect service under multi-client load.
- Hard max for `radius` and `limit`.
