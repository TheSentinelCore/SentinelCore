local JSON = require("lib/JSON")

local Autoloader = {}

local AUTOLOADER_DIR = "sentinel/autoloaders"

local _loaded = nil           -- parsed autoloader table
local _loaded_filename = nil  -- which file is loaded

---Log an error message if core.log is available.
---@param msg string
local function log_error(msg)
    if core and core.log then
        core.log("[SentinelCore] Autoloader: " .. msg)
    end
end

---Scan the autoloader directory for JSON files.
---Returns an array of {filename, name, author} by reading each file's metadata.
---@return table[] entries Array of {filename=string, name=string, author=string}
function Autoloader.scan()
    local results = {}

    local ok, files = pcall(core.read_dir, AUTOLOADER_DIR)
    if not ok or not files then
        return results
    end

    for _, filename in ipairs(files) do
        if filename:match("%.json$") then
            local path = AUTOLOADER_DIR .. "/" .. filename
            local read_ok, content = pcall(core.read_data_file, path)
            if read_ok and content then
                local decode_ok, data = pcall(JSON.decode, JSON, content)
                if decode_ok and type(data) == "table" then
                    results[#results + 1] = {
                        filename = filename,
                        name = type(data.name) == "string" and data.name or "",
                        author = type(data.author) == "string" and data.author or "",
                    }
                end
            end
        end
    end

    return results
end

---Load a specific autoloader file by filename.
---Validates schema_version and entries structure.
---@param filename string Filename within AUTOLOADER_DIR
---@return boolean success
function Autoloader.load(filename)
    if type(filename) ~= "string" or filename == "" then
        log_error("load() requires a non-empty filename")
        return false
    end

    local path = AUTOLOADER_DIR .. "/" .. filename

    local read_ok, content = pcall(core.read_data_file, path)
    if not read_ok or not content then
        log_error("failed to read file: " .. path)
        return false
    end

    local decode_ok, data = pcall(JSON.decode, JSON, content)
    if not decode_ok or type(data) ~= "table" then
        log_error("failed to decode JSON: " .. path)
        return false
    end

    -- Validate schema
    if data.schema_version ~= "1.0" then
        log_error("unsupported schema_version (expected \"1.0\"): " .. path)
        return false
    end

    -- Validate entries
    if type(data.entries) ~= "table" or #data.entries == 0 then
        log_error("entries must be a non-empty array: " .. path)
        return false
    end

    for i, entry in ipairs(data.entries) do
        if type(entry) ~= "table" then
            log_error("entries[" .. i .. "] must be a table: " .. path)
            return false
        end
        if type(entry.min_level) ~= "number" then
            log_error("entries[" .. i .. "].min_level must be a number: " .. path)
            return false
        end
        if type(entry.max_level) ~= "number" then
            log_error("entries[" .. i .. "].max_level must be a number: " .. path)
            return false
        end
        if type(entry.profile) ~= "string" or entry.profile == "" then
            log_error("entries[" .. i .. "].profile must be a non-empty string: " .. path)
            return false
        end
    end

    _loaded = data
    _loaded_filename = filename
    return true
end

---Check if an autoloader file is currently loaded.
---@return boolean
function Autoloader.is_loaded()
    return _loaded ~= nil
end

---Get the filename of the currently loaded autoloader.
---@return string|nil
function Autoloader.get_loaded_filename()
    return _loaded_filename
end

---Resolve a player level to a profile filename.
---First-match-wins: iterates entries and returns the first whose level range contains player_level.
---@param player_level number
---@return string|nil profile_filename
function Autoloader.resolve(player_level)
    if not _loaded or type(_loaded.entries) ~= "table" then
        return nil
    end

    for _, entry in ipairs(_loaded.entries) do
        if player_level >= entry.min_level and player_level <= entry.max_level then
            return entry.profile
        end
    end

    return nil
end

---Get the entries array from the loaded autoloader.
---@return table[] entries
function Autoloader.get_entries()
    if not _loaded or type(_loaded.entries) ~= "table" then
        return {}
    end
    return _loaded.entries
end

---Write an autoloader table as JSON to a file in the autoloader directory.
---Creates the directory if it does not exist.
---@param autoloader_table table The autoloader data to save
---@param filename string Target filename within AUTOLOADER_DIR
---@return boolean success
function Autoloader.save(autoloader_table, filename)
    if type(autoloader_table) ~= "table" then
        log_error("save() requires a table")
        return false
    end
    if type(filename) ~= "string" or filename == "" then
        log_error("save() requires a non-empty filename")
        return false
    end

    local mkdir_ok = pcall(core.create_data_folder, AUTOLOADER_DIR)
    if not mkdir_ok then
        log_error("failed to create directory: " .. AUTOLOADER_DIR)
        return false
    end

    local encode_ok, json_str = pcall(JSON.encode, JSON, autoloader_table)
    if not encode_ok or type(json_str) ~= "string" then
        log_error("failed to encode autoloader table to JSON")
        return false
    end

    local path = AUTOLOADER_DIR .. "/" .. filename
    local write_ok = pcall(core.write_data_file, path, json_str)
    if not write_ok then
        log_error("failed to write file: " .. path)
        return false
    end

    return true
end

---Unload the current autoloader, clearing all cached state.
function Autoloader.unload()
    _loaded = nil
    _loaded_filename = nil
end

return Autoloader
