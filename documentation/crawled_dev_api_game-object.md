# https://docs.project-sylvanas.net/dev/api/game-object

Game Object - Functions
Overview​

The game_object class represents entities within the game world. This class provides a comprehensive set of methods to interact with and retrieve information about game objects, such as players, NPCs, items, and more. Almost everything that we are ever going to interact with is a game_object, so this class is one of the most important ones.

Functions​
Validation and Type Checks 📃​
is_valid() -> boolean​

Checks if the game_object is valid (exists in the game world).

get_type() -> number​

Returns the type identifier of the object.

get_class() -> number​

Retrieves the class identifier of the object.

TIP

You can use the following code to translate from class ID to class name:

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

is_basic_object() -> boolean​

Determines if the object is a basic game object.

is_player() -> boolean​

Checks if the object is a player.

is_unit() -> boolean​

Checks if the object is a unit (NPC, creature, etc.).

is_item() -> boolean​

Checks if the object is an item.

is_pet() -> boolean​

Determines if the object is a pet.

is_boss() -> boolean​

Checks if the object is classified as a boss.

WARNING

Blizzard's "is_boss" function is not accurate, since only certain bosses like world bosses have this flag enabled. To check if a mob is a boss more accurately, you should use the function provided in the unit_helper module. Here is a code showing how to properly check if a unit is a boss or not:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



local function is_boss(target)

    return unit_helper:is_boss(target)

end



Identification and Attributes 📃​
get_npc_id() -> number​

Retrieves the NPC ID of the object (if applicable).

WARNING

This only works for npcs!

get_level() -> number​

Returns the level of the object.

get_faction_id() -> number​

Gets the faction ID the object belongs to.

get_target_marker_index() -> number​

Retrieves the target marker (raid icon) index:

0: No Icon
1: Yellow 4-point Star
2: Orange Circle
3: Purple Diamond
4: Green Triangle
5: White Crescent Moon
6: Blue Square
7: Red "X" Cross
8: White Skull
get_classification() -> number​

Gets the classification of the object:

-1: Unknown
0: Normal
1: Elite
2: Rare Elite
3: World Boss
4: Rare
5: Trivial
6: Minus
get_group_role() -> number​

Retrieves the group role of the object:

-1: Unknown / None
0: Tank
1: Healer
2: Damage Dealer
get_name() -> string​

Returns the name of the object.

get_attack_speed() -> number​

Retrieves the auto-attack swing speed.

Status and State Checks 📃​
get_specialization_id() -> integer​

Returns the spec_id if the game_object is a player.

get_creature_type() -> integer​

Returns the type of the creature.

is_dead() -> boolean​

Checks if the object is dead.

is_visible() -> boolean​

Checks if the object is visible or not. Also might be useful to check if an object is alive / useful or it's removed from the game (for example, a trap expiring).

is_mounted() -> boolean​

Determines if the object is mounted.

is_outdoors() -> boolean​

Checks if the object is outdoors.

is_indoors() -> boolean​

Checks if the object is indoors.

is_in_combat() -> boolean​

Checks if the object is currently in combat.

is_moving() -> boolean​

Determines if the object is moving.

is_dashing() -> boolean​

Checks if the object is dashing.

is_casting_spell() -> boolean​

Checks if the object is casting a spell.

is_channelling_spell() -> boolean​

Determines if the object is channeling a spell.

is_active_spell_interruptable() -> boolean​

Checks if the currently casting spell can be interrupted.

is_glow() -> boolean​

Checks if the object is glowing.

set_glow(state: boolean)​

Sets the glowing state of the object.

Combat and Threat 📃​
can_attack(other: game_object) -> boolean​

Determines if the object can attack another object.

is_enemy_with(other: game_object) -> boolean​

Checks if the object is an enemy of another object.

is_friend_with(other: game_object) -> boolean​

Checks if the object is friendly with another object.

get_threat_situation(obj: game_object) -> threat_table​

Retrieves the threat status relative to another object.

threat_table Properties:

is_tanking: Whether the object is tanking.
status: Threat status (0 to 3).
threat_percent: Threat percentage (0 to 100).
Position and Movement 📃​
get_position() -> vec3​

Gets the current position of the object. See vec3

get_rotation() -> number​

Retrieves the rotation angle of the object.

get_direction() -> vec3​

Gets the directional vector the object is facing. See vec3

get_movement_speed() -> number​

Returns the current movement speed.

get_movement_speed_max() -> number​

Retrieves the maximum possible movement speed.

get_swim_speed_max() -> number​

Gets the maximum swim speed.

get_flight_speed_max() -> number​

Returns the maximum flight speed.

get_bounding_radius() -> number​

Retrieves the bounding radius of the object.

get_height() -> number​

Returns the height of the object.

get_scale() -> number​

Gets the scale factor of the object.

Health and Power 📃​
get_health() -> number​

Retrieves the current health value.

get_max_health() -> number​

Gets the maximum health value.

get_max_health_modifier() -> number​

Returns any modifiers affecting max health.

get_power(power_type: number) -> number​

Gets the current power for a specified power type.

Refer to Power Types.

TIP

Use the enums power types to check all the possible values. For example:



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



get_max_power(power_type: number) -> number​

Retrieves the maximum power for a specified power type. Same like the previous function , only that this one returns the maximum possible power that the character can have, instead of the current one.

get_xp() -> number​

Returns the current experience points (XP).

get_max_xp() -> number​

Gets the maximum XP for the current level.

Casting and Spells 📃​
get_active_spell_id() -> number​

Retrieves the spell ID of the spell currently being cast.

get_active_spell_cast_start_time() -> number​

Gets the start time of the active spell cast.

get_active_spell_cast_end_time() -> number​

Retrieves the end time of the active spell cast.

get_active_spell_target() -> game_object​

Gets the target of the spell currently being cast.

get_active_channel_spell_id() -> number​

Retrieves the spell ID of the spell currently being channeled.

get_active_channel_cast_start_time() -> number​

Gets the start time of the active channel spell.

get_active_channel_cast_end_time() -> number​

Retrieves the end time of the active channel spell.

is_ghost() -> boolean​

Returns true when the game object is a ghost (not dead but not alive either)

Relationships 📃​
get_owner() -> game_object​

Returns the owner of the object (if any).

get_pet() -> game_object​

Retrieves the pet of the object (if any).

get_target() -> game_object​

Gets the current target of the object.

is_party_member() -> boolean​

Checks if the object is a party member.

Auras and Effects 📃​
get_auras() -> table<buff>​

Retrieves all auras affecting the object.

get_buffs() -> table<buff>​

Gets all buffs applied to the object. See buffs

get_debuffs() -> table<buff>​

Retrieves all debuffs applied to the object. see debuffs

buff Properties:

buff_name: Name of the buff.
buff_id: Unique identifier.
count: Stack count.
expire_time: When the buff expires.
duration: Total duration.
type: Type identifier.
caster: The object that applied the buff.
get_loss_of_control_info() -> loss_of_control_info​

Provides information on any loss of control effects.

loss_of_control_info Properties:

valid: Whether the info is valid.
spell_id: Associated spell ID.
start_time: Effect start time.
end_time: Effect end time.
duration: Total duration.
type: Type of control loss.
get_total_shield() -> number​

Returns the total shield applied to the game_object.

Items and Inventory 📃​
get_item_cooldown(item_id: integer) -> number​

Retrieves the cooldown for a specific item.

has_item(item_id: integer) -> boolean​

Checks if the object possesses a specific item.

get_item_id() -> integer​

Gets the item id from an item gameobject

get_equipped_items() -> table of item_slot_info​
NOTE

The item_slot info is a table with 2 members:


.object (game_object) -> the item itself
.slot_id (integer) -> the id of the slot

Check the Wiki for more info.

TIP

Also, check our Inventory Helper which provides the most important and required functionality in regards to inventory.

get_item_at_inventory_slot(integer) -> item_slot_info​

The item_slot_info of the item with at the given slot.

get_item_stack_count() -> integer​

The stack count of the item.

More GameObject Functions​
is_visible()​

Checks if the game object is currently visible.

Returns: boolean — true if the object is visible; otherwise, false.

get_total_shield()​

Returns the total shield absorption applied to the game object.

Returns: number — The total amount of shield absorption.

get_specialization_id()​

Retrieves the specialization ID of the player if the game object is a player.

Returns: integer — The specialization ID of the player.

get_creature_type()​

Determines the creature type of the game object (e.g., beast, humanoid, elemental).

Returns: integer — The type identifier for the creature.

get_incoming_heals()​

Returns the total amount of incoming heals to the game object from all sources.

Returns: number — The total incoming heal value.

get_incoming_heals_from(source: game_object)​

Returns the amount of incoming heals to the game object specifically from the specified source.

Parameters:
source (game_object) — The source object providing the heal.

Returns: number — The incoming heal value from the source.

get_creator_object()​

Retrieves the game object that created the current object (e.g., a player creating a totem or a pet).

Returns: game_object — The creator object.

does_bobber_have_fish()​

Checks if the player’s fishing bobber has caught a fish.

Returns: boolean — true if the bobber has a fish; otherwise, false.