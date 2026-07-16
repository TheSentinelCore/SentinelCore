# SentinelQueryServer - World Data Query Service

## Overview

SentinelQueryServer is a lightweight HTTP service that provides world state and quest data to SentinelCore via the Sylvannas `core.http_get` API. It queries the TBC mangos database (`Database/tbcmangos.sqlite`) with read-only endpoints.

## Architecture

```
sentinel/modules/quest/query_client.lua  -- Lua HTTP client
         |
         v  core.http_get()  (GET-only, async)
         |
         v
SentinelQueryServer (Rust)
         |
         v  SQLite (rusqlite with bundled libsqlite3)
         |
         v
Quest/NPC tables
```

## API Endpoints

### Health Check
```
GET /health
Response: {"status": "ok", "database": "/path/to/tbcmangos.sqlite"}
```

### Quest Details
```
GET /api/v1/quests/{quest_id}
Response: Quest object with objectives, rewards, prerequisites
```

Example:
```bash
curl http://127.0.0.1:8081/api/v1/quests/6
# {"quest_id":6,"title":"Bounty on Garrick Padfoot","min_level":2,...}
```

### Quest NPCs
```
GET /api/v1/quests/{quest_id}/npcs?relation={giver|turnin}
Response: Array of NPCs with positions
```

Example:
```bash
curl http://127.0.0.1:8081/api/v1/quests/6/npcs
# [{"npc_id":823,"name":"Deputy Willem","map_id":0,"x":-8933.54,...}]
```

## Data Schema

### Quest
```json
{
  "quest_id": 6,
  "title": "Bounty on Garrick Padfoot",
  "min_level": 2,
  "max_level": 255,
  "quest_level": 5,
  "zone_or_sort": 9,
  "suggested_players": 0,
  "prev_quest_id": 18,
  "objectives": [
    {"slot": 1, "item_id": 182, "item_count": 1, "text": ""}
  ],
  "rewards": [
    {"slot": 1, "item_id": 6076, "choice": true}
  ]
}
```

### QuestNpc
```json
{
  "npc_id": 823,
  "name": "Deputy Willem",
  "map_id": 0,
  "x": -8933.54,
  "y": -136.52,
  "z": 83.45,
  "quest_ids": [6]
}
```

## Configuration

Environment variables:
- `SENTINEL_QUERY_DB` - Path to SQLite database (default: `../Database/tbcmangos.sqlite`)
- `SENTINEL_QUERY_HOST` - Bind address (default: `127.0.0.1`)
- `SENTINEL_QUERY_PORT` - Port (default: `8081`)

## Lua Integration

```lua
local QueryClient = require("modules/quest/query_client")

local client = QueryClient.new(blackboard)

-- Get quest data (with caching)
local quest = client:fetch_quest(quest_id)

-- Get givers/turnins
local givers = client:fetch_quest_npcs(quest_id, "giver")
local turnins = client:fetch_quest_npcs(quest_id, "turnin")
```

## Caching

Quest data is cached for 300 seconds (5 minutes) using an in-memory table. Cache key is `quests/{id}` or `quests/{id}/npcs`.

## Running

```bash
# Build
cd SentinelQueryServer && cargo build --release

# Run with custom DB
SENTINEL_QUERY_DB="/path/to/tbcmangos.sqlite" cargo run --release
```

## Database Tables Used

- `quest_template` - Quest metadata (title, level, prerequisites, rewards)
- `creature_questrelation` - Quest givers
- `creature_involvedrelation` - Quest turn-ins
- `creature_template` - NPC names
- `creature` - NPC positions