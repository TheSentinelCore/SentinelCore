---
title: "Addon Integrations"
source: "https://docs.project-sylvanas.net/dev/api/addons"
crawled: "2026-07-14"
---
# Addon Integration Functions

## Overview

The `core.addons` module provides functions for interacting with popular World of Warcraft addons. Each addon has its own sub-namespace. Always check `is_loaded()` before calling other functions in an addon's namespace, as the addon may not be installed or active.

---

## Zygor

### `core.addons.zygor.is_loaded`

Syntax

```
core.addons.zygor.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the Zygor addon is loaded and active.

Description

Returns whether the Zygor Guides addon is currently loaded. Always check this before calling other Zygor functions.

---

### `core.addons.zygor.has_current_step`

Syntax

```
core.addons.zygor.has_current_step() -> boolean
```

Returns

-   `boolean`: Whether Zygor currently has an active step.

Description

Returns whether Zygor has a current guide step available. If no guide is active or the guide is complete, this returns false.

---

### `core.addons.zygor.get_current_step`

Syntax

```
core.addons.zygor.get_current_step() -> table
```

Returns

-   `table`: Current Zygor step info containing `step_text` (string), `goal_text` (string), and other step properties.

Description

Returns detailed information about the current Zygor guide step, including the step text and goal text. Check `has_current_step()` before calling.

---

### `core.addons.zygor.get_current_stickies`

Syntax

```
core.addons.zygor.get_current_stickies() -> table[]
```

Returns

-   `table[]`: Array of sticky step tables.

Description

Returns an array of Zygor sticky steps. Sticky steps are persistent guide objectives that remain visible alongside the current step.

---

### `core.addons.zygor.get_objectives`

Syntax

```
core.addons.zygor.get_objectives() -> (number|string)[]
```

Returns

-   `(number|string)[]`: Array of objective values.

Description

Returns an array of objective values from the current Zygor guide step. Values may be numbers (for progress tracking) or strings (for text objectives).

---

### `core.addons.zygor.get_current_waypoint`

Syntax

```
core.addons.zygor.get_current_waypoint() -> zygor_waypoint_info
```

Returns

-   `zygor_waypoint_info`: A table with the following fields:
    -   `map_id`: `integer` - The map ID of the waypoint.
    -   `x`: `number` - The X coordinate (0-1 range).
    -   `y`: `number` - The Y coordinate (0-1 range).
    -   `dist`: `number` - Distance to the waypoint.
    -   `title`: `string` - Waypoint title text.
    -   `type`: `string` - Waypoint type identifier.
    -   `goal_num`: `integer` - Associated goal number.
    -   `is_manual`: `boolean` - Whether the waypoint was manually placed.

Description

Returns the current active Zygor waypoint with its location, distance, and metadata.

---

### `core.addons.zygor.get_step_waypoints`

Syntax

```
core.addons.zygor.get_step_waypoints() -> zygor_waypoint_info[]
```

Returns

-   `zygor_waypoint_info[]`: Array of waypoint tables (same structure as `get_current_waypoint`).

Description

Returns all waypoints associated with the current Zygor guide step. This may include multiple waypoints when a step has several objectives in different locations.

---

## RestedXP

The `core.addons.rested_xp` namespace reads guide state from the RestedXP Guides addon. Check `is_loaded()` before using it. `get_current_step()` and `get_current_waypoint()` return zero-valued tables when there is no active guide step or waypoint.

### `core.addons.rested_xp.is_loaded`

Syntax

```
core.addons.rested_xp.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether RestedXP Guides is loaded and available.

Description

Returns whether the RestedXP Guides addon is loaded. Use this before reading any RestedXP guide state.

**Example Usage**

```
if core.addons.rested_xp.is_loaded() then    core.log("RestedXP Guides is available")end
```

---

### `core.addons.rested_xp.has_current_step`

Syntax

```
core.addons.rested_xp.has_current_step() -> boolean
```

Returns

-   `boolean`: Whether RestedXP currently has an active guide step.

Description

Returns whether RestedXP has a non-empty current guide. Use this to distinguish an active step from the zero-valued result returned by `get_current_step()` when no guide is active.

**Example Usage**

```
if core.addons.rested_xp.is_loaded() and core.addons.rested_xp.has_current_step() then    core.log("RestedXP has an active step")end
```

---

### `core.addons.rested_xp.get_current_step`

Syntax

```
core.addons.rested_xp.get_current_step() -> rested_xp_step_info
```

Returns

-   `rested_xp_step_info`: The current step with these fields:
    -   `num`: `integer` - Current RestedXP step index.
    -   `is_complete`: `boolean` - Whether RestedXP marks the step complete.
    -   `goals`: `rested_xp_goal_info[]` - The step goals.
-   `rested_xp_goal_info`: Each goal contains `action` (`string`), `quest_id` (`integer`), `text` (`string`), `is_complete` (`boolean`), `text_only` (`boolean`), and `ids` (`integer[]`) for multi-quest goals.

Description

Returns the current RestedXP guide step. If no current step is available, `num` is `0` and `goals` is empty.

**Example Usage**

```
if core.addons.rested_xp.has_current_step() then    local step = core.addons.rested_xp.get_current_step()    core.log("RestedXP step " .. step.num)end
```

---

### `core.addons.rested_xp.get_current_stickies`

Syntax

```
core.addons.rested_xp.get_current_stickies() -> rested_xp_step_info[]
```

Returns

-   `rested_xp_step_info[]`: Sticky guide steps, using the same fields as `get_current_step()`.

Description

Returns RestedXP sticky steps that remain visible beside the current guide step. The current step itself is not included.

**Example Usage**

```
for _, step in ipairs(core.addons.rested_xp.get_current_stickies()) do    core.log("Sticky step " .. step.num)end
```

---

### `core.addons.rested_xp.get_objectives`

Syntax

```
core.addons.rested_xp.get_objectives(quest_id: integer) -> rested_xp_objective_info[]
```

**Parameters**

-   `quest_id`: `integer` - The quest ID to inspect.

Returns

-   `rested_xp_objective_info[]`: An array of objective tables. Each contains `text` (`string`), `type` (`string`), `num_required` (`integer`), `num_fulfilled` (`integer`), and `finished` (`boolean`).

Description

Returns the RestedXP objective progress for the supplied quest. It returns an empty array when RestedXP has no matching objective data.

**Example Usage**

```
local objectives = core.addons.rested_xp.get_objectives(783)for _, objective in ipairs(objectives) do    core.log(objective.text .. ": " .. objective.num_fulfilled .. "/" .. objective.num_required)end
```

---

### `core.addons.rested_xp.get_current_waypoint`

Syntax

```
core.addons.rested_xp.get_current_waypoint() -> rested_xp_waypoint_info
```

Returns

-   `rested_xp_waypoint_info`: The current waypoint with `map_id` (`integer`), `x` and `y` (`number`, normalized to 0-1), `dist` (`number`), `title` (`string`), `type` (`string`), `goal_num` (`integer`), `is_manual` (`boolean`), and `wrong_continent` (`boolean`).

Description

Returns RestedXP's current arrow target. When `wrong_continent` is true, `dist` is not meaningful. If no waypoint is active, the returned fields use zero or empty values.

**Example Usage**

```
local waypoint = core.addons.rested_xp.get_current_waypoint()if waypoint.map_id ~= 0 and not waypoint.wrong_continent then    core.log(waypoint.title .. ": " .. waypoint.dist)end
```

---

### `core.addons.rested_xp.get_step_waypoints`

Syntax

```
core.addons.rested_xp.get_step_waypoints() -> rested_xp_waypoint_info[]
```

Returns

-   `rested_xp_waypoint_info[]`: Active RestedXP waypoints for the current step, using the same fields as `get_current_waypoint()`.

Description

Returns RestedXP waypoints for active steps only. Future guide look-ahead waypoints are excluded. The `dist` field is `0` for this list because RestedXP only exposes distance for the current arrow target.

**Example Usage**

```
for _, waypoint in ipairs(core.addons.rested_xp.get_step_waypoints()) do    core.log(waypoint.title .. " on map " .. waypoint.map_id)end
```

---

## BigWigs

### `core.addons.bigwigs.is_loaded`

Syntax

```
core.addons.bigwigs.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the BigWigs addon is loaded and active.

Description

Returns whether the BigWigs boss mod addon is currently loaded. Always check this before calling other BigWigs functions.

---

### `core.addons.bigwigs.has_active_bars`

Syntax

```
core.addons.bigwigs.has_active_bars() -> boolean
```

Returns

-   `boolean`: Whether there are any active BigWigs timer bars.

Description

Returns whether BigWigs currently has any active timer bars displayed. Use this as a quick check before iterating over bars.

---

### `core.addons.bigwigs.get_bars`

Syntax

```
core.addons.bigwigs.get_bars() -> bigwigs_bar_info[]
```

Returns

-   `bigwigs_bar_info[]`: Array of bar tables, each containing:
    -   `key`: `integer` - Unique bar identifier.
    -   `text`: `string` - The bar label text (ability name).
    -   `remaining`: `number` - Seconds remaining on the timer.
    -   `duration`: `number` - Total duration of the timer in seconds.
    -   `expire_time`: `number` - Game time when the bar expires.
    -   `is_emphasized`: `boolean` - Whether the bar is emphasized (important/imminent).

Description

Returns all active BigWigs timer bars. Each bar represents an upcoming boss ability or mechanic with timing information.

---

## Conroc

### `core.addons.conroc.is_loaded`

Syntax

```
core.addons.conroc.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the Conroc addon is loaded and active.

Description

Returns whether the Conroc rotation helper addon is currently loaded. Always check this before calling other Conroc functions.

---

### `core.addons.conroc.get_suggested_spells`

Syntax

```
core.addons.conroc.get_suggested_spells() -> table
```

Returns

-   `table`: The suggested spell list from Conroc.

Description

Returns the list of spells that Conroc is currently suggesting for the player's rotation. These represent the optimal next abilities to use.

---

### `core.addons.conroc.get_suggested_utility_spells`

Syntax

```
core.addons.conroc.get_suggested_utility_spells() -> table
```

Returns

-   `table`: The suggested utility spell list from Conroc.

Description

Returns the list of utility spells that Conroc is currently suggesting. These are non-rotational spells such as interrupts, defensives, or movement abilities.

---

## Questie

### `core.addons.questie.is_loaded`

Syntax

```
core.addons.questie.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the Questie addon is loaded and active.

Description

Returns whether the Questie quest helper addon is currently loaded. Always check this before calling other Questie functions.

---

### `core.addons.questie.get_quest_npc_ids`

Syntax

```
core.addons.questie.get_quest_npc_ids() -> integer[]
```

Returns

-   `integer[]`: NPC IDs related to the player's active quests.

Description

Returns a table of NPC IDs that are relevant to the player's current quests, as tracked by Questie. This can be used to identify quest targets in the game world.

---

### `core.addons.questie.get_quest_ids`

Syntax

```
core.addons.questie.get_quest_ids() -> integer[]
```

Returns

-   `integer[]`: Every quest ID in Questie's compiled quest database, or an empty array when Questie is not ready.

Description

Returns all quest IDs indexed by Questie's compiled quest database. This is the complete Questie ID set, not only the player's active quests. Call `is_ready()` first when readiness matters.

**Example Usage**

```
if core.addons.questie.is_ready() then    local quest_ids = core.addons.questie.get_quest_ids()    core.log("Questie indexes " .. #quest_ids .. " quests")end
```

---

### `core.addons.questie.is_ready`

Syntax

```
core.addons.questie.is_ready() -> boolean
```

Returns

-   `boolean`: Whether Questie is loaded and its API is ready.

Description

Returns whether Questie's API and database are ready for query calls. Use this before calling the `query_*_single` helpers if your code needs a quick readiness gate.

---

### `core.addons.questie.query_quest_single`

Syntax

```
core.addons.questie.query_quest_single(quest_id: integer, key: string) -> questie_query_value|nil
```

**Parameters**

-   `quest_id`: `integer` - The Questie quest ID.
-   `key`: `string` - The QuestieDB field key to read.

Returns

-   `questie_query_value|nil`: A number, string, boolean, nested query table, or nil when Questie is not ready or the key is missing.

Description

Queries a single field from Questie's quest database.

---

### `core.addons.questie.query_npc_single`

Syntax

```
core.addons.questie.query_npc_single(npc_id: integer, key: string) -> questie_query_value|nil
```

**Parameters**

-   `npc_id`: `integer` - The NPC ID.
-   `key`: `string` - The QuestieDB field key to read.

Returns

-   `questie_query_value|nil`: A number, string, boolean, nested query table, or nil when Questie is not ready or the key is missing.

Description

Queries a single field from Questie's NPC database.

---

### `core.addons.questie.query_object_single`

Syntax

```
core.addons.questie.query_object_single(object_id: integer, key: string) -> questie_query_value|nil
```

**Parameters**

-   `object_id`: `integer` - The object ID.
-   `key`: `string` - The QuestieDB field key to read.

Returns

-   `questie_query_value|nil`: A number, string, boolean, nested query table, or nil when Questie is not ready or the key is missing.

Description

Queries a single field from Questie's object database.

---

### `core.addons.questie.query_item_single`

Syntax

```
core.addons.questie.query_item_single(item_id: integer, key: string) -> questie_query_value|nil
```

**Parameters**

-   `item_id`: `integer` - The item ID.
-   `key`: `string` - The QuestieDB field key to read.

Returns

-   `questie_query_value|nil`: A number, string, boolean, nested query table, or nil when Questie is not ready or the key is missing.

Description

Queries a single field from Questie's item database.

---

### `core.addons.questie.is_quest_doable`

Syntax

```
core.addons.questie.is_quest_doable(quest_id: integer) -> boolean|nil
```

**Parameters**

-   `quest_id`: `integer` - The Questie quest ID.

Returns

-   `boolean|nil`: True if doable, false if not doable, or nil if Questie is not ready.

Description

Returns whether Questie considers the quest doable for the current character.

---

### `core.addons.questie.is_quest_complete`

Syntax

```
core.addons.questie.is_quest_complete(quest_id: integer) -> integer|nil
```

**Parameters**

-   `quest_id`: `integer` - The Questie quest ID.

Returns

-   `integer|nil`: `1` for complete, `0` for incomplete, `-1` for failed, or nil if Questie is not ready.

Description

Returns Questie's completion status for a quest.

---

## TSM (TradeSkillMaster)

### `core.addons.tsm.is_loaded`

Syntax

```
core.addons.tsm.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the TSM addon is loaded and active.

Description

Returns whether the TradeSkillMaster addon is currently loaded. Always check this before calling other TSM functions.

---

### `core.addons.tsm.get_item_prices`

Syntax

```
core.addons.tsm.get_item_prices(item_id: integer) -> table
```

**Parameters**

-   `item_id`: `integer` - The item ID to look up prices for.

Returns

-   `table`: TSM price data for the item.

Description

Returns TSM price data for a specific item. The returned table contains various price points tracked by TSM such as market value, historical price, and sale averages.

---

### `core.addons.tsm.get_market_data`

Syntax

```
core.addons.tsm.get_market_data(item_ids: integer[]) -> table
```

**Parameters**

-   `item_ids`: `integer[]` - Array of item IDs to look up market data for.

Returns

-   `table`: Bulk market data for all requested items.

Description

Returns market data for multiple items at once. More efficient than calling `get_item_prices` individually when you need data for many items.

---

### `core.addons.tsm.get_sniper_max_price`

Syntax

```
core.addons.tsm.get_sniper_max_price(item_id: integer) -> number
```

**Parameters**

-   `item_id`: `integer` - The item ID to check.

Returns

-   `number`: The sniper threshold price in copper.

Description

Returns the maximum price threshold for TSM's sniper feature for the given item. Prices are in copper (1 gold = 10000 copper).

---

### `core.addons.tsm.get_shopping_max_price`

Syntax

```
core.addons.tsm.get_shopping_max_price(item_id: integer) -> number
```

**Parameters**

-   `item_id`: `integer` - The item ID to check.

Returns

-   `number`: The shopping maximum price in copper.

Description

Returns the maximum shopping price for an item as configured in TSM shopping operations. Prices are in copper.

---

### `core.addons.tsm.get_auctioning_prices`

Syntax

```
core.addons.tsm.get_auctioning_prices(item_id: integer) -> table
```

**Parameters**

-   `item_id`: `integer` - The item ID to check.

Returns

-   `table`: A table containing `min_price`, `normal_price`, and `max_price` fields (all in copper).

Description

Returns the auctioning operation prices for an item. The returned table contains the minimum, normal, and maximum posting prices as configured in TSM auctioning operations.

---

### `core.addons.tsm.get_shopping_restock_quantity`

Syntax

```
core.addons.tsm.get_shopping_restock_quantity(item_id: integer) -> integer
```

**Parameters**

-   `item_id`: `integer` - The item ID to check.

Returns

-   `integer`: The restock quantity needed.

Description

Returns how many of an item need to be purchased to reach the restock target as defined in TSM shopping operations.

---

## Details

### `core.addons.details.is_loaded`

Syntax

```
core.addons.details.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the Details addon is loaded and active.

Description

Returns whether the Details! Damage Meter addon is currently loaded. Always check this before calling other Details functions.

---

### `core.addons.details.get_combat_info`

Syntax

```
core.addons.details.get_combat_info(segment_id?: integer) -> table
```

**Parameters**

-   `segment_id` (optional): `integer` - The segment ID. `0` = current (default), `-1` = overall, `1-25` = specific segment.

Returns

-   `table`: Combat information with the following fields:

Field

Type

Description

`combat_time`

`number`

Combat duration in seconds

`combat_name`

`string`

The combat/encounter name

`total_damage`

`number`

Total damage dealt in the segment

`total_healing`

`number`

Total healing done in the segment

Description

Returns summary information about a combat segment, including total damage, healing, and duration.

---

### `core.addons.details.get_damage_done`

Syntax

```
core.addons.details.get_damage_done(segment_id?: integer) -> table[]
```

**Parameters**

-   `segment_id` (optional): `integer` - The segment ID. `0` = current (default), `-1` = overall, `1-25` = specific segment.

Returns

-   `table[]`: Array of actor entries with the following fields:

Field

Type

Description

`name`

`string`

Actor name

`class_id`

`integer`

Class ID

`total`

`number`

Total damage dealt

`per_second`

`number`

Damage per second (DPS)

`is_player`

`boolean`

Whether the actor is a player

`is_group_member`

`boolean`

Whether the actor is in the group

`unit`

`game_object|nil`

The game object if found in the world

Description

Returns per-actor damage done data for a combat segment. The `unit` field is resolved by matching the actor name against visible game objects.

---

### `core.addons.details.get_healing_done`

Syntax

```
core.addons.details.get_healing_done(segment_id?: integer) -> table[]
```

**Parameters**

-   `segment_id` (optional): `integer` - The segment ID. `0` = current (default), `-1` = overall, `1-25` = specific segment.

Returns

-   `table[]`: Array of actor entries (same structure as `get_damage_done`).

Description

Returns per-actor healing done data for a combat segment.

---

### `core.addons.details.get_damage_taken`

Syntax

```
core.addons.details.get_damage_taken(segment_id?: integer) -> table[]
```

**Parameters**

-   `segment_id` (optional): `integer` - The segment ID. `0` = current (default), `-1` = overall, `1-25` = specific segment.

Returns

-   `table[]`: Array of actor entries (same structure as `get_damage_done`).

Description

Returns per-actor damage taken data for a combat segment.

---

### `core.addons.details.get_segments`

Syntax

```
core.addons.details.get_segments() -> table[]
```

Returns

-   `table[]`: Array of segment entries with the following fields:

Field

Type

Description

`index`

`integer`

The segment index

`name`

`string`

The segment name

`duration`

`number`

The segment duration in seconds

Description

Returns all available combat segments from the Details addon.

---

## Timeline Reminders

### `core.addons.timeline_reminders.is_loaded`

Syntax

```
core.addons.timeline_reminders.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the Timeline Reminders addon is loaded and active.

Description

Returns whether the Timeline Reminders addon is currently loaded. Always check this before calling other Timeline Reminders functions.

---

### `core.addons.timeline_reminders.get_reminders`

Syntax

```
core.addons.timeline_reminders.get_reminders(encounter_id: integer, difficulty_id: integer) -> table[]
```

**Parameters**

-   `encounter_id`: `integer` - The encounter ID.
-   `difficulty_id`: `integer` - The difficulty ID.

Returns

-   `table[]`: Array of reminder entries with the following fields:

Field

Type

Description

`trigger_time`

`number`

Time in seconds when the reminder triggers

`duration`

`number`

Duration of the reminder in seconds

`linger`

`number`

Linger time after the reminder fires

`hide_on_use`

`boolean`

Whether to hide after triggering

`region`

`string`

Display region

`display_type`

`string`

Display type

`spell_id`

`integer`

Associated spell ID

`text`

`string`

Reminder text

`load_type`

`string`

Load condition type

`load_class`

`string`

Class load condition

`load_spec`

`integer`

Specialization load condition

`load_role`

`string`

Role load condition

`load_name`

`string`

Name load condition

`countdown_enabled`

`boolean`

Whether countdown is enabled

`countdown_start`

`integer`

Countdown start time in seconds

Description

Returns all configured reminders for a specific encounter and difficulty. Each reminder includes trigger timing, display settings, and load conditions for filtering by class/spec/role.

---

## MaxDps

### `core.addons.maxdps.is_loaded`

Syntax

```
core.addons.maxdps.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the MaxDps addon is loaded and active.

Description

Returns whether the MaxDps rotation helper addon is currently loaded. Always check this before calling other MaxDps functions.

**Example Usage**

```
if core.addons.maxdps.is_loaded() then    local spell_id = core.addons.maxdps.get_next_spell()    core.log("MaxDps suggests spell: " .. spell_id)end
```

---

### `core.addons.maxdps.get_next_spell`

Syntax

```
core.addons.maxdps.get_next_spell() -> integer
```

Returns

-   `integer`: The spell ID of the next recommended ability from MaxDps.

Description

Returns the spell ID that MaxDps is currently recommending as the next ability to cast. This is the spell that MaxDps highlights on the action bars.

**Example Usage**

```
if core.addons.maxdps.is_loaded() then    local next_spell = core.addons.maxdps.get_next_spell()    if next_spell > 0 then        core.log("Next recommended spell ID: " .. next_spell)    endend
```

---

## Swing Timer

### `core.addons.swing_timer.is_loaded`

Syntax

```
core.addons.swing_timer.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether the Swing Timer addon is loaded and active.

Description

Returns whether the Swing Timer addon is currently loaded. Always check this before calling other Swing Timer functions.

**Example Usage**

```
if core.addons.swing_timer.is_loaded() then    local info = core.addons.swing_timer.get_player_ranged_info()    core.log("Last swing: " .. info.last_swing)end
```

---

### `core.addons.swing_timer.get_player_ranged_info`

Syntax

```
core.addons.swing_timer.get_player_ranged_info() -> swing_timer_ranged_info
```

Returns

-   `table`: A table containing the player's ranged swing timer data:

Field

Type

Description

`expiration_time`

`number`

The time when the current auto-shot expires

`last_swing`

`number`

The time of the last ranged swing

`auto_shot_cast_time`

`number`

The cast time of the auto-shot

Description

Returns the player's ranged auto-shot swing timer information. Useful for tracking auto-shot timing in ranged rotations to avoid clipping auto-shots.

**Example Usage**

```
if core.addons.swing_timer.is_loaded() then    local info = core.addons.swing_timer.get_player_ranged_info()    local current_time = core.time()    local time_until_next = info.expiration_time - current_time    if time_until_next > 0 then        core.log("Next auto-shot in: " .. string.format("%.2f", time_until_next) .. "s")    endend
```

---

### `core.addons.swing_timer.get_player_mainhand_info`

Syntax

```
core.addons.swing_timer.get_player_mainhand_info() -> swing_timer_hand_info
```

Returns

-   `table`: Main-hand swing timer info.

Field

Type

Description

`expiration_time`

`number`

The time when the current melee swing expires

`last_swing`

`number`

The time of the last melee swing

`swing_speed`

`number`

Current melee swing speed

`base_swing_speed`

`number`

Base melee swing speed

---

### `core.addons.swing_timer.get_player_offhand_info`

Syntax

```
core.addons.swing_timer.get_player_offhand_info() -> swing_timer_hand_info|nil
```

Returns

-   `table|nil`: Off-hand swing timer info, or nil when the player is not dual wielding.

The returned table has the same fields as `get_player_mainhand_info`.

---

## Arena Core

### `core.addons.arena_core.is_loaded`

Syntax

```
core.addons.arena_core.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether Arena Core is loaded and available.

Description

Returns whether Arena Core data can be read.

---

### `core.addons.arena_core.get_frame_info`

Syntax

```
core.addons.arena_core.get_frame_info(arena_index) -> arena_core_frame_info|nil
```

**Parameters**

-   `arena_index`: `integer` - The arena frame index.

Returns

-   `table|nil`: Arena frame info, or nil when unavailable.

Field

Type

Description

`unit`

`string`

Arena unit token, such as `arena1`

`id`

`integer`

Arena frame ID

`class`

`string`

Class name

`spec_id`

`integer`

Specialization ID

`spec_icon_texture`

`string`

Specialization icon texture path

`class_icon`

`integer`

Class icon texture ID

`spec_icon`

`integer`

Specialization icon texture ID

---

### `core.addons.arena_core.get_class`

Syntax

```
core.addons.arena_core.get_class(arena_index) -> string
```

**Parameters**

-   `arena_index`: `integer` - The arena frame index.

Returns

-   `string`: The class name, or an empty string when unavailable.

---

### `core.addons.arena_core.get_spec_id`

Syntax

```
core.addons.arena_core.get_spec_id(arena_index) -> integer
```

**Parameters**

-   `arena_index`: `integer` - The arena frame index.

Returns

-   `integer`: The specialization ID, or 0 when unavailable.

---

## Method Dungeon Tools

### `core.addons.mdt.is_loaded`

Syntax

```
core.addons.mdt.is_loaded() -> boolean
```

Returns

-   `boolean`: Whether Method Dungeon Tools is loaded and available.

---

### `core.addons.mdt.get_current_preset_meta`

Syntax

```
core.addons.mdt.get_current_preset_meta() -> mdt_preset_meta|nil
```

Returns

-   `table|nil`: Current MDT preset metadata, or nil when unavailable.

Field

Type

Description

`text`

`string`

Current preset display text

`current_dungeon_idx`

`integer`

Current MDT dungeon index

`current_pull`

`integer`

Current pull index

`current_sublevel`

`integer`

Current dungeon sublevel

`week`

`integer`

Configured affix week

`difficulty`

`integer`

Configured difficulty

`uid`

`string`

Preset UID

---

### `core.addons.mdt.get_pull_count`

Syntax

```
core.addons.mdt.get_pull_count() -> integer
```

Returns

-   `integer`: Number of pulls in the current preset.

---

### `core.addons.mdt.get_pull`

Syntax

```
core.addons.mdt.get_pull(pull_idx) -> mdt_pull|nil
```

**Parameters**

-   `pull_idx`: `integer` - The pull index.

Returns

-   `table|nil`: Pull data, or nil when unavailable.

Field

Type

Description

`color`

`string`

Pull color

`enemies`

`table[]`

Entries containing `enemy_idx` and `clones`

Each `enemies` entry contains `enemy_idx` (`integer`) and `clones` (`integer[]`).

---

### `core.addons.mdt.get_object_count`

Syntax

```
core.addons.mdt.get_object_count() -> integer
```

Returns

-   `integer`: Number of MDT map objects in the current preset.

---

### `core.addons.mdt.get_object`

Syntax

```
core.addons.mdt.get_object(obj_idx) -> mdt_object|nil
```

**Parameters**

-   `obj_idx`: `integer` - The object index.

Returns

-   `table|nil`: Map object data, or nil when unavailable.

Field

Type

Description

`kind`

`string`

`line`, `arrow`, `note`, or `unknown`

`color`

`string`

Object color

`note_text`

`string`

Note text

`note_x`

`number`

Note X coordinate

`note_y`

`number`

Note Y coordinate

`arrow_angle`

`number`

Arrow angle

`points`

`number[]`

Flat array of object points

---

### `core.addons.mdt.get_dungeon_enemy_count`

Syntax

```
core.addons.mdt.get_dungeon_enemy_count(dungeon_idx) -> integer
```

**Parameters**

-   `dungeon_idx`: `integer` - The MDT dungeon index.

Returns

-   `integer`: Number of enemies in the dungeon's MDT data.

---

### `core.addons.mdt.get_dungeon_enemy_info`

Syntax

```
core.addons.mdt.get_dungeon_enemy_info(dungeon_idx, enemy_idx) -> mdt_dungeon_enemy_info|nil
```

**Parameters**

-   `dungeon_idx`: `integer` - The MDT dungeon index.
-   `enemy_idx`: `integer` - The enemy index.

Returns

-   `table|nil`: Static dungeon enemy info, or nil when unavailable.

Field

Type

Description

`name`

`string`

Enemy name

`id`

`integer`

NPC ID

`count`

`integer`

Enemy count value

`health`

`integer`

Enemy health value

`scale`

`number`

Enemy scale

`display_id`

`integer`

Display ID

`creature_type`

`string`

Creature type

`level`

`integer`

Enemy level

`is_boss`

`boolean`

Whether this enemy is a boss

`encounter_id`

`integer`

Encounter ID

`instance_id`

`integer`

Instance ID

`clone_count`

`integer`

Number of clone placements

---

### `core.addons.mdt.get_dungeon_enemy_clone`

Syntax

```
core.addons.mdt.get_dungeon_enemy_clone(dungeon_idx, enemy_idx, clone_idx) -> mdt_dungeon_enemy_clone|nil
```

**Parameters**

-   `dungeon_idx`: `integer` - The MDT dungeon index.
-   `enemy_idx`: `integer` - The enemy index.
-   `clone_idx`: `integer` - The clone index.

Returns

-   `table|nil`: Clone placement info, or nil when unavailable.

Field

Type

Description

`x`

`number`

Clone X coordinate

`y`

`number`

Clone Y coordinate

`g`

`integer`

Clone group

`sublevel`

`integer`

Dungeon sublevel

`scale`

`number`

Clone scale

---

## Complete Examples

### Checking BigWigs Bars for Upcoming Mechanics

```
local function check_boss_timers()    if not core.addons.bigwigs.is_loaded() then        return    end    if not core.addons.bigwigs.has_active_bars() then        return    end    local bars = core.addons.bigwigs.get_bars()    for _, bar in ipairs(bars) do        if bar.remaining < 3.0 then            core.log("IMMINENT: " .. bar.text .. " in " .. string.format("%.1f", bar.remaining) .. "s")        end        if bar.is_emphasized then            core.log("IMPORTANT: " .. bar.text .. " (" .. string.format("%.1f", bar.remaining) .. "s)")        end    endend
```

### TSM Price Checking for Auction House Decisions

```
local function evaluate_item(item_id)    if not core.addons.tsm.is_loaded() then        core.log("TSM is not loaded")        return    end    local prices = core.addons.tsm.get_item_prices(item_id)    if not prices then        core.log("No price data for item: " .. item_id)        return    end    local auctioning = core.addons.tsm.get_auctioning_prices(item_id)    if auctioning then        local min_gold = auctioning.min_price / 10000        local normal_gold = auctioning.normal_price / 10000        local max_gold = auctioning.max_price / 10000        core.log(string.format("Auctioning - Min: %.1fg, Normal: %.1fg, Max: %.1fg", min_gold, normal_gold, max_gold))    end    local sniper_max = core.addons.tsm.get_sniper_max_price(item_id)    if sniper_max then        core.log(string.format("Sniper threshold: %.1fg", sniper_max / 10000))    end    local restock = core.addons.tsm.get_shopping_restock_quantity(item_id)    if restock and restock > 0 then        core.log("Need to restock: " .. restock .. " units")    endend-- Example: Check price data for Draconium Ore (item ID 190312)evaluate_item(190312)
```

[

Previous

Delves

](/dev/api/delves)[

Next

Color

](/dev/api/color)
