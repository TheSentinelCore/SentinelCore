-- sentinel/modules/quest/cache/lru_cache.lua
-- Reusable LRU Cache implementation

local LRUCache = {}
LRUCache.__index = LRUCache

function LRUCache.new(maxSize, ttlMs)
    return setmetatable({
        _maxSize = maxSize or 500,
        _ttlMs = ttlMs or 300000,
        _data = {},        -- key -> {value, timestamp}
        _accessOrder = {}, -- most recent first
    }, LRUCache)
end

function LRUCache:_now()
    return os.time() * 1000 -- milliseconds (wall time)
end

function LRUCache:_touch(key)
    -- Move to front (most recent)
    for i, k in ipairs(self._accessOrder) do
        if k == key then
            table.remove(self._accessOrder, i)
            break
        end
    end
    table.insert(self._accessOrder, 1, key)
end

function LRUCache:_evictLRU()
    if #self._accessOrder == 0 then return end
    local lruKey = table.remove(self._accessOrder)
    self._data[lruKey] = nil
end

function LRUCache:_cachePut(key, value)
    if self:_size() >= self._maxSize then
        self:_evictLRU()
    end
    self._data[key] = {value = value, timestamp = self:_now()}
    self:_touch(key)
end

function LRUCache:_cacheGet(key)
    local entry = self._data[key]
    if not entry then return nil end
    if self:_now() - entry.timestamp > self._ttlMs then
        self._data[key] = nil
        -- Remove from access order
        for i, k in ipairs(self._accessOrder) do
            if k == key then
                table.remove(self._accessOrder, i)
                break
            end
        end
        return nil
    end
    self:_touch(key)
    return entry.value
end

function LRUCache:_size()
    local count = 0
    for _ in pairs(self._data) do count = count + 1 end
    return count
end

function LRUCache:get(key)
    return self:_cacheGet(key)
end

function LRUCache:set(key, value)
    self:_cachePut(key, value)
end

function LRUCache:has(key)
    local entry = self._data[key]
    if not entry then return false end
    if os.clock() * 1000 - entry.timestamp > self._ttlMs then
        self._data[key] = nil
        for i, k in ipairs(self._accessOrder) do
            if k == key then
                table.remove(self._accessOrder, i)
                break
            end
        end
        return false
    end
    return true
end

function LRUCache:clear()
    self._data = {}
    self._accessOrder = {}
end

function LRUCache:stats()
    return {
        size = self:_size(),
        maxSize = self._maxSize,
        ttlMs = self._ttlMs,
    }
end

return LRUCache