# Project Sylvanas Documentation

Gecrawlt am: 2025-12-19T17:39:38.013Z
Anzahl Seiten: 33

---

## https://docs.project-sylvanas.net/dev

Getting Started
Overview​

In this document, you will learn how to setup your environment and begin developing scripts for Sylvanas. We will try to cover as much information as possible in this short guide, but if you still have any questions you can contact us and we will gladly help you as soon as possible. If you don't have your loader/user setup yet, check Getting Started - User Guide before continuing with this guide.

Welcome Letter
First of all, thanks for your interest in developing scripts for Sylvanas. Since we are internal, we have our own custom-made Lua API that is nothing like the WoW one, which can make it seem like working with us is more difficult than what you might be used to; this is why we will always appreciate your hard work and dedication, as we are aware that not everybody would be able to tackle such challenges. As a fellow developer, you will earn our respect; active developers will enjoy a series of unique benefits. We still don't know the specifics, but one thing is for sure: you will have a free subscription as long as you are active. As for the other benefits that we are planning, we can't discuss them all with you yet, but more information will be shared as soon as possible. Among these benefits, we are thinking of monetization support for some Lua Scripts.



For full details about our developer roles, benefits, and monetization system, please visit the 👉 Developer Program Overview page.

Without further ado, let's begin programming!

Getting Started​
NOTE

You can skip this part if you already have Visual Studio Code installed and the sumneko Lua extension installed and enabled.

First of all, we have to setup our IDE. You can program even with a notepad if you want, but we recommend you to follow this small tutorial, since we provide with intellisense mechanisms that are only available on Visual Studio Code with the sumneko Lua extension. (You can ignore the first 2 steps if you already have Visual Studio Code installed)


Navigate to Visual Studio Code - Official Page
Click on the "Download for Windows" button and install the program.
Open Visual Studio Code
Navigate to the extensions section (on the left bar, the second icon starting from the botton). Then, search "LUA" and install the first plugin that appears. (Check that the developer is "sumneko", just in case).

Now, our IDE is good to go. The next step is to prepare our scripting development environment.

Go to the folder where you have placed your loader
Locate the "Scripts" folder and place yourself inside of it.
There, you will see many encripted scripts that were donwloaded after you logged into your account using the loader.
The files that are required for you to develop your scripts are "Common" and the ones starting with "Core". Developer tools and prediction playground are nice to have too. (Although we recommend to not modify the initial Scripts folder)
Create a folder inside the scripts folder. For example, "script_plugin_test"
Inside "script_plugin_test", we will create 2 files: header.lua and main.lua

Now, everything is almost ready to actually begin coding.

NOTE

You can also just download the example plugin below. (Although downloading it from the Github repo is recommended, so you can be sure that you are downloading the latest version.)

Checking the API File (Optional)​

The Lua plugin that we previously added to Visual Studio Code no longer requires you to manually download the API files. The _api folder is now automatically updated and managed by us whenever you run the loader. This ensures that you always have the latest version of the API in your script folder without any extra effort.

However, if you’re curious to explore or manually check the API files, you can still access them here:

NOTE

You can browse the latest _api folder on our open GitHub repository.

TIP

Alternatively, you can download the mage fire example, which already includes a sample setup.

After your setup is successful, you should see Intellisense working:

Now, we should be good to actually start programming :)

Header File​
WARNING

The name of this file MUST be "header.lua". Other names are not accepted and the core won't recognize your script if you attempt to modify its file name.

This is the file that will essentially tell the core if your script will be loaded or not. This makes sense because you might develop a Fire Mage script, for example. The script shouldn't be loaded under any circumstance if the user is not playing a Fire Mage in this case. This file is also used to uniquely identify your plugin.

You will see how to use it more clearly with an example (the following example is the same code that we use in the Placeholder Plugin):

local plugin = {}



plugin["name"] = "Placeholder Script"

plugin["version"] = "0.0.0"

plugin["author"] = "Placeholder Author"

plugin["load"] = true



-- check if local player exists before loading the script (user is on loading screen / not ingame)

local local_player = core.object_manager.get_local_player()

if not local_player then

    plugin["load"] = false

    return plugin

end



---@type enums

local enums = require("common/enums")

local player_class = local_player:get_class()



-- change this line with the class of your script

local is_valid_class = player_class == enums.class_id.DRUID



if not is_valid_class then

    plugin["load"] = false

    return plugin

end



local player_spec_id = core.spell_book.get_specialization_id()

-- change this line with the spec id of your script

-- the spec id is in the same order as it appears in the talents WoW UI

local is_valid_spec_id = player_spec_id == 1



if not is_valid_spec_id then

    plugin["load"] = false

    return plugin

end



return plugin




As you can see, the core is expecting a table to be returned, with the following members filled:

"name"
"version"
"author"
"load"

All the elements of the table are self-explanatory. Just note that when the table["load"] is false, the plugin won't be loaded.
Main File​
WARNING

The name of this file MUST be "main.lua". Other names are not accepted and the core won't recognize your script if you attempt to modify its file name.

This is the file where all your logics must be placed, as this is the only file that the core will read, other than the header one. You can obviously have multiple files, just note that you will eventually have to import the code that you want to be run to the main file.



Since main.lua can become quite lengthy, we’ll start with a brief example here. For more detailed scripts, see the examples below.

-- Note:

-- This is a very basic example.

-- For a more comprehensive example, visit our GitHub or download the Fire Mage example script provided below.



local menu_elements =

{

    main_tree = core.menu.tree_node(),

    keybinds_tree_node = core.menu.tree_node(),



    -- you can add more menu elements in future here

}



-- and now render them:

local function my_menu_render()



    menu_elements.main_tree:render("Simple Example", function()

        -- this is the checkbohx that will appear upon opening the previous tree node

        menu_elements.enable_script_check:render("Enable Script")



        -- you can render more menu elements in future here...

    end)

end



core.log("Hello World! (This should be printed just once on console)")



local function my_on_update()



    local is_plugin_enabled = menu_elements.enable_script_check:get_state()

    if is_plugin_enabled then



        -- When menu element enable_script_check

        -- Is true, this will spam console in white

        core.log("Plugin Test is ENABLED!")

    else



        -- When menu element enable_script_check

        -- Is false, this will spam console in yellow

        core.log_warning("[DISABLED] Test Plugin")

    end

end



core.register_on_update_callback(my_on_update)

core.register_on_render_menu_callback(my_menu_render)

The way Sylvanas uses the main/header files​

The way we handle the Lua is simple. We just read the header file and the main file once (on injection / Lua reload). Then, we store all the information that is present in both files and then we internally run the code that we just stored. All the code that are not callbacks, or inside a callback, is just read and executed once.

NOTE

For more information about callbacks, check the more in-depth explanation of the available callbacks. You should know the way they work and what each one of them does before begining to develop scripts.

⚡ Next Steps​
Legacy vs. IZI SDK​

Over the past year, we’ve learned a lot from our community of developers, the struggles, the questions, and the creative solutions you’ve come up with. To celebrate our first anniversary, we’re introducing something special: IZI SDK.

🧩 What is IZI SDK?​

IZI SDK is a brand-new developer wrapper built on top of our Legacy API. It doesn’t introduce new features or performance improvements, instead, it focuses entirely on making development simpler, faster, and more intuitive.

Think of it as the same powerful engine, but with a friendlier dashboard. It lets you focus more on creativity and design, rather than technical hurdles or low-level setup.

Key ideas behind IZI SDK:

Built on top of the Legacy API (fully retrocompatible)
Designed for ease of use, not maximum performance
Great for beginners or anyone who prefers a smoother “vibe coding” experience
Perfect stepping stone before diving into Legacy API for full control and customization

While there’s a small trade-off in flexibility and performance, we believe it’s a worthwhile price for the simplicity it offers, especially when starting out.

🧙 Choose Your Path​

Starting from this point, you can choose your preferred learning path:

🔹 Option 1: Continue with Legacy API​

If you want to learn how everything works under the hood and get full control over performance, customization, and flow, keep following the Legacy API documentation.

Example: Fire Mage (Legacy)
Next Page: Developer Program → Overview
🔹 Option 2: Try the New IZI SDK (Recommended)​

If you’re new to the ecosystem or prefer to start coding right away with less setup and cleaner syntax, check out the new IZI SDK.

Example: Fire Mage (IZI)
Visit: IZI SDK Documentation
✨ In Short​

Both SDKs are great, it’s all about where you want to start. We recommend beginning with IZI SDK for its simplicity and comfort, then progressively moving toward the Legacy API as you gain experience and want more control.

💡 Tip: IZI SDK is completely compatible with the Legacy API. Everything you learn here will still apply if you decide to switch later.

Examples​

We have many examples available on the Examples page to demonstrate how to use both the IZI SDK and the Legacy API. These examples include full source code and code breakdowns you can reference in order to learn more about the ecosystem.

---

## https://docs.project-sylvanas.net/dev/developer-program

Developer Program
1. Getting Started​

Anyone can begin developing for our platform right away.
All the necessary documentation and tools are publicly available, so you can freely experiment, create, and test your scripts without any special roles or permissions.

If you later decide you’d like to publish your scripts or earn money from them, you’ll need to apply for the Trial Developer role.

2. Trial Developer​

Developers who already have a portfolio or reputation (for example, in WoW or a similar ecosystem) can be granted Trial Developer status upfront for a grace period of up to 30 days.

To become a Trial Developer, simply show us your work — either new scripts you’ve made for our platform or examples from your past experience.
Once reviewed and approved, you’ll receive the role and can start publishing your projects immediately.

The Trial Developer role is the first official step toward joining our development team.
It grants permission to publish your scripts and use PS for free during a limited grace period.

3. Developer​

After being an active Trial Developer for a while, you can advance to Developer status.
This is a more permanent position that provides unlimited PS time and reflects a deeper level of trust and commitment.

We aim to make sure this role is earned through consistent effort and meaningful contributions, not just by being around briefly.
This stage also acts as the gateway to the next level of recognition and benefits.

4. Senior / Veteran Developer​

The Senior or Veteran Developer role is reserved for long-term, highly active developers who have consistently delivered quality and innovation.
This role comes with improved revenue splits and extra perks, including free unlimited access for Private PS.

5. Revenue Split and Platform Services​

Our standard revenue split starts at 70/30 (Developer/Platform), with the potential to increase to 80/20 or even 90/10.
This split reflects the range of services we provide, allowing developers to focus entirely on creating their best work while we handle the rest.

We take care of:

Authentication systems
Encryption and security
Obfuscation
Distribution and marketing
Transaction management and chargeback protection

Your only focus should be on building and refining your creations.

6. Why the 30% Base Fee Exists​

The 30% base fee isn’t just a cut, it’s what funds everything we provide to keep your work secure, visible, and profitable.

Included in this fee:

Strong encryption and code protection
Automatic changelogs and exposure through updates
Guaranteed payments (even if chargebacks occur)
Access to the Developer Panel, a powerful and easy-to-use dashboard for managing scripts, updates, and earnings

We handle all the infrastructure, risk, and backend complexity so you can focus purely on your development.
For long-term developers who remain PS exclusive, this fee can be reduced over time.

7. Becoming a Developer​

If you’d like to become a developer or have questions about the process, you can DM Silvi directly.

If you already have a portfolio or a proven background in development, we’ll gladly review it and may grant you Trial Developer access immediately for a grace period of up to 30 days.

---

## https://docs.project-sylvanas.net/dev/api/core

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

---

## https://docs.project-sylvanas.net/dev/api/input

Input Functions and Spell Queue
Overview 📃​

In this module we introduce one of the most (if not the most) important features for scripting: a way to manage input from code. For now, this only includes spell casting. However, stay tuned to the changelogs, since other input methods like movement are planned to be supported in the near future.

The Way Raw Input Functions Work

Similar to what we previously discussed in the buffs page, the raw input functions that the game provides to us have some disadvantages. In this case, they are not FPS-related, but rather usability and safety related. These functions basically send a paquet to the game's server that mimics a legit spell cast or movement. Therefore, spamming raw inputs from code may be dangerous since you might be sending many more requests per seconds than any human would be able to send. So far, this is not a problem for us, but it's something to take into account for the future, as Blizzard anticheat evolves.

The real problem is usability 💥:
1 - Compatibility between plugins: If your scripts spam input requests, you will make everything else useless. For example, other modules like "Core Interrupt" might want to cast a spell to interrupt an important enemy cast. This usually has more priority than the normal damage rotation, but since you are flooding the server with your requests, the interruptor spell cast request won't have a chance to be sent.
2 - User Experience: If your script spam input requests you make the user unable to cast their own spells manually. As you could imagine, there might me certain situations in which the users have to cast certain spells on their own, so blocking this could be very frustrating them. To fix this, we handle everything in our LUA Spell Queue Module, which will be explained in detail below.

WARNING

You can still use raw input functions, but at your own risk. We advise you to read thoroughly the previous explanation and check if you really really need to use the raw functions. If you have any question, contact us and we will guide you through without any problem - Better safe than sorry. ❤️

NOTE

For some items that don't have global cooldown, the raw "Use Item" functions are perfectly fine, just make sure to add checks before the cast so you don't spam when the item isn't ready.

Raw Input Functions 📃​
Cast Target Spell 💣​

core.input.cast_target_spell(spell_id: integer, target: game_object) -> boolean

Cast a spell directly at a target.
Parameters:
spell_id: The ID of your chosen spell
target: The game_object that you want to cast the spell to
Returns: true if the spell was cast, false if it fizzled
NOTE

This function JUST sends a cast request to the server. It doesn't check if the enemy is close enough, if you are facing it, if the spell is ready, etc. Therefore, you must apply all these checks before casting. To do so, we created a LUA Spell Helper module that will make the job very easy. Check spell book.

We advise you to check the Spell Book module before jumping into input code. This is the proper way you should be casting spells:

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")



---@type plugin_helper

local plugin_helper = require("common/utility/plugin_helper")



local last_cast_time = 0.0

core.register_on_update_callback(function()

    -- if we remove this check, you will see in the console that more than 1 cast request is issued.

    -- To avoid this and only send one (this is good practice behaviour), we add a minimum delay of 0.25 seconds

    -- for this function to be ran again.

    local current_time = core.game_time()

    if current_time - last_cast_time < 0.50 then

        return false

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- since this is just a test, we will just get the hud target

    local hud_target = local_player:get_target()

    -- only cast the fireball when there is a target selected

    if not hud_target then

        return

    end



    -- avoid spamming cast request while already casting

    -- NOTE: in your scripts, you might want to do the same for channels.



    -- approach 1: take into account network latency



    -- local network = plugin_helper:get_latency()

    -- local cast_end_time = local_player:get_active_spell_cast_end_time()

    -- local cast_delta = math.max(cast_end_time - current_time, 0.0)

    -- if cast_delta > (network * 1000) then

    --     return

    -- end



    -- approach 2: more simple, works well in most cases.

    local cast_end_time = local_player:get_active_spell_cast_end_time()

    if current_time <= cast_end_time then

        return

    end



    local fireball_id = 133



    -- check first if the spell is castable, so we avoid sending useless packets (the script will be stuck permanently trying to cast a spell that can't be casted)

    local can_cast_fireball = spell_helper:is_spell_castable(fireball_id, local_player, hud_target, false, false)

    if not can_cast_fireball then

        return

    end



    local spell_cast = core.input.cast_target_spell(fireball_id, hud_target)

    if spell_cast then

        core.log("Fireball Cast!")

        last_cast_time = current_time

    end

end)


This example might be an overkill, specially if you are a beginner and are learning. Feel free to play with the code and go step by step. However, if you want to produce good quality products, consider adding at least all the steps specified in the previous example to your casts.

Cast Position Spell 💣​

core.input.cast_position_spell(spell_id: integer, position: vec3) -> boolean

Cast a spell at a specific location in the world.
Parameters:
spell_id: Your spell's ID
position: The XYZ coordinates for your spell. See vec3
Returns: true if cast successfully, false if not
NOTE

This function is only used for spells that don't require a target game_object, but instead require a target position. This is usually the case for some AOE spells like Blizzard or Flamestrike.

Let's cast a Flamestrike:

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")



---@type plugin_helper

local plugin_helper = require("common/utility/plugin_helper")



local last_cast_time = 0.0

core.register_on_update_callback(function()

    -- if we remove this check, you will see in the console that more than 1 cast request is issued.

    -- To avoid this and only send one (this is good practice behaviour), we add a minimum delay of 0.25 seconds

    -- for this function to be ran again.

    local current_time = core.game_time()

    if current_time - last_cast_time < 0.50 then

        return false

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- since this is just a test, we will just get the hud target

    local hud_target = local_player:get_target()

    -- only cast the fireball when there is a target selected

    if not hud_target then

        return

    end



    -- avoid spamming cast request while already casting

    -- NOTE: in your scripts, you might want to do the same for channels.



    -- approach 1: take into account network latency



    -- local network = plugin_helper:get_latency()

    -- local cast_end_time = local_player:get_active_spell_cast_end_time()

    -- local cast_delta = math.max(cast_end_time - current_time, 0.0)

    -- if cast_delta > (network * 1000) then

    --     return

    -- end



    -- approach 2: more simple, works well in most cases.

    local cast_end_time = local_player:get_active_spell_cast_end_time()

    if current_time <= cast_end_time then

        return

    end



    local flamestrike_id = 2120



    -- check first if the spell is castable, so we avoid sending useless packets (the script will be stuck permanently trying to cast a spell that can't be casted)

    local can_cast_fireball = spell_helper:is_spell_castable(flamestrike_id, local_player, hud_target, false, false)

    if not can_cast_fireball then

        return

    end



    local position_to_cast = hud_target:get_position()

    local spell_cast = core.input.cast_position_spell(flamestrike_id, position_to_cast)

    if spell_cast then

        core.log("Flamestrike Cast On Target Position!")

        last_cast_time = current_time

    end

end)

TIP

As you can see, in the previous example we are casting the spell to the target's position, without any further checks. For AOE spells, you would ideally want to cast on the position that would hit the most enemies, which is usually not the same as your main target's position. To do this, you should use some sort of algorithm to determine which is the actual best point to cast, according to your spell's characteristics. To do this, we have developed the "Spell Prediction" module. See Spell Prediction Module

Use Item 🎭​

We have three item usage functions, each with its own purpose:


1- Item Self-Cast
core.input.use_item(item_id: integer) -> boolean

This function is used for items that don't require a target or a target position.

2- Item Targeted-Cast
core.input.use_item_target(item_id: integer, target: game_object) -> boolean

This function is used for items that require a target or a target position.

3- Item Position-Cast
core.input.use_item_position(item_id: integer, position: vec3) -> boolean

Use an item at a specific location. (Note: This feature is still in development)
TIP

Most items don't have a global cooldown, so these raw functions are usually fine, as we discussed earlier. However, for items that apply GCD, consider using the spell_queue.

The code for casting items is pretty similar to the code for casting spells. You just have to be careful with the way you check if the item is ready, since it's different from checking if a spell is ready. Below, a simple example on how to cast a health potion:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



local last_cast_time = 0.0

core.register_on_update_callback(function()

    -- if we remove this check, you will see in the console that more than 1 cast request is issued.

    -- To avoid this and only send one (this is good practice behaviour), we add a minimum delay of 0.25 seconds

    -- for this function to be ran again.

    local current_time = core.game_time()

    if current_time - last_cast_time < 5.0 then

        return false

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    local cast_end_time = local_player:get_active_spell_cast_end_time()

    if current_time <= cast_end_time then

        return

    end



    -- the potion for this example is the "Greater Healing Potion"

    local potion_id = 1710

    local item_cooldown = local_player:get_item_cooldown(potion_id)

    local can_cast_potion = item_cooldown <= 0.0

    if not can_cast_potion then

        return false

    end



    -- we add this check so the potion is not attempted to be cast while full HP, since the game won't allow it.

    if unit_helper:get_health_percentage(local_player) >= 1.0 then

        return false

    end



    local spell_cast = core.input.use_item(potion_id)

    if spell_cast then

        core.log("Potion cast!")

        last_cast_time = current_time

    end

end)

Set Target 🎯​

core.input.set_target(unit: game_object) -> boolean

Set your current target.
Returns: true if targeting was successful, false if not

Example:

local local_player = core.object_manager.get_local_player()

if local_player then

    local player_position = local_player:get_position()

    local nearby_enemies = unit_helper:get_enemy_list_around(player_position, 30)



    for _, unit in ipairs(nearby_enemies) do

        local success = core.input.set_target(unit)

        if success then

            core.log("New target acquired! 🎯")

            break

        else

            core.log("Targeting failed. They're quick! 💨")

        end

    end

end

Set and Get Focus 🔍​
core.input.set_focus(unit: game_object) -> boolean: Set your focus target
core.input.get_focus() -> game_object | nil: Retrieve your current focus

Checking your focus:

local current_focus = core.input.get_focus()

if current_focus then

    core.log("Current focus: " .. current_focus:get_name() .. " 🔍")

else

    core.log("No focus set currently")

end

Spell Queue Module: Advanced Spell Management 🧠​

As discussed earlier, spell_queue module offers sophisticated spell management with priority queuing. It's the go-to tool for complex spell rotations and efficient casting, and what you should be using in most cases.


The Way The Spell Queue Module Works
Basically, this module just implements a priority queue for spell casts. When you send a spell cast request, it's added into the queue with a priority value that's passed by parameter. The queue is sorted every frame according to the priority values of the elements inside the said data structure. This way, we can make sure that the most important spells are casted before the less important ones, and we also secure compatibility between plugins, as any plugin can send a cast request at any given time.

Importing the Module​
---@type spell_queue

local spell_queue = require("common/modules/spell_queue")

WARNING

Remember to use the colon (:) when calling spell_queue methods!

Queue Spell with Target 🎯​

spell_queue:queue_spell_target(spell_id: number, target: game_object, priority: number, message?: string)

Queue a targeted spell with priority.
priority: Higher numbers = higher priority (1 is default, 9 is highest)
message: Optional logging message

Queueing a Fireball:

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")



---@type plugin_helper

local plugin_helper = require("common/utility/plugin_helper")



---@type spell_queue

local spell_queue = require("common/modules/spell_queue")



local last_cast_time = 0.0

core.register_on_update_callback(function()

    -- if we remove this check, you will see in the console that more than 1 cast request is issued.

    -- To avoid this and only send one (this is good practice behaviour), we add a minimum delay of 0.25 seconds

    -- for this function to be ran again.

    local current_time = core.game_time()

    if current_time - last_cast_time < 0.50 then

        return false

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- since this is just a test, we will just get the hud target

    local hud_target = local_player:get_target()

    -- only cast the fireball when there is a target selected

    if not hud_target then

        return

    end



    -- avoid spamming cast request while already casting

    -- NOTE: in your scripts, you might want to do the same for channels.



    -- approach 1: take into account network latency



    -- local network = plugin_helper:get_latency()

    -- local cast_end_time = local_player:get_active_spell_cast_end_time()

    -- local cast_delta = math.max(cast_end_time - current_time, 0.0)

    -- if cast_delta > (network * 1000) then

    --     return

    -- end



    -- approach 2: more simple, works well in most cases.

    local cast_end_time = local_player:get_active_spell_cast_end_time()

    if current_time <= cast_end_time then

        return

    end



    local fireball_id = 133



    -- check first if the spell is castable, so we avoid sending useless packets (the script will be stuck permanently trying to cast a spell that can't be casted)

    local can_cast_fireball = spell_helper:is_spell_castable(fireball_id, local_player, hud_target, false, false)

    if not can_cast_fireball then

        return

    end



    spell_queue:queue_spell_target(fireball_id, hud_target, 1, "Trying to cast fireball!")

    last_cast_time = current_time

end)


As you can see, the code is pretty much the same as the code that we would use for raw functions, the only thing that changes is the way we are attempting to cast the spell.

Queue Fast Spell with Target 🎯​

spell_queue:queue_spell_target_fast(spell_id: number, target: game_object, priority: number, message?: string)

The code would be exactly the same as the previous example, you just need to replace the queue spell function call.

Queue Spell with Position 🎯​

spell_queue:queue_spell_position(spell_id: number, position: vec3, priority: number, message?: string)

Queue a position-based spell.

As you can imagine, the code to cast Flamestrike using spell queue is pretty much the same as the code we used to cast Flamestrike with raw spells, the only thing that changes is the way we are issuing the actual cast. So, maybe it's more interesting to use the spell prediction for a smart Blizzard cast for this example:

local local_player = core.object_manager.get_local_player()

if local_player then

    local hud_target = local_player:get_target()

    if hud_target then

        local blizzard_id = 10

        local player_position = local_player:get_position()

        local prediction_spell_data = spell_prediction:new_spell_data(

            blizzard_id,                                    -- spell_id

            30,                                             -- range

            6,                                              -- radius

            0.2,                                            -- cast_time

            0.0,                                            -- projectile_speed

            spell_prediction.prediction_type.MOST_HITS,     -- prediction_type

            spell_prediction.geometry_type.CIRCLE,          -- geometry_type

            player_position                                 -- source_position

        )



        local prediction_result = spell_prediction:get_cast_position(hud_target, prediction_spell_data)

        if prediction_result and prediction_result.amount_of_hits > 0 then

            spell_queue:queue_spell_position(blizzard_id, prediction_result.cast_position, 1, "Queueing Blizzard at optimal position")

        end

    end

end


This code:

Sets up a Blizzard spell with prediction data
Uses MOST_HITS prediction type to maximize the spell's impact
Queues the Blizzard at the optimal position if targets are predicted to be hit

NOTE

As you can see, we call prediction_type.MOST_HITS to fire Death and Decay on the Priest. Instead of casting on the center, it strategically places the spell slightly to the left to hit extra dummies aswell.

TIP

Test with the prediction_type.ACCURACY values for pinpointing situations where the cast should be avoided

Queue Fast Spell with Position 🎯​

spell_queue:queue_spell_position_fast(spell_id: number, position: vec3, priority: number, message?: string)

Queue a position-based spell that ignores the global cooldown.

The code would be exactly the same as the previous example, you just need to replace the queue spell function call

Best Practices 🧙‍♂️💡​
1- Embrace the Spell Queue

2- Remember the priority scale (1-9). Use it to create sophisticated casting logic.


WARNING

Be cautious with priority levels! While 1 is the default, higher priorities should be applied only when absolutely necessary.

1 is the default priority, intended for the majority of spells in the standard rotation. Developers should strive to keep spells at priority 1 unless a clear, specific reason justifies using a higher priority. This preserves rotation efficiency and prevents disruption.

Higher priorities are intended for spells that require urgent action outside the rotation. For example, interrupts use priority 7 to ensure they execute immediately when conditions demand it, as timing is crucial for effective interruption. Core utility spells, such as racials, dispels, or spell reflections, are typically set between 4 to 6. They preempt the rotation without overshadowing interrupts, allowing critical utilities to occur in time-sensitive situations.

Finally, priority 9 is exclusively reserved for manual player actions, ensuring that the player’s chosen spell overrides any automated rotation or interrupt, with no delay.

In short, unless there is a compelling plan, stick with priority 1 for your spells. Use 2 only if you have a strong plan.

3- Fast Track Important Spells

Use _fast versions for critical, non-GCD spells.

4- Leave Breadcrumbs

Use the message parameter in spell_queue for easier debugging.

5- Learn to Use The Prediction Module

The spell_prediction module is powerful and easy to use library to evolve your logics.

Remember, mastering these tools takes practice. Experiment with different combinations and priorities to find what works best for your scripting needs.

More Raw Input Functions​
Movement Controls 🎮​
move_up_start()​

Starts moving the player upwards (used in flying scenarios).

Returns: boolean — true if the movement command was issued successfully.

move_up_stop()​

Stops the upward movement.

Returns: boolean — true if the movement command was issued successfully.

move_down_start()​

Starts moving the player downwards (used in flying or swimming scenarios).

Returns: boolean — true if the movement command was issued successfully.

move_down_stop()​

Stops the downward movement.

Returns: boolean — true if the movement command was issued successfully.

jump()​

Makes the player jump.

Returns: boolean — true if the jump command was issued successfully.

Mounting and Dismounting 🐎​
mount()​

Mounts the player's active mount.

Returns: boolean — true if the mount command was issued successfully.

dismount()​

Dismounts the player from their mount.

Returns: boolean — true if the dismount command was issued successfully.

Resurrection and Spirit Release 🎭​
release_spirit()​

Releases the player's spirit after death.

Returns: boolean — true if the spirit release command was issued successfully.

resurrect_corpse()​

Resurrects the player’s corpse.

Returns: boolean — true if the resurrection command was issued successfully.

Expanded Movement Controls 🎮​
move_forward_start()​

Starts moving the player forward.

move_forward_stop()​

Stops forward movement.

move_backward_start()​

Starts moving the player backward.

move_backward_stop()​

Stops backward movement.

turn_right_start()​

Starts turning the player to the right.

turn_right_stop()​

Stops turning to the right.

turn_left_start()​

Starts turning the player to the left.

turn_left_stop()​

Stops turning to the left.

Pet Control Functions 🐾​
pet_move(position: vec3)​

Commands the pet to move to the specified position.

pet_attack(target: game_object)​

Commands the pet to attack the target.

set_pet_wait()​

Sets the pet to wait at its current position.

set_pet_follow()​

Commands the pet to follow the player.

set_pet_assist()​

Sets the pet to assist the player.

set_pet_passive()​

Sets the pet to passive mode.

set_pet_defensive()​

Sets the pet to defensive mode.

set_pet_aggressive()​

Sets the pet to aggressive mode.

pet_move_position(position: vec3)​

Moves the pet to a specified world position.

pet_cast_target_spell(spell_id: integer, target: game_object)​

Commands the pet to cast a spell on a target.

pet_cast_position_spell(spell_id: integer, position: vec3)​

Commands the pet to cast a spell at a specific position.

Loot and Combat Management 🧹​
loot_object(unit: game_object)​

Loots the specified object.

stop_attack()​

Stops all ongoing player attacks.

Returns: boolean — true if the stop command was issued successfully.

---

## https://docs.project-sylvanas.net/dev/api/color

Lua Color Module Documentation
Overview​

The Lua Color Module provides functions for handling colors in Lua scripts. These functions allow for color creation, manipulation, blending, and predefined color creation.

Importing The Module​
WARNING

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the require function and store it in a local variable.

Here is an example of how to do it:

-- recomended "color" name for consistency

---@type color

local color = require("common/color");

Functions​
Color New​

color.new

Creates a new color object with the specified RGBA components.
local example_white_color = color.new(255, 255, 255, 255)

Color Clone​

color:clone

Clones the current color object.
local example_red_transparent_color = color.new(255, 0, 0, 150)

local cloned_color = example_red_transparent_color :clone()

Color Blend​

color:blend

Blends the current color with another color using the specified alpha value.
local other_color = color.new(255, 0, 0, 255)

local color_instance = color.new(0, 0, 255, 255)

local blended_color = color_instance:blend(other_color, 150)

Color Set​

color:set

Sets the RGBA components of the color.
local color_instance = color.new(255, 255, 255, 255)

-- now color_instance is white full alpha



color_instance:set(255, 0, 0, 150)

-- now color instance is red half transparent

Color Get​

color:get

Retrieves the RGBA components of the color.
local test_color = color_instance:get()

Color Clamp​

color:clamp

Clamps the RGBA components of the color to the range [0, 255].
Predefined Color Functions​

The module also provides predefined color functions for commonly used colors:

color.red
color.green
color.blue
color.white
color.black
color.yellow
color.pink
color.purple
color.gray
color.brown
color.gold
color.silver
color.orange
color.cyan
color.red_pale
color.green_pale
color.blue_pale
color.cyan_pale
color.gray_pale
Code Examples​
-- Example usage of creating and blending colors

local color1 = color.new(255, 0, 0, 255) -- Red color

local color2 = color.new(0, 255, 0, 255) -- Green color



-- Blend colors with alpha of 0.5

local blended_color = color1:blend(color2, 0.5)



core.log(blended_color:get()) -- Output: 127, 127, 0, 255 (Yellow color)


---

## https://docs.project-sylvanas.net/dev/api/geometry

Geometry
Overview​

The geometry module provides a set of classes to create and interact with geometric shapes such as circles, rectangles, and cones. These classes offer various methods to manipulate the shapes, check points within them, retrieve units inside them, and visualize them by drawing.

TIP

These classes are helpful for area-of-effect calculations, targeting systems, and visual debugging.

WARNING

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the require function and store it in a local variable.

Here is an example of how to do it:

-- Recommended "circle" name for consistency

local circle = require("common/geometry/circle")



local cursor_position = core.get_cursor_position()

local my_circle = circle:create(cursor_position, 5.0)

Classes​
Circle​

The circle class represents a circle with a center point and a radius.

Properties​
center: vec3 — The center position of the circle.
radius: number — The radius of the circle.
Methods​
create(center, radius)​

Creates a circle given a center and radius.

Parameters:
center (vec3) — The center position of the circle.
radius (number) — The radius of the circle.

Returns: circle — A new circle instance.

is_inside(point, hitbox)​

Checks if a point is inside the circle.

Parameters:
point (vec3) — The point to check.
hitbox (number) — The hitbox radius to consider.

Returns: boolean — true if the point is inside; otherwise, false.

get_units_inside(units_list)​

Retrieves units within the circle.

Parameters:
units_list (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the circle's center.

Returns: table<game_object> — A table of units inside the circle.

get_allies_inside(units_list_override)​

Retrieves allies within the circle.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the circle's center.

Returns: table<game_object> — A table of allies inside the circle.

get_enemies_inside(units_list_override)​

Retrieves enemies within the circle.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the circle's center.

Returns: table<game_object> — A table of enemies inside the circle.

draw(custom_height)​

Draws the circle.

Parameters:
custom_height (number, optional) — Custom height to draw the circle.

Returns: nil

draw_with_counter(count)​

Draws the circle and the number of units hit.

Parameters:
count (number, optional) — Number of units hit. If not provided, calculates the number of units inside the circle.

Returns: nil

Rectangle​

The rectangle class represents a rectangle with four corners, a width, and a length.

Properties​
corner1: vec3 — The first corner of the rectangle.
corner2: vec3 — The second corner of the rectangle.
corner3: vec3 — The third corner of the rectangle.
corner4: vec3 — The fourth corner of the rectangle.
width: number — The width of the rectangle.
length: number — The length of the rectangle.
origin: vec3 — The origin position of the rectangle.
Methods​
create(origin, destination, width, length)​

Creates a rectangle given an origin, destination, width, and length.

Parameters:
origin (vec3) — The origin position.
destination (vec3) — The destination position.
width (number) — The width of the rectangle.
length (number, optional) — The length of the rectangle. If not provided, it is calculated from the origin and destination.

Returns: rectangle — A new rectangle instance.

create_direction(position, direction, width, length)​

Creates a rectangle given a position, direction, width, and length.

Parameters:
position (vec3) — The starting position.
direction (vec3) — The direction vector.
width (number) — The width of the rectangle.
length (number) — The length of the rectangle.

Returns: rectangle — A new rectangle instance.

is_inside(point, hitbox)​

Checks if a point is inside the rectangle.

Parameters:
point (vec3) — The point to check.
hitbox (number) — The hitbox radius to consider.

Returns: boolean — true if the point is inside; otherwise, false.

get_units_inside(units_list)​

Retrieves units within the rectangle.

Parameters:
units_list (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the rectangle's origin.

Returns: table<game_object> — A table of units inside the rectangle.

get_allies_inside(units_list_override)​

Retrieves allies within the rectangle.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the rectangle's origin.

Returns: table<game_object> — A table of allies inside the rectangle.

get_enemies_inside(units_list_override)​

Retrieves enemies within the rectangle.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the rectangle's origin.

Returns: table<game_object> — A table of enemies inside the rectangle.

draw(custom_height)​

Draws the rectangle.

Parameters:
custom_height (number, optional) — Custom height to draw the rectangle.

Returns: nil

draw_with_counter(count)​

Draws the rectangle and the number of units hit.

Parameters:
count (number, optional) — Number of units hit. If not provided, calculates the number of units inside the rectangle.

Returns: nil

Cone​

The cone class represents a cone with a center point, radius, angle, and direction.

Properties​
center: vec3 — The center position of the cone.
radius: number — The radius of the cone.
angle: number — The angle of the cone in degrees.
direction: vec3 — The direction vector of the cone.
Methods​
create(center, radius, angle, direction)​

Creates a cone given a center position, radius, angle, and direction.

Parameters:
center (vec3) — The center position of the cone.
radius (number) — The radius of the cone.
angle (number) — The angle of the cone in degrees.
direction (vec3) — The direction vector the cone is facing.

Returns: cone — A new cone instance.

is_inside(point_position, hitbox)​

Checks if a point is inside the cone.

Parameters:
point_position (vec3) — The position of the point to check.
hitbox (number) — The hitbox radius to consider.

Returns: boolean — true if the point is inside; otherwise, false.

get_units_inside(units_list)​

Retrieves units within the cone.

Parameters:
units_list (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the cone's center.

Returns: table<game_object> — A table of units inside the cone.

get_allies_inside(units_list_override)​

Retrieves allies within the cone.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the cone's center.

Returns: table<game_object> — A table of allies inside the cone.

get_enemies_inside(units_list_override)​

Retrieves enemies within the cone.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the cone's center.

Returns: table<game_object> — A table of enemies inside the cone.

draw(custom_height)​

Draws the cone.

Parameters:
custom_height (number, optional) — Custom height to draw the cone.

Returns: nil

draw_with_counter(count)​

Draws the cone and the number of units hit.

Parameters:
count (number, optional) — Number of units hit. If not provided, calculates the number of units inside the cone.

Returns: nil

Examples​
Creating and Using a Circle​
-- load the circle class

---@type circle

local circle = require("common/geometry/circle")



local function generate_and_draw_circle_with_hit_count()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end

    -- get the player's position

    local player_position = core.object_manager.get_local_player():get_position()



    -- create a circle with a radius of 10 units, for example

    local my_circle = circle:create(player_position, 10.0)



    -- get enemies inside the circle

    local enemies = my_circle:get_enemies_inside()



    -- draw the circle and the number of enemies inside

    my_circle:draw_with_counter(#enemies)

end



core.register_on_render_callback(function()

    generate_and_draw_circle_with_hit_count()

end)


This is what you should be seeing after running that code:

Creating and Using a Rectangle​
-- load the rectangle class

---@type rectangle

local rectangle = require("common/geometry/rectangle")



---@type vec3

local vec3 = require("common/geometry/vector_3")



local function generate_and_draw_rect_with_ally_hit_count()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- define origin and destination positions

    local origin = local_player:get_position()

    local destination = origin + vec3.new(20, 0, 0)



    -- create a rectangle of width 5 units

    local my_rectangle = rectangle:create(origin, destination, 5.0)



    -- get allies inside the rectangle

    local allies = my_rectangle:get_allies_inside()



    -- Draw the rectangle

    my_rectangle:draw_with_counter(#allies)

end



core.register_on_render_callback(function()

    generate_and_draw_rect_with_ally_hit_count()

end)


This is what you should be seeing after running that code:

Creating and Using a Cone​
-- load the cone class

---@type cone

local cone = require("common/geometry/cone")



-- load the vec3 class

---@type vec3

local vec3 = require("common/geometry/vector_3")



local function generate_and_draw_cone_with_unit_hit_count()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- get the player's position and facing direction

    local position = local_player:get_position()

    local origin = local_player:get_position()

    local destination = origin + vec3.new(20, 0, 0)



    -- create a cone with a radius of 10 yds and an angle of 45 degrees

    local my_cone = cone:create(position, destination, 10.0, 45)



    -- draw the cone

    my_cone:draw_with_counter()



    my_cone:draw()

end



core.register_on_render_callback(function()

    generate_and_draw_cone_with_unit_hit_count()

end)


This is what you should be seeing after running that code:

NOTE

The shaders for the cones are still under development. It will be added in the future, that's why they look worse than the other geometries. Stay tuned for the shaders update!

Notes​
The vec3 type represents a 3D vector with x, y, and z coordinates. See Vectors (vec3) for more details.
The game_object type refers to any entity within the game world, such as players, NPCs, or items. See Game Object - Functions for more details.

---

## https://docs.project-sylvanas.net/dev/api/buffs

Buffs
Overview​

The Lua Buff Class provides a way to represent buffs in Lua scripts. Buffs are temporary enhancements or negative effects (debuffs) applied to game characters (players and npcs). For example, a deffensive cooldown would be a buff and a poison applied to an enemy would be a debuff. This is very basic, but we aim to be beginner friendly and welcome everybody abroad 🌟

The Way Raw Buffs and Debuffs Work
In WoW, buffs and debuffs are essentially a (usually) large list for each game_object. As you can imagine, checking every frame every buff for every unit in the game is very expensive CPU-wise. So, if you were to use the raw buffs given by Blizzard to check every frame, for example, if you have one buff up that would make you deal more dmg, you would quickly realize how your FPS take a slight hit, since your PC has to also go through all other irrelevant buffs. This scalates with the number of units for which you are checking buffs or debuffs. So, let's say you are an affliction warlock and your script is checking how many units around you have Corruption; or maybe you are a resto druid and you are checking how many dots from you does everyone on your party have: in this case, your FPS will take a big hit. 💣💣

How To: Retrieve Buffs and Debuffs Information 📃​

To get the buffs and debuffs info from a unit, we have 2 choices:

1 - Raw 💣​

1 - Using Raw Buffs and Debuffs
For the reasons explained in the previous point, this method is not recommended in most cases. However, you are still allowed to use it (at your own risk).

Acessing to the game_object function get_buffs() we can get the table of buffs. For the debuffs, we can just use get_debuffs(). This function will return a table with the following elements:
.buff_name (string)
.buff_id (integer)
.count (integer)
.expire_time (number)
.duration (number)
.type (integer)
.caster (game_object)

Here is the code to print all (raw) buffs information for a given unit:


---@param target game_object

local function print_buffs_info(target)

    --- buff_name        - string

    --- buff_id          - integer

    --- count            - number

    --- expire_time      - number

    --- duration         - number

    --- type             - integer

    --- caster           - game_object

    local buffs = target:get_buffs()



    for k, buff in ipairs(buffs) do

        core.log("Buff name: " .. buff.buff_name)

        core.log("Buff id: " .. tostring(buff.buff_id))

        core.log("Buff Stacks: " .. tostring(buff.count))

        core.log("Buff Expire Time: " .. tostring(buff.expire_time))

        core.log("Buff Duration: " .. tostring(buff.duration))

        core.log("Buff Type: " .. tostring(buff.type))

        core.log("Buff Caster: " .. buff.caster:get_name())

        core.log("- - - - - - - - - - - - - - - - - - - - - - - - - - -")

    end

end

Here is the code to print all (raw) debuffs information for a given unit:


---@param target game_object

local function print_debuffs_info(target)

    --- buff_name        - string

    --- buff_id          - integer

    --- count            - number

    --- expire_time      - number

    --- duration         - number

    --- type             - integer

    --- caster           - game_object

    local debuffs = target:deget_buffs()



    for k, debuff in ipairs(buffs) do

        core.log("Buff name: " .. debuff.buff_name)

        core.log("Buff id: " .. tostring(debuff.buff_id))

        core.log("Buff Stacks: " .. tostring(debuff.count))

        core.log("Buff Expire Time: " .. tostring(debuff.expire_time))

        core.log("Buff Duration: " .. tostring(debuff.duration))

        core.log("Buff Type: " .. tostring(debuff.type))

        core.log("Buff Caster: " .. debuff.caster:get_name())

        core.log("- - - - - - - - - - - - - - - - - - - - - - - - - - -")

    end

end


This is what you will be seeing in the console after running the showcased code (in this case, the parameter was local_player)

2 - Buff Manager Module 🔥​

2 - Using Our Custom-Made Buffs Module
For the reasons already explained, we recommend using this module to check buffs information, since we have a special cache system that reduces FPS impact to almost zero. The usage is very simple, you just have to import 2 modules: the enums module (although this is optional), and the buff_manager module.
Then, we just have to use either the buff_manager:get_buff_data() function or the buff_manager:get_debuff_data() function, depending on if we want to check the information of a buff or a debuff.

So, to get a specific buff information, you could use this code:

---@type buff_manager

local buff_manager = require("common/modules/buff_manager")

---@type enums

local enums = require("common/enums")



---@param target game_object

local function print_buffs_info(target)

    local buff_info = buff_manager:get_buff_data(target, enums.buff_db.BARSKIN)



    core.log("Is Buff Active: " .. tostring(buff_info.is_active))

    core.log("Buff Remaining: " .. tostring(buff_info.remaining)) -- in MILISECONDS (ms)

    core.log("Buff Stacks: " .. tostring(buff_info.stacks))

    core.log("- - - - - - - - - - - - - - - - - - - - - - - - -")

end


And to get a specific debuff information, you could use this code:

---@type buff_manager

local buff_manager = require("common/modules/buff_manager")

---@type enums

local enums = require("common/enums")



---@param target game_object

local function print_buffs_info(target)

    local debuff_info = buff_manager:get_debuff_data(target, enums.buff_db.BARSKIN)



    core.log("Is Buff Active: " .. tostring(debuff_info.is_active))

    core.log("Buff Remaining: " .. tostring(debuff_info.remaining)) -- in MILISECONDS (ms)

    core.log("Buff Stacks: " .. tostring(debuff_info.stacks))

    core.log("- - - - - - - - - - - - - - - - - - - - - - - - -")

end

Parameters:
1- target (game_object) (the unit to check the buffs/debuffs)
2- buff_ids (table of integers) (this is a TABLE)
3- custom_cache_duration (number) (the unit to check the buffs/debuffs)


NOTE

The parameters are the same, for both get_debuff_data and get_buff_data functions.

Brief Explanation Of The Parameters
1- Target:
This is just the game_object that we want to analyze the buffs or debuffs of.
2- Buff IDs:
This is a table that contains the possible IDs of the same buff or debuff. For example, let's say you have the buff named "Shiny Day". There might be something that alters the ID of this buff, in most cases a spec change. However, the buff is still "Shiny Day", and its functionality might even remain the same. This is a good reason why we are using a table here, so we can catch the buff or debuff even if it has multiple possible IDs. However, the most important reason for us to use a table is so that the buffs are compatible across all game versions, since all of them are expected to be supported in the future. For example, the "Rend" debuff might have a different ID in WoW Classic than in Retail. If the buff or debuff that you are trying to analyze only has one ID, you can just pass a table containing this one ID.
3- Custom Cache Duration:
This is an optional parameter and should usually not be modified. This is useful in some specific cases where you want the cache to renew very quickly (or slowly), for some buffs that only appear a very brief of time, for example. However, this is very rare and take into account that modifying this parameter might affect FPS.

This is how our console would look like after running the previous code passing an active buff id as parameter:

How To: Recommended Workflow With Buffs and Debuffs 📃​

The Way We Work
We offer you multiple tools to check all buffs and debuffs information of any unit. In the "Developer Tools" tab, in the main menu, you will find the following tools:


The buttons functionalities are self-explanatory. Everything will be printed to the console uppon pressing. This is useful to find, for example, the ID of a buff or a debuff that is not added to our buffs db (located in enums) and that you might need.

Another option is to use the Debug Panel, located just below "Benchmark Plugin" in the "Developer Tools" menu.






The buttons are, again, self-explanatory. Upon pressing them, a new window (made completely in LUA using our custom GUI. Check Custom UI to learn how to make your own visuals) will appear showing all the information available for the selected unit in the "Mode" combobox.

TIP

When you already know all the buffs and the debuffs that you are going to use, and have all of their IDs stored or know that they are in the buffs database, you can begin using them. If you are going to need the same buff or debuff information in multiple places of your code, maybe you should consider sepparating the said buff or debuff information into a function that you can call multiple times.
For example:

---@return boolean

---@param target game_object

local function has_hunters_mark(target)

    local buff_data = buff_manager:get_debuff_data(target, enums.buff_db.HUNTERS_MARK)

    return buff_data.is_active

end



--- Or, alternatively, using a custom buff ID table:



---@return boolean

---@param target game_object

local function has_hunters_mark(target)

    local possible_hunters_mark_debuff_ids = {257284, }

    local buff_data = buff_manager:get_debuff_data(target, possible_hunters_mark_debuff_ids)

    return buff_data.is_active

end




Then, we can call has_hunters_mark(target) as many times as we want more easily.

---

## https://docs.project-sylvanas.net/dev/api/object-manager

Lua Object Manager
Introduction 📃​

The Lua Object Manager module is your gateway to interacting with game objects in your scripts. While the core engine provides fundamental functions, we've developed additional tools to enhance your scripting capabilities and optimize performance. Let's explore how to leverage these features effectively!

Raw Functions 💣​
Local Player​
core.object_manager.get_local_player() -> game_object​
Retrieves the local player game_object.
Returns: game_object - The local player game_object.
TIP

Always verify the local player object before use. Implement a guard clause in your callbacks to prevent errors and ensure safe execution. Remember, the local_player is a pointer (8 bytes) to the game memory object, which can become invalid. Check its existence before each use.

Example of a guard clause:

local function on_update()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return -- Exit early if local_player is invalid

    end



    -- Your logic here, safely using local_player

end


This approach maintains code stability and prevents accessing invalid memory addresses.

All Objects​
core.object_manager.get_all_objects() -> table​
Retrieves all game objects.
Returns: table - A table containing all game_objects.
WARNING

Use get_all_objects() and get_visible_objects() judiciously. These functions return a comprehensive list, including non-unit entities, which can be computationally expensive to process every frame.

For most scenarios, our custom unit_helper library (discussed later) is recommended for optimized performance and more relevant object lists.

TIP

New to scripting? Visualize objects with this example:

---@type color

local color = require("common/color")



core.register_on_render_callback(function()

    local all_objects = core.object_manager.get_all_objects()

    for _, object in ipairs(all_objects) do

        local current_object_position = object:get_position()

        core.graphics.circle_3d(current_object_position, 2.0, color.cyan(100), 30.0, 1.5)

    end

end)


Code breakdown:

Import the color module for color creation.
Register a function for frame rendering.
Retrieve all game objects.
Iterate through each object.
Get each object's position (returns a vec3).
Draw a 3D circle at each position:
Center: Object's position
Radius: 2.0 yards
Color: Cyan (alpha 100)
Thickness: 30.0 units
Fade factor: 1.5 (higher value = faster fade)

This visualization helps you grasp the scope of objects returned by get_all_objects().

TIP

Want to dive deeper? Try accessing more object properties:

---@type enums

local enums = require("common/enums")



core.register_on_render_callback(function()

    local all_objects = core.object_manager.get_all_objects()

    for _, object in ipairs(all_objects) do

        local name = object:get_name()

        local health = object:get_health()

        local max_health = object:get_max_health()

        local position = object:get_position()

        local class_id = object:get_class()



        -- Convert class_id to a readable string

        local class_name = "Unknown"

        if class_id == enums.class_id.WARRIOR then

            class_name = "Warrior"

        elseif class_id == enums.class_id.WARLOCK then

            class_name = "Warlock"

        -- Add more class checks as needed

        end



        -- Log the information

        core.log(string.format("Name: %s, Class: %s, Health: %d/%d, Position: (%.2f, %.2f, %.2f)",

                            name, class_name, health, max_health, position.x, position.y, position.z))

    end

end)


This example showcases how to access various game object properties and use the enums module for interpreting class IDs. Feel free to expand on this for more complex visualizations or analysis tools!

Visible Objects​
WARNING
---- Not currently implemented ----
core.object_manager.get_visible_objects() -> table​
Retrieves all visible game objects.
Returns: table - A table containing all visible game_objects.
Unit Helper - Optimized Object Retrieval 🚀​

To address performance concerns and provide targeted functionality, we've developed the unit_helper library. This toolkit offers optimized methods for retrieving specific types of game objects, utilizing caching and filtering for improved performance.

NOTE

To use the unit_helper module, include it in your script:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")

Enemies Around​
unit_helper:get_enemy_list_around(point: vec3, range: number, include_out_of_combat: boolean, include_blacklist: boolean) -> table​
Retrieves a list of enemy units around a specified point.
Returns: table - A table containing enemy game_objects.
Parameters:

point: vec3 - The center point to search around.
range: number - The radius (in yards) to search within.
include_out_of_combat: boolean - If true, includes units not in combat.
include_blacklist: boolean - If true, includes special units (use with caution).

Example usage:

---@type color

local color = require("common/color")



---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



core.register_on_render_callback(function()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    local local_player_position = local_player:get_position()

    local range_to_check = 40.0 -- yards

    local enemies_around = unit_helper:get_enemy_list_around(local_player_position, range_to_check, false, false)



    for _, enemy in ipairs(enemies_around) do

        local enemy_position = enemy:get_position()

        core.graphics.circle_3d(enemy_position, 2.0, color.red(255), 30.0, 1.2)

    end

end)


This code visualizes enemies around the player with red circles, demonstrating the focused nature of unit_helper functions.

Allies Around​
unit_helper:get_ally_list_around(point: vec3, range: number, players_only: boolean, party_only: boolean) -> table​
Retrieves a list of allied units around a specified point.
Returns: table - A table containing allied game_objects.
Parameters:

point: vec3 - The center point to search around.
range: number - The radius (in yards) to search within.
players_only: boolean - If true, only includes player characters.
party_only: boolean - If true, only includes party members.

Example usage:

---@type color

local color = require("common/color")



---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



local function my_on_render()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    local range_to_check = 40.0 -- yards

    local green_color = color.new(0, 255, 0, 230)

    local player_position = local_player:get_position()

    local allies_around = unit_helper:get_ally_list_around(player_position, range_to_check, false, false)



    for _, ally in ipairs(allies_around) do

        local ally_position = ally:get_position()

        core.graphics.circle_3d(ally_position, 2.0, green_color, 30.0, 1.5)

    end

end



core.register_on_render_callback(my_on_render)


Let's break down the optimizations in this code:

Module Imports: We import necessary modules for color and unit helper functions.
Named Function: We use a named function my_on_render() for better readability and debugging.
Early Exit: We implement a guard clause for the local player check.
Pre-loop Calculations: We define constants and calculate values outside the loop for efficiency.
Optimized Retrieval: We use unit_helper:get_ally_list_around() for targeted, efficient object retrieval.
Efficient Looping: We use ipairs() for optimal iteration.

Performance Considerations 🏎️​

This code showcases several key performance optimizations:

Color Calculation: Pre-calculating the color object reduces redundant calculations.
Player Position: Calculating player_position once avoids repeated calls.
Targeted Retrieval: Using unit_helper functions significantly reduces processed objects.
Efficient Looping: Proper use of ipairs() ensures optimal iteration.
Optimization Principles 📊​

Key principles demonstrated:

Minimize Repetitive Calculations: Perform constant calculations outside loops.
Use Specialized Functions: Employ targeted functions for efficient processing.
Early Exit: Use guard clauses to avoid unnecessary computations.
Readability and Maintainability: Balance optimizations with code clarity.
TIP

The unit_helper functions not only boost performance but also provide more relevant data for most scripting scenarios. By using these functions, you can create more efficient and focused scripts, reducing unnecessary iterations and checks.

Remember, effective scripting often involves balancing raw data access with optimized helper functions. As you develop more complex scripts, consider the performance implications of your choices and leverage the unit_helper library when appropriate. Happy scripting! 🚀

More Object Manager Functions​
Mouse over Oject​
object_manager.get_mouse_over_object() -> game_object​

Returns the object that you are hovering with your mouse.

get_arena_target(index: integer)​

Retrieves the game object associated with the given arena frame index. Returns nil if not in an arena.

Parameters:
index (integer) — The arena frame index.

Returns: game_object | nil — The player corresponding to the arena frame, or nil if not available.

get_arena_frames()​

Retrieves the list of game objects representing all arena frames.

Returns: game_object[] — A list of all arena frame objects.

---

## https://docs.project-sylvanas.net/dev/api/game-object

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

---

## https://docs.project-sylvanas.net/dev/api/game-object/examples

Game Object - Code Examples
Overview​

In this section, we are going to showcase some usefull code examples that you could use for your own scripts. We advise you to understand the code before copying and pasting it. Before beginning, have a look at Game Object - Functions since you will be able to find all available functions for game objects there.

Starting The Journey
Before continuing, note that you should have some idea about callbacks, what they are and how they work, and the way functions work in LUA. Check Core - Callbacks

Example 1 - Retrieving the Tank From Your Party​

In this case, we already prepared a function that does this functionality for you. It's located in the unit_helper module.

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



---@param local_player game_object

---@returns game_object | nil

local get_tank_from_party(local_player)

    local allies_from_party = unit_helper:get_ally_list_around(local_player:get_position(), 40.0, true, true)



    for k, ally in ipairs(allies_from_party) do

        local is_current_ally_tank = unit_helper:is_tank(ally)



        if is_current_ally_tank then

            return ally

        end

    end



    return nil

end



NOTE

To retrieve the healer, we can do likewise and use the unit_helper. In this case, just use the function is_healer instead of is_tank

Example 2 - Retrieving the Skull-Marked Unit​
---@type enums

local enums = require("common/enums")



---@return game_object | nil

local function get_skull_marked_unit()

    -- first, we check if local player exists

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- then, we check all possible units in 40yds radius (for example)

    local search_radius = 40.0



    -- we will use squared distance, since this is much more efficient than the regular distance function,

    -- as it prevents a square root operation from being performed. (The final result is exactly the same one)

    local squared_search_radius = 40.0 * 40.0



    local all_units = core.object_manager.get_all_objects()



    -- important: do not try to get the local player position inside the loop, since this

    -- will drop fps as your CPU would be performing useless extra work.

    local local_player_position = local_player:get_position()

    for k, unit in ipairs(all_units) do

        local unit_position = unit:get_position()

        local squared_distance = unit_position:squared_dist_to_ignore_z(local_player_position)



        if squared_distance <= squared_search_radius then

            local unit_marker_index = unit:get_target_marker_index()

            local is_skull = unit_marker_index == enums.mark_index.SKULL



            if is_skull then

                return unit

            end

        end

    end



    return nil

end

TIP

You can check that the code works by using the following lines:

core.register_on_update_callback(function()

    local skull_marked_npc = get_skull_marked_npc()

    if skull_marked_npc then

        core.log("The Skull-Marked NPC's name is: " .. skull_marked_npc:get_name())

    else

        core.log("No Skull-Marked NPC was found!")

    end

end)


You can also retrieve the units marked with other marks by re-using the same code, you would just need to change the enums.mark_index. index. (Basically, you would just need to change line 30)

Example 3 - Retrieving the Future Position of a Unit​
---@param unit game_object

---@param time number

---@return vec3

local function get_future_position(unit, time)

    local unit_current_position = unit:get_position() -- vec3

    local unit_direction = unit:get_direction()       -- vec3

    local unit_speed = unit:get_movement_speed()      -- number



    -- first, we normalize the direction vector to ensure it has a length of 1

    local unit_direction_normalized = unit_direction:normalize()



    -- then, we calculate the displacement: distance = speed * time

    local displacement = unit_direction_normalized * unit_speed * time



    -- finally, we just calculate the future position by adding the displacement to the current position

    local future_position = unit_current_position + displacement



    return future_position

end

TIP

To test the previous code, you could use the following lines:

core.register_on_render_callback(function()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- lets draw a line between current position and our calculated future position

    local local_player_position = local_player:get_position()

    local local_player_future_pos_in_1_sec = get_future_position(local_player, 0.50)



    core.graphics.circle_3d(local_player_future_pos_in_1_sec, 2.5, color.cyan(200), 25.0, 1.5)

    core.graphics.line_3d(local_player_position, local_player_future_pos_in_1_sec, color.cyan(255), 6.0)

end)


Example 4 - Set Glowing To Enemies That Are Not On Line Of Sight​
---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



---@type enums

local enums = require("common/enums")



core.register_on_update_callback(function()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    local local_player_position = local_player:get_position()

    -- we get the enemies around 40 yards from player

    local enemies = unit_helper:get_enemy_list_around(local_player_position, 40.0, true)



    for k, enemy in ipairs(enemies) do

        local enemy_pos = enemy:get_position()

        -- trace line will return true if the enemy is in line of sight, as long as we pass the enums.collision_flags.LineOfSight flag

        local is_in_los = core.graphics.trace_line(local_player_position, enemy_pos, enums.collision_flags.LineOfSight)

        -- we have to check if the unit is glowing already

        local is_glowing_already = enemy:is_glow()



        if not is_in_los then

            if not is_glowing_already then

                -- make it glow if not glowing yet

                enemy:set_glow(enemy, true)

            end

        else

            if is_glowing_already then

                -- make it not glow if it's in line of sight, if it was glowing before

                enemy:set_glow(enemy, false)

            end

        end

    end

end)


---

## https://docs.project-sylvanas.net/dev/api/spellbook

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

---

## https://docs.project-sylvanas.net/dev/api/spellbook/helper

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


---

## https://docs.project-sylvanas.net/dev/api/ui

Menu
Overview 📃​

This module is one of the most important ones, since it is the one that will allow you to add customization options to your plugins. You could always design your own menu for your scripts using our Custom UI, in a way that makes your plugins very unique and different from the rest. However, this would add a level of complexity that might not be necessary in most cases. So, for most devs, we offer the option to add your own menu to the main menu directly. (You can still use the menu elements in your custom menu, if desired, as stated in the Custom UI guide).

Menu Elements Basics
There are a two things that you have to keep in mind when working with menu elements. The first one is that you can only render them in 2 specific callbacks. The other information that you should know is menu elements are, and therefore, must be treated as, objects. This implies that you must not declare the menu elements inside the render callback, since you would be generating a new different menu element with each iteration. This will cause issues, specially if done with tree nodes.

TIP

There is one exception to the previous rule, and that is, headers. You can render a header (a plain text in the menu) as follows:

    core.menu.header():render("Header Test", color.green(200))


And it would be valid, since headers are a very light-weight object and don't need of an unique ID, unlike the other menu elements.

An example of an invalid code:

-- The state of the checkbox is not saved into the variable "bad_code_example", since core.menu.checkbox doesn't return a boolean, but rather the checkbox object.

-- A new checkbox is being generated every frame, generating performance issues.

core.register_on_render_menu_callback(function()

    local bad_code_example = core.menu.checkbox(true, "testing_1"):render("AA")

end)


An example of code following best practices:

-- first, we generate a table containing all the menu elements that we are going to use OUTSIDE the callback



---@type color

local color = require("common/color")



local menu_elements =

{

    my_test_node = core.menu.tree_node(),

    my_checkbox_1 = core.menu.checkbox(true, "my_checkbox_test"),

    my_test_keybind = core.menu.keybind(7, false, "my_test_keybind")

}



core.register_on_render_menu_callback(function()

    menu_elements.my_test_node:render("Hi From Lua - Testing Menu Elements!", function()

        menu_elements.my_checkbox_1:render("Testing The Checkbox!", "This is a tooltip!")

        core.menu.header():render("Testing The Headers!", color.green(200))

        menu_elements.my_test_keybind:render("Testing The Keybind!")

    end)

end)




This is the result of the previous code:

Register Menu Callback​
WARNING

Menu elements can only be rendered inside the register_on_render_menu_callback OR register_on_render_window_callback callbacks. The first one is reserved for menu elements that will be rendered within the main menu, and the second one for menu elements that will be rendered within one of your custom-made windows. See Custom UI Guide

core.menu.register_on_render_menu_callback(callback: function)

This function registers the menu for interaction. Same like with other callbacks, you can also pass an anonymous function. This is how you would call the callback:
core.menu.register_on_render_menu_callback(function()

     -- your pre-defined menu elements render function code here

end)


Or:

local function my_render_menu_function()

    -- your pre-defined menu elements render function code here

end



core.menu.register_on_render_menu_callback(my_render_menu_function)

Available Menu Elements​
Tree Node 🌳​
Constructor​
tree_node()​

Creates a new tree node instance.

Returns: tree_node — A new tree_node object.

render(header, callback)​

Renders the tree node with content.

Parameters:
header (string) — The header text of the tree node.
callback (function) — The content to render inside the node.
Example​
-- Anonymous function approach

main_node:render("Debug Plugin", function()

    -- content inside the node

end)



-- Alternative

local function debug_plugin_node()

    -- content inside the node

    -- note: declare outside menu callback

end



-- Inside menu callback

main_node:render("Debug Plugin", debug_plugin_node)

is_open()​

Checks if the tree node is open.

Returns: boolean — true if the tree node is open; otherwise, false.

Checkbox ☑️​
Constructor​
checkbox(default_state, id)​

Creates a new checkbox instance.

Parameters:
default_state (boolean) — The default state of the checkbox.
id (string) — The unique identifier for the checkbox.

Returns: checkbox — A new checkbox object.

render(label, tooltip(optional))​

Renders the checkbox with the specified label and optional tooltip.

Parameters:
label (string) — The label text of the checkbox.
tooltip (string, optional) — The tooltip text for the checkbox.
TIP

Checkbox render supports \n to write multiple lines.

get_state()​

Retrieves the current state of the checkbox.

Returns: boolean — true if checked; otherwise, false.

set(new_state)​

Sets a new state for the checkbox.

Parameters:
new_state (boolean) — The new state to set.

Returns: nil

Slider Int 🎚️​
Constructor​
slider_int(min_value, max_value, default_value, id)​

Creates a new slider with integer values.

Parameters:
min_value (number) — The minimum value of the slider.
max_value (number) — The maximum value of the slider.
default_value (number) — The default value of the slider.
id (string) — The unique identifier for the slider.

Returns: slider_int — A new slider_int object.

render(label, tooltip(optional))​

Renders the slider with the specified label and optional tooltip.

Parameters:
label (string) — The label text of the slider.
tooltip (string, optional) — The tooltip text for the slider.
TIP

Slider render supports \n to write multiple lines.

get()​

Retrieves the current value of the slider.

Returns: number — The current value.

set(new_value)​

Sets a new value for the slider.

Parameters:
new_value (number) — The new value to set.

Returns: nil

Slider Float 🎛️​
Constructor​
slider_float(min_value, max_value, default_value, id)​

Creates a new slider with floating-point values.

Parameters:
min_value (number) — The minimum value of the slider.
max_value (number) — The maximum value of the slider.
default_value (number) — The default value of the slider.
id (string) — The unique identifier for the slider.

Returns: slider_float — A new slider_float object.

render(label, tooltip (optional))​

Renders the slider with the specified label and optional tooltip.

Parameters:
label (string) — The label text of the slider.
tooltip (string, optional) — The tooltip text for the slider.
TIP

Slider render supports \n to write multiple lines.

get()​

Retrieves the current value of the slider.

Returns: number — The current value.

set(new_value)​

Sets a new value for the slider.

Parameters:
new_value (number) — The new value to set.

Returns: nil

Combobox 🔽​
Constructor​
combobox(default_index, id)​

Creates a new combobox.

Parameters:
default_index (number) — The default index of the combobox options (1-based).
id (string) — The unique identifier for the combobox.

Returns: combobox — A new combobox object.

render(label, options, tooltip (optional))​

Renders the combobox with the specified label, options, and optional tooltip.

Parameters:
label (string) — The label text of the combobox.
options (table) — A table of strings containing the options for the combobox.
tooltip (string, optional) — The tooltip text for the combobox.
TIP

Combobox render supports \n to write multiple lines.

get()​

Retrieves the index of the currently selected option (1-based).

Returns: number — The index of the selected option.

set(new_value)​

Sets a new selected index for the combobox.

Parameters:
new_value (number) — The new index to select.

Returns: nil

TIP

You could use a combo box to let the user decide script behaviours in a more graphical way. Below, an example using 3 possible modes:

local combat_mode_enum =

{

    AUTO    = 1,

    AOE     = 2,

    SINGLE  = 3,

}



local combat_mode_options =

{

    "Auto",

    "AoE",

    "Single"

}



local main_tree = core.menu.tree_node()

local combat_mode = core.menu.combobox(combat_mode_enum.AUTO, "combat_mode_auto_aoe_single")



core.register_on_render_menu_callback(function()

    main_tree:render("Combo - Test", function()

        combat_mode:render("Testing Combo Boxes - Combat Modes", combat_mode_options)

    end)

end)



core.register_on_update_callback(function()

    local current_combat_mode = combat_mode:get()

    local current_combat_mode_str = combat_mode_options[current_combat_mode]



    local is_current_combat_mode_auto = current_combat_mode == combat_mode_enum.AUTO

    local is_current_combat_mode_aoe = current_combat_mode == combat_mode_enum.AOE

    local is_current_combat_mode_single = current_combat_mode == combat_mode_enum.SINGLE



    core.log("Current Combat Mode Is: " .. current_combat_mode_str)

    core.log("Is Current Combat Mode Auto: " .. tostring(is_current_combat_mode_auto))

    core.log("Is Current Combat Mode AOE: " .. tostring(is_current_combat_mode_aoe))

    core.log("Is Current Combat Mode Single: " .. tostring(is_current_combat_mode_single))

end)




This should be the result of running that code:

Keybind ⌨️​
Constructor​
keybind(default_value, initial_toggle_state, id)​

Creates a new keybind.

Parameters:
default_value (number) — The default key code for the keybind.
initial_toggle_state (boolean) — The initial toggle state.
id (string) — The unique identifier for the keybind.

Returns: keybind — A new keybind object.

render(label, tooltip (optional), add_separator(optional))​

Renders the keybind with the specified label and optional tooltip.

Parameters:
label (string) — The label text of the keybind.
tooltip (string, optional) — The tooltip text for the keybind.
add_separator (boolean, optional) — A flag to add a separator below the keybind. True by default.
get_state()​

Retrieves the state of the keybind.

Returns: boolean — The state of the keybind.

get_toggle_state()​

Retrieves the toggle state of the keybind.

Returns: boolean — The toggle state.

get_key_code()​

Retrieves the key code assigned to the keybind.

Returns: integer — The key code.

set_toggle_state(new_state)​

Sets a new toggle state for the keybind.

Parameters:
new_state (boolean) — The new toggle state.

Returns: nil

set_key_code(new_key_code)​

Sets a new key code for the keybind.

Parameters:
new_key_code (integer) — The new key code.

Returns: nil

Button 🖱️​
Constructor​
button()​

Creates a new button.

Returns: button — A new button object.

render(label, tooltip (optional))​

Renders the button with the specified label and optional tooltip.

Parameters:
label (string) — The label text of the button.
tooltip (string, optional) — The tooltip text for the button.

Returns: boolean — true if the button was clicked; otherwise, false.

Color Picker 🎨​
Constructor​
color_picker(default_color, id)​

Creates a new color picker.

Parameters:
default_color (number) — The default color value.
id (string) — The unique identifier for the color picker.

Returns: color_picker — A new color_picker object.

render(label, tooltip (optional))​

Renders the color picker with the specified label and optional tooltip.

Parameters:
label (string) — The label text of the color picker.
tooltip (string, optional) — The tooltip text for the color picker.
get()​

Retrieves the selected color value.

Returns: number — The selected color value.

Key Checkbox 🖱️​
NOTE

This is a special menu element that allows the user full customization over a keybind . Using this menu element might be overkill in most cases, but there are circumstances where you would want to add full costumization to a certain keybind, so all kinds of users are happy with the customization options. This is what it would look like:

Explanation of the menu element:
1 -> First, we have a checkbox. If this checkbox is disabled, the logic should be disabled completely.
2 -> Secondly, we have a keyboard icon. Upon pressing this icon, a new popup will appear.
3 -> > This popup contains 3 elements:
      3.1 -> Mode: This is the behaviour that the keybind has.
            3.1.1 -> Available modes:
                  3.1.1.1 -- (0) Hold
                  3.1.1.2 -- (1) Toggle
                  3.1.1.3 -- (2) Always
            3.1.2 -> Modes explanation:
                  3.1.2.1 -- Hold means that the keybind state will only return true when the user is pressing it. False otherwise.
                  3.1.2.2 -- Toggle means that the keybind wil behave as a toggle.
                  3.1.2.3 -- Always means that the keybind will always return true (acts as a checkbox, essentially)


Constructor​
key_checkbox(default_key, initial_toggle_state, default_state, show_in_binds, default_mode_state, id)​
--- Creates a new checkbox instance.

---@param default_key integer The default state of the checkbox.

---@param initial_toggle_state boolean The initial toggle state of the keybind

---@param default_state boolean The default state of the checkbox

---@param show_in_binds boolean The default show in binds state of the checkbox

---@param default_mode_state integer The default show in binds state of the checkbox  -> 0 is hold, 1 is toggle, 2 is always

---@param id string The unique identifier for the checkbox.

---@return key_checkbox

render(label, tooltip (optional))​

Renders the key checkbox with the specified label and optional tooltip.

Parameters:
label (string) — The label text of the button.
tooltip (string, optional) — The tooltip text for the button.

Returns: boolean — true if the button was clicked; otherwise, false.

Code Examples 🧰​
-- Define a unique developer ID to prevent ID collisions with other plugins

local dev_id = "unique_developer_id_here"



-- Create a table to store all menu elements

local menu_elements = {}



-- Create the main node for the menu

menu_elements.main_node = core.menu.tree_node()



-- Create checkboxes with unique IDs

menu_elements.checkbox_one = core.menu.checkbox(true, dev_id .. "checkbox_example_one")

menu_elements.checkbox_two = core.menu.checkbox(false, dev_id .. "checkbox_example_two")



-- Create slider int and float with unique IDs

menu_elements.slider_int = core.menu.slider_int(0, 100, 50, dev_id .. "slider_int")

menu_elements.slider_float = core.menu.slider_float(0, 100, 50, dev_id .. "slider_float")



-- Create the sub menu node inside the main node

menu_elements.sub_menu_node = core.menu.tree_node()



-- Create combobox, keybind, button, and color picker with unique IDs

menu_elements.combobox = core.menu.combobox(1, dev_id .. "combobox")

menu_elements.keybind = core.menu.keybind(46, false, dev_id .. "keybind")

menu_elements.button = core.menu.button()

menu_elements.colorpicker = core.menu.color_picker(-65536, dev_id .. "colorpicker")



-- Register the menu rendering callback

core.menu.register_on_render_menu_callback(function()

    -- Render the main node

    menu_elements.main_node:render("Menu Example", function()

        -- Render checkboxes

        menu_elements.checkbox_one:render("Checkbox Example One", "")

        menu_elements.checkbox_two:render("Checkbox Example Two", "")



        -- Render slider int and float

        menu_elements.slider_int:render("Slider Int", "")

        menu_elements.slider_float:render("Slider Float", "")



        -- Render the sub menu node

        menu_elements.sub_menu_node:render("More Elements", function()

            -- Render combobox

            menu_elements.combobox:render("ComboBox", {"Option A", "Option B", "Option C"}, "")

            -- Render keybind

            menu_elements.keybind:render("Keybind", "")

            -- Render button

            if menu_elements.button:render("Button", "") then

                core.log("Button was clicked!")

            end

            -- Render color picker

            menu_elements.colorpicker:render("ColorPicker", "")

        end)

    end)

end)

Notes 📝​
Always declare your menu elements outside of the render callback to prevent creating new instances each frame.
Use unique IDs for your menu elements to avoid conflicts with other menu elements within your plugin.
Menu elements can only be rendered inside the register_on_render_menu_callback or register_on_render_window_callback callbacks.

---

## https://docs.project-sylvanas.net/dev/api/ui/control-panel

Control Panel
Overview​

The control_panel module is essentially a separate unique graphical window that allows the user to track and easily modify the state of specific menu elements whose values are of special importance or are designed to be modified constantly, so the user doesn't have to open the main menu every time. This is usually how the Control Panel might look like for an average user:



How it Works - Basic Explanation

To add elements to the Control Panel, we need to use a specific callback. The core is expecting a table containing some information on the menu elements that are going to be shown in the Control Panel window to return from that callback. When this information is correct, the menu elements can be displayed in the Control Panel window, allowing them to be modified by clicking on them.

NOTE

Drag & Drop is also supported, although this approach requires a special handling that will be covered later.

How to Make it Work - Step by Step (With an Example)​
1- Include the Necessary Plugins
---@type key_helper

local key_helper = require("common/utility/key_helper")



---@type control_panel_helper

local control_panel_utility = require("common/utility/control_panel_helper")

2- Define your menu elements:

    local combat_mode_enum =

    {

        AUTO    = 1,

        AOE     = 2,

        SINGLE  = 3,

    }



    local combat_mode_options =

    {

        "Auto",

        "AoE",

        "Single"

    }



    local test_tree_node = core.menu.tree_node()



    local menu =

    {

        -- note that we are initializing the keybinds with the value "7". This value corresponds to <span style={{color: "rgba(220, 220, 255, 0.6)"}}>"Unbinded"</span>.

        -- We do this so the user has to manually set the key they want. Otherwise, this menu element won't appear

        -- in the <span style={{color: "rgba(255, 100, 200, 0.8)"}}>Control Panel</span>, and will be treated as if its value were true.



        enable_toggle = core.menu.keybind(7, false, "enable_toggle"),

        switch_combat_mode = core.menu.keybind(7, false, "switch_combat_mode"),

        soft_cooldown_toggle = core.menu.keybind(7, false, "soft_cooldown_toggle"),

        heavy_cooldown_toggle = core.menu.keybind(7, false, "heavy_cooldown_toggle"),

        combat_mode = core.menu.combobox(combat_mode_enum.AUTO, "combat_mode_auto_aoe_single"),

    }

3- Define the Function to Render your Menu Elements:

local function on_render_menu_elements()

    test_tree_node:render("Testing <span style={{color: "rgba(255, 100, 200, 0.8)"}}>Control Panel</span> Elements", function()

        menu.enable_toggle:render("Enable Toggle")

        menu.switch_combat_mode:render("Switch Combat Mode")

        menu.soft_cooldown_toggle:render("Soft Cooldowns Toggle")

        menu.combat_mode:render("Combat Mode", combat_mode_options)

    end)

end

4- Define the Callback Function

local function on_control_panel_render()

    -- this is how we build the toggle table that we return from the callback, as previously discussed:

    local enable_toggle_key = menu.enable_toggle:get_key_code()



    -- toggle table -> must have:

    -- member 1: .name

    -- member 2: .keybind (the menu element itself)

    local enable_toggle =

    {

        name = "[My Plugin] Enable (" .. key_helper:get_key_name(enable_toggle_key) .. ") ",

        keybind = menu.enable_toggle

    }



    local soft_toggle_key = menu.soft_cooldown_toggle:get_key_code()

    local soft_cooldowns_toggle =

    {

        name = "[My Plugin] Soft Cooldowns (" .. key_helper:get_key_name(soft_toggle_key) .. ") ",

        keybind = menu.soft_cooldown_toggle

    }



    -- combo table -> must have:

    -- member 1: .name

    -- member 2: .combobox (the menu element itself)

    -- member 3: .preview_value (the current value that the combobox has, in string format)

    -- member 4: .max_items (the amount of items that the combobox has)

    local combat_mode_key = menu.switch_combat_mode:get_key_code()

    local combat_mode = {

        name = "[My Plugin] Combat Mode (" .. key_helper:get_key_name(combat_mode_key) .. ") ",

        combobox = menu.combat_mode,

        preview_value = combat_mode_options[menu.combat_mode:get()],

        max_items = combat_mode_options

    }



    local hard_toggle_key = menu.heavy_cooldown_toggle:get_key_code()

    local hard_cooldowns_toggle =

    {

        name = "[My Plugin] Hard Cooldowns (" .. key_helper:get_key_name(hard_toggle_key) .. ") ",

        keybind = menu.heavy_cooldown_toggle

    }





    -- finally, we define the table that we are going to return from the callback

    local control_panel_elements = {}



    -- we use the <span style={{color: "rgba(255, 100, 200, 0.8)"}}>Control Panel</span> utility to insert this menu element in the table that we are going to return. This function has

    -- code that internally handles stuff related to <span style={{color: "rgba(150, 250, 200, 0.8)"}}>Drag & Drop</span>, so if you want to enable this functionality you must insert the

    -- menu elements by using this table. Otherwise, you could just return the elements without using the ccontrol_panel_helper plugin,

    -- but this way is recommended anyways for scalability reasons.



    control_panel_utility:insert_toggle_(control_panel_elements, enable_toggle.name, enable_toggle.keybind, false)

    control_panel_utility:insert_toggle_(control_panel_elements, soft_cooldowns_toggle.name, soft_cooldowns_toggle.keybind, false)

    control_panel_utility:insert_toggle_(control_panel_elements, hard_cooldowns_toggle.name, hard_cooldowns_toggle.keybind, false)



    control_panel_utility:insert_combo_(control_panel_elements, combat_mode.name, combat_mode.combobox,

    combat_mode.preview_value, combat_mode.max_items, main_menu.switch_combat_mode, false)



    return control_panel_elements

end



5- Use the Callbacks

-- finally, we just need to implement the callbacks. If we want drag and drop, we must also call on_update.

core.register_on_update_callback(function()

    control_panel_utility:on_update(menu)

end)



core.register_on_render_control_panel_callback(on_control_panel_render)

core.register_on_render_menu_callback(on_render_menu_elements)

5- Summary


So far, this is all the code that we created:

---@type key_helper

local key_helper = require("common/utility/key_helper")



---@type control_panel_helper

local control_panel_utility = require("common/utility/control_panel_helper")



local combat_mode_enum =

{

    AUTO    = 1,

    AOE     = 2,

    SINGLE  = 3,

}



local combat_mode_options =

{

    "Auto",

    "AoE",

    "Single"

}



local test_tree_node = core.menu.tree_node()



local menu =

{

    -- note that we are initializing the keybinds with the value "7". This value corresponds to <span style={{color: "rgba(220, 220, 255, 0.6)"}}>"Unbinded"</span>.

    -- We do this so the user has to manually set the key they want. Otherwise, this menu element won't appear

    -- in the <span style={{color: "rgba(255, 100, 200, 0.8)"}}>Control Panel</span>, and will be treated as if its value were true.



    enable_toggle = core.menu.keybind(7, false, "enable_toggle"),

    switch_combat_mode = core.menu.keybind(7, false, "switch_combat_mode"),

    soft_cooldown_toggle = core.menu.keybind(7, false, "soft_cooldown_toggle"),

    heavy_cooldown_toggle = core.menu.keybind(7, false, "heavy_cooldown_toggle"),

    combat_mode = core.menu.combobox(combat_mode_enum.AUTO, "combat_mode_auto_aoe_single"),

}



local function on_render_menu_elements()

    test_tree_node:render("Testing <span style={{color: "rgba(255, 100, 200, 0.8)"}}>Control Panel</span> Elements", function()

        menu.enable_toggle:render("Enable Toggle")

        menu.switch_combat_mode:render("Switch Combat Mode")

        menu.soft_cooldown_toggle:render("Soft Cooldowns Toggle")

        menu.heavy_cooldown_toggle:render("Heavy Cooldowns Toggle")

        menu.combat_mode:render("Combat Mode", combat_mode_options)

    end)

end



local function on_control_panel_render()

    -- this is how we build the toggle table that we return from the callback, as previously discussed:

    local enable_toggle_key = menu.enable_toggle:get_key_code()



    -- toggle table -> must have:

    -- member 1: .name

    -- member 2: .keybind (the menu element itself)

    local enable_toggle =

    {

        name = "[My Plugin] Enable (" .. key_helper:get_key_name(enable_toggle_key) .. ") ",

        keybind = menu.enable_toggle

    }



    local soft_toggle_key = menu.soft_cooldown_toggle:get_key_code()

    local soft_cooldowns_toggle =

    {

        name = "[My Plugin] Soft Cooldowns (" .. key_helper:get_key_name(soft_toggle_key) .. ") ",

        keybind = menu.soft_cooldown_toggle

    }



    -- combo table -> must have:

    -- member 1: .name

    -- member 2: .combobox (the menu element itself)

    -- member 3: .preview_value (the current value that the combobox has, in string format)

    -- member 4: .max_items (the amount of items that the combobox has)

    local combat_mode_key = menu.switch_combat_mode:get_key_code()

    local combat_mode = {

        name = "[My Plugin] Combat Mode (" .. key_helper:get_key_name(combat_mode_key) .. ") ",

        combobox = menu.combat_mode,

        preview_value = combat_mode_options[menu.combat_mode:get()],

        max_items = combat_mode_options

    }



    local hard_toggle_key = menu.heavy_cooldown_toggle:get_key_code()

    local hard_cooldowns_toggle =

    {

        name = "[My Plugin] Hard Cooldowns (" .. key_helper:get_key_name(hard_toggle_key) .. ") ",

        keybind = menu.heavy_cooldown_toggle

    }





    -- finally, we define the table that we are going to return from the callback

    local control_panel_elements = {}



    -- we use the <span style={{color: "rgba(255, 100, 200, 0.8)"}}>Control Panel</span> utility to insert this menu element in the table that we are going to return. This function has

    -- code that internally handles stuff related to <span style={{color: "rgba(150, 250, 200, 0.8)"}}>Drag & Drop</span>, so if you want to enable this functionality you must insert the

    -- menu elements by using this table. Otherwise, you could just return the elements without using the ccontrol_panel_helper plugin,

    -- but this way is recommended anyways for scalability reasons.



    control_panel_utility:insert_toggle_(control_panel_elements, enable_toggle.name, enable_toggle.keybind, false)

    control_panel_utility:insert_toggle_(control_panel_elements, soft_cooldowns_toggle.name, soft_cooldowns_toggle.keybind, false)

    control_panel_utility:insert_toggle_(control_panel_elements, hard_cooldowns_toggle.name, hard_cooldowns_toggle.keybind, false)



    control_panel_utility:insert_combo_(control_panel_elements, combat_mode.name, combat_mode.combobox,

    combat_mode.preview_value, combat_mode.max_items, menu.switch_combat_mode, false)



    return control_panel_elements

end



-- finally, we just need to implement the callbacks. If we want drag and drop, we must also call on_update.

core.register_on_update_callback(function()

    control_panel_utility:on_update(menu)

end)



core.register_on_render_control_panel_callback(on_control_panel_render)

core.register_on_render_menu_callback(on_render_menu_elements)


If you run that code, you will see the following result:

Control Panel Behaviour Explanation​

As you can see in the previous video, the user can remove and add elements from the Control Panel manually. There are 2 ways to do this:

1- The menu element was dragged and dropped: In this case, the user can remove the element from the Control Panel by double-clicking with the right-mouse button on its hitbox.

2- The menu element keybind was set: The user can also make the menu elements appear just by changing the keybind to another key different than the "Unbinded" one. In the same way, a user can remove an element from the Control Panel by setting its key value to "Unbinded" again (right clicking sets the value to default, which in the code example is "Unbinded" or "7").

NOTE

To drag a menu element that has Drag & Drop enabled, you have to press SHIFT and then click. When the Drag & Drop is ready, you will see a box with the menu element name appear. Then, you can drag the said box to the Control Panel. When the Control Panel is higlighted in green, you can drop the box there. After that, you will see that the menu element is now successfully binded to the Control Panel.

WARNING

If a menu element was dragged and dropped in the Control Panel, setting its value to "Unbinded" won't remove it from the Control Panel. Instead, RMB double-click is mandatory.

Likewise, if a menu element was introduced to the Control Panel by setting its value to one different than "Unbinded", RMB double-click won't remove it from the Control Panel.

Tables Expected By The Callback​

1 - Toggle table This table is reserved for toggle keybinds.

Its members must be the following:

1. name: The label that will appear in the Control Panel (string)
2. keybind: The keybind itself (menu_element)

2 - Combobox table This table is reserved for comboboxes.

Its members must be the following:

1. name: The label that will appear in the Control Panel (string)
2. combobox: The combobox itself (menu_element)
3. preview_value`: The current value that the combobox currently has, in string format. (string)
4. max_items: The items that the combobox has (integer)


Registering the Callback​

The procedure is the same as with all other callbacks:

WARNING

Keep in mind that this callback expects a table as a return value. This is the only callback that expects a return value.

core.register_on_render_control_panel_callback(function()

    local menu_elements_table = {}

    -- your control panel code here



    return menu_elements

end)




Or:

local function on_render_control_panel()

    local menu_elements_table = {}

    -- your control panel code here



    return menu_elements

end



core.register_on_render_control_panel_callback(on_render_control_panel)



NOTE

To use the following functions, you will need to include the Control Panel Helper module. To do this, you can just copy these lines:

---@type control_panel_helper

local control_panel_utility = require("common/utility/control_panel_helper")

Functions - Control Panel Helper​
on_update(menu)​

Updates the Control Panel elements by setting drag-and-drop flags based on the current Control Panel label.

Parameters:
menu (table) — The menu containing Control Panel elements to be updated.

Returns: nil

WARNING

You must call this function inside the on_update callback for Drag & Drop functionality to work for your menu elements. Ideally, call this function the first thing on your on_update function.
If this function is not called, Drag & Drop will not work.

insert_toggle(control_panel_table, toggle_table, only_drag_drop)​

Inserts a toggle into the Control Panel table if it is not already inserted and meets the specified criteria.

Parameters:
control_panel_table (table) — The Control Panel table where the toggle will be inserted.
toggle_table (table) — The table containing the toggle element details.
only_drag_drop (boolean, optional) — Flag to indicate if the insertion should only occur during drag-and-drop.

Returns: boolean — true if the toggle was inserted successfully; otherwise, false.

insert_toggle_(control_panel_table, display_name, keybind_element, only_drag_drop)​

Inserts a toggle into the Control Panel table if it is not already inserted and meets the specified criteria.

Parameters:
control_panel_table (table) — The Control Panel table where the toggle will be inserted.
display_name (string) — The name to be displayed for the toggle element.
keybind_element (userdata) — The keybind menu element.
only_drag_drop (boolean, optional) — Flag to indicate if the insertion should only occur during drag-and-drop.

Returns: boolean — true if the toggle was inserted successfully; otherwise, false.

insert_combo(control_panel_table, combo_table, increase_index_key, only_drag_drop)​

Inserts a combobox into the Control Panel table if it is not already inserted and meets the specified criteria.

Parameters:
control_panel_table (table) — The Control Panel table where the combo will be inserted.
combo_table (table) — The table containing the combo element details.
increase_index_key (userdata, optional) — The keybind to increase the index, if applicable.
only_drag_drop (boolean, optional) — Flag to indicate if the insertion should only occur during drag-and-drop.

Returns: boolean — true if the combo was inserted successfully; otherwise, false.

insert_combo_(control_panel_table, display_name, combobox_element, preview_value, max_items, increase_index_key, only_drag_drop)​

Inserts a combobox into the Control Panel table if it is not already inserted and meets the specified criteria.

Parameters:
control_panel_table (table) — The Control Panel table where the combo will be inserted.
display_name (string) — The name to be displayed for the combo element.
combobox_element (userdata) — The combobox menu element.
preview_value (any) — The preview value to be shown for the combobox.
max_items (number) — The maximum number of items in the combobox.
increase_index_key (userdata, optional) — The keybind to increase the index, if applicable.
only_drag_drop (boolean, optional) — Flag to indicate if the insertion should only occur during drag-and-drop.

Returns: boolean — true if the combo was inserted successfully; otherwise, false.

---

## https://docs.project-sylvanas.net/dev/api/ui/custom

Custom UI
Overview​

The Lua Menu Element Window module provides a range of functions for creating and managing custom GUI windows in Lua scripts. This module allows developers to design sophisticated interfaces with various visual elements and controls.

Create New Window 📃​

core.menu.window.new(id)

id: String - The unique identifier for the window.

Returns: window - A new window instance.

Creates a new window with the specified ID. Remember this should always be called outside of the render callback, since we are creating a new unique instance of a window.

Set Initial Size 📃​

window:set_initial_size(size)

size: vec2 - The initial size of the window.
NOTE

This function just sets the initial size of the window. It can be overriden later, either by user input or by code by calling this function inside the render callback (this is not the recommended behaviour)

Set Initial Position 📃​

window:set_initial_position(pos)

pos: vec2 - The initial position of the window.
NOTE

This function just sets the initial position of the window. It can be overriden later, either by user input or by code by calling the "force_next_begin_window_pos" function inside the render callback (this is not the recommended behaviour)

Set Next Close Cross Position Offset 📃​

window:set_next_close_cross_pos_offset(pos_offset)

pos_offset: vec2 - The position offset for the close cross.
NOTE

This function will add an offset on the close cross position. By default, it is rendered at the top-right corner of the window.

Add Menu Element Position Offset 📃​

window:add_menu_element_pos_offset(pos_offset)

pos_offset: vec2 - The position offset for menu elements.
NOTE

This function will add a position offset to the internal dynamic position variable. See "The Advanceds - Explaining Dynamic Drawing" for a more in-depth explanation on the matter.

Get Window Size 📃​

window:get_size()

Returns: vec2 - The current size of the window.
Get Window Position 📃​

window:get_position()

Returns: vec2 - The current position of the window.
Get Mouse Position 📃​

window:get_mouse_pos()

Returns: vec2 - The current mouse position relative to the window.
Get Current Context Dynamic Drawing Offset 📃​

window:get_current_context_dynamic_drawing_offset()

Returns: vec2 - The current context dynamic drawing offset.
NOTE

Retrieves the internal dynamic position variable's current value. See "The Advanceds - Explaining Dynamic Drawing" for a more in-depth explanation on the matter.

Get Text Size 📃​

window:get_text_size(str)

str: String - The text to measure.

Returns: vec2 - The size of the text.

Get Centered Text X Position 📃​

window:get_text_centered_x_pos(text)

text: String - The text to center.

Returns: Number - The X position offset for centered text.

NOTE

After we get the centered text x position offset, we just need to add this value to the dynamic drawing offset by using "window:get_current_context_dynamic_drawing_offset()". Another option is to use the "Center Text" function directly (recommended)

Center Text 📃​

window:center_text(text)

text: String - The text to center.
NOTE

After calling this function, we just need to render the text using the "add_text_on_dynamic_pos" function. You will see that the text is centered in the middle of the window.

Render Text 🖌️​

window:render_text(font_id, pos_offset, color, text)

font_id: Integer - The ID of the font to use.
pos_offset: vec2 - The position offset for the text.
color: color - The color of the text.
text: String - The text to render.
NOTE

Renders a text at the specified position with the given font and color. This function renders statically, so this text is not taken into account for the dynamic position offset.

Render Rectangle 🖌️​

window:render_rect(pos_min_offset, pos_max_offset, color, rounding, thickness [, flags])

pos_min_offset: vec2 - The minimum position offset for the rectangle.
pos_max_offset: vec2 - The maximum position offset for the rectangle.
color: color - The color of the rectangle.
rounding: Number - The rounding radius for the rectangle corners.
thickness: Number - The thickness of the rectangle border.
flags (Optional): Integer - Flags for rectangle rendering. Default is 0.
Available rounding flags: ( enums.window_enums.rect_borders_rounding_flags. )
NO_ROUNDING
ROUND_TOP_LEFT_CORNERS
ROUND_TOP_RIGHT_CORNERS
ROUND_BOTTOM_LEFT_CORNER
ROUND_BOTTOM_RIGHT_CORNER
ROUND_TOP_CORNERS
ROUND_BOTTOM_CORNERS
ROUND_LEFT_CORNERS
ROUND_RIGHT_CORNERS
ROUND_ALL_CORNERS


NOTE

Renders a rectangle at the specified position with the given properties. This function renders statically, so this rectangle is not taken into account for the dynamic position offset.

Render Filled Rectangle 🖌️​

window:render_rect_filled(pos_min_offset, pos_max_offset, color, rounding [, flags])

pos_min_offset: vec2 - The minimum position offset for the filled rectangle.
pos_max_offset: vec2 - The maximum position offset for the filled rectangle.
color: color - The fill color of the rectangle.
rounding: Number - The rounding radius for the rectangle corners.
flags (Optional): Integer - Flags for rectangle rendering. Default is 0.
Available rounding flags: ( enums.window_enums.rect_borders_rounding_flags. )
NO_ROUNDING
ROUND_TOP_LEFT_CORNERS
ROUND_TOP_RIGHT_CORNERS
ROUND_BOTTOM_LEFT_CORNER
ROUND_BOTTOM_RIGHT_CORNER
ROUND_TOP_CORNERS
ROUND_BOTTOM_CORNERS
ROUND_LEFT_CORNERS
ROUND_RIGHT_CORNERS
ROUND_ALL_CORNERS


NOTE

Renders a filled rectangle at the specified position with the given properties. This function renders statically, so this rectangle is not taken into account for the dynamic position offset.

Render Filled Rectangle with Multiple Colors 🖌️​

window:render_rect_filled_multicolor(pos_min_offset, pos_max_offset, col_upr_left, col_upr_right, col_bot_right, col_bot_left, rounding [, flags])

pos_min_offset: vec2 - The minimum position offset for the filled rectangle.
pos_max_offset: vec2 - The maximum position offset for the filled rectangle.
col_upr_left: color - The color for the upper-left corner.
col_upr_right: color - The color for the upper-right corner.
col_bot_right: color - The color for the bottom-right corner.
col_bot_left: color - The color for the bottom-left corner.
rounding: Number - The rounding radius for the rectangle corners.
flags (Optional): Integer - Flags for rectangle rendering. Default is 0.
Available rounding flags: ( enums.window_enums.rect_borders_rounding_flags. )
NO_ROUNDING
ROUND_TOP_LEFT_CORNERS
ROUND_TOP_RIGHT_CORNERS
ROUND_BOTTOM_LEFT_CORNER
ROUND_BOTTOM_RIGHT_CORNER
ROUND_TOP_CORNERS
ROUND_BOTTOM_CORNERS
ROUND_LEFT_CORNERS
ROUND_RIGHT_CORNERS
ROUND_ALL_CORNERS


NOTE

Renders a filled rectangle at the specified position with the given properties. This function renders statically, so this rectangle is not taken into account for the dynamic position offset. The specified colors will be blended so we recommend testing to get used to this function. You can achieve cool-looking visuals with this function. An example is the height / width resizing rectangles that appear when the mouse is hovering the draggable regions of the window. (You can see that on the bottom of the main menu, for example.)

Render Circle 🖌️​

window:render_circle(center, radius, color [, num_segments [, thickness]])

center: vec2 - The center position of the circle.
radius: Number - The radius of the circle.
color: color - The color of the circle.
num_segments (Optional): Integer - The number of segments for the circle. Default is 0.
thickness (Optional): Number - The thickness of the circle outline. Default is 1.0.
NOTE

Renders a circunference (non-filled circle) at the specified position with the given properties. This function renders statically, so this circle is not taken into account for the dynamic position offset.

Render Filled Circle 🖌️​

window:render_circle_filled(center, radius, color [, num_segments])

center: vec2 - The center position of the circle.
radius: Number - The radius of the circle.
color: color - The fill color of the circle.
num_segments (Optional): Integer - The number of segments for the circle. Default is 0.
NOTE

Renders a filled circle at the specified position with the given properties. This function renders statically, so this circle is not taken into account for the dynamic position offset.

Render Quadratic Bezier Curve 🖌️​

window:render_bezier_quadratic(p1, p2, p3, color, num_segments, thickness)

p1: vec2 - The start point of the curve.
p2: vec2 - The control point of the curve.
p3: vec2 - The end point of the curve.
color: color - The color of the curve.
num_segments: Integer - The number of segments for the curve.
thickness: Number - The thickness of the curve.
NOTE

Renders a quadratic bezier curve at the specified position with the given properties. This function renders statically, so this curve is not taken into account for the dynamic position offset.

Render Cubic Bezier Curve 🖌️​

window:render_bezier_cubic(p1, p2, p3, p4, color, num_segments, thickness)

p1: vec2 - The start point of the curve.
p2: vec2 - The first control point of the curve.
p3: vec2 - The second control point of the curve.
p4: vec2 - The end point of the curve.
color: color - The color of the curve.
num_segments: Integer - The number of segments for the curve.
thickness: Number - The thickness of the curve.
NOTE

Renders a cubic bezier curve at the specified position with the given properties. This function renders statically, so this curve is not taken into account for the dynamic position offset.

Render Triangle 🖌️​

window:render_triangle(p1, p2, p3, color, thickness)

p1: vec2 - The first point of the triangle.
p2: vec2 - The second point of the triangle.
p3: vec2 - The third point of the triangle.
color: color - The color of the triangle.
thickness: Number - The thickness of the triangle outline.
NOTE

Renders a triangle at the specified position with the given properties. This function renders statically, so this triangle is not taken into account for the dynamic position offset.

Render Filled Triangle 🖌️​

window:render_triangle_filled(p1, p2, p3, color)

p1: vec2 - The first point of the triangle.
p2: vec2 - The second point of the triangle.
p3: vec2 - The third point of the triangle.
color: color - The fill color of the triangle.
NOTE

Renders a filled triangle at the specified position with the given properties. This function renders statically, so this filled triangle is not taken into account for the dynamic position offset.

Render Filled Triangle with Multiple Colors 🖌️​

window:render_triangle_filled_multi_color(p1, p2, p3, col_1, col_2, col_3)

p1: vec2 - The first point of the triangle.
p2: vec2 - The second point of the triangle.
p3: vec2 - The third point of the triangle.
col_1: color - The color for the first point.
col_2: color - The color for the second point.
col_3: color - The color for the third point.
NOTE

Renders a filled triangle at the specified position with the given properties. This function renders statically, so this triangle is not taken into account for the dynamic position offset. The specified colors will be blended so we recommend testing to get used to this function. You can achieve cool-looking visuals with this function. An example is the height and width resizing triangle that appear when the mouse is hovering the draggable regions of the window. (You can see that on the right-left of the console, for example.)

Render Line 🖌️​

window:render_line(p1, p2, color, thickness)

p1: vec2 - The start point of the line.
p2: vec2 - The end point of the line.
color: color - The color of the line.
thickness: Number - The thickness of the line.
NOTE

Renders a line from p1 to p2 with the given properties. This function renders statically, so this line is not taken into account for the dynamic position offset.

Add Separator 🖌️​

window:add_separator(right_sep_offset, left_sep_offset, y_offset, width_offset, custom_color)

right_sep_offset: Number - The right offset for the separator.
left_sep_offset: Number - The left offset for the separator.
y_offset: Number - The y-offset for the separator.
width_offset: Number - The width offset for the separator.
custom_color: color - The custom color for the separator.
faded_line: Boolean - Render the separator as a faded line.
NOTE

Renders a separator from p1 to p2 with the given properties. This function renders statically, so the separator is not taken into account for the dynamic position offset.

Is Mouse Hovering Rect 📃​

window:is_mouse_hovering_rect(rect_min, rect_max)

rect_min: vec2 - The minimum position of the rectangle.

rect_max: vec2 - The maximum position of the rectangle.

Returns: Boolean

NOTE

Returns true if the mouse is hovering the specified bounds.

Is Rect Clicked 📃​

window:is_rect_clicked(rect_min, rect_max)

rect_min: vec2 - The minimum position of the rectangle.

rect_max: vec2 - The maximum position of the rectangle.

Returns: Boolean

NOTE

Returns true if the mouse left button was clicked while hovering the rect.

Is Rect Double Clicked 📃​

window:is_rect_double_clicked(rect_min, rect_max)

rect_min: vec2 - The minimum position of the rectangle.

rect_max: vec2 - The maximum position of the rectangle.

Returns: Boolean

NOTE

Returns true if the mouse left button was double-clicked while hovering the rect.

Set Visibility 📃​

window:set_visibility(visibility)

visibility: Boolean - The visibility state of the window.
NOTE

If visibility is false, the window will not be rendered. This is useful for window-popups, for example. See the examples in the guide.

Is Being Shown 📃​

window:is_being_shown()

Returns: Boolean - The current visibility state of the window.
Render 📃​

window:render(resizing_flag, is_adding_cross, bg_color, border_color, cross_style_flag, flag_1 (optional), flag_2 (optional), flag_3 (optional), callback)

resizing_flag: Integer - The resizing flag for the window.
is_adding_cross: Boolean - Indicates if a cross is being added.
bg_color: color - The background color of the window. Use color.new(0,0,0,0) to use the Sylvana's theme default color.
border_color: color - The border color of the window.
cross_style_flag (Optional): Integer - The style flag for the cross. Default is 0.
flag_1 (Optional): Integer - Additional rendering flag. Default is 0.
flag_2 (Optional): Integer - Additional rendering flag. Default is 0.
flag_3 (Optional): Integer - Additional rendering flag. Default is 0.
callback: Function - The callback function to execute during rendering.

Available flags: ( enums.window_enums.window_behaviour_flags. )
NO_MOVE - Disables the option for the user to drag the window.
ALWAYS_AUTO_RESIZE - Makes the window content automatically resize according to the space occupied by the widgets that affect the dynamic drawing variable.
NO_SCROLLBAR - Disables scrollbars on the window.

Returns: Boolean - True if the window is being rendered.
NOTE

Renders the window with the specified properties and executes the callback function if the window is open. This is the main function, so all the code regarding visuals will always be inside a window:render block. The callback function must always be the last parameter of the window:render function.

A use example:

---@type color

local color = require("common/color")



---@type vec2

local vec2 = require("common/geometry/vector_2")



---@type enums

local enums = require("common/enums")



local test_window = core.menu.window("Test window - ")



local initial_size = vec2.new(200, 200)

test_window:set_initial_size(initial_size)



local initial_position = vec2.new(500, 300)

test_window:set_initial_position(initial_position)



local bg_color = color.new(16, 16, 20, 180)

local border_color = color.new(100, 99, 150, 255)

core.register_on_render_window_callback(function()

    test_window:begin(enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS, true, color.new(0,0,0,0),

    border_color, enums.window_enums.window_cross_visuals.BLUE_THEME, function()

        -- render your stuff here

    end)

end)

Begin Group 📃​

window:begin_group(callback)

callback: Function - The callback function to execute within the group.
NOTE

Begins a new group and executes the callback function within the group context. This is useful when we want to draw multiple widgets at the same x offset, for example. By using this function, we avoid having to manually set the position for each widget. Instead, we can just set the position once and it will be applied for all widgets inside the callback.

For example, this is the code that we use for the main debug panel buttons:

    -- popup triggers

    window:add_menu_element_pos_offset(vec2.new(actual_offset, 7.0))

    window:begin_group(function()

        if menu_elements.unit_info_launch_popup:render("Show Unit Info") then

            is_unit_info_popup_enabled = true

            unit_info_window.set_visibility(true)

        end



        local auras_warning_msg = "Auras Table Is Empty\nFor Target: " .. target:get_name()

        if menu_elements.unit_auras_launch_popup:render("Show Auras Info") then

            is_unit_auras_popup_enabled = true

            auras_info_window.set_visibility(true)



            if #all_strings_to_show.auras_strings == 0 then

                core.graphics.add_notification(auras_warning_msg_id, "[Debug Panel - Warning]", auras_warning_msg,

                5.0, color.yellow(200))



                is_unit_auras_popup_enabled = false

                auras_info_window.set_visibility(false)

            end

        end



        local is_auras_popup_warning_clicked = core.graphics.is_notification_clicked(auras_warning_msg_id, 0.0)

        if is_auras_popup_warning_clicked then

            is_unit_auras_popup_enabled = true

            auras_info_window.set_visibility(true)

        end



        local buffs_warning_msg = "Buffs Table Is Empty\nFor Target: " .. target:get_name()

        if menu_elements.unit_buffs_launch_popup:render("Show Buffs Info") then

            is_unit_buffs_popup_enabled = true

            buffs_info_window.set_visibility(true)



            if #all_strings_to_show.buffs_strings == 0 then

                core.graphics.add_notification(buffs_warning_msg_id, "[Debug Panel - Warning]", buffs_warning_msg,

                5.0, color.yellow(200))



                is_unit_buffs_popup_enabled = false

                buffs_info_window.set_visibility(false)

            end

        end



        local is_buffs_popup_warning_clicked = core.graphics.is_notification_clicked(buffs_warning_msg_id, 0.0)

        if is_buffs_popup_warning_clicked then

            is_unit_buffs_popup_enabled = true

            buffs_info_window.set_visibility(true)

        end



        local debuffs_warning_msg = "Debuffs Table Is Empty\nFor Target: " .. target:get_name()

        if menu_elements.unit_debuffs_launch_popup:render("Show Debuffs Info") then

            is_unit_debuffs_popup_enabled = true

            debuffs_info_window.set_visibility(true)



            if #all_strings_to_show.debuffs_strings == 0 then

                core.graphics.add_notification(debuffs_warning_msg_id, "[Debug Panel - Warning]", debuffs_warning_msg, 5.0, color.yellow(200))



                is_unit_debuffs_popup_enabled = false

                debuffs_info_window.set_visibility(false)

            end

        end



        local is_debuffs_popup_warning_clicked = core.graphics.is_notification_clicked(debuffs_warning_msg_id, 0.0)

        if is_debuffs_popup_warning_clicked then

            debuffs_info_window.set_visibility(true)

            is_unit_debuffs_popup_enabled = true

        end



        if menu_elements.more_info_launch_popup:render("Show Extra Info") then

            is_extra_info_popup_enabled = true

            extra_unit_info_window.set_visibility(true)

        end

    end)


It is a very extense example, however, you can focus on the following: We are adding the position offset just once, and as you can see in-game, all buttons are centered at the same X position. Note that the "begin_group" function ONLY works for dynamic offset drawings.

Begin Popup 📃​

window:begin_popup(background_color, border_color, size, pos, is_close_on_release, is_triggering_from_button, callback)

background_color: color - The background color of the popup.

border_color: color - The border color of the popup.

size: vec2 - The size of the popup.

pos: vec2 - The initial position of the popup. Note that this position is relative to the parent window's position (the window that spawned the popup)

is_close_on_release: Boolean - Indicates if the popup should close on release, instead of on click.

is_triggering_from_button: Boolean - Indicates if the popup is triggered from a core.menu button, since this requires a special handling.

callback: Function - The callback function to execute within the popup.

Returns: Boolean

NOTE

Begins a new popup with the specified properties and executes the callback function if the popup is open. Essentially, a popup is just another window, with 2 main differences:
1 - We don't need to create a new object for it
2 - A popup will close automatically when the user clicks (or releases the mouse, if that's the specified behaviour) outside of its bounds.
The begin popup will return false when the popup is not being rendered (in other words, when the user closed it.) We have to use this information to set a boolean declared outside of the main render loop that will dictaminate wheter the popup will be rendered again after the user closed it or not. For this, we usually have to use a button or something similar. This might sound confusing at first, but here is a quick example to show how this works:

    -- use a custom rect as a button (you can also use core.menu buttons)

    if window:is_rect_clicked(open_popup_rect_v1, open_popup_rect_v2) then



        -- note: define this boolean is defined outside of the main render callback.

        is_popup_active = true

    end



    if is_popup_active then

        if window:begin_popup(color.new(16, 16, 20, 230), border_color, vec2.new(250, 250), vec2.new(150, 50), false, false, function()

            -- render your stuff here

            end)



        end) then

            -- You can do whatever you want here. If the code here is read it means that the popup is currently being rendered.

        else

            -- This means that the user clicked outside of the popup bounds (or released the mouse), so it shouldn't be rendered anymore.

            is_popup_active = false

        end

    end


You can also check "The Intermediates - Popups" part on Barney's Guide for a more extense explanation and code examples.

Draw Next Dynamic Widget on Same Line 📃​

window:draw_next_dynamic_widget_on_same_line(offset_from_start_x [, spacing_w])

offset_from_start_x: Number - The offset from the start X position.
spacing_w (Optional): Number - The spacing width. Default is -1.0.
NOTE

Draws the next dynamic widget on the same line with the specified offset and spacing. This esentially prevents the internal handling system to automatically add a Y offset for the next dynamic widget that will be rendered.

Draw Next Dynamic Widget on New Line 📃​

window:draw_next_dynamic_widget_on_new_line()

NOTE

Draws the next dynamic widget on a new line. This esentially forces the internal handling system to automatically add a Y offset for the next dynamic widget that will be rendered.

Add Text on Dynamic Position 📃​

window:add_text_on_dynamic_pos(color, text)

color: color - The color of the text.
text: String - The text to add.
NOTE

Adds text on the current dynamic position with the specified color.

Push Font 📃​

window:push_font(font_id)

font_id: Integer - The ID of the font to push.
NOTE

Pushes the specified font onto the internal font stack. Every text rendered after this call will be performed with the specified font, until a new push_font call is found. The currently available fonts are the following ones:
Available Fonts: ( enums.window_enums.font_id. )
FONT_SMALL = 0
FONT_NORMAL = 1
FONT_SEMI_BIG = 2
FONT_BIG = 3
FONT_ICONS_SMALL = 4
FONT_ICONS_BIG = 5
FONT_ICONS_VERY_BIG = 6


Animate Widget 📃​

window:animate_widget(animation_id, start_pos, end_pos, starting_alpha, max_alpha, alpha_speed, movement_speed, only_once)

animation_id: Integer - The ID of the animation.

start_pos: vec2 - The starting position of the animation.

end_pos: vec2 - The ending position of the animation.

starting_alpha: Integer - The starting alpha value.

max_alpha: Integer - The maximum alpha value.

alpha_speed: Number - The speed of the alpha change.

movement_speed: Number - The speed of the movement.

only_once: Boolean - Indicates if the animation should run only once.

Returns: Table - A table containing the animation result with keys current_position and alpha.

NOTE

Animates a widget with the specified properties and returns the animation result. Check "The Advanceds - Animations" part on Barney's Guide for a more in-depth explanation and code examples.

Set Next Window Items Spacing 📃​

window:set_next_window_items_spacing(spacing)

spacing: vec2 - The spacing between window items.
NOTE

Sets the spacing between items in the next window. This only applies to dynamic drawings. This function should be called before the window:render function.

Set Next Window Items Inner Spacing 📃​

window:set_next_window_items_inner_spacing(inner_spacing)

inner_spacing: vec2 - The inner spacing between window items.
NOTE

Sets the inner spacing between items in the next window. This only applies to dynamic drawings. This function should be called before the window:render function.

Set Next Window Padding 📃​

window:set_next_window_padding(padding)

padding: vec2 - The padding of the next window.
NOTE

Sets the padding for the next window. This only applies to dynamic drawings. This function should be called before the window:render function.

Set Background Multicolored 📃​

window:set_background_multicolored(top_left_color: color, top_right_color: color, bot_right_color: color, bot_left_color: color))

This function enables multi-color support for the given window's background.

WARNING

This function MUST be called before the window:begin function.

TIP

You could use a colorpicker for each color, giving infinite color customization options to the user. An example is the PvP UI module.

Manually Set End Called State 📃​

window:set_end_called_state()

This function is to manually set the end_called flag that's used within the core to check if a begin function was called for the given window. The implementation is a bit complex, just keep in mind that this function exists for when you use the functions to set the next window padding/spacing and it gives a Lua Error on the console. This means that we just found an unhandled exception. To fix this, just call this function at the end of your :begin function.
Force Next Begin Window Position 📃​

window:force_next_begin_window_pos(pos)

pos: vec2 - The position to force the next window to begin at.
NOTE

Forces the next window to be rendered at the specified position. This function's use is not recommended in most cases. This function should be called before the window:render function.

Stop Forcing Next Begin Window Position 📃​

window:stop_forcing_position()

NOTE

Stops the next window to be rendered at the specified position. This function's use is not recommended in most cases. This function should be called before the window:render function.

TIP

An example where force_next_begin_window_pos / stop_forcing_position might be useful is when you have to enable attachment / deattachment of one window to another window. (See PvP UI Module). This would be the simple code example:

    if not menu.menu_elements.deattach_check:get_state() then

        settings_window:force_next_begin_window_pos(vec2.new(current_window_pos.x + window_size_elements.x:get(), current_window_pos.y))

    else

        settings_window:stop_forcing_position()

    end


The previous code is extracted directly from the PvP UI Module. The settings window is the one that attaches to current window, which would be the main window (the one with the buttons).

Set Next Window Minimum Size 📃​

window:set_next_window_min_size(min_size)

min_size: vec2 - The minimum size of the next window.
NOTE

Sets the minimum size of the next window, so the user cannot reduce its size to less than the specified value. This function should be called before the window:render function.

Is Animation Finished 📃​

window:is_animation_finished(id)

id: Integer - The ID of the animation.

Returns: Boolean

NOTE

Returns true if the animation with the given ID has already finished.

Set Window Cross Round 📃​

window:set_next_window_cross_round()

NOTE

Sets the next window cross to be a circumference, instead of a rectangle. This function should be called before the window:render function.

Make Loading Circle Animation 📃​

window:make_loading_circle_animation(animation_id, origin, radius, color, thickness, animation_type)

animation_id: Integer - The ID of the animation.
origin: vec2 - The origin of the animation.
radius: Number - The radius of the circle.
color: color - The color of the circle.
thickness: Number - The thickness of the circle.
animation_type: Integer - The type of the animation.
NOTE

Creates a loading circle animation with the specified properties. These are the animations used by the loader, for example.

Get Window Type 📃​

window:get_type()

Returns: Integer - The type of the window.

---

## https://docs.project-sylvanas.net/dev/api/vector-2

Vector 2D
Overview​

The vec2 module provides functions for working with 2D vectors in Lua scripts. These functions include vector creation, arithmetic operations, normalization, length calculation, dot product calculation, interpolation, randomization, rotation, and more.

TIP

If you are new and don't know what a vec2 is and want a deep understanding of this class, and specially, the vec3 data structure, you might want to study some Linear Algebra. This information is basic and it will be usefull for any game-related project that you might work on in the future.

Importing the Module​
WARNING

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the require function and store it in a local variable.

Here is an example of how to do it:

---@type vec2

local vec2 = require("common/geometry/vector_2")

Functions​
Vector Creation and Cloning ✨​
new(x, y)​

Creates a new 2D vector with the specified x and y components.

Parameters:
x (number) — The x component of the vector.
y (number) — The y component of the vector.

Returns: vec2 — A new vector instance.

clone()​

Clones the current vector.

Returns: vec2 — A new vector instance that is a copy of the original.

Arithmetic Operations ➕​
__add(other)​

Overloads the addition operator (+) for vector addition.

Parameters:
other (vec2) — The vector to add.

Returns: vec2 — The result of the addition.

WARNING

Do not use this function directly. Instead, just use the operator +. For example:

---@type vec2

local vec2 = require("common/geometry/vector_2")



local v1 = vec2.new(1, 1)

local v2 = vec2.new(2, 2)



--- Bad code:

-- local v3 = v1:__add(v2)



--- Correct code:

local v3 = v1 + v2

__sub(other)​

Overloads the subtraction operator (-) for vector subtraction.

Parameters:
other (vec2) — The vector to subtract.

Returns: vec2 — The result of the subtraction.

WARNING

Do not use this function directly. Instead, just use the operator -. For example:

---@type vec2

local vec2 = require("common/geometry/vector_2")



local v1 = vec2.new(1, 1)

local v2 = vec2.new(2, 2)



--- Bad code:

-- local v3 = v1:__sub(v2)



--- Correct code:

local v3 = v1 - v2

__mul(value)​

Overloads the multiplication operator (*) for scalar multiplication or element-wise multiplication.

Parameters:
value (number or vec2) — The scalar or vector to multiply with.

Returns: vec2 — The result of the multiplication.

WARNING

Do not use this function directly. Instead, just use the operator *. For example:

---@type vec2

local vec2 = require("common/geometry/vector_2")



local v1 = vec2.new(1, 1)

local v2 = vec2.new(2, 2)



--- Bad code:

-- local v3 = v1:__mul(v2)



--- Correct code:

local v3 = v1 * v2

__div(value)​

Overloads the division operator (/) for scalar division or element-wise division.

Parameters:
value (number or vec2) — The scalar or vector to divide by.

Returns: vec2 — The result of the division.

WARNING

Do not use this function directly. Instead, just use the operator /. For example:

---@type vec2

local vec2 = require("common/geometry/vector_2")



local v1 = vec2.new(1, 1)

local v2 = vec2.new(2, 2)



--- Bad code:

-- local v3 = v1:__div(v2)



--- Correct code:

local v3 = v1 / v2

Vector Properties and Methods 🧮​
normalize()​

Returns the normalized vector (unit vector) of the current vector.

Returns: vec2 — The normalized vector.

length()​

Returns the length (magnitude) of the vector.

Returns: number — The length of the vector.

dot(other)​

Calculates the dot product of two vectors.

Parameters:
other (vec2) — The other vector.

Returns: number — The dot product.

lerp(target, t)​

Performs linear interpolation between two vectors.

Parameters:
target (vec2) — The target vector.
t (number) — The interpolation factor (between 0.0 and 1.0).

Returns: vec2 — The interpolated vector.

Advanced Operations ⚙️​
randomize_xy(margin)​

Randomizes the x and y components of the vector within a specified margin.

Parameters:
margin (number) — The maximum value to add or subtract from each component.

Returns: vec2 — The randomized vector.

rotate_around(origin, angle_degrees)​

Rotates the vector around a specified origin point by a given angle in degrees.

Parameters:
origin (vec2) — The origin point to rotate around.
angle_degrees (number) — The angle in degrees.

Returns: vec2 — The rotated vector.

dist_to(other)​

Calculates the distance to another vector.

Parameters:
other (vec2) — The other vector.

Returns: number — The distance between the vectors.

get_angle(origin)​

Calculates the angle between the vector and the x-axis, relative to a specified origin point.

Parameters:
origin (vec2) — The origin point.

Returns: number — The angle in degrees.

intersects(p1, p2)​

Checks if the vector (as a point) intersects with a line segment defined by two vectors.

Parameters:
p1 (vec2) — The first point of the line segment.
p2 (vec2) — The second point of the line segment.

Returns: boolean — true if the point intersects the line segment; otherwise, false.

get_perp_left(origin)​

Returns the left perpendicular vector of the current vector relative to a specified origin point.

Parameters:
origin (vec2) — The origin point.

Returns: vec2 — The left perpendicular vector.

get_perp_left_factor(origin, factor)​

Returns the left perpendicular vector of the vec2 instance with a factor applied.

Parameters:
origin (vec2) — The origin point.
factor (number) — The factor to apply.

Returns: vec2 — The left perpendicular vector.

get_perp_right(origin)​

Returns the right perpendicular vector of the current vector relative to a specified origin point.

Parameters:
origin (vec2) — The origin point.

Returns: vec2 — The right perpendicular vector.

get_perp_right_factor(origin, factor)​

Returns the right perpendicular vector of the vec2 instance with a factor applied.

Parameters:
origin (vec2) — The origin point.
factor (number) — The factor to apply.

Returns: vec2 — The right perpendicular vector.

Additional Functions 🛠️​
dot_product(other)​

An alternative method to calculate the dot product of two vectors.

Parameters:
other (vec2) — The other vector.

Returns: number — The dot product.

is_nan()​

Checks if the vector is not a number.

Returns: boolean — True if the vector_2 is not a number, false otherwise.

is_zero()​

Checks if the vector is zero.

Returns: boolean — True if the vector_2 is the vector(0,0), false otherwise.

TIP

Saying that a vector is_zero is the same as saying that the said vector equals the vec2.new(0,0)

Code Examples​
Example 1: Vector Addition​
---@type vec2

local vec2 = require("common/geometry/vector_2")



core.register_on_render_callback(function()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- example vectors

    local v1 = vec2.new(500.0, 350.0)

    local v2 = vec2.new(100.0, 100.0)



    local v3 = v1 + v2 -- (this is the result of adding v2 to v1)



    -- this is the blue line in the picture (a line from v1 to v3)

    core.graphics.line_2d(v1, v3, color.cyan(255))



    -- red circle at v1 position

    core.graphics.circle_2d(v1, 20.0, color.red(255))

    -- we adjust the text position by substracting a new vector

    local v1_text_position = v1 - vec2.new(10.0, 15.0)

    -- and finally draw the "v1" text at the position that we just calculated

    core.graphics.text_2d("v1", v1_text_position, 20, color.red(255))



    -- green circle at v3 position

    core.graphics.circle_2d(v3, 20.0, color.green_pale(255))

    -- we adjust the text position by substracting a new vector

    local v3_text_position = v3 - vec2.new(10.0, 10.0)

    -- and finally draw the "v3" text at the position that we just calculated

    core.graphics.text_2d("v3", v3_text_position, 20, color.green(255))

end)


This should be the result after running that piece of code:

Example 2: Vector Dot Product​
---@type vec2

local vec2 = require("common/geometry/vector_2")



-- Create two vectors

local v1 = vec2.new(3, 5)

local v2 = vec2.new(2, 8)



-- Calculate the dot product

local dot_product = v1:dot(v2)



-- Print the dot product

core.log("Dot product of the vectors: " .. dot_product)

Example 3: Vector Normalization​
---@type vec2

local vec2 = require("common/geometry/vector_2")



-- Create a vector

local v = vec2.new(3, 4)



-- Normalize the vector

local normalized = v:normalize()



-- Print the normalized vector

core.log("Normalized vector: (" .. normalized.x .. ", " .. normalized.y .. ")")

Example 4: Vector Rotation​
---@type vec2

local vec2 = require("common/geometry/vector_2")



core.register_on_render_callback(function()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- example vectors

    local v1 = vec2.new(500.0, 350.0)

    -- local v2 = vec2.new(100.0, 100.0)



    -- rotate the vector 90 degrees around the origin

    local v2 = v1:rotate_around(vec2.new(0, 0), 90)



    -- extend the starting position to the rotated position by 100

    local v3 = v1:get_extended(v2, 100.0)



    -- this is the blue line in the picture (a line from v1 to v3)

    core.graphics.line_2d(v1, v3, color.cyan(255))



    -- red circle at v1 position

    core.graphics.circle_2d(v1, 20.0, color.red(255))

    -- we adjust the text position by substracting a new vector

    local v1_text_position = v1 - vec2.new(10.0, 15.0)

    -- and finally draw the "v1" text at the position that we just calculated

    core.graphics.text_2d("v1", v1_text_position, 20, color.red(255))



    -- green circle at v3 position

    core.graphics.circle_2d(v3, 20.0, color.green_pale(255))

    -- we adjust the text position by substracting a new vector

    local v3_text_position = v3 - vec2.new(10.0, 10.0)

    -- and finally draw the "v3" text at the position that we just calculated

    core.graphics.text_2d("v3", v3_text_position, 20, color.green(255))

end)


This is the expected result after running that code:

If we rotate it by -90 degrees instead of 90, this is what we should be seeing now:

---

## https://docs.project-sylvanas.net/dev/api/vector-3

Vector 3D
Overview​

The vec3 module provides functions for working with 3D vectors in Lua scripts. These functions include vector creation, arithmetic operations, normalization, length calculation, dot and cross product calculation, interpolation, randomization, rotation, distance calculation, angle calculation, intersection checking, and more.

TIP

If you are new and don't know what a vec3 is and want a deep understanding of this class, or the vec2 data structure, you might want to study some Linear Algebra. This information is basic and it will be useful for any game-related project that you might work on in the future. Since vec3 has 1 more coordinate in the space, working with vec3 is a little bit more complex. Therefore, if you are new, we recommend you to study vec2 first.

Importing the Module​
WARNING

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the require function and store it in a local variable.

Here is an example of how to do it:

---@type vec3

local vec3 = require("common/geometry/vector_3")

Functions​
Vector Creation and Cloning​
new(x, y, z)​

Creates a new 3D vector with the specified x, y, and z components.

Parameters:
x (number) — The x component of the vector.
y (number) — The y component of the vector.
z (number) — The z component of the vector.

Returns: vec3 — A new vector instance.

NOTE

If no number is passed as parameter (you construct the vector by using vec3.new()) then, a vector_3 is constructed with the values (0,0,0). So, :is_zero will be true.

clone()​

Clones the current vector.

Returns: vec3 — A new vector instance that is a copy of the original.

Arithmetic Operations ➕➖✖️➗​
__add(other)​

Overloads the addition operator (+) for vector addition.

Parameters:
other (vec3) — The vector to add.

Returns: vec3 — The result of the addition.

WARNING

Do not use this function directly. Instead, just use the operator +. For example:

---@type vec3

local vec3 = require("common/geometry/vector_3")



local v1 = vec3.new(1, 1, 0)

local v2 = vec3.new(2, 2, 2)



--- Bad code:

-- local v3 = v1:__add(v2)



--- Correct code:

local v3 = v1 + v2

__sub(other)​

Overloads the subtraction operator (-) for vector subtraction.

Parameters:
other (vec3) — The vector to subtract.

Returns: vec3 — The result of the subtraction.

WARNING

Do not use this function directly. Instead, just use the operator -. For example:

---@type vec3

local vec3 = require("common/geometry/vector_3")



local v1 = vec3.new(1, 1, 0)

local v2 = vec3.new(2, 2, 2)



--- Bad code:

-- local v3 = v1:__sub(v2)



--- Correct code:

local v3 = v1 - v2

__mul(value)​

Overloads the multiplication operator (*) for scalar multiplication or element-wise multiplication.

Parameters:
value (number or vec3) — The scalar or vector to multiply with.

Returns: vec3 — The result of the multiplication.

WARNING

Do not use this function directly. Instead, just use the operator *. For example:

---@type vec3

local vec3 = require("common/geometry/vector_3")



local v1 = vec3.new(1, 1, 0)

local v2 = vec3.new(2, 2, 2)



--- Bad code:

-- local v3 = v1:__mul(v2)



--- Correct code:

local v3 = v1 * v2

__div(value)​

Overloads the division operator (/) for scalar division or element-wise division.

Parameters:
value (number or vec3) — The scalar or vector to divide by.

Returns: vec3 — The result of the division.

WARNING

Do not use this function directly. Instead, just use the operator /. For example:

---@type vec3

local vec3 = require("common/geometry/vector_3")



local v1 = vec3.new(1, 1, 0)

local v2 = vec3.new(2, 2, 2)



--- Bad code:

-- local v3 = v1:__div(v2)



--- Correct code:

local v3 = v1 / v2

__eq(value)​

Overloads the equals operator (==).

Parameters:
value (vec3) — The vector 3 to check if it's equal.

Returns: boolean — True if both vectors are equal, false otherwise.

WARNING

Do not use this function directly. Instead, just use the operator ==. For example:

---@type vec3

local vec3 = require("common/geometry/vector_3")



local v1 = vec3.new(1, 1, 0)

local v2 = vec3.new(2, 2, 2)



--- Bad code:

-- local are_v1_and_v2_the_same = v1:__eq(v2)



--- Correct code:

local are_v1_and_v2_the_same = v1 == (v2)

Vector Properties and Methods 🧮​
normalize()​

Returns the normalized vector (unit vector) of the current vector.

Returns: vec3 — The normalized vector.

length()​

Returns the length (magnitude) of the vector.

Returns: number — The length of the vector.

dot(other)​

Calculates the dot product of two vectors.

Parameters:
other (vec3) — The other vector.

Returns: number — The dot product.

cross(other)​

Calculates the cross product of two vectors.

Parameters:
other (vec3) — The other vector.

Returns: vec3 — The cross product vector.

lerp(target, t)​

Performs linear interpolation between two vectors.

Parameters:
target (vec3) — The target vector.
t (number) — The interpolation factor (between 0.0 and 1.0).

Returns: vec3 — The interpolated vector.

Advanced Operations ⚙️​
rotate_around(origin, angle_degrees)​

Rotates the vector around a specified origin point by a given angle in degrees.

Parameters:
origin (vec3) — The origin point to rotate around.
angle_degrees (number) — The angle in degrees.

Returns: vec3 — The rotated vector.

dist_to(other)​

Calculates the Euclidean distance to another vector.

Parameters:
other (vec3) — The other vector.

Returns: number — The distance between the vectors.

TIP

Usually, you would want to use dist_to_ignore_z, since for most cases you don't really care about the Z component of the vector (height differences). We recommend using squared_dist_to_ignore_z, instead of dist_to_ignore_z or squared_dist_to instead of dist_to. If you check the mathematical formula to calculate a distance between 2 vectors, you will see there is a square root operation there. This is computationally expensive, so, for performance reasons, we advise you to just use the square function and then compare it to the value you want to compare it, but squared. For example:

-- check if the distance between v1 and v2 is > 10.0

---@type vec3

local vec3 = require("common/geometry/vector_3")



local v1 = vec3.new(5.0, 5.0, 5.0)

local v2 = vec3.new(10.0, 10.0, 10.0)



local distance_check = 10.0

local distance_check_squared = distance_check * distance_check



-- method 1: BAD

local distance = v1:dist_to(v2)



local is_dist_superior_to_10_method1 = distance > distance_check

core.log("Method 1 result: " .. tostring(is_dist_superior_to_10_method1))



-- method 2: GOOD

local distance_squared = v1:squared_dist_to(v2)



local is_dist_superior_to_10_method2 = distance_squared > distance_check_squared

core.log("Method 2 result: " .. tostring(is_dist_superior_to_10_method2))




If you run the previous code, you will notice that the result from the first method is the same as the result from the second method. However, the second one is much more efficient. This will make no difference in a low scale, but if you have multiple distance checks in your code it will end up being very noticeable in the user's FPS counter.

squared_dist_to(other)​

Calculates the Euclidean squared distance to another vector.

Parameters:
other (vec3) — The other vector.

Returns: number — The squared distance between the vectors.

NOTE

This function is recommended over dist_to(other), for the reasons previously explained.

squared_dist_to_ignore_z(other)​

Calculates the Euclidean squared distance to another vector, ignoring the Z component of the vectors.

Parameters:
other (vec3) — The other vector.

Returns: number — The squared distance between the vectors, without taking into account the Z component of the vectors.

NOTE

This function is recommended over dist_to_ignore_z(other), for the reasons previously explained.

dist_to_line_segment(line_segment_start, line_segment_end)​

Calculates the distance from self to a given line segment.

Parameters:
other (vec3) — The other vector.

Returns: number — The distance between self and a line segment.

squared_dist_to_line_segment(line_segment_start, line_segment_end)​

Calculates the distance from self to a given line segment.

Parameters:
other (vec3) — The other vector.

Returns: number — The squared distance between self and a line segment.

NOTE

This function is recommended over dist_to_line_segment(), for the reasons previously explained.

squared_dist_to_ignore_z_line_segment(line_segment_start, line_segment_end)​

Calculates the distance from self to a given line segment, ignoring the Z component of the vector.

Parameters:
other (vec3) — The other vector.

Returns: number — The squared distance between self and a line segment, ignoring the Z component of the vector.

get_angle(origin)​

Calculates the angle between the vector and a target vector, relative to a specified origin point.

Parameters:
origin (vec3) — The origin point.

Returns: number — The angle in degrees.

intersects(p1, p2)​

Checks if the vector (as a point) intersects with a line segment defined by two points.

Parameters:
p1 (vec3) — The first point of the line segment.
p2 (vec3) — The second point of the line segment.

Returns: boolean — true if the point intersects the line segment; otherwise, false.

get_perp_left(origin)​

Returns the left perpendicular vector of the current vector relative to a specified origin point.

Parameters:
origin (vec3) — The origin point.

Returns: vec3 — The left perpendicular vector.

get_perp_right(origin)​

Returns the right perpendicular vector of the current vector relative to a specified origin point.

Parameters:
origin (vec3) — The origin point.

Returns: vec3 — The right perpendicular vector.

Additional Functions 🛠️​
dot_product(other)​

An alternative method to calculate the dot product of two vectors.

Parameters:
other (vec3) — The other vector.

Returns: number — The dot product.

is_nan()​

Checks if the vector is not a number.

Returns: boolean — True if the vector_3 is not a number, false otherwise.

is_zero()​

Checks if the vector is zero.

Returns: boolean — True if the vector_3 is the vector(0,0,0), false otherwise.

TIP

Saying that a vector is_zero is the same as saying that the said vector equals the vec3.new(0,0,0)

Code Examples​
---@type vec3

local vec3 = require("common/geometry/vector_3")



local v1 = vec3.new(1, 2, 3)

local v2 = vec3.new(4, 5, 6)

local v3 = v1:clone() -- Clone v1



-- Adding vectors

local v_add = v1 + v2

core.log("Vector addition result: " .. v_add.x .. ", " .. v_add.y .. ", " .. v_add.z)



-- Subtracting vectors

local v_sub = v1 - v2

core.log("Vector subtraction result: " .. v_sub.x .. ", " .. v_sub.y .. ", " .. v_sub.z)



-- Normalizing a vector

local v_norm = v1:normalize()

core.log("Normalized vector: " .. v_norm.x .. ", " .. v_norm.y .. ", " .. v_norm.z)



-- Finding the distance between two vectors, ignoring z

local dist_ignore_z = v1:dist_to_ignore_z(v2)

core.log("Distance ignoring Z: " .. dist_ignore_z)



-- Finding the squared length for efficiency

local dist_squared = v1:length_squared()

core.log("Squared length: " .. dist_squared)


---

## https://docs.project-sylvanas.net/dev/libraries/izi

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


---

## https://docs.project-sylvanas.net/dev/libraries/izi/object-extensions

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


---

## https://docs.project-sylvanas.net/dev/libraries/izi/spell

IZI - Spell (izi_spell)
Overview​

The IZI Spell system provides a powerful object-oriented approach to spell management and casting in World of Warcraft. Instead of working with raw spell IDs and manually checking multiple conditions or writing your own helpers, you create spell objects that encapsulate all the intelligence needed for smart, reliable spell casting.

Key Features:

Smart Casting - Automatic validation of facing, range, cooldowns, charges, resources, and more
Flexible Validation - Fine-grained control over which checks to skip or enforce via cast options
Unit & Position Casting - Cast spells on targets or ground positions with built-in prediction
AoE Optimization - Intelligent position prediction for maximizing hits with area-effect spells
Buff/Debuff Tracking - Monitor spell effects on units with configurable tracking
Cooldown Management - Query remaining cooldowns, charges, and charge fractional states
Resource Awareness - Automatic cost checking for mana, energy, rage, and other resources
LOS & Facing - Built-in line-of-sight and facing requirement validation

Whether you're building a damage rotation, healing routine, or utility automation, the izi_spell class eliminates boilerplate code and provides a consistent, intuitive interface for all your spell casting needs. Create a spell object once, then use its methods throughout your code for clean, maintainable spell management.

Creating a new Spell​
izi.spell​
Syntax
-- Overload 1: Single spell ID

izi.spell(id: integer)



-- Overload 2: Multiple spell IDs (variadic)

izi.spell(id1: integer, id2: integer, ...: integer)



-- Overload 3: Array of spell IDs

izi.spell(ids: integer[])


Parameters

Overload 1:

id: integer - A single spell ID to create a spell object for

Overload 2:

id1: integer - The first spell ID
id2: integer - The second spell ID
...: integer - Additional spell IDs (useful for spell ranks or alternatives)

Overload 3:

ids: integer[] - A table (array) of spell IDs
Returns
izi_spell - A new spell object with built-in casting utilities and validation methods
Description

Creates a new spell object that encapsulates all the functionality needed for intelligent spell casting. The spell object provides methods for casting, validation, cooldown checking, buff/debuff tracking, and more.

You can provide a single spell ID, multiple spell IDs (for spell ranks or alternatives), or an array of spell IDs. When multiple IDs are provided, the spell object will automatically use the first available and castable spell from the list.

Example Usage

local izi = require("common/izi_sdk")



-- Create a spell with a single ID

local fireball = izi.spell(133)



-- Create a spell with multiple IDs (spell ranks or alternatives)

local frostbolt = izi.spell(116, 61087, 228597)



-- Create a spell from a table (array) of IDs

local polymorph = izi.spell({ 118, 28272, 28271 })



-- Use the spell object to cast

if fireball:cast_safe(target) then

    izi.print("Cast Fireball!")

end



-- Check if spell is ready to cast

if frostbolt:is_castable() then

    izi.print("Frostbolt is ready!")

end



-- Get cooldown information

local cd_remaining = polymorph:cooldown()

izi.printf("Polymorph cooldown: %.1f seconds", cd_remaining)

Fields​

Once you've created an izi_spell object, you can access the following fields to inspect its state and configuration:

ids​
Type
integer[]

Description

The candidate spell IDs that this spell object can cast. When multiple IDs are provided during creation, the spell object will attempt to use the first available and castable spell from this list.

Example Usage

local frostbolt = izi.spell(116, 205021, 228597)

izi.printf("Frostbolt has %d spell variants", #frostbolt.ids)

max_enemies​
Type
integer

Description

A utility knob for controlling AoE heuristics and optimization. This field influences how the spell object calculates optimal positions for area-effect spells when using position prediction.

Example Usage

local blizzard = izi.spell(190356)

blizzard.max_enemies = 8  -- Optimize for hitting up to 8 enemies

last_cast_time​
Type
number

Description

The last time (in seconds) this spell was queued to cast. Useful for tracking spell usage patterns and implementing custom cooldown logic or cast frequency limits.

Example Usage

local fireball = izi.spell(133)

fireball:cast(target)



-- Check when the spell was last cast

local time_since_cast = izi.now() - fireball.last_cast_time

izi.printf("Fireball was cast %.2f seconds ago", time_since_cast)

minimum_range​
Type
number

Description

The minimum range from the spellbook for this spell. Returns 0 if the spell has no minimum range requirement. This is automatically populated from the spell's data.

Example Usage

local charge = izi.spell(100)

if charge.minimum_range > 0 then

    izi.printf("Charge requires at least %.1f yards", charge.minimum_range)

end

maximum_range​
Type
number

Description

The maximum range from the spellbook for this spell. Returns 0 if the spell has no maximum range (unlimited range). This is automatically populated from the spell's data.

Example Usage

local frostbolt = izi.spell(116)

izi.printf("Frostbolt max range: %.1f yards", frostbolt.maximum_range)



-- Check if target is in range

local target = izi.target()

if target and target:get_distance() <= frostbolt.maximum_range then

    izi.print("Target is in range!")

end

Helpers​

Once you've created an izi_spell object, you can call the following helpers to interact with and query the spell:

id​
Syntax
spell:id(): integer

Returns
integer - The active spell ID
Description

Returns the currently active spell ID. When multiple IDs are provided during spell creation, this returns the first available and usable spell ID from the list.

Example Usage

local frostbolt = izi.spell(116, 205021, 228597)

izi.printf("Active spell ID: %d", frostbolt:id())

name​
Syntax
spell:name(): string

Returns
string - The spell name
Description

Returns the name of the spell from the game's spell database.

Example Usage

local fireball = izi.spell(133)

izi.printf("Spell name: %s", fireball:name())  -- Output: "Spell name: Fireball"

is_learned​
Aliases
is_available
Syntax
spell:is_learned(): boolean

Returns
boolean - True if the spell is learned
Description

Checks if the player has learned this spell. Returns true if the spell is in the player's spellbook.

Example Usage

local polymorph = izi.spell(118)

if polymorph:is_learned() then

    izi.print("Polymorph is available in spellbook")

end

is_usable​
Syntax
spell:is_usable(): boolean

Returns
boolean - True if the spell is usable
Description

Checks if the spell can be used right now, considering factors like resources, cooldown, and player state.

Example Usage

local fireball = izi.spell(133)

if fireball:is_usable() then

    izi.print("Fireball is ready to cast")

end

cast_time​
Syntax
spell:cast_time(): integer

Returns
integer - The spell's cast time in seconds
Description

Returns the cast time of the spell in seconds.

Example Usage

local frostbolt = izi.spell(spell)

izi.printf("Frostbolt cast time: %d seconds", frostbolt:cast_time())

cast_time_ms​
Syntax
spell:cast_time_ms(): integer

Returns
integer - The spell's cast time in miliseconds
Description

Returns the cast time of the spell in miliseconds.

Example Usage

local frostbolt = izi.spell(spell)

izi.printf("Frostbolt cast time: %d miliseconds", frostbolt:cast_time_ms())

charges​
Syntax
spell:charges(): integer

Returns
integer - Current number of charges
Description

Returns the current number of charges available for the spell. Returns 0 if the spell doesn't have a charge system.

Example Usage

local fire_blast = izi.spell(108853)

izi.printf("Fire Blast charges: %d", fire_blast:charges())

max_charges​
Syntax
spell:max_charges(): integer

Returns
integer - Maximum number of charges
Description

Returns the maximum number of charges this spell can hold. Returns 0 if the spell doesn't have a charge system.

Example Usage

local fire_blast = izi.spell(108853)

izi.printf("Fire Blast: %d/%d charges", fire_blast:charges(), fire_blast:max_charges())

charges_info​
Syntax
spell:charges_info(): charge_info

Returns
current: integer - Current number of charges
maximum: integer - Maximum number of charges
start_ms: integer - Recharge start time in milliseconds
duration_ms: integer - Recharge duration in milliseconds
mod_rate: number - Recharge rate modifier
Description

Returns detailed information about the spell's charge system, including timing data for charge regeneration.

Example Usage

local fire_blast = izi.spell(108853)

local cur, max, start_ms, duration_ms, mod_rate = fire_blast:charges_info()

izi.printf("Charges: %d/%d, Recharge: %dms", cur, max, duration_ms)

charges_fractional​
Syntax
spell:charges_fractional(recharge_ms?: number): number


Parameters

recharge_ms?: number - Optional override for recharge time in milliseconds
Returns
number - Fractional charge count (e.g., 1.5 means 1 charge + 50% progress to next)
Description

Returns the current charge count including fractional progress towards the next charge. Useful for precise timing decisions.

Example Usage

local fire_blast = izi.spell(108853)

local fractional = fire_blast:charges_fractional()

izi.printf("Fire Blast charges: %.2f", fractional)  -- Output: "Fire Blast charges: 1.75"

recharge​
Syntax
spell:recharge(): number

Returns
number - Time in seconds until next charge is available
Description

Returns the time remaining until the next charge becomes available. Returns 0 if the spell is at max charges or doesn't use charges.

Example Usage

local fire_blast = izi.spell(108853)

local recharge_time = fire_blast:recharge()

if recharge_time > 0 then

    izi.printf("Next charge in %.1f seconds", recharge_time)

end

cooldown_remains​
Aliases
cooldown
Syntax
spell:cooldown_remains(): number

spell:cooldown(): number

Returns
number - Time in seconds remaining on cooldown
Description

Returns the remaining cooldown time in seconds. Returns 0 if the spell is not on cooldown.

Example Usage

local combustion = izi.spell(190319)

local cd = combustion:cooldown_remains()

if cd > 0 then

    izi.printf("Combustion ready in %.1f seconds", cd)

end

cooldown_up​
Syntax
spell:cooldown_up(): boolean

Returns
boolean - True if the spell is ready (not on cooldown)
Description

Returns true if the spell is not on cooldown and can be cast (cooldown-wise). This is the opposite of cooldown_down().

Example Usage

local combustion = izi.spell(190319)

if combustion:cooldown_up() then

    izi.print("Combustion is ready!")

end

cooldown_down​
Syntax
spell:cooldown_down(): boolean

Returns
boolean - True if the spell is on cooldown
Description

Returns true if the spell is currently on cooldown. This is the opposite of cooldown_up().

Example Usage

local combustion = izi.spell(190319)

if combustion:cooldown_down() then

    izi.print("Combustion is on cooldown")

end

get_gcd​
Syntax
spell:get_gcd(): number

Returns
number - The global cooldown duration in seconds
Description

Returns the global cooldown (GCD) duration that will be triggered when this spell is cast.

Example Usage

local fireball = izi.spell(133)

izi.printf("Fireball GCD: %.2f seconds", fireball:get_gcd())

skips_gcd​
Syntax
spell:skips_gcd(): boolean

Returns
boolean - True if the spell doesn't trigger GCD
Description

Returns true if the spell can be cast without triggering the global cooldown. Off-GCD spells can be used between other abilities.

Example Usage

local fire_blast = izi.spell(108853)

if fire_blast:skips_gcd() then

    izi.print("Fire Blast is off-GCD!")

end

is_usable_while_moving​
Syntax
spell:is_usable_while_moving(): boolean

Returns
boolean - True if the spell can be cast while moving
Description

Returns true if the spell can be cast while the player is moving. Instant cast spells typically return true.

Example Usage

local scorch = izi.spell(2948)

if scorch:is_usable_while_moving() then

    izi.print("Scorch can be cast while moving")

end

requires_back​
Syntax
spell:requires_back(): boolean

Returns
boolean - True if the spell requires positioning behind the target
Description

Returns true if the spell requires the player to be behind the target to cast (e.g., Backstab, Ambush).

Example Usage

local backstab = izi.spell(53)

if backstab:requires_back() then

    izi.print("Need to be behind target for Backstab")

end

since_last_cast​
Syntax
spell:since_last_cast(): number

Returns
number - Time in seconds since the spell was last cast
Description

Returns the time elapsed since this spell was last queued to cast. Useful for tracking spell usage patterns.

Example Usage

local fireball = izi.spell(133)

local time_since = fireball:since_last_cast()

izi.printf("Last Fireball cast: %.1f seconds ago", time_since)

in_gcd_window​
Syntax
spell:in_gcd_window(threshold?: number): boolean


Parameters

threshold?: number - Optional threshold in seconds (default varies by implementation)
Returns
boolean - True if within the GCD window
Description

Returns true if the current time is within the GCD window, allowing for predictive spell queueing. The threshold parameter allows customization of the timing window.

Example Usage

local fireball = izi.spell(133)

if fireball:in_gcd_window(0.3) then

    izi.print("Can queue next spell")

end

in_recharge​
Syntax
spell:in_recharge(): boolean

Returns
boolean - True if the spell is currently recharging
Description

Returns true if the spell is currently recharging a charge. Only applicable to spells with charge systems.

Example Usage

local fire_blast = izi.spell(108853)

if fire_blast:in_recharge() then

    izi.print("Fire Blast is recharging")

end

has_charges_at​
Syntax
spell:has_charges_at(t?: number): boolean


Parameters

t?: number - Optional time in the future (seconds from now) to check
Returns
boolean - True if charges will be available at the specified time
Description

Returns true if the spell will have at least one charge available at the specified time. If no time is provided, checks current availability.

Example Usage

local fire_blast = izi.spell(108853)

if fire_blast:has_charges_at(2.5) then

    izi.print("Fire Blast will have a charge in 2.5 seconds")

end

track_debuff​
Syntax
spell:track_debuff(spec: (number|number[])|nil): izi_spell


Parameters

spec: (number|number[])|nil - Debuff ID(s) to track, or nil to track the spell's own ID
Returns
izi_spell - Returns self for method chaining
Description

Configures the spell to track specific debuff IDs on targets. Useful when a spell applies a debuff with a different ID than the spell itself. Pass nil to track the spell's own ID.

Example Usage

local immolate = izi.spell(348)

local immolate_debuff_id = 157736 -- Immolate's debuff is different than its spell ID



-- Track the Immolate debuff (different ID than cast spell)

-- This will allow other helper functions such as izi.spread_dot track the debuffs for this DOT approprietly

immolate:track_debuff(immolate_debuff_id)

track_buff​
Syntax
spell:track_buff(spec: (number|number[])|nil): izi_spell


Parameters

spec: (number|number[])|nil - Buff ID(s) to track, or nil to track the spell's own ID
Returns
izi_spell - Returns self for method chaining
Description

Configures the spell to track specific buff IDs. Useful when a spell applies a buff with a different ID than the spell itself. Pass nil to track the spell's own ID.

Example Usage

-- Track multiple possible buff variants

local heroism = izi.spell(32182)

heroism:track_buff({ heroism:id(), 2825, 80353 })

get_tracked_debuff_spec​
Syntax
spell:get_tracked_debuff_spec(): number|number[]

Returns
number|number[] - The debuff ID(s) currently being tracked
Description

Returns the debuff ID specification that this spell is currently tracking. Returns either a single ID or an array of IDs.

Example Usage

local immolate = izi.spell(348)

immolate:track_debuff(157736)



local tracked = immolate:get_tracked_debuff_spec()

izi.printf("Tracking debuff ID: %d", tracked)

get_tracked_buff_spec​
Syntax
spell:get_tracked_buff_spec(): number|number[]

Returns
number|number[] - The buff ID(s) currently being tracked
Description

Returns the buff ID specification that this spell is currently tracking. Returns either a single ID or an array of IDs.

Example Usage

local bloodlust = izi.spell(2825)

bloodlust:track_buff(2825)



local tracked = bloodlust:get_tracked_buff_spec()

izi.printf("Tracking buff ID: %d", tracked)

Casting​
is_castable​
Syntax
spell:is_castable(opts?: cast_opts): boolean


Parameters

opts?: cast_opts - Optional casting options to customize validation checks
Returns
boolean - True if the spell can be cast
Description

Checks if the spell is castable right now based on basic validation criteria like charges, learned status, usability, player state (moving, mounted, casting, channeling), and positional requirements. This method performs general castability checks without requiring a target or position.

Example Usage

local fireball = izi.spell(133)



-- Basic castability check

if fireball:is_castable() then

    izi.print("Fireball can be cast")

end



-- Skip certain checks

if fireball:is_castable({ skip_moving = true }) then

    izi.print("Fireball can be cast (ignoring movement)")

end



-- Skip multiple checks

if fireball:is_castable({

    skip_moving = true,

    skip_casting = true

}) then

    izi.print("Fireball can be cast (ignoring movement and casting state)")

end

is_castable_to_unit​
Syntax
spell:is_castable_to_unit(target?: game_object, opts?: unit_cast_opts): boolean


Parameters

target?: game_object - Optional target unit (defaults to current target if not provided)
opts?: unit_cast_opts - Optional casting options to customize validation checks
Returns
boolean - True if the spell can be cast on the target unit
Description

Checks if the spell can be cast on a specific unit target. This method performs all basic castability checks plus unit-specific validation like facing requirements, range checks, and target-specific conditions. If no target is provided, it uses the player's current target.

Example Usage

local frostbolt = izi.spell(116)

local target = izi.target()



-- Check if we can cast on current target

if frostbolt:is_castable_to_unit() then

    izi.print("Can cast Frostbolt on target")

end



-- Check if we can cast on a specific unit

local enemy = izi.enemies(40)[1]

if enemy and frostbolt:is_castable_to_unit(enemy) then

    izi.print("Can cast Frostbolt on enemy")

end



-- Skip facing requirement

if frostbolt:is_castable_to_unit(target, { skip_facing = true }) then

    izi.print("Can cast (ignoring facing)")

end



-- Skip range and GCD checks

if frostbolt:is_castable_to_unit(target, {

    skip_range = true,

    skip_gcd = true

}) then

    izi.print("Can cast (ignoring range and GCD)")

end

is_castable_to_position​
Syntax
spell:is_castable_to_position(target?: game_object, cast_pos?: vec3, opts?: pos_cast_opts): boolean


Parameters

target?: game_object - Optional context target (defaults to current target or self)
cast_pos?: vec3 - Optional cast position (if nil, uses target's position)
opts?: pos_cast_opts - Optional casting options including prediction settings
Returns
boolean - True if the spell can be cast at the position
Description

Checks if the spell can be cast at a specific ground position. This method performs all castability checks plus position-specific validation like range to position, line of sight, and optional prediction calculations for optimal AoE placement. Ideal for ground-targeted spells, AoE abilities, and skillshots.

Example Usage

local blizzard = izi.spell(190356)

local target = izi.target()



-- Check if we can cast at target's position

if blizzard:is_castable_to_position(target) then

    izi.print("Can cast Blizzard at target location")

end



-- Check if we can cast at a specific position

local custom_pos = vec3(100, 100, 0)

if blizzard:is_castable_to_position(nil, custom_pos) then

    izi.print("Can cast at custom position")

end



-- Use prediction to find optimal position

if blizzard:is_castable_to_position(target, nil, {

        use_prediction = true,

        prediction_type = "MOST_HITS",

        min_hits = 3

    }) then

    izi.print("Can cast with optimal prediction for 3+ hits")

end



-- Custom AoE radius and geometry

if blizzard:is_castable_to_position(target, nil, {

        geometry = "CIRCLE",

        aoe_radius = 10,

        check_los = true

    }) then

    izi.print("Can cast with custom radius and LOS check")

end



-- Override cast time and projectile speed

if blizzard:is_castable_to_position(target, nil, {

        cast_time = 2000,  -- 2 seconds in milliseconds

        projectile_speed = 20, -- 20 game units/sec

        use_prediction = true

    }) then

    izi.print("Can cast with custom timing values")

end

cast​
Syntax
spell:cast(target?: game_object, message?: string, opts?: pos_cast_opts): boolean, izi_cast_meta


Parameters

target?: game_object - Optional target unit (defaults to player target or self)
message?: string - Optional message to display in the queue
opts?: pos_cast_opts - Optional position cast options (only used for positional spells; ignored for targeted spells)
Returns
boolean - True if the spell was successfully queued to cast
izi_cast_meta - Metadata about the cast attempt
Description

Casts the spell on a target or at a position. For positional spells, the opts parameter enables prediction, geometry customization, and other advanced features. For targeted spells, opts is ignored and standard safety checks should be handled via cast_safe() instead.

Example Usage

local fireball = izi.spell(133)

local blizzard = izi.spell(190356)

local target = izi.target()



-- Cast on target

if fireball:cast(target) then

    izi.print("Cast Fireball!")

end



-- Cast with custom message

if fireball:cast(target, "Fireball on primary target") then

    izi.print("Queued Fireball")

end



-- Cast positional spell with prediction

if blizzard:cast(target, "Blizzard AoE",

        {

            use_prediction = true,

            prediction_type = "MOST_HITS",

            min_hits = 3

        }) then

    izi.print("Cast Blizzard at optimal position")

end



-- Cast positional spell with custom geometry

if blizzard:cast(target, nil,

        {

            geometry = "CIRCLE",

            aoe_radius = 10,

            check_los = true

        }) then

    izi.print("Cast Blizzard with custom radius")

end

cast_safe​
Syntax
spell:cast_safe(target?: game_object, message?: string, opts?: unit_cast_opts|pos_cast_opts): boolean, izi_cast_meta


Parameters

target?: game_object - Optional target unit (defaults to player target or self)
message?: string - Optional message to display in the queue
opts?: unit_cast_opts|pos_cast_opts - Optional casting options with full safety checks
Returns
boolean - True if the spell was successfully queued to cast
izi_cast_meta - Metadata about the cast attempt
Description

Safe casting with full validation gates including facing, range, GCD, and other checks. For positional spells, also supports prediction and line of sight validation via opts. This method performs comprehensive safety checks before casting, making it ideal for production rotations.

Example Usage

local frostbolt = izi.spell(116)

local blizzard = izi.spell(190356)

local target = izi.target()



-- Safe cast on target with full validation

if frostbolt:cast_safe(target) then

    izi.print("Safely cast Frostbolt")

end



-- Safe cast with custom message and skip some checks

if frostbolt:cast_safe(target, "Frostbolt priority",

        {

            skip_facing = true,

            skip_moving = true

        }) then

    izi.print("Cast Frostbolt (skipped facing and movement)")

end



if blizzard:cast_safe(target, "Blizzard optimal",

        {

            use_prediction = true,

            prediction_type = "MOST_HITS",

            min_hits = 3,

            check_los = true

        }) then

    izi.print("Safely cast Blizzard with prediction")

end

cast_target_if​
Syntax
spell:cast_target_if(

    units: game_object[],

    mode: sort_mode,

    filter: fun(u: game_object): number|nil,

    adv_condition?: boolean|fun(u: game_object): boolean|nil,

    another_condition?: boolean,

    max_attempts?: integer,

    message?: string

): boolean, izi_cast_meta


Parameters

units: game_object[] - Array of units to evaluate
mode: sort_mode - "max" for highest score, "min" for lowest score
filter: fun(u: game_object): number|nil - Scoring function; return nil to exclude unit
adv_condition?: boolean|fun(u: game_object): boolean|nil - Optional advanced condition per unit or global boolean
another_condition?: boolean - Optional global veto condition (early exit if false)
max_attempts?: integer - Maximum number of units to try (default: 3)
message?: string - Optional queue message
Returns
boolean - True if the spell was successfully cast on a target
izi_cast_meta - Metadata about the cast attempt
Description

Ranks units by the scoring function in descending order for "max" mode or ascending for "min" mode, then attempts to cast on the top N units using the raw cast() method (no safety gates). Uses an internal blacklist to avoid repeatedly trying failed targets. This is a performance-optimized method for target selection.

Note: This method does not accept opts parameter and performs minimal validation.

Example Usage

local fireball = izi.spell(133)

local enemies = izi.enemies(40)



-- Cast on enemy with lowest health

if fireball:cast_target_if(enemies, "min", function(u) return u:get_health_percentage() end) then

    izi.print("Cast Fireball on lowest HP enemy")

end



-- Cast on enemy with highest health, with conditions

if fireball:cast_target_if(

        enemies,

        "max",

        function(u) return u:get_health_percentage() end,

        function(u) return not u:is_casting() end, -- Skip casting enemies

        true,                                      -- Global condition

        5,                                         -- Try up to 5 targets

        "Fireball max HP"

    ) then

    izi.print("Cast Fireball on highest HP non-casting enemy")

end



-- Cast on enemy furthest away

if fireball:cast_target_if(enemies, "max", function(u) return u:distance() end, nil, true, 3, "Fireball distant target") then

    izi.print("Cast on furthest enemy")

end

cast_target_if_safe​
Syntax
spell:cast_target_if_safe(

    units: game_object[],

    mode: sort_mode,

    filter: fun(u: game_object): number|nil,

    adv_condition?: boolean|fun(u: game_object): boolean|nil,

    another_condition?: boolean,

    max_attempts?: integer,

    message?: string,

    opts?: unit_cast_opts|pos_cast_opts

): boolean, izi_cast_meta


Parameters

units: game_object[] - Array of units to evaluate
mode: sort_mode - "max" for highest score, "min" for lowest score
filter: fun(u: game_object): number|nil - Scoring function; return nil to exclude unit
adv_condition?: boolean|fun(u: game_object): boolean|nil - Optional advanced condition per unit or global boolean
another_condition?: boolean - Optional global veto condition (early exit if false)
max_attempts?: integer - Maximum number of units to try (default: 3)
message?: string - Optional queue message
opts?: unit_cast_opts|pos_cast_opts - Optional casting options with full safety checks
Returns
boolean - True if the spell was successfully cast on a target
izi_cast_meta - Metadata about the cast attempt
Description

Same as cast_target_if() but uses cast_safe() internally and forwards the opts parameter for full validation gates including facing, range, GCD, and other safety checks. This is the recommended method for production rotations that need smart target selection with comprehensive validation.

Example Usage

local fireball = izi.spell(133)

local enemies = izi.enemies(40)



-- Cast on enemy with lowest health

if fireball:cast_target_if_safe(enemies, "min", function(u) return u:get_health_percentage() end) then

    izi.print("Cast Fireball on lowest HP enemy")

end



-- Cast on enemy with highest health, with conditions

if fireball:cast_target_if_safe(

        enemies,

        "max",

        function(u) return u:get_health_percentage() end,

        function(u) return not u:is_casting() end, -- Skip casting enemies

        true,                                      -- Global condition

        5,                                         -- Try up to 5 targets

        "Fireball max HP"

    ) then

    izi.print("Cast Fireball on highest HP non-casting enemy")

end



-- Cast on enemy furthest away

if fireball:cast_target_if_safe(enemies, "max", function(u) return u:distance() end, nil, true, 3, "Fireball distant target") then

    izi.print("Cast on furthest enemy")

end

cast_defensive​
Syntax
spell:cast_defensive(

    target: game_object,

    filters?: defensive_filters,

    message?: string,

    opts?: unit_cast_opts

): boolean


Parameters

target: game_object - The target to cast the defensive spell on
filters?: defensive_filters - Optional filters table to decide if the cast should proceed
message?: string - Optional custom message for the action queue
opts?: unit_cast_opts - Optional casting options that are forwarded to cast_safe
Returns
boolean - True if the spell was successfully cast, false otherwise
Description

Casts this spell as a defensive on self with extra filters to decide if the cast should proceed. Prevents casting more than one defensive within the block time. This is a convenience method that wraps izi.cast_defensive() for use directly on spell objects.

Example Usage

local ice_block = izi.spell(45438)  -- Mage Ice Block

local player = izi.get_player()



-- Cast Ice Block with custom health thresholds

local filters = {

    block_time = 2,                                  -- Block further defensives for 2 seconds

    health_percentage_threshold_raw = 25,            -- Cast if current HP <= 25%

    health_percentage_threshold_incoming = 20,       -- Cast if forecasted HP <= 20%

}



if ice_block:cast_defensive(player, filters, "Emergency Ice Block!") then

    izi.print("Ice Block activated!")

end



-- Simple usage with default filters

local divine_protection = izi.spell(498)  -- Paladin Divine Protection

if divine_protection:cast_defensive(player) then

    izi.print("Divine Protection activated!")

end



-- With damage type filters

local anti_magic_shell = izi.spell(48707)  -- DK Anti-Magic Shell

local magic_filters = {

    health_percentage_threshold_raw = 60,

    magical_damage_percentage_threshold = 50,  -- Only cast if 50%+ incoming damage is magical

}

if anti_magic_shell:cast_defensive(player, magic_filters, "AMS vs Magic") then

    izi.print("Anti-Magic Shell activated against heavy magic damage!")

end

Types​
cast_opts​

Fields

skip_charges?: boolean - Skip spell charge validation
skip_learned?: boolean - Skip spell learned validation
skip_usable?: boolean - Skip spell usable validation
skip_back?: boolean - Skip target behind validation (validated in is_castable_to_unit)
skip_moving?: boolean - Skip moving validation
skip_mount?: boolean - Skip mount validation
skip_casting?: boolean - Skip casting state validation
skip_channeling?: boolean - Skip channeling state validation
Description

Options for customizing spell casting validation. These flags allow you to bypass specific validation checks when determining if a spell can be cast. Useful for basic spell validation without target or position requirements.

unit_cast_opts​

Fields

skip_facing?: boolean - Skip facing requirement validation
skip_range?: boolean - Skip range validation
skip_usable?: boolean - Skip spell usable validation
skip_gcd?: boolean - Skip global cooldown validation
skip_learned?: boolean - Skip spell learned validation
skip_charges?: boolean - Skip spell charge validation
skip_back?: boolean - Skip target behind validation
skip_moving?: boolean - Skip moving validation
skip_mount?: boolean - Skip mount validation
skip_casting?: boolean - Skip casting state validation
skip_channeling?: boolean - Skip channeling state validation
Description

Options for customizing spell casting validation when targeting a unit. Extends basic cast options with additional unit-specific checks like facing and range requirements. Use these flags to bypass specific validation checks when casting spells on a target.

pos_cast_opts​

Fields

skip_facing?: boolean - Skip facing requirement validation
skip_range?: boolean - Skip range validation
skip_usable?: boolean - Skip spell usable validation
skip_gcd?: boolean - Skip global cooldown validation
skip_learned?: boolean - Skip spell learned validation
skip_charges?: boolean - Skip spell charge validation
skip_moving?: boolean - Skip moving validation
skip_mount?: boolean - Skip mount validation
skip_casting?: boolean - Skip casting state validation
skip_channeling?: boolean - Skip channeling state validation
check_los?: boolean - Enable line of sight validation
use_prediction?: boolean - Enable position prediction (default: true for position casts)
prediction_type?: prediction_type - Prediction algorithm: "auto" | "ACCURACY" | "MOST_HITS" | number
geometry?: geometry_type - Spell geometry: "CIRCLE" | "LINE" | number
aoe_radius?: number - Override the default AoE radius
min_hits?: integer - Minimum required hits (default: 1)
source_position?: vec3 - Custom origin point for prediction calculations
cast_time?: number - Override cast time in milliseconds (skips SDK lookup)
projectile_speed?: number - Override projectile speed in game units/sec (0 = instant)
is_heal?: boolean - Prediction becomes for allies instead of enemies
use_intersection?: boolean - Use intersection position instead of center (for accuracy type)
max_range?: number - Override the maximum range
Description

Advanced options for position-based spell casting with support for prediction and geometry customization. This type extends unit cast options with additional fields for controlling spell prediction algorithms, geometry shapes, and AoE calculations. Ideal for ground-targeted spells and skillshots that require precise positioning and hit detection.

izi_cast_meta​

Fields

cast_position?: vec3 - Set if a skillshot was queued
hit_time?: number - Cast time plus projectile travel, if available
predicted?: boolean - True if position came from prediction
hits?: integer - Predicted amount of hits, if available
prediction_meta?: table - Raw prediction block from _compute_cast_position
target?: game_object - Target for targeted casts
unit?: game_object - Candidate unit for *_target_if helpers
rank_index?: integer - Index chosen in ranked lists
attempted?: integer - How many candidates were attempted
reason?: string - Failure reason code on false
err?: string - Optional lower level error string
Description

Metadata returned from spell casting operations. This type provides detailed information about the cast attempt, including prediction data, targeting information, and diagnostic details for failed casts. Useful for debugging spell behavior and understanding why a cast succeeded or failed.

---

## https://docs.project-sylvanas.net/dev/libraries/izi/item

IZI - Item (izi_item)
Overview​

The IZI Item system provides a streamlined object-oriented interface for item management and usage in World of Warcraft. Instead of manually tracking item IDs, cooldowns, and charges, you create item objects that encapsulate all the functionality needed for intelligent item usage.

Key Features:

Smart Usage - Automatic validation of cooldowns, charges, usability, and inventory status
Flexible Validation - Fine-grained control over which checks to skip or enforce via usage options
Cooldown Management - Query remaining cooldowns, charges, and item readiness states
Inventory Awareness - Automatic detection of equipped and bag items
Charge Tracking - Monitor item charges with fractional charge support
Resource Detection - Determine if items are equipped or available in bags
LOS Validation - Built-in line-of-sight checks for targeted item usage

Whether you're managing trinkets, consumables, or utility items, the izi_item class eliminates boilerplate code and provides a consistent, intuitive interface for all your item usage needs. Create an item object once, then use its methods throughout your code for clean, maintainable item management.

Creating a new Item​
izi.item​
Syntax
-- Single item ID

izi.item(id: integer)


Parameters

id: integer - A single item ID to create an item object for
Returns
izi_item - A new item object with built-in usage utilities and validation methods
Description

Creates a new item object that encapsulates all the functionality needed for intelligent item usage. The item object provides methods for using items, validation, cooldown checking, charge tracking, and inventory detection.

You provide a single item ID to create the item object. The object will automatically track whether the item is equipped or in your bags and provide appropriate usage methods.

Example Usage

local izi = require("common/izi_sdk")



-- Create an item for a trinket

local trinket = izi.item(178742)  -- Some on use trinket



-- Create an item for a consumable

local health_potion = izi.item(171267)  -- Spiritual Healing Potion



-- Create an item for a utility item

local bandage = izi.item(172059)  -- Heavy Shrouded Cloth Bandage



-- Use the item object

if trinket:use() then

    izi.print("Used trinket!")

end



-- Check if item is ready to use

if health_potion:is_usable() then

    izi.print("Health potion is ready!")

end



-- Get cooldown information

local cd_remaining = trinket:cooldown()

izi.printf("Trinket cooldown: %.1f seconds", cd_remaining)

Methods​

Once you've created an izi_item object, you can call the following methods to interact with and query the item:

id​
Syntax
item:id(): integer

Returns
integer - The item ID
Description

Returns the item ID that this item object represents.

Example Usage

local trinket = izi.item(178742)

izi.printf("Item ID: %d", trinket:id())  -- Output: "Item ID: 178742"

name​
Syntax
item:name(): string

Returns
string - The item name
Description

Returns the name of the item from the game's item database.

Example Usage

local trinket = izi.item(178742)

izi.printf("Item name: %s", trinket:name())  -- Output: "Item name: Bottled Flayedwing Toxin"

object​
Syntax
item:object(): game_object|nil

Returns
game_object|nil - The game object representing the equipped item, or nil if not equipped
Description

Returns the game object for the item if it is currently equipped. Returns nil if the item is not equipped or not found.

Example Usage

local trinket = izi.item(178742)

local obj = trinket:object()

if obj then

    izi.print("Trinket is equipped")

end

equipped_slot​
Syntax
item:equipped_slot(): integer|nil

Returns
integer|nil - The equipment slot number, or nil if not equipped
Description

Returns the equipment slot number where the item is equipped, or nil if the item is not currently equipped.

Example Usage

local trinket = izi.item(178742)

local slot = trinket:equipped_slot()

if slot then

    izi.printf("Trinket equipped in slot: %d", slot)

end

equipped​
Syntax
item:equipped(): boolean

Returns
boolean - True if the item is equipped
Description

Returns true if the item is currently equipped on the player.

Example Usage

local trinket = izi.item(178742)

if trinket:equipped() then

    izi.print("Trinket is equipped")

end

count​
Syntax
item:count(): integer

Returns
integer - The number of items in inventory
Description

Returns the total count of this item in the player's inventory (bags).

Example Usage

local health_potion = izi.item(171267)

izi.printf("Health potions: %d", health_potion:count())

in_inventory​
Syntax
item:in_inventory(): boolean

Returns
boolean - True if the item is in inventory
Description

Returns true if the item is present in the player's inventory (bags).

Example Usage

local health_potion = izi.item(171267)

if health_potion:in_inventory() then

    izi.print("Health potion available in bags")

end

is_usable​
Syntax
item:is_usable(): boolean

Returns
boolean - True if the item is usable
Description

Returns true if the item can be used right now, considering factors like cooldown, equipped status, and player state.

Example Usage

local trinket = izi.item(178742)

if trinket:is_usable() then

    izi.print("Trinket is ready to use")

end

cooldown_remains​
Aliases
cooldown
Syntax
item:cooldown_remains(): number

item:cooldown(): number

Returns
number - Time in seconds remaining on cooldown
Description

Returns the remaining cooldown time in seconds. Returns 0 if the item is not on cooldown.

Example Usage

local trinket = izi.item(178742)

local cd = trinket:cooldown_remains()

if cd > 0 then

    izi.printf("Trinket ready in %.1f seconds", cd)

else

    izi.print("Trinket is ready!")

end

cooldown_up​
Syntax
item:cooldown_up(): boolean

Returns
boolean - True if the item is ready (not on cooldown)
Description

Returns true if the item is not on cooldown and can be used (cooldown-wise).

Example Usage

local trinket = izi.item(178742)

if trinket:cooldown_up() then

    izi.print("Trinket is ready!")

end

has_range​
Syntax
item:has_range(): boolean

Returns
boolean - True if the item has a range requirement
Description

Returns true if the item has a range requirement for usage (i.e., it can be used on targets at a distance).

Example Usage

local item = izi.item(12345)

if item:has_range() then

    izi.print("This item can be used at range")

end

is_in_range​
Syntax
item:is_in_range(target?: game_object): boolean


Parameters

target?: game_object - Optional target unit (defaults to current target if not provided)
Returns
boolean - True if the target is in range
Description

Returns true if the specified target (or current target) is within range for using the item. If the item has no range requirement, always returns true.

Example Usage

local trinket = izi.item(178742)

local target = izi.target()

if trinket:is_in_range(target) then

    izi.print("Target is in range for trinket")

end

use_self​
Syntax
item:use_self(message?: string, fast?: boolean): boolean


Parameters

message?: string - Optional message to display in the queue
fast?: boolean - Optional flag for fast usage mode (off GCD) (default: false)
Returns
boolean - True if the item was successfully queued to use
Description

Uses the item on the player. This is a basic usage method without extensive validation gates.

Example Usage

local health_potion = izi.item(171267)



-- Use potion on self

if health_potion:use_self() then

    izi.print("Used health potion!")

end



-- Use with custom message

if health_potion:use_self("Emergency healing") then

    izi.print("Used health potion")

end

use_on​
Syntax
item:use_on(target?: game_object, message?: string, fast?: boolean): boolean


Parameters

target?: game_object - Optional target unit (defaults to current target if not provided)
message?: string - Optional message to display in the queue
fast?: boolean - Optional flag for fast usage mode (off GCD) (default: false)
Returns
boolean - True if the item was successfully queued to use
Description

Uses the item on a target. This is a basic usage method without extensive validation gates.

Example Usage

local trinket = izi.item(178742)

local target = izi.target()



-- Use on target

if trinket:use_on(target) then

    izi.print("Used trinket on target!")

end



-- Use with custom message

if trinket:use_on(target, "Trinket on boss") then

    izi.print("Used trinket")

end

use_at_position​
Syntax
item:use_at_position(position: vec3, message?: string, fast?: boolean): boolean


Parameters

position: vec3 - The position to use the item at
message?: string - Optional message to display in the queue
fast?: boolean - Optional flag for fast usage mode (off GCD) (default: false)
Returns
boolean - True if the item was successfully queued to use
Description

Uses the item at a specific ground position. This is a basic usage method without extensive validation gates.

Example Usage

local item = izi.item(12345)

local pos = vec3(100, 100, 0)



-- Use at position

if item:use_at_position(pos) then

    izi.print("Used item at position!")

end



-- Use with custom message

if item:use_at_position(pos, "Item placement") then

    izi.print("Used item")

end

use_self_safe​
Syntax
item:use_self_safe(message?: string, opts?: item_use_opts): boolean


Parameters

message?: string - Optional message to display in the queue
opts?: item_use_opts - Optional usage options with full safety checks
Returns
boolean - True if the item was successfully queued to use
Description

Safe usage method that uses the item on the player with full validation gates including usability, cooldown, movement state, and other checks. This is the recommended method for production use.

Example Usage

local health_potion = izi.item(171267)



-- Safe use on self with full validation

if health_potion:use_self_safe() then

    izi.print("Safely used health potion!")

end



-- Safe use with custom message and skip some checks

if health_potion:use_self_safe("Emergency heal", {

    skip_moving = true,

    skip_casting = true

}) then

    izi.print("Used health potion (skipped movement/casting checks)")

end

use_on_safe​
Syntax
item:use_on_safe(target?: game_object, message?: string, opts?: item_use_opts): boolean


Parameters

target?: game_object - Optional target unit (defaults to current target if not provided)
message?: string - Optional message to display in the queue
opts?: item_use_opts - Optional usage options with full safety checks
Returns
boolean - True if the item was successfully queued to use
Description

Safe usage method that uses the item on a target with full validation gates including usability, cooldown, range, and other checks. This is the recommended method for production use.

Example Usage

local trinket = izi.item(178742)

local target = izi.target()



-- Safe use on target with full validation

if trinket:use_on_safe(target) then

    izi.print("Safely used trinket on target!")

end



-- Safe use with custom message and skip some checks

if trinket:use_on_safe(target, "Trinket on boss", {

    skip_range = true,

    skip_gcd = true

}) then

    izi.print("Used trinket (skipped range/GCD checks)")

end



-- Use with LOS check enabled

if trinket:use_on_safe(target, nil, {

    check_los = true

}) then

    izi.print("Used trinket with LOS validation")

end

use_at_position_safe​
Syntax
item:use_at_position_safe(target?: game_object, position: vec3, message?: string, opts?: item_use_opts): boolean


Parameters

target?: game_object - Optional context target for validation
position: vec3 - The position to use the item at
message?: string - Optional message to display in the queue
opts?: item_use_opts - Optional usage options with full safety checks
Returns
boolean - True if the item was successfully queued to use
Description

Safe usage method that uses the item at a position with full validation gates including usability, cooldown, range to position, and other checks. This is the recommended method for production use with ground-targeted items.

Example Usage

local item = izi.item(12345)

local target = izi.target()

local pos = vec3(100, 100, 0)



-- Safe use at position with full validation

if item:use_at_position_safe(target, pos) then

    izi.print("Safely used item at position!")

end



-- Safe use with custom message and options

if item:use_at_position_safe(target, pos, "Item placement", {

    check_los = true,

    skip_moving = true

}) then

    izi.print("Used item at position with LOS check")

end

Types​
item_use_opts​

Fields

skip_usable?: boolean - Skip item usable validation
skip_cooldown?: boolean - Skip cooldown validation
skip_range?: boolean - Skip range validation
skip_moving?: boolean - Skip moving validation
skip_mount?: boolean - Skip mount validation
skip_casting?: boolean - Skip casting state validation
skip_channeling?: boolean - Skip channeling state validation
skip_gcd?: boolean - Skip global cooldown validation
check_los?: boolean - Enable line of sight validation
Description

Options for customizing item usage validation. These flags allow you to bypass specific validation checks when determining if an item can be used. Use these flags to fine-tune item usage behavior and skip unnecessary checks for specific use cases.

---

## https://docs.project-sylvanas.net/dev/libraries/spell-prediction

Spell Prediction
Overview​

The spell_prediction module provides functions and utilities for predicting spell cast positions and determining optimal targets based on different prediction methods and geometries. This is a module that we provide to you, however we are basically using the geometry library and some math, so you could always try to make your own prediction and differentiate yourself from others.



Importing The Module​
WARNING

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the require function and store it in a local variable.

Here is an example of how to do it:

-- recomended "spell_prediction" name for consistency

---@type spell_prediction

local spell_prediction = require("common/modules/spell_prediction")

Using the Prediction Playground

In the main menu you will see that there is a "Prediction Playground" tree node. This plugin is multi-purpose. Firstly, it offers a visual way to see how prediction works, and on the other hand it will allow you to determine the accurate spell data of some spells.

This is what you should be seeing upon opening the tree node:


Available Options - Brief Explanation

1- Source: Where the spell will be launched from.
2- Target: Where the spell will arrive.
3- Type: The prediction mode. The position output will be either the best possible position to hit the main target, if type is "Accuracy" or the best possible position to hit the most targets, if type is "Most Hits".
4- Geometry: The geometry type.
5- Radius: The radius of the debug spell.
6- Range: The range of the debug spell.
7- Angle: The angle of the cone. (Make sure the spell geometry is set to "Cone")
8- Cast Time: The cast time of the debug spell.
9- Projectile Speed: The projectile speed. Leave to 0 since Blizzard doesn't care about projectiles apparently.
10- Override Hit Time: Option to override the calculated hit time. If 0.0, no override happens.
11- Override Hitbox Min: Option to override the hitbox min radius of the target. If 0.0, no override happens.
12- Draw Hits Amount: Option to draw the calculated amount of hits, with the given spell data. (Red text)
13- Draw Hits Amount: Option to draw a circle on the calculated hits positions, with the given spell data. (Blue circle)
14- Cache Slider: The refresh rate of the spell result cache.


As you can see, this is a powerful tool to retrieve the correct spell datas too, since you can check when you are hitting the targets with accuracy, at the given spell data.

NOTE

This plugin will be open source, for anyone to check its code and play with it.

Enums 🧮​
prediction_type​

Defines the prediction mode for the spell.

ACCURACY: Accuracy-based prediction.
MOST_HITS: Prediction to hit the maximum number of targets.
geometry_type​

Defines the geometry type of the spell's area of effect.

CIRCLE: Circular area.
RECTANGLE: Rectangular area.
CONE: Conical area.
Data Types 📊​
spell_data​

A table containing the following fields:

spell_id (number) — The ID of the spell.
max_range (number) — The maximum range of the spell.
radius (number) — The radius of the spell's area of effect.
cast_time (number) — The cast time of the spell.
projectile_speed (number) — The speed of the spell's projectile.
prediction_mode (prediction_type) — The prediction mode for the spell.
geometry_type (geometry_type) — The geometry type of the spell's area of effect.
source_position (vec3) — The source position of the spell.
intersection_factor (number) — The intersection factor for the spell.
angle (number) — The angle of the spell's area of effect (for cones).
exception_is_heal (boolean) — Whether the spell is a healing spell.
exception_player_included (boolean) — Whether to include the player in the spell's effect.
hitbox_min (number) — The minimum hitbox radius.
hitbox_max (number) — The maximum hitbox radius.
hitbox_mult (number) — The hitbox multiplier.
time_to_hit_override (number) — The override value for time to hit.
hit_data​

A table containing the following fields:

obj (game_object) — The game_object of the unit.
center_position (vec3) — The center position of the unit.
intersection_position (vec3) — The intersection position of the unit.
skillshot_result​

A table containing the following fields:

hit_list (table(hit_data)) — A list of hit_data tables for the units hit.
amount_of_hits (number) — The number of units hit.
cast_position (vec3) — The cast position for the spell.
Functions 📚​
new_spell_data(spell_id, max_range, radius, cast_time, projectile_speed, prediction_mode, geometry, source_position, intersection_factor, angle, exception_is_heal, exception_player_included)​

Creates new spell data with default or specified values.

Parameters:
spell_id (number) — The ID of the spell.
max_range (number, optional) — The maximum range of the spell.
radius (number, optional) — The radius of the spell's area of effect.
cast_time (number, optional) — The cast time of the spell.
projectile_speed (number, optional) — The speed of the spell's projectile.
prediction_mode (prediction_type, optional) — The prediction mode for the spell.
geometry (geometry_type, optional) — The geometry type of the spell's area of effect.
source_position (vec3, optional) — The source position of the spell.
intersection_factor (number, optional) — The interception factor for the spell.
angle (number, optional) — The angle of the spell's area of effect (for cones).
exception_is_heal (boolean, optional) — Whether the spell is a healing spell.
exception_player_included (boolean, optional) — Whether to include the player in the spell's effect.

Returns: spell_data — A table containing the spell data.

get_center_position(target, spell_data)​

Gets the center position of a target.

Parameters:
target (game_object) — The target game_object.
spell_data (spell_data) — The spell data.

Returns: vec3 — The center position of the target.

get_intersection_position(target, center_position, circle_radius, interception_percentage)​

Gets the intersection position for casting the spell.

Parameters:
target (game_object) — The target game_object.
center_position (vec3) — The center position of the target.
circle_radius (number) — The radius of the spell's area of effect.
interception_percentage (number) — The interception factor for the spell.

Returns: vec3 — The intersection position for casting the spell.

get_unit_list(position, range, is_heal)​

Gets the list of units around a position.

Parameters:
position (vec3) — The position to check around.
range (number) — The range to check within.
is_heal (boolean, optional) — Whether the spell is a healing spell.

Returns: table(hit_data) — A list of units around the position.

get_circle_list(target_position, spell_data, is_heal)​

Gets the list of units inside a circle.

Parameters:
target_position (vec3) — The center position of the circle.
spell_data (spell_data) — The spell data.
is_heal (boolean, optional) — Whether the spell is a healing spell.

Returns: table(hit_data) — A list of units inside the circle.

get_rectangle_list(target_position, spell_data, is_heal)​

Gets the list of units inside a rectangle.

Parameters:
target_position (vec3) — The center position of the rectangle.
spell_data (spell_data) — The spell data.
is_heal (boolean, optional) — Whether the spell is a healing spell.

Returns: table(hit_data) — A list of units inside the rectangle.

get_cone_list(target_position, spell_data, is_heal)​

Gets the list of units inside a cone.

Parameters:
target_position (vec3) — The center position of the cone.
spell_data (spell_data) — The spell data.
is_heal (boolean, optional) — Whether the spell is a healing spell.

Returns: table(hit_data) — A list of units inside the cone.

get_unit_geometry_list(position, spell_data)​

Gets the list of units inside a specified geometry.

Parameters:
position (vec3) — The center position of the geometry.
spell_data (spell_data) — The spell data.

Returns: table(hit_data) — A list of units inside the geometry.

get_most_hits_position(main_position, spell_data)​

Gets the best position to hit the most units.

Parameters:
main_position (vec3) — The center position to check from.
spell_data (spell_data) — The spell data.

Returns: skillshot_result — A table containing the best cast position and list of units hit.

get_cast_position(target, spell_data)​

Gets the cast position based on the prediction mode.

Parameters:
target (game_object) — The target game_object.
spell_data (spell_data) — The spell data.

Returns: skillshot_result — A table containing the cast position and list of units hit.

get_cast_position_(position_override, spell_data)​

Gets the cast position based on the prediction mode with a position override.

Parameters:
position_override (vec3) — The overridden position to check from.
spell_data (spell_data) — The spell data.

Returns: skillshot_result — A table containing the cast position and list of units hit.

Example Usage 🧰​
Using the Spell Prediction to Cast Blizzard​
---@type spell_queue

local spell_queue = require("common/modules/spell_queue")

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")

---@type spell_prediction

local spell_prediction = require("common/modules/spell_prediction")



local function cast_blizzard_to_hud_target()

    local local_player = core.object_manager.get_local_player()

    if local_player then

        local hud_target = local_player:get_target()

        if hud_target then

            local blizzard_id = 10

            local player_position = local_player:get_position()

            local prediction_spell_data = spell_prediction:new_spell_data(

                blizzard_id,                                    -- spell_id

                30,                                             -- range

                6,                                              -- radius

                0.2,                                            -- cast_time

                0.0,                                            -- projectile_speed

                spell_prediction.prediction_type.MOST_HITS,     -- prediction_type

                spell_prediction.geometry_type.CIRCLE,          -- geometry_type

                player_position                                 -- source_position

            )



            if spell_helper:is_spell_castable(blizzard_id, local_player, hud_target, false, false) then

                local prediction_result = spell_prediction:get_cast_position(hud_target, prediction_spell_data)

                if prediction_result and prediction_result.amount_of_hits > 0 then

                    spell_queue:queue_spell_position(blizzard_id, prediction_result.cast_position, 1, "Queueing Blizzard at optimal position")

                end

            end

        end

    end

end


This code:

Sets up a Blizzard spell with prediction data
Uses MOST_HITS prediction type to maximize the spell's impact
Queues the Blizzard at the optimal position if targets are predicted to be hit
Priest Death and Decay - Functionality Showcase​

NOTE

As you can see, we call prediction_type.MOST_HITS to fire Death and Decay on the Priest. Instead of casting on the center, it strategically places the spell slightly to the left to hit extra dummies aswell.

TIP

Test with the prediction_type.ACCURACY values for pinpointing situations where the cast should be avoided

Advanced Tips 💡​

Intersection Factor: Adjust intersection_factor in spell_data to control how the spell prediction accounts for moving targets. A higher value can anticipate where the target will be in the future.

Angle for Cones: When using geometry_type.CONE, ensure you set the angle parameter in spell_data to define the cone's spread.

Healing Spells: Set exception_is_heal to true if you're working with healing spells to target friendly units instead of enemies.

Prediction Modes: Use prediction_type.ACCURACY for single-target precision or prediction_type.MOST_HITS to maximize the number of targets hit.

Geometry Types: Choose the appropriate geometry_type based on your spell's area of effect shape.

Customizing Spell Data: When creating spell_data, you can override default values to fine-tune the prediction to match your spell's characteristics.

Exceptions: Use exception_is_heal and exception_player_included to adjust the prediction logic for healing spells or whether to include the player character.

Common Use Cases 🎯​
Area of Effect Spells: Use prediction_type.MOST_HITS with geometry_type.CIRCLE or RECTANGLE to maximize damage or healing.
Skill Shots: For spells that require precise targeting, use prediction_type.ACCURACY to predict the best cast position based on the target's movement.
Crowd Control: Combine prediction with geometry calculations to immobilize or debuff multiple enemies effectively.
Troubleshooting 🛠️​
Incorrect Cast Position: Verify that your spell_data parameters accurately reflect the spell's actual in-game properties.
No Targets Hit: Ensure that the get_unit_list function is correctly identifying units within range and that exception_is_heal is set appropriately.
Performance Issues: Limit the frequency of prediction calculations to prevent performance degradation, especially in scripts that run every frame.

---

## https://docs.project-sylvanas.net/dev/libraries/combat-forecast

Combat Forecast
Overview​

The Combat Forecast module is designed to help developers make more informed decisions during combat by predicting the length of encounters and the potential impact of spells. This module integrates with Sylvanas’ core functionality to provide accurate combat data, enhancing strategies for PvE scenarios. Below, we'll delve into its core functions and how to effectively utilize them.

TIP

You should check User Combat Forecast Guide to understand what this module is about in more depth before starting to work with it.

Importing The Module​

Like with all other LUA modules developed by us, you will need to import the health prediction module into your project. To do so, you can just use the following lines:


---@type combat_forecast

local combat_forecast = require("common/modules/combat_forecast")

WARNING

To access the module's functions, you must use : instead of .

For example, this code is not correct:

---@type combat_forecast

local combat_forecast = require("common/modules/combat_forecast")



local function should_cast_hard_cast_spell(player)

    local combat_length_simple = combat_forecast.get_forecast()

    return combat_length_simple >= 3.0

end


And this would be the corrected code:

---@type combat_forecast

local combat_forecast = require("common/modules/combat_forecast")



local function should_cast_hard_cast_spell(player)

    local combat_length_simple = combat_forecast:get_forecast()

    return combat_length_simple >= 3.0

end

Functions​
Forecast Lengths Enum 📋​
forecast_lengths​

The forecast_lengths enum provides various lengths for combat forecasting:

DISABLED: No forecast applied.
VERY_SHORT: Forecast is for a very short duration.
SHORT: Forecast is for a short duration.
MEDIUM: Forecast is for a medium duration.
LONG: Forecast is for a long duration.

This enum is used to specify the expected length of a combat scenario when making logic decisions.

Combat Data Retrieval 📊​
get_forecast() -> number​

Retrieves the forecast data for the current combat situation. This function provides an overall view of the combat forecast, which can be used to adapt strategies on the fly.

get_forecast_single(unit: game_object, include_pvp?: boolean) -> number​

Fetches the forecast data specifically for a single unit, with an option to include PvP-related considerations. This is particularly useful for predicting the impact of spells on individual targets.

Minimum Combat Length 📈​
get_min_combat_length(forecast_mode: any, plugin_name: string, spell_name: string) -> number​

Determines the minimum combat length required for a specified forecast mode, plugin, and spell. This data helps in deciding whether to use long cooldown abilities or time-sensitive spells.

Forecast Logic Validation 📋​
is_valid_forecast_logic(min_combat_length: number, unit?: game_object, include_pvp?: boolean) -> boolean​

Validates the forecast logic based on the minimum combat length and the specified unit. This function ensures that actions are only taken if they align with the expected duration of the encounter, avoiding the misuse of cooldowns.

Usage Example and Best Practices​

Here is an example of how to implement the Combat Forecast module effectively in your code:



---@type combat_forecast

local combat_forecast = require("common/modules/combat_forecast")



local function should_cast_spell_based_on_global_forecast(spell_name)

    local min_combat_length = combat_forecast:get_min_combat_length(combat_forecast.enum.SHORT, "my_plugin", spell_name)

    local is_valid_logic = combat_forecast:is_valid_forecast_logic(min_combat_length)



    if is_valid_logic then

        core.log("Casting " .. spell_name .. " based on combat forecast")

        return true

    else

        core.log("Skipping " .. spell_name .. " due to short combat forecast")

        return false

    end

end


Or, if we just want to check our main target:



---@type combat_forecast

local combat_forecast = require("common/modules/combat_forecast")



local function should_cast_spell_based_on_single_forecast(target, spell_name, forecast_max_time)

    local combat_length_single = combat_forecast:get_forecast_single(target)

    local is_valid_logic = combat_length_single <= forecast_max_time



    if is_valid_logic then

        core.log("Casting " .. spell_name .. " based on single - combat forecast")

        return true

    end



    core.log("Skipping " .. spell_name .. " due to short single - combat forecast")

    return false

end


Or, if we just want a quick, simple check for general usage (eg. not a very important spell)



---@type combat_forecast

local combat_forecast = require("common/modules/combat_forecast")



local function should_cast_spell_based_on_general_forecast(target, spell_name, forecast_max_time)

    local combat_length_simple = combat_forecast:get_forecast()

    local is_valid_logic = combat_length_single <= forecast_max_time



    if is_valid_logic then

        core.log("Casting " .. spell_name .. " based on single - combat forecast")

        return true

    end



    core.log("Skipping " .. spell_name .. " due to short single - combat forecast")

    return false

end

Best Practice Tip​
TIP

Always ensure that you validate the combat length before casting spells with long cooldowns or spells that have a long cast time. This approach will prevent unnecessary use of critical abilities in short fights, optimizing your overall strategy.

---

## https://docs.project-sylvanas.net/dev/libraries/health-prediction

Health Prediction
Overview​

The Health Prediction module is a powerful tool that provides developers with various functions to predict incoming damage and make better decisions for defensive and healing logics. This module plays a crucial role in enhancing the adaptability and accuracy of gameplay strategies in both PvP and PvE scenarios. Below, we'll explore its core functions and how to utilize them effectively.

TIP

You should check User Health Pred Guide to understand what this module is about in more depth before starting to work with it.

Importing The Module​

Like with all other LUA modules developed by us, you will need to import the health prediction module into your project. To do so, you can just use the following lines:


---@type health_prediction

local health_pred = require("common/modules/health_prediction")

WARNING

To access the module's functions, you must use : instead of .

For example, this code is not correct:

---@type health_prediction

local health_pred = require("common/modules/health_prediction")



local function get_incoming_damage_in_3_seconds(player)

    local health_pred_calculated_health = health_pred.get_incoming_damage(player, 3.0)

    return health_pred_calculated_health

end


And this would be the corrected code:

---@type health_prediction

local health_pred = require("common/modules/health_prediction")



local function get_incoming_damage_in_3_seconds(player)

    local health_pred_calculated_health = health_pred:get_incoming_damage(player, 3.0)

    return health_pred_calculated_health

end

Functions​
NOTE

There is only one relevant function for developers within the health prediction module. That is the get_incoming_damage function. You could also use the unit_helper library, which also has a function that will return the health percentage taking into account the incoming damage. This functions is get_health_percentage_inc.

TIP

Instead of using the health_prediction module, you can just include directly the unit_helper module, which already includes the functionality below.

get_incoming_damage(target: game_object, deadline_time_in_seconds: number, is_exception?: boolean) -> number​

Retrieves the amount of incoming damage to a specified target within a given timeframe.

Code Example 📋​

Below, a complete function example to check if you should cast deffensives or not, according to health prediction or raw health.

WARNING

This function is using previously defined menu elements. The comments explain them, but you can choose to remove them or create your own menu elements to replace them. This is just a real-life example used in one of our Mythic+ plugins.

---@type health_prediction

local health_pred = require("common/modules/health_prediction")



local function should_cast_deffensive_spell_on_incoming_damage(local_player)

    -- menu element to check if we are using health pred or not (you can remove this)

    local is_using_inc_dmg_logic = menu_elements.override_min_hp_on_incoming_hp_pct:get_state()



    -- we store player hp and max hp on a local variable to avoid calling the same function multiple times (performance)

    local local_player_hp = local_player:get_health()

    local local_player_max_hp = local_player:get_max_health()



    -- if this is true, it means that the user decided not to use the health prediction, so we just check for plain health percentage

    if not is_using_inc_dmg_logic then

        local player_current_hp_pct = local_player_hp / local_player_max_hp

        return player_current_hp_pct <= menu_elements.spell_min_hp_pct:get()

    end



    -- if this code is read, means the previous check was false, so the user decided to use health prediction



    --- get incoming damage in the next 3 seconds

    local inc_dmg_hp = health_pred:get_incoming_damage(local_player, 3.0)

    -- get our hp after all the incoming damage is received

    local hp_minus_inc_dmg = local_player - inc_dmg_hp

    -- check our future health percentage, after all the expected damage is received

    local inc_dmg_hp_pct = hp_minus_inc_dmg / local_player_max_hp



    local min_inc_dmg_hp_pct_slider_value = menu_elements.incoming_hp_pct:get()



    -- compare the previous future hp pct that we calculated to the min hp pct value set by the user

    local should_cast_deffensive = inc_dmg_hp_pct <= min_inc_dmg_hp_pct_slider_value



    if should_cast_deffensive then

        -- change spell_data.name with your spell name!

        core.log("Should Cast " .. spell_data.name .. "On Inc DMG HP PCT - - Inc Dmg: " .. tostring(inc_dmg_hp_pct))

        return true

    end



    return false

end

NOTE

As stated before, you can swap the health_pred module for the unit_helper module, since the latter also provides the get_inc_damage functionality.

---

## https://docs.project-sylvanas.net/dev/libraries/unit-helper

Unit Helper
Overview​

The Unit Helper module provides a collection of utility functions for working with game units in Sylvanas. This module simplifies tasks such as checking unit states, retrieving unit information, and working with groups of units. Below, we'll explore its core functions and how to effectively utilize them.

Importing The Module​

As with all other LUA modules developed by us, you will need to import the unit helper module into your project. To do so, you can use the following lines:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")

WARNING

To access the module's functions, you must use : instead of .

For example, this code is not correct:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



local function is_target_dummy(unit)

    return unit_helper.is_dummy(unit)

end


And this would be the corrected code:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



local function is_target_dummy(unit)

    return unit_helper:is_dummy(unit)

end

Functions​
Unit Classification Functions 📋​
is_dummy(unit: game_object) -> boolean​

Returns true if the given unit is a training dummy.

local is_training_dummy = unit_helper:is_dummy(unit)

if is_training_dummy then

    core.log("The unit is a training dummy.")

end

is_blacklist(npc_id: number) -> boolean​

Returns true if the npc_id is inside a blacklist. For example, incorporeal beings which should be ignored by the target selector.

local is_blacklisted = unit_helper:is_blacklist(npcID)

if is_blacklisted then

    core.log("The NPC is blacklisted.")

end

is_boss(unit: game_object) -> boolean​

Determines if the unit is a boss with certain exceptions.

is_valid_enemy(unit: game_object) -> boolean​

Determines if the unit is a valid enemy with exceptions.

is_valid_ally(unit: game_object) -> boolean​

Determines if the unit is a valid ally with exceptions.

Combat State Functions 🛡️​
is_in_combat(unit: game_object) -> boolean​

Determines if the unit is in combat with certain exceptions.

Health and Resource Functions ❤️​
get_health_percentage(unit: game_object) -> number​

Returns the health percentage of the unit in a format from 0.0 to 1.0.

local health_pct = unit_helper:get_health_percentage(unit)

core.log("Unit's health percentage: " .. (health_pct * 100) .. "%")

get_health_percentage_inc(unit: game_object, time_limit?: number) -> number, number, number, number​

Calculates the health percentage of a unit considering incoming damage within a specified time frame. This function uses the Health Prediction Module

NOTE



This function returns 4 values:

1- Total -> The value that you will want usually. It's the future health percentage that you willhave according to the incoming damage.
2- Incoming -> The amount of incoming damage.
3- Percentage -> The current HP percentage.
4- Incoming Percentage -> The HP percentage taking into account just the incoming damage and not current health.

local total, incoming, percentage, incoming_percent = unit_helper:get_health_percentage_inc(unit, 5)

core.log("Health after incoming damage: " .. (total * 100) .. "%")

TIP

Generally, you will use this function as follows:

    if unit_helper:get_health_percentage_inc(ally_target) < 0.45 then

        is_anyone_low = true

    end


Just taking into account the first value.

get_resource_percentage(unit: game_object, power_type: number) -> number​

Gets the power (resource) percentage of the unit. See PowerType Enum for power_type values.

---@type enums

local enums = require("common/enums")



local get_local_player_energy_pct(local_player)

    local energy_percentage = unit_helper:get_resource_percentage(local_player, enums.power_type.ENERGY)

    core.log("Unit's Energy percentage: " .. (energy_percentage * 100) .. "%")

    return energy_percentage

end



Role Determination Functions 🏹​
get_role_id(unit: game_object) -> number​

Determines the role ID of the unit (Tank, DPS, Healer).

is_healer(unit: game_object) -> boolean​

Determines if the unit is healer.

WARNING

Might not work in open world (if the target is not a party member).

is_player_in_arena() -> boolean​

Determines if the local player is in arena.

is_player_in_bg() -> boolean​

Determines if the local player is in BG.

is_tank(unit: game_object) -> boolean​
WARNING

Might not work in open world (if the target is not a party member).

Determines if the unit is in the tank role.

TIP

Below, an example on how to retrieve the tank from your party:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



---@param local_player game_object

---@returns game_object | nil

local get_tank_from_party(local_player)

    local allies_from_party = unit_helper:get_ally_list_around(local_player:get_position(), 40.0, true, true)



    for k, ally in ipairs(allies_from_party) do

        local is_current_ally_tank = unit_helper:is_tank(ally)



        if is_current_ally_tank then

            return ally

        end

    end



    return nil

end



Group Unit Functions 👥​
TIP

See Object Manager for a more in-depth explanation and code examples.

get_enemy_list_around(point: vec3, range: number, incl_out_combat?: boolean, incl_blacklist?: boolean) -> table<game_object>​

Returns a list of enemies within a designated area. This function is performance-friendly with Lua core cache.

point: The center point to search around.
range: The radius to search within.
incl_out_combat: Include units that are out of combat. Defaults to false.
incl_blacklist: Include units that are blacklisted. Defaults to false.
get_ally_list_around(point: vec3, range: number, players_only: boolean, party_only: boolean) -> table<game_object>​

Returns a list of allies within a designated area. This function is performance-friendly with Lua core cache.

point: The center point to search around.
range: The radius to search within.
players_only: Include only player units.
party_only: Include only party members.

---

## https://docs.project-sylvanas.net/dev/libraries/target-selector

Target Selector
Overview​

The Target Selector module gives you the tools to effectively retrieve the best targets for your logics. Its basic usage is very simple, so we encourage you to use this module in all your damage or healing-related plugins.

Importing The Module​

As with all other LUA modules developed by us, you will need to import the Target Selector module into your project. To do so, you can use the following lines:

---@type target_selector

local target_selector = require("common/modules/target_selector")

WARNING

To access the module's functions, you must use : instead of .

For example, this code is not correct:

---@type target_selector

local target_selector = require("common/modules/target_selector")



local function get_targets()

    return target_selector.get_targets()

end


And this would be the corrected code:

---@type target_selector

local target_selector = require("common/modules/target_selector")



local function get_targets()

    return target_selector:get_targets()

end

Functions​
get_targets(limit: integer (optional)) -> table<game_object>​
Retrieves the table containing the best targets possible, according to the current Target Selector settings.
The max number of targets it returns is 3 , but you can limit it to less by specifying the limit parameter.
get_targets_heal(limit: integer (optional)) -> table<game_object>​
Retrieves the table containing the best targets to heal possible, according to the current Target Selector settings.
The max number of targets it returns is 3 , but you can limit it to less by specifying the limit parameter.
Manually Modifying the Settings​

Altough the TS config should be good to go by default, you can manually set them inside your plugin. To do so, you have to access the target selector's menu elements and modify them. For example:

---@type target_selector

local target_selector = require("common/modules/target_selector")



-- this function is a simple one, not necessarily the best one for mage fires. This is just an example.

local is_ts_overriden = false

local function override_ts_settings()

    if is_ts_overriden then

        return

    end



    target_selector.menu_elements.damage.weight_multiple_hits:set(true)

    target_selector.menu_elements.damage.slider_weight_multiple_hits:set(4)

    target_selector.menu_elements.damage.slider_weight_multiple_hits_radius:set(8)

    target_selector.menu_elements.settings.max_range_damage:set(40)



    is_ts_overriden = true

end


In the previous example, we are manually setting the weight to multiple hits, and the max range of the TS. You can do this for all the parameters.

WARNING

In general, you will never need to modify the settings. If you have to modify them, we suggest that you add a menu element to give the user the power to disable your custom TS. For example:

---@type target_selector

local target_selector = require("common/modules/target_selector")



local is_ts_overriden = false

local function override_ts_settings()

    if is_ts_overriden then

        return

    end



    -- define this menu element elsewhere in your code, and render it

    local is_override_allowed = menu_elements.ts_custom_logic_override:get_state()

    if not is_override_allowed then

        return

    end



    target_selector.menu_elements.damage.is_damage_enabled:set(true)



    target_selector.menu_elements.damage.is_damage_enabled:set(true)

    target_selector.menu_elements.damage.weight_multiple_hits:set(true)

    target_selector.menu_elements.damage.slider_weight_multiple_hits:set(4)

    target_selector.menu_elements.damage.slider_weight_multiple_hits_radius:set(8)

    target_selector.menu_elements.settings.max_range_damage:set(40)



    is_ts_overriden = true

end


---

## https://docs.project-sylvanas.net/dev/libraries/inventory-helper

Inventory Helper
Overview​

The Inventory Helper module provides a comprehensive set of utility functions that aims to make your life easier when working with items. Below, we'll explore its functionality.

Importing The Module​

As with all other LUA modules developed by us, you will need to import the Inventory Helper module into your project. To do so, you can use the following lines:

---@type inventory_helper

local inventory_helper = require("common/utility/inventory_helper")

WARNING

To access the module's functions, you must use : instead of .

For example, this code is not correct:

---@type inventory_helper

local inventory_helper = require("common/utility/pvp_helper")



local function check_if_player(unit)

    return inventory_helper.get_bank_slots(unit)

end


And this would be the corrected code:

---@type inventory_helper

local inventory_helper = require("common/utility/pvp_helper")



local function check_if_player(unit)

    return inventory_helper:get_bank_slots(unit)

end

Functions​
get_all_slots() -> table<slot_data>​

Retrieves all item slots available to the player, including both character bags and bank slots.

Returns:
slots (table<slot_data>): A table containing slot data for all items.
get_character_bag_slots() -> table<slot_data>​

Retrieves all item slots from the character's bags, excluding bank slots.

Returns:
slots (table<slot_data>): A table containing slot data for items in character bags.
get_bank_slots() -> table<slot_data>​

Retrieves all item slots from the bank.

Returns:
slots (table<slot_data>): A table containing slot data for items in the bank.
get_current_consumables_list() -> table<consumable_data>​

Retrieves a list of consumables currently in the player's inventory.

Returns:
consumables (table<consumable_data>): A table containing data for each consumable item.
update_consumables_list()​

Updates the internal list of consumables. Call this function whenever the inventory changes to refresh the consumables list.

Example:

---@type inventory_helper

local inventory_helper = require("common/utility/pvp_helper")



-- After picking up new consumables

inventory_helper:update_consumables_list()

debug_print_consumables()​

Prints the current consumables list to the debug log for debugging purposes.

Data Structures​
Slot Data Structure 🎒​

The slot_data class represents an item slot in the inventory or bank.

Fields:​
item (game_object): The item object in this slot.
global_slot (number): Global slot identifier.
bag_id (integer): ID of the bag containing the item.
bag_slot (integer): Slot number within the bag.
stack_count (integer): Stack count of the item in this slot.

Example:

local slot = all_slots[1]

core.log("Item: " .. slot.item:get_name())

core.log("Stack Count: " .. tostring(slot.stack_count))

Consumable Data Structure 🧪​

The consumable_data class represents a consumable item in the inventory.

Fields:​
is_mana_potion (boolean): Whether the item is a mana potion.
is_health_potion (boolean): Whether the item is a health potion.
is_damage_bonus_potion (boolean): Whether the item is a damage bonus potion.
item (game_object): The item object for the consumable.
bag_id (integer): ID of the bag containing the item.
bag_slot (integer): Slot number within the bag.
stack_count (integer): Stack count of the item in this slot.
Examples​
Iterating Over All Inventory Slots​
---@type inventory_helper

local inventory = require("common/utility/inventory_helper")



local function print_all_items()

    local all_slots = inventory:get_all_slots()

    for _, slot in ipairs(all_slots) do

        core.log("Item: " .. slot.item:get_name() .. " in slot: " .. tostring(slot.global_slot))

    end

end



print_all_items()


---

## https://docs.project-sylvanas.net/dev/libraries/dungeons-helper

Dungeons Helper
Overview​

The Dungeons Helper module provides a comprehensive set of utility functions that aims to make your life easier when trying to gather information about dungeons. Below, we'll explore its functionality.

Importing The Module​

As with all other LUA modules developed by us, you will need to import the Dungeons Helper module into your project. To do so, you can use the following lines:

---@type dungeons_helper

local dungeons_helper = require("common/utility/dungeons_helper")

WARNING

To access the module's functions, you must use : instead of .

For example, this code is not correct:

---@type dungeons_helper

local dungeons_helper = require("common/utility/dungeons_helper")



local function check_if_player(unit)

    return dungeons_helper.is_mythic_dungeon(unit)

end


And this would be the corrected code:

---@type inventory_helper

local dungeons_helper = require("common/utility/dungeons_helper")



local function is_player_in_mythic_dungeon()

    return dungeons_helper:is_mythic_dungeon()

end

Functions​
is_mythic_dungeon() -> boolean​

Returns true if the local player is currently in a Mythic dungeon.

Returns:
boolean -> True if the local player is currently in a Mythic dungeon, false otherwise.
get_mythic_key_level() -> integer​

Retrieves the key level of the current Mythic dungeon.

Returns:
key level integer: The key level of the current Mythic dungeon.
is_kite_exception() -> boolean​

Checks if we are on kite exception.

Returns:
boolean: If we are on kite exception.
game_object | nil:
game_object | nil:
is_kikatal_near_cosmic_cast(energy_threshold: number) -> boolean​

Checks if kikatal is near a cosmic cast within a given energy threshold.

Returns:
boolean: If Kikatal is near cosmic cast.
game_object | nil:
is_kikatal_grasping_blood_exception() -> boolean, game_object | nil, game_object | nil​

Checks if we are under a kikatal grasping blood exception.

Returns:
boolean: If Kikatal is near cosmic cast.
game_object | nil:
game_object | nil:

---

## https://docs.project-sylvanas.net/dev/libraries/pvp/helper

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

---

## https://docs.project-sylvanas.net/dev/libraries/pvp/ui

PvP UI
Overview​

The PvP UI Module provides the required functions for you to implement your own PvP-UI own panel. Read (pvp ui module - user) todo add link -- before continuing with this guide, so you know what this module is about.

Importing The Module​

As with all other LUA modules developed by us, you will need to import the PVP Helper module into your project. To do so, you can use the following lines:

---@type ui_buttons_info

local ui_buttons_info = require("common/utility/ui_buttons_info")

WARNING

To access the module's functions, you must use . instead of :. This is the only module where : is not required.

Functions​
NOTE

Almost everything is handled automatically, so there is just one function that you must call under any circumstance. This is the push_button function. All the other functions are just regarding available customizations for the user, that are centralized within the plugin and can be modified by the user directly on the window that spawns. You should take into consideration these settings that the user might modify for your logic so your plugin is coherent.

WARNING

The function that you are going to pass to the GUI module MUST return TRUE at some point. When your logic function returns true, the logic is removed from the queue. Otherwise, the button will be permanently stuck on the "On Queue" state. Check the code example and the rest of documentation so you can fully understand how this works. Just keep this information in mind for when you read the "push_button" function definition, just below.

push_button(button_id: string, title: string, spell_ids:table<number>, logic_function:fun) -> nil​
Parameters explanation:
button_id: This is the unique identifier for the button.
title: This is the name that will appear in the button. For example, if you want to use scatter and trap, a desirable name would be Scatter-Trap, for example.
NOTE

Avoid long title names, as the buttons should be as small as possible so the PvP UI Window occupies as little space as possible on the screen.

spell_ids: These are the ids of the spells that you want to check the CD of. For example, if you want the button to be disabled when Scatter and Trap are on cooldown, you need to pass {scatter_id, trap_id} to this function. This is independent of the logic function, so you can just pass here Trap cooldown and then also cast Scatter.
function: This is the logic that will be run when the user presses the button from the UI.
WARNING

This function must be called just once, on script load. Do not place it inside any callback.

get_button_info(button_id: string) -> table​

Return value explanation: This function returns a table containing all available data for the button with the specifed ID. This table has the following members:

.button_id -> The id of the button.
.title -> The title of the button.
.spell_ids -> The table containing the IDs that are used to check the remaining time of the logic.
.is_pressed -> If the button is pressed now
.is_enabled -> If the button is enabled (when disabled, it won't be shown in the UI)
.last_trigger_time -> Last time that the button was pressed.
.is_attempting_to_run_logic -> If the logic is trying to be run right now (the logic is on queue).
.arena_frame_pressed_to -> The index of the button that was pressed. This is used internally to handle the target.
.logic -> The logic_function itself.

get_current_buttons_info() -> table​

Returns the table containing all the available UI buttons information. (See the previous function to see what elements does a UI button table contain)

is_logic_attempting_only_once() -> boolean​

Returns the configuration that the user set for the Logic Cast Mode, found within the GUI customization window. If true, the logic should be also attempted to be run once. Otherwise, you can apply your custom logics or behaviour. You should always set a maximum timer to reset the button state (return true from its function).

get_timeout_time() -> number​

Returns the timeout time that the user set.

.launch_checkbox -> checkbox​
WARNING

This is the checkbox that you must render within your plugin's menu, so the user is able to launch the PvP GUI Window. If you don't render this button, the user won't be able to re-launch the window after they close it, or it will never be shown to begin with.

Complete Example​

This is the logic that we are currently using for our Beast Mastery Hunter plugin. We made sure to explain everything in the comments, so you have an easier time understanding everything.

In the pvp_ui_implementation.lua file we have the following code:

---@type spell_queue

local spell_queue = require("common/modules/spell_queue")



---@type pvp_helper

local pvp_helper = require("common/utility/pvp_helper")



---@type spell_helper

local spell_helper = require("common/utility/spell_helper")



-- used spells ids

local inti_id = 19577

local trap_id = 187650

local scatter_id = 213691



---@type ui_buttons_info

local ui_buttons_info = require("common/utility/ui_buttons_info")



-- return true means remove logic from queue - it was casted already / aborted

local function scatter_trap_logic(local_player, target, trigger_time)

    -- target is immune to stun right now, so wait for them to stop being immune

    if pvp_helper:is_cc_immune(target, pvp_helper.cc_flags.STUN, 1000.0) then

        return false

    end



    -- check if we have pet

    local pet = local_player:get_pet()

    local is_there_pet = pet and not pet:is_dead()

    local is_trying_only_once = ui_buttons_info:is_logic_attempting_only_once()



    -- get the timeout time from the ui itself, since this can be modified by the user there

    local timeout_time = ui_buttons_info:get_timeout_time()



    local current_time = core.time()

    local attempting_time = current_time - trigger_time



    -- check if the spell has been in queue for longer than the value the user set.

    if attempting_time > timeout_time then

        return true

    end



    local tried_to_cast = false



    -- check if target is cced with at least 1 second of remaining cc time

    local is_target_cced_already, cc_flag, remaining = pvp_helper:is_crowd_controlled(target, pvp_helper.cc_flags.ANY_BUT_SLOW, 1000)



    if is_target_cced_already then

        -- trap is the most important spell, the other ones are just complementary to this one so they are stuck in place and the trap doesn't miss.

        -- therefore, if the target is cc'ed we can just cast the trap, we don't care about stun.

        if remaining < 2500 and spell_helper:is_spell_castable(trap_id, local_player, target, true, false) then

            spell_queue:queue_spell_position(trap_id, target:get_position(), 8, "Hunter MM - UI - Trap")

            -- set tried_to_cast flag to true, so if the user sets the behaviour to attempt only once we

            -- can already return true and remove this logic from the queue

            tried_to_cast = true

        end



        -- if the spell is on cooldown (> 2.0 to make sure global cooldown is not interfering) then our purppose is fullfilled and we can remove this logic

        -- from the queue, as we casted it already.

        return core.spell_book.get_spell_cooldown(trap_id) > 2.0

    else

        -- target was not cc'ed, which means that we have to cc him.

        -- First prio is pet stun since it doesn't share DR with trap.



        -- check if our pet is impaired

        local pet_cced = false

        if is_there_pet  then

            pet_cced, cc_flag, remaining = pvp_helper:is_crowd_controlled(pet, pvp_helper.cc_flags.ANY_BUT_SLOW, 1000)

        end



        -- if we can cast intimidation (pet not cc'ed, spell castable) then we cast it

        if spell_helper:is_spell_castable(inti_id, local_player, target, false, false) and not pet_cced then

            spell_queue:queue_spell_target(inti_id, target, 8, "Hunter MM - UI - Inti")

        else

            -- otherwise, ONLY if intimidation is on CD, we try to cast scatter. Otherwise we just wait for the pet to go out of cooldown or for us

            -- to be able to cast the spell to the target.

            if core.spell_book.get_spell_cooldown(inti_id) > 2.0 then

                if spell_helper:is_spell_castable(scatter_id, local_player, target, false, false) then

                    spell_queue:queue_spell_target(scatter_id, target, 8, "Hunter MM - UI - Inti (Scatter Backup Alt)")

                end

            end

        end

    end



    -- we already tried to cast, if the user set the behaviour to cast only once then this function fullfilled its purpose and we can

    -- remove it from the queue.

    if tried_to_cast then

        tried_to_cast = is_trying_only_once

    end



    -- we always remove this spell from queue if trap is on cd (was casted) or already attempted to cast and user set behaviour to attempt only once.

    return core.spell_book.get_spell_cooldown(trap_id) > 2.0 or tried_to_cast

end



-- call this in the main, ONLY ONCE. Do not place it inside any callback.

local function set_pvp_ui_buttons()

    -- PARAMETERS explanation:

    -- 1 -> remember to always use an unique identifier for each button.

    -- 2 -> remember to use a short title (as short as possible, but the user shuld still be able to understand what it's going to do upon press)

    -- 3 -> the ids of the spells that will be taken into account for tue GUI for the cooldown. In this case, only if trap is on CD, the button is going

    --     to be disabled. The GUI won't care about intimidation or scatter shot.

    -- 4 -> the logic itself. Remember it MUST return TRUE for the logic to be removed from queue. If your function never returns TRUE under any

    --     circumstance, the button will be stuck forever in the "On Queue" state after being pressed.

    ui_buttons_info:push_button("hunter_mm_scatter_trap", "Stun-Trap", {trap_id}, scatter_trap_logic)

end



local function hide_time_slider()

    -- if you want to use a custom timeout slider and don't want to let the user modify this value, hide the slider from the

    -- GUI customization window. (set the parameter to TRUE instead of FALSE).

    ui_buttons_info:set_no_render_timeout_time_slider_flag(false)

end



-- export these functions (and the launch button) to our main file, where we will call them

return

{

    set_pvp_ui_buttons = set_pvp_ui_buttons,

    launch_pvp_ui_button = buttons.launch_checkbox,

    hide_time_slider = hide_time_slider,

}




Then, for the main file we just have:

-- (...)

-- (this is NOT inside any callback)

local pvp_ui = require("pvp_ui_logics")



ui_buttons_info:set_pvp_ui_buttons()

ui_buttons_info:hide_time_slider()

-- (...)



--- (this IS inside the on_render_menu callback)

local on_render_menu()

    -- (...)

    pvp_ui.launch_pvp_ui_button:render("Enable PvP UI Window")

    -- (...)

end




This is the behaviour expected for the code above:

---

## https://docs.project-sylvanas.net/dev/guides/custom-ui

Barney's Basic Guide (With examples) 🎯
Overview​

This guide attempts to guide our fellow Sylvanas programmers into building their own custom user interfaces for their plugins. For this, I have created a step-by-step guide basic that anyone with programming knowledge can follow (hopefully, open to suggestions), adding multiple code examples and exercises to practise. The idea is to give you a starting point, so you can keep learning and evolving yourself afterwards.

🎯 Barney's Basic Guide 🎯
With this guide, our goal is to generate the following UI:

All the code that generates what we can see in the previous image will be extensively explained. The code is obviously open source for you to practise and be creative.

Basics - 0​
The basics - Getting Started



This module is located within the core.menu module. All our custom UI code will be rendered within a "Window". Each window is, and must be treated as, an independent object. Therefore, each individual window that we generate will have its own sepparate visuals and code. Before begining, these are the modules that will be required:

---@type color

local color = require("common/color")



---@type vec2

local vec2 = require("common/geometry/vector_2")



---@type enums

local enums = require("common/enums")

Basics - 1​

The basics - Creating a Window Object

As previously stated, each window must be an individual object. So, same like with menu elements, we are going to generate a window as follows:

local test_window = core.menu.window("Test window")

-- Important: every window must have a unique identifier.

-- In this case, the identifier is "Test window".


Now that we already have our window object, we have to set its initial position and size. (This can be changed later, either by user input or by code, on the rendering callback, however, it's important to always set the initial position and size, which will be used as default.)

NOTE

Size and position are of type vec2, since we need X and Y axis to define both magnitudes. See vec2

Case 1
We don't want size or position to be saved aftear each injection:


We can just set the hardcoded position and size as follows:

local initial_size = vec2.new(200, 200)

window:set_initial_size(initial_size)



local initial_position = vec2.new(500, 500)

window:set_initial_position(initial_position)


Case 2
We want size or position to be saved aftear each injection:
In this case, we also have to generate "ghost" sliders that will save the last known value of position and size of the window, since menu elements are the only available resources that allows us to save information between different injections.

local window_position_elements =

{

    x = core.menu.slider_int(0, 10000, 250, "test_window_x_initial_position"),

    y = core.menu.slider_int(0, 10000, 360, "test_window_y_initial_position"),

}



local window_size_elements =

{

    x = core.menu.slider_int(0, 10000, 250, "test_window_x_initial_size"),

    y = core.menu.slider_int(0, 10000, 360, "test_window_y_initial_size"),

}


Now that we have our sliders defined (you can also use float sliders if you want more precision), we can actually set the window's initial size and position:

local initial_size = vec2.new(window_size_elements.x:get(), window_size_elements.y:get())

test_window:set_initial_size(initial_size)



local initial_position = vec2.new(window_position_elements.x:get(), window_position_elements.y:get())

test_window:set_initial_position(initial_position)

NOTE

Everything that we used up to this point must be called OUTSIDE the render callback.

Basics - 2​

The basics - Rendering our First Window

Everything's ALMOST ready for us to render things and have fun. There is only one thing missing: we need to use the window's special rendering callback! We will use an anonymous function, so we can start rendering directly, but like with all other callbacks, you can define a function and then call the callback passing the said function.

core.register_on_render_window_callback(function()



end)


Now that we have our callback defined, let's actually start rendering. To render any window, we must use the window:begin function. This function's last parameter is another function, and from now on, almost all code will be placed inside this last function. I know it might sound confusing at first, but trust me, it's very simple. You will understand everything with this next example:

core.register_on_render_window_callback(function()

    -- I know all these parameters might overwhelm you at the beginning, but don't worry since all

    -- these parameters are straightforward and pretty much self-explanatory.



    -- Parameter 1: Resizing flags -> Accepts window_resizing_flags enum member:    .NO_RESIZE or 0,

    --                                                                              .RESIZE_WIDTH,

    --                                                                              .RESIZE_HEIGHT,

    --                                                                              .RESIZE_BOTH_AXIS



    -- .NO_RESIZE: The draggable resizing areas will be completely disabled,

    --  making it impossible for the user to change the window's size.

    -- .RESIZE_WIDTH: Only the lateral draggable zone will be enabled, so the user will only be able to increase the window's width.

    -- .RESIZE_HEIGHT: Only the bottom draggable zone will be enabled, so the user will only be able to increase the window's height.

    -- .RESIZE_BOTH_AXIS: The bottom-right draggable zone will be enabled, so the user will be able to modify both, width and height.



    -- Parameter 2: Is adding cross -> Accepts Boolean. The cross refers to the top right X that when pressed will make the window invisible. If false, no cross will be rendered,

    -- so you will have to manually handle a way to close and open the window (eg. custom buttons).



    -- Parameter 3: Background color -> Accepts Color



    -- Parameter 4: Border color -> Accepts Color



    -- Parameter 5: Cross style flag -> Accepts window_cross_visuals enum member:   DEFAULT = 0,

    --                                                                              PURPLE_THEME = 1,

    --                                                                              GREEN_THEME = 2,

    --                                                                              RED_THEME = 3,

    --                                                                              BLUE_THEME = 4,

    --                                                                              NO_BACKGROUND = 5,

    --                                                                              ONLY_HITBOX = 6,

    --                                                                              NO_BORDER = 7,

    --                                                                              NO_BACKGROUND_AND_NO_BORDER = 8,

    --                                                                              NO_CROSS = 9



    -- The cross style enum names are self explanatory, but I advise you to play with all these values and see how they change.



    -- There are up to 3 extra possible parameters that are optional before we add the function call, which is always the last parameter no matter what.

    -- These parameters are just extra flags that we can add that will alter the way the window behaves. They are inside the enums.window_enums.window_behaviour_flags.

    -- These flags are:



    -- .NO_MOVE: Disables the window's movement, so the user won't be able to move the window by dragging it.

    -- .NO_SCROLLBAR: Disables scrollbars for the window.

    -- .ALWAYS_AUTO_RESIZE: Window will automatically resize according to the elements, always according to the dynamic spacing size (see advanced guide)





    -- NOTE: To use the default color, we need to pass color.new(0,0,0,0)



    test_window:begin(enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS, true, color.new(0,0,0,0),

    color.new(0,0,0,0), enums.window_enums.window_cross_visuals.BLUE_THEME, function()







    end)

end)

Basics - Last​

The basics - Summary

Up to this point, this is all the code that we have created:

---@type color

local color = require("common/color")



---@type vec2

local vec2 = require("common/geometry/vector_2")



---@type enums

local enums = require("common/enums")



local test_window = core.menu.window("Test window")

-- Important: every window must have a unique identifier.

-- In this case, the identifier is "Test window".



local window_position_elements =

{

    x = core.menu.slider_int(0, 10000, 500, "test_window_x_initial_position_"),

    y = core.menu.slider_int(0, 10000, 500, "test_window_y_initial_position_"),

}



local window_size_elements =

{

    x = core.menu.slider_int(0, 10000, 500, "test_window_x_initial_size_"),

    y = core.menu.slider_int(0, 10000, 300, "test_window_y_initial_size_"),

}



local initial_size = vec2.new(window_size_elements.x:get(), window_size_elements.y:get())

test_window:set_initial_size(initial_size)



local initial_position = vec2.new(window_position_elements.x:get(), window_position_elements.y:get())

test_window:set_initial_position(initial_position)



core.register_on_render_window_callback(function()

    -- I know all these parameters might overwhelm you at the beginning, but don't worry since all these parameters are straightforward and pretty much self-explanatory.



    -- Parameter 1: Resizing flags -> Accepts window_resizing_flags enum member:    .NO_RESIZE or 0,

    --                                                                              .RESIZE_WIDTH,

    --                                                                              .RESIZE_HEIGHT,

    --                                                                              .RESIZE_BOTH_AXIS



    -- .NO_RESIZE: The draggable resizing areas will be completely disabled, making it impossible for the user to change the window's size.

    -- .RESIZE_WIDTH: Only the lateral draggable zone will be enabled, so the user will only be able to increase the window's width.

    -- .RESIZE_HEIGHT: Only the bottom draggable zone will be enabled, so the user will only be able to increase the window's height.

    -- .RESIZE_BOTH_AXIS: The bottom-right draggable zone will be enabled, so the user will be able to modify both, width and height.



    -- Parameter 2: Is adding cross -> Accepts Boolean. The cross refers to the top right X that when pressed will make the window invisible. If false, no cross will be rendered,

    -- so you will have to manually handle a way to close and open the window (eg. custom buttons).



    -- Parameter 3: Background color -> Accepts Color



    -- Parameter 4: Border color -> Accepts Color



    -- Parameter 5: Cross style flag -> Accepts window_cross_visuals enum member:   DEFAULT = 0,

    --                                                                              PURPLE_THEME = 1,

    --                                                                              GREEN_THEME = 2,

    --                                                                              RED_THEME = 3,

    --                                                                              BLUE_THEME = 4,

    --                                                                              NO_BACKGROUND = 5,

    --                                                                              ONLY_HITBOX = 6,

    --                                                                              NO_BORDER = 7,

    --                                                                              NO_BACKGROUND_AND_NO_BORDER = 8,

    --                                                                              NO_CROSS = 9



    -- The cross style enum names are self explanatory, but I advise you to play with all these values and see how they change.



    -- There are up to 3 extra possible parameters that are optional before we add the function call, which is always the last parameter no matter what.

    -- These parameters are just extra flags that we can add that will alter the way the window behaves. They are inside the enums.window_enums.window_behaviour_flags.

    -- These flags are:



    -- .NO_MOVE: Disables the window's movement, so the user won't be able to move the window by dragging it.

    -- .NO_SCROLLBAR: Disables scrollbars for the window.

    -- .ALWAYS_AUTO_RESIZE: Window will automatically resize according to the elements, always according to the dynamic spacing size (see advanced guide)



    -- NOTE: To use the default color, we need to pass color.new(0,0,0,0)



    test_window:begin(enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS, true, color.new(0,0,0,0),

    color.new(0,0,0,0), enums.window_enums.window_cross_visuals.BLUE_THEME, function()







    end)

end)


As you can see, if we remove the comments, it's a pretty short and straightforward code. This is what we will be seeing on screen after we run this code:




Intermediates - 1​

The Intermediates - Rendering The Title

I am going to introduce the "dynamic" positions offsets, since this is something we need for our showcase. However, this is more advanced, and therefore will be explained in detail in the "The Advanceds" part of the guide. For now, you can just copy and paste the code and play with its parameters. If you go back to the first image, you can notice there is a color-picker on the top-left of the window. Yes, we can render menu elements inside our windows, so you will be able to make your own menus for your plugins, visual guides or whatever your imagination is capable of. First, we will create and render this color picker, since it's the first element that appears on the window.

--- note: this is a menu element declaration, so it must be outside of the callback function.

local color_picker_test = core.menu.colorpicker(bg_color, "color_picker_test_id_1")



test_window:add_menu_element_pos_offset(vec2.new(13, 13))

color_picker_test:render("BG Color")

test_window:add_menu_element_pos_offset(vec2.new(-3, -3))


Now, the colorpicker should be appearing on the top-left of the window. Let's move on to render the title:

    local title_text = "Barney's UI Mini Demo"

    -- With this function we get the exact X position offset required to add to the current dynamic position so the text is in the center of the window:

    local text_centered_x_pos = window:get_text_centered_x_pos(title_text)

    -- We add the X position offset that we just calculated, and also we adjust the Y position:

    window:add_menu_element_pos_offset(vec2.new(text_centered_x_pos, -32))

    -- Finally, we just render the text on the dynamic position that we just set:

    window:add_text_on_dynamic_pos(color.green_pale(255), title_text)


Now that we just rendered the title and the color picker, let's add something to highlight the title. For example, a rectangle:

    window:render_rect(vec2.new(text_centered_x_pos - text_size.x / 20 - 3, 7.5), vec2.new(text_centered_x_pos + text_size.x * 1.05 - 1, 35), color.white(100), 0, 1.0)


And now we just have to add some separators, so it's clear that this is the title preview, right?

    window:add_separator(3.0, 3.0, 15.0, 0.0, color.new(100, 99, 150, 255))

    window:add_separator(3.0, 3.0, 17.0, 0.0, color.new(100, 99, 150, 255))


So, up to this point, this should be how our window's begin function code is looking like:

NOTE

As you will see soon, we can use the color picker that we just declared to set the color of our window.

    test_window:begin(enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS, true, color_picker_test:get_color(),

    color.new(0,0,0,0), enums.window_enums.window_cross_visuals.BLUE_THEME, function()

        test_window:add_menu_element_pos_offset(vec2.new(13, 13))

        color_picker_test:render("BG Color")

        test_window:add_menu_element_pos_offset(vec2.new(-3, -3))



        local title_text = "Barney's UI Mini Demo"

        -- With this function we get the exact X position offset required to add to the current dynamic position so the text is in the center of the window:

        local text_centered_x_pos = window:get_text_centered_x_pos(title_text) -- This function accepts a string, returns a number (which is the X offset)



        -- We add the X position offset that we just calculated, and also we adjust the Y position:

        window:add_menu_element_pos_offset(vec2.new(text_centered_x_pos, -32)) -- This function accepts a vec2, returns nothing (the parameter is the position offset)



        -- Finally, we just render the text on the dynamic position that we just set:

        window:add_text_on_dynamic_pos(color.green_pale(255), title_text) -- This function accepts a color and a string. This just renders the string with the color.



        local text_size = window:get_text_size(title_text)

        -- Now we render the rectangle to highlight the title:

        -- This function accepts start_position (vec2), end_position (vec2), color, rounding, thickness and extra flags. The extra flags are covered in the docs, in the function info.

        window:render_rect(vec2.new(text_centered_x_pos - text_size.x / 20 - 3, 12.0), vec2.new(text_centered_x_pos + text_size.x * 1.05 - 1, 37), color.white(100), 0, 1.0)



        -- We finished rendering the title, so let's add some separators:

        -- This function accepts the following parameters: separation from right offset (number), separation from left offset (number), y offset (number), width_offset (number) and color.

        window:add_separator(3.0, 3.0, 15.0, 0.0, color.new(100, 99, 150, 255))

        window:add_separator(3.0, 3.0, 17.0, 0.0, color.new(100, 99, 150, 255))

    end)


This is how our window should be looking like in game with the current code:

Intermediates - 2​
The Intermediates - Popups



We can also spawn popups (or other windows) from our window. To do this, we obviously need something that triggers the event of the popup appearing. To achieve this, we will usually need buttons. We can use either the buttons that are given from core.menu or we can make our own. In this case, since it's a guide, we will make the buttons ourselves.

First, we need to define the button bounds, and then we just need to control the cursor positioning and behaviour.

    -- top-left position of the button rect

    local open_popup_rect_v1 = vec2.new(13, 70)

    -- bot-right position of the button rect

    local open_popup_rect_v2 = vec2.new(123, 90)



    -- we can change alpha if the mouse is hovering our rect, so the user gets visual feedback and knows that the button does something.

    local alpha = 120

    if window:is_mouse_hovering_rect(open_popup_rect_v1, open_popup_rect_v2) then

        alpha = 255

    end



    -- now, we just need to render the rect accordingly



    -- this is the background of the rect

    window:render_rect_filled(open_popup_rect_v1, open_popup_rect_v2, color.black(alpha), 1.0)

    -- this is the borders of the rect

    window:render_rect(open_popup_rect_v1, open_popup_rect_v2, color.white(alpha), 1.0, 1.0)



    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(40, 71), color.white(255), "Open Me!")



    -- if the window is clicked, then we can do whatever. In this case, we are going to open a popup.

    if window:is_rect_clicked(open_popup_rect_v1, open_popup_rect_v2) then



        -- note: define this boolean outside of the render callback

        is_popup_active = true

    end


Note that popups are essentially windows too, the only difference is that they will be closed upon pressing outside of its bounds (or releasing the mouse, depending on the behaviour flag passed), so everything that we do inside its begin function is relative to the popup. Inside the popup begin function, the parent window's bounds etc are ignored. With this said, we can now go ahead and add the popup code:

if is_popup_active then

    -- the begin_popup function is very similar to the window:begin function. In this case, the parameters are:



    -- background color

    -- border color

    -- size

    -- start position (relative to the parent window)

    -- is_close_on_release (boolean)

    -- is_triggering_from_button (boolean) -> this is true only if you are using a core.menu.button as trigger, since it has a special internal handling. False otherwise.

    if window:begin_popup(color.new(16, 16, 20, 230), border_color, vec2.new(250, 250), vec2.new(150, 50), false, false, function()



        -- same like before, we add the title and separators

        local popup_title_text = "Popup Demo"

        local popup_text_centered_x_pos = window:get_text_centered_x_pos(popup_title_text)



        window:add_menu_element_pos_offset(vec2.new(popup_text_centered_x_pos, 10))

        window:add_text_on_dynamic_pos(color.green_pale(255), popup_title_text)

        window:add_separator(3.0, 3.0, 5.0, 0.0, color.new(100, 99, 150, 255))



        -- even tho this is a little bit more advanced, it's actually very simple.

        -- we are adding a position offset to the next dynamic element that we are rendering (see what's a dynamic element in the advanced guide).

        -- by doing a window:begin_group(), what we are doing is we are essentially saying that everything inside the begin_group function is a unique dynamic element.

        -- Therefore, the position offset will be applied to all elements inside equally.

        -- So, yes, begin group is used to group stuff, basically. In this case, we are grouping 4 menu elements. (Previously defined outside the render callback, like always)

        window:add_menu_element_pos_offset(vec2.new(250/4, 5))

        window:begin_group(function()

            checkbox1:render("Enable Test 1", "Showcasing ...")

            checkbox2:render("Enable Test 2")

            checkbox3:render("Enable Test 3")

            slider_float_test:render("Slider\nTest")

        end)



    end) then

        -- You can do whatever you want here. If the code here is read it means that the popup is currently being rendered.

    else

        -- This means that the user clicked outside of the popup bounds (or released the mouse), so it shouldn't be rendered anymore.

        is_popup_active = false

    end

end


So far, this is what should be appearing on your screen after you hit the "Open Me!" button:

Intermediates - 3​
The Intermediates - Spawning Windows



This is pretty similar to what we did with the popups. The only difference is that now we need to create a window object and we need to handle its visibility in a different way, since windows by default don't close when pressing outside of its bounds. First, we will generate the button that will trigger the window appeareance, just like we did with the popup:

    local open_window_rect_v1 = vec2.new(13, 120)

    local open_window_rect_v2 = vec2.new(123, 150)



    local alpha2 = 120

    if window:is_mouse_hovering_rect(open_window_rect_v1, open_window_rect_v2) then

        alpha2 = 255

    end



    window:render_rect_filled(open_window_rect_v1, open_window_rect_v2, color.black(alpha2), 1.0)

    window:render_rect(open_window_rect_v1, open_window_rect_v2, color.white(alpha2), 1.0, 1.0)

    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(open_window_rect_v1.x + 27, open_window_rect_v1.y + 7), color.white(255), "Open Me!")



    if window:is_rect_clicked(open_window_rect_v1, open_window_rect_v2) then

        -- since this is a window, when the user presses the exit cross, its visibility will be set to false automatically. The button was just clicked, so we need to make sure

        -- the window is visible again.

        window_popup:set_visibility(true)



        -- same like with the popup, we declare this variable outside of the render callback.

        is_window_popup_open = true

    end


Now we just need to render this window. Pretty easy, right? Just like we did for the main window:

    if is_window_popup_open then

        -- window_popup:set_next_window_padding(vec2.new(33, 33))

        window_popup:begin(enums.window_enums.window_resizing_flags.RESIZE_HEIGHT, true, color_picker_test:get(),

        border_color, enums.window_enums.window_cross_visuals.DEFAULT, function()



            local window_popup_title_text = "Window Popup Demo"

            local window_popup_text_centered_x_pos = window:get_text_centered_x_pos(window_popup_title_text)



            -- we render the title following the same principles as before

            window:add_menu_element_pos_offset(vec2.new(window_popup_text_centered_x_pos, 10))

            window:add_text_on_dynamic_pos(color.green_pale(255), window_popup_title_text)

            window:add_separator(3.0, 3.0, 15.0, 0.0, color.new(100, 99, 150, 255))



            window:add_menu_element_pos_offset(vec2.new(30, 20))

            window:begin_group(function()

                checkbox1:render("Enable Test 1", "Tooltip Test ...")

                checkbox2:render("Enable Test 2")

                checkbox3:render("Enable Test 3")

            end)



        end)

    else

        is_window_popup_open = false

    end

Intermediates - Last​
The Intermediates - Summary



So far, this is all the code that we created:

---@type color

local color = require("common/color")



---@type vec2

local vec2 = require("common/geometry/vector_2")



---@type enums

local enums = require("common/enums")



-- Important: every window must have a unique identifier.

-- In this case, the identifier is "Test window".

local test_window = core.menu.window("Test window - ")



local window_position_elements =

{

    x = core.menu.slider_int(0, 10000, 500, "test_window_x_initial_position_"),

    y = core.menu.slider_int(0, 10000, 500, "test_window_y_initial_position_"),

}



local window_size_elements =

{

    x = core.menu.slider_int(0, 10000, 500, "test_window_x_initial_size_"),

    y = core.menu.slider_int(0, 10000, 300, "test_window_y_initial_size_"),

}



local initial_size = vec2.new(window_size_elements.x:get(), window_size_elements.y:get())

test_window:set_initial_size(initial_size)



local initial_position = vec2.new(window_position_elements.x:get(), window_position_elements.y:get())

test_window:set_initial_position(initial_position)





local bg_color = color.new(16, 16, 20, 180)

local border_color = color.new(100, 99, 150, 255)

local color_picker_test = core.menu.colorpicker(bg_color, "color_picker_test_id_1")



local window_popup = core.menu.window("Window Popup Test")



window_popup:set_initial_size(vec2.new(300, 200))

-- this is relative to the parent window, not relative to screen, unlike the parent window initial position.

window_popup:set_initial_position(vec2.new(500, 500))



local is_window_popup_open = false

local is_popup_active = false



core.register_on_render_window_callback(function()

--     -- I know all these parameters might overwhelm you at the beginning, but don't worry since all these parameters are straightforward and pretty much self-explanatory.



--     -- Parameter 1: Resizing flags -> Accepts window_resizing_flags enum member:    .NO_RESIZE or 0,

--     --                                                                              .RESIZE_WIDTH,

--     --                                                                              .RESIZE_HEIGHT,

--     --                                                                              .RESIZE_BOTH_AXIS



--     -- .NO_RESIZE: The draggable resizing areas will be completely disabled, making it impossible for the user to change the window's size.

--     -- .RESIZE_WIDTH: Only the lateral draggable zone will be enabled, so the user will only be able to increase the window's width.

--     -- .RESIZE_HEIGHT: Only the bottom draggable zone will be enabled, so the user will only be able to increase the window's height.

--     -- .RESIZE_BOTH_AXIS: The bottom-right draggable zone will be enabled, so the user will be able to modify both, width and height.



--     -- Parameter 2: Is adding cross -> Accepts Boolean. The cross refers to the top right X that when pressed will make the window invisible. If false, no cross will be rendered,

--     -- so you will have to manually handle a way to close and open the window (eg. custom buttons).



--     -- Parameter 3: Background color -> Accepts Color



--     -- Parameter 4: Border color -> Accepts Color



--     -- Parameter 5: Cross style flag -> Accepts window_cross_visuals enum member:   DEFAULT = 0,

--     --                                                                              PURPLE_THEME = 1,

--     --                                                                              GREEN_THEME = 2,

--     --                                                                              RED_THEME = 3,

--     --                                                                              BLUE_THEME = 4,

--     --                                                                              NO_BACKGROUND = 5,

--     --                                                                              ONLY_HITBOX = 6,

--     --                                                                              NO_BORDER = 7,

--     --                                                                              NO_BACKGROUND_AND_NO_BORDER = 8,

--     --                                                                              NO_CROSS = 9



--     -- The cross style enum names are self explanatory, but I advise you to play with all these values and see how they change.



--     -- There are up to 3 extra possible parameters that are optional before we add the function call, which is always the last parameter no matter what.

--     -- These parameters are just extra flags that we can add that will alter the way the window behaves. They are inside the enums.window_enums.window_behaviour_flags.

--     -- These flags are:



--     -- .NO_MOVE: Disables the window's movement, so the user won't be able to move the window by dragging it.

--     -- .NO_SCROLLBAR: Disables scrollbars for the window.

--     -- .ALWAYS_AUTO_RESIZE: Window will automatically resize according to the elements, always according to the dynamic spacing size (see advanced guide)



--     -- NOTE: To use the default color, we need to pass color.new(0,0,0,0)



    test_window:begin(enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS, true, color.new(0,0,0,0),

    border_color, enums.window_enums.window_cross_visuals.BLUE_THEME, function()

        test_window:add_menu_element_pos_offset(vec2.new(13, 13))

        color_picker_test:render("BG Color")

        test_window:add_menu_element_pos_offset(vec2.new(-3, -3))



        local title_text = "Barney's UI Mini Demo"

        -- With this function we get the exact X position offset required to add to the current dynamic position so the text is in the center of the window:

        local text_centered_x_pos = window:get_text_centered_x_pos(title_text) -- This function accepts a string, returns a number (which is the X offset)



        -- We add the X position offset that we just calculated, and also we adjust the Y position:

        window:add_menu_element_pos_offset(vec2.new(text_centered_x_pos, -32)) -- This function accepts a vec2, returns nothing (the parameter is the position offset)



        -- Finally, we just render the text on the dynamic position that we just set:

        window:add_text_on_dynamic_pos(color.green_pale(255), title_text) -- This function accepts a color and a string. This just renders the string with the color.



        local text_size = window:get_text_size(title_text)

        -- Now we render the rectangle to highlight the title:

        -- This function accepts start_position (vec2), end_position (vec2), color, rounding, thickness and extra flags. The extra flags are covered in the docs, in the function info.

        window:render_rect(vec2.new(text_centered_x_pos - text_size.x / 20 - 3, 12.0), vec2.new(text_centered_x_pos + text_size.x * 1.05 - 1, 37), color.white(100), 0, 1.0)



        -- We finished rendering the title, so let's add some separators:

        -- This function accepts the following parameters: separation from right offset (number), separation from left offset (number), y offset (number), width_offset (number) and color.

        window:add_separator(3.0, 3.0, 15.0, 0.0, color.new(100, 99, 150, 255))

        window:add_separator(3.0, 3.0, 17.0, 0.0, color.new(100, 99, 150, 255))



         -- top-left position of the button rect

        local open_popup_rect_v1 = vec2.new(13, 70)

        -- bot-right position of the button rect

        local open_popup_rect_v2 = vec2.new(123, 90)



        -- we can change alpha if the mouse is hovering our rect, so the user gets visual feedback and knows that the button does something.

        local alpha = 120

        if window:is_mouse_hovering_rect(open_popup_rect_v1, open_popup_rect_v2) then

            alpha = 255

        end



        -- now, we just need to render the rect accordingly



        -- this is the background of the rect

        window:render_rect_filled(open_popup_rect_v1, open_popup_rect_v2, color.black(alpha), 1.0)

        -- this is the borders of the rect

        window:render_rect(open_popup_rect_v1, open_popup_rect_v2, color.white(alpha), 1.0, 1.0)



        window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(40, 71), color.white(255), "Open Me!")



        -- if the window is clicked, then we can do whatever. In this case, we are going to open a popup.

        if window:is_rect_clicked(open_popup_rect_v1, open_popup_rect_v2) then



            -- note: define this boolean outside of the render callback

            is_popup_active = true

        end



        if is_popup_active then

            -- the begin_popup function is very similar to the window:begin function. In this case, the parameters are:



            -- background color

            -- border color

            -- size

            -- start position (relative to the parent window)

            -- is_close_on_release (boolean)

            -- is_triggering_from_button (boolean) -> this is true only if you are using a core.menu.button as trigger, since it has a special internal handling. False otherwise.

            if window:begin_popup(color.new(16, 16, 20, 230), border_color, vec2.new(250, 250), vec2.new(150, 50), false, false, function()



                -- same like before, we add the title and separators

                local popup_title_text = "Popup Demo"

                local popup_text_centered_x_pos = window:get_text_centered_x_pos(popup_title_text)



                window:add_menu_element_pos_offset(vec2.new(popup_text_centered_x_pos, 10))

                window:add_text_on_dynamic_pos(color.green_pale(255), popup_title_text)

                window:add_separator(3.0, 3.0, 5.0, 0.0, color.new(100, 99, 150, 255))



                -- even tho this is a little bit more advanced, it's actually very simple.

                -- we are adding a position offset to the next dynamic element that we are rendering (see what's a dynamic element in the advanced guide).

                -- by doing a window:begin_group(), what we are doing is we are essentially saying that everything inside the begin_group function is a unique dynamic element.

                -- Therefore, the position offset will be applied to all elements inside equally.

                -- So, yes, begin group is used to group stuff, basically. In this case, we are grouping 4 menu elements. (Previously defined outside the render callback, like always)

                window:add_menu_element_pos_offset(vec2.new(250/4, 5))

                window:begin_group(function()

                    checkbox1:render("Enable Test 1", "Showcasing ...")

                    checkbox2:render("Enable Test 2")

                    checkbox3:render("Enable Test 3")

                    slider_float_test:render("Slider\nTest")

                end)



            end) then

                -- You can do whatever you want here. If the code here is read it means that the popup is currently being rendered.

            else

                -- This means that the user clicked outside of the popup bounds (or released the mouse), so it shouldn't be rendered anymore.

                is_popup_active = false

            end

        end



        -- now, the window popup code:



        local open_window_rect_v1 = vec2.new(13, 120)

        local open_window_rect_v2 = vec2.new(123, 150)



        local alpha2 = 120

        if window:is_mouse_hovering_rect(open_window_rect_v1, open_window_rect_v2) then

            alpha2 = 255

        end



        window:render_rect_filled(open_window_rect_v1, open_window_rect_v2, color.black(alpha2), 1.0)

        window:render_rect(open_window_rect_v1, open_window_rect_v2, color.white(alpha2), 1.0, 1.0)

        window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(open_window_rect_v1.x + 27, open_window_rect_v1.y + 7), color.white(255), "Open Me!")



        if window:is_rect_clicked(open_window_rect_v1, open_window_rect_v2) then

            window_popup:set_visibility(true)

            is_window_popup_open = true

        end



        if is_window_popup_open then

            -- window_popup:set_next_window_padding(vec2.new(33, 33))

            window_popup:begin(enums.window_enums.window_resizing_flags.RESIZE_HEIGHT, true, color_picker_test:get(),

            border_color, enums.window_enums.window_cross_visuals.DEFAULT, function()



                local window_popup_title_text = "Window Popup Demo"

                local window_popup_text_centered_x_pos = window:get_text_centered_x_pos(window_popup_title_text)



                window:add_menu_element_pos_offset(vec2.new(window_popup_text_centered_x_pos, 10))

                window:add_text_on_dynamic_pos(color.green_pale(255), window_popup_title_text)

                window:add_separator(3.0, 3.0, 15.0, 0.0, color.new(100, 99, 150, 255))



                window:add_menu_element_pos_offset(vec2.new(30, 20))

                window:begin_group(function()

                    checkbox1:render("Enable Test 1", "Tooltip Test ...")

                    checkbox2:render("Enable Test 2")

                    checkbox3:render("Enable Test 3")

                end)



            end)

        else

            is_window_popup_open = false

        end

    end)

end)


And this is what you should be seeing, after running this code in-game:

If you noticed, in the first image, on the right of the main window, there are some drawings that we havn't covered yet. Try to do that yourself as an excercise.

TIP

You will need to use the following functions: window:render_circle_filled, window:render_circle, window:render_triangle_filled_multicolor, window:render_rect_filled_multicolor, window::render_bezier_quadratic, window:render_bezier_cubic, window:render_text. However, you can be creative, look into the documentation the different possibilities available and make your own design, or if you have ideas, you can always request more features.

Advanceds - 1​
The Advanceds - Animations



If you look closely at the first image, you will notice there are some random circles on the left. These circles are not static, but animated. You are more than welcome to do your own animations, but our windows provide a simple feature to animate widgets. First, we just need to declare the animations (they behave like independant objects)

    -- parameter 1: the id of the animation (integer)

    -- parameter 2: the starting position of the animation (vec2)

    -- parameter 3: the ending position of the animation (vec2)

    -- parameter 4: the starting alpha of the animation (integer)

    -- parameter 5: the ending (max alpha) of the animation (integer)

    -- parameter 6: alpha speed (integer)

    -- parameter 7: movement speed (integer)

    -- parameter 8: animate only once (boolean)

    local animation = window:animate_widget(1, vec2.new(0,0), vec2.new(50, 300), 0, 100, 100, 50, false)

    local animation2 = window:animate_widget(2, vec2.new(0,0), vec2.new(180, 300), 0, 100, 80, 60, false)

    local animation3 = window:animate_widget(3, vec2.new(0,0), vec2.new(210, 300), 0, 100, 100, 50, false)

    local animation4 = window:animate_widget(4, vec2.new(300,0), vec2.new(50, 300), 0, 100, 105, 50, false)


The animation objects that we just created are returning a table. This table contains 2 elements:

1 - current_position (vec2)
2 - alpha (integer)

We are going to use these values to now draw our widgets accordingly:

    window:render_circle(animation.current_position, 10.0, color.new(100, 99, 150, animation.alpha), 3.0)

    window:render_circle(animation2.current_position, 10.0, color.green_pale(animation2.alpha), 3.0)

    window:render_circle(animation3.current_position, 10.0, color.green_pale(animation3.alpha), 3.0)

    window:render_circle(animation4.current_position, 10.0, color.new(100, 99, 150, animation3.alpha), 3.0)


And that's it. We now have some animated circles.

Advanceds - 2​

The Advanceds - Explaining Dynamic Drawing

If you remember, in the previous section we used window:add_menu_element_pos_offset() and :add_text_on_dynamic_pos() function.. I will try to explain how our windows work internally, giving a brief overview so you can understand how this works, more or less.

So, there are 2 ways to draw stuff in a window:




- Statically: function. this is very simple, since you are just basically hardcoding where you want to draw things, and they will be drawn there, not caring about other things that are currently being rendered in the window etc. (Note that all positions that you pass to the functions that draw statically are relative to the current window position, not the screen position. So, if you pass vec2(100, 100), the actual position would be vec2(100 + window_position.x, 100 + window_position.y))




- Dynamically: function. this is a little bit more complex to work with. Let's say there is an internal position variable. This variable's value is a vec2, and it changes according to the dynamic widgets that we render. For example, if the internal position variable currently has value vec2(100, 50) and we render something dynamically (a text, for example), this text will be rendered at the position vec2(100, 50) and this internal position variable will change according to the text bounds. Let's say the text size is vec2(50, 50). In this case, the internal position variable will be (after rendering the text), vec2(150, 100). So far, this doesn't sound too bad, and the only native dynamic drawing functionality (by native I mean the only function that allows you to directly draw in the internal position variable) is the :add_text_on_dynamic_pos function.

However, we can still do cool stuff with this dynamic position offset, since we can manually add space. For example, we can just render a rectangle and then add the rectangle bounds to this internal position variable, so it's taken into account for multiple stuff (for example, scrollbars are dependant on the internal position variable). To do this, we have to use the function :add_artificial_item_bounds function.

By using :add_menu_element_pos_offset, :get_current_context_dynamic_drawing_offset, :add_artificial_item_bounds you can achieve very interesting results.

TIP

Check the "Panel Debug Target - Show Auras Info" to dive deeper into this matter and see some use examples. In this case, I am using static text drawings and making them dynamic, so we can use the scrollbar (necessary since there are many auras and they don't fit on the screen), and also the "Remaining" is a number that varies a lot with time. If we didn't use static text, since the dynamic text varies according to the previous widgets sizes, all the line would have a very ugly flickering all the time, according to the "Remaining" number text size.

"The basic guide ends here. I hope you are having fun creating some cool visuals so far! Check all the available code examples and all the individual functions documentation, with their code examples, and play with them. That's the best way to learn after all. Cya soon as a fellow developer :)"

Best regards, Barney



---

## https://docs.project-sylvanas.net/dev/api/graphics/notifications

Lua Graphics - Notifications Documentation
Overview​

As you might know already, our project have an in-built notifications system. A notification is basically a box that spawns in a given position, containing some information. The cool part about them is that the user can interact with them, allowing you to create interactive functions. For example, if you are a hunter and your pet dies, you can send a notification that warns the user that the pet has died. Since the notifications are interactive, as previously said, you could add a functionality to revive the pet if the notification is clicked.


Basic Functionality Explanation

Using notifications is very simple, since almost everything is handled internally. You just have to keep in mind a couple key points:

1- Callbacks: You can use all notifications functionalities from any callback, since the rendering is handled internally.


2- Positioning: By default, all notifications are rendered in the position that is specified in the main menu (System -> Notifications). However, you can still customize their spawn position, although this is not recommended in general since the user might be expecting all notifications from all plugins to spawn in the same place. You can still do something like the Hunter Plugins notifications customizations, where by default the position is the same as the main menu one, but the user can specifically customize the notifications from your plugin.


3- Identification: Every notification must have its own unique ID, same like with menu elements. This ID is a string, so we recommend using local variables (defined outside of the callbacks) that are easy to recognize for each individual notification. Only 1 notification with the same ID can be active at a time.

Functions 🛠️​
Add Notification 🔔​
Syntax
core.graphics.add_notification(header, message, duration_s, color, x_pos_offset, y_pos_offset, max_background_alpha, length, height)

Parameters
header: string - The information text for the notification that will appear on top.
message: string - The message text for the notification. This is the actual notification information.
duration_s: integer - The duration of the notification in seconds.
color: color - The color of the notification.
x_pos_offset (Optional): number - The x-position offset for the notification. Default is 0.0.
y_pos_offset (Optional): number - The y-position offset for the notification. Default is 0.0.
max_background_alpha (Optional): number - The maximum background alpha value. Default is 0.95.
length (Optional): number - The length offset of the notification (This value adds up to the default notification length). Default is 0.0.
height (Optional): number - The height offset of the notification (This value adds up to the default notification height). Default is 0.0.
Description

Adds a notification with the specified information, message, duration, color, and optional positional offsets, background alpha, length, and height.


Example:
Adding a notification after right mouse button was clicked


---@type color

local color = require("common/color")



local notification_id = "rmb_pressed_notification"



local function notify_rmb_was_pressed()

    -- you can avoid this check if you checked it earlier in your code.

    -- It's just to make sure nothing is rendered while on loading screen.

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return nil

    end



    local is_rmb_pressed = core.input.is_key_pressed(0x02)



    if is_rmb_pressed then

        core.graphics.add_notification(notification_id, "[Notifying]", "RMB Was Pressed!", 5, color.get_rainbow_color(20))

    end

end



Is Notification Clicked 🔔🖱️​
Syntax
core.graphics.is_notification_clicked(id, trigger_after_time)

Parameters
id: string - The ID of the notification to check.
trigger_after_time (Optional): number - The time in seconds after which the notification click is triggered. Default is 0.0.
Returns
boolean: true if the notification has been clicked, false otherwise.
Description

Checks if a notification with the specified message has been clicked, with an optional trigger time delay.

Get Notifications Core Position 📍​
Syntax
core.graphics.get_notifications_core_pos()

Returns
vec2: The core position of the notifications.
Description

Retrieves the core position of the notifications. This is the position that can be customized in the main menu
(System -> Notifications)

Get Notifications Default Size 📏​
Syntax
core.graphics.get_notifications_default_size()

Returns
vec2: The default size of the notifications.
Description

Retrieves the default size of the notifications. This size cannot be modified by user input.

Complete Example​

Lets finish off with an example that summarizes all functionality. The code will add a notification when RMB is pressed by the user. It will spam in the console whether the notification is active or not, and if it's clicked by the user, it will print so in the console and the notification won't be shown again until the LUA modules are reloaded.


Summarizing Example:
Interiorizing the concepts


---@type color

local color = require("common/color")



local notification_id = "rmb_pressed_notification"



local function notify_rmb_was_pressed()

    -- you can avoid this check if you checked it earlier in your code.

    -- It's just to make sure nothing is rendered while on loading screen.

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return nil

    end



    local is_rmb_pressed = core.input.is_key_pressed(0x02)



    if is_rmb_pressed then

        core.graphics.add_notification(notification_id, "[Notifying]", "RMB Was Pressed!", 5, color.get_rainbow_color(20))

    end

end



local notification_ended = false

core.register_on_update_callback(function()

    if notification_ended then

        return

    end



    notify_rmb_was_pressed()



    local is_notification_clicked = core.graphics.is_notification_clicked(notification_id)



    if not is_notification_clicked then

        core.log("Is Notification Appearing On Screen: " .. tostring(core.graphics.is_notification_active(notification_id)))

    else

        core.log("Is Notification Clicked: " .. tostring(is_notification_clicked))

        notification_ended = true

    end

end)


---

## https://docs.project-sylvanas.net/dev/api/graphics

Lua Graphics Module Documentation
Overview​

The Lua Graphics Module provides a range of functions for rendering various graphical elements in Lua scripts. This module empowers developers to create visually engaging user interfaces and enhance in-game visuals.

Register Graphics Callback​
WARNING

This callback should only be used for graphics, as explained in Core - Overview

core.menu.register_on_render_callback(callback: function)

This function registers the menu for interaction. Same like with other callbacks, you can also pass an anonymous function. This is how you would call the callback:
core.menu.register_on_render_callback(function()

     -- your rendering code here

end)


Or:

local function my_render_function()

    -- your rendering code here

end



core.menu.register_on_render_callback(my_render_function)

Functions 🛠️​
Line Of Sight 👁️​
WARNING

In most cases, you should NOT use this function, since it's very expensive. Instead, you should instead use the spell_helper:is_spell_in_line_of_sight() function. See Spell Helper - LOS

Syntax
core.graphics.is_line_of_sight(caster, target)

Parameters
caster: game_object - The caster object.
target: game_object - The target object.
Returns
boolean: true if the target is in line of sight from the caster, false otherwise.
Description

Determines if the target is within the line of sight of the caster.

💡

You can use this function to check visibility between two game objects.

Cursor World Position 👁️​
Syntax
core.graphics.get_cursor_world_position()

Returns
vec3 : The current cursor position's coordinates transformed to 3D dimensions.
Description

Retrieves the current cursor position screen coordinates (2D) and returns it after transforming them to 3D.

Trace Line 🧭​
Syntax
core.graphics.trace_line(pos1, pos2, flags)

Parameters
pos1: vec3 - Starting position.
pos2: vec3 - Ending position.
flags: Collision flags that determine which objects to consider during tracing.
Returns
boolean: true if there is a valid trace line between pos1 and pos2, false otherwise.
Description

Indicates if there is a valid trace line between pos1 and pos2 following the collision flags you provide.

Collision Flags

None,

DoodadCollision     = 0x00000001,

DoodadRender        = 0x00000002,

WmoCollision        = 0x00000010,

WmoRender           = 0x00000020,

WmoNoCamCollision   = 0x00000040,

Terrain             = 0x00000100,

IgnoreWmoDoodad     = 0x00002000,

LiquidWaterWalkable = 0x00010000,

LiquidAll           = 0x00020000,

Cull                = 0x00080000,

EntityCollision     = 0x00100000,

EntityRender        = 0x00200000,



Collision           = DoodadCollision | WmoCollision | Terrain | EntityCollision,

LineOfSight         = WmoCollision | EntityCollision

WARNING

The collision flags are located in enums.collision_flags. You should import the enums module:

---@type enums

local enums = require("common/enums")


Avoid using their values directly, as this is not recommended since these values might change in the future. By importing the enums module, any updates will automatically be reflected in your code.

You can use this function to see which enemies are not in line of sight. You can adjust the flags according to your requirements.

Example:
Here's an example function to gather all units that are not in line of sight within a search distance:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



---@type enums

local enums = require("common/enums")



---@param search_distance number

---@return table<game_object> | nil

local function get_enemies_that_are_not_in_los(search_distance)

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return nil

    end



    local local_player_position = local_player:get_position()



    local enemies = unit_helper:get_enemy_list_around(local_player_position, search_distance, true)



    local not_in_los_enemies = {}



    for _, enemy in ipairs(enemies) do

        local enemy_pos = enemy:get_position()

        -- trace_line will return true if the enemy is in line of sight, as long as we pass the enums.collision_flags.LineOfSight flag

        local is_in_los = core.graphics.trace_line(local_player_position, enemy_pos, enums.collision_flags.LineOfSight)



        if not is_in_los then

            table.insert(not_in_los_enemies, enemy)

        end

    end



    return not_in_los_enemies

end

NOTE

For this example, to check if something is in LOS (line of sight), you could also use the core.graphics.is_line_of_sight function, defined earlier.

World to Screen 🌐➡️🖥️​
Syntax
core.graphics.w2s(position)

Parameters
position: vec3 - The 3D world position to convert.
Returns
vec2: The 2D screen position corresponding to the 3D world position.
Description

Converts a 3D world position to a 2D screen position, facilitating the rendering of objects in screen space.

WARNING

Before using the return value, you should make sure it's not nil, since a vec3 out of the screen won't be converted and will return nil.

Example:
Drawing text at the 2D position of a given unit
---@type color

local color = require("common/color")



---@param unit game_object

---@param text string

local function draw_text_at_unit_screen_position(unit, text)

    if not unit then

        return

    end



    local unit_position = unit:get_position()

    local unit_screen_position = core.graphics.w2s(unit_position)

    if not unit_screen_position then

        return

    end



    core.graphics.text_2d(text, unit_screen_position, 16, color.cyan(230))

end

Is Menu Open 📋🔍​
Syntax
core.graphics.is_menu_open()

Returns
boolean: true if the main menu is visible, false otherwise.
Description

Checks if the main menu is currently open.

Get Screen Size 🖥️📏​
Syntax
core.graphics.get_screen_size()

Returns
vec2: The width and height of the screen.
Description

Retrieves the current screen size in pixels.

Render 2D Text 📝​
Syntax
core.graphics.text_2d(text, position, font_size, color, centered, font_id)

Parameters
text: string - The text to render.
position: vec2 - The position where the text will be rendered.
font_size: number - The font size of the text.
color: color - The color of the text.
centered (Optional): boolean - Indicates whether the text should be centered at the specified position. Default is false.
font_id (Optional): integer - The font ID. Default is 0.
Description

Renders 2D text on the screen at the specified position with the given font size and color.

Render 3D Text 📝🌐​
Syntax
core.graphics.text_3d(text, position, font_size, color, centered, font_id)

Parameters
text: string - The text to render.
position: vec3 - The position in 3D space where the text will be rendered.
font_size: number - The font size of the text.
color: color - The color of the text.
centered (Optional): boolean - Indicates whether the text should be centered at the specified position. Default is false.
font_id (Optional): integer - The font ID. Default is 0.
Description

Renders 3D text in the world at the specified position with the given font size and color.

Get Text Width 📐​
Syntax
core.graphics.get_text_width(text, font_size, font_id)

Parameters
text: string - The text to measure.
font_size: number - The font size of the text.
font_id (Optional): integer - The font ID. Default is 0.
Returns
number: The width of the text.
Description

Calculates and returns the width of the specified text, useful for aligning text elements.

Draw 2D Line ✏️​
Syntax
core.graphics.line_2d(start_point, end_point, color, thickness)

Parameters
start_point: vec2 - The start point of the line.
end_point: vec2 - The end point of the line.
color: color - The color of the line.
thickness (Optional): number - The thickness of the line. Default is 1.
Description

Draws a 2D line between two points with the specified color and optional thickness.

Draw 3D Line ✏️🌐​
Syntax
core.graphics.line_3d(start_point, end_point, color, thickness)

Parameters
start_point: vec3 - The start point of the line in 3D space.
end_point: vec3 - The end point of the line in 3D space.
color: color - The color of the line.
thickness (Optional): number - The thickness of the line. Default is 1.
Description

Draws a 3D line between two points with the specified color and optional thickness.


Example:
Drawing A Line From Local Player To a Unit

---@type color

local color = require("common/color")



---@param unit game_object

local function draw_line_to_unit(unit)

    if not unit then

        return

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return nil

    end



    local local_player_position = local_player:get_position()

    local unit_position = unit:get_position()



    core.graphics.line_3d(local_player_position, unit_position, color.cyan(220), 5.0)

end

Draw 2D Rectangle Outline 🖼️​
Syntax
core.graphics.rect_2d(top_left_point, width, height, color, thickness, rounding)

Parameters
top_left_point: vec2 - The top-left corner point of the rectangle.
width: number - The width of the rectangle.
height: number - The height of the rectangle.
color: color - The color of the rectangle outline.
thickness (Optional): number - The thickness of the outline. Default is 1.
rounding (Optional): number - The rounding of corners. Default is 0.
Description

Draws an outlined 2D rectangle with the specified dimensions, color, and optional thickness and rounding.

Draw 2D Filled Rectangle 🖼️🖌️​
Syntax
core.graphics.rect_2d_filled(top_left_point, width, height, color, rounding)

Parameters
top_left_point: vec2 - The top-left corner point of the rectangle.
width: number - The width of the rectangle.
height: number - The height of the rectangle.
color: color - The fill color of the rectangle.
rounding (Optional): number - The rounding of corners. Default is 0.
Description

Draws a filled 2D rectangle with the specified dimensions, color, and optional rounding.


Example:
Drawing a 2d filled rect at cursor screen position

---@type color

local color = require("common/color")



local function render_rect_2d_at_cursor_screen_pos()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return nil

    end



    local cursor_pos_2d = core.get_cursor_position()



    core.graphics.rect_2d_filled(cursor_pos_2d, 200, 50, color.cyan_pale(200))

end


Draw 3D Rectangle Outline 🖼️🌐​
Syntax
core.graphics.rect_3d(p1, p2, p3, p4, color, thickness)

Parameters
p1, p2, p3, p4: vec3 - Four points defining the corners of the rectangle in 3D space.
color: color - The color of the rectangle outline.
thickness (Optional): number - The thickness of the outline. Default is 1.
Description

Draws an outlined 3D rectangle with the specified corner points, color, and optional thickness.


Example:
How to Render a 3D Rectangle From Local Player to Mouse Position


---@type color

local color = require("common/color")



local function render_rect_3d_to_mouse()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return nil

    end



    local local_player_position = local_player:get_position()

    local cursor_position_3d = core.graphics.get_cursor_world_position()



    core.graphics.rect_3d(local_player_position, cursor_position_3d, 5.0, color.cyan_pale(200), 30.0, 1.5)

end


Draw 3D Filled Rectangle 🖼️🖌️🌐​
Syntax
core.graphics.rect_3d_filled(p1, p2, p3, p4, color)

Parameters
p1, p2, p3, p4: vec3 - Four points defining the corners of the rectangle in 3D space.
color: color - The fill color of the rectangle.
Description

Draws a filled 3D rectangle with the specified corner points and color.

Draw 2D Circle Outline 🎯​
Syntax
core.graphics.circle_2d(center, radius, color, thickness)

Parameters
center: vec2 - The center point of the circle.
radius: number - The radius of the circle.
color: color - The color of the circle outline.
thickness (Optional): number - The thickness of the outline. Default is 1.
Description

Draws an outlined 2D circle with the specified center, radius, color, and optional thickness.

Draw 2D Filled Circle 🎯🖌️​
Syntax
core.graphics.circle_2d_filled(center, radius, color)

Parameters
center: vec2 - The center point of the circle.
radius: number - The radius of the circle.
color: color - The fill color of the circle.
Description

Draws a filled 2D circle with the specified center, radius, and color.

Draw 3D Circle Outline 🎯🌐​
Syntax
core.graphics.circle_3d(center, radius, color, thickness)

Parameters
center: vec3 - The center point of the circle in 3D space.
radius: number - The radius of the circle.
color: color - The color of the circle.
thickness (Optional): number - The thickness of the lines forming the circle.
Description

Draws an outlined 3D circle with the specified center, radius, color, and optional thickness.


Example:
How to Render a 3D Circle at Unit's Position


---@type color

local color = require("common/color")



local function render_rect_3d_at_unit_position(unit)

    if not unit then

        return

    end



    -- you can avoid this check if you checked it earlier in your code.

    -- It's just to make sure nothing is rendered while on loading screen.

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return nil

    end



    local unit_position = unit:get_position()

    core.graphics.circle_3d(unit_position, 5.0, color.cyan(230), 40, 1.5)

end


Draw 3D Circle Outline Percentage 🎯🌐📊​
Syntax
core.graphics.circle_3d_percentage(center, radius, color, percentage, thickness)

Parameters
center: vec3 - The center point of the circle in 3D space.
radius: number - The radius of the circle.
color: color - The color of the circle outline.
percentage: number - The percentage of the circle to render.
thickness (Optional): number - The thickness of the outline. Default is 1.
Description

Draws an outlined 3D circle with the specified center, radius, color, and percentage of the circle to render. Optionally, the thickness can be specified.

TIP

This function might be useful to track casts, since you can render the circle up to a unit's current cast completion percentage, for example.

Draw 3D Filled Circle 🎯🖌️🌐​
Syntax
core.graphics.circle_3d_filled(center, radius, color)

Parameters
center: vec3 - The center point of the circle in 3D space.
radius: number - The radius of the circle.
color: color - The fill color of the circle.
Description

Draws a filled 3D circle with the specified center, radius, and color.

Draw 2D Filled Triangle 🔺🖌️​
Syntax
core.graphics.triangle_2d_filled(p1, p2, p3, color)

Parameters
p1, p2, p3: vec2 - Three points defining the corners of the triangle in 2D space.
color: color - The fill color of the triangle.
Description

Draws a filled 2D triangle with the specified corner points and color.

Draw 3D Filled Triangle 🔺🖌️🌐​
Syntax
core.graphics.triangle_3d_filled(p1, p2, p3, color)

Parameters
p1, p2, p3: vec3 - Three points defining the corners of the triangle in 3D space.
color: color - The fill color of the triangle.
Description

Draws a filled 3D triangle with the specified corner points and color.

---

