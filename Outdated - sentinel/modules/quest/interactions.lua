local Interactions = {}

local function call(name, ...)
    if not core or not core.quests or type(core.quests[name]) ~= "function" then
        return false, nil
    end
    return pcall(core.quests[name], ...)
end

function Interactions.is_open()
    local ok, shown = call("is_gossip_frame_shown")
    return ok and shown == true
end

function Interactions.accept_available(quest_id)
    if not Interactions.is_open() then
        return false
    end
    local ok = call("select_gossip_available_quest", tonumber(quest_id))
    if not ok then
        return false
    end
    return call("accept_quest")
end

function Interactions.complete_active(quest_id, reward_index)
    if not Interactions.is_open() then
        return false
    end
    local ok = call("select_gossip_active_quest", tonumber(quest_id))
    if not ok then
        return false
    end
    ok = call("complete_quest")
    if not ok then
        return false
    end
    if reward_index then
        return call("get_quest_reward", tonumber(reward_index))
    end
    return true
end

function Interactions.close()
    return call("close_gossip")
end

return Interactions
