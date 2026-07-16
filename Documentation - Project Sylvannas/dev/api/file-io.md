---
title: "File I/O Functions"
source: "https://docs.project-sylvanas.net/dev/api/file-io"
crawled: "2026-07-14"
---

# File I/O Functions

## Overview

This module provides sandboxed file operations for reading and writing data. The scripting environment is intentionally sandboxed to prevent malicious code from accessing arbitrary files on your system.

You can interact with files in two allowed locations:

1.  **Game Files** - Inside the World of Warcraft installation folder (read-only)
2.  **Loader Data Files** - Inside the loader's `scripts_data/` folder (read/write)

> **Quick Alternative**
> 
> For simple logging needs, we recommend using [izi.log](https://docs.project-sylvanas.net/dev/libraries/izi#izilog) from the izi library. It handles file creation and management automatically, making it much faster than manually building log files.

---

## Game Files (Read-Only)

These functions allow you to read files from inside the World of Warcraft installation folder. Any path outside the WoW folder is blocked.

### `core.read_file`

**Syntax:**
```lua
core.read_file(filename: string) -> string
```

**Parameters:**
- `filename`: `string` - Path inside the World of Warcraft folder (UTF-8).

**Returns:** `string` - The file contents as a Lua string. Returns empty string or nil on failure.

**Description:** Reads the entire contents of a sandboxed game file. Use relative-style paths such as `Data/...` or `_retail_/...` depending on your client layout.

**Example Usage:**
```lua
local text = core.read_file("_retail_/WTF/Config.wtf")
if text and #text > 0 then
    core.log("Config length: " .. #text)
end
```

---

### `core.read_file_partial`

**Syntax:**
```lua
core.read_file_partial(filename: string, offset: integer, size_to_read: integer) -> string|nil
```

**Parameters:**
- `filename`: `string` - Path inside the World of Warcraft folder (UTF-8).
- `offset`: `integer` - Byte offset to start reading from.
- `size_to_read`: `integer` - Number of bytes to read.

**Returns:** `string|nil` - The read bytes as a Lua string, or nil on failure.

**Description:** Reads a portion of a sandboxed game file, starting at a byte offset. The returned string can contain binary data and may include zero bytes.

**Example Usage:**
```lua
local path = "_retail_/WTF/Config.wtf"
local chunk = core.read_file_partial(path, 0, 64)
if chunk then
    core.log("First 64 bytes: " .. chunk)
else
    core.log("Read failed (outside sandbox, missing, or access denied)")
end
```

---

### `core.get_file_size`

**Syntax:**
```lua
core.get_file_size(filename: string) -> integer
```

**Parameters:**
- `filename`: `string` - Path inside the World of Warcraft folder (UTF-8).

**Returns:** `integer` - The file size in bytes. Returns 0 if file doesn't exist or isn't accessible.

**Description:** Gets the size of a sandboxed game file in bytes.

> **note**
> 
> If you need to distinguish between "missing" vs "empty file", attempt a small read as well.

**Example Usage:**
```lua
local path = "_retail_/WTF/Config.wtf"
local size = core.get_file_size(path)
if size > 0 then
    core.log("Config size: " .. size .. " bytes")
else
    core.log("Missing, blocked, or empty file")
end
```

---

## Loader Data Files (Read/Write)

These functions allow you to read and write files inside the loader's `scripts_data/` directory. This is the only directory writable by scripts.

**Important:** All paths are relative to `scripts_data/`. Do not prefix with `scripts_data/` yourself.

### `core.create_data_folder`

**Syntax:**
```lua
core.create_data_folder(folder: string) -> nil
```

**Parameters:**
- `folder`: `string` - Folder path inside `scripts_data/` (UTF-8).

**Description:** Creates a folder inside the loader's `scripts_data/` directory.

**Example Usage:**
```lua
-- Creates: <loader_path>/scripts_data/profiles/
core.create_data_folder("profiles")
-- Then you can create files in it
core.create_data_file("profiles/user1.json")
```

---

### `core.create_data_file`

**Syntax:**
```lua
core.create_data_file(filename: string) -> nil
```

**Parameters:**
- `filename`: `string` - Path inside `scripts_data/` (UTF-8).

**Description:** Creates a new data file inside the loader's `scripts_data/` directory. Parent folders should exist - use `core.create_data_folder` for subfolders if needed.

**Example Usage:**
```lua
core.create_data_file("settings.json")
core.write_data_file("settings.json", "{}")
```

---

### `core.write_data_file`

**Syntax:**
```lua
core.write_data_file(filename: string, data: string) -> nil
```

**Parameters:**
- `filename`: `string` - Path inside `scripts_data/` (UTF-8).
- `data`: `string` - The data to write into the file.

**Description:** Writes data to a loader data file inside `scripts_data/`. In most systems, this overwrites the file.

**Example Usage:**
```lua
core.write_data_file("cache/state.txt", "last_login=123")
```

---

### `core.read_data_file`

**Syntax:**
```lua
core.read_data_file(filename: string) -> string
```

**Parameters:**
- `filename`: `string` - Path inside `scripts_data/` (UTF-8).

**Returns:** `string` - The file contents as a Lua string.

**Description:** Reads the entire contents of a loader data file from `scripts_data/`. The returned string can contain binary data.

**Example Usage:**
```lua
local json = core.read_data_file("settings.json")
if json and #json > 0 then
    core.log("Settings: " .. json)
end
```

---

### `core.read_data_file_partial`

**Syntax:**
```lua
core.read_data_file_partial(filename: string, offset: integer, size_to_read: integer) -> string|nil
```

**Parameters:**
- `filename`: `string` - Path inside `scripts_data/` (UTF-8).
- `offset`: `integer` - Byte offset to start reading from.
- `size_to_read`: `integer` - Number of bytes to read.

**Returns:** `string|nil` - The read bytes as a Lua string, or nil on failure.

**Description:** Reads a portion of a loader data file from `scripts_data/`, starting at a byte offset. The returned string can contain binary data and may include zero bytes.

**Example Usage:**
```lua
local chunk = core.read_data_file_partial("settings.json", 0, 256)
if chunk then
    core.log("JSON header: " .. chunk)
else
    core.log("Read failed (missing or blocked)")
end
```

---

### `core.get_data_file_size`

**Syntax:**
```lua
core.get_data_file_size(filename: string) -> integer
```

**Parameters:**
- `filename`: `string` - Path inside `scripts_data/` (UTF-8).

**Returns:** `integer` - The file size in bytes.

**Description:** Gets the size of a loader data file in bytes from `scripts_data/`. Returns 0 if file doesn't exist or isn't accessible.

**Example Usage:**
```lua
local size = core.get_data_file_size("settings.json")
if size > 0 then
    core.log("settings.json size: " .. size .. " bytes")
else
    core.log("Missing, blocked, or empty file")
end
```

---

### `core.read_dir`

**Syntax:**
```lua
core.read_dir(directory: string) -> string[]|nil
```

**Parameters:**
- `directory`: `string` - Directory path inside `scripts_data/` (UTF-8).

**Returns:** `string[]|nil` - Array of file/folder names, or `nil` on failure.

**Description:** Lists all files and folders in a directory inside `scripts_data/`. Returns an array of names (not full paths). Includes both files and subdirectories but does not include `.` or `..` entries.

> **note**
> 
> This function only works within the `scripts_data/` sandbox. Any path that resolves outside this directory will return `nil`.

**Example Usage:**
```lua
-- List all files in the profiles folder
local files = core.read_dir("profiles")
if files then
    core.log("Found " .. #files .. " items:")
    for i, name in ipairs(files) do
        core.log("  " .. name)
    end
else
    core.log("Directory not found or access denied")
end
```

**Example: Finding All JSON Files:**
```lua
local function get_json_files(folder)
    local files = core.read_dir(folder)
    if not files then return {} end
    
    local json_files = {}
    for i = 1, #files do
        local name = files[i]
        if name:match("%.json$") then
            table.insert(json_files, name)
        end
    end
    return json_files
end

local configs = get_json_files("configs")
for _, filename in ipairs(configs) do
    core.log("Found config: " .. filename)
end
```

---

## Log Files

Log files are intended for diagnostics and debugging output. The exact storage location is implementation-defined by the loader.

> **tip**
> 
> For quick and easy logging, consider using [izi.log](https://docs.project-sylvanas.net/dev/libraries/izi#izilog) from the izi library instead of manually managing log files.

### `core.create_log_folder`

**Syntax:**
```lua
core.create_log_folder(folder: string) -> boolean
```

**Parameters:**
- `folder`: `string` - Folder path inside `scripts_log/` (UTF-8).

**Returns:** `boolean` - `true` if the folder (and any missing parents) was created or already exists.

**Description:** Creates a folder inside the loader's `scripts_log/` directory. Intermediate segments are created automatically, so nested paths like `"my_addon/combat"` work without calling the function for each level.

**Example Usage:**
```lua
-- Creates: <loader_path>/scripts_log/my_addon/
core.create_log_folder("my_addon")
-- Then you can create log files inside it
core.create_log_file("my_addon/combat.log")
core.write_log_file("my_addon/combat.log", "Addon started\n")
```

---

### `core.create_log_file`

**Syntax:**
```lua
core.create_log_file(filename: string) -> nil
```

**Parameters:**
- `filename`: `string` - The name of the log file to create.

**Description:** Creates a new log file.

> **note**
> 
> If the log file already exists, the native side may truncate it or keep it, depending on implementation.

---

### `core.write_log_file`

**Syntax:**
```lua
core.write_log_file(filename: string, message: string) -> nil
```

**Parameters:**
- `filename`: `string` - The name of the log file to write to.
- `message`: `string` - The message to write into the log file.

**Description:** Writes a message to a log file. Use this for debug output that should persist outside the in-game console.

> **note**
> 
> Whether a newline is automatically appended depends on native implementation. If you want one, include `"\n"` yourself.

**Example Usage:**
```lua
-- Create a log file at startup
core.create_log_file("combat.log")
core.write_log_file("combat.log", "Addon started\n")

-- Log events during gameplay
core.write_log_file("combat.log", "Target acquired: " .. tostring(unit_name) .. "\n")
core.write_log_file("combat.log", "Spell cast: " .. spell_name .. " at " .. tostring(core.game_time()) .. "\n")
```

---

## Complete Examples

### Example: Saving and Loading Settings

```lua
local SETTINGS_FILE = "my_addon/settings.json"

-- Save settings
local function save_settings(settings)
    core.create_data_folder("my_addon")
    core.create_data_file(SETTINGS_FILE)
    
    -- Convert table to JSON string (you'd use a JSON library)
    local json_str = '{"enabled": true, "threshold": 50}'
    core.write_data_file(SETTINGS_FILE, json_str)
    
    core.log("Settings saved!")
end

-- Load settings
local function load_settings()
    local json_str = core.read_data_file(SETTINGS_FILE)
    if json_str and #json_str > 0 then
        -- Parse JSON string (you'd use a JSON library)
        core.log("Loaded settings: " .. json_str)
        return json_str
    else
        core.log("No settings found, using defaults")
        return nil
    end
end
```

### Example: Debug Logging System

```lua
local DEBUG_LOG = "debug.log"
local debug_enabled = true

local function init_debug_log()
    if debug_enabled then
        core.create_log_file(DEBUG_LOG)
        core.write_log_file(DEBUG_LOG, "=== Debug session started at " .. tostring(core.game_time()) .. " ===\n")
    end
end

local function debug_log(message)
    if debug_enabled then
        local timestamp = string.format("[%.2f] ", core.game_time() / 1000)
        core.write_log_file(DEBUG_LOG, timestamp .. message .. "\n")
    end
end

-- Usage
init_debug_log()
debug_log("Player entered combat")
debug_log("Cast spell ID: 12345")
```

### Example: Loading Local Textures

> **Easier Alternatives**
> 
> For texture and icon loading, consider using these higher-level utilities instead of raw file I/O:
> 
> - **[Assets Helper](https://docs.project-sylvanas.net/dev/api/assets-helper)** - Automatic texture loading with caching and ZIP pack support
> - **[Icons Helper](https://docs.project-sylvanas.net/dev/api/icons-helper)** - WoW icon loading from Wowhead with disk caching
> - **[IZI SDK Graphics](https://docs.project-sylvanas.net/dev/libraries/izi/graphics)** - High-level graphics API wrapping both helpers
> 
> The example below shows raw file I/O for educational purposes, but the utilities above handle caching, error recovery, and format conversion automatically.

```lua
local my_texture_id = nil

local function load_my_texture()
    if my_texture_id then return end
    
    local bytes = core.read_data_file("icons/my_icon.png")
    if not bytes or #bytes == 0 then
        core.log("Missing icon: scripts_data/icons/my_icon.png")
        return
    end
    
    local tex_id, width, height = core.graphics.load_texture(bytes)
    if tex_id then
        my_texture_id = tex_id
        core.log("Texture loaded! Size: " .. width .. "x" .. height)
    else
        core.log("Failed to decode texture")
    end
end
```

---

## File Deletion Functions

### `core.delete_file`

**Syntax:**
```lua
core.delete_file(filename: string) -> boolean
```

**Parameters:**
- `filename`: `string` - Path inside the World of Warcraft installation folder (UTF-8).

**Returns:** `boolean` - `true` if the file was successfully deleted, `false` otherwise.

**Description:** Deletes a file inside the World of Warcraft installation folder. This operation is sandboxed and only allows deletion of files within the WoW folder.

**Example Usage:**
```lua
local success = core.delete_file("_retail_/WTF/old_config.bak")
if success then
    core.log("File deleted successfully")
end
```

---

### `core.delete_log_file`

**Syntax:**
```lua
core.delete_log_file(filename: string) -> boolean
```

**Parameters:**
- `filename`: `string` - The name of the log file to delete.

**Returns:** `boolean` - `true` if the log file was successfully deleted, `false` otherwise.

**Description:** Deletes a log file from the `scripts_log/` directory.

**Example Usage:**
```lua
local success = core.delete_log_file("debug.log")
if success then
    core.log("Log file deleted")
end
```

---

### `core.delete_data_file`

**Syntax:**
```lua
core.delete_data_file(filename: string) -> boolean
```

**Parameters:**
- `filename`: `string` - Path inside `scripts_data/` (UTF-8).

**Returns:** `boolean` - `true` if the data file was successfully deleted, `false` otherwise.

**Description:** Deletes a data file from the `scripts_data/` directory.

**Example Usage:**
```lua
local success = core.delete_data_file("cache/old_state.txt")
if success then
    core.log("Data file deleted")
end
```

---

## Security Notes

-   Scripts can **only** read from the WoW installation folder
-   Scripts can **only** write to the `scripts_data/` folder
-   Any attempt to access files outside these locations will fail
-   This sandboxing is intentional to prevent malicious code
