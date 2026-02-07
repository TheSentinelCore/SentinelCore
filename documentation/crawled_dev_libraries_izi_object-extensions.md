# https://docs.project-sylvanas.net/dev/libraries/izi/object-extensions

IZI - Game Object Extensions
Overview​

When you import the IZI SDK into your project, it automatically applies powerful extensions to the game_object class. These extensions add a comprehensive set of utility methods that enhance your ability to interact with game objects, making common tasks simpler and more intuitive.

These extensions are applied globally once IZI is imported, meaning all game_object instances in your code will have immediate access to these additional functions without any extra setup. This seamless integration allows you to write cleaner, more expressive code while leveraging advanced functionality for combat analysis, buff tracking, positioning, and much more.

INFO

In all code examples throughout this documentation, unit represents a game_object instance.

Unit Info​
max_health​
Syntax
unit:max_health(): number


Returns

number - Maximum health
Description

Returns the maximum health of the unit.

Example Usage

local max_hp = target:max_health()

get_health_percentage​
Syntax
unit:get_health_percentage(): number


Returns

number - The health percentage from 1 to 100 (e.g., 90 means ~90% HP)
Description

Returns the current health percentage of the unit.

Example Usage

local hp_pct = target:get_health_percentage()

if hp_pct < 20 then

    -- Execute finishing ability

end

level​
Syntax
unit:level(): number


Returns

number - The unit's level
Description

Returns the level of the unit.

Example Usage

local target_level = target:level()

get_guid​
Syntax
unit:get_guid(): game_object


Returns

game_object - The underlying game_object reference
Description

Returns the underlying game_object reference.

npc_id​
Syntax
unit:npc_id(): integer


Returns

integer - The NPC ID (0 for players)
Description

Returns the NPC ID of the unit. Returns 0 for player characters.

Example Usage

local id = target:npc_id()

if id == 12345 then

    -- Specific NPC

end

is_dummy​
WARNING

is_dummy uses an internal npc database to check if the unit is a training dummy. If the unit is not detected as a dummy please report it to silvi.

Syntax
unit:is_dummy(): boolean


Returns

boolean - True if the unit is a training dummy
Description

Checks if the unit is a training dummy.

Example Usage

if target:is_dummy() then

    -- Enable training mode features

end

is_alive​
Syntax
unit:is_alive(): boolean


Returns

boolean - True if the unit is alive
Description

Convenience method to check if the unit is alive.

Example Usage

if target:is_alive() then

    -- Cast damaging spell

end

is_valid_enemy​
Syntax
unit:is_valid_enemy(): boolean


Returns

boolean - True if the unit is an enemy of the local player
Description

Checks if the unit is a valid enemy of the local player.

Example Usage

if target:is_valid_enemy() then

    -- Engage combat

end

is_valid_ally​
Syntax
unit:is_valid_ally(): boolean


Returns

boolean - True if the unit is an ally of the local player
Description

Checks if the unit is a valid ally of the local player.

Example Usage

if target:is_valid_ally() then

    -- Cast healing spell

end

is_dead_or_ghost​
Syntax
unit:is_dead_or_ghost(): boolean


Returns

boolean - True if the unit is dead or a ghost
Description

Checks if the unit is dead or in ghost form.

Example Usage

if not target:is_dead_or_ghost() then

    -- Unit is alive, continue combat

end

is_standing_still​
Syntax
unit:is_standing_still(): boolean


Returns

boolean - True if the unit is not moving
Description

Checks if the unit is standing still (not moving), there is a slight delay to ensure accurate detection.

Example Usage

if player:is_standing_still() then

    -- Cast stationary ability

end

haste_pct​
Syntax
unit:haste_pct(): number


Returns

number - Haste percentage (e.g., 15 means 15% haste)
Description

Returns the haste percentage of the unit.

Example Usage

local haste = player:haste_pct()

spell_haste_multiplier​
Syntax
unit:spell_haste_multiplier(): number


Returns

number - Spell haste multiplier
Description

Returns the spell haste multiplier for the unit.

gcd​
Syntax
unit:gcd(): number


Returns

number - Global cooldown duration in seconds
Description

Returns the current global cooldown duration in seconds.

Example Usage

local gcd_time = player:gcd()

gcd_remains​
Syntax
unit:gcd_remains(): number


Returns

number - Remaining global cooldown time in seconds, 0 if GCD is not active
Description

Returns the remaining time on the global cooldown.

Example Usage

if player:gcd_remains() == 0 then

    -- GCD is ready

end

Damage & Defense​
get_incoming_damage​
WARNING

get_incoming_damage is not intended to be very precise it is intended to give some context to the combat scenario but do not expect it to be 100% accurate.

Syntax
unit:get_incoming_damage(deadline_time_in_seconds: number, is_exception?: boolean): number


Parameters

deadline_time_in_seconds: number - Time window to check for incoming damage
is_exception?: boolean - Optional exception flag

Returns

number - Heuristic incoming damage amount
Description

Calculates the estimated incoming damage within a specified time window.

Example Usage

local incoming = target:get_incoming_damage(2.0)

if incoming > target:max_health() * 0.5 then

    -- Heavy damage incoming, use defensive cooldown

end

get_incoming_damage_types​
Syntax
unit:get_incoming_damage_types(deadline_time_in_seconds?: number, is_exception?: boolean): table


Parameters

deadline_time_in_seconds?: number - Optional time window to check
is_exception?: boolean - Optional exception flag

Returns

table - Recent and predicted damage profile
Description

Returns a detailed breakdown of incoming damage types, allowing you to determine what defensive to press, for example if 40% of the damage is from magic we can cast a magic immunity.

get_health_percentage_inc​
WARNING

get_health_percentage_inc is not intended to be very precise it is intended to give some context to the combat scenario but do not expect it to be 100% accurate.

Syntax
unit:get_health_percentage_inc(deadline_time_in_seconds: number): (number, number, number, number)


Parameters

deadline_time_in_seconds: number - Time window for prediction

Returns

number - Future HP percentage (1..100)
number - Incoming damage amount
number - Current HP percentage
number - Incoming damage percentage
Description

Predicts future health percentage accounting for incoming damage.

Example Usage

local future_hp, incoming, current_hp, incoming_pct = target:get_health_percentage_inc(1.5)

if future_hp < 30 then

    -- Use emergency heal

end

is_damage_immune​
Syntax
unit:is_damage_immune(type_flags?: integer, min_remaining_ms?: number): (boolean, number, number)


Parameters

type_flags?: integer - Optional damage type flags to check
min_remaining_ms?: number - Minimum remaining time in milliseconds

Returns

boolean - True if the unit is damage immune
number - Remaining immunity time in milliseconds
number - Immunity expiration time
Description

Checks if the unit has PvP damage immunity active.

Example Usage

local is_immune, remaining_ms = target:is_damage_immune()

if is_immune then

    -- Skip damage abilities

end

is_cc_immune​
Syntax
unit:is_cc_immune(type_flags?: integer, min_remaining_ms?: number, ignore_dot?: boolean, dot_blacklist?: number[]): (boolean, number, number)


Parameters

type_flags?: integer - Optional CC type flags to check
min_remaining_ms?: number - Minimum remaining time in milliseconds
ignore_dot?: boolean - Whether to ignore DoT effects
dot_blacklist?: number[] - List of DoT spell IDs to ignore

Returns

boolean - True if the unit is CC immune
number - Remaining immunity time in milliseconds
number - Immunity expiration time
Description

Checks if the unit has PvP crowd control immunity active.

Example Usage

local is_immune = target:is_cc_immune()

if not is_immune then

    -- Cast crowd control ability

end

has_burst_active​
Syntax
unit:has_burst_active(min_remaining_ms?: number): boolean


Parameters

min_remaining_ms?: number - Minimum remaining time in milliseconds

Returns

boolean - True if the unit has a PvP burst window active
Description

Checks if the unit currently has offensive cooldowns active (burst window).

Example Usage

if target:has_burst_active() then

    -- Use defensive cooldowns

end

is_physical_damage_taken_relevant​
Syntax
unit:is_physical_damage_taken_relevant(): boolean


Returns

boolean - True if incoming physical damage is relevant (heuristic: >= 3.3% of current health)
Description

Checks if the unit is taking relevant physical damage based on a heuristic threshold (>= 3.3% of current health).

Example Usage

if player:is_physical_damage_taken_relevant() then

    -- Use physical damage reduction ability

end

is_magical_damage_taken_relevant​
Syntax
unit:is_magical_damage_taken_relevant(): boolean


Returns

boolean - True if incoming magical damage is relevant (heuristic: >= 3.3% of current health)
Description

Checks if the unit is taking relevant magical damage based on a heuristic threshold (>= 3.3% of current health).

Example Usage

if player:is_magical_damage_taken_relevant() then

    -- Use magical damage reduction ability

end

is_any_damage_taken_relevant​
Syntax
unit:is_any_damage_taken_relevant(): boolean


Returns

boolean - True if any incoming damage (physical + magical) is relevant (heuristic: >= 3.3% of current health)
Description

Checks if the unit is taking relevant damage of any type (physical or magical) based on a heuristic threshold (>= 3.3% of current health).

Example Usage

if player:is_any_damage_taken_relevant() then

    -- Use general damage reduction ability

end

Buffs​
get_buff_data​
Syntax
unit:get_buff_data(spec: aura_spec): buff_manager_data|nil


Parameters

spec: aura_spec - The buff specification (single spell ID or table of spell IDs)

Returns

buff_manager_data|nil - Resolved buff data from cache, or nil if not present
Description

Retrieves the full buff data for a specified buff.

Example Usage

local buff_data = target:get_buff_data(12345)

if buff_data then

    izi.print("Stacks:", buff_data.stacks)

end

buff_up​
Aliases
has_buff
Syntax
unit:buff_up(spec: aura_spec): boolean

unit:has_buff(spec: aura_spec): boolean


Parameters

spec: aura_spec - The buff specification

Returns

boolean - True if the buff is present
Description

Checks if the unit has a specific buff active.

Example Usage

if target:buff_up(12345) then

    -- Buff is active

end

buff_down​
Syntax
unit:buff_down(spec: aura_spec): boolean


Parameters

spec: aura_spec - The buff specification

Returns

boolean - True if the buff is not present
Description

Checks if the buff is not active (opposite of has_buff).

Example Usage

if player:buff_down(12345) then

    -- Reapply buff

end

get_buff_stacks​
Syntax
unit:get_buff_stacks(spec: aura_spec): number


Parameters

spec: aura_spec - The buff specification

Returns

number - Number of stacks (0 if buff is absent)
Description

Returns the number of stacks for a buff.

Example Usage

local stacks = player:get_buff_stacks(12345)

if stacks >= 5 then

    -- Consume stacks

end

buff_remains​
Aliases
buff_remains_sec
Syntax
unit:buff_remains(spec: aura_spec): number

unit:buff_remains_sec(spec: aura_spec): number


Parameters

spec: aura_spec - The buff specification

Returns

number - Remaining duration in seconds (>=0)
Description

Returns the remaining duration of a buff in seconds.

Example Usage

if player:buff_remains(12345) < 3 then

    -- Buff expiring soon

end

buff_remains_ms​
Syntax
unit:buff_remains_ms(spec: aura_spec): number


Parameters

spec: aura_spec - The buff specification

Returns

number - Remaining duration in milliseconds (>=0)
Description

Returns the remaining duration of a buff in milliseconds.

get_all_buffs​
Syntax
unit:get_all_buffs(): any[]


Returns

any[] - Snapshot of all buffs from the buff cache
Description

Returns all active buffs on the unit.

Example Usage

local buffs = target:get_all_buffs()

for _, buff in ipairs(buffs) do

    izi.print("Buff ID:", buff.spell_id)

end

Debuffs​
get_debuff_data​
Syntax
unit:get_debuff_data(spec: aura_spec): buff_manager_data|nil


Parameters

spec: aura_spec - The debuff specification

Returns

buff_manager_data|nil - Resolved debuff data from cache (includes fake window), or nil
Description

Retrieves the full debuff data for a specified debuff, including fake pandemic windows.

debuff_up​
Aliases
has_debuff
Syntax
unit:debuff_up(spec: aura_spec): boolean

unit:has_debuff(spec: aura_spec): boolean


Parameters

spec: aura_spec - The debuff specification

Returns

boolean - True if the debuff is present
Description

Checks if the unit has a specific debuff active.

Example Usage

if target:has_debuff(12345) then

    -- Debuff is active

end

debuff_down​
Syntax
unit:debuff_down(spec: aura_spec): boolean


Parameters

spec: aura_spec - The debuff specification

Returns

boolean - True if the debuff is not present
Description

Checks if the debuff is not active.

Example Usage

if target:debuff_down(12345) then

    -- Apply debuff

end

get_debuff_stacks​
Syntax
unit:get_debuff_stacks(spec: aura_spec): number


Parameters

spec: aura_spec - The debuff specification

Returns

number - Number of stacks (0 if absent; fake window returns 1)
Description

Returns the number of stacks for a debuff.

Example Usage

local stacks = target:get_debuff_stacks(12345)

if stacks >= 3 then

    -- High stack count

end

debuff_remains​
Aliases
debuff_remains_sec
Syntax
unit:debuff_remains(spec: aura_spec): number

unit:debuff_remains_sec(spec: aura_spec): number


Parameters

spec: aura_spec - The debuff specification

Returns

number - Remaining duration in seconds (>=0; fake window returns ~10)
Description

Returns the remaining duration of a debuff in seconds.

Example Usage

if target:debuff_remains(12345) < 2 then

    -- Refresh debuff

end

debuff_remains_ms​
Syntax
unit:debuff_remains_ms(spec: aura_spec): number


Parameters

spec: aura_spec - The debuff specification

Returns

number - Remaining duration in milliseconds (>=0; fake window returns ~10000)
Description

Returns the remaining duration of a debuff in milliseconds.

get_all_debuffs​
Syntax
unit:get_all_debuffs(): any[]


Returns

any[] - Snapshot of all debuffs from the debuff cache
Description

Returns all active debuffs on the unit.

Example Usage

local debuffs = target:get_all_debuffs()

for _, debuff in ipairs(debuffs) do

    izi.print("Debuff ID:", debuff.spell_id)

end

Auras​
get_aura_data​
Syntax
unit:get_aura_data(spec: aura_spec): buff_manager_data|nil


Parameters

spec: aura_spec - The aura specification

Returns

buff_manager_data|nil - Resolved aura data via aura cache, or nil
Description

Retrieves aura data for any aura (buff or debuff).

aura_up​
Aliases
has_aura
Syntax
unit:aura_up(spec: aura_spec): boolean

unit:has_aura(spec: aura_spec): boolean


Parameters

spec: aura_spec - The aura specification

Returns

boolean - True if the aura is present
Description

Checks if the unit has any aura (buff or debuff) active.

Example Usage

if target:has_aura(12345) then

    -- Aura is active

end

aura_down​
Syntax
unit:aura_down(spec: aura_spec): boolean


Parameters

spec: aura_spec - The aura specification

Returns

boolean - True if the aura is not present
Description

Checks if the aura is not active.

get_aura_stacks​
Syntax
unit:get_aura_stacks(spec: aura_spec): number


Parameters

spec: aura_spec - The aura specification

Returns

number - Number of stacks (0 if absent)
Description

Returns the number of stacks for an aura.

aura_remains​
Aliases
aura_remains_sec
Syntax
unit:aura_remains(spec: aura_spec): number

unit:aura_remains_sec(spec: aura_spec): number


Parameters

spec: aura_spec - The aura specification

Returns

number - Remaining duration in seconds (>=0)
Description

Returns the remaining duration of an aura in seconds.

aura_remains_ms​
Syntax
unit:aura_remains_ms(spec: aura_spec): number


Parameters

spec: aura_spec - The aura specification

Returns

number - Remaining duration in milliseconds (>=0)
Description

Returns the remaining duration of an aura in milliseconds.

get_all_auras​
Syntax
unit:get_all_auras(): any[]


Returns

any[] - Snapshot of all auras from the aura cache
Description

Returns all active auras on the unit.

Role & Combat​
is_tank​
Syntax
unit:is_tank(): boolean


Returns

boolean - True if the unit is a tank (role heuristic)
Description

Uses heuristics to determine if the unit has a tank role.

Example Usage

if party_member:is_tank() then

    -- Let tank handle aggro

end

is_dps​
Syntax
unit:is_dps(): boolean


Returns

boolean - True if the unit is a DPS (role heuristic)
Description

Uses heuristics to determine if the unit has a DPS role.

affecting_combat​
Syntax
unit:affecting_combat(): boolean


Returns

boolean - True if the unit is in combat
Description

Checks if the unit is currently in combat.

Example Usage

if target:affecting_combat() then

    -- Target is actively fighting

end

time_in_combat​
Syntax
unit:time_in_combat(): number


Returns

number - Time in combat in seconds
Description

Returns how long the unit has been in combat.

Example Usage

if player:time_in_combat() > 10 then

    -- Been in combat for 10+ seconds

end

get_time_to_death​
Aliases
time_to_die
Syntax
unit:get_time_to_death(): number

unit:time_to_die(): number


Returns

number - Forecasted time to death in seconds
Description

Forecasts time until the unit will die based on the current damage rates.

Range & Distance​
is_spell_in_range​
Syntax
unit:is_spell_in_range(spell: integer|izi_spell|{id:fun(self):integer}): boolean


Parameters

spell: integer|izi_spell|{id:fun(self):integer} - The spell to check range for

Returns

boolean - True if the spell is in range of the unit from the local player
Description

Checks if a spell is in range between the local player and the unit.

Example Usage

if target:is_spell_in_range(12345) then

    -- Cast spell

end

is_in_range​
Syntax
unit:is_in_range(meters: number): boolean


Parameters

meters: number - The range in meters

Returns

boolean - True if distance is less than or equal to meters
Description

Checks if the unit is within a specified distance from the local player.

Example Usage

if target:is_in_range(40) then

    -- Within 40 yards

end

is_in_melee_range​
Syntax
unit:is_in_melee_range(meters: number): boolean


Parameters

meters: number - The base range in meters

Returns

boolean - True if distance is less than or equal to meters + target radius
Description

Checks if the unit is within melee range, accounting for target hitbox size.

Example Usage

if target:is_in_melee_range(5) then

    -- Use melee ability

end

distance​
Syntax
unit:distance(): number


Returns

number - Distance to the local player in yards
Description

Returns the distance between the unit and the local player.

Example Usage

local dist = target:distance()

izi.print("Target is", dist, "yards away")

distance_to​
Syntax
unit:distance_to(other: game_object): number


Parameters

other: game_object - Another unit

Returns

number - Distance to the other unit in yards
Description

Returns the distance between this unit and another unit.

Example Usage

local dist = target:distance_to(focus)

distance_from_position​
Syntax
unit:distance_from_position(pos: vec3): number


Parameters

pos: vec3 - A world position

Returns

number - Distance to the position in yards
Description

Returns the distance between the unit and a world position.

Unit Queries​
get_enemies_in_splash_range​
Syntax
unit:get_enemies_in_splash_range(meters: number): game_object[]


Parameters

meters: number - The splash range in meters

Returns

game_object[] - All enemies within the splash range
Description

Returns enemies within a specified distance plus their radius from this unit. PvP-aware.

Example Usage

local nearby_enemies = target:get_enemies_in_splash_range(8)

if #nearby_enemies >= 3 then

    -- Use AoE ability

end

get_enemies_in_splash_range_count​
Syntax
unit:get_enemies_in_splash_range_count(meters: number): number


Parameters

meters: number - The splash range in meters

Returns

number - Count of enemies within the splash range
Description

Returns the count of enemies within splash range of this unit.

Example Usage

if target:get_enemies_in_splash_range_count(8) >= 3 then

    -- AoE opportunity

end

get_enemies_in_range​
Syntax
unit:get_enemies_in_range(meters: number, players_only?: boolean): game_object[]


Parameters

meters: number - The range in meters
players_only?: boolean - Optional flag to only include players

Returns

game_object[] - Enemies within range of this unit
Description

Returns all enemies within a specified distance from this unit.

get_enemies_in_melee_range​
Syntax
unit:get_enemies_in_melee_range(meters: number, players_only?: boolean): game_object[]


Parameters

meters: number - The base range in meters
players_only?: boolean - Optional flag to only include players

Returns

game_object[] - Enemies within melee range
Description

Returns all enemies within melee range accounting for hitbox sizes from this unit.

get_friends_in_range​
Syntax
unit:get_friends_in_range(meters: number, players_only?: boolean): game_object[]


Parameters

meters: number - The range in meters
players_only?: boolean - Optional flag to only include players

Returns

game_object[] - Friendly units within range
Description

Returns all friendly units within a specified distance from this unit.

get_party_members_in_range​
Syntax
unit:get_party_members_in_range(meters: number, players_only?: boolean): game_object[]


Parameters

meters: number - The range in meters
players_only?: boolean - Optional flag to only include players

Returns

game_object[] - Party members within range
Description

Returns all party members within a specified distance from this unit.

get_all_minions​
Syntax
unit:get_all_minions(meters?: number): game_object[]


Parameters

meters?: number - Optional range limit in meters

Returns

game_object[] - All minions belonging to this unit
Description

Returns all minions (pets, totems, etc.) belonging to this unit.

get_enemies_in_range_if​
Syntax
unit:get_enemies_in_range_if(meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_object[]


Parameters

meters: number - The range in meters
players_only?: boolean - Optional flag to only include players
filter?: unit_predicate|unit_predicate_list - Optional filtering predicate(s)

Returns

game_object[] - Filtered enemies within range
Description

Returns enemies within range that match the specified filter conditions from this unit.

Example Usage

local low_hp_enemies = target:get_enemies_in_range_if(40, false, function(u)

    return u:get_health_percentage() < 30

end)

get_enemies_in_melee_range_if​
Syntax
unit:get_enemies_in_melee_range_if(meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_object[]


Parameters

meters: number - The base range in meters
players_only?: boolean - Optional flag to only include players
filter?: unit_predicate|unit_predicate_list - Optional filtering predicate(s)

Returns

game_object[] - Filtered enemies within melee range
Description

Returns enemies within melee range that match the specified filter conditions from this unit.

get_friends_in_range_if​
Syntax
unit:get_friends_in_range_if(meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_object[]


Parameters

meters: number - The range in meters
players_only?: boolean - Optional flag to only include players
filter?: unit_predicate|unit_predicate_list - Optional filtering predicate(s)

Returns

game_object[] - Filtered friendly units within range
Description

Returns friendly units within range that match the specified filter conditions from this unit.

Example Usage

local injured_allies = player:get_friends_in_range_if(40, true, function(u)

    return u:get_health_percentage() < 80

end)

Casting​
is_casting​
Syntax
unit:is_casting(): boolean


Returns

boolean - True if the unit is currently casting
Description

Checks if the unit is actively casting a spell.

Example Usage

if target:is_casting() then

    -- Interrupt

end

get_cast_start_ms​
Syntax
unit:get_cast_start_ms(): number


Returns

number - Cast start time in milliseconds since epoch/game time, 0 if not casting
Description

Returns when the current cast started.

get_cast_end_ms​
Syntax
unit:get_cast_end_ms(): number


Returns

number - Cast end time in milliseconds, 0 if not casting
Description

Returns when the current cast will end.

get_cast_duration_ms​
Syntax
unit:get_cast_duration_ms(): number


Returns

number - Total cast duration in milliseconds
Description

Returns the total duration of the current cast.

get_cast_elapsed_ms​
Syntax
unit:get_cast_elapsed_ms(): number


Returns

number - Elapsed cast time in milliseconds, 0 if not casting
Description

Returns how much time has elapsed in the current cast.

get_cast_remaining_ms​
Syntax
unit:get_cast_remaining_ms(): number


Returns

number - Remaining cast time in milliseconds, 0 if not casting
Description

Returns the remaining time until the cast completes.

Example Usage

if target:get_cast_remaining_ms() < 200 then

    -- Cast almost finished

end

get_cast_remaining_sec​
Syntax
unit:get_cast_remaining_sec(): number


Returns

number - Remaining cast time in seconds
Description

Returns the remaining cast time in seconds.

get_cast_ratio​
Syntax
unit:get_cast_ratio(): number


Returns

number - Cast progress ratio from 0 to 1
Description

Returns the cast progress as a ratio (0.0 = just started, 1.0 = finished).

get_cast_pct​
Aliases
casting_pct
casting_percentage
Syntax
unit:get_cast_pct(): number

unit:casting_pct(): number

unit:get_cast_pct(): number


Returns

number - Cast progress percentage from 0 to 100
Description

Returns the cast progress as a percentage.

Example Usage

if target:get_cast_pct() > 70 then

    -- Interrupt near the end

end

can_cast_while_moving​
Syntax
unit:can_cast_while_moving(): boolean


Returns

boolean - True if the unit can cast while moving
Description

Checks if the unit has a buff that allows casting while moving.

Example Usage

if player:can_cast_while_moving() then

    -- Cast normally even while moving

end

Channeling​
is_channeling​
Syntax
unit:is_channeling(): boolean


Returns

boolean - True if the unit is currently channeling
Description

Checks if the unit is actively channeling a spell.

get_channel_start_ms​
Syntax
unit:get_channel_start_ms(): number


Returns

number - Channel start time in milliseconds since epoch/game time, 0 if not channeling
Description

Returns when the current channel started.

get_channel_end_ms​
Syntax
unit:get_channel_end_ms(): number


Returns

number - Channel end time in milliseconds, 0 if not channeling
Description

Returns when the current channel will end.

get_channel_duration_ms​
Syntax
unit:get_channel_duration_ms(): number


Returns

number - Total channel duration in milliseconds
Description

Returns the total duration of the current channel.

get_channel_elapsed_ms​
Syntax
unit:get_channel_elapsed_ms(): number


Returns

number - Elapsed channel time in milliseconds, 0 if not channeling
Description

Returns how much time has elapsed in the current channel.

get_channel_remaining_ms​
Syntax
unit:get_channel_remaining_ms(): number


Returns

number - Remaining channel time in milliseconds, 0 if not channeling
Description

Returns the remaining time until the channel completes.

Example Usage

if target:get_channel_remaining_ms() < 500 then

    -- Channel almost finished

end

get_channel_remaining_sec​
Syntax
unit:get_channel_remaining_sec(): number


Returns

number - Remaining channel time in seconds
Description

Returns the remaining channel time in seconds.

get_channel_ratio​
Syntax
unit:get_channel_ratio(): number


Returns

number - Channel progress ratio from 0 to 1
Description

Returns the channel progress as a ratio (0.0 = just started, 1.0 = finished).

get_channel_pct​
Aliases
channeling_pct
channeling_percentage
Syntax
unit:get_channel_pct(): number

unit:channeling_pct(): number

unit:channeling_percentage(): number


Returns

number - Channel progress percentage from 0 to 100
Description

Returns the channel progress as a percentage.

Example Usage

if target:get_channel_pct() > 80 then

    -- Interrupt near the end

end

Cast/Channel Helpers​
is_channeling_or_casting​
Syntax
unit:is_channeling_or_casting(): boolean


Returns

boolean - True if channeling or casting
Description

Checks if the unit is either casting or channeling.

Example Usage

if target:is_channeling_or_casting() then

    -- Unit is busy with a spell

end

get_active_cast_or_channel_id​
Aliases
get_any_active_spell_id
Syntax
unit:get_active_cast_or_channel_id(): number

unit:get_any_active_spell_id(): number


Returns

number - Active spell ID (prefers channel over cast), 0 if none
Description

Returns the spell ID of the active cast or channel. Returns 0 if neither is active.

Example Usage

local spell_id = target:get_active_cast_or_channel_id()

if spell_id == 12345 then

    -- Interrupt this specific spell

end

get_channeling_or_casting_remaining_ms​
Aliases
get_any_remaining_ms
Syntax
unit:get_channeling_or_casting_remaining_ms(): number

unit:get_any_remaining_ms(): number


Returns

number - Remaining time in milliseconds for active cast or channel, 0 if neither
Description

Returns the remaining time for whichever is active (channel or cast). Prefers channel over cast if both are active.

Example Usage

if target:get_channeling_or_casting_remaining_ms() < 300 then

    -- Interrupt soon

end

get_channeling_or_casting_remaining_sec​
Aliases
get_any_remaining_sec
Syntax
unit:get_channeling_or_casting_remaining_sec(): number

unit:get_any_remaining_sec(): number


Returns

number - Remaining time in seconds for active cast or channel
Description

Returns the remaining time in seconds for whichever is active (channel or cast).

get_channeling_or_casting_pct​
Syntax
unit:get_channeling_or_casting_pct(): number


Returns

number - Progress percentage from 0 to 100 for active cast or channel
Description

Returns the progress percentage for whichever is active (channel or cast).

get_channeling_or_casting_ratio​
Syntax
unit:get_channeling_or_casting_ratio(): number


Returns

number - Progress ratio from 0 to 1 for active cast or channel
Description

Returns the progress ratio for whichever is active (channel or cast).

Power (Generic)​
power_max​
Syntax
unit:power_max(): number


Returns

number - Maximum power for the unit's primary power type
Description

Returns the maximum value of the unit's primary power resource.

Example Usage

local max_power = player:power_max()

power_current​
Syntax
unit:power_current(): number


Returns

number - Current power amount
Description

Returns the current value of the unit's primary power resource.

power_pct​
Syntax
unit:power_pct(): number


Returns

number - Power percentage from 0 to 100
Description

Returns the percentage of current power relative to maximum.

Example Usage

if player:power_pct() > 80 then

    -- High power, spend it

end

power_deficit​
Syntax
unit:power_deficit(): number


Returns

number - Amount of missing power (max - current)
Description

Returns how much power is missing from maximum.

power_deficit_pct​
Syntax
unit:power_deficit_pct(): number


Returns

number - Deficit as a percentage from 0 to 100
Description

Returns the power deficit as a percentage of maximum power.

Mana​
mana_max​
Syntax
unit:mana_max(): number


Returns

number - Maximum mana
Description

Returns the maximum mana of the unit.

Example Usage

local max_mana = player:mana_max()

mana_current​
Syntax
unit:mana_current(): number


Returns

number - Current mana amount
Description

Returns the current mana of the unit.

mana_pct​
Syntax
unit:mana_pct(): number


Returns

number - Mana percentage from 0 to 100
Description

Returns the percentage of current mana relative to maximum.

Example Usage

if player:mana_pct() < 20 then

    -- Low mana warning

end

mana_deficit​
Syntax
unit:mana_deficit(): number


Returns

number - Amount of missing mana (max - current)
Description

Returns how much mana is missing from maximum.

Rage​
rage_max​
Syntax
unit:rage_max(): number


Returns

number - Maximum rage
Description

Returns the maximum rage of the unit.

Example Usage

local max_rage = player:rage_max()

rage_current​
Syntax
unit:rage_current(): number


Returns

number - Current rage amount
Description

Returns the current rage of the unit.

rage_pct​
Syntax
unit:rage_pct(): number


Returns

number - Rage percentage from 0 to 100
Description

Returns the percentage of current rage relative to maximum.

Example Usage

if player:rage_pct() > 80 then

    -- Spend rage

end

rage_deficit​
Syntax
unit:rage_deficit(): number


Returns

number - Amount of missing rage (max - current)
Description

Returns how much rage is missing from maximum.

Focus​
focus_max​
Syntax
unit:focus_max(): number


Returns

number - Maximum focus
Description

Returns the maximum focus of the unit.

Example Usage

local max_focus = player:focus_max()

focus_current​
Syntax
unit:focus_current(): number


Returns

number - Current focus amount
Description

Returns the current focus of the unit.

focus_pct​
Syntax
unit:focus_pct(): number


Returns

number - Focus percentage from 0 to 100
Description

Returns the percentage of current focus relative to maximum.

Example Usage

if player:focus_pct() > 60 then

    -- Cast focus spender

end

focus_deficit​
Syntax
unit:focus_deficit(): number


Returns

number - Amount of missing focus (max - current)
Description

Returns how much focus is missing from maximum.

focus_regen​
Syntax
unit:focus_regen(): number


Returns

number - Focus regeneration per second
Description

Returns the focus regeneration rate per second.

focus_regen_pct​
Syntax
unit:focus_regen_pct(): number


Returns

number - Focus regeneration as percentage of max per second
Description

Returns the focus regeneration rate as a percentage of maximum focus per second.

focus_time_to_max​
Syntax
unit:focus_time_to_max(): number


Returns

number - Time in seconds to reach maximum focus
Description

Calculates how long it will take to regenerate to maximum focus.

Example Usage

local ttm = player:focus_time_to_max()

if ttm < 3 then

    -- Will be at max soon

end

focus_time_to_x​
Syntax
unit:focus_time_to_x(amount: number): number


Parameters

amount: number - Target focus amount

Returns

number - Time in seconds to reach the specified focus amount
Description

Calculates how long it will take to regenerate to a specific focus amount.

Example Usage

local time_to_50 = player:focus_time_to_x(50)

focus_time_to_x_pct​
Syntax
unit:focus_time_to_x_pct(pct: number): number


Parameters

pct: number - Target focus percentage (0-100)

Returns

number - Time in seconds to reach the specified focus percentage
Description

Calculates how long it will take to regenerate to a specific focus percentage.

Energy​
energy_max​
Syntax
unit:energy_max(): number


Returns

number - Maximum energy
Description

Returns the maximum energy of the unit.

Example Usage

local max_energy = player:energy_max()

energy_current​
Syntax
unit:energy_current(): number


Returns

number - Current energy amount
Description

Returns the current energy of the unit.

energy_pct​
Syntax
unit:energy_pct(): number


Returns

number - Energy percentage from 0 to 100
Description

Returns the percentage of current energy relative to maximum.

Example Usage

if player:energy_pct() > 70 then

    -- Enough energy for combo

end

energy_deficit​
Syntax
unit:energy_deficit(): number


Returns

number - Amount of missing energy (max - current)
Description

Returns how much energy is missing from maximum.

energy_regen​
Syntax
unit:energy_regen(): number


Returns

number - Energy regeneration per second
Description

Returns the energy regeneration rate per second.

energy_regen_pct​
Syntax
unit:energy_regen_pct(): number


Returns

number - Energy regeneration as percentage of max per second
Description

Returns the energy regeneration rate as a percentage of maximum energy per second.

energy_time_to_max​
Syntax
unit:energy_time_to_max(): number


Returns

number - Time in seconds to reach maximum energy
Description

Calculates how long it will take to regenerate to maximum energy.

Example Usage

local ttm = player:energy_time_to_max()

energy_time_to_x​
Syntax
unit:energy_time_to_x(amount: number): number


Parameters

amount: number - Target energy amount

Returns

number - Time in seconds to reach the specified energy amount
Description

Calculates how long it will take to regenerate to a specific energy amount.

Example Usage

local time_to_60 = player:energy_time_to_x(60)

energy_time_to_x_pct​
Syntax
unit:energy_time_to_x_pct(pct: number): number


Parameters

pct: number - Target energy percentage (0-100)

Returns

number - Time in seconds to reach the specified energy percentage
Description

Calculates how long it will take to regenerate to a specific energy percentage.

energy_predicted​
Syntax
unit:energy_predicted(seconds: number): number


Parameters

seconds: number - Time in the future to predict

Returns

number - Predicted energy amount at the specified time
Description

Predicts the energy amount at a future point in time based on current regeneration.

Example Usage

local future_energy = player:energy_predicted(2.5)

if future_energy >= 80 then

    -- Will have enough energy in 2.5 seconds

end

energy_predicted_pct​
Syntax
unit:energy_predicted_pct(seconds: number): number


Parameters

seconds: number - Time in the future to predict

Returns

number - Predicted energy percentage at the specified time
Description

Predicts the energy percentage at a future point in time based on current regeneration.

energy_deficit_predicted​
Syntax
unit:energy_deficit_predicted(seconds: number): number


Parameters

seconds: number - Time in the future to predict

Returns

number - Predicted energy deficit at the specified time
Description

Predicts the energy deficit at a future point in time.

Runic Power​
runic_power_max​
Syntax
unit:runic_power_max(): number


Returns

number - Maximum runic power
Description

Returns the maximum runic power of the unit.

Example Usage

local max_rp = player:runic_power_max()

runic_power_current​
Syntax
unit:runic_power_current(): number


Returns

number - Current runic power amount
Description

Returns the current runic power of the unit.

runic_power_pct​
Syntax
unit:runic_power_pct(): number


Returns

number - Runic power percentage from 0 to 100
Description

Returns the percentage of current runic power relative to maximum.

Example Usage

if player:runic_power_pct() > 80 then

    -- Spend runic power

end

runic_power_deficit​
Syntax
unit:runic_power_deficit(): number


Returns

number - Amount of missing runic power (max - current)
Description

Returns how much runic power is missing from maximum.

Soul Shards​
soul_shards_max​
Syntax
unit:soul_shards_max(): number


Returns

number - Maximum soul shards
Description

Returns the maximum soul shards of the unit.

Example Usage

local max_shards = player:soul_shards_max()

soul_shards_current​
Syntax
unit:soul_shards_current(): number


Returns

number - Current soul shards amount
Description

Returns the current soul shards of the unit.

Example Usage

if player:soul_shards_current() >= 3 then

    -- Cast expensive spell

end

soul_shards_deficit​
Syntax
unit:soul_shards_deficit(): number


Returns

number - Amount of missing soul shards (max - current)
Description

Returns how many soul shards are missing from maximum.

Astral Power​
astral_power_max​
Syntax
unit:astral_power_max(): number


Returns

number - Maximum astral power
Description

Returns the maximum astral power of the unit.

Example Usage

local max_ap = player:astral_power_max()

astral_power_current​
Syntax
unit:astral_power_current(): number


Returns

number - Current astral power amount
Description

Returns the current astral power of the unit.

astral_power_pct​
Syntax
unit:astral_power_pct(): number


Returns

number - Astral power percentage from 0 to 100
Description

Returns the percentage of current astral power relative to maximum.

Example Usage

if player:astral_power_pct() > 70 then

    -- Cast Starsurge

end

astral_power_deficit​
Syntax
unit:astral_power_deficit(): number


Returns

number - Amount of missing astral power (max - current)
Description

Returns how much astral power is missing from maximum.

astral_power_deficit_pct​
Syntax
unit:astral_power_deficit_pct(): number


Returns

number - Deficit as a percentage from 0 to 100
Description

Returns the astral power deficit as a percentage of maximum astral power.

Chi​
chi_max​
Syntax
unit:chi_max(): number


Returns

number - Maximum chi
Description

Returns the maximum chi of the unit.

Example Usage

local max_chi = player:chi_max()

chi_current​
Syntax
unit:chi_current(): number


Returns

number - Current chi amount
Description

Returns the current chi of the unit.

chi_pct​
Syntax
unit:chi_pct(): number


Returns

number - Chi percentage from 0 to 100
Description

Returns the percentage of current chi relative to maximum.

Example Usage

if player:chi_pct() > 80 then

    -- Spend chi

end

chi_deficit​
Syntax
unit:chi_deficit(): number


Returns

number - Amount of missing chi (max - current)
Description

Returns how much chi is missing from maximum.

chi_deficit_pct​
Syntax
unit:chi_deficit_pct(): number


Returns

number - Deficit as a percentage from 0 to 100
Description

Returns the chi deficit as a percentage of maximum chi.

Stagger​
stagger_amount​
Syntax
unit:stagger_amount(): number


Returns

number - Current stagger damage amount
Description

Returns the current stagger damage amount for Brewmaster Monks.

Example Usage

local stagger = player:stagger_amount()

stagger_pct​
Syntax
unit:stagger_pct(): number


Returns

number - Stagger percentage relative to max health
Description

Returns the stagger amount as a percentage of maximum health.

Example Usage

if player:stagger_pct() > 5 then

    -- High stagger, use purify

end

is_stagger_medium_or_more​
Syntax
unit:is_stagger_medium_or_more(): boolean


Returns

boolean - True if stagger is at medium level or higher
Description

Checks if the stagger level is at least medium (yellow).

Example Usage

if player:is_stagger_medium_or_more() then

    -- Consider using Purifying Brew

end

is_stagger_heavy​
Syntax
unit:is_stagger_heavy(): boolean


Returns

boolean - True if stagger is at heavy level
Description

Checks if the stagger level is heavy (red).

Example Usage

if player:is_stagger_heavy() then

    -- Use Purifying Brew immediately

end

Combo Points​
combo_points_max​
Syntax
unit:combo_points_max(): number


Returns

number - Maximum combo points
Description

Returns the maximum combo points of the unit.

Example Usage

local max_cp = player:combo_points_max()

combo_points_current​
Syntax
unit:combo_points_current(): number


Returns

number - Current combo points amount
Description

Returns the current combo points of the unit.

Example Usage

if player:combo_points_current() >= 5 then

    -- Use finisher

end

combo_points_deficit​
Syntax
unit:combo_points_deficit(): number


Returns

number - Amount of missing combo points (max - current)
Description

Returns how many combo points are missing from maximum.

charged_combo_points​
Syntax
unit:charged_combo_points(): number


Returns

number - Number of charged combo points available
Description

Returns the number of charged combo points (from abilities like Echoing Reprimand).

Example Usage

local charged = player:charged_combo_points()

if charged > 0 then

    -- Use charged finisher

end

Runes​
rune_count​
Syntax
unit:rune_count(): number


Returns

number - Number of available runes
Description

Returns the number of currently available runes for Death Knights.

Example Usage

if player:rune_count() >= 3 then

    -- Cast rune-consuming ability

end

rune_time_to_x​
Syntax
unit:rune_time_to_x(count: number): number


Parameters

count: number - Target number of runes

Returns

number - Time in seconds until the specified number of runes are available
Description

Calculates how long it will take until a specific number of runes are available.

Example Usage

local time_to_3 = player:rune_time_to_x(3)

if time_to_3 < 2 then

    -- Will have 3 runes soon

end

rune_type_count​
Syntax
unit:rune_type_count(rune_type: number): number


Parameters

rune_type: number - The rune type to count (Blood=1, Frost=2, Unholy=3)

Returns

number - Number of available runes of the specified type
Description

Returns the number of available runes of a specific type for Death Knights.

Totems​
get_totem_info​
Syntax
unit:get_totem_info(slot: number): (boolean, string, number, number, number)


Parameters

slot: number - Totem slot number (1-4)

Returns

boolean - True if totem exists in this slot
string - Totem name
number - Start time
number - Duration
number - Totem spell ID
Description

Returns information about a totem in the specified slot for Shamans.

Example Usage

local has_totem, name, start_time, duration, spell_id = player:get_totem_info(1)

if has_totem then

    izi.print("Totem:", name)

end

Stealth​
stealth_remains​
Syntax
unit:stealth_remains(): number


Returns

number - Remaining stealth duration in seconds, 0 if not stealthed
Description

Returns the remaining duration of stealth effects.

Example Usage

if player:stealth_remains() > 0 then

    -- Still in stealth

end

stealth_up​
Syntax
unit:stealth_up(): boolean


Returns

boolean - True if the unit is in stealth
Description

Checks if the unit is currently in stealth.

Example Usage

if player:stealth_up() then

    -- Use stealth opener

end

stealth_down​
Syntax
unit:stealth_down(): boolean


Returns

boolean - True if the unit is not in stealth
Description

Checks if the unit is not in stealth.

Positioning​
is_behind_unit​
Syntax
unit:is_behind_unit(other: game_object): boolean


Parameters

other: game_object - The target unit

Returns

boolean - True if this unit is behind the other unit
Description

Checks if this unit is positioned behind another unit.

Example Usage

if player:is_behind_unit(target) then

    -- Use backstab

end

is_behind​
Aliases
is_behind_unit
Syntax
unit:is_behind(other: game_object): boolean


Parameters

other: game_object - The target unit

Returns

boolean - True if this unit is behind the other unit
Description

Checks if this unit is positioned behind another unit.

predict_position​
Syntax
unit:predict_position(seconds: number): vec3


Parameters

seconds: number - Time in the future to predict

Returns

vec3 - Predicted position at the specified time
Description

Predicts where the unit will be at a future point in time based on current movement.

Example Usage

local future_pos = target:predict_position(1.5)

predict_distance​
Syntax
unit:predict_distance(seconds: number): number


Parameters

seconds: number - Time in the future to predict

Returns

number - Predicted distance to the local player at the specified time
Description

Predicts the distance between this unit and the local player at a future point in time.

Example Usage

local future_dist = target:predict_distance(2.0)

if future_dist > 40 then

    -- Target will be out of range

end

los_to​
Syntax
unit:los_to(other: game_object): boolean


Parameters

other: game_object - The target unit

Returns

boolean - True if this unit has line of sight to the other unit
Description

Checks if there is line of sight between this unit and another unit.

Example Usage

if player:los_to(target) then

    -- Can cast spell

end

los_to_position​
Syntax
unit:los_to_position(pos: vec3): boolean


Parameters

pos: vec3 - The target position

Returns

boolean - True if this unit has line of sight to the position
Description

Checks if there is line of sight between this unit and a world position.

is_behind_future​
Syntax
unit:is_behind_future(other: game_object, seconds: number): boolean


Parameters

other: game_object - The target unit
seconds: number - Time in the future to check

Returns

boolean - True if this unit will be behind the other unit at the specified time
Description

Predicts if this unit will be behind another unit at a future point in time.

Example Usage

if player:is_behind_future(target, 1.0) then

    -- Will be in position for backstab

end

is_moving_towards_me​
Syntax
unit:is_moving_towards_me(): boolean


Returns

boolean - True if the unit is moving towards the local player
Description

Checks if the unit is currently moving towards the local player.

Example Usage

if target:is_moving_towards_me() then

    -- Enemy is closing in

end

PvP​
is_pvp​
Aliases
in_pvp
isPvP
inPvP
Syntax
unit:is_pvp(): boolean

unit:in_pvp(): boolean

unit:isPvP(): boolean

unit:inPvP(): boolean

Returns
boolean - True if in a PvP context
Description

Returns true if the unit is in a PvP context such as arena, battleground, duel, or war mode versus another player.

Example Usage

local target = izi.target()

if target:is_pvp() then

    izi.print("PvP combat detected!")

end

is_player_or_dummy​
Aliases
is_playerlike
isPlayerLike
isPlayerOrDummy
Syntax
unit:is_player_or_dummy(): boolean

unit:is_playerlike(): boolean

unit:isPlayerLike(): boolean

unit:isPlayerOrDummy(): boolean

Returns
boolean - True if the unit is a player or player-like target
Description

Treats special targets flagged like players (such as training dummies) as player-like entities. Useful for testing rotations against dummies that simulate player mechanics.

Example Usage

local target = izi.target()

if target:is_playerlike() then

    -- Apply PvP rotation logic

end

is_cc​
Aliases
crowd_controlled
isCrowdControlled
isCC
Syntax
unit:is_cc(min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)

unit:crowd_controlled(min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)

unit:isCrowdControlled(min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)

unit:isCC(min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration in milliseconds (default: 1000)
cc_flags?: CCFlagMask - CC type flags to check (default: CC.ANY)
source_mask?: SourceMask - Source filter mask (default: ANY)
Returns
active: boolean - True if any matching CC is active
applied_mask: CCFlagMask - Bitmask of matched CC categories
remaining_ms: Milliseconds - Best remaining duration among matches
immune: boolean - True if currently immune to the queried CC set
weak: boolean - True if only weak CC is present (breaks on damage)
Description

Generic CC query with optional filters. Checks if a unit is under crowd control effects matching the specified criteria.

Example Usage

local target = izi.target()

local is_ccd, mask, remaining, immune, weak = target:is_cc()

if is_ccd and not weak then

    izi.printf("Target CC'd for %d ms", remaining)

end



-- Check for stuns specifically

local is_stunned = target:is_cc(500, target.CC.STUN)

is_cc_weak​
Aliases
weak_cc
isWeakCC
Syntax
unit:is_cc_weak(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:weak_cc(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isWeakCC(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if weak CC is active
applied_mask: CCFlagMask - Bitmask of matched CC categories
remaining_ms: Milliseconds - Remaining duration
Description

Checks for weak CC effects that break on damage. Convenience wrapper for detecting fragile crowd control.

Example Usage

local target = izi.target()

local has_weak_cc, mask, remaining = target:is_cc_weak()

if has_weak_cc then

    izi.print("Target has weak CC - don't break it!")

end

is_rooted​
Aliases
rooted
isRooted
Syntax
unit:is_rooted(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:rooted(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isRooted(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if rooted
CC.ROOT: CCFlagMask - Root flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently rooted (unable to move but can still cast and attack).

Example Usage

local target = izi.target()

local is_rooted, _, remaining = target:is_rooted()

if is_rooted then

    izi.printf("Target rooted for %d ms", remaining)

end

is_stunned​
Aliases
stunned
isStunned
Syntax
unit:is_stunned(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:stunned(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isStunned(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if stunned
CC.STUN: CCFlagMask - Stun flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently stunned (unable to move, cast, or attack).

Example Usage

local target = izi.target()

if target:is_stunned() then

    izi.print("Target is stunned!")

end

is_feared​
Aliases
feared
isFeared
Syntax
unit:is_feared(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:feared(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isFeared(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if feared
CC.FEAR: CCFlagMask - Fear flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently feared (running away uncontrollably).

Example Usage

local target = izi.target()

if target:is_feared() then

    izi.print("Target is feared!")

end

is_sapped​
Aliases
sapped
isSapped
Syntax
unit:is_sapped(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:sapped(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isSapped(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if sapped
CC.SAP: CCFlagMask - Sap flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently sapped (incapacitated by rogue Sap ability).

Example Usage

local target = izi.target()

if target:is_sapped() then

    izi.print("Target is sapped!")

end

is_silenced​
Aliases
silenced
isSilenced
Syntax
unit:is_silenced(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:silenced(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isSilenced(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if silenced
CC.SILENCE: CCFlagMask - Silence flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently silenced (unable to cast spells).

Example Usage

local target = izi.target()

if target:is_silenced() then

    izi.print("Target is silenced!")

end

is_cycloned​
Aliases
cycloned
isCycloned
Syntax
unit:is_cycloned(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:cycloned(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isCycloned(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if cycloned
CC.CYCLONE: CCFlagMask - Cyclone flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently cycloned (incapacitated and immune to damage).

Example Usage

local target = izi.target()

if target:is_cycloned() then

    izi.print("Target is cycloned!")

end

is_disarmed​
Aliases
disarmed
isDisarmed
Syntax
unit:is_disarmed(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:disarmed(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isDisarmed(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if disarmed
CC.DISARM: CCFlagMask - Disarm flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently disarmed (unable to use weapon-based attacks).

Example Usage

local target = izi.target()

if target:is_disarmed() then

    izi.print("Target is disarmed!")

end

is_disoriented​
Aliases
isDisoriented
isDisorient
Syntax
unit:is_disoriented(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isDisoriented(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isDisorient(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if disoriented
CC.DISORIENT: CCFlagMask - Disorient flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently disoriented (wandering randomly, breaks on damage).

Example Usage

local target = izi.target()

if target:is_disoriented() then

    izi.print("Target is disoriented!")

end

is_incapacitated​
Aliases
is_incap
isIncapacitated
Syntax
unit:is_incapacitated(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:is_incap(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isIncapacitated(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 500)
source_mask?: SourceMask - Source filter mask
Returns
active: boolean - True if incapacitated
CC.INCAPACITATE: CCFlagMask - Incapacitate flag mask
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently incapacitated (unable to act, breaks on damage).

Example Usage

local target = izi.target()

if target:is_incap() then

    izi.print("Target is incapacitated!")

end

get_dr​
Aliases
dr
dr_for
getDR
DR
Syntax
unit:get_dr(category: integer|string, hit_at_sec?: number): number

unit:dr(category: integer|string, hit_at_sec?: number): number

unit:dr_for(category: integer|string, hit_at_sec?: number): number

unit:getDR(category: integer|string, hit_at_sec?: number): number

unit:DR(category: integer|string, hit_at_sec?: number): number


Parameters

category: integer|string - CC flag integer or category name ("stun", "root", "fear", "sap", "disorient", "incapacitate", "silence", "disarm", "knockback", "cyclone", "horror", "mind_control")
hit_at_sec?: number - Time to evaluate DR at (default: 0 for now)
Returns
number - DR multiplier (1.0, 0.5, 0.25, 0.0). Values > 1.01 indicate not tracked yet
Description

Returns the diminishing returns multiplier for a CC category. DR reduces the effectiveness of consecutive CC applications.

Example Usage

local target = izi.target()

local dr = target:get_dr("stun")

if dr < 1.0 then

    izi.printf("Stun DR: %.0f%%", dr * 100)

end



-- Check DR for specific flag

local root_dr = target:get_dr(target.CC.ROOT)

get_dr_time​
Aliases
dr_time
drTimeLeft
getDRTime
Syntax
unit:get_dr_time(category: integer|string): number

unit:dr_time(category: integer|string): number

unit:drTimeLeft(category: integer|string): number

unit:getDRTime(category: integer|string): number


Parameters

category: integer|string - CC flag integer or category name
Returns
number - Seconds until DR fully resets
Description

Returns the time remaining until diminishing returns fully reset for a CC category.

Example Usage

local target = izi.target()

local time_left = target:get_dr_time("stun")

if time_left > 0 then

    izi.printf("Stun DR resets in %.1f seconds", time_left)

end

is_cc_immune​
Aliases
immune_cc
isCCImmune
Syntax
unit:is_cc_immune(cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:immune_cc(cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

unit:isCCImmune(cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)


Parameters

cc_flags?: CCFlagMask - CC types to check (default: CC.ANY)
min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 100)
ignore_dot?: boolean - Whether to ignore DoT effects (default: false)
dot_blacklist?: table<integer, true> - DoT spell IDs to exclude
source_mask?: SourceMask - Source filter mask
Returns
immune: boolean - True if immune to the queried CC set
applied_mask: CCFlagMask - Mask of immunity sources
remaining_ms: Milliseconds - Best remaining duration
Description

Checks if the unit is currently immune to crowd control effects.

Example Usage

local target = izi.target()

local immune, mask, remaining = target:is_cc_immune()

if immune then

    izi.printf("Target immune to CC for %d ms", remaining)

end

get_cc_reduction​
Aliases
cc_reduction
getCCReduce
getCCReduction
Syntax
unit:get_cc_reduction(cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)

unit:get_cc_cc_reductionreduction(cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)

unit:getCCReduce(cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)

unit:getCCReduction(cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)


Parameters

cc_flags?: CCFlagMask - CC types to check (default: CC.ANY)
min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 100)
ignore_dot?: boolean - Whether to ignore DoT effects
dot_blacklist?: table<integer, true> - DoT spell IDs to exclude
source_mask?: SourceMask - Source filter mask
Returns
percent: number - Reduction percentage (0..100)
applied_mask: CCFlagMask - Mask of reduction sources
remaining_ms: Milliseconds - Remaining duration
Description

Returns the percentage by which CC duration is reduced on the target.

Example Usage

local target = izi.target()

local reduction, mask, remaining = target:get_cc_reduction()

if reduction > 0 then

    izi.printf("Target has %.0f%% CC reduction", reduction)

end

is_slowed​
Aliases
slowed
isSlowed
Syntax
unit:is_slowed(threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)

unit:slowed(threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)

unit:isSlowed(threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)


Parameters

threshold?: number - Slow threshold (default: 0.30, meaning 30% slow)
min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 2000)
source_mask?: SourceMask - Source filter mask
Returns
is_slowed: boolean - True if slowed past threshold
mult: number - Movement multiplier 0..1 (e.g., 0.6 = 40% slow)
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is slowed past a specified threshold. The movement multiplier represents the speed: 0.6 means the unit moves at 60% speed (40% slow).

Example Usage

local target = izi.target()

local is_slowed, mult, remaining = target:is_slowed(0.30)

if is_slowed then

    local slow_pct = (1 - mult) * 100

    izi.printf("Target slowed by %.0f%%", slow_pct)

end

get_slow​
Aliases
slow_mult
getSlow
Syntax
unit:get_slow(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)

unit:slow_mult(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)

unit:getSlow(min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 2000)
source_mask?: SourceMask - Source filter mask
Returns
mult: number - Movement multiplier 0..1
remaining_ms: Milliseconds - Remaining duration
Description

Returns the current slow multiplier and remaining time without a threshold check.

Example Usage

local target = izi.target()

local mult, remaining = target:get_slow()

izi.printf("Movement speed: %.0f%%", mult * 100)

is_slow_immune​
Aliases
slow_immune
isSlowImmune
Syntax
unit:is_slow_immune(source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)

unit:slow_immune(source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)

unit:isSlowImmune(source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)


Parameters

source_mask?: SourceMask - Source filter mask
min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 100)
Returns
immune: boolean - True if immune to slows
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is currently immune to slow effects.

Example Usage

local target = izi.target()

local immune, remaining = target:is_slow_immune()

if immune then

    izi.print("Target immune to slows")

end

get_damage_reduction​
Aliases
dmg_reduction
getDRPct
dmgRed
getDamageReduction
Syntax
unit:get_damage_reduction(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)

unit:dmg_reduction(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)

unit:getDRPct(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)

unit:dmgRed(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)

unit:getDamageReduction(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)


Parameters

type_flags?: DMGTypeMask - Damage types to check (default: DMG.ANY)
min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 100)
Returns
percent: number - Damage reduction percentage (0..100)
type_mask: DMGTypeMask - Matched damage types
remaining_ms: Milliseconds - Remaining duration
Description

Returns the damage reduction percentage for specified damage types.

Example Usage

local target = izi.target()

local reduction, mask, remaining = target:get_damage_reduction()

if reduction > 0 then

    izi.printf("Target has %.0f%% damage reduction", reduction)

end



-- Check physical damage reduction

local phys_dr = target:get_damage_reduction(target.DMG.PHYSICAL)

is_damage_immune​
Aliases
immune_dmg
isImmune
isDamageImmune
Syntax
unit:is_damage_immune(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)

unit:immune_dmg(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)

unit:isImmune(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)

unit:isDamageImmune(type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)


Parameters

type_flags?: DMGTypeMask - Damage types to check (default: DMG.ANY)
min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 25)
Returns
immune: boolean - True if immune to specified damage types
type_mask: DMGTypeMask - Matched damage types
remaining_ms: Milliseconds - Remaining duration
Description

Checks if the unit is immune to damage of the specified types.

Example Usage

local target = izi.target()

local immune, mask, remaining = target:is_damage_immune()

if immune then

    izi.printf("Target immune to damage for %d ms", remaining)

end

has_burst​
Aliases
is_bursting
bursting
hasBurst
Syntax
unit:has_burst(min_remaining_ms?: Milliseconds): boolean

unit:is_bursting(min_remaining_ms?: Milliseconds): boolean

unit:bursting(min_remaining_ms?: Milliseconds): boolean

unit:hasBurst(min_remaining_ms?: Milliseconds): boolean


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 1600)
Returns
boolean - True if has an active offensive burst window
Description

Returns true if the unit has an offensive burst window active (e.g., cooldowns, damage buffs). Friendly alias for has_burst_active.

Example Usage

local target = izi.target()

if target:has_burst() then

    izi.print("Target is bursting!")

end

cc_text​
Aliases
cc_desc
CCText
Syntax
unit:cc_text(cc_mask: CCFlagMask): string

unit:cc_desc(cc_mask: CCFlagMask): string

unit:CCText(cc_mask: CCFlagMask): string


Parameters

cc_mask: CCFlagMask - CC flag bitmask
Returns
string - Human-readable CC list
Description

Converts a CC bitmask into a human-readable string. Useful for HUDs and debugging.

Example Usage

local target = izi.target()

local is_ccd, mask = target:is_cc()

if is_ccd then

    local cc_desc = target:cc_text(mask)

    izi.printf("CC active: %s", cc_desc)

end

dmg_text​
Aliases
dmg_desc
DMGText
Syntax
unit:dmg_text(dmg_mask: DMGTypeMask): string

unit:dmg_desc(dmg_mask: DMGTypeMask): string

unit:DMGText(dmg_mask: DMGTypeMask): string


Parameters

dmg_mask: DMGTypeMask - Damage type flag bitmask
Returns
string - Human-readable damage type list
Description

Converts a damage type bitmask into a human-readable string. Useful for HUDs and debugging.

Example Usage

local target = izi.target()

local immune, mask = target:is_damage_immune()

if immune then

    local dmg_desc = target:dmg_text(mask)

    izi.printf("Immune to: %s", dmg_desc)

end

is_purgable​
Aliases
is_purgeable
can_be_purged
isPurgable
isPurgeable
canBePurged
Syntax
unit:is_purgable(min_remaining_ms?: Milliseconds): PurgeScanResult

unit:is_purgeable(min_remaining_ms?: Milliseconds): PurgeScanResult

unit:can_be_purged(min_remaining_ms?: Milliseconds): PurgeScanResult

unit:isPurgable(min_remaining_ms?: Milliseconds): PurgeScanResult

unit:isPurgeable(min_remaining_ms?: Milliseconds): PurgeScanResult

unit:canBePurged(min_remaining_ms?: Milliseconds): PurgeScanResult


Parameters

min_remaining_ms?: Milliseconds - Minimum remaining duration (default: 250)
Returns
PurgeScanResult - Detailed purge scan information
Description

Scans the target for purgeable buffs and returns detailed information about which buffs can be dispelled, their priorities, and timing.

Example Usage

local target = izi.target()

local result = target:is_purgable()

if result.is_purgeable then

    izi.printf("Found %d purgeable buffs", #result.table)

    for _, entry in ipairs(result.table) do

        izi.printf("- %s (priority: %d)", entry.buff_name, entry.priority)

    end

end

is_disarmable​
Aliases
can_be_disarmed
canBeDisarmed
isDisarmable
Syntax
unit:is_disarmable(include_all?: boolean): boolean

unit:can_be_disarmed(include_all?: boolean): boolean

unit:canBeDisarmed(include_all?: boolean): boolean

unit:isDisarmable(include_all?: boolean): boolean


Parameters

include_all?: boolean - If supported, include off-hand or special cases
Returns
boolean - True if the target can be disarmed
Description

Checks if the unit can currently be disarmed (has a weapon equipped that can be disarmed).

Example Usage

local target = izi.target()

if target:is_disarmable() then

    izi.print("Target can be disarmed!")

end
