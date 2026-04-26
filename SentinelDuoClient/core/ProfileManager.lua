-- ProfileManager.lua — File-backed profile CRUD.
-- All I/O goes to scripts_data/SentinelDuoFarm/profiles/ (PS sandbox).

local helpers = require("lib/helpers")

local PROFILE_DIR = "SentinelDuoFarm/profiles"
local ACTIVE_FILE = "SentinelDuoFarm/active_profile.txt"

local ProfileManager = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Lua table serializer — produces a valid "return { ... }" Lua source file.
-- ─────────────────────────────────────────────────────────────────────────────
local function serialize_val(val, depth)
    local t = type(val)
    if t == "nil" then
        return "nil"
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        -- Escape backslash, double-quote, and control characters
        local s = val
        s = s:gsub("\\", "\\\\")
        s = s:gsub("\"", "\\\"")
        s = s:gsub("\n", "\\n")
        s = s:gsub("\r", "\\r")
        s = s:gsub("\t", "\\t")
        return '"' .. s .. '"'
    elseif t == "table" then
        local indent     = string.rep("    ", depth + 1)
        local indent_end = string.rep("    ", depth)
        local parts = {}

        -- Array part first (ipairs gives 1-based sequential keys)
        local array_len = 0
        for i = 1, #val do
            if val[i] == nil then break end
            array_len = i
            parts[#parts + 1] = indent .. serialize_val(val[i], depth + 1) .. ","
        end

        -- Hash part (string keys and non-sequential integer keys)
        local keys = {}
        for k in pairs(val) do
            if not (type(k) == "number" and k >= 1 and k <= array_len) then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta == tb then return tostring(a) < tostring(b) end
            return ta < tb
        end)
        for _, k in ipairs(keys) do
            local kstr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                kstr = k
            else
                kstr = "[" .. serialize_val(k, depth + 1) .. "]"
            end
            parts[#parts + 1] = indent .. kstr .. " = " .. serialize_val(val[k], depth + 1) .. ","
        end

        if #parts == 0 then
            return "{}"
        end
        return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent_end .. "}"
    else
        -- functions, userdata, threads — skip
        return "nil"
    end
end

local function serialize_lua(t)
    return "return " .. serialize_val(t, 0) .. "\n"
end

-- ─────────────────────────────────────────────────────────────────────────────

--- Ensure folders exist. Call once on startup.
function ProfileManager.init()
    pcall(core.create_data_folder, "SentinelDuoFarm")
    pcall(core.create_data_folder, PROFILE_DIR)
end

--- Return sorted list of saved profile names (no extension).
function ProfileManager.list()
    local ok, files = pcall(core.read_dir, PROFILE_DIR)
    if not ok or type(files) ~= "table" then return {} end
    local result = {}
    for _, f in ipairs(files) do
        local name = f:match("^(.+)%.lua$")
        if name then result[#result + 1] = name end
    end
    table.sort(result)
    return result
end

--- Load a profile by name. Returns (profile_table, nil) or (nil, err_string).
function ProfileManager.load(name)
    local path = PROFILE_DIR .. "/" .. name .. ".lua"
    local ok, content = pcall(core.read_data_file, path)
    if not ok or not content or content == "" then
        return nil, "not found: " .. path
    end
    local chunk, compile_err = loadstring(content)
    if not chunk then
        return nil, "Lua parse error in " .. path .. ": " .. tostring(compile_err)
    end
    local ok2, data = pcall(chunk)
    if not ok2 or type(data) ~= "table" then
        return nil, "invalid Lua profile in: " .. path
    end
    data._profile_name = name  -- internal tag for save-as
    return data, nil
end

--- Save a profile table under name. Returns true/false.
function ProfileManager.save(name, profile)
    -- Remove internal tracking fields before writing
    local to_save = {}
    for k, v in pairs(profile) do
        if k ~= "_profile_name" and k ~= "_source_name" then
            to_save[k] = v
        end
    end
    local lua_str = serialize_lua(to_save)
    local path = PROFILE_DIR .. "/" .. name .. ".lua"
    pcall(core.create_data_file, path)
    local ok = pcall(core.write_data_file, path, lua_str)
    if not ok then
        helpers.log_err("[ProfileManager] write failed: " .. path)
        return false
    end
    helpers.log("[ProfileManager] saved: " .. name)
    return true
end

--- Delete a profile by name.
function ProfileManager.delete(name)
    local path = PROFILE_DIR .. "/" .. name .. ".lua"
    -- Overwrite with empty string (PS has no delete API)
    pcall(core.write_data_file, path, "")
    helpers.log("[ProfileManager] deleted: " .. name)
end

--- Read the currently active profile name from disk.
function ProfileManager.get_active_name()
    local ok, content = pcall(core.read_data_file, ACTIVE_FILE)
    if ok and content and content ~= "" then
        return content:match("^%s*(.-)%s*$")  -- trim whitespace
    end
    return nil
end

--- Write the active profile name to disk.
function ProfileManager.set_active_name(name)
    pcall(core.create_data_file, ACTIVE_FILE)
    pcall(core.write_data_file,  ACTIVE_FILE, name)
end

--- Deep-copy a profile table for editing (avoids mutating the live profile).
function ProfileManager.deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = ProfileManager.deep_copy(v)
    end
    return copy
end

--- Generate a unique name for a copy. E.g. "stratholme_se" → "stratholme_se_copy".
function ProfileManager.copy_name(base)
    local existing = ProfileManager.list()
    local existing_set = {}
    for _, n in ipairs(existing) do existing_set[n] = true end
    local candidate = base .. "_copy"
    local i = 2
    while existing_set[candidate] do
        candidate = base .. "_" .. i
        i = i + 1
    end
    return candidate
end

return ProfileManager
