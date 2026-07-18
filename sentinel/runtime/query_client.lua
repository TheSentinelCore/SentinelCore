-- sentinel/runtime/query_client.lua
-- Async HTTP client for the QueryServer
-- Wraps core.http_get (callback-based) with caching and request deduplication

local JSON = require("lib/JSON")

local QueryClient = {}
QueryClient.__index = QueryClient

-- Default configuration
local DEFAULT_BASE_URL = "http://127.0.0.1:3000"
local DEFAULT_CACHE_TTL_S = 300 -- 5 minutes

---Create a new QueryClient
---@param opts table|nil Optional config: { base_url, cache_ttl_s }
---@return table QueryClient instance
function QueryClient.new(opts)
    opts = opts or {}
    local o = setmetatable({}, QueryClient)
    o._base_url = opts.base_url or DEFAULT_BASE_URL
    o._cache_ttl_s = opts.cache_ttl_s or DEFAULT_CACHE_TTL_S
    o._cache = {}            -- key → { data, timestamp }
    o._pending = {}          -- key → { callbacks } for in-flight dedup
    o._request_count = 0     -- total requests fired
    o._cache_hits = 0        -- total cache hits
    return o
end

-- ============================================================================
-- Configuration
-- ============================================================================

---Set the server base URL
---@param url string
function QueryClient:set_base_url(url)
    self._base_url = url
end

---Get the server base URL
---@return string
function QueryClient:get_base_url()
    return self._base_url
end

---Set the cache TTL in seconds
---@param ttl_s number
function QueryClient:set_cache_ttl(ttl_s)
    self._cache_ttl_s = ttl_s
end

-- ============================================================================
-- Internal helpers
-- ============================================================================

local function current_time_ms()
    if core and core.game_time then
        return core.game_time()
    end
    return 0
end

---Build full URL from path
---@param path string
---@return string
function QueryClient:_build_url(path)
    return self._base_url .. path
end

---Check if a cache entry is still valid
---@param entry table
---@return boolean
function QueryClient:_is_cache_valid(entry)
    if not entry then return false end
    local now_ms = current_time_ms()
    return (now_ms - entry.timestamp) < (self._cache_ttl_s * 1000)
end

---Get from cache if valid
---@param key string
---@return table|nil data
function QueryClient:_cache_get(key)
    local entry = self._cache[key]
    if self:_is_cache_valid(entry) then
        self._cache_hits = self._cache_hits + 1
        return entry.data
    end
    if entry then
        self._cache[key] = nil -- expired
    end
    return nil
end

---Set cache entry
---@param key string
---@param data table
function QueryClient:_cache_set(key, data)
    self._cache[key] = {
        data = data,
        timestamp = current_time_ms(),
    }
end

---Parse JSON response body
---@param body string|nil
---@return table|nil data
---@return string|nil error
function QueryClient:_parse_json(body)
    if not body or body == "" then
        return nil, "empty response body"
    end
    local data, err = JSON.decode(body)
    if err then
        return nil, "JSON decode error: " .. tostring(err)
    end
    return data, nil
end

---Make an HTTP GET request with in-flight deduplication.
---If a request for the same key is already in-flight, the callback
---is queued and will be called when the first request completes.
---@param key string Cache/dedup key
---@param path string URL path (appended to base_url)
---@param callback function(data, err)
function QueryClient:_get(key, path, callback)
    -- 1. Check cache
    local cached = self:_cache_get(key)
    if cached then
        if callback then
            callback(cached, nil)
        end
        return
    end

    -- 2. Dedup in-flight requests
    if self._pending[key] then
        table.insert(self._pending[key], callback)
        return
    end

    -- 3. Fire request
    self._pending[key] = { callback }
    self._request_count = self._request_count + 1
    local url = self:_build_url(path)

    if not core or not core.http_get then
        -- No HTTP available (test environment without mock) — fail all
        local pending_cbs = self._pending[key]
        self._pending[key] = nil
        for _, cb in ipairs(pending_cbs) do
            if cb then cb(nil, "core.http_get not available") end
        end
        return
    end

    core.http_get(url, function(http_code, content_type, response_data, response_headers)
        -- Collect all waiting callbacks
        local pending_cbs = self._pending[key]
        self._pending[key] = nil

        if http_code ~= 200 then
            local err_msg = "HTTP " .. tostring(http_code) .. " for " .. path
            for _, cb in ipairs(pending_cbs) do
                if cb then cb(nil, err_msg) end
            end
            return
        end

        local data, parse_err = self:_parse_json(response_data)
        if parse_err then
            for _, cb in ipairs(pending_cbs) do
                if cb then cb(nil, parse_err) end
            end
            return
        end

        -- Cache and return to all waiters
        self:_cache_set(key, data)
        for _, cb in ipairs(pending_cbs) do
            if cb then cb(data, nil) end
        end
    end)
end

-- ============================================================================
-- Public API: Health Check
-- ============================================================================

---Check QueryServer health
---@param callback function(data, err)
function QueryClient:health(callback)
    self:_get("health", "/health", callback)
end

-- ============================================================================
-- Public API: Quest Endpoints
-- ============================================================================

---Search quests by query string
---@param query string
---@param callback function(data, err)
function QueryClient:search_quests(query, callback)
    local key = "quests:search:" .. query
    local path = "/api/v1/quests/search?query=" .. self:_encode_uri(query)
    self:_get(key, path, callback)
end

---Get quest by ID
---@param quest_id integer
---@param callback function(data, err)
function QueryClient:get_quest(quest_id, callback)
    quest_id = tonumber(quest_id)
    if not quest_id then
        if callback then callback(nil, "invalid quest_id") end
        return
    end
    local key = "quests:" .. quest_id
    local path = "/api/v1/quests/" .. quest_id
    self:_get(key, path, callback)
end

-- ============================================================================
-- Public API: NPC Endpoints
-- ============================================================================

---Search NPCs by query string
---@param query string
---@param callback function(data, err)
function QueryClient:search_npcs(query, callback)
    local key = "npcs:search:" .. query
    local path = "/api/v1/npcs/search?query=" .. self:_encode_uri(query)
    self:_get(key, path, callback)
end

---Get NPC by entry
---@param entry integer
---@param callback function(data, err)
function QueryClient:get_npc(entry, callback)
    entry = tonumber(entry)
    if not entry then
        if callback then callback(nil, "invalid npc entry") end
        return
    end
    local key = "npcs:" .. entry
    local path = "/api/v1/npcs/" .. entry
    self:_get(key, path, callback)
end

-- ============================================================================
-- Public API: Creature Endpoints
-- ============================================================================

---Get creature by entry
---@param entry integer
---@param callback function(data, err)
function QueryClient:get_creature(entry, callback)
    entry = tonumber(entry)
    if not entry then
        if callback then callback(nil, "invalid creature entry") end
        return
    end
    local key = "creatures:" .. entry
    local path = "/api/v1/creatures/" .. entry
    self:_get(key, path, callback)
end

-- ============================================================================
-- Public API: Route Endpoints
-- ============================================================================

---Get route between two points (not cached — always fresh)
---@param from_map integer
---@param from_x number
---@param from_y number
---@param to_map integer
---@param to_x number
---@param to_y number
---@param callback function(data, err)
function QueryClient:get_route(from_map, from_x, from_y, to_map, to_x, to_y, callback)
    local path = string.format(
        "/api/v1/route?from_map=%d&from_x=%.1f&from_y=%.1f&to_map=%d&to_x=%.1f&to_y=%.1f",
        from_map, from_x, from_y, to_map, to_x, to_y
    )
    -- Route is not cached — use a unique key per request
    local key = "route:" .. tostring(from_map) .. ":" .. tostring(from_x) .. ":" .. tostring(from_y) ..
                ":" .. tostring(to_map) .. ":" .. tostring(to_x) .. ":" .. tostring(to_y)
    self:_get(key, path, callback)
end

-- ============================================================================
-- Cache Management
-- ============================================================================

---Invalidate all cached data
function QueryClient:invalidate_cache()
    self._cache = {}
end

---Invalidate specific cache key pattern
---@param pattern string Lua pattern to match cache keys
function QueryClient:invalidate_matching(pattern)
    local to_remove = {}
    for key in pairs(self._cache) do
        if key:find(pattern) then
            table.insert(to_remove, key)
        end
    end
    for _, key in ipairs(to_remove) do
        self._cache[key] = nil
    end
end

---Get cache statistics
---@return table { entries, ttl_s, request_count, cache_hits }
function QueryClient:get_stats()
    local count = 0
    for _ in pairs(self._cache) do count = count + 1 end
    return {
        entries = count,
        ttl_s = self._cache_ttl_s,
        request_count = self._request_count,
        cache_hits = self._cache_hits,
    }
end

-- ============================================================================
-- URL Encoding
-- ============================================================================

---Percent-encode a string for use in URL query parameters
---@param str string
---@return string
function QueryClient:_encode_uri(str)
    if str == nil then return "" end
    str = tostring(str)
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w _%%%-%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = str:gsub(" ", "+")
    return str
end

return QueryClient
