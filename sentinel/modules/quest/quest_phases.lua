local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local NPCInteraction = require("modules/quest/npc_interaction")
local RewardSelector = require("modules/quest/reward_selector")

local QuestPhases = {}
local _quest_guard_diag_last = 0

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
            bb:set("module.quest.phase_done", true)
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
            bb:set("module.quest.phase_done", true)
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
        local count = phase.count or 1
        local area = phase.area

        -- Check if objective complete via tracker
        local tracker = bb:get("module.quest.tracker")
        if tracker and plan.quests and plan.quests[1] then
            local quest = tracker:get(plan.quests[1].id)
            if quest then
                for _, obj in ipairs(quest.objectives) do
                    if obj.text then
                        local current, needed = obj.text:match("(%d+)/(%d+)")
                        if current and needed
                            and tonumber(current) >= tonumber(needed) then
                            bb:set("module.quest.phase_done", true)
                            return Status.SUCCESS
                        end
                    end
                end
            end
        end

        -- Set grind target filter for quest mobs (only when target_id is known)
        if target_id then
            bb:set("module.grind.quest_target_id", target_id)
        end
        bb:set("module.grind.quest_target_area", area)
        bb:set("module.grind.quest_kill_needed", count)

        -- Return FAILURE so grind tree falls through to combat/pull/acquire
        return Status.FAILURE
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
            bb:set("module.quest.phase_done", true)
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
        
        -- Return FAILURE so grind tree falls through to combat/loot/pull
        -- which pick up the quest_collect flags
        return Status.FAILURE
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
            local ok, id = pcall(npc.get_npc_id, npc)
            if ok and id == npc_id then
                escort_npc = npc
                break
            end
        end
        
        if not escort_npc then
            -- NPC not found - may have died or not spawned
            bb:set("module.quest.phase_done", true)
            return Status.SUCCESS
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
                return Status.FAILURE
            end
        end
        
        -- Follow waypoints if available
        if waypoints and #waypoints > 0 then
            local nav = bb:get("module.quest.nav_adapter")
            if nav then
                -- Check navigation state - similar to travel phase pattern
                local state = nav:get_state()
                if state == "arrived" then
                    bb:set("module.quest.phase_done", true)
                    return Status.SUCCESS
                elseif state == "failed" then
                    bb:set("module.quest.phase_done", true)
                    return Status.FAILURE
                elseif state == "moving" or state == "requesting_path" then
                    return Status.RUNNING
                end
                
                -- Start navigation
                nav:follow_path(waypoints)
            end
            -- Started navigation - check again next tick
            return Status.RUNNING
        end
        
        return Status.FAILURE
    end)
end

---Phase completion handler — advances QuestPlan only when current phase is done.
---Sets `module.quest.phase_done` based on the current phase's success criteria.
---@return table BT node
function QuestPhases.advance_phase()
    return BT.action("quest:advance_phase", function(bb)
        local plan = bb:get("module.quest.current_plan")
        if not plan then return Status.FAILURE end

        local current_idx = plan.current_phase or 1
        local phase = plan.phases[current_idx]
        if not phase then
            -- Past the end — plan is complete
            plan.current_phase = current_idx + 1
            bb:set("module.quest.current_plan", plan)
            local event_bus = bb:get("event_bus")
            if event_bus then
                event_bus:publish("quest:plan_complete", {quest_ids = plan.quests})
            end
            return Status.SUCCESS
        end

        -- Determine if the current phase is complete
        local done = bb:get("module.quest.phase_done") == true
        if not done then
            -- Phase not yet complete; don't advance, let lower-priority grind phases run
            return Status.FAILURE
        end

        -- Phase is complete — advance
        bb:set("module.quest.phase_done", nil)
        bb:set("module.quest.phase_arrived", nil)
        bb:set("module.quest.at_collect_area", nil)
        bb:set("module.grind.quest_target_id", nil)
        bb:set("module.grind.quest_collect_item", nil)
        bb:set("module.grind.quest_kill_needed", nil)
        bb:set("module.grind.quest_collect_needed", nil)
        bb:set("module.grind.quest_collect_area", nil)
        bb:set("module.grind.quest_target_area", nil)

        plan.current_phase = current_idx + 1
        bb:set("module.quest.current_plan", plan)

        local event_bus = bb:get("event_bus")
        if event_bus then
            event_bus:publish("quest:phase_complete", {
                phase = current_idx,
                total_phases = #plan.phases,
            })
        end

        if plan.current_phase > #plan.phases then
            if event_bus then
                event_bus:publish("quest:plan_complete", {quest_ids = plan.quests})
            end
            return Status.SUCCESS
        end

        return Status.RUNNING
    end)
end

---Build complete quest execution tree for GrindTree integration.
---Wrapped in a Sequence(guard, phases) so the condition is re-evaluated every tick
---and quest phases don't block lower-priority BT nodes with RUNNING.
---@return table BT node
function QuestPhases.build_quest_tree()
    return BT.sequence("quest_execution", {
        -- Guard: only tick quest phases when a plan exists and has pending phases.
        -- Also sets current_spot from the active phase's area so the acquire
        -- phase knows where to navigate when quest phases delegate to the grind tree.
        BT.condition("has_quest_plan", function(bb)
            local plan = bb:get("module.quest.current_plan")
            if not (plan and plan.phases and #plan.phases > 0 and plan.current_phase <= #plan.phases) then
                return false
            end
            local phase = plan.phases[plan.current_phase]
            if phase and phase.area and phase.area.center then
                bb:set("module.grind.current_spot", {
                    center = phase.area.center,
                    radius = phase.area.radius or 100,
                    level_min = 1,
                    level_max = 80,
                })
            end
            local now = bb:get("system.now_ms", 0)
            if now - (_quest_guard_diag_last or 0) >= 5000 then
                _quest_guard_diag_last = now
                if core and core.log then
                    pcall(core.log, string.format(
                        "[QuestBT] guard PASS: phase=%d/%d type=%s",
                        plan.current_phase, #plan.phases,
                        tostring(phase and phase.type)))
                end
            end
            return true
        end),

        BT.priority_selector("quest_phases", {
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

            -- Advance phase (only succeeds when current phase is done)
            QuestPhases.advance_phase(),
        }),
    })
end

return QuestPhases