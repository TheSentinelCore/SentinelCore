---@class SpellbookResolver
local SpellbookResolver = {}
SpellbookResolver.__index = SpellbookResolver

---@private
---@param value string
---@return string
local function normalize(value)
    return tostring(value or ""):lower()
end

---@private
---@param haystack string
---@param needle string
---@return boolean
local function contains(haystack, needle)
    return haystack:find(needle, 1, true) ~= nil
end

---@private
---@param spell_id number
---@return boolean
local function is_spell_learned(spell_id)
    local id = tonumber(spell_id) or 0
    if id <= 0 then
        return false
    end

    if core and core.spell_book and core.spell_book.is_spell_learned then
        local ok, learned = pcall(core.spell_book.is_spell_learned, id)
        if ok and learned == true then
            return true
        end
    end

    if core and core.spell_book and core.spell_book.has_spell then
        local ok, has = pcall(core.spell_book.has_spell, id)
        if ok and has == true then
            return true
        end
    end

    if core and core.spell_book and core.spell_book.get_spells then
        local ok, spells = pcall(core.spell_book.get_spells)
        if ok and type(spells) == "table" then
            if spells[id] ~= nil then
                return true
            end
            for raw_id, raw_name in pairs(spells) do
                local known_id = tonumber(raw_id)
                if type(raw_name) == "table" then
                    known_id = tonumber(raw_name.spell_id or raw_name.id or raw_id)
                end
                if known_id == id then
                    return true
                end
            end
        end
    end

    return false
end

---@return SpellbookResolver
function SpellbookResolver:new()
    local o = setmetatable({}, SpellbookResolver)
    o._last_refresh = -1000
    o._spells = {}
    return o
end

---@private
function SpellbookResolver:_refresh()
    local now = (core and core.time and core.time()) or 0
    local has_cached_spells = type(self._spells) == "table" and next(self._spells) ~= nil
    if has_cached_spells and now - self._last_refresh < 1.0 then
        return
    end
    self._last_refresh = now

    local spells = {}
    if core and core.spell_book and core.spell_book.get_spells then
        local ok, result = pcall(core.spell_book.get_spells)
        if ok and type(result) == "table" then
            spells = result
        end
    end
    self._spells = spells
end

---@param spell_name string
---@param fallback_ids? number[]
---@return number|nil
function SpellbookResolver:best_rank(spell_name, fallback_ids)
    if type(fallback_ids) == "table" and #fallback_ids > 0 then
        -- Fallback lists are authored in rank order (highest -> lowest).
        for i = 1, #fallback_ids do
            local id = tonumber(fallback_ids[i]) or 0
            if is_spell_learned(id) then
                return id
            end
        end
    end

    self:_refresh()
    local wanted = normalize(spell_name)

    local best_id = nil
    local best_rank_idx = nil
    local fallback_rank_idx = {}
    if type(fallback_ids) == "table" then
        for i = 1, #fallback_ids do
            local id = tonumber(fallback_ids[i]) or 0
            if id > 0 then
                fallback_rank_idx[id] = i
            end
        end
    end

    for raw_id, raw_name in pairs(self._spells) do
        local id = tonumber(raw_id)
        local name = normalize(raw_name)

        if type(raw_name) == "table" then
            id = tonumber(raw_name.spell_id or raw_name.id or raw_id)
            name = normalize(raw_name.spell_name or raw_name.name or "")
        end

        if id and id > 0 and name ~= "" and contains(name, wanted) then
            local idx = fallback_rank_idx[id]
            if idx then
                if best_rank_idx == nil or idx < best_rank_idx then
                    best_rank_idx = idx
                    best_id = id
                end
            elseif best_rank_idx == nil and (best_id == nil or id > best_id) then
                best_id = id
            end
        end
    end

    if best_id ~= nil then
        return best_id
    end

    if type(fallback_ids) == "table" and #fallback_ids > 0 then
        -- Lowest rank is the safest fallback when runtime rank detection is uncertain.
        return tonumber(fallback_ids[#fallback_ids])
    end

    return nil
end

return SpellbookResolver
