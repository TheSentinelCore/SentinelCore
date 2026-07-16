local QueryClient = {}
QueryClient.__index = QueryClient

local QUEST_CACHE = {}
local CACHE_TTL_S = 300  -- 5 minutes in seconds

function QueryClient.new(blackboard)
    local o = setmetatable({}, QueryClient)
    o._blackboard = blackboard
    o._base_url = "http://127.0.0.1:8081"
    return o
end

function QueryClient.get_cached_quest(quest_id)
    local entry = QUEST_CACHE[quest_id]
    if not entry then
        return nil
    end
    local now = core and core.time and core.time() or 0
    if now - entry.timestamp > CACHE_TTL_S then
        QUEST_CACHE[quest_id] = nil
        return nil
    end
    return entry.data
end

function QueryClient.cache_quest(quest_id, data)
    QUEST_CACHE[quest_id] = {
        data = data,
        timestamp = core and core.time and core.time() or 0,
    }
end

function QueryClient:fetch_quest(quest_id)
    quest_id = tonumber(quest_id)
    if not quest_id or not core or not core.http_get then
        return nil
    end
    
    local url = self._base_url .. "/api/v1/quests/" .. quest_id
    local cached = QueryClient.get_cached_quest(quest_id)
    if cached then
        return cached
    end
    
    local response = nil
    local ok, err = pcall(function()
        response = core.http_get(url, function(code, content_type, body)
            if code == 200 and body then
                return body
            end
        end)
    end)
    
    if not ok or not response then
        return nil
    end
    
    -- Cache successful responses
    QueryClient.cache_quest(quest_id, response)
    return response
end

function QueryClient:fetch_quest_npcs(quest_id, relation)
    quest_id = tonumber(quest_id)
    if not quest_id or not core or not core.http_get then
        return nil
    end
    
    local url = self._base_url .. "/api/v1/quests/" .. quest_id .. "/npcs"
    if relation then
        url = url .. "?relation=" .. relation
    end
    
    local response = nil
    pcall(function()
        response = core.http_get(url, function(code, content_type, body)
            if code == 200 and body then
                return body
            end
        end)
    end)
    
    return response
end

return QueryClient