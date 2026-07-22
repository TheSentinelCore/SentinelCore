---
title: "Game UI Functions"
source: "https://docs.project-sylvanas.net/dev/api/game-ui"
crawled: "2026-07-14"
---

# Game UI Functions

## Overview

The `core.game_ui` module provides functions for interacting with the World of Warcraft game interface. This includes accessing loot windows, battlefield information, cursor positions, and map utilities.

---

## Loot Window Functions

### `core.game_ui.get_loot_item_count`

**Syntax:**
```lua
core.game_ui.get_loot_item_count() -> integer
```

**Returns:** `integer` - The number of lootable items currently available in the loot window.

**Description:** Retrieves the number of items currently available in the loot window.

**Example Usage:**
```lua
local item_count = core.game_ui.get_loot_item_count()
core.log("Lootable items: " .. item_count)
```

---

### `core.game_ui.get_loot_item_id`

**Syntax:**
```lua
core.game_ui.get_loot_item_id(index: integer) -> integer
```

**Parameters:**
- `index`: `integer` - The index of the loot item.

**Returns:** `integer` - The ID of the lootable item.

**Description:** Retrieves the item ID of a lootable item at the specified index.

**Example Usage:**
```lua
local item_id = core.game_ui.get_loot_item_id(0)
core.log("First loot item ID: " .. item_id)
```

---

### `core.game_ui.get_loot_item_name`

**Syntax:**
```lua
core.game_ui.get_loot_item_name(index: integer) -> string
```

**Parameters:**
- `index`: `integer` - The index of the loot item.

**Returns:** `string` - The name of the lootable item.

**Description:** Retrieves the name of the lootable item at the specified index.

**Example Usage:**
```lua
local item_name = core.game_ui.get_loot_item_name(0)
core.log("First loot item: " .. item_name)
```

---

### `core.game_ui.get_loot_is_gold`

**Syntax:**
```lua
core.game_ui.get_loot_is_gold(index: integer) -> boolean
```

**Parameters:**
- `index`: `integer` - The index of the loot item.

**Returns:** `boolean` - `true` if the item is gold; otherwise, `false`.

**Description:** Checks if the lootable item at the specified index is gold.

**Example Usage:**
```lua
if core.game_ui.get_loot_is_gold(0) then
    core.log("First loot slot contains gold!")
end
```

---

## Loot Window - Complete Example

```lua
local function process_loot()
    local count = core.game_ui.get_loot_item_count()
    
    for i = 0, count - 1 do
        if core.game_ui.get_loot_is_gold(i) then
            core.log("Slot " .. i .. ": Gold")
        else
            local name = core.game_ui.get_loot_item_name(i)
            local id = core.game_ui.get_loot_item_id(i)
            core.log("Slot " .. i .. ": " .. name .. " (ID: " .. id .. ")")
        end
    end
end
```

---

## Battlefield Functions

### `core.game_ui.get_battlefield_status`

**Syntax:**
```lua
core.game_ui.get_battlefield_status(index: integer) -> string
```

**Parameters:**
- `index`: `integer` - The battlefield queue index.

**Returns:** `string` - The status of the battlefield queue.

**Possible Return Values:**

| Value | Description |
|-------|-------------|
| `"confirm"` | Battlefield is ready to join |
| `"queued"` | Currently in queue |
| `"active"` | Currently in the battlefield |
| `"error"` | Error state |
| `"none"` | Not queued |

**Example Usage:**
```lua
local status = core.game_ui.get_battlefield_status(1)
if status == "confirm" then
    core.log("Battlefield ready! Accept the queue.")
elseif status == "queued" then
    core.log("Waiting in queue...")
end
```

---

### `core.game_ui.get_battlefield_state`

**Syntax:**
```lua
core.game_ui.get_battlefield_state() -> integer
```

**Returns:** `integer` - The current state of the battlefield.

**State Values:**

| Value | Description |
|-------|-------------|
| `2` | Preparation phase |
| `3` | Active/In progress |
| `5` | Finished |

**Example Usage:**
```lua
local state = core.game_ui.get_battlefield_state()
if state == 2 then
    core.log("Battlefield starting soon - preparation phase")
elseif state == 3 then
    core.log("Battlefield in progress!")
elseif state == 5 then
    core.log("Battlefield finished")
end
```

---

### `core.game_ui.get_battlefield_run_time`

**Syntax:**
```lua
core.game_ui.get_battlefield_run_time() -> number
```

**Returns:** `number` - Timer in milliseconds since the battlefield started.

**Description:** Retrieves the time elapsed since the battlefield started.

**Example Usage:**
```lua
local run_time = core.game_ui.get_battlefield_run_time()
local minutes = math.floor(run_time / 60000)
local seconds = math.floor((run_time % 60000) / 1000)
core.log(string.format("Battlefield running for: %d:%02d", minutes, seconds))
```

---

### `core.game_ui.get_battlefield_winner`

**Syntax:**
```lua
core.game_ui.get_battlefield_winner() -> integer|nil
```

**Returns:** `integer|nil` - The winner of the battlefield, or `nil` if no winner yet.

**Return Values:**

| Value | Description |
|-------|-------------|
| `nil` | No winner yet (match in progress) |
| `0` | Horde won |
| `1` | Alliance won |
| `2` | Tie |

**Example Usage:**
```lua
local winner = core.game_ui.get_battlefield_winner()
if winner == nil then
    core.log("Match still in progress")
elseif winner == 0 then
    core.log("Horde wins!")
elseif winner == 1 then
    core.log("Alliance wins!")
elseif winner == 2 then
    core.log("It's a tie!")
end
```

---

### `core.game_ui.get_active_match_winner`

**Syntax:**
```lua
core.game_ui.get_active_match_winner() -> integer|nil
```

**Returns:** `integer|nil` - The winning faction index, or `nil` if the match has no winner yet.

**Description:** Retrieves the faction index of the team that won the active PvP match (wraps `C_PvP.GetActiveMatchWinner`). Returns `nil` while the match is still in progress or when the C_PvP API is unavailable.

**Return Values:**

| Value | Description |
|-------|-------------|
| `nil` | No winner yet (match in progress) or API unavailable |
| `0` | Horde won |
| `1` | Alliance won |

**Example Usage:**
```lua
local winner = core.game_ui.get_active_match_winner()
if winner == 0 then
    core.log("Horde won the match!")
elseif winner == 1 then
    core.log("Alliance won the match!")
else
    core.log("Match still in progress")
end
```

---

### `core.game_ui.get_active_match_state`

**Syntax:**
```lua
core.game_ui.get_active_match_state() -> integer
```

**Returns:** `integer` - The current PvP match state (`Enum.PvPMatchState`).

**Description:** Retrieves the current PvP match state (wraps `C_PvP.GetActiveMatchState`). This mirrors `get_battlefield_state` but is exposed under the C_PvP-style name for new logic. Returns `0` when the API is unavailable.

**State Values:**

| Value | Description |
|-------|-------------|
| `0` | Inactive |
| `1` | Waiting |
| `2` | StartUp |
| `3` | Engaged |
| `4` | PostRound |
| `5` | Complete |

**Example Usage:**
```lua
local state = core.game_ui.get_active_match_state()
if state == 3 then
    core.log("Match is engaged - fight!")
elseif state == 5 then
    core.log("Match complete")
end
```

---

### `core.game_ui.get_match_pvp_stat_column`

**Syntax:**
```lua
core.game_ui.get_match_pvp_stat_column(pvp_stat_id: integer) -> pvp_stat_column|nil
```

**Parameters:**
- `pvp_stat_id`: `integer` - The PvP stat ID of the column to fetch.

**Returns:** `pvp_stat_column|nil` - The scoreboard stat column, or `nil` if not found / unavailable.

**`pvp_stat_column` Properties:**

| Field | Type | Description |
|-------|------|-------------|
| `pvp_stat_id` | `integer` | The PvP stat ID this column reports |
| `column_header_id` | `integer` | The column header ID |
| `order_index` | `integer` | The display order index of the column |
| `name` | `string` | The localized column name |
| `tooltip_title` | `string` | The tooltip title for the column header |
| `tooltip` | `string` | The tooltip body text for the column header |

**Description:** Retrieves a single PvP scoreboard stat column by its PvP stat ID (wraps `C_PvP.GetMatchPVPStatColumn`).

**Example Usage:**
```lua
local column = core.game_ui.get_match_pvp_stat_column(123)
if column then
    core.log("Column: " .. column.name)
end
```

---

### `core.game_ui.get_match_pvp_stat_columns`

**Syntax:**
```lua
core.game_ui.get_match_pvp_stat_columns() -> pvp_stat_column[]
```

**Returns:** `pvp_stat_column[]` - An array of scoreboard stat column tables (empty if none / unavailable).

**Description:** Retrieves every PvP scoreboard stat column for the active match (wraps `C_PvP.GetMatchPVPStatColumns`). The columns describe the scoreboard layout (kills, damage, healing, etc.) for the current battleground or arena.

**Example Usage:**
```lua
local columns = core.game_ui.get_match_pvp_stat_columns()
for _, column in ipairs(columns) do
    core.log(string.format("[%d] %s", column.order_index, column.name))
end
```

---

### `core.game_ui.get_battlefield_arena_faction`

**Syntax:**
```lua
core.game_ui.get_battlefield_arena_faction() -> integer | nil
```

**Returns:** `integer | nil` - `0` = Horde, `1` = Alliance (your arena/battleground team), or `nil` if unavailable / not in a match.

**Description:** Returns the player's arena/battleground team faction (wraps `GetBattlefieldArenaFaction`). Useful for coloring friendly vs enemy scoreboard rows relative to your own team.

**Example Usage:**
```lua
local my_faction = core.game_ui.get_battlefield_arena_faction()
if my_faction then
    core.log(my_faction == 0 and "On Horde team" or "On Alliance team")
end
```

---

### `core.game_ui.get_active_match_personal_rated_info`

**Syntax:**
```lua
core.game_ui.get_active_match_personal_rated_info() -> pvp_personal_rated_info | nil
```

**Returns:** `pvp_personal_rated_info | nil` - The player's rated info for the active match, or `nil` outside a rated match.

| Field | Type | Description |
|-------|------|-------------|
| `personal_rating` | `integer` | Current personal rating for the active bracket |
| `best_season_rating` | `integer` | Best rating achieved this season |
| `best_weekly_rating` | `integer` | Best rating achieved this week |
| `season_played` | `integer` | Matches played this season |
| `season_won` | `integer` | Matches won this season |
| `weekly_played` | `integer` | Matches played this week |
| `weekly_won` | `integer` | Matches won this week |
| `last_weeks_best_rating` | `integer` | Best rating from last week |
| `has_won_bracket_today` | `boolean` | Whether a match in this bracket was won today |
| `tier` | `integer` | Current tier ID |
| `ranking` | `integer` | Ladder ranking |
| `rounds_season_played` | `integer` | Solo-shuffle rounds played this season (0 before patch 10.0) |
| `rounds_season_won` | `integer` | Solo-shuffle rounds won this season (0 before patch 10.0) |
| `rounds_weekly_played` | `integer` | Solo-shuffle rounds played this week (0 before patch 10.0) |
| `rounds_weekly_won` | `integer` | Solo-shuffle rounds won this week (0 before patch 10.0) |

**Description:** Returns the player's rated info for the active match (wraps `C_PvP.GetPVPActiveMatchPersonalRatedInfo`).

**Example Usage:**
```lua
local rated = core.game_ui.get_active_match_personal_rated_info()
if rated then
    core.log(string.format("Rating: %d (season: %d-%d)",
        rated.personal_rating, rated.season_won, rated.season_played - rated.season_won))
end
```

---

### `core.game_ui.get_score_info`

**Syntax:**
```lua
core.game_ui.get_score_info(index: integer) -> pvp_score_info | nil
```

**Parameters:**
- `index`: `integer` - 1-based scoreboard row index.

**Returns:** `pvp_score_info | nil` - The scoreboard row, or `nil` if not found / unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Player name (may include realm) |
| `guid` | `string` | Player GUID |
| `killing_blows` | `integer` | Killing blows |
| `honorable_kills` | `integer` | Honorable kills |
| `deaths` | `integer` | Deaths |
| `honor_gained` | `integer` | Honor gained this match |
| `faction` | `integer` | Faction index (0 = Horde, 1 = Alliance) |
| `race_name` | `string` | Localized race name |
| `class_name` | `string` | Localized class name |
| `class_token` | `string` | Locale-independent class token (e.g. `"MAGE"`) |
| `damage_done` | `integer` | Total damage done |
| `healing_done` | `integer` | Total healing done |
| `rating` | `integer` | Current rating |
| `rating_change` | `integer` | Rating change from this match |
| `prematch_mmr` | `integer` | Matchmaking rating before the match |
| `mmr_change` | `integer` | Matchmaking rating change from this match |
| `postmatch_mmr` | `integer` | Matchmaking rating after the match |
| `talent_spec` | `string` | Localized talent specialization name |
| `honor_level` | `integer` | Honor level |
| `role_assigned` | `integer` | Assigned role ID |
| `num_stats` | `integer` | Number of entries in the per-row stats array |

**Description:** Returns a scoreboard row for the active match by index (wraps `C_PvP.GetScoreInfo`).

**Example Usage:**
```lua
-- Print every scoreboard row's name, class and damage
local index = 1
while true do
    local row = core.game_ui.get_score_info(index)
    if not row then break end
    core.log(string.format("%s (%s): %d dmg, %d healing",
        row.name, row.class_token, row.damage_done, row.healing_done))
    index = index + 1
end
```

---

## Cursor Functions

### `core.game_ui.get_wow_cursor_position`

**Syntax:**
```lua
core.game_ui.get_wow_cursor_position() -> vec2
```

**Returns:** `vec2` - The cursor position in WoW UI coordinates.

**Description:** Retrieves the current WoW cursor position in UI coordinates.

**Example Usage:**
```lua
local cursor = core.game_ui.get_wow_cursor_position()
core.log(string.format("WoW Cursor: (%.2f, %.2f)", cursor.x, cursor.y))
```

---

### `core.game_ui.get_normalized_cursor_position`

**Syntax:**
```lua
core.game_ui.get_normalized_cursor_position() -> vec2
```

**Returns:** `vec2` - The cursor position normalized to 0-1 range.

**Description:** Retrieves the current cursor position in normalized coordinates (0-1 range).

**Example Usage:**
```lua
local cursor = core.game_ui.get_normalized_cursor_position()
core.log(string.format("Normalized Cursor: (%.3f, %.3f)", cursor.x, cursor.y))
```

---

### `core.game_ui.normalize_ui_position`

**Syntax:**
```lua
core.game_ui.normalize_ui_position(pos: vec2) -> vec2
```

**Parameters:**
- `pos`: `vec2` - The UI position to normalize.

**Returns:** `vec2` - The normalized position (0-1 range).

**Description:** Normalizes a UI position to the 0-1 range.

**Example Usage:**
```lua
local ui_pos = vec2.new(960, 540)
local normalized = core.game_ui.normalize_ui_position(ui_pos)
core.log(string.format("Normalized: (%.3f, %.3f)", normalized.x, normalized.y))
```

---

## Map Functions

### `core.game_ui.get_current_map_id`

**Syntax:**
```lua
core.game_ui.get_current_map_id() -> integer
```

**Returns:** `integer` - The ID of the current map.

**Description:** Retrieves the ID of the current map from the game UI context.

**Example Usage:**
```lua
local map_id = core.game_ui.get_current_map_id()
core.log("Current UI map ID: " .. map_id)
```

---

### `core.game_ui.is_map_open`

**Syntax:**
```lua
core.game_ui.is_map_open() -> boolean
```

**Returns:** `boolean` - `true` if the world map is currently open; otherwise, `false`.

**Description:** Checks whether the world map UI is currently open.

**Example Usage:**
```lua
if core.game_ui.is_map_open() then
    core.log("Map is open - player is checking their location")
else
    core.log("Map is closed")
end
```

**Example: Pause Navigation While Map Open:**
```lua
local function update_navigation()
    -- Don't process movement while player is looking at the map
    if core.game_ui.is_map_open() then
        return
    end
    
    -- Continue with navigation logic...
    movement:process()
end
```

---

### `core.game_ui.get_world_pos_from_map_pos`

**Syntax:**
```lua
core.game_ui.get_world_pos_from_map_pos(map_id: integer, map_pos: vec2) -> vec2
```

**Parameters:**
- `map_id`: `integer` - The map ID.
- `map_pos`: `vec2` - The position on the map (normalized 0-1 coordinates).

**Returns:** `vec2` - The X/Y world position (Z height not included).

**Description:** Converts a map position to world coordinates. Returns a `vec2` with X and Y in 3D world format - note that the Z (height) component is not included.

**Example Usage:**
```lua
local map_id = core.game_ui.get_current_map_id()
local map_pos = vec2.new(0.5, 0.5) -- Center of the map
local world_pos = core.game_ui.get_world_pos_from_map_pos(map_id, map_pos)
core.log(string.format("World position: (%.2f, %.2f)", world_pos.x, world_pos.y))
-- To get the Z coordinate, use:
local full_pos = vec3.new(world_pos.x, world_pos.y, 0)
local height = core.get_height_for_position(full_pos)
```

---

### `core.game_ui.get_map_top_left`

**Syntax:**
```lua
core.game_ui.get_map_top_left() -> vec2
```

**Returns:** `vec2` - The top-left corner of the world map frame in UI coordinates.

---

### `core.game_ui.get_map_bottom_right`

**Syntax:**
```lua
core.game_ui.get_map_bottom_right() -> vec2
```

**Returns:** `vec2` - The bottom-right corner of the world map frame in UI coordinates.

---

### `core.game_ui.ui_pos_to_screen_pos`

**Syntax:**
```lua
core.game_ui.ui_pos_to_screen_pos(ui_pos: vec2) -> vec2
```

**Parameters:**
- `ui_pos`: `vec2` - The position in UI coordinates.

**Returns:** `vec2` - The corresponding screen-space position in pixels.

**Description:** Converts a UI-space position to screen-space pixel coordinates.

---

### `core.game_ui.world_pos_to_map_pos_normalized`

**Syntax:**
```lua
core.game_ui.world_pos_to_map_pos_normalized(world_pos: vec3) -> vec2
```

**Parameters:**
- `world_pos`: `vec3` - A world position.

**Returns:** `vec2` - The normalized map position (0-1 range).

**Description:** Converts a 3D world position to normalized map coordinates.

---

## UI Scale Functions

### `core.game_ui.get_effective_scale`

**Syntax:**
```lua
core.game_ui.get_effective_scale() -> number
```

**Returns:** `number` - The effective UI scale factor.

**Description:** Retrieves the effective UI scale factor. This is used internally to convert between raw UI coordinates and screen-space coordinates.

**Example Usage:**
```lua
local scale = core.game_ui.get_effective_scale()
core.log("Effective UI scale: " .. scale)
```

---

## Vendor Functions

### `core.game_ui.get_vendor_item_count`

**Syntax:**
```lua
core.game_ui.get_vendor_item_count() -> integer
```

**Returns:** `integer` - The total number of items the current vendor has for sale.

**Example Usage:**
```lua
local count = core.game_ui.get_vendor_item_count()
core.log("Vendor has " .. count .. " items for sale")
```

---

### `core.game_ui.get_vendor_item_info`

**Syntax:**
```lua
core.game_ui.get_vendor_item_info(vendor_item_id: integer) -> vendor_item_info
```

**Parameters:**
- `vendor_item_id`: `integer` - The 1-based index of the vendor item.

**Returns:** `vendor_item_info` - A table containing the vendor item details.

**`vendor_item_info` Properties:**

| Field | Type | Description |
|-------|------|-------------|
| `cost` | `integer` | The cost of the item in copper |
| `is_usable` | `boolean` | Whether the item is usable by the player |
| `item_id` | `integer` | The item ID |
| `item_name` | `string` | The name of the item |
| `quantity` | `integer` | The quantity available |
| `vendor_item_index` | `integer` | The vendor slot index |

**Description:** Retrieves detailed information about a specific vendor item.

**Example Usage:**
```lua
local count = core.game_ui.get_vendor_item_count()
for i = 1, count do
    local info = core.game_ui.get_vendor_item_info(i)
    local gold = math.floor(info.cost / 10000)
    local silver = math.floor((info.cost % 10000) / 100)
    core.log(string.format("%s - %dg %ds (qty: %d)", info.item_name, gold, silver, info.quantity))
end
```

---

## Death & Resurrection Functions

### `core.game_ui.get_resurrect_corpse_delay`

**Syntax:**
```lua
core.game_ui.get_resurrect_corpse_delay() -> number
```

**Returns:** `number` - The delay in seconds before resurrection is possible.

**Example Usage:**
```lua
local delay = core.game_ui.get_resurrect_corpse_delay()
if delay > 0 then
    core.log("Can resurrect in " .. delay .. " seconds")
else
    core.log("Ready to resurrect!")
end
```

---

### `core.game_ui.get_corpse_position`

**Syntax:**
```lua
core.game_ui.get_corpse_position() -> vec3
```

**Returns:** `vec3` - The position of the player's corpse.

**Example Usage:**
```lua
local corpse_pos = core.game_ui.get_corpse_position()
core.log(string.format("Corpse at: (%.2f, %.2f, %.2f)", corpse_pos.x, corpse_pos.y, corpse_pos.z))
local player = core.object_manager.get_local_player()
if player then
    local player_pos = player:get_position()
    local distance = player_pos:dist_to(corpse_pos)
    core.log("Distance to corpse: " .. string.format("%.1f", distance) .. " yards")
end
```

---

## Quest Log Functions

### `core.game_ui.get_quest_log_count`

**Syntax:**
```lua
core.game_ui.get_quest_log_count() -> integer
```

**Returns:** `integer` - The total number of entries in the quest log (including headers).

**Description:** Returns the total number of entries in the quest log. This count includes both quest entries and zone header entries.

---

### `core.game_ui.get_quest_log_info`

**Syntax:**
```lua
core.game_ui.get_quest_log_info(quest_log_id: integer) -> quest_log_info
```

**Parameters:**
- `quest_log_id`: `integer` - The 1-based index of the quest log entry.

**Returns:** `quest_log_info` - A table containing the quest log entry details.

| Field | Type | Description |
|-------|------|-------------|
| `title` | `string` | The title of the quest |
| `level` | `integer` | The level of the quest |
| `suggested_group` | `string` | The suggested group size for the quest |
| `is_header` | `boolean` | Whether this entry is a header (zone name) rather than a quest |
| `is_collapsed` | `boolean` | Whether this header is collapsed |
| `is_complete` | `integer` | Quest completion status (1 = complete, -1 = failed, 0 = in progress) |
| `frequency` | `integer` | The quest frequency (0 = normal, 1 = daily, 2 = weekly) |
| `quest_id` | `integer` | The unique quest ID |
| `start_event` | `boolean` | Whether the quest has a start event |
| `display_quest_id` | `boolean` | Whether the quest ID should be displayed |
| `is_on_map` | `boolean` | Whether the quest is shown on the map |
| `has_local_poi` | `boolean` | Whether the quest has a local point of interest |
| `is_task` | `boolean` | Whether the quest is a bonus objective / world quest task |
| `is_bounty` | `boolean` | Whether the quest is a bounty (emissary) quest |
| `is_story` | `boolean` | Whether the quest is part of the zone story line |
| `is_hidden` | `boolean` | Whether the quest is hidden |
| `is_scaling` | `boolean` | Whether the quest scales with the player's level |

**Example Usage:**
```lua
local count = core.game_ui.get_quest_log_count()
for i = 1, count do
    local info = core.game_ui.get_quest_log_info(i)
    if info.is_header then
        core.log("--- " .. info.title .. " ---")
    else
        local status = info.is_complete == 1 and "COMPLETE" or "In Progress"
        core.log(string.format("  [%d] %s (Lv %d) - %s", info.quest_id, info.title, info.level, status))
    end
end
```

---

### `core.game_ui.get_all_completed_quest_ids`

**Syntax:**
```lua
core.game_ui.get_all_completed_quest_ids() -> integer[]
```

**Returns:** `integer[]` - An array of completed quest IDs.

**Example Usage:**
```lua
local completed = core.game_ui.get_all_completed_quest_ids()
core.log("Total completed quests: " .. #completed)
local target_quest_id = 12345
for _, quest_id in ipairs(completed) do
    if quest_id == target_quest_id then
        core.log("Quest " .. target_quest_id .. " has been completed!")
        break
    end
end
```

---

## Instance Functions

### `core.game_ui.reset_instances`

**Syntax:**
```lua
core.game_ui.reset_instances() -> nil
```

**Description:** Resets all instances for the local player.

**Example Usage:**
```lua
core.game_ui.reset_instances()
core.log("All instances have been reset")
```

---

## Tooltip Functions

### `core.game_ui.get_tooltip_info`

**Syntax:**
```lua
core.game_ui.get_tooltip_info() -> tooltip_info
```

**Returns:** `tooltip_info` - A table containing the current tooltip information.

| Field | Type | Description |
|-------|------|-------------|
| `type` | `string` | The tooltip type: `"unit"`, `"spell"`, `"item"`, or `""` |
| `id` | `integer` | The ID of the tooltip subject |
| `name` | `string` | The name of the tooltip subject |
| `num_lines` | `integer` | The number of lines in the tooltip |

**Example Usage:**
```lua
local info = core.game_ui.get_tooltip_info()
if info.type ~= "" then
    core.log(string.format("Tooltip: %s - %s (ID: %d)", info.type, info.name, info.id))
end
```

---

### `core.game_ui.add_tooltip_line`

**Syntax:**
```lua
core.game_ui.add_tooltip_line(text: string, r?: number, g?: number, b?: number) -> nil
```

**Parameters:**
- `text`: `string` - The text to add to the tooltip.
- `r` (optional): `number` - Red color component (0.0-1.0). Defaults to 1.0.
- `g` (optional): `number` - Green color component (0.0-1.0). Defaults to 1.0.
- `b` (optional): `number` - Blue color component (0.0-1.0). Defaults to 0.0.

**Description:** Adds a colored line to the GameTooltip. Default color is yellow (1.0, 1.0, 0.0).

**Example Usage:**
```lua
core.game_ui.add_tooltip_line("Custom info line", 0.0, 1.0, 0.0)
```

---

### `core.game_ui.add_tooltip_double_line`

**Syntax:**
```lua
core.game_ui.add_tooltip_double_line(left_text: string, right_text: string, lr?: number, lg?: number, lb?: number, rr?: number, rg?: number, rb?: number) -> nil
```

**Description:** Adds a double-line entry to the GameTooltip with separate left and right text, each with optional color.

**Example Usage:**
```lua
core.game_ui.add_tooltip_double_line("Item Level", "450", 1.0, 1.0, 1.0, 0.0, 1.0, 0.0)
```

---

## Countdown

### `core.game_ui.do_countdown`

**Syntax:**
```lua
core.game_ui.do_countdown(seconds: integer) -> boolean
```

**Parameters:**
- `seconds`: `integer` - The countdown duration in seconds.

**Returns:** `boolean` - Whether the countdown was started successfully.

**Description:** Starts a countdown timer in the party or raid group using `C_PartyInfo.DoCountdown`.

**Example Usage:**
```lua
local success = core.game_ui.do_countdown(10)
```

---

## Talents

### `core.game_ui.get_talent_info`

**Syntax:**
```lua
core.game_ui.get_talent_info(arg1: integer, arg2: integer, arg3?: integer) -> table
```

**Parameters:**
- `arg1`: `integer` - Tab index (Classic) or tier (Retail).
- `arg2`: `integer` - Talent index (Classic) or column (Retail).
- `arg3` (optional): `integer` - Is inspect flag (Classic) or spec group index (Retail).

**Returns:** `table` - Talent information. Fields vary by game version.

**Classic fields:** `name`, `texture`, `tier`, `column`, `rank`, `max_rank`, `is_exceptional`, `available`

**Retail fields:** `talent_id`, `name`, `texture`, `selected`, `available`, `spell_id`, `row`, `column`, `known`

**Example Usage:**
```lua
-- Classic: get info for tab 1, talent 3
local info = core.game_ui.get_talent_info(1, 3)
print(info.name, info.rank .. "/" .. info.max_rank)

-- Retail: get info for tier 2, column 1, active spec
local info = core.game_ui.get_talent_info(2, 1, 1)
print(info.name, info.spell_id)
```

---

### `core.game_ui.get_active_talents`

**Syntax:**
```lua
core.game_ui.get_active_talents() -> active_talent_entry[]
```

**Returns:** `active_talent_entry[]` - Array of tables, each containing:

| Field | Type | Description |
|-------|------|-------------|
| `node_id` | `integer` | The talent node ID |
| `spell_id` | `integer` | The spell ID associated with the talent |
| `name` | `string` | The talent name |
| `rank` | `integer` | The current rank purchased |
| `max_rank` | `integer` | The maximum rank available |

**Description:** Returns all active talent nodes for the player using the retail 10.0+ C_Traits API. Returns an empty table on classic.

**Example Usage:**
```lua
local talents = core.game_ui.get_active_talents()
for _, t in ipairs(talents) do
    print(t.name, t.spell_id, t.rank .. "/" .. t.max_rank)
end
```

---

## Complete Examples

### Example: Auto-Loot System

```lua
local function auto_loot()
    local count = core.game_ui.get_loot_item_count()
    if count == 0 then return end
    
    for i = 0, count - 1 do
        if core.game_ui.get_loot_is_gold(i) then
            core.input.loot_item(i)
        else
            local item_id = core.game_ui.get_loot_item_id(i)
            if should_loot_item(item_id) then
                core.input.loot_item(i)
            end
        end
    end
end
```

### Example: Battlefield Status Monitor

```lua
local function check_battlefield_status()
    for i = 1, 3 do
        local status = core.game_ui.get_battlefield_status(i)
        if status == "confirm" then
            core.graphics.add_notification(
                "bg_ready_" .. i,
                "Battlefield Ready!",
                "Queue " .. i .. " is ready to join",
                5000,
                color.new(0, 255, 0, 255)
            )
        end
    end
    
    local state = core.game_ui.get_battlefield_state()
    if state == 3 then
        local run_time = core.game_ui.get_battlefield_run_time()
        local minutes = math.floor(run_time / 60000)
        local seconds = math.floor((run_time % 60000) / 1000)
        core.log(string.format("Battlefield: %d:%02d", minutes, seconds))
    end
end
```

### Example: Corpse Run Helper

```lua
local function corpse_run_helper()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_dead() then return end
    
    local corpse_pos = core.game_ui.get_corpse_position()
    local player_pos = player:get_position()
    local distance = player_pos:dist_to(corpse_pos)
    
    core.graphics.line_3d(player_pos, corpse_pos, color.new(255, 255, 0, 200), 2)
    core.graphics.circle_3d(corpse_pos, 5, color.new(255, 255, 0, 200), 2)
    
    local screen_pos = core.graphics.w2s(corpse_pos)
    if screen_pos then
        core.graphics.text_2d(
            string.format("%.0f yards", distance),
            screen_pos,
            16,
            color.new(255, 255, 255, 255),
            true
        )
    end
    
    local delay = core.game_ui.get_resurrect_corpse_delay()
    if delay > 0 then
        core.log("Wait " .. delay .. " seconds to resurrect")
    end
end
```

### Example: Vendor Auto-Buy

```lua
local function buy_from_vendor(item_name, quantity)
    local count = core.game_ui.get_vendor_item_count()
    for i = 1, count do
        local info = core.game_ui.get_vendor_item_info(i)
        if info.item_name == item_name and info.is_usable then
            core.input.buy_item(i, quantity)
            local gold = math.floor(info.cost * quantity / 10000)
            core.log(string.format("Bought %dx %s for %dg", quantity, item_name, gold))
            return true
        end
    end
    core.log("Item not found at vendor: " .. item_name)
    return false
end
```
