-- sentinel/modules/quest/step_executors/init.lua
-- Step Executors: Individual executors for each step type

local StepExecutors = {}

-- Travel Executor: Handles movement to a destination
StepExecutors.TravelExecutor = {
    execute = function(step, ctx)
        -- step = {type="travel", target={x,y,z,map_id}, policy="policy_name", waypoints={...}}
        local nav = ctx.engine.nav
        local policy = step.policy or "default"
        local goal = step.target
        
        if not goal then
            return false, "No target position specified"
        end
        
        local start = ctx.engine.blackboard:get("player.position")
        if not start then
            return false, "No player position"
        end
        
        -- Request path from NavServer with policy
        local path = nav:followPolicy(policy, goal)
        if not path then
            return false, "Path planning pending"
        end
        
        return true
    end
}

-- Interact Executor: Handles NPC interaction (accept/turn-in quests)
StepExecutors.InteractExecutor = {
    execute = function(step, ctx)
        -- step = {type="interact", action="accept|turnin|bind", questId=..., npcId=...}
        local action = step.action
        local questId = step.questId
        local npcId = step.npcId
        
        if action == "accept" then
            return ctx.engine:acceptQuest(questId, npcId)
        elseif action == "turnin" then
            return ctx.engine:turnInQuest(questId, step.rewardIndex)
        elseif action == "bind" then
            return ctx.engine:bindHearthstone(npcId)
        end
        
        return false, "Unknown interact action: " .. tostring(action)
    end
}

-- Kill Executor: Handles killing NPCs for objectives
StepExecutors.KillExecutor = {
    execute = function(step, ctx)
        -- step = {type="kill", npcIds={...}, count=..., area={center={...}, radius=...}}
        local combat = ctx.engine.combat
        local nav = ctx.engine.nav
        
        -- Set target filter
        if step.npcIds then
            combat:setTargetFilter(step.npcIds)
        end
        
        -- Navigate to area if specified
        if step.area then
            nav:followPolicy(step.policy or "smart", step.area.center)
        end
        
        -- Engage combat
        combat:engage()
        
        -- Wait for objective completion (handled by statechart transitions)
        return true
    end,
    
    cleanup = function(step, ctx)
        ctx.engine.combat:clearTargetFilter()
    end
}

-- Collect Executor: Handles collecting items
StepExecutors.CollectExecutor = {
    execute = function(step, ctx)
        -- step = {type="collect", itemId=..., count=..., sources={...}, area={...}}
        local nav = ctx.engine.nav
        local combat = ctx.engine.combat
        
        -- If sources are NPCs, kill them
        if step.sources and step.sources[1] and step.sources[1].npcIds then
            combat:setTargetFilter(step.sources[1].npcIds)
            if step.area then
                ctx.engine.nav:followPolicy(step.policy or "smart", step.area.center)
            end
            combat:engage()
        end
        
        -- If sources are objects, navigate and interact
        if step.sources and step.sources[1] and step.sources[1].objectIds then
            -- Would need object interaction logic
        end
        
        return true
    end
}

-- Escort Executor: Handles escort quests
StepExecutors.EscortExecutor = {
    execute = function(step, ctx)
        -- step = {type="escort", npcId=..., waypoints={...}}
        local nav = ctx.engine.nav
        local npcId = step.npcId
        
        -- Start escort (would accept quest and follow NPC)
        -- nav:followNPC(npcId, step.waypoints)
        
        return true
    end
}

-- Vendor Executor: Handles vendor operations
StepExecutors.VendorExecutor = {
    execute = function(step, ctx)
        -- step = {type="vendor", action="sell|repair|buy", items={...}}
        local vendor = ctx.engine.vendor
        local nav = ctx.engine.nav
        
        if step.action == "sell" then
            return vendor:sellJunk()
        elseif step.action == "repair" then
            return vendor:repair()
        elseif step.action == "buy" then
            return vendor:buyConsumables(step.items or {})
        end
        return false
    end
}

-- Repair Executor: Handles equipment repair
StepExecutors.RepairExecutor = {
    execute = function(step, ctx)
        local vendor = ctx.engine.vendor
        return vendor:repair()
    end
}

-- Train Executor: Handles trainer operations
StepExecutors.TrainExecutor = {
    execute = function(step, ctx)
        local trainer = ctx.engine.trainer
        return trainer:trainAvailable()
    end
}

-- Fly Executor: Handles flight paths
StepExecutors.FlyExecutor = {
    execute = function(step, ctx)
        local nav = ctx.engine.nav
        local movement = ctx.engine.movement
        
        if step.action == "take" then
            -- Take flight path
            return movement:takeFlightPath(step.from, step.to)
        elseif step.action == "discover" then
            -- Discover flight path
            return nav:discoverFlightPath(step.nodeId)
        end
        return false
    end
}

-- Grind Executor: Handles grinding mobs for XP/loot
StepExecutors.GrindExecutor = {
    execute = function(step, ctx)
        local combat = ctx.engine.combat
        local nav = ctx.engine.nav
        
        combat:setTargetFilter(step.npcIds)
        if step.area then
            nav:followPolicy(step.policy or "smart", step.area.center)
        end
        combat:engage()
        
        return true
    end,
    
    cleanup = function(step, ctx)
        ctx.engine.combat:clearTargetFilter()
    end
}

-- Recover Executor: Handles death recovery
StepExecutors.RecoverExecutor = {
    execute = function(step, ctx)
        local nav = ctx.engine.nav
        local consume = ctx.engine.consume
        
        -- Release spirit and run to corpse
        if step.action == "spirit_rez" then
            -- Release spirit
        elseif step.action == "corpse_run" then
            nav:followPolicy("corpse_recovery", step.corpsePos)
        elseif step.action == "rezzed" then
            consume:useFood()
            consume:useWater()
        end
        
        return true
    end
}

return StepExecutors