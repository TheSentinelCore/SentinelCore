# https://docs.project-sylvanas.net/dev/api/spellbook/helper

Spell helper
Overview​

As explained in the previous page Spell Book Functions, the spell helper module will provide you most of the possible and most used functionalities related to spells.

TIP

Check the examples section, which is essentially the summary of all this module.

Importing The Module​
WARNING

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the require function and store it in a local variable.

Here is an example of how to do it:

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")

Functions​
Spell Availability 📖​
has_spell_equipped(spell_id)​

Checks if the spell is in the spellbook.

Parameters:
spell_id (number) — The ID of the spell to check.

Returns: boolean — true if the spell is equipped; otherwise, false.

Spell Cooldown ⏳​
is_spell_on_cooldown(spell_id)​

Checks if the spell is currently on cooldown.

Parameters:
spell_id (number) — The ID of the spell to check.

Returns: boolean — true if the spell is on cooldown; otherwise, false.

Range and Angle Checks 🎯​
is_spell_in_range(spell_id, target, source, destination)​

Checks if a spell is within castable range given a target.

Parameters:
spell_id (number) — The ID of the spell.
target (game_object) — The target game object.
source (vec3) — The source position vector.
destination (vec3) — The destination position vector.

Returns: boolean — true if the spell is within range; otherwise, false.

is_spell_within_angle(spell_id, caster, target, caster_position, target_position)​

Checks if the target is within a permissible angle for casting a spell.

Parameters:
spell_id (number) — The ID of the spell.
caster (game_object) — The caster game object.
target (game_object) — The target game object.
caster_position (vec3) — The position of the caster.
target_position (vec3) — The position of the target.

Returns: boolean — true if the target is within angle; otherwise, false.

Line of Sight Checks 👁️​
is_spell_in_line_of_sight(spell_id, caster, target)​

Checks if the caster has the target in line of sight for a spell.

Parameters:
spell_id (number) — The ID of the spell.
caster (game_object) — The caster game object.
target (game_object) — The target game object.

Returns: boolean — true if the target is in line of sight; otherwise, false.

is_spell_in_line_of_sight_position(spell_id, caster, cast_position)​

Checks if the caster has the position in line of sight for a spell.

Parameters:
spell_id (number) — The ID of the spell.
caster (game_object) — The caster game object.
cast_position (vec3) — The position to check.

Returns: boolean — true if the position is in line of sight; otherwise, false.

Resource and Cost Checks 💰​
get_spell_cost(spell_id)​

Retrieves the cost of a spell.

Parameters:
spell_id (number) — The ID of the spell.

Returns: table — A table containing the cost details of the spell.

Cost Table Properties:

cost_type: The type of resource required (e.g., mana, energy).
cost: The amount of resource required to cast the spell.
cost_percent: The percentage of the resource pool required.
Other cost-related fields as applicable.
WARNING

In most cases, you do not want to use this function, as it returns a table that needs to be specially handled, same like the raw function.

can_afford_spell(unit, spell_id, spell_costs)​

Checks if a unit has enough resources to cast a spell.

Parameters:
unit (game_object) — The unit attempting to cast the spell.
spell_id (number) — The ID of the spell.
spell_costs (table) — The cost table retrieved from get_spell_cost.

Returns: boolean — true if the unit can afford the spell; otherwise, false.

Casting Readiness ✅​
is_spell_castable(spell_id, caster, target, skip_facing, skips_range)​

Checks if the spell can be cast to target.

Parameters:
spell_id (number) — The ID of the spell.
caster (game_object) — The caster game object.
target (game_object) — The target game object.
skip_facing (boolean) — If true, skips the facing check.
skips_range (boolean) — If true, skips the range check.

Returns: boolean — true if the spell can be cast; otherwise, false.

NOTE

This function handles everything for you (line of sight, cooldown, spell cost, etc), so, for most cases, this is the only function you will need to check if you can cast a spell or not.

Examples​
How To - Check If You Can Cast A Spell 🎯​
TIP

This is the recommended way to check if you can cast a spell. Just check the last two parameters (skip_facing and skip_range), since you might wanna set them to "true" in some cases (for example, for some self-cast spells).

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")



local function can_cast(local_player, target)

    local is_logic_allowed = spell_helper:is_spell_castable(spell_data.id, local_player, target, false, false)

    return is_logic_allowed

end
