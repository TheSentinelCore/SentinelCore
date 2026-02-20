---
title: Constants
layout: default
parent: Reference
nav_order: 2
---

# Constants Reference
{: .no_toc }

Map ID mappings, indoor zone detection, and other constant values used by SentinelNavClient.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Continent IDs

SentinelNavServer uses integer continent IDs to identify which navmesh map data to query:

| ID | Continent | Description |
|:---|:----------|:------------|
| `0` | Eastern Kingdoms | Stormwind, Ironforge, Undercity, Silvermoon, all EK zones |
| `1` | Kalimdor | Orgrimmar, Thunder Bluff, Darnassus, Exodar, all Kalimdor zones |
| `530` | Outland | Shattrath, Hellfire Peninsula, all Outland zones |
| `571` | Northrend | Dalaran, Borean Tundra, all Northrend zones |

Instance/dungeon maps use their own map IDs (e.g., 33 for Shadowfang Keep, 36 for Deadmines). See the complete list in [Instance Map IDs](#instance-map-ids).

---

## UI_MAP_TO_CONTINENT

This table maps WoW UiMapIDs (returned by `core.get_map_id()`) to SentinelNavServer continent IDs. Navigation uses this for automatic map detection when `opts.map_id` is not explicitly provided.

### Eastern Kingdoms (Continent 0)

| UiMapID | Zone |
|:--------|:-----|
| 37 | Elwynn Forest |
| 42 | Deadwind Pass |
| 47 | Duskwood |
| 49 | Redridge Mountains |
| 51 | Swamp of Sorrows |
| 52 | Westfall |
| 56 | Wetlands |
| 84 | Stormwind City |
| 87 | Ironforge |
| 90 | Undercity |
| 94 | Eversong Woods |
| 95 | Ghostlands |
| 97 | Azuremyst Isle |
| 106 | Bloodmyst Isle |
| 110 | Silvermoon City |
| 122 | Isle of Quel'Danas |
| 124 | Stranglethorn Vale |
| 17 | Blasted Lands |
| 19 | Burning Steppes |
| 29 | Dun Morogh |
| 32 | Searing Gorge |
| 36 | Alterac Mountains |
| 39 | Arathi Highlands |
| 41 | Badlands |
| 14 | Tirisfal Glades |
| 18 | Silverpine Forest |
| 21 | Hillsbrad Foothills |
| 23 | Eastern Plaguelands |
| 25 | The Hinterlands |
| 27 | Western Plaguelands |
| 37 | Elwynn Forest |
| 48 | Loch Modan |

### Kalimdor (Continent 1)

| UiMapID | Zone |
|:--------|:-----|
| 57 | Teldrassil |
| 62 | Darkshore |
| 63 | Ashenvale |
| 64 | Thousand Needles |
| 65 | Stonetalon Mountains |
| 66 | Desolace |
| 69 | Feralas |
| 70 | Dustwallow Marsh |
| 71 | Tanaris |
| 73 | Un'Goro Crater |
| 76 | Azshara |
| 77 | Felwood |
| 78 | Winterspring |
| 80 | Moonglade |
| 81 | Silithus |
| 57 | Teldrassil |
| 61 | Orgrimmar |
| 62 | Darkshore |
| 69 | Feralas |
| 7 | Mulgore |
| 11 | The Barrens |
| 75 | Durotar |
| 83 | Thunder Bluff |
| 85 | Exodar |
| 86 | Darnassus |

### Outland (Continent 530)

| UiMapID | Zone |
|:--------|:-----|
| 100 | Hellfire Peninsula |
| 101 | Zangarmarsh |
| 104 | Shadowmoon Valley |
| 105 | Blade's Edge Mountains |
| 107 | Nagrand |
| 108 | Terokkar Forest |
| 109 | Netherstorm |
| 111 | Shattrath City |

### Northrend (Continent 571)

| UiMapID | Zone |
|:--------|:-----|
| 113 | Northrend |
| 114 | Borean Tundra |
| 115 | Dragonblight |
| 116 | Grizzly Hills |
| 117 | Howling Fjord |
| 118 | Icecrown |
| 119 | Sholazar Basin |
| 120 | The Storm Peaks |
| 121 | Zul'Drak |
| 123 | Wintergrasp |
| 125 | Dalaran |
| 127 | Crystalsong Forest |

{: .note }
If a UiMapID is not found in `UI_MAP_TO_CONTINENT`, Navigation defaults to continent `0` (Eastern Kingdoms).

---

## INDOOR_UI_MAPS

Boolean set of UiMapIDs for dungeon and raid zones. Used by `Navigation.is_indoor()` to determine whether corridor pathfinding should be used.

Contains all WotLK dungeons, raids, and indoor instances. When `is_indoor()` returns `true`:
- `move_to()` uses `find_path_corridor` instead of `find_path`
- Corridor widths are measured at each waypoint
- Waypoint tolerance is adapted to corridor width

### Dungeon UiMapIDs

Includes (but is not limited to):

| Type | Example Maps |
|:-----|:-------------|
| **Classic Dungeons** | Deadmines, Shadowfang Keep, Stockades, Gnomeregan, Scarlet Monastery, etc. |
| **Classic Raids** | Molten Core, Blackwing Lair, Ahn'Qiraj, Naxxramas (original) |
| **TBC Dungeons** | Hellfire Ramparts, Blood Furnace, Slave Pens, Mana-Tombs, Shadow Labyrinth, etc. |
| **TBC Raids** | Karazhan, Gruul's Lair, Magtheridon's Lair, Serpentshrine Cavern, Tempest Keep, etc. |
| **WotLK Dungeons** | Utgarde Keep, The Nexus, Azjol-Nerub, Halls of Lightning, etc. |
| **WotLK Raids** | Naxxramas, Obsidian Sanctum, Ulduar, Trial of the Crusader, Icecrown Citadel |
| **Battleground Instances** | Alterac Valley, Warsong Gulch, Arathi Basin, Eye of the Storm, etc. |

---

## Instance Map IDs

SentinelNavServer loads instance navmesh data using WoW's internal map IDs (different from UiMapIDs). These are used as the `map_id` parameter in Navigation endpoints:

| Map ID | Instance |
|:-------|:---------|
| 33 | Shadowfang Keep |
| 34 | Stormwind Stockade |
| 36 | Deadmines |
| 43 | Wailing Caverns |
| 47 | Razorfen Kraul |
| 48 | Blackfathom Deeps |
| 70 | Uldaman |
| 90 | Gnomeregan |
| 109 | Sunken Temple |
| 129 | Razorfen Downs |
| 189 | Scarlet Monastery |
| 209 | Zul'Farrak |
| 229 | Blackrock Spire |
| 230 | Blackrock Depths |
| 249 | Onyxia's Lair |
| 289 | Scholomance |
| 309 | Zul'Gurub |
| 329 | Stratholme |
| 349 | Maraudon |
| 389 | Ragefire Chasm |
| 409 | Molten Core |
| 429 | Dire Maul |
| 469 | Blackwing Lair |
| 509 | Ruins of Ahn'Qiraj |
| 531 | Temple of Ahn'Qiraj |
| 532 | Karazhan |
| 533 | Naxxramas |
| 534 | Hyjal Summit |
| 540 | Hellfire Ramparts |
| 542 | Blood Furnace |
| 543 | Shattered Halls |
| 544 | Magtheridon's Lair |
| 545 | Steamvault |
| 546 | Underbog |
| 547 | Slave Pens |
| 548 | Serpentshrine Cavern |
| 550 | Tempest Keep |
| 552 | The Arcatraz |
| 553 | The Botanica |
| 554 | The Mechanar |
| 555 | Shadow Labyrinth |
| 556 | Sethekk Halls |
| 557 | Mana-Tombs |
| 558 | Auchenai Crypts |
| 560 | Old Hillsbrad Foothills |
| 564 | Black Temple |
| 565 | Gruul's Lair |
| 568 | Zul'Aman |
| 580 | Sunwell Plateau |
| 585 | Magister's Terrace |

### Tile Counts

As of the 2026-02-17 full generation:

| Map | Tiles | Notes |
|:----|:------|:------|
| Map 0 (Eastern Kingdoms) | 687 | Largest continent |
| Map 1 (Kalimdor) | 1,018 | Largest tile count |
| Map 530 (Outland) | 800 | |
| **Total** | **2,748 tiles** | 72 maps, 2,820 files total |
| **Lost tiles** | 2 | Karazhan [532][35,52], Naxxramas [533][38,26] |

---

## Internal Constants

### Movement

| Constant | Value | Description |
|:---------|:------|:------------|
| `BASE_RUN_SPEED` | `7.0` | Base WoW run speed in yards/second |

### Obstacle

| Constant | Value | Description |
|:---------|:------|:------------|
| `collision_flags` | `0x00000001` | DoodadCollision flag for `trace_line` |

### Visualization

| Constant | Value | Description |
|:---------|:------|:------------|
| `Z_OFFSET` | `2.0` | Yards above ground for visualization elements |
| Path cull distance | 300 yards | |
| Destination cull distance | 300 yards | |
| Obstacle cull distance | 200 yards | |
| Text cull distance | 100 yards | |
| Corridor cull distance | 250 yards | |

### Navigation Retry

| Constant | Value | Description |
|:---------|:------|:------------|
| Retry delays | 0.5s, 1.0s, 2.0s | Exponential backoff |
| Retryable codes | 0, 500, 502, 503, 504 | HTTP status codes |
| Failure threshold | 3 | Consecutive failures before `is_available()` returns false |
