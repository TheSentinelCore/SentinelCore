---@class Logger
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
    NONE = 5
}

-- Current global minimum log level
local _global_level = LOG_LEVELS.INFO

-- Level names for display
local LEVEL_NAMES = {
    [LOG_LEVELS.DEBUG] = "DEBUG",
    [LOG_LEVELS.INFO] = "INFO",
    [LOG_LEVELS.WARNING] = "WARN",
    [LOG_LEVELS.ERROR] = "ERROR"
}

---Create a new logger instance for a module
---@param name string The module name
---@param level? number|string Optional minimum log level
---@return Logger
function Logger:new(name, level)
    local instance = setmetatable({}, Logger)
    instance._name = name or "SentinelGather"

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

---Set the minimum log level for this logger
---@param level number|string The log level
function Logger:set_level(level)
    if type(level) == "string" then
        self._level = LOG_LEVELS[level:upper()] or LOG_LEVELS.INFO
    else
        self._level = level or LOG_LEVELS.INFO
    end
end

---Format a log message
---@private
---@param level number Log level
---@param message string The message
---@return string
function Logger:_format(level, message)
    local timestamp = string.format("%.3f", core.time())
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

    -- Use appropriate core logging function
    if level >= LOG_LEVELS.ERROR then
        core.log_error(log_line)
    elseif level >= LOG_LEVELS.WARNING then
        core.log_warning(log_line)
    else
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
            table.insert(parts, key_str .. "=" .. val_str)
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end

    local serialized = serialize(tbl, 1)
    self:debug("%s: %s", message, serialized)
end

---Run unit tests
---@return table<string, boolean> Test results
function Logger:_test()
    local results = {}

    -- Test 1: Create logger
    local log = Logger:new("TestModule")
    results.create = (log._name == "TestModule")

    -- Test 2: Level parsing
    local log2 = Logger:new("Test", "DEBUG")
    results.level_parse = (log2._level == LOG_LEVELS.DEBUG)

    -- Test 3: Set level
    log2:set_level("WARNING")
    results.set_level = (log2._level == LOG_LEVELS.WARNING)

    -- Test 4: Format output (just verify no errors)
    local format_ok = true
    local success = pcall(function()
        log:_format(LOG_LEVELS.INFO, "test message")
    end)
    results.format = success

    -- Test 5: Log methods exist
    results.methods = (
        type(log.debug) == "function" and
        type(log.info) == "function" and
        type(log.warn) == "function" and
        type(log.error) == "function"
    )

    -- Test 6: Global level
    Logger.set_global_level("DEBUG")
    results.global_level = (Logger.get_global_level() == LOG_LEVELS.DEBUG)
    Logger.set_global_level("INFO") -- Reset

    return results
end

return Logger
