--- Sentinel Runtime Action Executor
--- Executes RuntimeAction types defined in RuntimeProfile
--- Returns: "success", "retry", "blocked", "failed", "skipped"

-- ============================================================================
-- Named constants for navigation and proximity (W3.1, W3.6)
-- ============================================================================
local NAV_RETRY_DELAY = 1.0    -- Seconds between navigation retries

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
    local dest   = payload.destination    -- string zone name (e.g. "Elwynn Forest")
    local tol    = payload.tolerance or 5.0
    local target = payload.position       -- {x, y, z} from compiler (preferred)

    -- Resolve target position: prefer explicit coords, fall back to zone waypoint
    local target_pos = nil
    if type(target) == "table" and target.x then
        target_pos = target
    elseif type(dest) == "string" then
        target_pos = ctx:get_zone_waypoint(dest)
    end

    if not target_pos then
        return "blocked" -- No known position to navigate to
    end

    -- Already there?
    if ctx:is_at_destination(target_pos, tol) then
        return "success"
    end

    -- Already navigating? Poll for arrival.
    if ctx.nav and ctx.nav:is_active() then
        local state, progress = ctx.nav:poll()
        if state == "arrived" or state == "idle" then
            -- Arrived: verify position
            if ctx:is_at_destination(target_pos, tol) then
                ctx.nav:stop("arrived")
                return "success"
            end
            -- Not close enough; allow re-navigation below
        elseif state == "requesting_path" or state == "moving" then
            return "blocked" -- Still navigating
        elseif state == "stuck" then
            return "retry" -- Pathfinding issue; outer loop can try recovery
        else
            -- failed / unknown → fall through to retry
        end
    end

    -- Start navigation via NavAdapter
    if ctx.nav then
        local ok, err = ctx.nav:move_to(target_pos, { tolerance = tol })
        if ok then
            return "blocked" -- Will be polled on subsequent tick
        end
        return "retry" -- Dispatch failed; outer loop can retry
    end

    -- No NavAdapter available: use raw key movement as last resort
    if core and core.input and core.input.move then
        core.input.move(target_pos.x or 0, target_pos.y or 0, target_pos.z or 0)
        return "blocked"
    end

    return "blocked" -- Navigation unavailable
end

function RuntimeAction.execute_kill(payload, ctx)
    local entries = payload.creature_entries or {}

    -- Find and target nearest creature
    if core and core.object_manager and core.object_manager.GetNearestCreature then
        local target = core.object_manager.GetNearestCreature(entries)
        if target and target.IsValid then
            if target:IsDead() then
                return "success"
            end
            -- Check proximity — if out of combat range, initiate navigation (W3.6)
            if not ctx:is_at_npc(entries[1], 30.0) then
                -- Start navigation to target's position
                if ctx.nav and not ctx.nav:is_active() then
                    local npc_pos = nil
                    if target.get_position then
                        local ok, pos = pcall(target.get_position, target)
                        if ok then npc_pos = pos end
                    end
                    if npc_pos then
                        ctx.nav:move_to(npc_pos, { tolerance = 5.0 })
                    end
                end
                return "blocked" -- Navigate to target first
            end
            return "success" -- In range, trust kill loop
        end
    end

    -- No targets found — check if we should navigate to a known spawn area
    local dest = payload.destination
    if dest and ctx.nav and not ctx.nav:is_active() then
        local target_pos = nil
        if type(dest) == "table" and dest.x then
            target_pos = dest
        elseif type(dest) == "string" then
            target_pos = ctx:get_zone_waypoint(dest)
        end
        if target_pos then
            ctx.nav:move_to(target_pos)
            return "blocked" -- Navigating to spawn area
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

--- Evaluate a single RuntimeCondition against game state.
--- Returns true/false.
--- Each condition type maps to a handler in the lookup table.
function RuntimeAction.evaluate_condition(ctx, cond)
    -- Unit variant (AlwaysTrue, AlwaysFalse — serialised as bare string)
    if type(cond) == "string" then
        local handler = RuntimeAction._condition_handlers[cond]
        if handler then
            return handler(ctx, nil)
        end
        return true
    end

    -- Struct variant — { type = "VariantName", payload = <value> }
    if type(cond) == "table" and cond.type then
        local handler = RuntimeAction._condition_handlers[cond.type]
        if handler then
            return handler(ctx, cond.payload)
        end
        return true
    end

    return true
end

--- Execute a Condition action (gate).
--- Returns "success" if condition met, "skipped" if not.
function RuntimeAction.execute_condition(payload, ctx)
    local cond = payload.condition
    local ok = RuntimeAction.evaluate_condition(ctx, cond)
    return ok and "success" or "skipped"
end

-- ============================================================================
-- Condition handler lookup table
-- Each handler receives (ctx, payload) and returns true/false.
-- ============================================================================
RuntimeAction._condition_handlers = {}

-- Always true — always passes
RuntimeAction._condition_handlers["AlwaysTrue"] = function(ctx, _)
    return true
end

--- Quest conditions ---
RuntimeAction._condition_handlers["QuestAccepted"] = function(ctx, quest_entry)
    return ctx:is_quest_active(quest_entry)
end

RuntimeAction._condition_handlers["QuestCompleted"] = function(ctx, quest_entry)
    return ctx:is_quest_completed(quest_entry)
end

RuntimeAction._condition_handlers["QuestRewarded"] = function(ctx, quest_entry)
    return ctx:is_quest_completed(quest_entry)
end

RuntimeAction._condition_handlers["ObjectiveComplete"] = function(ctx, payload)
    local quest_entry = payload[1]
    local objective_idx = payload[2]
    return ctx:is_objective_complete(quest_entry, objective_idx)
end

--- Level conditions ---
RuntimeAction._condition_handlers["LevelAtLeast"] = function(ctx, level)
    return ctx:get_player_level() >= level
end

RuntimeAction._condition_handlers["LevelBelow"] = function(ctx, level)
    return ctx:get_player_level() < level
end

--- Item conditions ---
RuntimeAction._condition_handlers["HasItem"] = function(ctx, item_entry)
    local count = ctx:get_item_count(item_entry)
    return count ~= nil and count > 0
end

RuntimeAction._condition_handlers["ItemCountAtLeast"] = function(ctx, payload)
    local item_entry = payload[1]
    local count = payload[2]
    return (ctx:get_item_count(item_entry) or 0) >= count
end

--- Gold condition ---
RuntimeAction._condition_handlers["GoldAtLeast"] = function(ctx, copper)
    return (ctx:get_money() or 0) >= copper
end

--- Profession condition ---
RuntimeAction._condition_handlers["ProfessionSkillAtLeast"] = function(ctx, payload)
    local skill_name = payload[1]
    local skill_level = payload[2]
    return (ctx:get_skill_level(skill_name) or 0) >= skill_level
end

--- Item cooldown ---
RuntimeAction._condition_handlers["ItemCooldownReady"] = function(ctx, item_entry)
    return ctx:is_item_ready(item_entry)
end

--- Reputation condition ---
RuntimeAction._condition_handlers["ReputationAtLeast"] = function(ctx, payload)
    local faction = payload[1]
    local standing = payload[2]
    return (ctx:get_reputation(faction) or -42000) >= standing
end

--- Player conditions ---
RuntimeAction._condition_handlers["RaceIs"] = function(ctx, race_name)
    return ctx:get_player_race() == race_name
end

RuntimeAction._condition_handlers["ClassIs"] = function(ctx, class_name)
    return ctx:get_player_class() == class_name
end

RuntimeAction._condition_handlers["FactionIs"] = function(ctx, faction_name)
    return ctx:get_player_faction() == faction_name
end

--- Logical operators ---
RuntimeAction._condition_handlers["Not"] = function(ctx, inner)
    return not RuntimeAction.evaluate_condition(ctx, inner)
end

RuntimeAction._condition_handlers["All"] = function(ctx, conditions)
    for _, subcond in ipairs(conditions) do
        if not RuntimeAction.evaluate_condition(ctx, subcond) then
            return false
        end
    end
    return true
end

RuntimeAction._condition_handlers["Any"] = function(ctx, conditions)
    for _, subcond in ipairs(conditions) do
        if RuntimeAction.evaluate_condition(ctx, subcond) then
            return true
        end
    end
    return false
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

    -- Proximity check (W3.6) — if object not in range, navigate first
    if not ctx:is_at_object(object_entry) then
        if ctx.nav and not ctx.nav:is_active() then
            -- Try to get nearest object's position for navigation
            if core and core.object_manager then
                local nearest_obj = nil
                if core.object_manager.GetNearestGameObject then
                    nearest_obj = core.object_manager.GetNearestGameObject({ object_entry })
                elseif core.object_manager.GetNearestObject then
                    nearest_obj = core.object_manager.GetNearestObject({ object_entry })
                end
                if nearest_obj and nearest_obj.get_position then
                    local ok, obj_pos = pcall(nearest_obj.get_position, nearest_obj)
                    if ok and obj_pos then
                        ctx.nav:move_to(obj_pos, { tolerance = 5.0 })
                    end
                end
            end
        end
        return "blocked" -- Not in loot range
    end

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