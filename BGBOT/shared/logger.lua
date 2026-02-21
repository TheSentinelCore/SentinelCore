---@module BGBOT.shared.logger
-- Simple NDJSON logger for structured telemetry events.

local logger = {}
logger.__index = logger

local function split_path(path)
    local parts = {}
    for part in tostring(path or ""):gmatch("[^/]+") do
        parts[#parts + 1] = part
    end
    return parts
end

local function json_escape(s)
    return tostring(s)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
end

local function json_encode_flat(record)
    local parts = {}
    for k, v in pairs(record or {}) do
        local key = '"' .. json_escape(k) .. '"'
        local value
        local t = type(v)
        if t == "string" then
            value = '"' .. json_escape(v) .. '"'
        elseif t == "number" then
            value = tostring(v)
        elseif t == "boolean" then
            value = v and "true" or "false"
        elseif v == nil then
            value = "null"
        else
            value = '"' .. json_escape(tostring(v)) .. '"'
        end
        parts[#parts + 1] = key .. ":" .. value
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function logger.new(opts)
    local options = opts or {}
    local self = setmetatable({}, logger)
    self.enabled = options.enabled == true
    self.dir = tostring(options.dir or "BGBOT/data/telemetry")
    self.file_name = tostring(options.file_name or "events.ndjson")
    self.path = self.dir .. "/" .. self.file_name
    self.buffer = ""
    self.file_ready = false
    self.last_error = ""
    return self
end

function logger:set_enabled(state)
    self.enabled = state == true
    if self.enabled then
        self:ensure_file()
    end
end

function logger:is_enabled()
    return self.enabled == true
end

function logger:get_path()
    return self.path
end

function logger:ensure_file()
    if self.file_ready then
        return true
    end

    local ok, err = pcall(function()
        local parts = split_path(self.dir)
        local cursor = nil
        for _, part in ipairs(parts) do
            if cursor then
                cursor = cursor .. "/" .. part
            else
                cursor = part
            end
            core.create_data_folder(cursor)
        end

        local read_ok, existing = pcall(core.read_data_file, self.path)
        if read_ok and existing and existing ~= "" then
            self.buffer = existing
        else
            core.create_data_file(self.path)
            self.buffer = ""
        end
    end)

    if not ok then
        self.last_error = tostring(err)
        return false
    end

    self.file_ready = true
    self.last_error = ""
    return true
end

function logger:append(record)
    if not self.enabled then
        return false
    end
    if not self:ensure_file() then
        return false
    end

    local row = {}
    for k, v in pairs(record or {}) do
        row[k] = v
    end
    if row.time == nil then
        row.time = core.time()
    end

    self.buffer = self.buffer .. json_encode_flat(row) .. "\n"
    local ok, err = pcall(core.write_data_file, self.path, self.buffer)
    if not ok then
        self.last_error = tostring(err)
        return false
    end

    self.last_error = ""
    return true
end

return logger
