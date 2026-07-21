local RuntimeAction = {}

-- Execute a single action. Returns: "success", "retry", "blocked", "failed", "skipped"
function RuntimeAction.execute(action, ctx)
    local payload = action.payload
    local action_type = action.type

    if action_type == "AcceptQuest" then
        return RuntimeAction.execute_accept_quest(payload, ctx)
    elseif action_type == "TurnInQuest" then
        return RuntimeAction.execute_turnin_quest(payload, ctx)
    elseif action_type == "Travel" then
        return RuntimeAction.execute_travel(payload, ctx)
    elseif action_type == "Kill" then
        return RuntimeAction.execute_kill(payload, ctx)
    elseif action_type == "Vendor" then
        return RuntimeAction.execute_vendor(payload, ctx)
    elseif action_type == "Train" then
        return RuntimeAction.execute_train(payload, ctx)
    elseif action_type == "Flight" then
        return RuntimeAction.execute_flight(payload, ctx)
    elseif action_type == "Hearth" then
        return RuntimeAction.execute_hearth(payload, ctx)
    elseif action_type == "Wait" then
        return RuntimeAction.execute_wait(payload, ctx)
    elseif action_type == "UseItem" then
        return RuntimeAction.execute_use_item(payload, ctx)
    elseif action_type == "Comment" then
        return "success" -- Comments are no-ops
    elseif action_type == "Condition" then
        return RuntimeAction.execute_condition(payload, ctx)
    elseif action_type == "SetVariable" then
        return RuntimeAction.execute_set_variable(payload, ctx)
    elseif action_type == "Repair" then
        return RuntimeAction.execute_repair(payload, ctx)
    elseif action_type == "LearnFlightPath" then
        return RuntimeAction.execute_learn_flight_path(payload, ctx)
    elseif action_type == "Mailbox" then
        return RuntimeAction.execute_mailbox(payload, ctx)
    elseif action_type == "Bank" then
        return RuntimeAction.execute_bank(payload, ctx)
    elseif action_type == "InteractNpc" then
        return RuntimeAction.execute_interact_npc(payload, ctx)
    elseif action_type == "Loot" then
        return RuntimeAction.execute_loot(payload, ctx)
    elseif action_type == "Grind" then
        return RuntimeAction.execute_grind(payload, ctx)
    elseif action_type == "Escort" then
        return RuntimeAction.execute_escort(payload, ctx)
    elseif action_type == "Patrol" then
        return RuntimeAction.execute_patrol(payload, ctx)
    else
        return "failed" -- Unknown action type
    end
end

function RuntimeAction.execute_accept_quest(payload, ctx)
    local quest_id = payload.quest_id
    local npc_entry = payload.npc_entry

    if payload.auto_complete_dialog then
        -- Auto-dialog quest
        return _G.SentinelCore.AutoAcceptQuest(quest_id) and "success" or "retry"
    end

    -- Navigate to NPC and accept
    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    if _G.SentinelCore.SelectQuestEntry(quest_id) then
        return "success"
    end

    return "retry"
end

function RuntimeAction.execute_turnin_quest(payload, ctx)
    local quest_id = payload.quest_id
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    if _G.SentinelCore.HasQuest(quest_id) then
        return _G.SentinelCore.TurnInQuest(quest_id) and "success" or "retry"
    end

    return "success" -- Already completed
end

function RuntimeAction.execute_travel(payload, ctx)
    local dest = payload.destination
    local tolerance = payload.tolerance or 5.0

    if ctx:is_at_destination(dest, tolerance) then
        return "success"
    end

    local nav = _G.SentinelNavClient
    if nav and nav.navigate_to_zone then
        return nav.navigate_to_zone(dest) and "success" or "retry"
    end

    return "blocked" -- Navigation unavailable
end

function RuntimeAction.execute_kill(payload, ctx)
    local entries = payload.creature_entries
    local quantity = payload.quantity

    -- Find and target nearest creature
    local target = _G.ObjectManager:GetNearestCreature(entries)
    if not target or not target:IsValid() then
        return "blocked" -- No targets nearby
    end

    if payload.loot then
        target:Loot()
    end

    if quantity and ctx.kill_count > quantity then
        return "success"
    end

    return "success" -- Trust kill loop to handle timing
end

function RuntimeAction.execute_vendor(payload, ctx)
    local npc_entry = payload.npc_entry
    local sell_grey = payload.sell_grey
    local repair = payload.repair

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    if sell_grey then
        _G.SentinelCore.SellGreys()
    end

    if repair and payload.repair then
        _G.SentinelCore.Repair()
    end

    if payload.buy_items and #payload.buy_items > 0 then
        _G.SentinelCore.BuyItems(payload.buy_items)
    end

    return "success"
end

function RuntimeAction.execute_train(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return _G.SentinelCore.Train() and "success" or "retry"
end

function RuntimeAction.execute_flight(payload, ctx)
    local npc_entry = payload.npc_entry
    local destination = payload.destination

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return _G.SentinelCore.TakeFlight(destination) and "success" or "retry"
end

function RuntimeAction.execute_hearth(payload, ctx)
    return _G.SentinelCore.UseHearthstone() and "success" or "retry"
end

function RuntimeAction.execute_wait(payload, ctx)
    local duration = payload.duration
    if not ctx.wait_start then
        ctx.wait_start = _G.GetTime()
        return "success" -- Start waiting
    end

    if _G.GetTime() - ctx.wait_start >= duration then
        ctx.wait_start = nil
        return "success"
    end

    return "success" -- Still waiting
end

function RuntimeAction.execute_use_item(payload, ctx)
    local item_id = payload.item
    return _G.SentinelCore.UseItem(item_id) and "success" or "retry"
end

function RuntimeAction.execute_condition(payload, ctx)
    local cond = payload.condition

    -- Evaluate condition using Sylvanas APIs
    -- For now, just check if AlwaysTrue
    return "success"
end

function RuntimeAction.execute_set_variable(payload, ctx)
    ctx.variables[payload.name] = payload.value
    return "success"
end

function RuntimeAction.execute_repair(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return _G.SentinelCore.Repair() and "success" or "retry"
end

function RuntimeAction.execute_learn_flight_path(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return _G.SentinelCore.LearnFlightPath() and "success" or "retry"
end

function RuntimeAction.execute_mailbox(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return _G.SentinelCore.OpenMailbox() and "success" or "retry"
end

function RuntimeAction.execute_bank(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return _G.SentinelCore.OpenBank() and "success" or "retry"
end

function RuntimeAction.execute_interact_npc(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return _G.SentinelCore.InteractNpc(npc_entry, payload.gossip) and "success" or "retry"
end

function RuntimeAction.execute_loot(payload, ctx)
    local object_entry = payload.object_entry

    if payload.count then
        -- Loot specific count
        for i = 1, payload.count do
            if not _G.SentinelCore.LootObject(object_entry) then
                return "retry"
            end
        end
    else
        _G.SentinelCore.LootObject(object_entry)
    end

    return "success"
end

function RuntimeAction.execute_grind(payload, ctx)
    -- Navigate to grind area and kill mobs
    return "success" -- Placeholder
end

function RuntimeAction.execute_escort(payload, ctx)
    -- Escort NPC behavior
    return "success" -- Placeholder
end

function RuntimeAction.execute_patrol(payload, ctx)
    -- Patrol waypoints
    return "success" -- Placeholder
end

return RuntimeAction