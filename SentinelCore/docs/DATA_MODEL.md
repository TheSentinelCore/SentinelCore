# SentinelCore Data Model (P0 -> P1.5)

## 1. Canonical Rule
All world/entity identity for this phase uses cmangos canonical IDs.

Primary keys:
- `map_id` (canonical)
- `zone_id`
- `area_id`
- entity IDs (`npc_id`, `vendor_id`, `trainer_id`, `quest_id`)

TBC-only dataset.

## 2. Core Domain Entities
## 2.1 RuntimeContext
- `ui_map_id` number
- `canonical_map_id` number
- `zone_id` number
- `area_id` number
- `x` number
- `y` number
- `z` number
- `instance_type` string
- `resolved_at` timestamp
- `resolution_confidence` number

## 2.2 Vendor
- `vendor_id` number
- `npc_id` number
- `name` string
- `map_id` number
- `zone_id` number
- `area_id` number
- `x` number
- `y` number
- `z` number
- `faction_mask` number
- `can_repair` boolean
- `can_sell` boolean
- `can_reagents` boolean
- `source` string

## 2.3 VendorItem
- `vendor_id` number
- `item_id` number
- `stack_count` number
- `extended_cost_id` number|null
- `required_reputation` number|null

## 2.4 Trainer
- `trainer_id` number
- `npc_id` number
- `trainer_type` enum(`class`, `profession`)
- `class_mask` number
- `profession_id` number|null
- `name` string
- `map_id` number
- `zone_id` number
- `area_id` number
- `x` number
- `y` number
- `z` number

## 2.5 TrainerSpell
- `trainer_id` number
- `spell_id` number
- `cost` number
- `required_level` number
- `required_skill_line` number|null
- `required_skill_rank` number|null

## 2.6 Quest
- `quest_id` number
- `title` string
- `min_level` number
- `quest_level` number
- `zone_or_sort` number
- `required_class_mask` number
- `required_race_mask` number
- `is_repeatable` boolean
- `is_daily` boolean

## 2.7 QuestRelation
- `quest_id` number
- `npc_id` number
- `relation_type` enum(`starter`, `ender`)
- `map_id` number
- `zone_id` number
- `area_id` number
- `x` number
- `y` number
- `z` number

## 2.8 NpcSpawn
- `npc_id` number
- `map_id` number
- `zone_id` number
- `area_id` number
- `x` number
- `y` number
- `z` number
- `spawn_group` string|null

## 3. Bot-Side Operational Data
## 3.1 SessionSnapshot
- `session_id` string
- `state` string
- `started_at` timestamp
- `map_id` number
- `zone_id` number
- `kills` number
- `deaths` number
- `loot_events` number
- `vendor_trips` number
- `xp_per_hour` number
- `gold_per_hour` number

## 3.2 InventoryPolicy
- `min_free_slots` number (default 2)
- `never_sell` number[] (item IDs)
- `always_sell` number[] (item IDs)
- `sell_quality_max` number
- `sell_gray` boolean
- `sell_white` boolean
- `sell_green` boolean
- `sell_blue` boolean
- `sell_epic` boolean
- `keep_stack_min` table<item_id, count>

## 3.3 CandidateBlacklist
- `id` string
- `type` enum(`vendor`, `npc`, `target`)
- `reason` string
- `expires_at` timestamp

## 3.4 Scripts Data Files (Persistent)
All persistent bot data for this phase lives under:
- `scripts_data/SentinelCore/`

Primary files:
- `scripts_data/SentinelCore/config/vendor_inventory_policy.v1.json`
- `scripts_data/SentinelCore/state/runtime_state.v1.json`
- `scripts_data/SentinelCore/cache/vendor_runtime_cache.v1.json`

See `SentinelCore/docs/SCRIPTS_DATA_SCHEMA.md` for full schema.

## 4. Indexing Requirements (SentinelQueryServer)
Required indexes:
- `(map_id, zone_id, area_id)`
- `(map_id, x, y)` spatial-supporting index
- `(zone_id, entity_type)`
- `(npc_id)`
- `(quest_id)`
- `(trainer_type, class_mask, profession_id)`
- `(vendor_id, item_id)`

## 5. Query Semantics
- Zone list queries are strict `zone_id` scoped.
- Nearby queries are spatial and may cross zone boundaries, but remain within same `map_id`.
- Same-map rule is mandatory for vendor selection in this phase.

## 6. Versioning and Migration
- Dataset version tag stored in SentinelQueryServer manifest.
- SentinelCore stores expected dataset version.
- On mismatch: fail closed with explicit version error.

## 7. Serialization
- Network payloads: JSON (API v1).
- Internal db storage: SQL tables.
- Optional server cache serialization: compact binary (implementation detail).
