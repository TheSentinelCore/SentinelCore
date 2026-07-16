# SentinelCore Quest Engine

## Overview

The Quest Engine provides questing automation capabilities for SentinelCore. It combines live quest state from the Sylvannas Questie addon with historical quest data from the SentinelQueryServer to enable intelligent quest routing and objective completion.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 SentinelApp                        │
│                    (runtime)                      │
└───────────────────────┬─────────────────────────────┘
                      │
                      v
┌─────────────────────────────────────────────────────┐
│                   Quest Module                        │
│  (modules/quest/module.lua)                         │
│  - Initialize with blackboard                      │
│  - Subscribe to QUEST_LOG_UPDATE events             │
│  - Provide Engine to other modules                   │
└───────────────────────┬─────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
┌───────────────────────┐ ┌─────────────────────────────────┐
│  Quest Tracker        │ │  Quest Engine (route planning)    │
│  (tracker.lua)        │ │  (engine.lua)                   │
│  - Refresh quest log  │ │  - get_quest_givers(npc_id)       │
│  - Merge with Questie │ │  - get_quest_turnins(npc_id)      │
│  - Active quests list │ │  - can_turn_in(quest_id)          │
└───────────────────────┘ └─────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│              Query Client                           │
│  (query_client.lua)                                 │
│  - HTTP GET to SentinelQueryServer                  │
│  - Cache responses for 5 minutes                    │
└─────────────────────────────────────────────────────┘
                      │
                      v
┌─────────────────────────────────────────────────────┐
│            SentinelQueryServer (Rust)                 │
│  - SQLite: quest_template, creature_* tables          │
│  - Endpoints: /api/v1/quests/{id}                  │
│  - Endpoints: /api/v1/quests/{id}/npcs             │
└─────────────────────────────────────────────────────┘
```

## Components

### modules/quest/questie_adapter.lua

Live Questie addon wrapper. Provides runtime quest state.

```lua
local Questie = require("modules/quest/questie_adapter")

Questie.is_ready()           -- Addon available and loaded
Questie.query_quest(id, key) -- Quest metadata (title, level, etc.)
Questie.is_quest_doable(id)  -- Can accept (level, prerequisites met)
Questie.is_quest_complete(id) -- Is completed
Questie.get_active_npc_ids() -- NPCs with available/turnin quests
```

### modules/quest/tracker.lua

Quest log scanner. Reads `core.quests.*` APIs.

```lua
local tracker = Tracker.new(blackboard)
tracker:refresh(now_ms)    -- Parse quest log
tracker:all()              -- Return all quests table
tracker:get(quest_id)      -- Specific quest
tracker:count()            -- Active quest count
```

The tracker merges live quest state with Questie:
```lua
-- During refresh:
if Questie.is_ready() then
    quest.questie = {
        doable = Questie.is_quest_doable(quest.quest_id),
        complete = Questie.is_quest_complete(quest.quest_id),
    }
end
```

### modules/quest/query_client.lua

HTTP client for SentinelQueryServer. Uses `core.http_get`.

```lua
local client = QueryClient.new(blackboard)

client:fetch_quest(quest_id)        -- Returns quest metadata
client:fetch_quest_npcs(quest_id, "giver")   -- Quest givers
client:fetch_quest_npcs(quest_id, "turnin")   -- Turn-in NPCs
```

### modules/quest/engine.lua

Route planning layer. Combines Tracker + QueryClient.

```lua
local engine = Engine.new(blackboard)

engine:get_quest_givers(quest_id, map_id)      -- Get giver NPCs
engine:get_quest_turnins(quest_id, map_id)     -- Get turn-in NPCs
engine:get_quest_data(quest_id)                -- Full quest metadata
engine:can_turn_in(quest_id)                   -- Check completion
engine:get_active_quests()                     -- All active quests with state
```

### modules/quest/interactions.lua

Gossip/NPC interaction primitives.

```lua
Interactions.is_open()              -- Gossip frame shown
Interactions.accept_available(id)   -- Accept quest
Interactions.complete_active(id)      -- Complete quest
Interactions.close()               -- Close gossip
```

### modules/quest/module.lua

Main module orchestrator.

```lua
local Quest = require("modules/quest/module")

Quest.new(event_bus, blackboard)
Quest:initialize()        -- Register callbacks, reset state
Quest:update(blackboard)  -- Periodic tracker refresh
Quest:set_enabled(bool)   -- Toggle module
Quest:get_tracker()       -- Access to QuestTracker
Quest:get_engine()        -- Access to QuestEngine
```

## Event Flow

1. **Game Event**: `QUEST_LOG_UPDATE` fires when quest log changes
2. **CallbackBridge**: Forwards event to EventBus as `game:quest_log_update`
3. **Quest Module**: Receives event, calls `tracker:refresh()`
4. **Tracker**: Parses `core.quests.*` APIs, merges Questie state
5. **Blackboard**: Stores `module.quest.quests` and `module.quest.active_count`

## Data Flow

1. **Quest Selection**: Engine queries database for available quests by zone
2. **Route Planning**: Uses SentinelNavServer to find path to giver NPC
3. **Objective Tracking**: Live state from Questie tracks progress
4. **Turn-in**: Query givers/turnins again for return NPC position

## Usage Example

```lua
-- In a grind/quest module
function quest_module:execute(blackboard)
    local engine = self:get_engine()
    local active = engine:get_active_quests()
    
    -- Filter for incomplete quests
    for _, quest in ipairs(active) do
        if not quest.complete then
            -- Get giver NPC
            local givers = engine:get_quest_givers(quest.quest_id, map_id)
            if #givers > 0 then
                -- Navigate to giver
                self._nav:move_to(givers[1].position)
                return
            end
        end
    end
end
```

## Quest Data Packs

Offline-generated JSON files in `sentinel/data/quests/`.

Currently available:
- `human_1_10.json` - Human starting zones (Northshire, Elwynn, Westfall, Redridge, Duskwood)

Generation tool: `modules/quest/generate_data_pack.lua` (requires `sqlite3 -json` CLI)