local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local NPCInteraction = require("modules/quest/npc_interaction")
local RewardSelector = require("modules/quest/reward_selector")

local QuestPhases = {}

---Create travel phase (to giver or turn-in)
---@param phase_type string "TRAVEL_TO_GIVER" | "TRAVEL_TO_TURNIN" | "TRAVEL_TO_OBJECTIVE"
---@return table BT node
function QuestPhases.travel(phase_type)
    return BT.action("quest:" .. phase_type:lower(), function(bb)
        local plan = bb:get("module.quest.current_plan")
        if not plan then return Status.FAILURE end
        
        local phase = plan.phases[plan.current_phase]
        if not phase or not phase.target then return Status.FAILURE end
        
        local nav = bb:get("module.quest.nav_adapter")
        if not nav then return Status.FAILURE end
        
        local state = nav:get_state()
        local progress = nav:get_progress()
        
        if state == "arrived" then
            bb:set("module.quest.phase_arrived", true)
            return Status.SUCCESS
        elseif state == "failed" then
            bb:set("module.quest.phase_arrived", false)
            return Status.FAILURE
        elseif state == "moving" or state == "requesting_path" then
            return Status.RUNNING
        end
        
        -- Start movement
        local constraints = phase.constraints or {}
        local opts = {
            avoid_elites = constraints.avoid_elites,
            avoid_water = constraints.avoid_water,
        }
        
        if phase.waypoints and #phase.waypoints > 0 then
            nav:follow_path(phase.waypoints, opts)
        else
            nav:move_to(phase.target, opts)
        end
        
        return Status.RUNNING
    end)
end

---Create NPC interaction phase (accept or turn-in)
---@param phase_type string "INTERACT_ACCEPT" | "INTERACT_TURNIN"
---@return table BT node
function QuestPhases.interact(phase_type)
    return BT.action("quest:" .. phase_type:lower(), function(bb)
        local plan = bb:get("module.quest.current_plan")
        if not plan then return Status.FAILURE end
        
        local phase = plan.phases[plan.current_phase]
        if not phase or not phase.npc_id then return Status.FAILURE end
        
        -- Delegate to NPCInteraction service queue
        local interaction = NPCInteraction.new(bb)
        local result = interaction:execute(phase)
        
        if result == "SUCCESS" then
            return Status.SUCCESS
        elseif result == "FAILURE" then
            return Status.FAILURE
        else
            return Status.RUNNING
        end
    end)
end

---Create kill objective phase
---@return table BT node
function QuestPhases.objective_kill()
    return BT.action("quest:objective_kill", function(bb)
        local plan = bb:get("module.quest.current_plan")
        if not plan then return Status.FAILURE end
        
        local phase = plan.phases[plan.current_phase]
        if not phase or phase.type ~= "OBJECTIVE_KILL" then return Status.FAILURE end
        
        local target_id = phase.target_id
        local count = phase.count
        local area = phase.area
        
        -- Check if objective complete via tracker
        local tracker = bb:get("module.quest.tracker")
        if tracker then
            local quest = tracker:get(plan.quests[1].id)
            if quest then
                for _, obj in ipairs(quest.objectives) do
                    if obj.text and obj.text:match(target_id) then
                        local current, needed = obj.text:match("(%d+)/(%d+)")
                        if current and tonumber(current) >= tonumber(needed) then
                            return Status.SUCCESS
                        end
                    end
                end
            end
        end
        
        -- Set grind target filter for quest mobs
        bb:set("module.grind.quest_target_id", target_id)
        bb:set("module.grind.quest_target_area", area)
        bb:set("module.grind.quest_kill_needed", count)
        
        -- Let grind tree handle acquisition/combat
        local grind_state = bb:get("module.grind.current_target")
        if grind_state then
            -- In combat or has target - wait
            return Status.RUNNING
        end
        
        -- No target - grind acquire phase will find one
        return Status.RUNNING
    end)
end

---Create collect objective phase
---@return table BT node
function QuestPhases.objective_collect()
    return BT.action("quest:objective_collect", function(bb)
        local plan = bb:get("module.quest.current_plan")
        if not plan then return Status.FAILURE end
        
        local phase = plan.phases[plan.current_phase]
        if not phase or phase.type ~= "OBJECTIVE_COLLECT" then return Status.FAILURE end
        
        local item_id = phase.item_id
        local count = phase.count
        local area = phase.area
        local sources = phase.sources
        
        -- Check bag count
        local bag_scanner = require("modules/grind/bag_scanner")
        local have = bag_scanner.count_item(item_id) or 0
        
        if have >= count then
            return Status.SUCCESS
        end
        
        -- Navigate to area
        local nav = bb:get("module.quest.nav_adapter")
        if nav and area and not bb:get("module.quest.at_collect_area") then
            nav:move_to(area.center)
            bb:set("module.quest.at_collect_area", true)
            return Status.RUNNING
        end
        
        -- At area - grind will handle looting
        bb:set("module.grind.quest_collect_item", item_id)
        bb:set("module.grind.quest_collect_needed", count - have)
        bb:set("module.grind.quest_collect_area", area)
        
        return Status.RUNNING
    end)
end

---Create escort objective phase
---@return table BT node
function QuestPhases.objective_escort()
    return BT.action("quest:objective_escort", function(bb)
        local plan = bb:get("module.quest.current_plan")
        if not plan then return Status.FAILURE end
        
        local phase = plan.phases[plan.current_phase]
        if not phase or phase.type ~= "OBJECTIVE_ESCORT" then return Status.FAILURE end
        
        local npc_id = phase.npc_id
        local waypoints = phase.waypoints
        
        -- Find escort NPC
        local om = core and core.object_manager
        if not om then return Status.FAILURE end
        
        local npcs = om.get_objects_by_type("unit") or {}
        local escort_npc = nil
        for _, npc in ipairs(npcs) do
            local ok, id = pcall(npc.get_entry, npc)
            if ok and id == npc_id then
                escort_npc = npc
                break
            end
        end
        
        if not escort_npc then
            -- NPC not found - may have died or not spawned
            return Status.FAILURE
        end
        
        local npc_pos = escort_npc.get_position and escort_npc:get_position()
        local player_pos = bb:get("player.position")
        
        -- Check distance to NPC
        if npc_pos and player_pos then
            local dx = npc_pos.x - player_pos.x
            local dy = npc_pos.y - player_pos.y
            local dz = npc_pos.z - player_pos.z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            
            if dist > 15 then
                -- Move closer to NPC
                local nav = bb:get("module.quest.nav_adapter")
                if nav then
                    nav:move_to(npc_pos)
                end
                return Status.RUNNING
            end
        end
        
        -- Follow waypoints if available
        if waypoints and #waypoints > 0 then
            local nav = bb:get("module.quest.nav_adapter")
            if nav then
                nav:follow_path(waypoints)
            end
        end
        
        return Status.RUNNING
    end)
end

---Phase completion handler - advances QuestPlan
---@return table BT node
function QuestPhases.advance_phase()
    return BT.action("quest:advance_phase", function(bb)
        local plan = bb:get("module.quest.current_plan")
        if not plan then return Status.FAILURE end
        
        plan.current_phase = (plan.current_phase or 1) + 1
        bb:set("module.quest.current_plan", plan)
        
        -- Clear phase-specific state
        bb:set("module.quest.phase_arrived", nil)
        bb:set("module.quest.at_collect_area", nil)
        bb:set("module.grind.quest_target_id", nil)
        bb:set("module.grind.quest_collect_item", nil)
        bb:set("module.grind.quest_kill_needed", nil)
        bb:set("module.grind.quest_collect_needed", nil)
        bb:set("module.grind.quest_collect_area", nil)
        bb:set("module.grind.quest_target_area", nil)
        
        -- Emit telemetry
        local event_bus = bb:get("event_bus")
        if event_bus then
            event_bus:publish("quest:phase_complete", {
                phase = plan.current_phase - 1,
                total_phases = #plan.phases,
            })
        end
        
        if plan.current_phase > #plan.phases then
            -- Plan complete!
            event_bus:publish("quest:plan_complete", {quest_ids = plan.quests})
            return Status.SUCCESS
        end
        
        return Status.RUNNING
    end)
end

---Build complete quest phase sequence for GrindTree integration
---@return table BT selector
function QuestPhases.build_quest_tree()
    return BT.priority_selector("quest_execution", {
        -- Check if quest plan exists and has phases
        BT.condition("has_quest_plan", function(bb)
            local plan = bb:get("module.quest.current_plan")
            return plan and plan.phases and #plan.phases > 0 and plan.current_phase <= #plan.phases
        end),
        
        -- Travel phases
        QuestPhases.travel("TRAVEL_TO_GIVER"),
        QuestPhases.travel("TRAVEL_TO_TURNIN"),
        QuestPhases.travel("TRAVEL_TO_OBJECTIVE"),
        
        -- Interaction phases
        QuestPhases.interact("INTERACT_ACCEPT"),
        QuestPhases.interact("INTERACT_TURNIN"),
        
        -- Objective phases
        QuestPhases.objective_kill(),
        QuestPhases.objective_collect(),
        QuestPhases.objective_escort(),
        
        -- Advance phase
        QuestPhases.advance_phase(),
    })
end

return QuestPhases