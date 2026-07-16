---
title: "Game Object - Functions"
source: "https://docs.project-sylvanas.net/dev/api/game-object"
crawled: "2026-07-14"
---

# Game Object - Functions

## Overview

The `game_object` class represents entities within the game world. This class provides a comprehensive set of methods to interact with and retrieve information about game objects, such as players, NPCs, items, and more. Almost everything that we are ever going to interact with is a game_object, so this class is one of the most important ones.

## Functions

### Validation and Type Checks

### `is_valid() -> boolean`

Checks if the `game_object` is valid (exists in the game world).

### `get_type() -> number`

Returns the type identifier of the object.

### `get_class() -> number`

Retrieves the class identifier of the object.

> **tip**: You can use the following code to translate from class ID to class name:

```lua
---@type enums
local enums = require("common/enums")

local function call_this_function_inside_the_on_update_callback()
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        return
    end
    local class_name = enums.class_id_to_name[local_player:get_class()]
    core.log("This is my current class: " .. class_name)
end
```

### `is_basic_object() -> boolean`

Determines if the object is a basic game object.

### `is_player() -> boolean`

Checks if the object is a player.

### `is_unit() -> boolean`

Checks if the object is a unit (NPC, creature, etc.).

### `is_item() -> boolean`

Checks if the object is an item.

### `is_pet() -> boolean`

Determines if the object is a pet.

### `is_minion() -> boolean`

Determines if the object is a minion (alternative pets, such as summons that are not the main pet).

### `is_boss() -> boolean`

Checks if the object is classified as a boss.

> **warning**: Blizzard's "is_boss" function is not accurate, since only certain bosses like world bosses have this flag enabled. To check if a mob is a boss more accurately, you should use the function provided in the unit_helper module. Here is a code showing how to properly check if a unit is a boss or not:

```lua
---@type unit_helper
local unit_helper = require("common/utility/unit_helper")

local function is_boss(target)
    return unit_helper:is_boss(target)
end
```

### `is_item_bag() -> boolean`

Checks if the object is a bag type item.

### Identification and Attributes

### `get_npc_id() -> number`

Retrieves the NPC ID of the object (if applicable).

> **warning**: This only works for npcs!

### `get_level() -> number`

Returns the level of the object.

### `get_effective_level() -> number`

Returns the effective level of the game object.

### `get_gold() -> number`

Returns the gold amount (in copper).

### `get_faction_id() -> number`

Gets the faction ID the object belongs to.

### `get_target_marker_index() -> number`

Retrieves the target marker (raid icon) index:
- `0`: No Icon
- `1`: Yellow 4-point Star
- `2`: Orange Circle
- `3`: Purple Diamond
- `4`: Green Triangle
- `5`: White Crescent Moon
- `6`: Blue Square
- `7`: Red "X" Cross
- `8`: White Skull

### `set_target_marker_index(index) -> nil`

Sets the target marker (raid icon) on the game object.

- `index`: `integer` - The marker index (0-8, same values as `get_target_marker_index`).

### `get_race_id() -> integer`

Returns the race ID of the game object.

### `get_classification() -> number`

Gets the classification of the object:
- `-1`: Unknown
- `0`: Normal
- `1`: Elite
- `2`: Rare Elite
- `3`: World Boss
- `4`: Rare
- `5`: Trivial
- `6`: Minus

### `get_group_role() -> number`

Retrieves the group role of the object:
- `-1`: Unknown / None
- `0`: Tank
- `1`: Healer
- `2`: Damage Dealer

### `get_name() -> string`

Returns the name of the object.

### `get_guid() -> string`

Returns the unit's globally-unique GUID string (e.g. `"Player-970-0002FD41"`, `"Creature-0-..."`). Pair it with `core.object_manager.get_object_from_guid` to resolve a stored GUID back into a live game object.

### `get_attack_speed() -> number`

Retrieves the auto-attack swing speed.

### `get_unit_phase() -> number`

Returns the phase ID of the game object.

### Status and State Checks

### `get_specialization_id() -> integer`

Returns the spec_id if the game_object is a player.

### `get_creature_type() -> integer`

Returns the type of the creature.

### `is_dead() -> boolean`

Checks if the object is dead.

### `is_ghost() -> boolean`

Returns true when the game object is a ghost (not dead but not alive either).

### `is_feign_death() -> boolean`

Checks if the object is feigning death. Useful for hunters — a feigning unit appears dead but is not actually dead.

### `is_visible() -> boolean`

Checks if the object is visible or not. Also might be useful to check if an object is alive / useful or it's removed from the game (for example, a trap expiring).

### `is_mounted() -> boolean`

Determines if the object is mounted.

### `is_outdoors() -> boolean`

Checks if the object is outdoors.

### `is_indoors() -> boolean`

Checks if the object is indoors.

### `is_quest_unit() -> boolean`

Returns whether the object is a quest unit.

### `is_tap_denied() -> number`

Returns whether the NPC is tap denied (grey healthbar).

### `is_in_combat() -> boolean`

Checks if the object is currently in combat.

### `is_moving() -> boolean`

Determines if the object is moving.

### `is_dashing() -> boolean`

Checks if the object is dashing.

### `is_flying() -> boolean`

Checks if the object is currently flying.

### `is_auto_attacking() -> boolean`

Returns whether the game object currently has auto attack toggled on.

### `is_casting_spell() -> boolean`

Checks if the object is casting a spell.

### `is_channelling_spell() -> boolean`

Determines if the object is channeling a spell.

### `is_active_spell_interruptable() -> boolean`

Checks if the currently casting spell can be interrupted.

### `is_glow() -> boolean`

Checks if the object is glowing.

### `set_glow(state: boolean)`

Sets the glowing state of the object.

### Combat and Threat

### `can_attack(other: game_object) -> boolean`

Determines if the object can attack another object.

### `is_enemy_with(other: game_object) -> boolean`

Checks if the object is an enemy of another object.

### `is_friend_with(other: game_object) -> boolean`

Checks if the object is friendly with another object.

### `get_threat_situation(obj: game_object) -> threat_table`

Retrieves the threat status relative to another object.

**`threat_table` Properties:**
- `is_tanking`: Whether the object is tanking.
- `status`: Threat status (`0` to `3`).
- `threat_percent`: Threat percentage (`0` to `100`).

### `get_unit_ranged_damage() -> unit_ranged_damage_data`

Returns the unit's ranged damage information.

**`unit_ranged_damage_data` Properties:**
- `speed`: (*number*) Ranged attack speed.
- `min_damage`: (*number*) Minimum ranged damage.
- `max_damage`: (*number*) Maximum ranged damage.
- `pos_buff`: (*integer*) Positive buff modifier count.
- `neg_buff`: (*integer*) Negative buff modifier count.
- `percent`: (*number*) Damage percentage modifier.

### `get_nameplate() -> nameplate_info|nil`

Returns this unit's nameplate visibility and on-screen rectangle, or `nil` when the unit has no nameplate frame (out of range, nameplates disabled, or the `C_NamePlate` API is unavailable on older clients).

The rectangle uses a **bottom-left origin** and is measured in scaled screen pixels, matching the values returned by the WoW nameplate frame.

**`nameplate_info` Properties:**
- `is_shown`: (*boolean*) Whether the nameplate frame is currently shown on screen.
- `left`: (*number*) The x coordinate of the nameplate's bottom-left corner, in scaled screen pixels.
- `bottom`: (*number*) The y coordinate of the nameplate's bottom-left corner, in scaled screen pixels.
- `width`: (*number*) The nameplate width in scaled screen pixels.
- `height`: (*number*) The nameplate height in scaled screen pixels.

```lua
local plate = target:get_nameplate()
if plate and plate.is_shown then
    core.log(string.format("Nameplate at (%.0f, %.0f) size %.0fx%.0f",
        plate.left, plate.bottom, plate.width, plate.height))
end
```

### Position and Movement

### `get_position() -> vec3`

Gets the current position of the object.

### `get_rotation() -> number`

Retrieves the rotation angle of the object.

### `get_direction() -> vec3`

Gets the directional vector the object is facing.

### `get_movement_direction() -> vec3`

Gets the directional vector of the object's movement manager. This may differ from `get_direction()` when the object is moving in a direction it is not facing (e.g., strafing or backpedaling).

### `get_movement_speed() -> number`

Returns the current movement speed.

### `get_movement_speed_max() -> number`

Retrieves the maximum possible movement speed.

### `get_swim_speed_max() -> number`

Gets the maximum swim speed.

### `get_flight_speed_max() -> number`

Returns the maximum flight speed.

### `get_glide_speed() -> number`

Returns the current glide speed of the object.

### `get_bounding_radius() -> number`

Retrieves the bounding radius of the object.

### `get_combat_reach() -> number`

Returns the combat reach of the unit.

### `get_height() -> number`

Returns the height of the object.

### `get_scale() -> number`

Gets the scale factor of the object.

### Model Attachments

### `get_attachment_name_position() -> vec3`

Returns the world position of the unit's **name attachment point** — the anchor above the model where the name/nameplate text sits (roughly the top of the head). Handy for drawing text, icons, or widgets above a unit. Returns a zero vector when the model is not loaded.

### `get_attachment_position(attachment_id: integer) -> vec3`

Returns the world position of a specific model attachment point, identified by its numeric `attachment_id` (e.g. hands, chest, base, overhead). Returns a zero vector when the model is not loaded or does not have the requested attachment.

Parameters:
- **`attachment_id`** (*integer*) — The model attachment point ID to query.

### Health and Power

### `get_health() -> number`

Retrieves the current health value.

### `get_max_health() -> number`

Gets the maximum health value.

### `get_max_health_modifier() -> number`

Returns any modifiers affecting max health.

### `get_power(power_type: number) -> number`

Gets the current power for a specified power type.

> **tip**: Use the enums power types to check all the possible values. For example:

```lua
---@type enums
local enums = require("common/enums")

local function print_player_fury()
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        return
    end
    local local_player_power = local_player:get_power(enums.power_type.FURY)
    core.log("Local Player Current Fury: " .. tostring(local_player_power))
end
```

### `get_max_power(power_type: number) -> number`

Retrieves the maximum power for a specified power type. Same as the previous function, only that this one returns the maximum possible power that the character can have, instead of the current one.

### `get_xp() -> number`

Returns the current experience points (XP).

### `get_max_xp() -> number`

Gets the maximum XP for the current level.

### `get_total_shield() -> number`

Returns the total absorb shield applied to the game_object.

### `get_total_heal_absorbs() -> number`

Returns the total amount of healing that is being absorbed on this game object (i.e., healing that cannot land until the absorb is removed).

### `get_incoming_heals() -> number`

Returns the total amount of incoming heals to the game object from all sources.

### `get_incoming_heals_from(source: game_object) -> number`

Returns the amount of incoming heals to the game object specifically from the specified source.

Parameters:
- **`source`** (*game_object*) — The source object providing the heal.

### `get_armor() -> number`

Returns the armor value of the game object.

### `game_object:get_state_flags`

```
object:get_state_flags() -> integer
```

Returns:
- `integer`: The current state flags bitfield for the game object.

Description: Returns the raw state flags bitfield exposed by the game object.

### `get_spell_haste() -> number`

Returns the current spell haste percentage of the game object. A value of `8` means 8% haste.

### Casting and Spells

### `get_active_spell_id() -> number`

Retrieves the spell ID of the spell currently being cast.

### `get_active_spell_cast_start_time() -> number`

Gets the start time of the active spell cast.

### `get_active_spell_cast_end_time() -> number`

Retrieves the end time of the active spell cast.

### `get_active_spell_target() -> game_object`

Gets the target of the spell currently being cast.

### `get_active_channel_spell_id() -> number`

Retrieves the spell ID of the spell currently being channeled.

### `get_active_channel_cast_start_time() -> number`

Gets the start time of the active channel spell.

### `get_active_channel_cast_end_time() -> number`

Retrieves the end time of the active channel spell.

### `get_combo_points_target() -> game_object`

Returns the game object that currently holds the combo points generated by this game object. Useful for rogue and druid scripts to determine which target your combo points are applied to.

### Empower Spells

### `get_empower_current_stage() -> number`

Returns the current empower stage of the spell being cast by the game object. Returns `-1` if the object is not currently casting an empower spell.

### `get_empower_max_stage() -> number`

Returns the maximum empower stage of the spell being cast.

### `get_empower_stage_duration(index: number) -> number`

Returns the duration (in seconds) of a specific empower stage for the currently cast empower spell.

Parameters:
- **`index`** (*number*) — The stage index to query.

Returns: *number* — The duration in seconds for that empower stage.

### Relationships

### `get_owner() -> game_object`

Returns the owner of the object (if any).

### `get_pet() -> game_object`

Retrieves the pet of the object (if any).

### `get_target() -> game_object`

Gets the current target of the object.

### `get_creator_object() -> game_object`

Retrieves the game object that created the current object (e.g., a player creating a totem or a pet).

### `is_party_member() -> boolean`

Checks if the object is a party member.

### Auras and Effects

### `get_auras() -> table<buff>`

Retrieves all auras affecting the object.

### `get_buffs() -> table<buff>`

Gets all buffs applied to the object.

### `get_debuffs() -> table<buff>`

Retrieves all debuffs applied to the object.

**`buff` Properties:**
- `buff_name`: Name of the buff.
- `buff_id`: Unique identifier.
- `count`: Stack count.
- `expire_time`: When the buff expires.
- `duration`: Total duration.
- `type`: Type identifier.
- `caster`: The object that applied the buff.
- `points`: Variable values from aura data (e.g. absorb remaining for shields).

### `get_buff_data(spec) -> buff_manager_data|nil`

Returns resolved buff data for the given aura spec (cached). Spec can be a buff_db or number[].

### `get_debuff_data(spec) -> buff_manager_data|nil`

Returns resolved debuff data for the given aura spec (cached). Spec can be a buff_db or number[].

### `get_aura_data(spec) -> buff_manager_data|nil`

Returns resolved aura data for the given aura spec (cached). Spec can be a buff_db or number[].

### `get_loss_of_control_info() -> loss_of_control_info`

Provides information on any loss of control effects.

**`loss_of_control_info` Properties:**
- `valid`: Whether the info is valid.
- `spell_id`: Associated spell ID.
- `start_time`: Effect start time.
- `end_time`: Effect end time.
- `duration`: Total duration.
- `type`: Type of control loss.
- `lockout_school`: The school flag that is locked out.

### Items and Inventory

### `get_item_cooldown(item_id: integer) -> number`

Retrieves the cooldown for a specific item.

### `has_item(item_id: integer) -> boolean`

Checks if the object possesses a specific item.

### `get_item_id() -> integer`

Gets the item id from an item gameobject

### `get_equipped_items() -> table of item_slot_info`

> **note**: The item_slot info is a table with 2 members:
> - .object (game_object) -> the item itself
> - .slot_id (integer) -> the id of the slot

### `get_item_at_inventory_slot(integer) -> item_slot_info`

The item_slot_info of the item with at the given slot.

### `get_item_stack_count() -> integer`

The stack count of the item.

### Item Enchant Info

### `item_has_enchant() -> boolean`

Returns whether the item game object has an enchant applied.

### `item_enchant_id() -> integer`

Returns the enchant ID of the item.

### `item_enchant_expiration() -> number`

Returns the expiration time (in seconds) of the enchant on the item.

### `item_enchant_charges() -> integer`

Returns the number of remaining charges of the enchant on the item.

### Loot and Interaction

### `can_be_looted() -> boolean`

Returns whether the game object can be looted.

### `has_loot() -> boolean`

Returns whether the game object contains loot.

### `can_be_used() -> boolean`

Returns whether the game object can be used (e.g., quest objects, chests).

### `can_be_skinned() -> boolean`

Returns whether the game object can be skinned.

### `has_skin() -> boolean`

Returns whether the object has skin to harvest.

### `does_bobber_have_fish() -> boolean`

Checks if the player's fishing bobber has caught a fish.
