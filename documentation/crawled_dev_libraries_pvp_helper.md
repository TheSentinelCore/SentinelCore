# https://docs.project-sylvanas.net/dev/libraries/pvp/helper

PvP Helper
Overview​

The PVP Helper module provides a comprehensive set of utility functions and data structures for working with player-versus-player (PVP) scenarios in Sylvanas. This module simplifies tasks such as identifying PVP players, checking crowd control statuses, handling damage reductions, and managing PVP-specific buffs and debuffs. Below, we'll explore its core functions and how to effectively utilize them.

Importing The Module​

As with all other LUA modules developed by us, you will need to import the PVP Helper module into your project. To do so, you can use the following lines:

---@type pvp_helper

local pvp_helper = require("common/utility/pvp_helper")

WARNING

To access the module's functions, you must use : instead of .

For example, this code is not correct:

---@type pvp_helper

local pvp_helper = require("common/utility/pvp_helper")



local function check_if_player(unit)

    return pvp_helper.is_player(unit)

end


And this would be the corrected code:

---@type pvp_helper

local pvp_helper = require("common/utility/pvp_helper")



local function check_if_player(unit)

    return pvp_helper:is_player(unit)

end

Functions​
Player Identification Functions 👤​
is_player(unit: game_object) -> boolean​

Determines if the given unit is a player character.

local is_unit_player = pvp_helper:is_player(unit)

if is_unit_player then

    core.log("The unit is a player.")

end

is_pvp_scenario() -> boolean​

Determines if the current scenario is a PVP situation.

local is_pvp_scenario = pvp_helper:is_pvp_scenario()

if is_pvp_scenario then

    core.log("Engaging in PVP combat.")

end

Crowd Control Functions 🌀​

The PVP Helper provides extensive functionality for handling crowd control (CC) effects. It uses a set of CC flags to categorize different types of CC.

CC Flags​

The module defines a cc_flags table containing various CC types as flags:

pvp_helper.cc_flags.MAGICAL        -- Magical CC effects

pvp_helper.cc_flags.PHYSICAL       -- Physical CC effects

pvp_helper.cc_flags.SLOW           -- Slow effects

pvp_helper.cc_flags.ROOT           -- Root effects

pvp_helper.cc_flags.STUN           -- Stun effects

pvp_helper.cc_flags.INCAPACITATE   -- Incapacitate effects

pvp_helper.cc_flags.DISORIENT      -- Disorient effects

pvp_helper.cc_flags.FEAR           -- Fear effects

pvp_helper.cc_flags.SAP            -- Sap effects

pvp_helper.cc_flags.CYCLONE        -- Cyclone effects

pvp_helper.cc_flags.KICK           -- Kick effects

pvp_helper.cc_flags.SILENCE        -- Silence effects

pvp_helper.cc_flags.ANY            -- Any CC effect

pvp_helper.cc_flags.ANY_BUT_SLOW   -- Any CC effect except slows


You can combine multiple CC flags using the combine function:

local combined_flags = pvp_helper.cc_flags:combine("STUN", "ROOT")

CC Flag Descriptions​

You can access human-readable descriptions of CC flags:

local cc_description = pvp_helper.cc_flag_descriptions[pvp_helper.cc_flags.STUN]

is_crowd_controlled(unit: game_object, type_flags?: number, min_remaining?: number) -> boolean, number, number​

Determines if the unit is under any crowd control effect specified by type_flags.

Returns:

is_cc (boolean): Whether the unit is crowd controlled.
current_remaining_ms (number): The remaining duration of the CC in milliseconds.
expire_time (number): The timestamp when the CC effect will expire.

Parameters:

unit (game_object): Unit to check CC data.
type_flags (number, optional): CC flags to check for. Defaults to pvp_helper.cc_flags.ANY.
min_remaining (number, optional): Minimum remaining duration in milliseconds.
local is_cced, remaining_ms, expire_time = pvp_helper:is_crowd_controlled(enemy_unit, pvp_helper.cc_flags.STUN)

if is_cced then

    core.log("Enemy is stunned for " .. (remaining_ms / 1000) .. " seconds.")

end

is_cc_immune(unit: game_object, type_flags?: number, min_remaining?: number) -> boolean, number, number​

Determines if the unit is immune to any crowd control effects specified by type_flags.

local is_immune, remaining_ms, expire_time = pvp_helper:is_cc_immune(enemy_unit, pvp_helper.cc_flags.ROOT)

if is_immune then

    core.log("Enemy is immune to roots.")

end

get_cc_reduction_mult(unit: game_object, type_flags?: number, min_remaining?: number) -> number, number, number​

Gets the CC reduction multiplier for the unit.

Returns:
mult (number): The reduction multiplier (e.g., 0.5 means 50% reduction).
current_remaining_ms (number): Remaining duration in milliseconds.
expire_time (number): The timestamp when the effect expires.
local reduction_mult = pvp_helper:get_cc_reduction_mult(enemy_unit)

if reduction_mult < 1 then

    core.log("Enemy has CC reduction: " .. ((1 - reduction_mult) * 100) .. "%")

end

get_cc_reduction_percentage(unit: game_object, type_flags?: number, min_remaining?: number) -> number, number, number​

Gets the CC reduction percentage for the unit.

local reduction_pct = pvp_helper:get_cc_reduction_percentage(enemy_unit)

if reduction_pct > 0 then

    core.log("Enemy's CC duration is reduced by " .. (reduction_pct * 100) .. "%")

end

has_cc_reduction(unit: game_object, threshold?: number, type_flags?: number, min_remaining?: number) -> boolean, number, number​

Checks if the unit has any CC reduction above a certain threshold.

Parameters:
threshold (number, optional): The minimum reduction multiplier to consider. Defaults to 0.
local has_reduction = pvp_helper:has_cc_reduction(enemy_unit, 20)

if has_reduction then

    core.log("Enemy has 20% CC reduction.")

end

is_slow(unit: game_object, threshold?: number, min_remaining?: number) -> boolean, number, number​

Determines if the unit is affected by a slowing effect.

Parameters:
threshold (number, optional): The minimum slow percentage to consider.
min_remaining (number, optional): Minimum remaining duration in milliseconds.
local is_slowed, slow_pct, expire_time = pvp_helper:is_slow(enemy_unit, 0.5)

if is_slowed then

    core.log("Enemy is slowed by at least 50%")

end

get_slow_percentage(unit: game_object, min_remaining?: number) -> number, number​

Gets the slow percentage applied to the unit.

Returns:
slow_percentage (number): The slow percentage (e.g., 0.3 for 30% slow).
expire_time (number): The timestamp when the slow effect expires.
local slow_pct, expire_time = pvp_helper:get_slow_percentage(enemy_unit)

if slow_pct > 0 then

    core.log("Enemy is slowed by " .. (slow_pct * 100) .. "%")

end

Damage Reduction Functions 🛡️​

The module provides functions to handle damage reduction effects, helping you determine if an enemy has active damage reduction buffs.

Damage Type Flags​

Similar to CC flags, damage type flags categorize types of damage:

pvp_helper.damage_type_flags.PHYSICAL    -- Physical damage

pvp_helper.damage_type_flags.MAGICAL     -- Magical damage

pvp_helper.damage_type_flags.ANY         -- Any damage type

pvp_helper.damage_type_flags.BOTH        -- Both physical and magical damage


You can combine multiple damage type flags:

local combined_damage_flags = pvp_helper.damage_type_flags:combine("PHYSICAL", "MAGICAL")

get_damage_reduction_mult(unit: game_object, type_flags?: number, min_remaining?: number) -> number, number, number​

Gets the damage reduction multiplier for the unit.

Returns:
mult (number): Damage reduction multiplier (e.g., 0.8 means 20% damage reduction).
current_remaining_ms (number): Remaining duration in milliseconds.
expire_time (number): The timestamp when the effect expires.
local reduction_mult = pvp_helper:get_damage_reduction_mult(enemy_unit)

if reduction_mult < 1 then

    core.log("Enemy has damage reduction: " .. ((1 - reduction_mult) * 100) .. "%")

end

get_damage_reduction_percentage(unit: game_object, type_flags?: number, min_remaining?: number) -> number, number, number​

Gets the damage reduction percentage for the unit.

local reduction_pct = pvp_helper:get_damage_reduction_percentage(enemy_unit)

if reduction_pct > 0 then

    core.log("Enemy's damage taken is reduced by " .. (reduction_pct * 100) .. "%")

end

has_damage_reduction(unit: game_object, threshold?: number, type_flags?: number, min_remaining?: number) -> boolean, number, number​

Checks if the unit has any damage reduction above a certain threshold.

Parameters:
threshold (number, optional): The minimum reduction multiplier to consider. Defaults to 0.
local has_reduction = pvp_helper:has_damage_reduction(enemy_unit, 20)

if has_reduction then

    core.log("Enemy has 20% damage reduction.")

end

is_damage_immune(unit: game_object, type_flags?: number, min_remaining?: number) -> boolean, number, number​

Determines if the unit is immune to any damage specified by type_flags.

local is_immune, remaining_ms, expire_time = pvp_helper:is_damage_immune(enemy_unit, pvp_helper.damage_type_flags.MAGICAL)

if is_immune then

    core.log("Enemy is immune to magical damage.")

end

Offensive Cooldown Functions 🔥​
offensive_cooldowns​

A table containing information about offensive cooldown buffs.

for _, cooldown in pairs(pvp_helper.offensive_cooldowns) do

    core.log("Offensive cooldown: " .. cooldown.buff_name)

end

has_offensive_cooldown_active(unit: game_object, min_remaining?: number) -> boolean​

Checks if the unit has any offensive cooldowns active.

local has_off_cd = pvp_helper:has_offensive_cooldown_active(enemy_unit)

if has_off_cd then

    core.log("Enemy has an offensive cooldown active.")

end

Purgeable Buffs Functions ✨​
purgeable_buffs​

A list of buffs that can be purged from a unit.

is_purgeable(unit: game_object, min_remaining?: number) -> {is_purgeable: boolean, table: {buff_id: number, buff_name: string, priority: number, min_remaining: number}?, current_remaining_ms: number, expire_time: number}​

Determines if the unit has any purgeable buffs.

Returns:
is_purgeable (boolean): Whether the unit has a purgeable buff.
table (table): Details about the purgeable buff.
current_remaining_ms (number): Remaining duration in milliseconds.
expire_time (number): The timestamp when the buff expires.
local purge_info = pvp_helper:is_purgeable(enemy_unit)

if purge_info.is_purgeable then

    core.log("Enemy has a purgeable buff: " .. purge_info.table.buff_name)

end

Utility Functions 🛠️​
get_combined_cc_descriptions(type: number) -> string​

Gets a combined description of CC types based on the type flags.

local cc_description = pvp_helper:get_combined_cc_descriptions(pvp_helper.cc_flags:combine("STUN", "ROOT"))

core.log("CC types: " .. cc_description)

get_combined_damage_type_descriptions(type: number) -> string​

Gets a combined description of damage types based on the type flags.

local damage_description = pvp_helper:get_combined_damage_type_descriptions(pvp_helper.damage_type_flags.BOTH)

core.log("Damage types: " .. damage_description)

Data Structures​
CC Flags Table 🏳️​

The cc_flags table is a collection of CC type flags used by the module.

Fields:​
MAGICAL (number): Represents magical CC effects.
PHYSICAL (number): Represents physical CC effects.
SLOW (number): Represents slow effects.
ROOT (number): Represents root effects.
STUN (number): Represents stun effects.
INCAPACITATE (number): Represents incapacitate effects.
DISORIENT (number): Represents disorient effects.
FEAR (number): Represents fear effects.
SAP (number): Represents sap effects.
CYCLONE (number): Represents cyclone effects.
KICK (number): Represents kick effects.
SILENCE (number): Represents silence effects.
ANY (number): Represents any CC effect.
ANY_BUT_SLOW (number): Represents any CC effect except slows.
Methods:​
combine(...: string) -> number: Combines multiple CC flags into a single flag value.
Damage Type Flags Table 💥​

The damage_type_flags table is a collection of damage type flags used by the module.

Fields:​
PHYSICAL (number): Represents physical damage.
MAGICAL (number): Represents magical damage.
ANY (number): Represents any damage type.
BOTH (number): Represents both physical and magical damage.
Methods:​
combine(...: string) -> number: Combines multiple damage type flags into a single flag value.
Examples​
Checking if a Unit is Under CC​
---@type pvp_helper

local pvp_helper = require("common/utility/pvp_helper")



local function is_enemy_stunned(enemy_unit)

    local is_cced = pvp_helper:is_crowd_controlled(enemy_unit, pvp_helper.cc_flags.STUN)

    return is_cced

end

Applying Logic Based on Damage Reduction​
local function should_cast_big_damage(enemy_unit)

    local has_reduction = pvp_helper:has_damage_reduction(enemy_unit, 0.3)

    return not has_reduction

end

Checking for Purgeable Buffs​
local function can_purge(enemy_unit)

    local purge_info = pvp_helper:is_purgeable(enemy_unit)

    return purge_info.is_purgeable

end

Tips and Notes​
Always ensure you're using the correct CC or damage type flags when checking for effects.
Utilize the combine function to check for multiple types simultaneously.
Remember to consider min_remaining durations if you're interested in effects that last beyond a certain time frame.