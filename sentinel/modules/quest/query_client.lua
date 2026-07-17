local JSON = require("lib/JSON")

local QueryClient = {}
QueryClient.__index = QueryClient

local QUEST_CACHE = {}
local NPC_CACHE = {}
local ITEM_CACHE = {}
local QUEST_SEARCH_CACHE = {}
local NPC_SEARCH_CACHE = {}
local ITEM_SEARCH_CACHE = {}
local CACHE_TTL_S = 300  -- 5 minutes in seconds

function QueryClient.new(blackboard)
    local o = setmetatable({}, QueryClient)
    o._blackboard = blackboard
    o._base_url = "http://127.0.0.1:8081"
    o._npc_cache = {}
    o._pending_requests = {}  -- Track in-flight HTTP requests
    return o
end

local function is_cache_valid(timestamp)
    local now = core and core.time and core.time() or 0
    return (now - timestamp) < CACHE_TTL_S
end

local function cache_get(cache, key)
    local entry = cache[key]
    if entry and is_cache_valid(entry.timestamp) then
        return entry.data
    end
    return nil
end

local function cache_set(cache, key, data)
    cache[key] = {
        data = data,
        timestamp = core and core.time and core.time() or 0,
    }
end

---Fetch quest data from the query server (async).
---First call fires the HTTP request and returns nil.
---Subsequent calls return cached data once the callback has fired.
---In-flight requests are deduplicated to prevent spamming the server.
---@param quest_id integer
---@return table|nil
function QueryClient:fetch_quest(quest_id)
    quest_id = tonumber(quest_id)
    if not quest_id or not core or not core.http_get then
        return nil
    end

    -- Check cache first
    local cached = QuestCache[quest_id]
    if cached then
        return cached
    end

    -- Check if request is already in-flight (deduplication)
    if self._pending_requests[quest_id] then
        return nil
    end
    self._pending_requests[quest_id] = true

    -- Fire async request — callback caches the parsed result
    local url = self._base_url .. "/api/v1/quests/" .. quest_id
    pcall(function()
        core.http_get(url, function(code, content_type, body)
            -- Clear in-flight flag on callback
            self._pending_requests[quest_id] = nil
            
            if code == 200 and body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" then
                    QuestCache[quest_id] = data
                end
            end
        end)
    end)

    -- Data not ready yet — will be available on next poll
    return nil
end

---Fetch quest NPC relations from the query server (async).
---First call fires the HTTP request and returns nil.
---Subsequent calls return cached data once the callback has fired.
---In-flight requests are deduplicated to prevent spamming the server.
---@param quest_id integer
---@param relation string|nil "giver" | "turnin"
---@return table|nil
function QueryClient:fetch_quest_npcs(quest_id, relation)
    quest_id = tonumber(quest_id)
    if not quest_id or not core or not core.http_get then
        return nil
    end

    local cache_key = quest_id .. ":" .. (relation or "all")

    -- Check cache
    local cached = self._npc_cache[cache_key]
    if cached then
        return cached
    end

    -- Check if request is already in-flight (deduplication)
    if self._pending_requests[cache_key] then
        return nil
    end
    self._pending_requests[cache_key] = true

    -- Fire async request — callback caches the parsed result
    local url = self._base_url .. "/api/v1/quests/" .. quest_id .. "/npcs"
    if relation then
        url = url .. "?relation=" .. relation
    end

    pcall(function()
        core.http_get(url, function(code, content_type, body)
            -- Clear in-flight flag on callback
            self._pending_requests[cache_key] = nil
            
            if code == 200 and body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" then
                    self._npc_cache[cache_key] = data
                end
            end
        end)
    end)

    -- Data not ready yet — will be available on next poll
    return nil
end

--- Request a path from NavServer using a routing policy
---@param start table {x, y, z, map_id}
---@param goal table {x, y, z, map_id}
---@param policy table Routing policy object
---@return table|nil Waypoints or nil if pending
function QueryClient:plan_path(start, goal, policy)
    if not core or not core.http_post then
        return nil
    end

    local url = self._base_url .. "/nav/plan_path"
    local body = {
        start = start,
        goal = goal,
        policy = policy,
    }

    local result = nil
    pcall(function()
        core.http_post(url, JSON.encode(body), function(code, content_type, body)
            if code == 200 and body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" then
                    result = data
                end
            end
        end)
    end)

    return result
end

---Search for quests matching criteria.
---@param criteria table {name?: string, min_level?: number, max_level?: number, zone_id?: number, faction?: string}
---@return table|nil
function QueryClient:search_quests(criteria)
    if not core or not core.http_get then
        return nil
    end

    -- Build cache key from criteria
    local key = JSON:encode(criteria)
    local cached = QUEST_SEARCH_CACHE[key]
    if cached and is_cache_valid(cached.timestamp) then
        return cached.data
    end

    -- Build query string from criteria
    local query_parts = {}
    if criteria.name then
        table.insert(query_parts, "name=" .. core.net_url_encode(criteria.name))
    end
    if criteria.min_level then
        table.insert(query_parts, "min_level=" .. criteria.min_level)
    end
    if criteria.max_level then
        table.insert(query_parts, "max_level=" .. criteria.max_level)
    end
    if criteria.zone_id then
        table.insert(query_parts, "zone_id=" .. criteria.zone_id)
    end
    if criteria.faction then
        table.insert(query_parts, "faction=" .. core.net_url_encode(criteria.faction))
    end

    local query = table.concat(query_parts, "&")
    if query == "" then
        query = "limit=20"  -- Default limit if no criteria
    else
        query = query .. "&limit=20"
    end

    -- Check if request is already in-flight (deduplication)
    if self._pending_requests["search_quests_" .. key] then
        return nil
    end
    self._pending_requests["search_quests_" .. key] = true

    -- Fire async request
    local url = self._base_url .. "/api/v1/quests/search?" .. query
    pcall(function()
        core.http_get(url, function(code, content_type, body)
            -- Clear in-flight flag on callback
            self._pending_requests["search_quests_" .. key] = nil
            
            if code == 200 and body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" then
                    QUEST_SEARCH_CACHE[key] = {
                        data = data,
                        timestamp = core and core.time and core.time() or 0,
                    }
                end
            end
        end)
    end)

    -- Data not ready yet — will be available on next poll
    return nil
end

---Search for NPCs matching criteria.
---@param criteria table {name?: string, zone_id?: number, faction?: string}
---@return table|nil
function QueryClient:search_npcs(criteria)
    if not core or not core.http_get then
        return nil
    end

    -- Build cache key from criteria
    local key = JSON:encode(criteria)
    local cached = NPC_SEARCH_CACHE[key]
    if cached and is_cache_valid(cached.timestamp) then
        return cached.data
    end

    -- Build query string from criteria
    local query_parts = {}
    if criteria.name then
        table.insert(query_parts, "name=" .. core.net_url_encode(criteria.name))
    end
    if criteria.zone_id then
        table.insert(query_parts, "zone_id=" .. criteria.zone_id)
    end
    if criteria.faction then
        table.insert(query_parts, "faction=" .. core.net_url_encode(criteria.faction))
    end

    local query = table.concat(query_parts, "&")
    if query == "" then
        query = "limit=20"  -- Default limit if no criteria
    else
        query = query .. "&limit=20"
    end

    -- Check if request is already in-flight (deduplication)
    if self._pending_requests["search_npcs_" .. key] then
        return nil
    end
    self._pending_requests["search_npcs_" .. key] = true

    -- Fire async request
    local url = self._base_url .. "/api/v1/npcs/search?" .. query
    pcall(function()
        core.http_get(url, function(code, content_type, body)
            -- Clear in-flight flag on callback
            self._pending_requests["search_npcs_" .. key] = nil
            
            if code == 200 and body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" then
                    NPC_SEARCH_CACHE[key] = {
                        data = data,
                        timestamp = core and core.time and core.time() or 0,
                    }
                end
            end
        end)
    end)

    -- Data not ready yet — will be available on next poll
    return nil
end

---Search for items matching criteria.
---@param criteria table {name?: string, quality?: number, class?: string, subclass?: string}
---@return table|nil
function QueryClient:search_items(criteria)
    if not core or not core.http_get then
        return nil
    end

    -- Build cache key from criteria
    local key = JSON:encode(criteria)
    local cached = ITEM_SEARCH_CACHE[key]
    if cached and is_cache_valid(cached.timestamp) then
        return cached.data
    end

    -- Build query string from criteria
    local query_parts = {}
    if criteria.name then
        table.insert(query_parts, "name=" .. core.net_url_encode(criteria.name))
    end
    if criteria.quality then
        table.insert(query_parts, "quality=" .. criteria.quality)
    end
    if criteria.class then
        table.insert(query_parts, "class=" .. core.net_url_encode(criteria.class))
    end
    if criteria.subclass then
        table.insert(query_parts, "subclass=" .. core.net_url_encode(criteria.subclass))
    end

    local query = table.concat(query_parts, "&")
    if query == "" then
        query = "limit=20"  -- Default limit if no criteria
    else
        query = query .. "&limit=20"
    end

    -- Check if request is already in-flight (deduplication)
    if self._pending_requests["search_items_" .. key] then
        return nil
    end
    self._pending_requests["search_items_" .. key] = true

    -- Fire async request
    local url = self._base_url .. "/api/v1/items/search?" .. query
    pcall(function()
        core.http_get(url, function(code, content_type, body)
            -- Clear in-flight flag on callback
            self._pending_requests["search_items_" .. key] = nil
            
            if code == 200 and body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" then
                    ITEM_SEARCH_CACHE[key] = {
                        data = data,
                        timestamp = core and core.time and core.time() or 0,
                    }
                end
            end
        end)
    end)

    -- Data not ready yet — will be available on next poll
    return nil
end

---Get detailed quest information including prerequisites, objectives, rewards.
---Enhanced version of fetch_quest with additional data.
---@param quest_id integer
---@return table|nil
function QueryClient:get_quest_details(quest_id)
    -- This is essentially the same as fetch_quest but with a different name
    -- to indicate it returns detailed information
    return self:fetch_quest(quest_id)
end

---Get detailed NPC information including location, quests offered, services.
---@param npc_id integer
---@return table|nil
function QueryClient:get_npc_details(npc_id)
    if not core or not core.http_get then
        return nil
    end

    -- Check cache first
    local cached = NPC_CACHE[npc_id]
    if cached then
        return cached
    end

    -- Check if request is already in-flight (deduplication)
    if self._pending_requests[npc_id] then
        return nil
    end
    self._pending_requests[npc_id] = true

    -- Fire async request — callback caches the parsed result
    local url = self._base_url .. "/api/v1/npcs/" .. npc_id
    pcall(function()
        core.http_get(url, function(code, content_type, body)
            -- Clear in-flight flag on callback
            self._pending_requests[npc_id] = nil
            
            if code == 200 and body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" then
                    NPC_CACHE[npc_id] = data
                end
            end
        end)
    end)

    -- Data not ready yet — will be available on next poll
    return nil
end

return QueryClient
