# https://docs.project-sylvanas.net/dev/api/core

Core Functions
Overview​

This module contains a collection of essential functions that you will probably need sooner or later in your scripts. This module includes utilities for logging, callbacks, time management, and accessing game information.


Callbacks - Brief Explanation
This is essentially the most important part of scripting, since most of your code must be ran inside a callback.


What is a Callback?
A callback is a function that you write, which you then pass to the game engine or framework. The engine doesn't execute this function immediately. Instead, it "calls back" to your function at a specific time or when a particular event occurs in the game. Think of it like leaving your phone number with a friend (the game engine) and asking them to call you (execute your function) when a certain event happens.


Why Use Callbacks?
Callbacks allow your game to respond to events without constantly checking for them. This makes your code more efficient and easier to manage. Instead of writing code that keeps asking, "Has the player pressed a button yet? Has an enemy appeared yet?" you can simply tell the game engine, "When this happens, run this function." So, all games use callbacks to run, and same with WoW.


Real-World Analogy


Imagine you're waiting for a package to be delivered. You don't stand by the door all day waiting for it (which would be like constantly checking in a loop). Instead, you might continue with your day, and when the doorbell rings (the event), you go to answer it (the callback function is executed).

What was explained is what is a callback in general in the context of videogames. In our case, we have multiple events that our callbacks will be listening to. These are the following:

On Update — This is the callback that you will use to run your logic most of the time. The code placed inside this callback is called at a reduced speed, relative to the speed of On Render. It's ideal for logic that doesn't need to be executed every frame. In a game where 95% of spells have a global cooldown, 50% of spells are cast, and units move at 7 yards per second, you don't need to read all the information and check everything every frame. Doing so at 120 FPS means you're, for example, checking the position of all units 120 times per second, which is unnecessary. That's where On Update comes in.

On Render — This is a callback used only for rendering graphics, like rectangles, circles, etc. (See graphics). It is the most important and central callback, placed within the game inside DirectX in a part called EndScene. Every time DirectX is about to render something, this callback is called. That's why it's called On Render, and it's the callback that's called the most times of all—exactly once per frame. This allows the game to draw the graphics and call your callback so that you can draw at the same speed, neither one frame more nor less, ensuring it feels natural within the game. While you could place your logic here, common sense suggests otherwise.

On Render Menu — This is a callback used only for rendering menu elements. (See Menu Elements)

On Render Control Panel — This is a very specialized callback that will be used ONLY to handle the control panel elements. (See Control Panel)

On Spell Cast — This callback will only trigger if a spell is cast, so it might be useful to control some specific cooldowns or how your spells (or other game objects) are being cast.

On Legit Spell Cast — This callback will only trigger if a spell is MANUALLY cast by the player.

NOTE

As you will see in the following examples, all callbacks expect you to pass a function. This function must contain all the code that will be read in the case that the event that the callback is listening to is triggered.

You can pass it anonymously:

core.register_on_render_callback(function()

    -- your render code here

end)


Or you can pass a defined function:

local function all_my_render_code_function()

-- your render code here

end



core.register_on_render_callback(all_my_render_code_function)


On render callback was used just as an example, but this behaviour is the same for all available callbacks.

Callback Functions 🔄​
core.register_on_pre_tick_callback​
Syntax
core.register_on_pre_tick_callback(callback: function)


Parameters

callback: function - The function to be called before each game tick.
Description

Registers a callback function to be executed before each game tick.

Example Usage

core.register_on_pre_tick_callback(function()

    -- Code to execute before each game tick

end)

core.register_on_update_callback​
Syntax
core.register_on_update_callback(callback: function)


Parameters

callback: function - The function to be called on each frame update.
Description

Registers a callback function to be executed on each frame update.

Example Usage

core.register_on_update_callback(function()

    -- Code to execute every frame

end)

core.register_on_render_callback​
Syntax
core.register_on_render_callback(callback: function)


Parameters

callback: function - The function to be called during the render phase.
Description

Registers a callback function to be executed during the render phase.

Example Usage

local function on_render()

    -- Rendering code here

end



core.register_on_render_callback(on_render)

core.register_on_render_menu_callback​
Syntax
core.register_on_render_menu_callback(callback: function)


Parameters

callback: function - The function to render custom menu elements.
Description

Registers a callback function to render custom menu elements.

WARNING

Avoid calling game functions within this callback. It should be used solely for rendering menus and variables.

Example Usage

local function render_menu()

    -- Menu rendering code here

end



core.register_on_render_menu_callback(render_menu)

core.register_on_render_control_panel_callback​
Syntax
core.register_on_render_control_panel_callback(callback: function)


Parameters

callback: function - The function to render control panel elements.
Description

Registers a callback function to render control panel elements.

Example Usage

local function render_control_panel()

    -- Control panel rendering code here

end



core.register_on_render_control_panel_callback(render_control_panel)

core.register_on_spell_cast_callback​
Syntax
core.register_on_spell_cast_callback(callback: function)


Parameters

callback: function - The function to be called when any spell is cast.
Description

Registers a callback function that is invoked whenever any spell is cast in the game, including spells cast by the player, allies, and enemies.

Example Usage

local function on_spell_casted(data)

    -- Access spell data

    local spell_name = core.spell_book.get_spell_name(data.spell_id)

    core.log(string.format("Spell cast detected: %s", spell_name))

end



core.register_on_spell_cast_callback(on_spell_casted)

core.register_on_legit_spell_cast_callback​
Syntax
core.register_on_legit_spell_cast_callback(callback: function)


Parameters

callback: function - The function to be called when the local player casts a spell, including unsuccessful attempts.
Description

Registers a callback function that is invoked when the local player casts a spell, including unsuccessful attempts.

Example Usage

local function on_legit_spell_cast(data)

    -- Handle local player's spell cast

end



core.register_on_legit_spell_cast_callback(on_legit_spell_cast)

NOTE

The "data" parameter is filled with the ID of the spell that was just casted. You can check the way this callback works by adding a core.log(tostring(data)) call inside the function called by the callback.

Logging - An Important Tool 🔥​

Use Logs In Your Code!
Adding debug logs is a very powerfull tool that you should use in all your plugins. This will help you find bugs and typos very easily. One option that we recommend is that you add a debug local variable (boolean) at the top of your code. When true, the debug for your code will be enabled. For example:

local debug = false



local function my_logics()

    local is_check_1_ok = true

    if not is_check_1_ok then

        if debug then

            core.log("Check 1 is not ok! .. aborting logics because of it - -")

        end



        return false

    end



    local is_check_2_ok = true

    if not is_check_2_ok then

        if debug then

            core.log("Check 2 is not ok! .. aborting logics because of it - -")

        end



        return false

    end



    if debug then

        core.log("All checks were ok! .. Running logics succesfully!")

    end



    return true

end


Obviously, this is a very simple example without any real logic or functionality, but it was showcased here just so you see the recommended workflow. All these prints will only work if your debug variable is true, which is something you can change in less than a second.

Logging - Functions 📄​
core.log​
Syntax
core.log(message: string)


Parameters

message: string - The message to log.
Description

Logs a standard message.

Example Usage

core.log("This is a standard log message.")

TIP

Use LUA's in-built strings function to format your logs. For example, to pass from boolean or number to string, you would have to use the tostring() function. Example: Logging the cooldown of a spell:

local function print_spell_cd(spell_id)

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    local spell_cd = core.spell_book.get_spell_cooldown(spell_id)



    core.log("Remaining Spell (ID: " .. tostring(spell_id) .. ") CD: " .. tostring(spell_cd) .. "s")

end

core.log_error​
Syntax
core.log_error(message: string)


Parameters

message: string - The error message to log.
Description

Logs an error message.

Example Usage

core.log_error("An error has occurred.")

core.log_warning​
Syntax
core.log_warning(message: string)


Parameters

message: string - The warning message to log.
Description

Logs a warning message.

Example Usage

core.log_warning("This is a warning message.")

core.log_file​
Syntax
core.log_file(message: string)


Parameters

message: string - The message to log to a file.
Description

Logs a message to a file.

WARNING

Access to log files may be restricted due to security considerations.

Example Usage

core.log_file("Logging this message to a file.")

Time and Performance Functions ⏱️​
core.get_ping​
Syntax
core.get_ping() -> number

Returns
number: The current network ping.
Description

Retrieves the current network ping.

Example Usage

local ping = core.get_ping()

core.log("Current ping: " .. ping .. " ms")

core.time​
Syntax
core.time() -> number

Returns
number: The time in milliseconds since the script was injected.
Description

Returns the time elapsed since the script was injected.

Example Usage

local script_time = core.time()

core.log("Time since script injection: " .. script_time .. " ms")

core.game_time​
Syntax
core.game_time() -> number

Returns
number: The time in milliseconds since the game started.
Description

Returns the time elapsed since the game started.

Example Usage

local game_time = core.game_time()

core.log("Game time elapsed: " .. game_time .. " ms")

core.delta_time​
Syntax
core.delta_time() -> number

Returns
number: The time in milliseconds since the last frame.
Description

Returns the time elapsed since the last frame.

Example Usage

local dt = core.delta_time()

-- Use dt for frame-dependent calculations

core.cpu_time​
Syntax
core.cpu_time() -> number

Returns
number: The CPU time used.
Description

Retrieves the CPU time used.

Example Usage

local cpu_time = core.cpu_time()

core.log("CPU time used: " .. cpu_time)

core.cpu_ticks_per_second​
Syntax
core.cpu_ticks_per_second() -> number

Returns
number: The number of CPU ticks per second.
Description

Retrieves the number of CPU ticks per second.

Example Usage

local ticks_per_second = core.cpu_ticks_per_second()

core.log("CPU ticks per second: " .. ticks_per_second)

Game Information Functions 🗺️​
core.get_map_id​
Syntax
core.get_map_id() -> number

Returns
number: The current map ID.
Description

Retrieves the ID of the current map.

Example Usage

local map_id = core.get_map_id()

core.log("Current map ID: " .. map_id)

core.get_map_name​
Syntax
core.get_map_name() -> string

Returns
string: The name of the current map.
Description

Retrieves the name of the current map.

Example Usage

local map_name = core.get_map_name()

core.log("Current map: " .. map_name)

core.get_cursor_position​
Syntax
core.get_cursor_position() -> vec2

Returns
vec2: The current cursor position.
Description

Retrieves the current cursor position on the screen.

Example Usage

local cursor_pos = core.get_cursor_position()

core.log(string.format("Cursor position: (%.2f, %.2f)", cursor_pos.x, cursor_pos.y))

core.get_instance_id()​
Syntax
core.get_instance_id() -> integer

Returns
integer: the ID of the current instance.
core.get_instance_name()​
Syntax
core.get_instance_name() -> string

Returns
string: the name of the current instance.
core.get_difficulty_id()​
Syntax
core.get_difficulty_id() -> integer

Returns
integer: the ID of the current instance difficulty.
core.get_difficulty_name()​
Syntax
core.get_difficulty_name() -> string

Returns
string: the name of the current instance's difficulty.
get_keystone_level()​

Returns the Mythic+ keystone level of the current dungeon, if applicable.

Returns: integer — The level of the Mythic+ keystone.

get_height_for_position(position: vec3)​

Returns the height at the given position in the game world.

Parameters:
position (vec3) — The 3D coordinates for which to get the height.

Returns: number — The height value at the given position.

Inventory 🗺️​
NOTE

See Inventory Helper for more info.

core.inventory.get_items_in_bag(id: integer) -> table<item_slot_info>​

Retrieves all items in the bag with the specified ID.

Syntax
core.inventory.get_items_in_bag(id) -> table<item_slot_info>

Returns
table<item_slot_info>: A table containing the item data.
NOTE

The item slot info contains 2 members:

.slot_id -> the id of the slot
.object -> the item itself (game_object)
Description

This function returns all the items in the bag with the ID that you pass as parameter. This is a low-level function, and we recommend, like always, to use our LUA libraries that we crafted so the development is easier for everyone. For mor info, check out the Inventory Helper library.

NOTE
-2 for the keyring
-4 for the tokens bag
0 = backpack, 1 to 4 for the bags on the character

While bank is opened:

-1 for the bank content
5 to 11 for bank bags (numbered left to right, was 5-10 prior to tbc expansion, 2.0 game version)

Check https://wowwiki-archive.fandom.com/wiki/BagId for more info.
Additional Notes 📝​
Performance Monitoring: Utilize the time and CPU functions to monitor and optimize your script's performance.
Event Handling: Register appropriate callbacks to handle events effectively within your script.
Logging Best Practices: Consistently log important information for easier debugging and maintenance.
Core Game UI - New Functions 🆕​
get_loot_item_count()​

Retrieves the number of items currently available in the loot window.

Returns: integer — The number of lootable items.

get_loot_item_id(index: integer)​

Retrieves the item ID of a lootable item at the specified index.

Parameters:
index (integer) — The index of the lootable item.

Returns: integer — The ID of the lootable item.

get_loot_is_gold(index: integer)​

Checks if the lootable item at the specified index is gold.

Parameters:
index (integer) — The index of the lootable item.

Returns: boolean — true if the item is gold; otherwise, false.

get_loot_item_name(index: integer)​

Retrieves the name of the lootable item at the specified index.

Parameters:
index (integer) — The index of the lootable item.

Returns: string — The name of the lootable item.

get_resurrect_corpse_delay()​

Retrieves the remaining time before the player can resurrect at their corpse.

Returns: number — The delay in seconds before resurrection is possible.

get_corpse_position()​

Retrieves the position of the player’s corpse as a 3D vector.

Returns: vec3 — The position of the corpse.