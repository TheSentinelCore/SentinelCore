local Questie = {}

local function api()
    return core and core.addons and core.addons.questie or nil
end

function Questie.is_ready()
    local addon = api()
    if not addon then return false end
    if type(addon.is_ready) == "function" then
        local ok, ready = pcall(addon.is_ready)
        return ok and ready == true
    end
    return false
end

function Questie.get_active_npc_ids()
    local addon = api()
    if not addon or type(addon.get_quest_npc_ids) ~= "function" then return {} end
    local ok, ids = pcall(addon.get_quest_npc_ids)
    return ok and type(ids) == "table" and ids or {}
end

function Questie.get_quest_ids()
    local addon = api()
    if not addon or type(addon.get_quest_ids) ~= "function" then return {} end
    local ok, ids = pcall(addon.get_quest_ids)
    return ok and type(ids) == "table" and ids or {}
end

function Questie.query_quest(quest_id, key)
    local addon = api()
    if not addon or not Questie.is_ready() or type(addon.query_quest_single) ~= "function" then return nil end
    local ok, value = pcall(addon.query_quest_single, tonumber(quest_id), key)
    return ok and value or nil
end

function Questie.query_npc(npc_id, key)
    local addon = api()
    if not addon or not Questie.is_ready() or type(addon.query_npc_single) ~= "function" then return nil end
    local ok, value = pcall(addon.query_npc_single, tonumber(npc_id), key)
    return ok and value or nil
end

function Questie.is_quest_doable(quest_id)
    local addon = api()
    if not addon or not Questie.is_ready() or type(addon.is_quest_doable) ~= "function" then return nil end
    local ok, value = pcall(addon.is_quest_doable, tonumber(quest_id))
    return ok and value or nil
end

function Questie.is_quest_complete(quest_id)
    local addon = api()
    if not addon or not Questie.is_ready() or type(addon.is_quest_complete) ~= "function" then return nil end
    local ok, value = pcall(addon.is_quest_complete, tonumber(quest_id))
    return ok and value or nil
end

return Questie
