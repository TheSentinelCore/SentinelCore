---@class RotationRankPolicy
local RankPolicy = {}

---@private
---@param id any
---@return number
local function spell_id(id)
    return tonumber(id) or 0
end

---@private
---@param id number
---@return boolean
local function is_learned(id)
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

    return false
end

---@private
---@param ids number[]|nil
---@return number|nil
local function first_learned(ids)
    if type(ids) ~= "table" then
        return nil
    end

    for i = 1, #ids do
        local id = spell_id(ids[i])
        if is_learned(id) then
            return id
        end
    end

    return nil
end

---@param ctx table
---@param spell_name string
---@param fallback_ids number[]|nil
---@return number|nil
function RankPolicy.select_max_rank(ctx, spell_name, fallback_ids)
    if ctx and type(ctx.resolve_spell_id) == "function" and type(spell_name) == "string" then
        local resolved = spell_id(ctx.resolve_spell_id(spell_name, fallback_ids))
        if resolved > 0 then
            return resolved
        end
    end

    local learned = first_learned(fallback_ids)
    if learned then
        return learned
    end

    if type(fallback_ids) == "table" and #fallback_ids > 0 then
        local id = spell_id(fallback_ids[1])
        if id > 0 then
            return id
        end
    end

    return nil
end

---@param fallback_ids number[]|nil
---@param preferred_rank_ids number[]|nil
---@return number|nil
function RankPolicy.select_downrank(fallback_ids, preferred_rank_ids)
    local preferred = first_learned(preferred_rank_ids)
    if preferred then
        return preferred
    end

    return first_learned(fallback_ids)
end

---@param ctx table
---@param policy table
---@return number|nil
function RankPolicy.select_by_mana_policy(ctx, policy)
    policy = policy or {}

    local spell_name = tostring(policy.spell_name or "")
    if spell_name == "" then
        return nil
    end

    local fallback_ids = policy.fallback_ids
    local high_rank = RankPolicy.select_max_rank(ctx, spell_name, fallback_ids)
    local low_rank = RankPolicy.select_downrank(fallback_ids, policy.low_mana_rank_ids)

    local mana = tonumber(ctx and ctx.player_mana_pct)
    local low_threshold = tonumber(policy.low_mana_threshold) or 0.20
    local critical_threshold = tonumber(policy.critical_mana_threshold) or 0.08

    if mana == nil then
        return high_rank or low_rank
    end

    if mana <= critical_threshold then
        return low_rank or high_rank
    end

    if mana <= low_threshold then
        return low_rank or high_rank
    end

    return high_rank or low_rank
end

return RankPolicy
