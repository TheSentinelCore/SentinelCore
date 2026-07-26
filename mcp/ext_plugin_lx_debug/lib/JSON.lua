---@class JSON
---@field private pos number Current parsing position
---@field private str string Current string being parsed
---@field private len number Length of current string
local JSON = {}
JSON.__index = JSON

-- Character codes for faster comparison
local CHAR_SPACE = 32
local CHAR_TAB = 9
local CHAR_NEWLINE = 10
local CHAR_RETURN = 13
local CHAR_QUOTE = 34
local CHAR_COLON = 58
local CHAR_COMMA = 44
local CHAR_OPEN_BRACE = 123
local CHAR_CLOSE_BRACE = 125
local CHAR_OPEN_BRACKET = 91
local CHAR_CLOSE_BRACKET = 93
local CHAR_BACKSLASH = 92
local CHAR_SLASH = 47
local CHAR_B = 98
local CHAR_F = 102
local CHAR_N = 110
local CHAR_R = 114
local CHAR_T = 116
local CHAR_U = 117

-- Escape character mapping
local ESCAPE_MAP = {
    [CHAR_QUOTE] = '"',
    [CHAR_BACKSLASH] = '\\',
    [CHAR_SLASH] = '/',
    [CHAR_B] = '\b',
    [CHAR_F] = '\f',
    [CHAR_N] = '\n',
    [CHAR_R] = '\r',
    [CHAR_T] = '\t',
}

-- Reverse escape mapping for encoding
local ENCODE_ESCAPE_MAP = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

---Create a new JSON parser/encoder instance
---@return JSON
function JSON:new()
    local instance = setmetatable({}, JSON)
    instance.pos = 1
    instance.str = ""
    instance.len = 0
    return instance
end

---Skip whitespace characters
---@private
function JSON:_skip_whitespace()
    while self.pos <= self.len do
        local byte = self.str:byte(self.pos)
        if byte == CHAR_SPACE or byte == CHAR_TAB or byte == CHAR_NEWLINE or byte == CHAR_RETURN then
            self.pos = self.pos + 1
        else
            break
        end
    end
end

---Parse a string value
---@private
---@return string
function JSON:_parse_string()
    -- Skip opening quote
    self.pos = self.pos + 1
    local start = self.pos
    local result = {}
    local has_escape = false

    while self.pos <= self.len do
        local byte = self.str:byte(self.pos)

        if byte == CHAR_QUOTE then
            if not has_escape then
                -- Simple string with no escapes
                local str = self.str:sub(start, self.pos - 1)
                self.pos = self.pos + 1
                return str
            else
                -- Already built result table
                self.pos = self.pos + 1
                return table.concat(result)
            end
        elseif byte == CHAR_BACKSLASH then
            has_escape = true
            -- Add everything before the escape
            if self.pos > start then
                table.insert(result, self.str:sub(start, self.pos - 1))
            end
            self.pos = self.pos + 1

            if self.pos > self.len then
                error("JSON: Unexpected end of string")
            end

            local escape_byte = self.str:byte(self.pos)
            if escape_byte == CHAR_U then
                -- Unicode escape \uXXXX
                self.pos = self.pos + 1
                local hex = self.str:sub(self.pos, self.pos + 3)
                if #hex ~= 4 then
                    error("JSON: Invalid unicode escape")
                end
                local code = tonumber(hex, 16)
                if not code then
                    error("JSON: Invalid unicode escape")
                end
                -- Convert to UTF-8
                if code < 0x80 then
                    table.insert(result, string.char(code))
                elseif code < 0x800 then
                    table.insert(result, string.char(
                        0xC0 + math.floor(code / 64),
                        0x80 + (code % 64)
                    ))
                else
                    table.insert(result, string.char(
                        0xE0 + math.floor(code / 4096),
                        0x80 + (math.floor(code / 64) % 64),
                        0x80 + (code % 64)
                    ))
                end
                self.pos = self.pos + 4
            else
                local escaped = ESCAPE_MAP[escape_byte]
                if escaped then
                    table.insert(result, escaped)
                else
                    error("JSON: Invalid escape character: " .. string.char(escape_byte))
                end
                self.pos = self.pos + 1
            end
            start = self.pos
        else
            self.pos = self.pos + 1
        end
    end

    error("JSON: Unterminated string")
end

---Parse a number value
---@private
---@return number
function JSON:_parse_number()
    local start = self.pos

    -- Handle negative
    if self.str:byte(self.pos) == 45 then -- '-'
        self.pos = self.pos + 1
    end

    -- Integer part
    while self.pos <= self.len do
        local byte = self.str:byte(self.pos)
        if byte >= 48 and byte <= 57 then -- 0-9
            self.pos = self.pos + 1
        else
            break
        end
    end

    -- Decimal part
    if self.pos <= self.len and self.str:byte(self.pos) == 46 then -- '.'
        self.pos = self.pos + 1
        while self.pos <= self.len do
            local byte = self.str:byte(self.pos)
            if byte >= 48 and byte <= 57 then
                self.pos = self.pos + 1
            else
                break
            end
        end
    end

    -- Exponent part
    if self.pos <= self.len then
        local byte = self.str:byte(self.pos)
        if byte == 101 or byte == 69 then -- 'e' or 'E'
            self.pos = self.pos + 1
            byte = self.str:byte(self.pos)
            if byte == 43 or byte == 45 then -- '+' or '-'
                self.pos = self.pos + 1
            end
            while self.pos <= self.len do
                byte = self.str:byte(self.pos)
                if byte >= 48 and byte <= 57 then
                    self.pos = self.pos + 1
                else
                    break
                end
            end
        end
    end

    local num_str = self.str:sub(start, self.pos - 1)
    local num = tonumber(num_str)
    if not num then
        error("JSON: Invalid number: " .. num_str)
    end
    return num
end

---Parse an array
---@private
---@return table
function JSON:_parse_array()
    local arr = {}
    self.pos = self.pos + 1 -- Skip '['

    self:_skip_whitespace()

    -- Empty array
    if self.pos <= self.len and self.str:byte(self.pos) == CHAR_CLOSE_BRACKET then
        self.pos = self.pos + 1
        return arr
    end

    while self.pos <= self.len do
        local value = self:_parse_value()
        table.insert(arr, value)

        self:_skip_whitespace()

        local byte = self.str:byte(self.pos)
        if byte == CHAR_CLOSE_BRACKET then
            self.pos = self.pos + 1
            return arr
        elseif byte == CHAR_COMMA then
            self.pos = self.pos + 1
            self:_skip_whitespace()
        else
            error("JSON: Expected ',' or ']' in array")
        end
    end

    error("JSON: Unterminated array")
end

---Parse an object
---@private
---@return table
function JSON:_parse_object()
    local obj = {}
    self.pos = self.pos + 1 -- Skip '{'

    self:_skip_whitespace()

    -- Empty object
    if self.pos <= self.len and self.str:byte(self.pos) == CHAR_CLOSE_BRACE then
        self.pos = self.pos + 1
        return obj
    end

    while self.pos <= self.len do
        self:_skip_whitespace()

        -- Parse key
        if self.str:byte(self.pos) ~= CHAR_QUOTE then
            error("JSON: Expected string key in object")
        end
        local key = self:_parse_string()

        self:_skip_whitespace()

        -- Expect colon
        if self.str:byte(self.pos) ~= CHAR_COLON then
            error("JSON: Expected ':' after object key")
        end
        self.pos = self.pos + 1

        self:_skip_whitespace()

        -- Parse value
        local value = self:_parse_value()
        obj[key] = value

        self:_skip_whitespace()

        local byte = self.str:byte(self.pos)
        if byte == CHAR_CLOSE_BRACE then
            self.pos = self.pos + 1
            return obj
        elseif byte == CHAR_COMMA then
            self.pos = self.pos + 1
            self:_skip_whitespace()
        else
            error("JSON: Expected ',' or '}' in object")
        end
    end

    error("JSON: Unterminated object")
end

---Parse a JSON value
---@private
---@return any
function JSON:_parse_value()
    self:_skip_whitespace()

    if self.pos > self.len then
        error("JSON: Unexpected end of input")
    end

    local byte = self.str:byte(self.pos)

    -- String
    if byte == CHAR_QUOTE then
        return self:_parse_string()
    end

    -- Object
    if byte == CHAR_OPEN_BRACE then
        return self:_parse_object()
    end

    -- Array
    if byte == CHAR_OPEN_BRACKET then
        return self:_parse_array()
    end

    -- Number (starts with digit or minus)
    if (byte >= 48 and byte <= 57) or byte == 45 then
        return self:_parse_number()
    end

    -- true
    if self.str:sub(self.pos, self.pos + 3) == "true" then
        self.pos = self.pos + 4
        return true
    end

    -- false
    if self.str:sub(self.pos, self.pos + 4) == "false" then
        self.pos = self.pos + 5
        return false
    end

    -- null
    if self.str:sub(self.pos, self.pos + 3) == "null" then
        self.pos = self.pos + 4
        return nil
    end

    error("JSON: Unexpected character at position " .. self.pos .. ": " .. string.char(byte))
end

---Decode a JSON string into a Lua value
---@param json_str string The JSON string to decode
---@return any value The decoded Lua value
---@return string|nil error Error message if decoding failed
function JSON:decode(json_str)
    if type(json_str) ~= "string" then
        return nil, "JSON: Expected string input"
    end

    if json_str == "" then
        return nil, "JSON: Empty input"
    end

    self.str = json_str
    self.len = #json_str
    self.pos = 1

    local ok, result = pcall(function()
        return self:_parse_value()
    end)

    if not ok then
        return nil, tostring(result)
    end

    return result, nil
end

---Encode a string value for JSON
---@private
---@param str string
---@return string
local function encode_string(str)
    local result = {'"'}
    for i = 1, #str do
        local char = str:sub(i, i)
        local escape = ENCODE_ESCAPE_MAP[char]
        if escape then
            table.insert(result, escape)
        elseif char:byte() < 32 then
            -- Control character - encode as \uXXXX
            table.insert(result, string.format("\\u%04x", char:byte()))
        else
            table.insert(result, char)
        end
    end
    table.insert(result, '"')
    return table.concat(result)
end

---Encode a Lua value to JSON string
---@private
---@param value any The value to encode
---@param indent number|nil Current indentation level (for pretty printing)
---@param pretty boolean|nil Whether to pretty print
---@return string
local function encode_value(value, indent, pretty)
    local value_type = type(value)

    if value == nil then
        return "null"
    end

    if value_type == "boolean" then
        return value and "true" or "false"
    end

    if value_type == "number" then
        -- Handle special float values
        if value ~= value then -- NaN
            return "null"
        end
        if value == math.huge or value == -math.huge then
            return "null"
        end
        -- Use integer format if possible
        if math.floor(value) == value and math.abs(value) < 2^53 then
            return string.format("%d", value)
        end
        return string.format("%.14g", value)
    end

    if value_type == "string" then
        return encode_string(value)
    end

    if value_type == "table" then
        local is_array = true
        local max_index = 0
        local count = 0

        -- Check if it's an array
        for k, _ in pairs(value) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                is_array = false
                break
            end
            if k > max_index then
                max_index = k
            end
            count = count + 1
        end

        -- Also check for holes
        if is_array and max_index ~= count then
            is_array = false
        end

        local new_indent = indent and (indent + 1) or nil
        local indent_str = ""
        local newline = ""
        local space = ""

        if pretty and indent then
            indent_str = string.rep("  ", indent)
            newline = "\n"
            space = " "
        end

        local child_indent_str = ""
        if pretty and new_indent then
            child_indent_str = string.rep("  ", new_indent)
        end

        if is_array then
            if max_index == 0 then
                return "[]"
            end

            local parts = {}
            for i = 1, max_index do
                local v = value[i]
                local encoded = encode_value(v, new_indent, pretty)
                table.insert(parts, child_indent_str .. encoded)
            end

            if pretty then
                return "[" .. newline .. table.concat(parts, "," .. newline) .. newline .. indent_str .. "]"
            else
                return "[" .. table.concat(parts, ",") .. "]"
            end
        else
            local parts = {}
            -- Sort keys for consistent output
            local keys = {}
            for k in pairs(value) do
                if type(k) == "string" then
                    table.insert(keys, k)
                end
            end
            table.sort(keys)

            if #keys == 0 then
                return "{}"
            end

            for _, k in ipairs(keys) do
                local v = value[k]
                local encoded_key = encode_string(k)
                local encoded_value = encode_value(v, new_indent, pretty)
                table.insert(parts, child_indent_str .. encoded_key .. ":" .. space .. encoded_value)
            end

            if pretty then
                return "{" .. newline .. table.concat(parts, "," .. newline) .. newline .. indent_str .. "}"
            else
                return "{" .. table.concat(parts, ",") .. "}"
            end
        end
    end

    -- Unsupported type
    return "null"
end

---Encode a Lua value to JSON string
---@param value any The Lua value to encode
---@param pretty boolean|nil If true, format with indentation
---@return string json The JSON string
---@return string|nil error Error message if encoding failed
function JSON:encode(value, pretty)
    local ok, result = pcall(function()
        return encode_value(value, pretty and 0 or nil, pretty)
    end)

    if not ok then
        return "", tostring(result)
    end

    return result, nil
end

-- Create singleton instance
local json_instance = JSON:new()

---Decode a JSON string (singleton wrapper)
---@param json_str string The JSON string to decode
---@return any value The decoded Lua value
---@return string|nil error Error message if decoding failed
local function decode(json_str)
    return json_instance:decode(json_str)
end

---Encode a Lua value to JSON string (singleton wrapper)
---@param value any The Lua value to encode
---@param pretty boolean|nil If true, format with indentation
---@return string json The JSON string
---@return string|nil error Error message if encoding failed
local function encode(value, pretty)
    return json_instance:encode(value, pretty)
end

return {
    decode = decode,
    encode = encode,
    new = function() return JSON:new() end
}
