---
title: "Core Functions"
source: "https://docs.project-sylvanas.net/dev/api/core"
crawled: "2026-07-14"
---

# Core Functions

## Overview

This module contains a collection of essential functions that you will probably need sooner or later in your scripts. This module includes utilities for logging, callbacks, time management, and accessing game information.  


## Callbacks - Brief Explanation

This is essentially the most important part of scripting, since most of your code must be ran inside a callback.  

**What is a Callback?**  
A callback is a function that you write, which you then pass to the game engine or framework. The engine doesn't execute this function immediately. Instead, it "calls back" to your function at a specific time or when a particular event occurs in the game. Think of it like leaving your phone number with a friend (the game engine) and asking them to call you (execute your function) when a certain event happens.  

**Why Use Callbacks?**  
Callbacks allow your game to respond to events without constantly checking for them. This makes your code more efficient and easier to manage. Instead of writing code that keeps asking, "Has the player pressed a button yet? Has an enemy appeared yet?" you can simply tell the game engine, "When this happens, run this function." So, all games use callbacks to run, and same with WoW.  

**Real-World Analogy**  

Imagine you're waiting for a package to be delivered. You don't stand by the door all day waiting for it (which would be like constantly checking in a loop). Instead, you might continue with your day, and when the doorbell rings (the event), you go to answer it (the callback function is executed).

What was explained is what is a callback in general in the context of videogames. In our case, we have multiple events that our callbacks will be listening to. These are the following:

-   **On Update** — This is the callback that you will use to run your logic most of the time. The code placed inside this callback is called at a **reduced speed**, relative to the speed of `On Render`. It's ideal for logic that doesn't need to be executed every frame. In a game where 95% of spells have a global cooldown, 50% of spells are cast, and units move at 7 yards per second, you don't need to read all the information and check everything every frame. Doing so at 120 FPS means you're, for example, checking the position of all units 120 times per second, which is unnecessary. That's where `On Update` comes in.
    
-   **On Render** — This is a callback used **only for rendering graphics**, like rectangles, circles, etc. (See [graphics](https://docs.project-sylvanas.net/dev/api/graphics)). It is the **most important and central callback**, placed within the game inside DirectX in a part called `EndScene`. Every time DirectX is about to render something, this callback is called. That's why it's called `On Render`, and it's the callback that's called the most times of all—**exactly once per frame**. This allows the game to draw the graphics and call your callback so that you can draw at the same speed, neither one frame more nor less, ensuring it feels natural within the game. While you could place your logic here, common sense suggests otherwise.
    
-   **On Render Menu** — This is a callback used **only for rendering menu elements**. (See [Menu Elements](https://docs.project-sylvanas.net/dev/api/ui))
    
-   **On Render Control Panel** — This is a very specialized callback that will be used **ONLY** to handle the control panel elements. (See [Control Panel](https://docs.project-sylvanas.net/dev/api/ui/control-panel))
    
-   **On Spell Cast** — This callback will only trigger if a spell is cast, so it might be useful to control some specific cooldowns or how your spells (or other game objects) are being cast.
    
-   **On Legit Spell Cast** — This callback will only trigger if a spell is **MANUALLY** cast by the player.
    

> **note**
> 
> As you will see in the following examples, all callbacks expect you to pass a function. This function must contain all the code that will be read in the case that the event that the callback is listening to is triggered.  
  
You can pass it anonymously:

```lua
core.register_on_render_callback(function()
    -- your render code here
end)
```

Or you can pass a defined function:

```lua
local function all_my_render_code_function()
    -- your render code here
end
core.register_on_render_callback(all_my_render_code_function)
```

On render callback was used just as an example, but this behaviour is the same for all available callbacks.

## Callback Functions

### `core.register_on_pre_tick_callback`

**Syntax:**
```lua
core.register_on_pre_tick_callback(callback: function)
```

**Parameters:**
- `callback`: `function` - The function to be called before each game tick.

**Description:** Registers a callback function to be executed before each game tick.

**Example Usage:**
```lua
core.register_on_pre_tick_callback(function()
    -- Code to execute before each game tick
end)
```

---

### `core.register_on_update_callback`

**Syntax:**
```lua
core.register_on_update_callback(callback: function)
```

**Parameters:**
- `callback`: `function` - The function to be called on each frame update.

**Description:** Registers a callback function to be executed on each frame update.

**Example Usage:**
```lua
core.register_on_update_callback(function()
    -- Code to execute every frame
end)
```

---

### `core.register_on_render_callback`

**Syntax:**
```lua
core.register_on_render_callback(callback: function)
```

**Parameters:**
- `callback`: `function` - The function to be called during the render phase.

**Description:** Registers a callback function to be executed during the render phase.

**Example Usage:**
```lua
local function on_render()
    -- Rendering code here
end
core.register_on_render_callback(on_render)
```

---

### `core.register_on_render_menu_callback`

**Syntax:**
```lua
core.register_on_render_menu_callback(callback: function)
```

**Parameters:**
- `callback`: `function` - The function to render custom menu elements.

**Description:** Registers a callback function to render custom menu elements.

> **warning**
> 
> Avoid calling game functions within this callback. It should be used solely for rendering menus and variables.

**Example Usage:**
```lua
local function render_menu()
    -- Menu rendering code here
end
core.register_on_render_menu_callback(render_menu)
```

---

### `core.register_on_render_control_panel_callback`

**Syntax:**
```lua
core.register_on_render_control_panel_callback(callback: function)
```

**Parameters:**
- `callback`: `function` - The function to render control panel elements.

**Description:** Registers a callback function to render control panel elements.

**Example Usage:**
```lua
local function render_control_panel()
    -- Control panel rendering code here
end
core.register_on_render_control_panel_callback(render_control_panel)
```

---

### `core.register_on_render_window_callback`

**Syntax:**
```lua
core.register_on_render_window_callback(callback: function)
```

**Parameters:**
- `callback`: `function` - The function to be called during window rendering.

**Description:** Registers a callback function to be executed during window rendering phase.

**Example Usage:**
```lua
core.register_on_render_window_callback(function()
    -- Window rendering code here
end)
```

---

### `core.register_on_spell_cast_callback`

**Syntax:**
```lua
core.register_on_spell_cast_callback(callback: function)
```

**Parameters:**
- `callback`: `function` - The function to be called when any spell is cast.

**Description:** Registers a callback function that is invoked whenever any spell is cast in the game, including spells cast by the player, allies, and enemies.

**Callback Data Structure:**

| Field | Type | Description |
|-------|------|-------------|
| `spell_id` | `number` | Unique identifier for the spell |
| `caster` | `game_object\|nil` | The game object that cast the spell |
| `target` | `game_object\|nil` | The game object targeted by the spell |
| `spell_cast_time` | `number` | The time when the spell was cast |

**Example Usage:**
```lua
local function on_spell_casted(data)
    -- Access spell data
    local spell_name = core.spell_book.get_spell_name(data.spell_id)
    core.log(string.format("Spell cast detected: %s", spell_name))
end
core.register_on_spell_cast_callback(on_spell_casted)
```

---

### `core.register_on_legit_spell_cast_callback`

**Syntax:**
```lua
core.register_on_legit_spell_cast_callback(callback: function)
```

**Parameters:**
- `callback`: `function` - The function to be called when the local player casts a spell, including unsuccessful attempts.

**Description:** Registers a callback function that is invoked when the local player casts a spell, including unsuccessful attempts.

**Example Usage:**
```lua
local function on_legit_spell_cast(data)
    -- Handle local player's spell cast
end
core.register_on_legit_spell_cast_callback(on_legit_spell_cast)
```

> **note**
> 
> The "data" parameter is filled with the ID of the spell that was just casted. You can check the way this callback works by adding a core.log(tostring(data)) call inside the function called by the callback.

## Logging - An Important Tool

## Use Logs In Your Code!

Adding debug logs is a very powerfull tool that you should use in all your plugins. This will help you find bugs and typos very easily. One option that we recommend is that you add a debug local variable (boolean) at the top of your code. When true, the debug for your code will be enabled. For example:

```lua
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
```

Obviously, this is a very simple example without any real logic or functionality, but it was showcased here just so you see the recommended workflow. All these prints will only work if your debug variable is true, which is something you can change in less than a second.

### Logging - Functions

### `core.log`

**Syntax:**
```lua
core.log(message: string)
```

**Parameters:**
- `message`: `string` - The message to log.

**Description:** Logs a standard message.

**Example Usage:**
```lua
core.log("This is a standard log message.")
```

> **tip**
> 
> Use LUA's in-built strings function to format your logs. For example, to pass from boolean or number to string, you would have to use the tostring() function. Example: Logging the cooldown of a spell:

```lua
local function print_spell_cd(spell_id)
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        return
    end
    local spell_cd = core.spell_book.get_spell_cooldown(spell_id)
    core.log("Remaining Spell (ID: " .. tostring(spell_id) .. ") CD: " .. tostring(spell_cd) .. "s")
end
```

---

### `core.log_error`

**Syntax:**
```lua
core.log_error(message: string)
```

**Parameters:**
- `message`: `string` - The error message to log.

**Description:** Logs an error message.

**Example Usage:**
```lua
core.log_error("An error has occurred.")
```

---

### `core.log_warning`

**Syntax:**
```lua
core.log_warning(message: string)
```

**Parameters:**
- `message`: `string` - The warning message to log.

**Description:** Logs a warning message.

**Example Usage:**
```lua
core.log_warning("This is a warning message.")
```

---

### `core.log_file`

**Syntax:**
```lua
core.log_file(message: string)
```

**Parameters:**
- `message`: `string` - The message to log to a file.

**Description:** Logs a message to a file.

> **warning**
> 
> Access to `core.log_file` may be restricted due to security considerations.

**File Logging for Third-Party Developers:**

For third-party developers who need file logging capabilities, you can use `core.create_log_file` and `core.write_log_file` from the [File I/O](https://docs.project-sylvanas.net/dev/api/file-io) module:

```lua
-- Create and write to a custom log file
core.create_log_file("combat.log")
core.write_log_file("combat.log", "Addon started\n")
core.write_log_file("combat.log", "Target acquired: " .. tostring(unit_name) .. "\n")
```

> **tip**
> 
> For the quickest and easiest logging solution, we recommend using the [izi.log](https://docs.project-sylvanas.net/dev/libraries/izi#izilog) helper functions from the izi library. It handles file creation and management automatically, so you don't have to manually build your log files every time.

For more details on file operations, see [File I/O](https://docs.project-sylvanas.net/dev/api/file-io).

## Time and Performance Functions

### `core.get_ping`

**Syntax:**
```lua
core.get_ping() -> number
```

**Returns:** `number` - The current network ping.

**Description:** Retrieves the current network ping.

**Example Usage:**
```lua
local ping = core.get_ping()
core.log("Current ping: " .. ping .. " ms")
```

---

### `core.time`

**Syntax:**
```lua
core.time() -> number
```

**Returns:** `number` - The time in seconds since the PS injection happened.

> **warning**
> 
> Dont use this time to work with server info like buff_end_time, spell_cast_end_time, they work in milliseconds and only with core.game_time()

**Description:** Returns the time elapsed since the script was injected.

**Example Usage:**
```lua
local script_time = core.time()
core.log("Time since script injection: " .. script_time .. " s")
```

---

### `core.game_time`

**Syntax:**
```lua
core.game_time() -> number
```

**Returns:** `number` - The time in milliseconds since the game started.

> **note**
> 
> This is the time that should be used to work with game info like buff_end_time, spell_cast_end_time, etc...

**Description:** Returns the time elapsed since the game started.

**Example Usage:**
```lua
local game_time = core.game_time()
core.log("Game time elapsed: " .. game_time .. " ms")
```

---

### `core.delta_time`

**Syntax:**
```lua
core.delta_time() -> number
```

**Returns:** `number` - The time in milliseconds since the last frame.

**Description:** Returns the time elapsed since the last frame.

**Example Usage:**
```lua
local dt = core.delta_time()
-- Use dt for frame-dependent calculations
```

---

### `core.cpu_time`

**Syntax:**
```lua
core.cpu_time() -> number
```

**Returns:** `number` - The CPU time used.

**Description:** Retrieves the CPU time used.

**Example Usage:**
```lua
local cpu_time = core.cpu_time()
core.log("CPU time used: " .. cpu_time)
```

---

### `core.cpu_ticks`

**Syntax:**
```lua
core.cpu_ticks() -> number
```

**Returns:** `number` - The current CPU tick count.

**Description:** Retrieves the current CPU tick count. Useful for high-precision performance profiling.

**Example Usage:**
```lua
local start_ticks = core.cpu_ticks()
-- ... code to profile ...
local end_ticks = core.cpu_ticks()
local elapsed = (end_ticks - start_ticks) / core.cpu_ticks_per_second()
core.log("Operation took: " .. elapsed .. " seconds")
```

---

### `core.cpu_ticks_per_second`

**Syntax:**
```lua
core.cpu_ticks_per_second() -> number
```

**Returns:** `number` - The number of CPU ticks per second.

**Description:** Retrieves the number of CPU ticks per second. Use this in conjunction with `core.cpu_ticks()` for accurate performance measurements.

**Example Usage:**
```lua
local ticks_per_second = core.cpu_ticks_per_second()
core.log("CPU ticks per second: " .. ticks_per_second)
```

---

## Game Information Functions

### `core.get_map_id`

**Syntax:**
```lua
core.get_map_id() -> number
```

**Returns:** `number` - The current map ID.

**Description:** Retrieves the ID of the current map.

**Example Usage:**
```lua
local map_id = core.get_map_id()
core.log("Current map ID: " .. map_id)
```

---

### `core.get_map_name`

**Syntax:**
```lua
core.get_map_name() -> string
```

**Returns:** `string` - The name of the current map.

**Description:** Retrieves the name of the current map.

**Example Usage:**
```lua
local map_name = core.get_map_name()
core.log("Current map: " .. map_name)
```

---

### `core.get_cursor_position`

**Syntax:**
```lua
core.get_cursor_position() -> vec2
```

**Returns:** `vec2` - The current cursor position.

**Description:** Retrieves the current cursor position on the screen.

**Example Usage:**
```lua
local cursor_pos = core.get_cursor_position()
core.log(string.format("Cursor position: (%.2f, %.2f)", cursor_pos.x, cursor_pos.y))
```

---

### `core.get_instance_id`

**Syntax:**
```lua
core.get_instance_id() -> integer
```

**Returns:** `integer` - The ID of the current instance.

**Description:** Retrieves the ID of the current instance.

---

### `core.get_instance_name`

**Syntax:**
```lua
core.get_instance_name() -> string
```

**Returns:** `string` - The name of the current instance.

**Description:** Retrieves the name of the current instance.

---

### `core.get_instance_type`

**Syntax:**
```lua
core.get_instance_type() -> string
```

**Returns:** `string` - The type of the current instance.

**Description:** Retrieves the type of the current instance (e.g., "raid", "dungeon", "arena", "battleground", "none").

**Example Usage:**
```lua
local instance_type = core.get_instance_type()
if instance_type == "raid" then
    core.log("Currently in a raid!")
end
```

---

### `core.get_difficulty_id`

**Syntax:**
```lua
core.get_difficulty_id() -> integer
```

**Returns:** `integer` - The ID of the current instance difficulty.

**Description:** Retrieves the ID of the current instance difficulty.

---

### `core.get_difficulty_name`

**Syntax:**
```lua
core.get_difficulty_name() -> string
```

**Returns:** `string` - The name of the current instance's difficulty.

**Description:** Retrieves the name of the current instance's difficulty (e.g., "Normal", "Heroic", "Mythic").

---

### `core.get_keystone_level`

**Syntax:**
```lua
core.get_keystone_level() -> integer
```

**Returns:** `integer` - The level of the Mythic+ keystone.

**Description:** Returns the Mythic+ keystone item on your bag.

---

### `core.get_height_for_position`

**Syntax:**
```lua
core.get_height_for_position(position: vec3) -> number
```

**Parameters:**
- `position`: `vec3` - The 3D coordinates for which to get the height.

**Returns:** `number` - The height value at the given position.

**Description:** Returns the height at the given position in the game world.

---

### `core.get_game_version`

**Syntax:**
```lua
core.get_game_version() -> string
```

**Returns:** `string` - The current game version.

**Description:** Returns the current game version. Possible values: `"Midnight"`, `"Tbc"`, `"Vanilla"`, `"Mop"`, `"Titan"`.

**Example Usage:**
```lua
local version = core.get_game_version()
if version == "Midnight" then
    core.log("Running on Retail (12.X) !")
elseif version == "Vanilla" then
    core.log("Running on Classic Era (1.X) !")
elseif version == "Tbc" then
    core.log("Running on Classic Tbc (2.X) !")
elseif version == "Mop" then
    core.log("Running on Classic Mop (5.X) !")
end
```

---

### `core.get_game_region`

**Syntax:**
```lua
core.get_game_region() -> string
```

**Returns:** `string` - The current game region.

**Description:** Returns the current game region. Possible values: `"West"`, `"China"`.

**Example Usage:**
```lua
local region = core.get_game_region()
core.log("Playing in region: " .. region)
```

---

### `core.is_main_menu_open`

**Syntax:**
```lua
core.is_main_menu_open() -> boolean
```

**Returns:** `boolean` - `true` if the main menu is open, `false` otherwise.

**Description:** Checks if the main menu is currently open.

**Example Usage:**
```lua
if core.is_main_menu_open() then
    core.log("Main menu is open")
end
```

---

### `core.get_exact_game_version`

**Syntax:**
```lua
core.get_exact_game_version() -> string
```

**Returns:** `string` - The exact game version string.

**Description:** Returns the exact game version including build number (e.g. "11.1.0.59069").

**Example Usage:**
```lua
local version = core.get_exact_game_version()
core.log("Exact game version: " .. version)
```

---

### `core.set_window_foremost`

**Syntax:**
```lua
core.set_window_foremost() -> nil
```

**Description:** Forces the game window to the foreground.

**Example Usage:**
```lua
core.set_window_foremost()
```

---

### `core.is_textbox_focused`

**Syntax:**
```lua
core.is_textbox_focused() -> boolean
```

**Returns:** `boolean` - `true` if a textbox (such as chat) is currently focused, `false` otherwise.

**Description:** Returns whether a textbox (like chat) is currently focused. Useful for disabling keybinds while the player is typing.

**Example Usage:**
```lua
if not core.is_textbox_focused() then
    -- Safe to process keybinds
end
```

---

### `core.play_sound_by_id`

**Syntax:**
```lua
core.play_sound_by_id(id: number) -> nil
```

**Parameters:**
- `id`: `number` - The game sound ID to play.

**Description:** Plays a game sound by its sound ID.

**Example Usage:**
```lua
core.play_sound_by_id(8959)
```

---

### `core.get_mouse_wheel_delta`

**Syntax:**
```lua
core.get_mouse_wheel_delta() -> number
```

**Returns:** `number` - The mouse wheel scroll delta for the current frame.

**Description:** Returns the mouse wheel scroll delta for the current frame. Positive values indicate scrolling up, negative values indicate scrolling down.

**Example Usage:**
```lua
local delta = core.get_mouse_wheel_delta()
if delta ~= 0 then
    core.log("Mouse wheel delta: " .. delta)
end
```

---

## HTTP Functions

The HTTP module allows you to make asynchronous HTTP requests for fetching remote data such as JSON, text, or images.

### `core.http_get`

**Syntax:**
```lua
-- Without headers
core.http_get(url: string, callback: function)
-- With headers
core.http_get(url: string, headers: table, callback: function)
```

**Parameters:**
- `url`: `string` - The URL to fetch.
- `headers` (optional): `table<string, string>` - HTTP headers to send with the request.
- `callback`: `function` - Function called when the request completes.

**Callback Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `http_code` | `integer` | HTTP status code (200, 404, etc). Transport failure may be 0. |
| `content_type` | `string` | Server content type |
| `response_data` | `string` | Raw response body (binary safe) |
| `response_headers` | `string` | Response headers dump |

**Description:** Performs an asynchronous HTTP GET request. This API is generally used to fetch remote data (JSON, text, images, etc).

**Example Usage - Simple Request:**
```lua
core.http_get("https://httpbin.org/get", function(http_code, content_type, response_data, response_headers)
    core.log("Status: " .. http_code)
    core.log("Response: " .. response_data)
end)
```

**Example Usage - With Headers:**
```lua
core.http_get("https://httpbin.org/get", {
    ["Authorization"] = "Bearer token123",
    ["User-Agent"] = "MyApp/1.0",
    ["Accept"] = "application/json"
}, function(http_code, content_type, response_data, response_headers)
    core.log("Status: " .. http_code)
    core.log("Response: " .. response_data)
end)
```

**Example Usage - Download and Load Texture:**
```lua
core.http_get("https://example.com/image.png", function(http_code, content_type, response_data, response_headers)
    if http_code == 200 and response_data and #response_data > 0 then
        local texture_id, width, height = core.graphics.load_texture(response_data)
        if texture_id then
            core.log("Texture loaded! ID: " .. texture_id .. ", Size: " .. width .. "x" .. height)
        end
    end
end)
```

---

### `core.http_post`

**Syntax:**
```lua
-- Without headers
core.http_post(url: string, body: string, callback: function)
-- With headers
core.http_post(url: string, headers: table, body: string, callback: function)
```

**Parameters:**
- `url`: `string` - The URL to send the POST request to.
- `headers` (optional): `table<string, string>` - HTTP headers to send with the request.
- `body`: `string` - The request body to send.
- `callback`: `function` - Function called when the request completes.

**Callback Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `http_code` | `integer` | HTTP status code (200, 404, etc). Transport failure may be 0. |
| `content_type` | `string` | Server content type |
| `response_data` | `string` | Raw response body (binary safe) |
| `response_headers` | `string` | Response headers dump |

**Description:** Performs an asynchronous HTTP POST request. Supports two overloads: one without headers and one with headers.

**Example Usage - Simple POST:**
```lua
core.http_post("https://httpbin.org/post", '{"key": "value"}', function(http_code, content_type, response_data, response_headers)
    core.log("Status: " .. http_code)
    core.log("Response: " .. response_data)
end)
```

**Example Usage - With Headers:**
```lua
core.http_post("https://httpbin.org/post", {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer token123"
}, '{"key": "value"}', function(http_code, content_type, response_data, response_headers)
    core.log("Status: " .. http_code)
    core.log("Response: " .. response_data)
end)
```

---

## Inventory

> **note**
> 
> See [Inventory Helper](https://docs.project-sylvanas.net/dev/libraries/mini-libs/inventory-helper) for more info.

### `core.inventory.get_items_in_bag`

**Syntax:**
```lua
core.inventory.get_items_in_bag(id: integer) -> table<item_slot_info>
```

**Parameters:**
- `id`: `integer` - The bag ID.

**Returns:** `table<item_slot_info>` - A table containing the item data.

> **note**
> 
> The item slot info contains 2 members:
> - `.slot_id` -> the id of the slot
> - `.object` -> the item itself (game_object)

**Description:** This function returns all the items in the bag with the ID that you pass as parameter. This is a low-level function, and we recommend, like always, to use our LUA libraries that we crafted so the development is easier for everyone. For more info, check out the [Inventory Helper](https://docs.project-sylvanas.net/dev/libraries/mini-libs/inventory-helper) library.

> **note**
> 
> **Bag IDs:**
> - `-2` for the keyring
> - `-4` for the tokens bag
> - `0` = backpack, `1` to `4` for the bags on the character
> 
> **While bank is opened:**
> - `-1` for the bank content
> - `5` to `11` for bank bags (numbered left to right, was 5-10 prior to TBC expansion, 2.0 game version)
> 
> Check [BagId](https://wowwiki-archive.fandom.com/wiki/BagId) for more info.

---

### `core.inventory.get_num_bag_slots`

**Syntax:**
```lua
core.inventory.get_num_bag_slots(bag_id: integer) -> integer
```

**Parameters:**
- `bag_id`: `integer` - The bag ID (see bag ID reference above).

**Returns:** `integer` - The number of slots in the specified bag.

**Description:** Returns the total number of slots available in the specified bag container.

**Example Usage:**
```lua
-- Check how many slots the backpack has
local slots = core.inventory.get_num_bag_slots(0)
core.log("Backpack has " .. slots .. " slots")
```

---

### `core.inventory.get_total_repair_cost`

**Syntax:**
```lua
core.inventory.get_total_repair_cost() -> integer
```

**Returns:** `integer` - The total repair cost in copper.

**Description:** Returns the total cost to repair all equipped items, in copper. Divide by 10000 for gold, by 100 for silver.

**Example Usage:**
```lua
local cost = core.inventory.get_total_repair_cost()
local gold = math.floor(cost / 10000)
local silver = math.floor((cost % 10000) / 100)
core.log(string.format("Repair cost: %dg %ds", gold, silver))
```

---

### `core.inventory.get_gold`

**Syntax:**
```lua
core.inventory.get_gold() -> integer
```

**Returns:** `integer` - The player's current gold in copper.

**Description:** Returns the player's total gold amount in copper. Divide by 10000 for gold, by 100 for silver.

**Example Usage:**
```lua
local copper = core.inventory.get_gold()
local gold = math.floor(copper / 10000)
local silver = math.floor((copper % 10000) / 100)
local remaining_copper = copper % 100
core.log(string.format("Player gold: %dg %ds %dc", gold, silver, remaining_copper))
```

---

## Game UI Functions

For game UI related functions such as loot window, battlefield status, cursor position, and more, see the dedicated [Game UI](https://docs.project-sylvanas.net/dev/api/game-ui) documentation.

---

## File I/O Functions

For file operations including reading/writing data files, log files, and accessing game files, see the dedicated [File I/O](https://docs.project-sylvanas.net/dev/api/file-io) documentation.

---

## Character Functions

### `core.character.get_combat_rating_bonus`

**Syntax:**
```lua
core.character.get_combat_rating_bonus(rating_index: integer) -> number
```

**Parameters:**
- `rating_index`: `integer` - The combat rating index (e.g. crit, haste, mastery).

**Returns:** `number` - The combat rating bonus for the given rating index.

**Description:** Returns the combat rating bonus for a given rating index (crit, haste, mastery, etc.).

**Example Usage:**
```lua
local crit_bonus = core.character.get_combat_rating_bonus(9)
core.log("Crit rating bonus: " .. crit_bonus)
```

---

### `core.character.get_combat_rating_bonus_for_combat_rating_value`

**Syntax:**
```lua
core.character.get_combat_rating_bonus_for_combat_rating_value(rating_index: integer, value: integer) -> number
```

**Parameters:**
- `rating_index`: `integer` - The combat rating index.
- `value`: `integer` - The hypothetical rating value to evaluate.

**Returns:** `number` - The bonus that the hypothetical rating value would provide.

**Description:** Returns what bonus a hypothetical rating value would provide for a given rating index. Useful for simulating stat changes.

**Example Usage:**
```lua
local haste_bonus = core.character.get_combat_rating_bonus_for_combat_rating_value(18, 1000)
core.log("1000 haste rating would give: " .. haste_bonus .. "% bonus")
```

---

### `core.character.get_realm_name`

**Syntax:**
```lua
core.character.get_realm_name() -> string
```

**Returns:** `string` - The connected realm's display name, or an empty string when it is unavailable.

**Description:** Returns the connected realm's display name. The result may contain spaces and punctuation, so use it for UI text and player-facing messages.

**Example Usage:**
```lua
local realm_name = core.character.get_realm_name()
core.log("Connected realm: " .. realm_name)
```

---

### `core.character.get_normalized_realm_name`

**Syntax:**
```lua
core.character.get_normalized_realm_name() -> string
```

**Returns:** `string` - The normalized realm name, or an empty string when it is unavailable.

**Description:** Returns the realm name without spaces or punctuation. On clients that do not expose a normalized realm API, this falls back to the display name.

**Example Usage:**
```lua
local realm_key = core.character.get_normalized_realm_name()
core.log("Realm key: " .. realm_key)
```

---

## World Functions

### `core.world.is_flyable_area`

**Syntax:**
```lua
core.world.is_flyable_area() -> boolean
```

**Returns:** `boolean` - `true` if the current area allows regular flying, `false` otherwise.

**Description:** Returns whether the current area allows regular flying.

**Example Usage:**
```lua
if core.world.is_flyable_area() then
    core.log("You can fly here!")
end
```

---

### `core.world.is_advanced_flyable_area`

**Syntax:**
```lua
core.world.is_advanced_flyable_area() -> boolean
```

**Returns:** `boolean` - `true` if the current area allows dynamic/skyriding flying, `false` otherwise.

**Description:** Returns whether the current area allows dynamic/skyriding flying.

**Example Usage:**
```lua
if core.world.is_advanced_flyable_area() then
    core.log("Skyriding is available here!")
end
```

---

### `core.world.get_encounters_on_map`

**Syntax:**
```lua
core.world.get_encounters_on_map(ui_map_id: integer) -> encounter_info[]
```

**Parameters:**
- `ui_map_id`: `integer` - The UI map ID to query encounters for.

**Returns:** `encounter_info[]` - An array of encounter info tables. Each entry contains:

| Field | Type | Description |
|-------|------|-------------|
| `encounter_id` | `integer` | The encounter ID |
| `map_x` | `number` | The X position on the map |
| `map_y` | `number` | The Y position on the map |

**Description:** Returns a list of encounters on the specified map.

**Example Usage:**
```lua
local map_id = core.game_ui.get_current_map_id()
local encounters = core.world.get_encounters_on_map(map_id)
for _, enc in ipairs(encounters) do
    core.log(string.format("Encounter %d at (%.2f, %.2f)", enc.encounter_id, enc.map_x, enc.map_y))
end
```

---

## Additional Notes

-   **Performance Monitoring**: Utilize the time and CPU functions to monitor and optimize your script's performance.
-   **Event Handling**: Register appropriate callbacks to handle events effectively within your script.
-   **Logging Best Practices**: Consistently log important information for easier debugging and maintenance.
