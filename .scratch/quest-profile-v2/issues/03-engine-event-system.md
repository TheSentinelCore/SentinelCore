---
id: 3
title: "Engine Event System — Publish 20+ Game Events for Statechart"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:high", "size:medium"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

# Engine Event System — Publish 20+ Game Events for Statechart

## Description

Modify `Engine` and `Quest` module to publish structured game events via `event_bus` whenever relevant game state changes. The `StatechartExecutor` consumes these events to drive transitions.

## Events to Publish

| Event | Trigger | Payload |
|-------|---------|---------|
| `QuestAccepted` | Quest log update: new quest | `{questId, title, level}` |
| `QuestCompleted` | All objectives met (Questie + tracker) | `{questId}` |
| `QuestTurnedIn` | Quest removed from log + reward | `{questId, rewardChoice}` |
| `QuestFailed` | Quest abandoned/failed | `{questId, reason}` |
| `ObjectiveProgress` | Objective counter changed | `{questId, objectiveIndex, current, required}` |
| `InventoryChanged` | Bag slot count changed | `{freeSlots, totalSlots}` |
| `DurabilityChanged` | Equipment durability changed | `{slot, current, max, pct}` |
| `PlayerDied` | Death event | `{mapId, x, y, z}` |
| `PlayerResurrected` | Spirit rez or corpse recovery | `{mapId, x, y, z}` |
| `CombatStart` | Entered combat | `{targetGUID}` |
| `CombatEnd` | Left combat | `{targetGUID}` |
| `LootReady` | Lootable corpse with items | `{targetGUID, items[]}` |
| `LevelUp` | Player level increased | `{newLevel}` |
| `SkillUp` | Profession/weapon skill increased | `{skill, newValue}` |
| `ReputationChanged` | Faction standing changed | `{faction, standing}` |
| `ZoneChanged` | Map/zone transition | `{newZone, newMapId}` |
| `HearthstoneReady` | Hearthstone off cooldown | `{cooldownRemaining}` |
| `FlightPathDiscovered` | New flight path learned | `{nodeId, name}` |
| `RareSeen` | Rare NPC detected | `{npcId, name, x, y, z}` |
| `EliteSeen` | Elite NPC detected | `{npcId, name, x, y, z}` |
| `PlayerNearby` | Player within range | `{name, distance, isGM}` |
| `Stuck` | No position change >30s | `{x, y, z, duration}` |

## Implementation

- In `Engine:update()` or `Quest:update()`, track previous state for each event source
- On change, `self._event_bus:publish("quest:" .. eventName, payload)`
- Deduplicate: only publish when state actually changes
- Use existing blackboard keys: `player.level`, `player.position`, `system.map_id`, `module.quest.quests`, etc.

## Acceptance Criteria

- [x] All 20+ events published at correct moments
- [x] Payloads match specification exactly
- [x] No duplicate events for same state change
- [x] Event names prefixed with `quest:` (e.g., `quest:QuestAccepted`)
- [x] Performance: event detection adds <1ms per tick
- [x] Unit tests: each event fires once per state change, payload correct

## Blocked by

- **02-statechart-executor** — integration test needs executor (can develop in parallel)

## Files Modified

- `sentinel/modules/quest/engine.lua` — add event detection/publishing
- `sentinel/modules/quest/module.lua` — wire event bus to engine
- `sentinel/modules/quest/events.lua` — event name constants + payload builders + detector

# Engine Event System — Publish 20+ Game Events for Statechart

## Description

Modify `Engine` and `Quest` module to publish structured game events via `event_bus` whenever relevant game state changes. The `StatechartExecutor` consumes these events to drive transitions.

## Events to Publish

| Event | Trigger | Payload |
|-------|---------|---------|
| `QuestAccepted` | Quest log update: new quest | `{questId, title, level}` |
| `QuestCompleted` | All objectives met (Questie + tracker) | `{questId}` |
| `QuestTurnedIn` | Quest removed from log + reward | `{questId, rewardChoice}` |
| `QuestFailed` | Quest abandoned/failed | `{questId, reason}` |
| `ObjectiveProgress` | Objective counter changed | `{questId, objectiveIndex, current, required}` |
| `InventoryChanged` | Bag slot count changed | `{freeSlots, totalSlots}` |
| `DurabilityChanged` | Equipment durability changed | `{slot, current, max, pct}` |
| `PlayerDied` | Death event | `{mapId, x, y, z}` |
| `PlayerResurrected` | Spirit rez or corpse recovery | `{mapId, x, y, z}` |
| `CombatStart` | Entered combat | `{targetGUID}` |
| `CombatEnd` | Left combat | `{targetGUID}` |
| `LootReady` | Lootable corpse with items | `{targetGUID, items[]}` |
| `LevelUp` | Player level increased | `{newLevel}` |
| `SkillUp` | Profession/weapon skill increased | `{skill, newValue}` |
| `ReputationChanged` | Faction standing changed | `{faction, standing}` |
| `ZoneChanged` | Map/zone transition | `{newZone, newMapId}` |
| `HearthstoneReady` | Hearthstone off cooldown | `{cooldownRemaining}` |
| `FlightPathDiscovered` | New flight path learned | `{nodeId, name}` |
| `RareSeen` | Rare NPC detected | `{npcId, name, x, y, z}` |
| `EliteSeen` | Elite NPC detected | `{npcId, name, x, y, z}` |
| `PlayerNearby` | Player within range | `{name, distance, isGM}` |
| `Stuck` | No position change >30s | `{x, y, z, duration}` |

## Implementation

- In `Engine:update()` or `Quest:update()`, track previous state for each event source
- On change, `self._event_bus:publish("quest:" .. eventName, payload)`
- Deduplicate: only publish when state actually changes
- Use existing blackboard keys: `player.level`, `player.position`, `system.map_id`, `module.quest.quests`, etc.

## Acceptance Criteria

- [ ] All 20+ events published at correct moments
- [ ] Payloads match specification exactly
- [ ] No duplicate events for same state change
- [ ] Event names prefixed with `quest:` (e.g., `quest:QuestAccepted`)
- [ ] Performance: event detection adds <1ms per tick
- [ ] Unit tests: each event fires once per state change, payload correct

## Blocked by

- **02-statechart-executor** — integration test needs executor (can develop in parallel)

## Files to Modify

- `sentinel/modules/quest/engine.lua` — add event detection/publishing
- `sentinel/modules/quest/module.lua` — wire event bus to engine
- `sentinel/modules/quest/events.lua` — event name constants + payload builders