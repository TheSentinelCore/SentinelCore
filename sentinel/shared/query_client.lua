--- Sentinel Query Client
--- HTTP client for QueryServer (port 3030)
--- Communicates with the SentinelQueryServer Rust backend to resolve NPCs, quests, vendors

local QueryClient = {}
QueryClient.__index = QueryClient

-- The Sylvannas sandbox has NO global `JSON` — relying on it meant every in-game query
-- silently returned nil (the same bug runtime_profile.lua had with profile parsing).
-- Prefer the shipped pure-Lua parser; fall back to an injected global only for harnesses
-- that supply one.
local JsonLib = (function()
    local ok, mod = pcall(require, "core/JSON")
    if ok and type(mod) == "table" and mod.decode then
        return mod
    end
    return nil
end)()

local function json_decode(str)
    if type(str) ~= "string" then return nil end
    if JsonLib then
        local ok, value = pcall(JsonLib.decode, str)
        if ok then return value end
        return nil
    end
    if JSON and JSON.parse then
        local ok, value = pcall(JSON.parse, str)
        if ok then return value end
    end
    return nil
end

function QueryClient:new(host, port)
    local o = setmetatable({}, QueryClient)
    o._host = host or "127.0.0.1"
    o._port = port or 3030
    return o
end

function QueryClient:_url(path)
    return string.format("http://%s:%d%s", self._host, self._port, path)
end

function QueryClient:_get(path)
    local full_url = self:_url(path)
    if core and core.http_get then
        local response = core.http_get(full_url)
        if response then
            local decoded = json_decode(response)
            if decoded then return decoded end
        end
    end
    return nil
end

function QueryClient:search_quests(query)
    return self:_get("/quests/search?q=" .. tostring(query))
end

function QueryClient:get_quest(quest_id)
    return self:_get("/quest/" .. tostring(quest_id))
end

function QueryClient:search_npcs(query)
    return self:_get("/npc/search?q=" .. tostring(query))
end

function QueryClient:get_npc(entry)
    return self:_get("/npc/" .. tostring(entry))
end

function QueryClient:get_vendor(entry)
    return self:_get("/vendor/" .. tostring(entry))
end

function QueryClient:get_trainer(entry)
    return self:_get("/trainer/" .. tostring(entry))
end

function QueryClient:get_flight(entry)
    return self:_get("/flight/" .. tostring(entry))
end

function QueryClient:get_object(entry)
    return self:_get("/object/" .. tostring(entry))
end

--- Static item facts (name, quality, sell_price). The live SDK has no item-quality API,
--- so grey detection for vendor selling rides on this endpoint.
function QueryClient:get_item(entry)
    return self:_get("/item/" .. tostring(entry))
end

function QueryClient:creatures_in_polygon(polygon)
    return self:_get("/creatures/polygon?polygon=" .. tostring(polygon))
end

return QueryClient