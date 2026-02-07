
---@class core
_G.core = {}

---@alias game_objects_table game_object[]
---@alias item_slot_info_table item_slot_info[]
---@alias spell_costs_table spell_costs[]
---@alias buff_table buff[]
---@alias vec3_table vec3[]
---@alias vec2_table vec2[]
---@alias hit_data_table hit_data[]
---@alias consumable_data_table consumable_data[]

--- Log a message to the console.
---@param message string The message to log.
function core.log(message) end

--- Log a warning message to the console.
---@param message string The warning message to log.
function core.log_warning(message) end

--- Log an error message to the console.
---@param message string The error message to log.
function core.log_error(message) end

--- Register a function to be called before each tick.
---@param callback function The function to register as a pre-tick callback.
function core.register_on_pre_tick_callback(callback) end

--- Register a function to be called before each tick.
---@param callback function The function to register as a pre-tick callback.
function core.register_on_render_window_callback(callback) end

--- Register a function to be called during the update phase.
---@param callback function The function to register as an update callback.
function core.register_on_update_callback(callback) end

--- Register a function to be called during the rendering phase.
---@param callback function The function to register as a render callback.
function core.register_on_render_callback(callback) end

--- Register a function to be called during the rendering of menus.
---@param callback function The function to register as a render menu callback.
function core.register_on_render_menu_callback(callback) end

--- Register a function to be called to send control_panel data to core
---@param callback function The function to register as a control_panel callback
function core.register_on_render_control_panel_callback(callback) end

--- Register a function that triggers every time game registers a legit cast attempt
---@param callback function The function to register as a legit cast callback
function core.register_on_legit_spell_cast_callback(callback) end

---@class OnProcessSpellCastData
--- Defines the structure of the data table passed to the on_process_spell callback.
---@field spell_id number        -- Unique identifier for the spell.
---@field caster game_object|nil -- The game object that cast the spell (or nil).
---@field target game_object|nil -- The game object targeted by the spell (or nil).
---@field spell_cast_time number -- The time when the spell was cast.

--- Registers a callback to be triggered when a spell is cast.
--- The callback function receives a OnProcessSpellCastData table as a parameter.
---@param callback fun(data: OnProcessSpellCastData): nil
function core.register_on_spell_cast_callback(callback) end

--- Get the current ping.
---@return number The current ping.
function core.get_ping()
    return 0
end

--- Get the current time in seconds since the injection time.
---@return number The current time in seconds.
function core.time()
    return 0
end

--- Useful for profiling
---@return number
function core.cpu_ticks()
    return 0
end

--- Useful for profiling
---@return number
function core.cpu_ticks_per_second()
    return 0
end

--- Get the current game time in milliseconds since the start of the game.
---@return number The current game time in milliseconds.
function core.game_time()
    return 0
end

--- Get the time in seconds since the last frame.
---@return number The time in seconds since the last frame.
function core.delta_time()
    return 0
end

--- Get the screen position of cursor.
---@return vec2 The screen position of cursor.
function core.get_cursor_position()
    return {}
end

--- Get the id of the current localplayer map.
---@return number The id of the current localplayer map.
function core.get_map_id()
    return 0
end

---@return number
function core.get_instance_id()
    return 0
end

---@return number
function core.get_difficulty_id()
    return 0
end

---@return number
function core.get_keystone_level()
    return 0
end

---@return string
function core.get_instance_name()
    return ""
end

---@return string
function core.get_difficulty_name()
    return ""
end

---@return string
function core.get_instance_type()
    return ""
end

--- Get the name of the current localplayer map.
---@return string The name of the current localplayer map.
function core.get_map_name()
    return ""
end

---@return boolean
function core.is_debug()
    return false
end

---@return number
function core.get_user_role_flags()
    return 0
end

---@return number
function core.get_user_flags()
    return 0
end

---@return number
---@param pos vec3
function core.get_height_for_position(pos)
    return 0
end

---@return nil
function core.disable_drawings()
    return nil
end

---@return nil
function core.enable_drawings()
    return nil
end

--- Reload Game UI
---@return nil
function core.reload_game_ui()
    return nil
end

---@return boolean
function core.is_main_menu_open()
    return false
end

---@return string
---Returns "Retail", "Classic", "Classic Era", "Classic Pandaria", "Classic Tbc", "Titan"
function core.get_game_version()
    return ""
end

---@return string
---Returns "West", "China"
function core.get_game_region()
    return ""
end

---@return nil
--- Set Game Window Foremost
function core.set_window_foremost()
    return nil
end

---@return boolean
function core.is_window_foremost()
    return false
end

---@return nil
function core.reload_plugins()
    return nil
end

---@return string
function core.get_account_name()
    return ""
end

--------------------------------------------------------------------------------
-- Sandbox file I O
--
-- This scripting environment is sandboxed on purpose to prevent malicious code.
-- You can only interact with files in two allowed locations:
--
-- 1) Game files, inside the World of Warcraft installation folder
--    Used by: core.read_file, core.read_file_partial, core.get_file_size
--
-- 2) Loader data files, inside the loader's scripts_data folder
--    Used by: core.create_data_file, core.create_data_folder, core.write_data_file
--             core.read_data_file, core.read_data_file_partial, core.get_data_file_size
--
-- Any attempt to access files outside these locations will fail.
--------------------------------------------------------------------------------

--- Reads the entire contents of a sandboxed game file.
---
--- Sandbox scope:
--- - Only files inside the World of Warcraft installation folder are accessible.
--- - Any path outside the WoW folder is blocked.
---
--- Path rules:
--- - `filename` is treated as a path inside the WoW folder.
--- - Use relative-style paths such as `Data/...` or `_retail_/...` depending on your client layout.
---
--- Returns:
--- - On success: the full file contents as a Lua string.
--- - On failure: typically an empty string or nil depending on native implementation.
---
--- Example:
--- ```lua
--- local text = core.read_file("_retail_/WTF/Config.wtf")
--- print("Config length:", #text)
--- ```
---
---@param filename string Path inside the World of Warcraft folder (UTF-8).
---@return string data The file contents as a Lua string.
function core.read_file(filename)
    return ""
end

--- Reads a portion of a sandboxed game file, starting at a byte offset.
---
--- Sandbox scope:
--- - Only files inside the World of Warcraft installation folder are accessible.
--- - Any path outside the WoW folder is blocked.
--- - Returns nil if the file cannot be read (missing, outside scope, access denied, etc).
---
--- Path rules:
--- - `filename` is treated as a path inside the WoW folder.
--- - Use relative-style paths such as `Data/...` or `_retail_/...` depending on your client layout.
---
--- Notes:
--- - `offset` and `size_to_read` are in bytes.
--- - The returned string can contain binary data and may include zero bytes.
---
--- Example:
--- ```lua
--- local p = "_retail_/WTF/Config.wtf"
--- local chunk = core.read_file_partial(p, 0, 64)
--- if chunk then
---   print("First 64 bytes:", chunk)
--- else
---   print("Read failed (outside sandbox, missing, or access denied).")
--- end
--- ```
---
---@param filename string Path inside the World of Warcraft folder (UTF-8).
---@param offset integer Byte offset to start reading from.
---@param size_to_read integer Number of bytes to read.
---@return string|nil data The read bytes as a Lua string, or nil on failure.
function core.read_file_partial(filename, offset, size_to_read)
    return ""
end

--- Gets the size of a sandboxed game file in bytes.
---
--- Sandbox scope:
--- - Only files inside the World of Warcraft installation folder are accessible.
--- - Any path outside the WoW folder is blocked.
---
--- Notes:
--- - If the file does not exist or is not accessible, the native side may return 0.
--- - If you need to distinguish "missing" vs "empty file", attempt a small read as well.
---
--- Example:
--- ```lua
--- local p = "_retail_/WTF/Config.wtf"
--- local size = core.get_file_size(p)
--- if size > 0 then
---   print("Config size:", size)
--- else
---   print("Missing, blocked, or empty file.")
--- end
--- ```
---
---@param filename string Path inside the World of Warcraft folder (UTF-8).
---@return integer size The file size in bytes.
function core.get_file_size(filename)
    return 0
end

--- Creates a new data file inside the loader's `scripts_data/` directory.
---
--- Sandbox scope:
--- - Data files are stored under: `<loader_path>/scripts_data/`
--- - Only this directory is writable by scripts (by design).
---
--- Path rules:
--- - `filename` is relative to `scripts_data/`.
--- - Do not prefix with `scripts_data/` yourself.
---
--- Notes:
--- - Parent folders should exist. Use core.create_data_folder for subfolders if needed.
---
--- Example:
--- ```lua
--- core.create_data_file("settings.json")
--- core.write_data_file("settings.json", "{}")
--- ```
---
---@param filename string Path inside `scripts_data/` (UTF-8), relative to the loader data directory.
---@return nil
function core.create_data_file(filename)
    return nil
end

--- Creates a folder inside the loader's `scripts_data/` directory.
---
--- Sandbox scope:
--- - Folders are created under: `<loader_path>/scripts_data/`
--- - Only this directory is writable by scripts (by design).
---
--- Path rules:
--- - `folder` is relative to `scripts_data/`.
--- - Do not prefix with `scripts_data/` yourself.
---
--- Example:
--- ```lua
--- core.create_data_folder("profiles")
--- core.create_data_file("profiles/user1.json")
--- ```
---
---@param folder string Folder path inside `scripts_data/` (UTF-8), relative to the loader data directory.
---@return nil
function core.create_data_folder(folder)
    return nil
end

--- Writes data to a loader data file inside `scripts_data/`.
---
--- Sandbox scope:
--- - Files are written under: `<loader_path>/scripts_data/`
--- - Only this directory is writable by scripts (by design).
---
--- Path rules:
--- - `filename` is relative to `scripts_data/`.
--- - Do not prefix with `scripts_data/` yourself.
---
--- Notes:
--- - The write behavior (overwrite vs append) depends on native implementation.
---   In most systems this overwrites the file.
---
--- Example:
--- ```lua
--- core.write_data_file("cache/state.txt", "last_login=123")
--- ```
---
---@param filename string Path inside `scripts_data/` (UTF-8), relative to the loader data directory.
---@param data string The data to write into the file.
---@return nil
function core.write_data_file(filename, data)
    return nil
end

--- Reads the entire contents of a loader data file from `scripts_data/`.
---
--- Sandbox scope:
--- - Files are read from: `<loader_path>/scripts_data/`
--- - You cannot access arbitrary PC files via this API.
---
--- Path rules:
--- - `filename` is relative to `scripts_data/`.
--- - Do not prefix with `scripts_data/` yourself.
---
--- Notes:
--- - Returned string can contain binary data.
--- - If the file cannot be read, the native side may return an empty string or nil depending on implementation.
---
--- Example:
--- ```lua
--- local json = core.read_data_file("settings.json")
--- if json and #json > 0 then
---   print("settings.json:", json)
--- end
--- ```
---
---@param filename string Path inside `scripts_data/` (UTF-8), relative to the loader data directory.
---@return string data The file contents as a Lua string.
function core.read_data_file(filename)
    return ""
end

--- Creates a new log file.
---
--- Purpose:
--- - Log files are intended for diagnostics and debugging output.
--- - The exact storage location is implementation-defined by the loader.
---
--- Notes:
--- - If the log file already exists, the native side may truncate it or keep it, depending on implementation.
---
--- Example:
--- ```lua
--- core.create_log_file("combat.log")
--- core.write_log_file("combat.log", "addon started")
--- ```
---
---@param filename string The name of the log file to create.
---@return nil
function core.create_log_file(filename)
    return nil
end

--- Writes a message to a log file.
---
--- Purpose:
--- - Use this for debug output that should persist outside the in-game console.
---
--- Notes:
--- - Whether a newline is automatically appended depends on native implementation.
---   If you want one, include "\n" yourself.
---
--- Example:
--- ```lua
--- core.write_log_file("combat.log", "Target acquired: " .. tostring(unit_name) .. "\n")
--- ```
---
---@param filename string The name of the log file to write to.
---@param message string The message to write into the log file.
---@return nil
function core.write_log_file(filename, message)
    return nil
end

--- Reads a portion of a loader data file from `scripts_data/`, starting at a byte offset.
---
--- Sandbox scope:
--- - Files are read from: `<loader_path>/scripts_data/`
--- - You cannot access arbitrary PC files via this API.
--- - Returns nil if the data file cannot be read (missing, not permitted, etc).
---
--- Path rules:
--- - `filename` is resolved relative to `scripts_data/`.
--- - Do not prefix with `scripts_data/` yourself.
---
--- Notes:
--- - `offset` and `size_to_read` are in bytes.
--- - The returned string can contain binary data and may include zero bytes.
---
--- Example:
--- ```lua
--- local name = "settings.json" -- resolved as: <loader_path>/scripts_data/settings.json
--- local chunk = core.read_data_file_partial(name, 0, 256)
--- if chunk then
---   print("JSON header:", chunk)
--- else
---   print("Read failed (missing or blocked).")
--- end
--- ```
---
---@param filename string Path inside `scripts_data/` (UTF-8), relative to the loader data directory.
---@param offset integer Byte offset to start reading from.
---@param size_to_read integer Number of bytes to read.
---@return string|nil data The read bytes as a Lua string, or nil on failure.
function core.read_data_file_partial(filename, offset, size_to_read)
    return ""
end

--- Gets the size of a loader data file in bytes, from `scripts_data/`.
---
--- Sandbox scope:
--- - Only files inside the loader's `scripts_data/` directory are accessible.
---
--- Notes:
--- - If the file does not exist or is not accessible, the native side may return 0.
--- - If you need to distinguish "missing" vs "empty file", attempt a small partial read as well.
---
--- Example:
--- ```lua
--- local name = "settings.json"
--- local size = core.get_data_file_size(name)
--- if size > 0 then
---   print("settings.json size:", size)
--- else
---   print("Missing, blocked, or empty file.")
--- end
--- ```
---
---@param filename string Path inside `scripts_data/` (UTF-8), relative to the loader data directory.
---@return integer size The file size in bytes.
function core.get_data_file_size(filename)
    return 0
end

--- Lists all files and folders in a directory inside `scripts_data/`.
---
--- Sandbox scope:
--- - Only directories inside the loader's `scripts_data/` directory are accessible.
--- - Any path outside `scripts_data/` will return nil.
---
--- Path rules:
--- - `directory` is relative to `scripts_data/`.
--- - Do not prefix with `scripts_data/` yourself.
--- - Use forward slashes or backslashes as path separators.
---
--- Returns:
--- - On success: a table (array) of file names in the directory.
--- - On failure: nil (path outside sandbox, doesn't exist, or not a directory).
---
--- Notes:
--- - Only returns file/folder names, not full paths.
--- - Includes both files and subdirectories.
--- - Does not include "." or ".." entries.
---
--- Example:
--- ```lua
--- local files = core.read_dir("profiles")
--- if files then
---   for i, name in ipairs(files) do
---     print("Found: " .. name)
---   end
--- else
---   print("Directory not found or outside sandbox")
--- end
--- ```
---
---@param directory string Directory path inside `scripts_data/` (UTF-8), relative to the loader data directory.
---@return string[]|nil files Array of file/folder names, or nil on failure.
function core.read_dir(directory)
    return nil
end

---@class inventory
core.inventory = {}

--- -2 for the keyring
--- -4 for the tokens bag
--- 0 = backpack, 1 to 4 for the bags on the character
--- While bank is opened -1 for the bank content, 5 to 11 for bank bags (numbered left to right, was 5-10 prior to tbc expansion, 2.0 game version)
---@param bag_id integer BagId https://wowwiki-archive.fandom.com/wiki/BagId
---@return item_slot_info_table
function core.inventory.get_items_in_bag(bag_id)
    return {}
end

---@class game_ui
core.game_ui = {}

--- Get the count of lootable items.
---@return number The number of lootable items.
function core.game_ui.get_loot_item_count()
    return 0
end

--- Check if a loot item is gold.
---@param index integer The index of the loot item.
---@return boolean True if the loot item is gold, false otherwise.
function core.game_ui.get_loot_is_gold(index)
    return false
end

--- Get the item ID of a lootable item.
---@param index integer The index of the loot item.
---@return number The item ID of the lootable item.
function core.game_ui.get_loot_item_id(index)
    return 0
end

--- Get the name of a lootable item.
---@param index integer The index of the loot item.
---@return string The name of the lootable item.
function core.game_ui.get_loot_item_name(index)
    return ""
end

--- @return string
--- @param index number
--- confirm, queued, none, error, active
function core.game_ui.get_battlefield_status(index)
    return ""
end

--- @return number
--- 2 Prep | 3 Action | 5 Finished
function core.game_ui.get_battlefield_state()
    return 0
end

--- @return vec2
--- @param map_id number
--- @param map_pos vec2
--- Returns vec2 x / y in 3dworld format, just missing z height
function core.game_ui.get_world_pos_from_map_pos(map_id, map_pos)
    return {}
end

--- Get the current WoW cursor position.
---@return vec2 The cursor position in UI coordinates.
function core.game_ui.get_wow_cursor_position()
    return {}
end

--- Get the current cursor position in normalized coordinates.
---@return vec2 The cursor position normalized (0-1 range).
function core.game_ui.get_normalized_cursor_position()
    return {}
end

--- Normalize a UI position.
---@param pos vec2 The UI position to normalize.
---@return vec2 The normalized position (0-1 range).
function core.game_ui.normalize_ui_position(pos)
    return {}
end

--- @return number
--- Timer in MS Since the battlefield started
function core.game_ui.get_battlefield_run_time()
    return 0
end

--- @return number|nil
--- NIL NONE | 0 Horde | 1 Ally | 2 Tie
function core.game_ui.get_battlefield_winner()
    return nil
end

--- @return number
function core.game_ui.get_current_map_id()
    return 0
end

--- @return boolean
--- Returns true if the world map is currently open.
function core.game_ui.is_map_open()
    return false
end

---@class input
core.input = {}

--- Casts a spell on a specific target game object.
---@param spell_id integer The ID of the spell to cast.
---@param target game_object The target game object on which the spell will be cast.
---@return boolean Indicates whether the spell was successfully cast on the target.
function core.input.cast_target_spell(spell_id, target)
    return false
end

--- Casts a spell on a vec3 position
---@param spell_id integer The ID of the spell to cast.
---@param position vec3 the position where you want to cast the spell.
---@return boolean Indicates whether the spell was successfully cast on the position.
function core.input.cast_position_spell(spell_id, position)
    return false
end

--- Use a self cast item
---@param item_id integer The ID of the item to use.
---@return boolean Indicates whether the spell was successfully usage of the item
function core.input.use_item(item_id)
    return false
end

---@param target game_object
---@param item_id integer The ID of the item to use.
---@return boolean Indicates whether the spell was successfully usage of the item
function core.input.use_item_target(item_id, target)
    return false
end

---@param position vec3
---@param item_id integer The ID of the item to use.
---@return boolean Indicates whether the spell was successfully usage of the item
function core.input.use_item_position(item_id, position)
    return false
end

--- Set the local player target
---@param unit game_object The game_object to set as target
---@return boolean Return true on successfully targetting the desired unit
function core.input.set_target(unit)
    return false
end

--- Set the local player focus
---@param unit game_object The game_object to set as focus
---@return boolean Return true on successfully focusing the desired unit
function core.input.set_focus(unit)
    return false
end

--- Get the local player focus
---@return table Return the game_object focus, can be nil
function core.input.get_focus()
    return {};
end

--- Checks if the key is pressed
--- @param key integer The key to check if is pressed or not
--- @return boolean Returns true if the passed key is being currently pressed. Check https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
function core.input.is_key_pressed(key)
    return false;
end

--- @return boolean
--- @param bit_flag number
function core.input.is_input_bit_active(bit_flag)
    return false
end

--- @return nil
--- Starts local rotation to right side
function core.input.turn_right_start()
    return nil
end

--- @return nil
--- Stops local rotation to right side
function core.input.turn_right_stop()
    return nil
end

--- @return nil
--- Starts local rotation to left side
function core.input.turn_left_start()
    return nil
end

--- @return nil
--- Stops local rotation to left side
function core.input.turn_left_stop()
    return nil
end

--- @return nil
--- Starts local strafe to right
function core.input.strafe_right_start()
    return nil
end

--- @return nil
--- Stops local strafe to right
function core.input.strafe_right_stop()
    return nil
end

--- @return nil
--- Starts local strafe to left
function core.input.strafe_left_start()
    return nil
end

--- @return nil
--- Stops local strafe to left
function core.input.strafe_left_stop()
    return nil
end

--- @return nil
--- Starts local forward
function core.input.move_forward_start()
    return nil
end

--- @return nil
--- Stops local forward
function core.input.move_forward_stop()
    return nil
end

--- @return nil
--- Starts local backward
function core.input.move_backward_start()
    return nil
end

--- @return nil
--- Stops local backward
function core.input.move_backward_stop()
    return nil
end

--- @return nil
function core.input.cancel_spells()
    return nil
end

--- @return nil
function core.input.enable_movement()
    return nil
end

--- @return nil
--- @param is_lock boolean
function core.input.disable_movement(is_lock)
    return nil
end

--- @return nil
--- Faces to vec3
--- @param point vec3
function core.input.look_at(point)
    return nil
end

--- Stops the local player’s current attack.
---@return nil
function core.input.stop_attack()
    return nil
end

---@return nil
function core.input.stop_spell_target()
    return nil
end

--- Sets the pet to passive mode.
---@return nil
function core.input.set_pet_passive()
    return nil
end

--- Sets the pet to defensive mode.
---@return nil
function core.input.set_pet_defensive()
    return nil
end

--- Sets the pet to aggressive mode.
---@return nil
function core.input.set_pet_aggressive()
    return nil
end

--- Sets the pet to assist mode.
---@return nil
function core.input.set_pet_assist()
    return nil
end

--- Commands the pet to wait at its current position.
---@return nil
function core.input.set_pet_wait()
    return nil
end

--- Commands the pet to follow the player.
---@return nil
function core.input.set_pet_follow()
    return nil
end

--- Commands the pet to attack a target.
---@param target game_object The target to attack.
---@return nil
function core.input.pet_attack(target)
    return nil
end

--- Commands the pet to cast a spell on a target.
---@param spell_id integer The ID of the spell to cast.
---@param target game_object The target to cast the spell on.
---@return nil
function core.input.pet_cast_target_spell(spell_id, target)
    return nil
end

--- Commands the pet to cast a spell at a position.
---@param spell_id integer The ID of the spell to cast.
---@param position vec3 The position to cast the spell at.
---@return nil
function core.input.pet_cast_position_spell(spell_id, position)
    return nil
end

--- Commands the pet to move to a specified game object.
---@param target game_object The game object to move to.
---@return nil
function core.input.pet_move(target)
    return nil
end

--- Commands the pet to move to a specified position.
---@param position vec3 The position to move to.
---@return nil
function core.input.pet_move_position(position)
    return nil
end

--- Loots a specified game object.
---@param target game_object The game object to loot.
---@return nil
function core.input.loot_object(target)
    return nil
end

--- Skins a specified game object.
---@param target game_object The game object to skin.
---@return nil
function core.input.skin_object(target)
    return nil
end

--- Uses a specified game object.
---@param target game_object The game object to use.
---@return nil
function core.input.use_object(target)
    return nil
end

--- Interacts with a specified game object.
---@param target game_object The game object to interact with.
---@return nil
function core.input.interact_with_object(target)
    return nil
end

--- Releases the player's spirit after death.
---@return nil
function core.input.release_spirit()
    return nil
end

--- Sends player back to its corpse.
---@return nil
function core.input.resurrect_corpse()
    return nil
end

--- Starts moving the player character upwards (e.g., for flying or swimming).
--- @return nil
function core.input.move_up_start()
    return nil
end

--- Stops the upward movement of the player character.
--- @return nil
function core.input.move_up_stop()
    return nil
end

--- Starts moving the player character downward (e.g., for flying or swimming).
--- @return nil
function core.input.move_down_start()
    return nil
end

--- Stops the downward movement of the player character.
--- @return nil
function core.input.move_down_stop()
    return nil
end

--- Makes the player character jump.
--- @return nil
function core.input.jump()
    return nil
end

--- Mounts a specific mount by its index.
---@param mount_index integer The index of the mount to use.
---@return nil
function core.input.mount(mount_index)
    return nil
end

--- Dismounts the player from their current mount.
--- @return nil
function core.input.dismount()
    return nil
end

--- Loot a specific item from the loot window.
---@param index integer The index of the loot item to loot.
---@return nil
function core.input.loot_item(index)
    return nil
end

--- Close the loot window.
---@return nil
function core.input.close_loot()
    return nil
end

---@return nil
---@param buff_otr buff
function core.input.cancel_buff(buff_otr)
    return nil
end

---@return nil
---@param index number
---@param is_accept boolean
function core.input.accept_battlefield_port(index, is_accept)
    return nil
end

---@return nil
---@param role_flags number
---@param battlefield_id number
function core.input.join_battlefield(battlefield_id, role_flags)
    return nil
end

---@return nil
function core.input.leave_party()
    return nil
end

---@return nil
function core.input.leave_battlefield()
    return nil
end

---@return nil
---@param dungeon_id number
---@param category_id number
function core.input.select_dungeon(category_id, dungeon_id)
    return nil
end

---@return nil
---@param role_flags number
---@param category_id number
function core.input.join_dungeon(category_id, role_flags)
    return nil
end

---@return nil
function core.input.has_dungeon_proposal()
    return nil
end

---@return nil
---@param is_accept boolean
function core.input.accept_dungeon_proposal(is_accept)
    return nil
end

---@return nil
---@param index integer
function core.input.clear_dungeon_selections(index)
    return nil
end

---@class object_manager
core.object_manager = {}

--- Retrieves the local player game object.
---@return game_object
function core.object_manager.get_local_player()
    return {}
end

--- Retrieves all game objects.
---@return game_objects_table
function core.object_manager.get_all_objects()
    return {}
end

-- Retrieves the player for the given arena frame index, nil means we are not in arena
--- @param index integer
--- @return game_object | nil
function core.object_manager.get_arena_target(index)
    return {}
end

--- Retrieves all visible game objects.
---@return game_objects_table
function core.object_manager.get_visible_objects()
    return {}
end

--- Retrieves a list of game objects with all the arena frames.
---@return game_objects_table
function core.object_manager.get_arena_frames()
    return {}
end

--- Retrieves mouse_over object
---@return game_object
function core.object_manager.get_mouse_over_object()
    return {}
end

---@class spell_book
core.spell_book = {}

--- Retrieves the local_player specialization_id
---@return number The local_player specialization_id
function core.spell_book.get_specialization_id()
    return 0
end

--- Retrieves the global cooldown duration in seconds.
---@return number The global cooldown duration in seconds.
function core.spell_book.get_global_cooldown()
    return 0
end

--- Retrieves the cooldown duration of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return number The cooldown duration of the specified spell in seconds.
function core.spell_book.get_spell_cooldown(spell_id)
    return 0
end


--- Indicates if the spell can be usable based on many requirements.
---@param spell_id integer The ID of the spell.
---@return boolean to indicate if the spell is usable.
function core.spell_book.is_usable_spell(spell_id)
    return false
end

--- Retrieves the amount of current charges of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return integer The amount of current stacks of the specified spell.
function core.spell_book.get_spell_charge(spell_id)
    return 0
end

--- Retrieves the amount of max charges of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return integer The amount of max stacks of the specified spell.
function core.spell_book.get_spell_charge_max(spell_id)
    return 0
end

--- Retrieves the total cooldown of the specified spell charge identified by its ID.
---@param spell_id integer The ID of the spell.
---@return integer The amount of max stacks of the specified spell.
function core.spell_book.get_spell_charge_cooldown_duration(spell_id)
    return 0
end

--- Retrieves the last time a charge was triggered of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return integer The amount of max stacks of the specified spell.
function core.spell_book.get_spell_charge_cooldown_start_time(spell_id)
    return 0
end

--- Retrieves the name of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return string The name of the specified spell.
function core.spell_book.get_spell_name(spell_id)
    return ""
end

--- Retrieves the whole tooltip text of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return string The tooltip text of the specified spell.
function core.spell_book.get_spell_description(spell_id)
    return ""
end

--- Retrieves the whole tooltip text of the specified buff.
---@param buff_ptr buff
---@return string The tooltip text of the specified buff.
function core.spell_book.get_buff_description(buff_ptr)
    return ""
end

--- Retrieves a table containing all spells and their corresponding IDs.
---@return table<number, number>
function core.spell_book.get_spells()
    return {}
end

--- Checks if the specified spell identified by its ID is owned by the localplayer.
---@param spell_id integer The ID of the spell.
---@return boolean Returns true if the specified spell is equipped, otherwise returns false.
function core.spell_book.has_spell(spell_id)
    return false
end

--- Checks if the specified spell identified by its ID is learned by the localplayer.
---@param spell_id integer The ID of the spell.
---@return boolean Returns true if the specified spell is learned, otherwise returns false.
function core.spell_book.is_spell_learned(spell_id)
    return false
end

---@param n integer
---@param flag integer
---@param spell_id integer The ID of the spell.
---@return boolean Returns true if the specified spell has certain attribute.
function core.spell_book.spell_has_attribute(spell_id, n, flag)
    return false
end

--- Returns the spell_id from the talent_id.
---@param talent_id integer The ID of the talent.
---@return number Returns the spell_id from the talent_id.
function core.spell_book.get_talent_spell_id(talent_id)
    return 0
end

--- Returns the name from the talent_id.
---@param talent_id integer The ID of the talent.
---@return string Returns the name from the talent_id.
function core.spell_book.get_talent_name(talent_id)
    return ""
end

--- Checks if the specified spell is melee type.
---@param spell_id integer The ID of the spell.
---@return boolean Returns true if the specified spell is melee type.
function core.spell_book.is_melee_spell(spell_id)
    return false
end

--- Checks if the specified spell is an skillshot.
---@param spell_id integer The ID of the spell.
---@return boolean Returns true if the specified spell is skillshot.
function core.spell_book.is_spell_position_cast(spell_id)
    return false
end

--- Checks if the cursor is currently busy with an skillshot.
---@return boolean Returns true if the cursor is currently busy with an skillshot.
function core.spell_book.cursor_has_spell()
    return false
end

---@class spell_costs
---@field public min_cost number
---@field public cost number
---@field public cost_per_sec number
---@field public cost_type number
---@field public required_buff_id number

--- Returns spell_costs structure
---@param spell_id integer The ID of the spell.
---@return spell_costs
function core.spell_book.get_spell_costs(spell_id)
    return {}
end

---@class range_data
---@field public min number
---@field public max number

--- Retrieves the range data of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return range_data A table containing the minimum and maximum range of the specified spell.
function core.spell_book.get_spell_range_data(spell_id)
    return {}
end

--- Retrieves the minimum range of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return number The minimum range of the specified spell.
function core.spell_book.get_spell_min_range(spell_id)
    return 0
end

--- Retrieves the maximum range of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return number The maximum range of the specified spell.
function core.spell_book.get_spell_max_range(spell_id)
    return 0
end

--- Retrieves the school flag of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return schools_flag The spell school flag.
function core.spell_book.get_spell_school(spell_id)

    ---@type schools_flag
    return nil
end

--- Retrieves the cast time of the specified spell identified by its ID.
---@param spell_id integer The ID of the spell.
---@return number The cast time in seconds.
function core.spell_book.get_spell_cast_time(spell_id)
    return 0
end

--- Note: This Function is deprecated
--- Alternative: Common Utility Spell Helper
--- Retrieves the damage value of the spell_id.
-- -@param spell_id integer The ID of the spell.
-- -@return number The damage value of the spell.
-- function core.spell_book.get_spell_damage(spell_id)
    -- return 0
-- end

--- Retrieves the mode flag of our pet
---@return number
function core.spell_book.get_pet_mode()
    return 0
end

--- Retrieves a table with all the pet spells
---@return table
function core.spell_book.get_pet_spells()
    return {}
end

---@class mount_info
---@field public mount_name string The name of the mount.
---@field public spell_id integer The spell ID associated with the mount.
---@field public mount_id integer The unique ID of the mount.
---@field public is_active boolean Whether the mount is currently active.
---@field public is_usable boolean Whether the mount is usable.
---@field public mount_type integer The type/category of the mount.

--- Retrieves the number of mounts available to the player.
---@return integer The total number of mounts.
function core.spell_book.get_mount_count()
    return 0
end

--- Retrieves information about a specific mount by its index.
---@param mount_index integer The index of the mount.
---@return mount_info|nil A table containing the mount information, or nil if the index is invalid.
function core.spell_book.get_mount_info(mount_index)
    return {}
end

---@return integer
---@param spell_id integer
function core.spell_book.get_base_spell_id(spell_id)
    return 0
end

---@class totem_info
---@field public have_totem boolean         -- Whether the totem exists
---@field public totem_name string          -- Name of the totem
---@field public start_time number          -- Start time of the totem
---@field public duration number            -- Duration of the totem

---@return totem_info
---@param index integer
---Returns a table with totem info for the given index (1–4).  
---Index corresponds to the totem slot (e.g., Fire, Earth, Water, Air).
function core.spell_book.get_totem_info(index)
    return {}
end

---@return boolean
---@param item_id integer
function core.spell_book.is_item_usable(item_id)
    return false
end

---@return integer
---@param index integer
--- 1 Blood | 2 Unholy | 3 Frost | 4 Death
function core.spell_book.get_rune_type(index)
    return 0
end

---@return boolean
---@param index integer
function core.spell_book.is_rune_slot_active(index)
    return false
end

--- Retrieves the base (out-of-combat) power regeneration rate of the local player.
--- This represents the passive regeneration rate when not casting or using abilities.
---@return number The base power regeneration per second.
function core.spell_book.get_base_power_regen()
    return 0
end

--- Retrieves the power regeneration rate of the local player while casting.
--- This may differ from the base regen due to talents, buffs, or class mechanics.
---@return number The casting power regeneration per second.
function core.spell_book.get_casting_power_regen()
    return 0
end

---@class rune_info
---@field public start number     -- cooldown start time (seconds)
---@field public duration number  -- cooldown duration (seconds)
---@field public ready boolean    -- true if the rune is ready now

--- Retrieves cooldown info for the rune in the given slot (1..6).
---@param slot integer  -- 1..6
---@return rune_info
function core.spell_book.get_rune_info(slot)
    -- Example stub values; engine should return real timings:
    return { start = 0, duration = 0, ready = true }
end

--- Checks whether a spell is in range from a specified caster to a target.
--- If `caster` is not provided, it defaults to the local player.
--- If `target` is not provided, it defaults to the current target of the local player.
--- This function internally evaluates the spell’s range data and both game object positions.
---@param spell_id integer The ID of the spell to check.
---@param target? game_object (optional) The target game object to check range against. Defaults to current target if omitted.
---@param caster? game_object (optional) The caster game object. Defaults to the local player if omitted.
---@return boolean Returns true if the target is within range for the specified spell, otherwise false.
function core.spell_book.is_spell_in_range(spell_id, target, caster)
    return false
end

--- Checks whether an item has a built-in range definition (e.g., targetable items).
--- Engine should resolve the item’s underlying “use spell” and report if range data exists.
---@param item_id integer
---@return boolean  -- true if the item supports range checking
function core.spell_book.has_item_range(item_id)
    -- Engine-backed; stubbed here for syntax.
    return false
end

--- Checks whether an item can be used on `target` with respect to range.
--- Internally maps the item to its “use spell” and performs a spell range check.
--- If `target` is nil, the engine may default to the current target.
---@param item_id integer
---@param target? game_object
---@return boolean  -- true if `target` is in range for this item
function core.spell_book.is_item_in_range(item_id, target)
    -- Engine-backed; stubbed here for syntax.
    return false
end

---@return number
---@param spell_id number
function core.spell_book.get_spell_cast_count(spell_id)
    return 0
end

---@return number
---@param target game_object
function core.spell_book.get_assisted_spell_id(target)
    return 0
end

---@class graphics
core.graphics = {}

--- Adds a notification to the display.
--- @param unique_id string UNIQUE identifier for the notification.
--- @param label string The title or heading for the notification.
--- @param message string The main content of the notification.
--- @param duration_ms integer The duration in seconds that the notification should be displayed.
--- @param color color The color of the notification text.
--- @param x_pos_offset number Optional horizontal position offset, defaults to 0.0.
--- @param y_pos_offset number Optional vertical position offset, defaults to 0.0.
--- @param max_background_alpha number Optional maximum background alpha (opacity), defaults to 0.95.
--- @param length number Optional length of the notification box, defaults to 0.0.
--- @param height number Optional height of the notification box, defaults to 0.0.
--- @overload fun(unique_id:string, label: string, message: string, duration_s: number, color: color):boolean
--- @overload fun(unique_id:string, label: string, message: string, duration_s: number, color: color, x_pos_offset: number):boolean
--- @overload fun(unique_id:string, label: string, message: string, duration_s: number, color: color, x_pos_offset: number, y_pos_offset: number):boolean
--- @overload fun(unique_id:string, label: string, message: string, duration_s: number, color: color, x_pos_offset: number, y_pos_offset: number, max_background_alpha: number):boolean
--- @overload fun(unique_id:string, label: string, message: string, duration_s: number, color: color, x_pos_offset: number, y_pos_offset: number, max_background_alpha: number, length: number):boolean
function core.graphics.add_notification(unique_id, label, message, duration_ms, color, x_pos_offset, y_pos_offset, max_background_alpha, length, height)
    return false
end

---@return vec2 main_menu_screen_position
function core.graphics.get_main_menu_screen_pos()
    return {}
end

---@return string key_name
---@param key integer
function core.graphics.translate_vkey_to_string(key)
    return ""
end

---@return vec2 main_menu_screen_size
function core.graphics.get_main_menu_screen_size()
    return {}
end

--- @param unique_id string UNIQUE identifier of the notification.
--- @param delay number|nil Optional delay to trigger (eg. delay = 5.0, this function will return true if the notification was clicked 5 seconds ago), defaults to 0.0
function core.graphics.is_notification_clicked(unique_id, delay)
    return false
end

-- Returns true if the notification is being shown on screen
--- @param unique_id string UNIQUE identifier of the notification.
function core.graphics.is_notification_active(unique_id)
    return false
end

--- Retrieves the current screen position of notifications.
---@return vec2 notifications_position The screen coordinates (x, y) where notifications are displayed.
function core.graphics.get_notifications_menu_position()
    return {}
end

--- Retrieves the default size of notifications.
---@return vec2 notifications_default_size The default width and height of notifications.
function core.graphics.get_notifications_default_size()
    return {}
end

---@return string current_dragged_menu_element_pending_to_be_added_to_control_panel_label The current dragged menu element that is pending to be added to control panel
function core.graphics.get_current_control_panel_element_label()
    return ""
end

---@param label string
function core.graphics.set_current_control_panel_element_label(label) end

--- Retrieves the scaled width - Main resolution is your current resolution X, must be hardcoded. (Eg. 1920)
---@return number scaled_width
---@param value_to_scale number
---@param main_resolution number
function core.graphics.scale_width_to_screen_size(value_to_scale, main_resolution)
    return 0.0
end

--- Retrieves the scaled height - Main resolution is your current resolution Y, must be hardcoded. (Eg. 1080)
---@return number scaled_width
---@param value_to_scale number
---@param main_resolution number
function core.graphics.scale_height_to_screen_size(value_to_scale, main_resolution)
    return 0.0
end

--- Retrieves the scaled size - Main resolution is your current resolution. Must be hardcoded. (Eg. 1920*1080)
---@return vec2 scaled_size
---@param value_to_scale vec2
---@param main_resolution vec2
function core.graphics.scale_size_to_screen_size(value_to_scale, main_resolution)
    return {}
end

--- Line Of Sight
---@return boolean
---@param caster game_object
---@param target game_object
function core.graphics.is_line_of_sight(caster, target)
    return false
end

--- Trace Line
---@return boolean
---@param pos1 vec3
---@param pos2 vec3
---@param flags number
function core.graphics.trace_line(pos1, pos2, flags)
    return false
end

--- World to Screen
---@param position vec3 The 3D world position to convert.
---@return vec2 | nil
function core.graphics.w2s(position)
    return {}
end

--- World to Screen
---@return vec2 --| nil
function core.graphics.get_screen_size()
    return {}
end

--- Cursor World Position (Vec3)
---@return vec3
function core.graphics.get_cursor_world_position()
    return {}
end

--- Returns true when the main menu is open
---@return boolean
function core.graphics.is_menu_open()
    return false
end

--- Render 2D text.
---@param text string The text to render.
---@param position vec2 The position where the text will be rendered.
---@param font_size number The font size of the text.
---@param color color The color of the text.
---@param centered? boolean Indicates whether the text should be centered at the specified position. Default is false.
---@param font_id? integer The font ID. Default is 0.
function core.graphics.text_2d(text, position, font_size, color, centered, font_id) end

--- Render 3D text.
---@param text string The text to render.
---@param position vec3 The position in 3D space where the text will be rendered.
---@param font_size number The font size of the text.
---@param color color The color of the text.
---@param centered? boolean Indicates whether the text should be centered at the specified position. Default is false.
---@param font_id? integer The font ID. Default is 0.
function core.graphics.text_3d(text, position, font_size, color, centered, font_id) end

--- Get Text Width
---@return number
---@param text string The text to render.
---@param font_size number The font size of the text.
---@param font_id? integer The font ID. Default is 0.
function core.graphics.get_text_width(text, font_size, font_id)
    return 0
end

--- Draw 2D Line
---@param start_point vec2 The start point of the line.
---@param end_point vec2 The end point of the line.
---@param color color The color of the line.
---@param thickness? number The thickness of the line. Default is 1.
function core.graphics.line_2d(start_point, end_point, color, thickness) end

--- Draw 2D Rectangle Outline
---@param top_left_point vec2 The top-left corner point of the rectangle.
---@param width number The width of the rectangle.
---@param height number The height of the rectangle.
---@param color color The color of the rectangle outline.
---@param thickness? number The thickness of the outline. Default is 1.
---@param rounding? number The rounding of corners. Default is 0.
function core.graphics.rect_2d(top_left_point, width, height, color, thickness, rounding) end

--- Draw 2D Filled Rectangle
---@param top_left_point vec2 The top-left corner point of the rectangle.
---@param width number The width of the rectangle.
---@param height number The height of the rectangle.
---@param color color The color of the rectangle outline.
---@param rounding? number The rounding of corners. Default is 0.
function core.graphics.rect_2d_filled(top_left_point, width, height, color, rounding) end

--- Draw 3D Line
---@param start_point vec3 The start point of the line in 3D space.
---@param end_point vec3 The end point of the line in 3D space.
---@param color color The color of the line.
---@param thickness? number The thickness of the line. Default is 1.
---@param fade_factor? number The thickness of the outline. Default is 2.5.
---@param has_volume? boolean Add volume. Default true.
function core.graphics.line_3d(start_point, end_point, color, thickness, fade_factor, has_volume) end

--- Draw 3D Rectangle Outline
-- ---@param p1 vec3 The first corner point of the rectangle in 3D space.
-- ---@param p2 vec3 The second corner point of the rectangle in 3D space.
-- ---@param p3 vec3 The third corner point of the rectangle in 3D space.
-- ---@param p4 vec3 The fourth corner point of the rectangle in 3D space.
-- ---@param color color The color of the rectangle outline.
-- ---@param thickness? number The thickness of the outline. Default is 1.
-- function core.graphics.rect_3d(p1, p2, p3, p4, color, thickness) end

--- Draw 3D Rectangle Outline New
---@param origin vec3
---@param destination vec3
---@param color color The color of the rectangle outline.
---@param thickness? number The thickness of the line. Default is 1.
---@param fade_factor? number The thickness of the outline. Default is 2.5.
function core.graphics.rect_3d(origin, destination, width, color, thickness, fade_factor) end

--- Draw 3D Filled Rectangle
---@param p1 vec3 The first corner point of the rectangle in 3D space.
---@param p2 vec3 The second corner point of the rectangle in 3D space.
---@param p3 vec3 The third corner point of the rectangle in 3D space.
---@param p4 vec3 The fourth corner point of the rectangle in 3D space.
---@param color color The fill color of the rectangle.
function core.graphics.rect_3d_filled(p1, p2, p3, p4, color) end

--- Draw 2D Circle Outline
---@param center vec2 The center point of the circle.
---@param radius number The radius of the circle.
---@param color color The color of the circle outline.
---@param thickness? number The thickness of the outline. Default is 1.
function core.graphics.circle_2d(center, radius, color, thickness) end

--- Draw 2D Circle Outline Gradient
---@param center vec2 The center point of the circle.
---@param radius number The radius of the circle.
---@param color_1 color
---@param color_2 color
---@param color_3 color
---@param thickness? number The thickness of the outline. Default is 1.
function core.graphics.circle_2d_gradient(center, radius, color_1, color_2, color_3, thickness) end

--- Draw 2D Filled Circle
---@param center vec2 The center point of the circle.
---@param radius number The radius of the circle.
---@param color color The fill color of the circle.
function core.graphics.circle_2d_filled(center, radius, color) end

--- Draw 3D Circle Outline
---@param center vec3 The center point of the circle in 3D space.
---@param radius number The radius of the circle.
---@param color color The color of the circle outline.
---@param thickness? number The thickness of the outline. Default is 1.
---@param fade_factor? number The factor / strenght it fades out, bigger value, faster fade. Default is 2.5.
function core.graphics.circle_3d(center, radius, color, thickness, fade_factor) end

--- Draw 3D Circle Outline Percentage
---@param center vec3 The center point of the circle in 3D space.
---@param radius number The radius of the circle.
---@param color color The color of the circle outline.
---@param percentage number The percentage of the circle to render.
---@param thickness? number The thickness of the outline. Default is 1.
function core.graphics.circle_3d_percentage(center, radius, color, percentage, thickness) end

--- Draw 3D Circle Outline Gradient
---@param center vec3 The center point of the circle in 3D space.
---@param radius number The radius of the circle.
---@param color_1 color
---@param color_2 color
---@param color_3 color
---@param thickness? number The thickness of the outline. Default is 1.
function core.graphics.circle_3d_gradient(center, radius, color_1, color_2, color_3, thickness) end

--- Draw 3D Cone
---@param center vec3 The center point of the circle in 3D space.
---@param target_pos vec3 The target position of the cone
---@param radius number The radius of the cone
---@param angle_degrees number
---@param color color
---@param fade_power number | nil
function core.graphics.cone_3d(center, target_pos, radius, angle_degrees, color, fade_power) end

--- Draw 3D Circle Outline Gradient Percentage
---@param center vec3 The center point of the circle in 3D space.
---@param radius number The radius of the circle.
---@param color_1 color
---@param color_2 color
---@param color_3 color
---@param percentage number The percentage of the circle to render.
---@param thickness? number The thickness of the outline. Default is 1.
function core.graphics.circle_3d_gradient_percentage(center, radius, color_1, color_2, color_3, percentage, thickness) end

--- Draw 3D Filled Circle
---@param center vec3 The center point of the circle in 3D space.
---@param radius number The radius of the circle.
---@param color color The fill color of the circle.
function core.graphics.circle_3d_filled(center, radius, color) end

--- Draw 2D Filled Triangle
---@param p1 vec2 The first corner point of the triangle in 2D space.
---@param p2 vec2 The second corner point of the triangle in 2D space.
---@param p3 vec2 The third corner point of the triangle in 2D space.
---@param color color The fill color of the triangle.
function core.graphics.triangle_2d_filled(p1, p2, p3, color) end

--- Draw 3D Filled Triangle
---@param p1 vec3 The first corner point of the triangle in 3D space.
---@param p2 vec3 The second corner point of the triangle in 3D space.
---@param p3 vec3 The third corner point of the triangle in 3D space.
---@param color color The fill color of the triangle.
function core.graphics.triangle_3d_filled(p1, p2, p3, color) end

--- Load Image
---@param path_to_asset string The path to the image file.
function core.graphics.load_image(path_to_asset) end

--- Draw Image
---@param image any Loaded image object.
---@param position vec2 The position to place the image.
function core.graphics.draw_image(image, position) end

--- Renders System Menu from C++
function core.graphics.render_system_menu() end

---@class menu
core.menu = {}

--- Registers the menu for interaction.
function core.menu.register_menu() end

--- Creates a new tree node instance
---@return tree_node
function core.menu.tree_node()
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new checkbox instance.
---@param default_state boolean The default state of the checkbox.
---@param id string The unique identifier for the checkbox.
---@return checkbox
function core.menu.checkbox(default_state, id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new checkbox instance.
---@param default_key integer The default state of the checkbox.
---@param initial_toggle_state boolean The initial toggle state of the keybind
---@param default_state boolean The default state of the checkbox
---@param show_in_binds boolean The default show in binds state of the checkbox
---@param default_mode_state integer The default show in binds state of the checkbox  -> 0 is hold, 1 is toggle, 2 is always
---@param id string The unique identifier for the checkbox.
---@return key_checkbox
function core.menu.key_checkbox(default_key, initial_toggle_state, default_state, show_in_binds,  default_mode_state, id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new slider with integer values.
---@param min_value number The minimum value of the slider.
---@param max_value number The maximum value of the slider.
---@param default_value number The default value of the slider.
---@param id string The unique identifier for the slider.
---@return slider_int
function core.menu.slider_int(min_value, max_value, default_value, id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new slider with floating-point values.
---@param min_value number The minimum value of the slider.
---@param max_value number The maximum value of the slider.
---@param default_value number The default value of the slider.
---@param id string The unique identifier for the slider.
---@return slider_float
function core.menu.slider_float(min_value, max_value, default_value, id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new combobox.
---@param default_index number The default index of the combobox options (1-based).
---@param id string The unique identifier for the combobox.
---@return combobox
function core.menu.combobox(default_index, id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new combobox_reorderable.
---@param default_index number The default index of the combobox options (1-based).
---@param id string The unique identifier for the combobox.
---@return combobox_reorderable
function core.menu.combobox_reorderable(default_index, id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new keybind.
---@param default_value number The default value for the keybind.
---@param initial_toggle_state boolean The initial toggle state for the keybind.
---@param id string The unique identifier for the keybind.
---@return keybind
function core.menu.keybind(default_value, initial_toggle_state, id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new button.
---@return button
---@param id string The unique identifier for the button.
function core.menu.button(id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new color picker.
---@return color_picker
---@param default_color color The default color value.
---@param id string The unique identifier for the color picker.
function core.menu.colorpicker(default_color, id)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new header
---@return header
function core.menu.header()
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new text input
---@return text_input
---@param save_input boolean?
---@param id string The unique identifier for the color picker.
function core.menu.text_input(id, save_input)
    return {} -- Empty return statement to implicitly return nil
end

--- Creates a new window
---@return window
function core.menu.window(window_id)
    return {} -- Empty return statement to implicitly return nil
end

--------------------------------------------------------------------------------
-- HTTP
--------------------------------------------------------------------------------

--- Performs an asynchronous HTTP GET request.
---
--- This API is generally used to fetch remote data (JSON, text, images, etc).
--- It is optional for texture usage. Most textures are loaded from local files
--- already stored under `scripts_data/`.
---
--- Overloads:
--- 1) core.http_get(url, callback)
--- 2) core.http_get(url, headers, callback)
---
--- Headers:
--- - `headers` is a table<string, string>
--- - Each pair is sent as: "Key: Value"
---
--- Callback parameters:
--- - `http_code` integer, HTTP status code (200, 404, etc). Transport failure may be 0 (native-defined).
--- - `content_type` string, server content type (native-defined on failure).
--- - `response_data` string, raw response body, binary safe.
--- - `response_headers` string, response headers dump, format is native-defined.
---
---@param url string
---@param headers_or_callback table<string, string>|fun(http_code: integer, content_type: string, response_data: string, response_headers: string)
---@param callback_opt fun(http_code: integer, content_type: string, response_data: string, response_headers: string)|nil
---@return nil
function core.http_get(url, headers_or_callback, callback_opt)
  return nil
end

--------------------------------------------------------------------------------
-- GRAPHICS, TEXTURES
--------------------------------------------------------------------------------

core.graphics = core.graphics or {}

--- Loads a GPU texture from raw image bytes.
---
--- Common usage patterns:
--- 1) Load from a local file in `scripts_data/`
---    - Read the file bytes with `core.read_data_file("path.png")`
---    - Pass bytes to `core.graphics.load_texture(bytes)`
---
--- 2) Load from an HTTP download (less common)
---    - Download bytes via `core.http_get(...)`
---    - Pass bytes to `core.graphics.load_texture(response_data)`
---
--- Native behavior:
--- - Returns nil if the image bytes cannot be decoded.
--- - Returns `texture_id` if texture is already loaded or already queued.
--- - Returns `texture_id, width, height` only when newly queued.
---
--- Notes:
--- - `texture_id` is a numeric handle used by `core.graphics.draw_texture`.
--- - The bytes string may contain binary data and zero bytes.
---
---@param image_data string Raw image bytes (binary-safe Lua string).
---@return integer|nil texture_id Texture handle, or nil on failure.
---@return integer|nil width Width in pixels (only returned when newly created).
---@return integer|nil height Height in pixels (only returned when newly created).
function core.graphics.load_texture(image_data)
  return nil
end

--- Draws a previously loaded texture.
---
--- Typical usage:
--- - Load once, store `texture_id` in a variable.
--- - Draw every frame (inside your render callback or equivalent).
---
--- Parameters:
--- - `texture_id` integer, returned by `core.graphics.load_texture`
--- - `top_left` vec2, screen position
--- - `width` number, draw width in pixels
--- - `height` number, draw height in pixels
--- - `color` optional, tint color (defaults to white)
--- - `is_for_window` optional boolean, defaults false (background). True draws in current window.
---
---@param texture_id integer
---@param top_left vec2
---@param width number
---@param height number
---@param color color|nil
---@param is_for_window boolean|nil
---@return nil
function core.graphics.draw_texture(texture_id, top_left, width, height, color, is_for_window)
  return nil
end

--------------------------------------------------------------------------------
-- EXAMPLES
--------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------
Example A, Most common, Load a local texture from scripts_data and draw every frame

Goal:
- Put `icons/sword.png` under: <loader_path>/scripts_data/icons/sword.png
- Load it once at startup
- Draw it each frame

Files:
- You distribute a script that, on first run, expects the file to exist inside scripts_data.
- Later, our library will automate ensuring files exist, downloading, caching, etc.

Code:

local sword_tex_id = nil
local sword_w, sword_h = 0, 0

local function load_sword_icon_once()
  if sword_tex_id ~= nil then
    return
  end

  local bytes = core.read_data_file("icons/sword.png")
  if not bytes or #bytes == 0 then
    core.log("Missing icon: scripts_data/icons/sword.png")
    return
  end

  local tex_id, w, h = core.graphics.load_texture(bytes)
  if not tex_id then
    core.log("Failed to decode icon: icons/sword.png")
    return
  end

  sword_tex_id = tex_id
  sword_w = w or sword_w
  sword_h = h or sword_h

  core.log("Loaded sword icon, texture_id=" .. tostring(sword_tex_id) ..
           ", w=" .. tostring(sword_w) .. ", h=" .. tostring(sword_h))
end

local function on_render()
  -- Ensure it is loaded once before drawing
  load_sword_icon_once()

  if sword_tex_id then
    local pos = vec2.new(20, 20)
    core.graphics.draw_texture(sword_tex_id, pos, 32, 32)
  end
end

-- Register your render callback as appropriate for your environment:
-- core.register_callback("render", on_render)
------------------------------------------------------------------------------]]

--[[----------------------------------------------------------------------------
Example B, Download once (if missing), save to scripts_data, load once, draw every frame

Goal:
- If icons/sword.png is missing locally, download it.
- Save it into scripts_data for next launch.
- Load it into GPU once.
- Draw every frame.

Important lifecycle concept:
- Download and file write happens once (or rarely).
- Texture load happens once (or whenever you need to refresh).
- draw_texture happens every frame.

Code:

local remote_icon_url = "https://dummyimage.com/64x64/000/fff.png"
local remote_icon_path = "icons/remote_icon.png"

local remote_tex_id = nil
local remote_w, remote_h = 0, 0
local remote_requested = false

local function load_remote_icon_from_disk_once()
  if remote_tex_id ~= nil then
    return true
  end

  local bytes = core.read_data_file(remote_icon_path)
  if not bytes or #bytes == 0 then
    return false
  end

  local tex_id, w, h = core.graphics.load_texture(bytes)
  if not tex_id then
    core.log("Failed to decode icon after reading from disk: " .. remote_icon_path)
    return false
  end

  remote_tex_id = tex_id
  remote_w = w or remote_w
  remote_h = h or remote_h
  return true
end

local function ensure_remote_icon_available()
  -- 1) If already loaded from disk, done.
  if load_remote_icon_from_disk_once() then
    return
  end

  -- 2) If not on disk, request download once.
  if remote_requested then
    return
  end
  remote_requested = true

  -- Ensure folder exists
  core.create_data_folder("icons")

  core.http_get(remote_icon_url, function(code, content_type, body, headers)
    if code ~= 200 or not body or #body == 0 then
      core.log("Download failed, code=" .. tostring(code) .. ", type=" .. tostring(content_type))
      remote_requested = false
      return
    end

    -- Persist to scripts_data so we do not re-download next time
    core.create_data_file(remote_icon_path)
    core.write_data_file(remote_icon_path, body)

    -- Load into GPU once
    local tex_id, w, h = core.graphics.load_texture(body)
    if not tex_id then
      core.log("Downloaded icon, but decode failed: " .. remote_icon_path)
      remote_requested = false
      return
    end

    remote_tex_id = tex_id
    remote_w = w or remote_w
    remote_h = h or remote_h

    core.log("Downloaded and loaded icon, texture_id=" .. tostring(remote_tex_id))
  end)
end

local function on_render_remote()
  ensure_remote_icon_available()

  if remote_tex_id then
    local pos = vec2.new(20, 60)
    core.graphics.draw_texture(remote_tex_id, pos, 32, 32)
  end
end

-- Register your render callback as appropriate:
-- core.register_callback("render", on_render_remote)

------------------------------------------------------------------------------]]


--[[----------------------------------------------------------------------------
Example C, HTTP GET with headers (data request, not texture)

Goal:
- Fetch JSON with auth headers.
- Process response.

Code:

local function fetch_profile()
  core.http_get("https://httpbin.org/get", {
    ["Authorization"] = "Bearer token123",
    ["Accept"] = "application/json",
    ["User-Agent"] = "MyApp/1.0",
  }, function(code, content_type, body, headers)
    core.log("Status: " .. tostring(code))
    core.log("Content-Type: " .. tostring(content_type))
    if body then
      core.log("Body: " .. tostring(body))
    end
  end)
end

-- fetch_profile()
------------------------------------------------------------------------------]]

-- More Http examples:
-- Without headers
-- core.http_get("https://httpbin.org/get", function(http_code, content_type, response_data, response_headers)
--     core.log("Status: " .. http_code)
--     core.log("Response: " .. response_data)
--     core.log("ResponseHeaders: " .. response_headers)
-- end)

-- -- With headers
-- core.http_get("https://httpbin.org/get", {
--     ["Authorization"] = "Bearer token123",
--     ["User-Agent"] = "MyApp/1.0",
--     ["Accept"] = "application/json"
-- }, function(http_code, content_type, response_data, response_headers)
--     core.log("Status: " .. http_code)
--     core.log("Response: " .. response_data)
--     core.log("ResponseHeaders: " .. response_headers)
-- end)

-- Load external texture example:
-- local function on_render()
--   if downloaded_texture then
--         -- Draw at position (100, 100) with size 200x200
--         local position = vec2.new(100, 100)
--         core.graphics.draw_texture(downloaded_texture, position, 200, 200)

--         -- Optional: draw with a custom color (semi-transparent white)
--         -- local color = core.color.new(255, 255, 255, 128)
--         -- core.graphics.draw_texture(downloaded_texture, position, 200, 200, color)
--     end

-- end

-- core.http_get("https://dummyimage.com/200x200/000/fff.png", function(http_code, content_type, response_data, response_headers)
--     if content_type ~= "error" and http_code == 200 then
--         downloaded_texture, width, height = core.graphics.load_texture(response_data)

--         if downloaded_texture then
--             core.log("Texture object created successfully and stored in global variable")
--             core.log("Texture: " .. downloaded_texture)
--             core.log("width: " .. width)
--             core.log("height: " .. height)
--         else
--             core.log("Failed to create texture from image data")
--         end
--     else
--         core.log("HTTP request failed. Code: " .. tostring(http_code))
--     end
-- end)
