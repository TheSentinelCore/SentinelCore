# SentinelQueryServer Data Model (v1)

## 1. Modeling Goals
- Preserve cmangos identity and table semantics.
- Keep runtime schema close to source (mirror-first strategy).
- Add only minimal helper structures for performance and observability.

## 2. Canonical Domain Types
## 2.1 DatasetManifest
- `dataset_version` (string)
- `game_version` (`tbc`)
- `source` (`cmangos`)
- `db_version_string` (from `db_version.version`)
- `importer_schema_version` (integer)
- `built_at_utc` (ISO-8601)

## 2.2 WorldContext
- `map_id` (required when resolved)
- `zone_id` (nullable)
- `area_id` (nullable)
- `resolution` (`exact|partial|unresolved`)
- `source`
- `warnings[]`

## 2.3 SpawnedNpcEntity
- `guid`
- `entry`
- `name`
- `map_id`
- `x`,`y`,`z`
- `orientation`
- `npc_flags`
- `faction_id`
- `faction_team` (nullable)

## 2.4 VendorEntity
Extends `SpawnedNpcEntity` with:
- `can_sell` (bool)
- `can_repair` (bool)
- `vendor_item_count` (int)

## 2.5 TrainerEntity
Extends `SpawnedNpcEntity` with:
- `trainer_type`
- `trainer_class`
- `trainer_race`
- `trainer_spell_count`

## 2.6 FlightMasterEntity
Extends `SpawnedNpcEntity`.
Role determined from npc flags.

## 2.7 InnkeeperEntity
Extends `SpawnedNpcEntity`.
Role determined from npc flags.

## 3. Source Tables (Mirrored)
Core required tables:
- `creature`
- `creature_template`
- `npc_vendor`
- `npc_trainer`
- `npc_trainer_template`
- `faction_store`
- `db_version`

Optional usage:
- `areatrigger_tavern`
- `gossip_menu`
- `gossip_menu_option`

## 4. Internal SentinelQueryServer Tables
## 4.1 `sqs_manifest`
Columns:
- `id` (integer primary key)
- `dataset_version` (text, unique)
- `game_version` (text)
- `source` (text)
- `db_version_string` (text)
- `importer_schema_version` (integer)
- `built_at_utc` (text)
- `dump_path` (text)

## 4.2 `sqs_import_runs`
Columns:
- `run_id` (text primary key)
- `started_at_utc` (text)
- `completed_at_utc` (text nullable)
- `status` (`started|failed|completed`)
- `error_code` (text nullable)
- `error_message` (text nullable)

## 4.3 `sqs_ui_map_map` (optional)
Maps external ui map IDs to canonical map IDs when curated mapping is available.

## 5. Views (Recommended)
- `v_vendor_npc`
- `v_trainer_npc`
- `v_flight_master_npc`
- `v_innkeeper_npc`

Each view joins `creature + creature_template` and computes role booleans from `NpcFlags` and role tables.

## 6. Role Flag Interpretation
For v1 role classification, read from `creature_template.NpcFlags`:
- Vendor: any vendor-related flag set.
- Trainer: trainer/class/profession trainer flag set.
- Flight master: flight master flag set.
- Innkeeper: innkeeper flag set.

Notes:
- Final bit constants are implementation constants in code, validated by fixture tests.

## 7. Query Helper Structures
## 7.1 B-Tree Indexes
Required:
- `creature(map, id)`
- `creature(id, map)`
- `creature_template(Entry)`
- `npc_vendor(entry)`
- `npc_trainer(entry)`
- `faction_store(Entry)`

Recommended:
- `creature(map, position_x, position_y)`

## 7.2 Optional RTree
If nearby query latency exceeds target:
- Build `sqs_creature_rtree(guid, min_x, max_x, min_y, max_y)`
- Keep synchronized during import build.

## 8. Context Resolution Data Limits
Dump-only datasets may not provide complete zone/area geometry.
Therefore:
- `map_id` is strongly resolvable.
- `zone_id` and `area_id` can be null when not deterministically derivable.
- This is represented explicitly through `resolution` state.

## 9. Dataset Version Derivation
`dataset_version` construction:
- `db_version.version` (from source dump)
- `db_version.creature_ai_version`
- `importer_schema_version`

Canonical example:
- `TBC-DB 1.10.0|ACID 2.4.3|importer-v1`

## 10. Data Integrity Rules
- Active DB must have exactly one current manifest row.
- Manifest must be present before HTTP service is marked ready.
- Required source tables must exist and be readable.
- Missing required tables => `DATASET_INVALID` at startup.
