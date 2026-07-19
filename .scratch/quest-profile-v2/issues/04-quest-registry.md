---
id: 4
title: "QuestRegistry — On-Demand Query + LRU Cache for Quest/NPC Data"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:high", "size:medium"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

# QuestRegistry — On-Demand Query + LRU Cache for Quest/NPC Data

## Description

Replace `QuestGraph`'s graph-building logic with a lightweight `QuestRegistry` that provides on-demand access to quest and NPC data via `QueryClient` (HTTP → SentinelQueryServer → Mangos DB), with an LRU cache to avoid repeated queries.

## Requirements

### API

```lua
local registry = QuestRegistry.new(queryClient, {maxSize=500, ttlMs=300000})

-- Quest data
local quest = registry:getQuest(questId)  -- cached or fetched
local npcs = registry:getQuestNPCs(questId, "giver")  -- giver/turnin
local prereqs = registry:getPrerequisites(questId)  -- prev_quest_id chain

-- Search (for editor autocomplete)
local results = registry:searchQuests({zone="Elwynn Forest", minLevel=1, maxLevel=10, faction="Alliance"})
-- returns [{id, title, level, zone, start_npc, end_npc}] — top 20
```

### Cache Behavior

- LRU eviction when `maxSize` reached
- TTL expiration (5 min default) — stale entries refreshed on next access
- Separate caches: quest data, NPC data, search results
- Memory target: <2MB total (500 quests × ~2KB + 200 NPCs × ~1KB + search cache)

### Validation Support (for ProfileCompiler)

- `registry:validateQuestExists(id)` → bool + data
- `registry:validateNPCExists(id)` → bool + data
- `registry:validatePrerequisitesMet(id, completedQuestIds)` → bool + missing[]

## Acceptance Criteria

- [ ] `getQuest(id)` returns quest data on first call, cached on second
- [ ] Cache evicts LRU when `maxSize` exceeded
- [ ] TTL expiration forces refetch
- [ ] `searchQuests` hits QueryClient search endpoint (or filters locally if small dataset)
- [ ] Memory usage <2MB under normal operation
- [ ] No full DB preload on startup
- [ ] Thread-safe (single-threaded Lua, but no global state corruption)

## Blocked by

- `QueryClient` search endpoint may need extension (can mock for MVP)

## Files to Create

- `sentinel/modules/quest/quest_registry.lua`
- `sentinel/modules/quest/cache/lru_cache.lua` (reusable)

## Deprecates

- `QuestGraph:build_from_db` logic (replaced by on-demand queries)