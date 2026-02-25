---@class SentinelLogger
---@field private _name string Module name for prefixing
---@field private _level number Minimum log level
local Logger = {}
Logger.__index = Logger

-- Log levels (lower = more verbose)
local LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4,
    NONE = 5,
}

-- Current global minimum log level
local _global_level = LOG_LEVELS.INFO

-- Level names for display
local LEVEL_NAMES = {
    [LOG_LEVELS.DEBUG] = "DEBUG",
    [LOG_LEVELS.INFO] = "INFO",
    [LOG_LEVELS.WARNING] = "WARN",
    [LOG_LEVELS.ERROR] = "ERROR",
}

-- Shared history ring buffer (module-level, not per-instance)
local _history = {}
local _history_max = 200

-- File logging state (module-level)
local _log_file_path = nil       -- nil = no file logging
local _log_file_enabled = false

---Create a new logger instance
---@param name string The module name
---@param level? number|string Optional minimum log level
---@return SentinelLogger
function Logger:new(name, level)
    local instance = setmetatable({}, Logger)
    instance._name = name or "SentinelCore"

    if type(level) == "string" then
        instance._level = LOG_LEVELS[level:upper()] or LOG_LEVELS.INFO
    else
        instance._level = level or LOG_LEVELS.INFO
    end

    return instance
end

---Set the global minimum log level
---@param level number|string The log level
function Logger.set_global_level(level)
    if type(level) == "string" then
        _global_level = LOG_LEVELS[level:upper()] or LOG_LEVELS.INFO
    else
        _global_level = level or LOG_LEVELS.INFO
    end
end

---Get the global minimum log level
---@return number
function Logger.get_global_level()
    return _global_level
end

---Get log levels table
---@return table
function Logger.get_levels()
    return LOG_LEVELS
end

---Set the minimum log level for this logger instance
---@param level number|string The log level
function Logger:set_level(level)
    if type(level) == "string" then
        self._level = LOG_LEVELS[level:upper()] or LOG_LEVELS.INFO
    else
        self._level = level or LOG_LEVELS.INFO
    end
end

---Push an entry to the shared history buffer.
---Used by both Logger instances and ConsoleLogger for a unified stream.
---@param level_num number Log level number
---@param message string Formatted message
---@param source? string Source name (logger name or event name)
function Logger.push_history(level_num, message, source)
    local now = 0
    if core and core.time then
        now = core.time()
    end

    _history[#_history + 1] = {
        timestamp = now,
        level_num = level_num,
        level = LEVEL_NAMES[level_num] or "???",
        source = source or "",
        message = message,
    }

    while #_history > _history_max do
        table.remove(_history, 1)
    end

    -- Mirror to file log (ConsoleLogger events and direct push_history calls)
    if _log_file_enabled then
        local ts = string.format("%.3f", now)
        local level_name = LEVEL_NAMES[level_num] or "???"
        Logger._write_to_file(string.format("[%s] [%s] [%s] %s\n", ts, level_name, source or "Event", message))
    end
end

---Get recent history entries
---@param limit? number Max entries to return (default: all)
---@return table[]
function Logger.get_history(limit)
    local out = {}
    local max = tonumber(limit) or #_history
    if max < 1 then
        return out
    end

    local start_index = math.max(1, #_history - max + 1)
    for i = start_index, #_history do
        out[#out + 1] = _history[i]
    end
    return out
end

---Clear the shared history buffer
function Logger.clear_history()
    _history = {}
end

---Set the maximum history buffer size
---@param n number
function Logger.set_max_history(n)
    _history_max = tonumber(n) or 200
    while #_history > _history_max do
        table.remove(_history, 1)
    end
end

---Set the log file path. Pass nil to disable file logging.
---The file is written to scripts_data/ via core.write_data_file (append-by-read).
---@param path string|nil Relative path inside scripts_data/, or nil to disable.
function Logger.set_log_file(path)
    _log_file_path = path
    _log_file_enabled = (path ~= nil)
    if _log_file_enabled then
        local ts = "0.000"
        if core and core.time then
            ts = string.format("%.3f", core.time())
        end
        local header = string.format(
            "\n========================================\n" ..
            "  SentinelCore Log Session Started\n" ..
            "  File: %s\n" ..
            "  Time: %s\n" ..
            "========================================\n",
            path, ts
        )
        Logger._write_to_file(header)
    end
end

---Returns whether file logging is currently active.
---@return boolean
function Logger.is_file_logging_enabled()
    return _log_file_enabled
end

---Internal: append a text string to the log file.
---Uses read-then-write because the Sylvannas API only exposes core.write_data_file
---(overwrite). Wrapped in pcall so file I/O errors never crash the bot.
---@param text string
function Logger._write_to_file(text)
    if not _log_file_enabled or not _log_file_path then return end
    if not core or not core.write_data_file then return end
    pcall(function()
        local existing = ""
        if core.read_data_file then
            local ok, content = pcall(core.read_data_file, _log_file_path)
            if ok and type(content) == "string" then
                existing = content
            end
        end
        -- Ensure the file exists before writing (create_data_file is idempotent).
        if core.create_data_file then
            pcall(core.create_data_file, _log_file_path)
        end
        core.write_data_file(_log_file_path, existing .. text)
    end)
end

---Format a log message
---@private
---@param level number Log level
---@param message string The message
---@return string
function Logger:_format(level, message)
    local timestamp = "0.000"
    if core and core.time then
        timestamp = string.format("%.3f", core.time())
    end
    local level_name = LEVEL_NAMES[level] or "???"
    return string.format("[%s] [%s] [%s] %s", timestamp, level_name, self._name, message)
end

---Log a message at the specified level
---@private
---@param level number Log level
---@param message string The message
---@param ... any Format arguments
function Logger:_log(level, message, ...)
    -- Check both instance and global level
    local effective_level = math.max(self._level, _global_level)
    if level < effective_level then
        return
    end

    -- Format message with arguments if provided
    local formatted_message
    if select("#", ...) > 0 then
        local success, result = pcall(string.format, message, ...)
        if success then
            formatted_message = result
        else
            formatted_message = message .. " [FORMAT ERROR: " .. tostring(result) .. "]"
        end
    else
        formatted_message = message
    end

    local log_line = self:_format(level, formatted_message)

    -- Push to shared history; push_history also mirrors to file log.
    Logger.push_history(level, formatted_message, self._name)

    -- Output to console (handle missing core gracefully for tests)
    if not core then
        return
    end

    if level >= LOG_LEVELS.ERROR and core.log_error then
        core.log_error(log_line)
    elseif level >= LOG_LEVELS.WARNING and core.log_warning then
        core.log_warning(log_line)
    elseif core.log then
        core.log(log_line)
    end
end

---Log a debug message
---@param message string The message
---@param ... any Format arguments
function Logger:debug(message, ...)
    self:_log(LOG_LEVELS.DEBUG, message, ...)
end

---Log an info message
---@param message string The message
---@param ... any Format arguments
function Logger:info(message, ...)
    self:_log(LOG_LEVELS.INFO, message, ...)
end

---Log a warning message
---@param message string The message
---@param ... any Format arguments
function Logger:warn(message, ...)
    self:_log(LOG_LEVELS.WARNING, message, ...)
end

---Log an error message
---@param message string The message
---@param ... any Format arguments
function Logger:error(message, ...)
    self:_log(LOG_LEVELS.ERROR, message, ...)
end

---Log a table for debugging
---@param message string Description
---@param tbl table The table to log
---@param max_depth? number Maximum recursion depth (default 2)
function Logger:table(message, tbl, max_depth)
    max_depth = max_depth or 2

    local function serialize(t, depth, visited)
        if depth > max_depth then return "{...}" end
        if type(t) ~= "table" then return tostring(t) end

        visited = visited or {}
        if visited[t] then return "{circular}" end
        visited[t] = true

        local parts = {}
        for k, v in pairs(t) do
            local key_str = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
            local val_str
            if type(v) == "table" then
                val_str = serialize(v, depth + 1, visited)
            elseif type(v) == "string" then
                val_str = '"' .. v .. '"'
            else
                val_str = tostring(v)
            end
            parts[#parts + 1] = key_str .. "=" .. val_str
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end

    local serialized = serialize(tbl, 1)
    self:debug("%s: %s", message, serialized)
end

return Logger
