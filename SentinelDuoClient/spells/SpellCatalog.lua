---@class SpellCatalog
---@field _data table<number, table>
---@field _by_name table<string, table[]>
local SpellCatalog = {}
SpellCatalog.__index = SpellCatalog

--- Create a new SpellCatalog from a spell_data table.
---@param spell_data_table table<number, table>
---@return SpellCatalog
function SpellCatalog:new(spell_data_table)
    local self = setmetatable({}, SpellCatalog)
    self._data = spell_data_table or {}
    self._by_name = {}

    -- Index by name: _by_name[name] = [{id, rank, entry}, ...] sorted by rank ascending
    for id, entry in pairs(self._data) do
        local name = entry.name
        if not self._by_name[name] then
            self._by_name[name] = {}
        end
        table.insert(self._by_name[name], { id = id, rank = entry.rank or 0, entry = entry })
    end

    -- Sort each name's list by rank ascending
    for _, list in pairs(self._by_name) do
        table.sort(list, function(a, b) return a.rank < b.rank end)
    end

    return self
end

--- Resolve the highest learned rank of a spell by name.
---@param spell_name string
---@param player any -- game object (PS API)
---@return number|nil spell_id
function SpellCatalog:resolve(spell_name, player)
    local candidates = self._by_name[spell_name]
    if not candidates then return nil end

    local best_id = nil
    local best_rank = -1

    for _, entry in ipairs(candidates) do
        local ok, has = pcall(function()
            return core.spell_book.has_spell(entry.id)
        end)
        if ok and has and entry.rank > best_rank then
            best_rank = entry.rank
            best_id = entry.id
        end
    end

    return best_id
end

--- Direct lookup by spell ID.
---@param spell_id number
---@return table|nil
function SpellCatalog:resolve_by_id(spell_id)
    return self._data[spell_id]
end

--- Get the mana cost for the highest learned rank of a spell.
---@param spell_name string
---@param player any
---@return number
function SpellCatalog:get_mana_cost(spell_name, player)
    local id = self:resolve(spell_name, player)
    if not id then return 0 end
    local entry = self._data[id]
    return entry and entry.mana_cost or 0
end

--- Get the remaining cooldown in seconds for the highest learned rank.
---@param spell_name string
---@param player any
---@return number seconds remaining (0 if ready)
function SpellCatalog:get_cooldown_remaining(spell_name, player)
    local id = self:resolve(spell_name, player)
    if not id then return 999 end
    local ok, cd = pcall(function()
        return core.spell_book.get_spell_cooldown(id)
    end)
    if ok and type(cd) == "number" then
        return cd
    end
    return 999  -- assume on cooldown on API failure
end

--- Check if a spell is ready to cast.
---@param spell_name string
---@param player any
---@return boolean
function SpellCatalog:is_ready(spell_name, player)
    local id = self:resolve(spell_name, player)
    if not id then return false end

    -- Check cooldown
    local cd = self:get_cooldown_remaining(spell_name, player)
    if cd > 0.1 then return false end

    -- Check GCD
    local ok, gcd = pcall(function()
        return core.spell_book.get_spell_cooldown(61304)  -- Global Cooldown spell ID
    end)
    if ok and type(gcd) == "number" and gcd > 0.1 then return false end

    return true
end

return SpellCatalog
