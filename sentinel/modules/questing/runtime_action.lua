--- Sentinel Runtime Action Executor
--- Executes RuntimeAction types defined in RuntimeProfile
--- Returns: "success", "retry", "blocked", "failed", "skipped"

local RuntimeAction = {}

-- Execute a single action
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
        return _G.SentinelCore and _G.SentinelCore.AutoAcceptQuest(quest_id) and "success" or "retry"
    end

    -- Navigate to NPC and accept
    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    if _G.SentinelCore and _G.SentinelCore.SelectQuestEntry then
        return _G.SentinelCore.SelectQuestEntry(quest_id) and "success" or "retry"
    end
    return "retry"
end

function RuntimeAction.execute_turnin_quest(payload, ctx)
    local quest_id = payload.quest_id
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    if _G.SentinelCore and _G.SentinelCore.HasQuest then
        if _G.SentinelCore.HasQuest(quest_id) then
            return _G.SentinelCore.TurnInQuest and _G.SentinelCore.TurnInQuest(quest_id) and "success" or "retry"
        end
    end
    return "success" -- Already completed or no API
end

function RuntimeAction.execute_travel(payload, ctx)
    local dest = payload.destination
    local tolerance = payload.tolerance or 5.0

    if ctx:is_at_destination(dest, tolerance) then
        return "success"
    end

    if _G.SentinelNavClient and _G.SentinelNavClient.navigate_to_zone then
        return _G.SentinelNavClient.navigate_to_zone(dest) and "success" or "retry"
    end

    if core and core.input and core.input.move then
        -- Fallback: use zone name as waypoint if available
        local zone_info = ctx:get_zone_waypoint(dest)
        if zone_info then
            core.input.move(zone_info.x, zone_info.y, zone_info.z)
            return "success"
        end
    end

    return "blocked" -- Navigation unavailable
end

function RuntimeAction.execute_kill(payload, ctx)
    local entries = payload.creature_entries or {}
    local quantity = payload.quantity

    -- Find and target nearest creature
    if core and core.object_manager and core.object_manager.GetNearestCreature then
        local target = core.object_manager.GetNearestCreature(entries)
        if target and target.IsValid then
            if target:IsDead() then
                return "success"
            end
            return "success" -- Trust kill loop to handle timing
        end
    end
    return "blocked" -- No targets nearby or no API
end

function RuntimeAction.execute_vendor(payload, ctx)
    local npc_entry = payload.npc_entry
    local sell_grey = payload.sell_grey
    local repair = payload.repair

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    if _G.SentinelCore then
        if sell_grey and _G.SentinelCore.SellGreys then
            _G.SentinelCore.SellGreys()
        end
        if repair and _G.SentinelCore.Repair then
            _G.SentinelCore.Repair()
        end
        if payload.buy_items and _G.SentinelCore.BuyItems then
            _G.SentinelCore.BuyItems(payload.buy_items)
        end
    end
    return "success"
end

function RuntimeAction.execute_train(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return (_G.SentinelCore and _G.SentinelCore.Train and _G.SentinelCore.Train()) and "success" or "retry"
end

function RuntimeAction.execute_flight(payload, ctx)
    local npc_entry = payload.npc_entry
    local destination = payload.destination

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return (_G.SentinelCore and _G.SentinelCore.TakeFlight and _G.SentinelCore.TakeFlight(destination)) and "success" or "retry"
end

function RuntimeAction.execute_hearth(payload, ctx)
    return (_G.SentinelCore and _G.SentinelCore.UseHearthstone and _G.SentinelCore.UseHearthstone()) and "success" or "retry"
end

function RuntimeAction.execute_wait(payload, ctx)
    local duration = payload.duration
    if not ctx.wait_start then
        ctx.wait_start = (_G.GetTime and _G.GetTime()) or 0
        return "success" -- Start waiting
    end

    if (_G.GetTime and _G.GetTime()) - ctx.wait_start >= duration then
        ctx.wait_start = nil
        return "success"
    end
    return "success" -- Still waiting
end

function RuntimeAction.execute_use_item(payload, ctx)
    local item_id = payload.item
    if core and core.input and core.input.use_item then
        core.input.use_item(item_id)
        return "success"
    end
    return "blocked"
end

function RuntimeAction.execute_condition(payload, ctx)
    local cond = payload.condition

    -- Evaluate condition using Sylvanas APIs
    -- For now, check simple conditions
    if cond == "AlwaysTrue" then
        return "success"
    end

    -- TODO: Implement condition evaluation
    return "success"
end

function RuntimeAction.execute_set_variable(payload, ctx)
    ctx.variables = ctx.variables or {}
    ctx.variables[payload.name] = payload.value
    return "success"
end

function RuntimeAction.execute_repair(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return (_G.SentinelCore and _G.SentinelCore.Repair and _G.SentinelCore.Repair()) and "success" or "retry"
end

function RuntimeAction.execute_learn_flight_path(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return (_G.SentinelCore and _G.SentinelCore.LearnFlightPath and _G.SentinelCore.LearnFlightPath()) and "success" or "retry"
end

function RuntimeAction.execute_mailbox(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return (_G.SentinelCore and _G.SentinelCore.OpenMailbox and _G.SentinelCore.OpenMailbox()) and "success" or "retry"
end

function RuntimeAction.execute_bank(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    return (_G.SentinelCore and _G.SentinelCore.OpenBank and _G.SentinelCore.OpenBank()) and "success" or "retry"
end

function RuntimeAction.execute_interact_npc(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    if _G.SentinelCore and _G.SentinelCore.InteractNpc then
        return _G.SentinelCore.InteractNpc(npc_entry, payload.gossip) and "success" or "retry"
    end
    return "blocked"
end

function RuntimeAction.execute_loot(payload, ctx)
    local object_entry = payload.object_entry

    if core and core.input and core.input.loot_object then
        core.input.loot_object(object_entry)
    end
    return "success"
end

function RuntimeAction.execute_grind(payload, ctx)
    -- Navigate to grind area and kill mobs
    return "success" -- Placeholder - needs area navigation
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