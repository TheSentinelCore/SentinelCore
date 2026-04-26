# https://docs.project-sylvanas.net/dev/api/spellbook

Spell Book - Raw Functions
Overview​

The spell_book module provides a comprehensive set of methods to interact with spells in your scripts. You can use these functions to query spell cooldowns, retrieve spell names, check if a spell is equipped, etc. However, same like with the Input module, using the raw functions directly might not be the best idea in most cases. For example, to check if a spell is castable, you would need to first check if the spell is equipped, if the spell is on cooldown, then range... As you can see, this is going to become an annoying task in most of your scripts. To make your life easier and centralize code as much as possible so the amount of bugs is reduced, we developed the Spell helper module.

TIP

Check the Spell helper module after checking the raw functions, provided below.

Functions​
General Functions 📃​
get_specialization_id()​

Returns the specialization ID of the local player.

Returns: number — The specialization ID.

NOTE

This function is specially useful to decide whether to load or not your script. Here is an example to properly avoid loading scripts when they are not necessary (for example, your script is for rogues and the user is playing a monk).

--- this is the HEADER file

local plugin_info = require("plugin_info")

local plugin = {}



plugin["name"] = plugin_info.plugin_load_name

plugin["version"] = plugin_info.plugin_version

plugin["author"] = plugin_info.author



-- by default, we load the plugin always

plugin["load"] = true



-- if there is no local player (eg. user injected before being in-game or is in loading screen) then

-- we don't load the script



local local_player = core.object_manager.get_local_player()

if not local_player then

    plugin["load"] = false

    return plugin

end



-- we check if the class that is being played currently matches our script's intended class

local enums = require("common/enums")

local player_class = local_player:get_class()

local is_valid_class = player_class == enums.class_id.ROGUE



if not is_valid_class then

    plugin["load"] = false

    return plugin

end



-- then, we check if the spec id that is being currently played matches our script's intended spec

local player_spec_id = core.spell_book.get_specialization_id()

local is_valid_spec_id = player_spec_id == 3



if not is_valid_spec_id then

    plugin["load"] = false

    return plugin

end



return plugin

Cooldowns and Charges ⏳​
get_global_cooldown()​

Returns the duration of the global cooldown, which is the time between casting spells.

Returns: number — The global cooldown duration in seconds.

get_spell_cooldown(spell_id)​

Returns the cooldown duration of the specified spell in seconds.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: number — The cooldown duration in seconds.

get_spell_charge(spell_id)​

Returns the current number of charges available for the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: integer — The current number of charges.

get_spell_charge_max(spell_id)​

Returns the maximum number of charges available for the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: integer — The maximum number of charges.

Spell Information ℹ️​
get_spell_name(spell_id)​

Returns the name of the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: string — The name of the spell.

get_spell_description(spell_id)​

Retrieves the tooltip text of the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: string — The tooltip text.

get_spells()​

Returns a table containing all spells and their corresponding IDs.

Returns: table — A table mapping spell IDs to spell names.

has_spell(spell_id)​

Checks if the specified spell is equipped.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: boolean — true if the spell is equipped; otherwise, false.

is_spell_learned(spell_id)​

Determines if the specified spell is learned.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: boolean — true if the spell is learned; otherwise, false.

Note: is_spell_learned is more reliable than has_spell for checking talents.

Spell Costs 💰​
get_spell_costs(spell_id)​

Returns a table containing the power cost details of the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: table — A table containing power cost details.

spell_cost Properties:

min_cost: Minimum cost required to cast the spell.
cost: Standard cost to cast the spell.
cost_per_sec: Cost per second if the spell is channeled.
cost_type: Type of resource used (e.g., mana, energy).
required_buff_id: ID of any buff required to modify the cost.
WARNING

Do not use this function, as it returns a table that needs to be handled in a specific way. We still provide its functionality, but in general you wouldn't want to use it.

Spell Range and Damage 🎯​
get_spell_range_data(spell_id)​

Returns a table containing the minimum and maximum range of the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: table — A table with min_range and max_range.

Range Data Properties:

min_range: Minimum distance required to cast the spell.
max_range: Maximum distance within which the spell can be cast.
get_spell_min_range(spell_id)​

Returns the minimum range of the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: number — The minimum range.

get_spell_max_range(spell_id)​

Returns the maximum range of the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: number — The maximum range.

get_spell_damage(spell_id)​

Retrieves the damage value of the specified spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: number — The damage value.

Casting Types 🎭​
is_melee_spell(spell_id)​

Determines if the specified spell is of melee type.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: boolean — true if the spell is melee type; otherwise, false.

is_spell_position_cast(spell_id)​

Checks if the specified spell is a skillshot (position-cast spell).

Parameters:
spell_id (integer) — The ID of the spell.

Returns: boolean — true if the spell is a skillshot; otherwise, false.

cursor_has_spell()​

Checks if the cursor is currently busy with a skillshot.

Returns: boolean — true if the cursor is busy; otherwise, false.

Talents 🌟​
get_talent_name(talent_id)​

Returns the name of the specified talent.

Parameters:
talent_id (integer) — The ID of the talent.

Returns: string — The name of the talent.

get_talent_spell_id(talent_id)​

Returns the spell ID associated with the specified talent.

Parameters:
talent_id (integer) — The ID of the talent.

Returns: number — The spell ID.

More SpellBook Functions​
get_pet_mode()​

Retrieves the current mode of the player's pet.

Returns: number — The pet's current mode (e.g., passive, aggressive).

get_pet_spells()​

Returns a table of spells available to the player's pet.

Returns: table — A table containing the pet's spell IDs and names.

get_spell_school(spell_id)​

Determines the school of magic for a given spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: number — The school of the spell (e.g., arcane, fire, shadow).

get_spell_cast_time(spell_id)​

Returns the cast time required for a specific spell.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: number — The spell's cast time in seconds.

get_mount_info(mount_id)​

Returns detailed information about a specific mount.

Parameters:
mount_id (integer) — The ID of the mount.

Returns: table — A table containing information about the mount, such as its name, type, and attributes.

get_mount_count()​

Returns the total number of mounts available to the player.

Returns: integer — The number of available mounts.

is_usable_spell(spell_id)​

Determines whether the specified spell can be cast at the current moment.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: boolean — true if the spell is usable; otherwise, false.

get_spell_charge_cooldown_start_time(spell_id)​

Returns the start time of the cooldown for a spell's charge.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: number — The timestamp when the cooldown started.

get_spell_charge_cooldown_duration(spell_id)​

Returns the duration of the cooldown for a spell’s charge.

Parameters:
spell_id (integer) — The ID of the spell.

Returns: number — The cooldown duration in seconds.

is_player_in_control()​

Determines if the player is currently in full control of their character (not stunned, feared, or incapacitated).

Returns: boolean — true if the player is in control; otherwise, false.