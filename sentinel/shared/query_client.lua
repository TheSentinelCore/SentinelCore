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

-- Negative-cache sentinel: a resolved 404/parse failure returns nil FAST forever after,
-- instead of re-requesting every tick.
local NOT_FOUND = "__not_found__"

function QueryClient:new(host, port)
    local o = setmetatable({}, QueryClient)
    o._host = host or "127.0.0.1"
    o._port = port or 3030
    o._cache = {}
    o._inflight = {}
    return o
end

function QueryClient:_url(path)
    return string.format("http://%s:%d%s", self._host, self._port, path)
end

--- Request-and-cache fetch. The LIVE core.http_get is ASYNC — `(url, callback)`, with the
--- one-argument synchronous form raising "function expected" (verified in-game
--- 2026-07-23; the old sync call meant QueryClient never returned data in-game at all).
--- First call fires the request and usually returns (nil, true) = pending; callers poll
--- again next tick — which is exactly the executor's retry/waiting model. Offline
--- harnesses with synchronous mocks (either signature) resolve immediately.
--- @return table|nil result, boolean|nil pending
function QueryClient:_get(path)
    if not (core and core.http_get) then return nil end
    self._cache = self._cache or {}
    self._inflight = self._inflight or {}

    local cached = self._cache[path]
    if cached ~= nil then
        if cached == NOT_FOUND then return nil end
        return cached
    end
    if self._inflight[path] then
        return nil, true
    end

    local url = self:_url(path)
    local client = self
    self._inflight[path] = true
    local ok, sync_body = pcall(core.http_get, url, function(http_code, _content_type, body)
        client._inflight[path] = nil
        if http_code == 200 and type(body) == "string" then
            local decoded = json_decode(body)
            client._cache[path] = decoded ~= nil and decoded or NOT_FOUND
        else
            client._cache[path] = NOT_FOUND
        end
    end)

    if not ok then
        -- Legacy offline mock with the old single-argument synchronous signature.
        self._inflight[path] = nil
        local ok2, resp = pcall(core.http_get, url)
        if ok2 and type(resp) == "string" then
            local decoded = json_decode(resp)
            self._cache[path] = decoded ~= nil and decoded or NOT_FOUND
            if decoded then return decoded end
        end
        return nil
    end

    -- Synchronous mock that accepted (url, callback) but returned the body directly.
    if type(sync_body) == "string" then
        self._inflight[path] = nil
        local decoded = json_decode(sync_body)
        if decoded then
            self._cache[path] = decoded
            return decoded
        end
    end

    -- The live client may have run the callback before http_get returned; honor it.
    cached = self._cache[path]
    if cached ~= nil then
        if cached == NOT_FOUND then return nil end
        return cached
    end
    return nil, true
end

-- Declared even though `/resolve` reads the body as raw bytes: a POST that announces nothing is one
-- a proxy, or a future strict handler, is entitled to reject — and that rejection would arrive as an
-- opaque 400 the operator would spend the evening blaming their recording for.
local JSON_HEADERS = { ["Content-Type"] = "application/json" }

--- One-shot POST, answered through `on_complete(http_code, body)`.
---
--- NOT cached the way `_get` is: a POST's answer depends on the body it carried, so a path-keyed
--- cache would hand the second recording the first one's plan.
---
--- `core.http_post` is ASYNCHRONOUS — `(url, [headers,] body, callback)`, returning before the
--- server has answered (docs/SylvannasAPI/dev/api/core.md). There is no synchronous form, and
--- waiting for one inside a tick would stall the game client, so this returns as soon as the
--- request is dispatched and the CALLER owns the wait. `http_code` is 0 on transport failure, which
--- is the only way to tell "QueryServer is not running" from "QueryServer said no".
---
--- The headers form is tried first and the three-argument form is the fallback. This is not
--- defensive padding: `_get` above records that the live `core.http_get` raises "function expected"
--- on the signature this tree assumed, and that failure was invisible offline for months.
--- @return string|nil "dispatched", or nil plus the reason the request never left
function QueryClient:post(path, body, on_complete)
    if not (core and core.http_post) then
        return nil, "core.http_post is unavailable in this sandbox"
    end
    if type(body) ~= "string" or body == "" then
        return nil, "refusing to POST an empty body"
    end
    if type(on_complete) ~= "function" then
        return nil, "a POST with no completion handler discards the server's answer"
    end

    local url = self:_url(path)
    local delivered = false
    local function deliver(http_code, _content_type, response)
        -- A transport that both invokes the callback and returns the body would otherwise answer
        -- twice, and the second answer would overwrite a good result with a guessed one.
        if delivered then return end
        delivered = true
        on_complete(tonumber(http_code) or 0, type(response) == "string" and response or nil)
    end

    local ok, sync_body = pcall(core.http_post, url, JSON_HEADERS, body, deliver)
    if not ok then
        local ok3, sync3 = pcall(core.http_post, url, body, deliver)
        if not ok3 then
            return nil, "core.http_post rejected the request: " .. tostring(sync3)
        end
        sync_body = sync3
    end

    -- Legacy offline mocks return the body straight from the call instead of invoking the callback.
    -- Nothing in the live client does this, which is why the status is assumed rather than read.
    if type(sync_body) == "string" and not delivered then
        deliver(200, nil, sync_body)
    end

    return "dispatched"
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

function QueryClient:get_quest_chain(quest_id)
    return self:_get("/quest/" .. tostring(quest_id) .. "/chain")
end

function QueryClient:get_quest_objectives(quest_id)
    return self:_get("/quest/" .. tostring(quest_id) .. "/objectives")
end

return QueryClient