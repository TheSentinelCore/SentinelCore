local Logger = {}
Logger.__index = Logger

---@param tag string
---@return table
function Logger:new(tag)
    local o = setmetatable({}, Logger)
    o._tag = tostring(tag or "StrathDuoMage")
    return o
end

local function write(level, tag, message)
    local line = string.format("[%s] [%s] %s", tostring(tag), tostring(level), tostring(message or ""))
    if level == "ERROR" and core and core.log_error then
        core.log_error(line)
        return
    end
    if core and core.log then
        core.log(line)
    end
end

function Logger:debug(fmt, ...)
    write("DEBUG", self._tag, string.format(tostring(fmt or ""), ...))
end

function Logger:info(fmt, ...)
    write("INFO", self._tag, string.format(tostring(fmt or ""), ...))
end

function Logger:warn(fmt, ...)
    write("WARN", self._tag, string.format(tostring(fmt or ""), ...))
end

function Logger:error(fmt, ...)
    write("ERROR", self._tag, string.format(tostring(fmt or ""), ...))
end

return Logger
