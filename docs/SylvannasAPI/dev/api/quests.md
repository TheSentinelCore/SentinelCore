---
title: "Quest Functions"
source: "https://docs.project-sylvanas.net/dev/api/quests"
crawled: "2026-07-14"
---

# Quest Functions

## Overview

The `core.quests` module provides functions for interacting with quest dialogs, the quest log, gossip frames, trainer services, and item information. These functions cover the full lifecycle of quest management from accepting quests at NPCs to tracking and completing them.

---

## Quest Dialog Functions

### `core.quests.accept_quest`

**Syntax:** `core.quests.accept_quest() -> nil`

**Description:** Accepts the current quest dialog.

---

### `core.quests.close_quest`

**Syntax:** `core.quests.close_quest() -> nil`

**Description:** Closes the quest dialog frame.

---

### `core.quests.decline_quest`

**Syntax:** `core.quests.decline_quest() -> nil`

**Description:** Declines the current quest dialog.

---

### `core.quests.complete_quest`

**Syntax:** `core.quests.complete_quest() -> nil`

**Description:** Completes the current quest dialog.

---

### `core.quests.get_quest_reward`

**Syntax:** `core.quests.get_quest_reward(choice: integer) -> nil`

**Parameters:**
- `choice`: `integer` - The index of the reward choice to select.

**Description:** Selects a reward choice and completes the quest.

---

### `core.quests.confirm_accept_quest`

**Syntax:** `core.quests.confirm_accept_quest() -> nil`

**Description:** Confirms quest acceptance for escort-type quests.

---

### `core.quests.select_active_quest`

**Syntax:** `core.quests.select_active_quest(index: integer) -> nil`

**Parameters:**
- `index`: `integer` - The index of the active quest in the NPC's quest list.

---

### `core.quests.select_available_quest`

**Syntax:** `core.quests.select_available_quest(index: integer) -> nil`

**Parameters:**
- `index`: `integer` - The index of the available quest in the NPC's quest list.

---

### `core.quests.get_active_title`

**Syntax:** `core.quests.get_active_title(index: integer) -> string`

**Returns:** `string` - The title of the active quest at the NPC.

---

### `core.quests.get_available_title`

**Syntax:** `core.quests.get_available_title(index: integer) -> string`

**Returns:** `string` - The title of the available quest at the NPC.

---

### `core.quests.get_active_level`

**Syntax:** `core.quests.get_active_level(index: integer) -> integer`

**Returns:** `integer` - The level of the active quest at the NPC.

---

### `core.quests.get_available_level`

**Syntax:** `core.quests.get_available_level(index: integer) -> integer`

**Returns:** `integer` - The level of the available quest at the NPC.

---

### `core.quests.get_reward_money`

**Syntax:** `core.quests.get_reward_money() -> integer`

**Returns:** `integer` - The copper reward amount for the current quest.

**Example Usage:**
```lua
local copper = core.quests.get_reward_money()
local gold = math.floor(copper / 10000)
local silver = math.floor((copper % 10000) / 100)
core.log(string.format("Quest reward: %dg %ds", gold, silver))
```

---

### `core.quests.get_quest_item_link`

**Syntax:** `core.quests.get_quest_item_link(type: string, index: integer) -> string`

**Parameters:**
- `type`: `string` - The type of quest item (`"reward"` or `"choice"`).
- `index`: `integer` - The index of the item.

**Returns:** `string` - The item link for the quest reward or choice item.

---

## Quest Log Functions

### `core.quests.get_num_quest_log_entries`

**Syntax:** `core.quests.get_num_quest_log_entries() -> integer`

**Returns:** `integer` - The number of quest log entries (including headers).

---

### `core.quests.get_quest_log_title`

**Syntax:** `core.quests.get_quest_log_title(index: integer) -> table`

**Parameters:**
- `index`: `integer` - The quest log entry index.

**Returns:** `table` - A table containing quest log entry details (title, level, quest_id, is_header, is_complete).

**Example Usage:**
```lua
local num_entries = core.quests.get_num_quest_log_entries()
for i = 1, num_entries do
    local info = core.quests.get_quest_log_title(i)
    if not info.is_header then
        local status = info.is_complete and "COMPLETE" or "In Progress"
        core.log(string.format("[%d] %s (Lv %d) - %s", info.quest_id, info.title, info.level, status))
    end
end
```

---

### `core.quests.is_quest_flagged_completed`

**Syntax:** `core.quests.is_quest_flagged_completed(quest_id: integer) -> boolean`

**Returns:** `boolean` - `true` if the quest was ever completed by this character.

---

### `core.quests.is_on_quest`

**Syntax:** `core.quests.is_on_quest(quest_id: integer) -> boolean`

**Returns:** `boolean` - `true` if the quest is currently in the quest log.

---

### `core.quests.select_quest_log_entry`

**Syntax:** `core.quests.select_quest_log_entry(index: integer) -> nil`

**Description:** Selects a quest log entry. Required before calling `quest_log_push_quest` or `set_abandon_quest`.

---

### `core.quests.get_num_quest_leader_boards`

**Syntax:** `core.quests.get_num_quest_leader_boards(quest_log_index: integer) -> integer`

**Returns:** `integer` - The number of objectives for the quest.

---

### `core.quests.get_quest_log_leader_board`

**Syntax:** `core.quests.get_quest_log_leader_board(obj_index: integer, quest_log_index: integer) -> string`

**Returns:** `string` - The objective description text (e.g., `"Wolves slain: 3/10"`).

---

### `core.quests.get_quest_log_item_link`

**Syntax:** `core.quests.get_quest_log_item_link(type: string, index: integer, quest_id: integer) -> string`

---

### `core.quests.add_quest_watch`

**Syntax:** `core.quests.add_quest_watch(index: integer, watch_time: number) -> nil`

**Description:** Adds a quest to the on-screen quest tracker for the specified duration.

---

### `core.quests.remove_quest_watch`

**Syntax:** `core.quests.remove_quest_watch(index: integer) -> nil`

---

### `core.quests.quest_log_push_quest`

**Syntax:** `core.quests.quest_log_push_quest() -> nil`

**Description:** Shares the currently selected quest log entry with the party.

---

### `core.quests.set_abandon_quest`

**Syntax:** `core.quests.set_abandon_quest() -> nil`

**Description:** Marks the currently selected quest log entry for abandonment.

---

### `core.quests.abandon_quest`

**Syntax:** `core.quests.abandon_quest() -> nil`

**Description:** Confirms abandonment of the quest previously marked with `set_abandon_quest`.

---

## Gossip Functions

### `core.quests.get_gossip_options`

**Syntax:** `core.quests.get_gossip_options() -> table`

**Returns:** `table` - An array of gossip options available from the NPC.

---

### `core.quests.select_gossip_option`

**Syntax:** `core.quests.select_gossip_option(id: integer) -> nil`

---

### `core.quests.get_gossip_available_quests`

**Syntax:** `core.quests.get_gossip_available_quests() -> table`

**Returns:** `table` - An array of available quests from the gossip NPC.

---

### `core.quests.get_gossip_active_quests`

**Syntax:** `core.quests.get_gossip_active_quests() -> table`

**Returns:** `table` - An array of active quests at the gossip NPC.

---

### `core.quests.select_gossip_available_quest`

**Syntax:** `core.quests.select_gossip_available_quest(quest_id: integer) -> nil`

---

### `core.quests.select_gossip_active_quest`

**Syntax:** `core.quests.select_gossip_active_quest(quest_id: integer) -> nil`

---

### `core.quests.close_gossip`

**Syntax:** `core.quests.close_gossip() -> nil`

---

### `core.quests.is_gossip_frame_shown`

**Syntax:** `core.quests.is_gossip_frame_shown() -> boolean`

**Returns:** `boolean` - `true` if the gossip frame is currently open.

---

## Trainer Functions

### `core.quests.get_num_trainer_services`

**Syntax:** `core.quests.get_num_trainer_services() -> integer`

**Returns:** `integer` - The number of services available from the trainer.

---

### `core.quests.get_trainer_service_info`

**Syntax:** `core.quests.get_trainer_service_info(index: integer) -> table`

---

### `core.quests.get_trainer_service_cost`

**Syntax:** `core.quests.get_trainer_service_cost(index: integer) -> integer`

**Returns:** `integer` - The cost in copper.

---

### `core.quests.buy_trainer_service`

**Syntax:** `core.quests.buy_trainer_service(index: integer) -> nil`

---

## Item Info Functions

### `core.quests.get_item_spell`

**Syntax:** `core.quests.get_item_spell(item_id_or_link) -> string`

**Returns:** `string` - The spell name associated with the item.

---

### `core.quests.get_item_info`

**Syntax:** `core.quests.get_item_info(item_id_or_link) -> table`

**Returns:** `table` - A table containing item information.

---

## Complete Examples

### Example: Auto-Accept and Turn In Quests at NPC

```lua
local function handle_npc_quests()
    if not core.quests.is_gossip_frame_shown() then
        return
    end
    
    local active = core.quests.get_gossip_active_quests()
    for _, quest in ipairs(active) do
        core.quests.select_gossip_active_quest(quest.quest_id)
        core.quests.complete_quest()
        return
    end
    
    local available = core.quests.get_gossip_available_quests()
    for _, quest in ipairs(available) do
        core.quests.select_gossip_available_quest(quest.quest_id)
        core.quests.accept_quest()
        return
    end
end
```

### Example: Quest Progress Tracker

```lua
local function print_quest_progress()
    local num_entries = core.quests.get_num_quest_log_entries()
    for i = 1, num_entries do
        local info = core.quests.get_quest_log_title(i)
        if not info.is_header then
            core.log(string.format("[%d] %s", info.quest_id, info.title))
            local num_objectives = core.quests.get_num_quest_leader_boards(i)
            for j = 1, num_objectives do
                local text = core.quests.get_quest_log_leader_board(j, i)
                core.log("    " .. text)
            end
        end
    end
end
```
