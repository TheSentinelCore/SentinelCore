# https://docs.project-sylvanas.net/dev/libraries/izi

IZI - SDK
Overview​

The IZI SDK is a comprehensive, high-level toolkit designed to accelerate and simplify your plugin development workflow. It provides a rich set of utilities, event-driven callbacks, and intelligent helpers that abstract away common complexities, allowing you to focus on building powerful features rather than reinventing the wheel.

Key Features:

Enhanced Logging - Formatted console and file logging utilities
Extended Event System - Register callbacks for combat events, spell casts, buffs/debuffs, and keyboard input
Time Management - Precise timing utilities with scheduled callbacks
Target Selection - Seamlessly integrate with the target selector system
Smart Unit Management - Easily query and filter enemies, friends, and party members with flexible predicates
Queue Automation - Detect and interact with PvP/PvE queue popups
Game Object Extensions - Automatic extensions to the game_object class with advanced utility methods

Whether you're building a combat routine, automation tool, or utility plugin, the IZI SDK provides the building blocks you need to create professional-grade solutions with minimal boilerplate code.

Importing The Module​
WARNING

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the require function and store it in a local variable.

Here is an example of how to do it:

-- recomended "izi" name for consistency

---@type izi_api

local izi = require("common/izi_sdk")

Logging​
izi.print​
Syntax
izi.print(...: any)


Parameters

...: any - The arguments to print
Description

Concatenates the arguments and prints them to the console. Any non-string arguments will automatically be casted to a string.

Example Usage

izi.print("izi ", "rocks!") -- Outputs: "izi rocks!" to the console

izi.printf​
Syntax
izi.printf(fmt: string, ...: any)


Parameters

fmt: string - The format string defining the structure of the message
...: any - The values for the format string placeholders
Description

Formats a message with the provided format string and values and then prints it to the console.

Example Usage

izi.printf("izi %s!", "rocks")    -- Outputs: "izi rocks!" to the console

izi.printf("%d and %i", 1, 2)     -- Outputs: "1 and 2" to the console

izi.printf("%.2f", 3.14159265359) -- Outputs: "3.14" to the console

izi.log​
Syntax
izi.log(filename: string, ...: any)


Parameters

filename: string - The name of the file to log to (relative to your_loader_dir/scripts_log/)
...: any - The arguments to write to the file
Description

Concatenates the arguments and logs them to the specified file. Any non-string arguments will automatically be casted to a string.

Example Usage

izi.log("izi.log", "izi, ", "rocks!") -- Appends  "izi rocks!" to the file "izi.log"

izi.logf​
Syntax
izi.logf(filename: string, fmt: string, ...: any)


Parameters

filename: string - The name of the file to log to (relative to your_loader_dir/scripts_log/)
fmt: string - The format string defining the structure of the log message
...: any - The values for the format string placeholders
Description

Formats a log message with the provided format string and values and then writes it to the specified file.

Example Usage

local targets = 32

izi.logf("izi.log", "Found %d targets", targets) -- Appends "Found 32 targets" to the file "izi.log"

Callbacks​
izi.on_buff_gain​
Syntax
izi.on_buff_gain(callback: function): function


Parameters

callback: function - The function to be called when a unit gains a buff
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when a unit gains a buff.

Example Usage

local unsubscribe = izi.on_buff_gain(function(event)

    local unit = event.unit

    local buff_id = event.buff_id

    izi.printf("%s gained buff: %d", unit:get_name(), buff_id) -- Output Example: "Sylvanas gained buff: 642"

end)

izi.on_buff_lose​
Syntax
izi.on_buff_lose(callback: function): function


Parameters

callback: function - The function to be called when a unit loses a buff
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when when a unit loses a buff.

Example Usage

local unsubscribe = izi.on_buff_lose(function(event)

    local unit = event.unit

    local buff_id = event.buff_id

    izi.printf("%s lost buff: %d", unit:get_name(), buff_id) -- Output Example: "Sylvanas lost buff: 642"

end)

izi.on_debuff_gain​
Syntax
izi.on_debuff_gain(callback: function): function


Parameters

callback: function - The function to be called when a unit gains a debuff
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when when a unit gains a debuff.

Example Usage

local unsubscribe = izi.on_debuff_gain(function(event)

    local unit = event.unit

    local buff_id = event.buff_id

    izi.printf("%s gained debuff: %d", unit:get_name(), buff_id) -- Output Example: "Sylvanas gained debuff: 642"

end)

izi.on_debuff_lose​
Syntax
izi.on_debuff_lose(callback: function): function


Parameters

callback: function - The function to be called when a unit loses a debuff
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when a unit loses a debuff.

Example Usage

local unsubscribe = izi.on_debuff_lose(function(event)

    local unit = event.unit

    local buff_id = event.buff_id

    izi.printf("%s lost buff: %d", unit:get_name(), buff_id) -- Output Example: "Sylvanas lost debuff: 642"

end)

izi.on_combat_start​
Syntax
izi.on_combat_start(callback: function): function


Parameters

callback: function - The function to be called when a unit starts combat
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when a unit starts combat.

Example Usage

local unsubscribe = izi.on_combat_start(function(event)

    local unit = event.unit

    izi.printf("%s entered combat", unit:get_name()) -- Output Example: "Sylvanas entered combat"

end)

izi.on_combat_finish​
Syntax
izi.on_combat_finish(callback: function): function


Parameters

callback: function - The function to be called when a unit finishes combat
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when a unit finishes combat.

Example Usage

local unsubscribe = izi.on_combat_finish(function(event)

    local unit = event.unit

    izi.printf("%s left combat", unit:get_name()) -- Output Example: "Sylvanas left combat"

end)

izi.on_spell_begin​
Syntax
izi.on_spell_begin(callback: function): function


Parameters

callback: function - The function to be called when a unit begins casting a spell
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when a unit begins casting a spell.

Example Usage

local unsubscribe = izi.on_spell_begin(function(event)

    local spell_id = event.spell_id

    local caster = event.caster

    local target = event.target

    izi.printf("%s began casting %d at %s", caster:get_name(), spell_id, target:get_name()) -- Output Example: "Sylvanas started casting 1246861 at Arthas"

end)

izi.on_spell_success​
Syntax
izi.on_spell_success(callback: function): function


Parameters

callback: function - The function to be called when a unit cancels a spell cast
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when a unit cancels a spell cast.

Example Usage

local unsubscribe = izi.on_spell_cancel(function(event)

    local spell_id = event.spell_id

    local caster = event.caster

    local target = event.target

    izi.printf("%s stopped casting %d at %s", caster:get_name(), spell_id, target:get_name()) -- Output Example: "Sylvanas stopped casting 1246861 at Arthas"

end)

izi.on_key_release​
Syntax
izi.on_key_release(key: integer, callback: function): function


Parameters

key: integer - The key to listen for
callback: function - The function to be called when the key is released
Returns
unsubscribe: function - Function to unsubscribe the callback when invoked
Description

Registers a callback function to be invoked when the provided key is released.

Example Usage

izi.on_key_release(0x46, function()

    izi.print("F was released")

end)

Time​
izi.now​
Aliases
izi.now_seconds
Syntax
izi.now(): number

izi.now_seconds(): number

Returns
number - Current time in seconds
Description

Returns the time in seconds since the script was injected. This should not be used with game time values.

Example Usage

local current_time = izi.now()

izi.printf("Current time: %.2f seconds", current_time)



-- Using the alias

local time_seconds = izi.now_seconds()

izi.now_ms​
Syntax
izi.now_ms(): number

Returns
number - Current time in milliseconds
Description

Returns the time in miliseconds since the script was injected in milliseconds. This should not be used with game time values.

Example Usage

local current_time_ms = izi.now_ms()

izi.printf("Current time: %.0f milliseconds", current_time_ms)



-- Measuring elapsed time

local start = izi.now_ms()

-- ... some operation ...

local elapsed = izi.now_ms() - start

izi.printf("Operation took %.2f ms", elapsed)

izi.now_game_time_ms​
Syntax
izi.now_game_time_ms(): number

Returns
number - Current game time in milliseconds (if available)
Description

Returns the current game time in milliseconds using game_time() if available. This should not be used with time values as this refers to game time and not script injection time

Example Usage

local game_time = izi.now_game_time_ms()

if game_time then

    izi.printf("Game time: %.0f ms", game_time)

end

izi.after​
Syntax
izi.after(seconds, fn): function

Parameters
seconds: number - Number of seconds to wait before executing the function
fn: function - The function to execute after the delay
Returns
function - A cancel function that can be called to prevent the scheduled execution
Description

Schedules a function to be executed after a specified number of seconds. Returns a cancel function that can be used to abort the scheduled execution before it occurs.

Example Usage

-- Schedule a message to be printed after 5 seconds

local cancel = izi.after(5, function()

    izi.print("5 seconds have passed!")

end)



-- Cancel the scheduled function if needed

if some_condition then

    cancel()

    izi.print("Cancelled the scheduled message")

end

Helpers​
izi.get_player​
Aliases
izi.me
Syntax
izi.get_player(): game_object|nil`

izi.me(): game_object|nil`

Returns
me: game_object|nil - The local player object if it exists, otherwise nil
Description

Retrieves the local player object if it exists.

Example Usage

local me = izi.me()



if me then

    izi.printf("Local Player: %s", me:get_name())

end

izi.target​
Syntax
izi.target(): game_object|nil

Returns
target: game_object|nil - The local player's target if it exists, otherwise nil
Description

Retrieves the local player's target if it exists.

Example Usage

local target = izi.target()



if target then

    izi.printf("Hud Target: %s", target)

end

izi.is_in_arena​
Aliases
izi.is_arena
izi.in_arena
Syntax
izi.is_in_arena(): boolean

izi.is_arena(): boolean

izi.in_arena(): boolean

Returns
boolean
Description

Returns true if the local player is in an arena instance.

Example Usage

local in_arena = izi.is_in_arena()

izi.printf("In arena: %s", in_arena)

izi.get_time_to_die_global​
Syntax
izi.get_time_to_die_global(): number

Returns
number - The total time for the current combat scenario enemies to die in seconds
Description

Retrieves the total time to die for the local player's current combat scenario.

Example Usage

local ttd = izi.get_time_to_die_global()

izi.printf("All enemies die in: %d", ttd)

izi.spread_dot​
Syntax
izi.spread_dot(spell: izi_spell, enemies?: game_objects_table, refresh_below_ms?: number, max_attempts?: integer, message?: string): boolean

Parameters
spell: izi_spell - The DoT spell to spread to enemies
enemies?: game_object[] - Optional list of enemies to consider for spreading the DoT, if not provided, uses nearby enemies
refresh_below_ms?: number - Cast on units with remains <= this value (ms). Default 0 (only missing/expired). Uses izi_spell:cast_target_if_safe under the hood.
max_attempts?: integer - Try at most this many units (default 3)
message?: string - Optional custom message to print when casting the spell
Returns
boolean - Returns true if the spell was successfully cast on a target, false otherwise.
Description

Automatically spreads a DoT (Damage over Time) spell across multiple enemy targets. This function intelligently selects targets that either don't have the DoT applied or need it refreshed, and casts the spell on them. Very useful for multi-dotting scenarios in both PvE and PvP.

Example Usage

--Calculate immolate pandemic threshold

local IMMOLATE_PANDEMIC_SEC = 18 * 0.30

local IMMOLATE_PANDEMIC_MS = IMMOLATE_PANDEMIC_SEC * 1000



local immolate = izi.spell(348)   -- Create a new izi_spell object for immolate

local immolate_debuff_id = 157736 -- The immolate debuff ID



-- Immolate applies a **debuff** on the target that has a different ID; track it explicitly.

immolate:track_debuff({ immolate_debuff_id, immolate_spell:id() })



-- Register an update handler to call our DoT spreading every game tick

core.register_on_update_callback(function()

    -- Get all enemies within 40 yards of the local player

    local enemies = izi.enemies(40)



    -- Spread the DoT

    if izi.spread_dot(immolate_spell, enemies, IMMOLATE_PANDEMIC_MS, 3, "Immolate Spread") then

        izi.print("Immolate spread successful!")

    end

end)

izi.cast_defensive​
Syntax
izi.cast_defensive(spell: izi_spell, target: game_object, filters?: defensive_filters, message?: string, opts?: unit_cast_opts): boolean

Parameters
spell: izi_spell - The defensive spell wrapper to cast
target: game_object - The target to cast the defensive spell on
filters?: defensive_filters - Optional filters table to decide if the cast should proceed
message?: string - Optional custom message for the action queue
opts?: unit_cast_opts - Optional casting options that are forwarded to spell:cast_safe
Returns
boolean - Returns true if the spell was successfully cast, false otherwise.
Description

Casts a defensive spell on self with extra filters to decide if the cast should proceed. This function prevents casting more than one defensive within the block time, helping to avoid overlapping defensives and wasting cooldowns.

Example Usage

local ds = izi.spell(642)  -- Divine Shield (total immunity for 8 seconds)



local filters =

{

    block_time = 8.0,  -- Block further defensives for 8.0 seconds after cast

    health_percentage_threshold_raw = 30,  -- Cast if current HP <= 30%

    health_percentage_threshold_incoming = 20,  -- Cast if forecasted HP <= 20%

    physical_damage_percentage_threshold = 0,  -- Ignored

    magical_damage_percentage_threshold = 0,  -- Ignored

}



izi.cast_defensive(ds, player, filters, "izi:divine_shield", { skip_gcd = true })



local bop = izi.spell(1044)  -- Blessing of Protection (physical immunity)



local filters =

{

    block_time = 2.0,  -- Block further defensives for 2.0 seconds after cast

    health_percentage_threshold_raw = 40,  -- Cast if current HP <= 30%

    health_percentage_threshold_incoming = 30,  -- Cast if forecasted HP <= 20%

    physical_damage_percentage_threshold = 50,  -- 50% physical damage minimum!

    magical_damage_percentage_threshold = 0,  -- Ignored

}



izi.cast_defensive(bop, target, filters, "izi:blessing_of_protection", { skip_gcd = true })

Item​
izi.best_health_potion_id​
Syntax
izi.best_health_potion_id(): integer|nil

Returns
integer|nil - The item ID of the best health potion available in inventory, or nil if none found
Description

Automatically detects and returns the item ID of the best (highest level/quality) health potion available in the player's inventory. This is useful for creating adaptive healing logic that works across different character levels and expansions.

Example Usage

local potion_id = izi.best_health_potion_id()

if potion_id then

    izi.printf("Best health potion ID: %d", potion_id)

    local potion = izi.item(potion_id)

    if potion:use_self_safe() then

        izi.print("Used health potion!")

    end

end

izi.best_mana_potion_id​
Syntax
izi.best_mana_potion_id(): integer|nil

Returns
integer|nil - The item ID of the best mana potion available in inventory, or nil if none found
Description

Automatically detects and returns the item ID of the best (highest level/quality) mana potion available in the player's inventory. This is useful for creating adaptive mana management logic that works across different character levels and expansions.

Example Usage

local potion_id = izi.best_mana_potion_id()

if potion_id then

    izi.printf("Best mana potion ID: %d", potion_id)

    local potion = izi.item(potion_id)

    if potion:use_self_safe() then

        izi.print("Used mana potion!")

    end

end

izi.use_best_health_potion_safe​
Syntax
izi.use_best_health_potion_safe(opts?: item_use_opts): boolean


Parameters

opts?: item_use_opts - Optional usage options with full safety checks
Returns
boolean - True if a health potion was successfully used
Description

Convenience function that automatically finds and uses the best health potion available in the player's inventory with full validation. This combines best_health_potion_id() with safe item usage in a single call.

Example Usage

local player = izi.get_player()



-- Use health potion when below 50% health

if player:get_health_percentage() < 50 then

    if izi.use_best_health_potion_safe() then

        izi.print("Used health potion!")

    end

end



-- Use with custom options

if player:get_health_percentage() < 30 then

    if izi.use_best_health_potion_safe({

        skip_moving = true,

        skip_casting = true

    }) then

        izi.print("Emergency health potion used!")

    end

end

izi.use_best_mana_potion_safe​
Syntax
izi.use_best_mana_potion_safe(opts?: item_use_opts): boolean


Parameters

opts?: item_use_opts - Optional usage options with full safety checks
Returns
boolean - True if a mana potion was successfully used
Description

Convenience function that automatically finds and uses the best mana potion available in the player's inventory with full validation. This combines best_mana_potion_id() with safe item usage in a single call.

Example Usage

local player = izi.get_player()



-- Use mana potion when below 30% mana

if player:get_power_percentage() < 30 then

    if izi.use_best_mana_potion_safe() then

        izi.print("Used mana potion!")

    end

end



-- Use with custom options

if player:get_power_percentage() < 20 then

    if izi.use_best_mana_potion_safe({

        skip_moving = true,

        skip_gcd = true

    }) then

        izi.print("Emergency mana potion used!")

    end

end

Target Selector​
izi.get_ts_target​
Syntax
izi.get_ts_target()

Returns
target: game_object|nil - The first target from the target selector, or nil if none are found.
Description

Gets the first target from the target selector, if there are no targets it returns nil.

Example Usage

local target = izi.get_ts_target()



if target then

    izi.printf("Target: %s", target:get_name())

end

izi.get_ts_targets​
Syntax
izi.get_ts_targets(limit?: integer): game_object[]


Parameters

limit?: integer - Optional maximum number of targets to retrieve
Returns
targets: game_object[] - An array of target selector units, or an empty array if none are found.
Description

Gets all the targets from the target selector, if a limit is provided it will provide up to that limit.

Example Usage

local targets = izi.get_ts_targets()

izi.printf("%d targets", #targets)

izi.ts​
Syntax
izi.ts(i?: integer): game_object|nil


Parameters

i?: integer - Optional target selector index to retrieve. Default: 1
Returns
target: game_object|nil - The target selector unit, or nil if not found.
Description

Retrieves the target selector unit, if no index is provided it will return the first target.

Example Usage

local target = izi.ts(2)



if target then

    izi.printf("Target at index 2: %s", target)

end

Unit Manager​
izi.enemies​
Syntax
izi.enemies(radius?: number, players_only?: boolean): game_object[]


Parameters

radius?: integer - Optional maximum radius around the local player to get enemies from.
players_only?: boolean - Optional flag to get enemy players only ignoring NPCs.
Returns
enemies: game_object[] - An array of game objects representing enemies within the specified radius.
Description

Gets enemies around the local player.

Example Usage

local enemies = izi.enemies(40)

izi.printf("%d enemies within 40 yards", #enemies)

izi.friends​
Syntax
izi.friends(radius?: number, players_only?: boolean): game_object[]


Parameters

radius?: integer - Optional maximum radius around the local player to get friends from
players_only?: boolean - Optional flag to get friendly players only ignoring NPCs
Returns
friends: game_object[] - An array of game objects representing friends within the specified radius.
Description

Gets friends around the local player.

Example Usage

local friends = izi.friends(40)

izi.printf("%d friends within 40 yards", #friends)

izi.party​
Syntax
izi.party(radius?: number): game_object[]


Parameters

radius?: integer - Optional maximum radius around the local player to get party members from
Returns
party: game_object[] - An array of game objects representing party members within the specified radius.
Description

Gets party members around the local player.

Example Usage

local party = izi.party(40)

izi.printf("%d party members within 40 yards", #party)

izi.pick_enemy​
Syntax
izi.pick_enemy(radius?: number, players_only?: boolean, filter: function, mode: sort_mode): game_object|nil


Parameters

radius?: number - Optional maximum radius around the local player to search for an enemy
players_only?: boolean - Optional flag to only include enemy players, excluding NPCs
filter: function - A function that takes a game_object and returns a number for scoring, or nil to exclude the unit
mode: sort_mode - The sorting mode to determine which enemy to pick
Returns
game_object|nil - The selected enemy based on the filter and sort mode, or nil if no valid enemy found
Description

Picks a single enemy from nearby units based on a custom scoring function and sort mode. The filter function should return a number representing the unit's priority score, or nil to exclude the unit from consideration.

Example Usage

-- Pick the enemy with the lowest health percentage

local low_hp_enemy = izi.pick_enemy(40, false, function(enemy)

    return enemy:get_health_percentage()

end, "min")



if low_hp_enemy then

    izi.printf("Lowest HP enemy: %s (%.1f%%)", low_hp_enemy:get_name(), low_hp_enemy:get_health_percentage())

end

izi.enemies_if​
Syntax
izi.enemies_if(radius?: number, filter?: function): game_object[]


Parameters

radius?: number - Optional maximum radius around the local player to search for enemies
filter?: function | function[] - A predicate function or list of predicates that takes a game_object and returns true to include the unit
Returns
game_object[] - A table of enemies that match the filter criteria
Description

Gets enemies around the local player that match the specified filter condition(s). The filter can be a single predicate function or a list of predicate functions.

Example Usage

-- Get all enemies below 50% health

local low_hp_enemies = izi.enemies_if(40, function(unit)

    return unit:get_health_percentage() < 50

end)



izi.printf("Found %d low HP enemies", #low_hp_enemies)



-- Get all enemies that are casting

local casting_enemies = izi.enemies_if(40, function(unit)

    return unit:is_casting()

end)



-- Get all enemies that are both in combat and players

local combat_players = izi.enemies_if(40, function(unit)

    return unit:is_in_combat() and unit:is_player()

end)

izi.friends_if​
Syntax
izi.friends_if(radius?: number, filter?: function): game_object[]


Parameters

radius?: number - Optional maximum radius around the local player to search for friendly units
filter?: function - A predicate function or list of predicates that takes a game_object and returns true to include the unit
Returns
game_object[] - A table of friendly units that match the filter criteria
Description

Gets friendly units around the local player that match the specified filter condition(s). The filter can be a single predicate function or a list of predicate functions.

Example Usage

-- Get all friends below 70% health

local injured_friends = izi.friends_if(40, function(unit)

    return unit:get_health_percentage() < 70

end)



izi.printf("Found %d injured friends", #injured_friends)



-- Get all friends that are in combat

local combat_friends = izi.friends_if(40, function(unit)

    return unit:is_in_combat()

end)

Queue​
izi.queue_popup_info​
Syntax
izi.queue_popup_info(): { has_popup: boolean, info: queue_popup_info|nil }

Returns
has_popup: boolean - Whether a queue popup is currently active.
info: queue_popup_info|nil - Information about the queue popup if one exists. See queue_popup_info
Description

Returns whether a queue popup is currently present and provides detailed information about it. The queue_popup_info contains details such as the queue kind (PvP or PvE) and other relevant data.

Example Usage

local has_popup, info = izi.queue_popup_info()



if has_popup then

    izi.printf("Queue popup detected: %s", info.kind)

end

izi.queue_has_popup​
Syntax
izi.queue_has_popup(): boolean

Returns
boolean - True if a queue popup is currently active
Description

A simple check to determine if a queue popup is currently present. This is a convenience function that provides just the boolean result without additional information.

Example Usage

if izi.queue_has_popup() then

    izi.print("Queue is ready!")

end

izi.queue_accept​
Syntax
izi.queue_accept(kind?: queue_kind, idx?: integer): boolean


Parameters

kind?: queue_kind - The kind of queue to accept. If not specified, accepts any queue. See queue_kind
idx?: integer - The index of the queue to accept if multiple queues are available
Returns
boolean - True if the queue was successfully accepted
Description

Accepts a queue popup. You can optionally specify the kind of queue (PvP or PvE) and the index if multiple queues are present.

Example Usage

-- Accept any queue

if izi.queue_has_popup() then

    izi.queue_accept()

end



-- Accept only PvP queues

local has_popup, info = izi.queue_popup_info()

if has_popup and info.kind == "pvp" then

    izi.queue_accept("pvp")

end

izi.queue_decline​
Syntax
izi.queue_decline(kind?: queue_kind, idx?: integer): boolean


Parameters

kind?: queue_kind - The kind of queue to decline. If not specified, declines any queue
idx?: integer - The index of the queue to decline if multiple queues are available
Returns
boolean - True if the queue was successfully declined
Description

Declines a queue popup. You can optionally specify the kind of queue (PvP or PvE) and the index if multiple queues are present.

Example Usage

-- Decline any queue

if izi.queue_has_popup() then

    izi.queue_decline()

end



-- Decline only PvE queues

local has_popup, info = izi.queue_popup_info()

if has_popup and info.kind == "pve" then

    izi.queue_decline("pve")

end

Queue - Types​
queue_kind​
Type Definition
"none" | "pve" | "pvp"

Description

Represents the type of queue. Can be one of three values:

"none" - No active queue
"pve" - Player vs Environment queue (dungeons, raids, etc.)
"pvp" - Player vs Player queue (battlegrounds, arenas, etc.)
queue_pve_meta​
Type Definition
{

    proposal: boolean

}


Fields

proposal: boolean
Description

Metadata specific to PvE queue popups.

queue_pvp_slot​
Type Definition
{

    idx: integer,

    status: any,

    is_call: boolean|nil,

    expires_at_ms: integer|nil

}


Fields

idx: integer - The index of the PvP queue slot.
status: any - The current status of the queue slot.
is_call: boolean|nil
expires_at_ms: integer|nil - Timestamp in milliseconds when the queue expires
Description

Represents a single PvP queue slot with its status and timing information.

queue_pvp_meta​
Type Definition
{

    slots: queue_pvp_slot[]

}


Fields

slots: queue_pvp_slot[] - Table of PvP queue slots
Description

Metadata specific to PvP queue popups, containing information about all available queue slots.

queue_popup_info​
Type Definition
{

    kind: queue_kind,

    since_sec: number,

    since_ms: integer,

    age_sec: number,

    age_ms: integer,

    expire_sec: number|nil,

    expire_ms: integer|nil,

    pve: queue_pve_meta|nil,

    pvp: queue_pvp_meta|nil

}


Fields

kind queue_kind - The type of queue ("none", "pve", or "pvp")
since_sec: number - Time in seconds since the queue popup appeared (relative to game time)
since_ms: integer - Time in milliseconds since the queue popup appeared (relative to game time)
age_sec: number - Age of the queue popup in seconds
age_ms: integer - Age of the queue popup in milliseconds
expire_sec: number|nil - Seconds until the queue popup expires (if applicable)
expire_ms: integer|nil - Milliseconds until the queue popup expires (if applicable)
pve: queue_pve_meta|nil - PvE-specific metadata (present when kind is "pve")
pvp: queue_pvp_meta|nil - PvP-specific metadata (present when kind is "pvp")
Description

Contains comprehensive information about a queue popup, including timing details and queue-type-specific metadata.

Types​
sort_mode​
Union Type Definition
"max" | "min"

Description

Represents the sorting mode for functions that select values based on scoring criteria.

"max" - Selects the value with the highest score
"min" - Selects the value with the lowest score
CCFlagMask​
Type Alias
integer

Description

Bitmask of CC (Crowd Control) flags. These flags can be combined using bitwise OR operations to represent multiple CC types simultaneously.

DMGTypeMask​
Type Alias
integer

Description

Bitmask of damage-type flags. These flags can be combined using bitwise OR operations to represent multiple damage types simultaneously.

SourceMask​
Type Alias
integer

Description

Bitmask of source filters for identifying the origin of effects (e.g., player, pet, totem). These are engine-defined values that can be combined using bitwise OR operations.

Milliseconds​
Type Alias
integer

Description

Represents time values in milliseconds. Used for precise timing calculations in PvP scenarios.

defensive_filters​
Type Definition
{

    block_time?: number,

    health_percentage_threshold_raw?: number,

    health_percentage_threshold_incoming?: number,

    physical_damage_percentage_threshold?: number,

    magical_damage_percentage_threshold?: number

}


Fields

block_time?: number - Seconds to block further defensives after success (default: 1)
health_percentage_threshold_raw?: number - Cast if current HP % <= this value (default: 50)
health_percentage_threshold_incoming?: number - Cast if forecasted HP % <= this value (default: 40)
physical_damage_percentage_threshold?: number - If >0, cast if incoming physical damage %>= this and relevant (default: 0, ignored)
magical_damage_percentage_threshold?: number - If >0, cast if incoming magical damage % >= this and relevant (default: 0, ignored)
Description

Optional filters for controlling when defensive spells should be cast. These filters help automate defensive spell usage based on health thresholds and incoming damage types.

PurgeEntry​
Type Definition
{

    buff_id: integer,

    buff_name: string,

    priority: integer,

    min_remaining: number

}


Fields

buff_id: integer - The ID of the purgeable buff
buff_name: string - The name of the purgeable buff
priority: integer - Priority value for purging (higher priority = more important to purge)
min_remaining: number - Minimum remaining duration in seconds for the buff to be considered for purging
Description

Represents a single purgeable buff entry with metadata about its priority and duration requirements. Used by the purge scanning system to identify which buffs should be dispelled.

PurgeScanResult​
Type Definition
{

    is_purgeable: boolean,

    table: PurgeEntry[],

    current_remaining_ms: integer,

    expire_time: number

}


Fields

is_purgeable: boolean - Whether the target has any purgeable buffs
table: PurgeEntry[] - List of purge candidate buffs
current_remaining_ms: integer - Remaining duration in milliseconds of the shortest candidate
expire_time: number - Engine time in seconds when the shortest candidate expires
Description

Contains the result of a purge scan operation, including all purgeable buffs found on a target and timing information for optimal purge execution. The table field contains detailed information about each purgeable buff, sorted by priority and duration.

Notes:

CC flags and damage type flags are bitmasks that can be combined with bitwise OR operations
Source mask is a bitmask for filtering effect sources (player, pet, totem, etc.)
CC query functions return: (active: boolean, applied_mask: integer, remaining_ms: integer [, immune: boolean] [, weak: boolean])
DR (Diminishing Returns): get_dr() returns multiplicative DR values (1.0, 0.5, 0.25, 0.0); get_dr_time() returns seconds until DR reset
Slows: Movement multiplier (mult) is in range [0..1]. Example: mult 0.6 means 40% slow. is_slowed(threshold) compares against 1 - mult
has_burst is a friendly alias for has_burst_active within pvp_helper
Code Examples​
Focus game when queue pops​
---@type izi_api

local izi = require("common/izi_sdk")



-- =========

-- Config UI

-- =========



local tag = "izi_queue_pop_" .. "19_09_2025_"



local menu_elements = {

    root_node = core.menu.tree_node(),

    track_pvp = core.menu.checkbox(true,  tag .. "track_pvp"),

    track_pve = core.menu.checkbox(true,  tag .. "track_pve"),

    anti_afk  = core.menu.checkbox(true,  tag .. "anti_afk"),

}



local plugin_name = "Queue Popup Helper"

local function menu_render()

    menu_elements.root_node:render(plugin_name, function()

        menu_elements.track_pvp:render("Track PvP queues")

        menu_elements.track_pve:render("Track PvE queues")

        menu_elements.anti_afk:render("Anti AFK")

    end)

end



local prefix = "[" .. plugin_name .. "] "

local function print(message)

    core.log(prefix .. message)

end



-- ==================

-- Lightweight runtime

-- ==================



-- queue → bring window to front every 2.0s while popup is present (if enabled)

local last_focus_ping_s   = 0

local FOCUS_PING_EVERY_S  = 10.0



-- anti-afk: one tiny step forward if 60s of no movement

local last_seen_move_s = 0

local nudge_active     = false

local nudge_start_s    = 0

local NUDGE_GAP_S      = 60.0

local NUDGE_HOLD_S     = 0.05   -- how long we hold the forward key



-- helper: simple on/off

local function anti_afk_enabled_now()

    return menu_elements.anti_afk:get_state()

end



local function on_update()

    local lp = izi.me()

    if not (lp and lp.is_valid and lp:is_valid()) then return end



    local now_s = core.time()



    -- Track real movement (any movement resets the AFK timer)

    if lp:is_moving() then

        last_seen_move_s = now_s

    end



    -- Queue focus ping (ultra-cheap; only every 2s)

    do

        local has, info = izi.queue_popup_info()

        if has and (now_s - last_focus_ping_s) >= FOCUS_PING_EVERY_S then

            if (info.kind == "pvp" and menu_elements.track_pvp:get_state()) or

               (info.kind == "pve" and menu_elements.track_pve:get_state()) then

                if core.set_window_foremost then core.set_window_foremost() end

                print("Triggering window foremost for queue!")

                last_focus_ping_s = now_s

            end

        end



        -- Anti-AFK (simple on/off)

        local want_afk = anti_afk_enabled_now()



        -- finish a running nudge after hold time

        if nudge_active and (now_s - nudge_start_s) >= NUDGE_HOLD_S then

            nudge_active = false

            if core.input and core.input.move_forward_stop then

                core.input.move_forward_stop()

            end

        end



        if want_afk then

            if (now_s - last_seen_move_s) >= NUDGE_GAP_S and not nudge_active then

                -- do a tiny forward tap

                if core.input and core.input.move_forward_start then

                    core.input.move_forward_start()

                    nudge_active   = true

                    nudge_start_s  = now_s

                    last_seen_move_s = now_s -- schedule next nudge in 60s

                    print("Anti AFK")

                end

            end

        end

    end

end



-- Initialize AFK timer so we don’t instantly nudge on load

last_seen_move_s = core.time()



core.register_on_render_menu_callback(menu_render)

core.register_on_update_callback(on_update)
