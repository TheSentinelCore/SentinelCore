local ConditionLibrary = require("modules/combat/condition_library")
local ActionLibrary = require("modules/combat/action_library")
local QueuePriorities = require("shared/queue_priorities")
local BT = require("core/bt/factory")
local Status = require("core/bt/status")

local SharedSubtrees = {}

-- ============================================================================
-- INTERRUPT SUBTREE
-- ============================================================================

--- Create an interrupt subtree
-- @param interrupt_spell string Spell key for interrupt (e.g. "counterspell", "pummel", "wind_shear")
-- @param options table Optional configuration
--   - range: number (default: 30) - interrupt range check
--   - priority: number (default: 7) - queue priority for interrupt (INTERRUPT = 7)
-- @return function Returns a function that takes blackboard and returns BT node
function SharedSubtrees.interrupt(interrupt_spell, options)
    options = options or {}
    local range = options.range or 30
    local priority = options.priority or 7  -- INTERRUPT priority from queue_priorities.lua
    
    return function(blackboard)
        return BT.sequence("interrupt_" .. interrupt_spell, {
            -- Check if target is valid and casting/channelling
            ConditionLibrary.target_valid,
            ConditionLibrary.target_casting_interruptible,
            -- Check range
            BT.condition("target_in_range_" .. interrupt_spell, 
                function(bb)
                    local _, target = blackboard:get("player.object"), blackboard:get("combat.target") or blackboard:get("player.target")
                    if not target then return false end
                    local player = blackboard:get("player.object")
                    if not player then return false end
                    -- Use compat library for distance if available, otherwise manual calc
                    local Compat = require("shared/compat")
                    if Compat and Compat.dist then
                        return Compat.dist(player:get_position(), target:get_position()) <= range
                    else
                        -- Fallback manual calculation
                        local px, py, pz = player:get_position().x, player:get_position().y, player:get_position().z
                        local tx, ty, tz = target:get_position().x, target:get_position().y, target:get_position().z
                        local dx, dy, dz = tx - px, ty - py, tz - pz
                        return math.sqrt(dx*dx + dy*dy + dz*dz) <= range
                    end
                end),
            -- Check if spell is ready and castable
            ConditionLibrary.spell_ready(interrupt_spell),
            -- Execute interrupt
            ActionLibrary.cast_target(interrupt_spell, nil, priority)
        })
    end
end

-- ============================================================================
-- DEFENSIVE SUBTREE
-- ============================================================================

--- Create a defensive cooldowns subtree
-- @param defenses table List of defensive configurations
--   Each entry: { spell = "ice_block", threshold = 0.2, priority = 5 }
--   threshold can be health_pct (0-1) or time_to_die (seconds)
-- @return function Returns a function that takes blackboard and returns BT node
function SharedSubtrees.defensive(defenses)
    return function(blackboard)
        local defensive_actions = {}
        
        for i, def in ipairs(defenses) do
            local condition
            if def.health_threshold then
                condition = ConditionLibrary.health_below(def.health_threshold)
            elseif def.time_to_die then
                -- Note: This would need integration with IZI SDK's time_to_die function
                -- For now, we'll approximate with health percentage
                condition = ConditionLibrary.health_below(math.min(0.2, def.time_to_die * 0.05))  -- Rough conversion
            else
                -- Default to 30% health
                condition = ConditionLibrary.health_below(0.3)
            end
            
            -- Add buff check if specified (don't cast if already have the buff)
            if def.buff_to_avoid then
                condition = ConditionLibrary.and_({
                    condition,
                    ConditionLibrary.not_(ConditionLibrary.has_buff(def.buff_to_avoid))
                })
            end
            
            table.insert(defensive_actions, 
                BT.sequence("defensive_" .. def.spell, {
                    condition,
                    ActionLibrary.cast_self(def.spell, def.priority or QueuePriorities.DEFAULT)
                }))
        end
        
        if #defensive_actions == 0 then
            return BT.action("no_defensives", function() return Status.FAILURE end)
        elseif #defensive_actions == 1 then
            return defensive_actions[1]
        else
            return BT.selector("defensive_options", defensive_actions)
        end
    end
end

-- ============================================================================
-- EXECUTE SUBTREE
-- ============================================================================

--- Create an execute subtree for finishing low-health targets
-- @param execute_spell string Spell key for execute ability (e.g. "hammer_of_wrath", "execute")
-- @param options table Optional configuration
--   - health_threshold: number (default: 0.2) - execute when target < 20% health
--   - time_to_die: number (default: nil) - execute when TTD < X seconds
--   - requires_buff: string (default: nil) - only execute when buff is active
--   - ignores_defensive: boolean (default: false) - ignore target's defensive buffs
--   - priority: number (default: QueuePriorities.DEFAULT)
-- @return function Returns a function that takes blackboard and returns BT node
function SharedSubtrees.execute(execute_spell, options)
    options = options or {}
    local health_threshold = options.health_threshold or 0.2
    local time_to_die = options.time_to_die
    local requires_buff = options.requires_buff
    local ignores_defensive = options.ignores_defensive or false
    local priority = options.priority or QueuePriorities.DEFAULT
    
    return function(blackboard)
        local conditions = {
            ConditionLibrary.target_valid,
            -- Default melee range, could be made configurable
            ConditionLibrary.target_in_range(8),
        }
        
        if health_threshold then
            table.insert(conditions, ConditionLibrary.health_below(health_threshold))
        end
        
        if time_to_die then
            -- Would integrate with TTD from IZI SDK
            table.insert(conditions, ConditionLibrary.health_below(math.min(0.1, time_to_die * 0.05)))  -- Rough approx
        end
        
        if requires_buff then
            table.insert(conditions, ConditionLibrary.has_buff(requires_buff))
        end
        
        if not ignores_defensive then
            -- Add common defensive buff checks to avoid wasting execute
            table.insert(conditions, ConditionLibrary.not_(ConditionLibrary.has_any_buff({
                "divine_shield", "ice_block", "lifeblood", "shield_wall"
            })))
        end
        
        return BT.sequence("execute_" .. execute_spell, {
            ConditionLibrary.and_(unpack(conditions)),
            ActionLibrary.cast_target(execute_spell, nil, priority)
        })
    end
end

-- ============================================================================
-- AREA OF EFFECT (AOE) SUBTREE
-- ============================================================================

--- Create an AOE subtree for ground-targeted spells
-- @param aoe_spell string Spell key for AOE spell (e.g. "blizzard", "consecration", "death_and_decay")
-- @param options table Optional configuration
--   - min_targets: number (default: 3) - minimum enemies required to consider AOE
--   - check_radius: number (default: 8) - radius around target to check for enemies
--   - max_range: number (default: 30) - maximum range to attempt AOE
--   - use_prediction: boolean (default: true) - attempt to use spell prediction for optimal placement
--   - require_still: boolean (default: true) - require player to be stationary for channeled AOEs
--   - priority: number (default: QueuePriorities.DEFAULT)
-- @return function Returns a function that takes blackboard and returns BT node
function SharedSubtrees.aoe(aoe_spell, options)
    options = options or {}
    local min_targets = options.min_targets or 3
    local check_radius = options.check_radius or 8
    local max_range = options.max_range or 30
    local use_prediction = options.use_prediction ~= false
    local require_still = options.require_still ~= false
    local priority = options.priority or QueuePriorities.DEFAULT
    
    return function(blackboard)
        local conditions = {
            -- Check if we should consider AOE (enough enemies nearby)
            ConditionLibrary.enemies_in_range(min_targets, check_radius),
            -- Check if spell is ready
            ConditionLibrary.spell_ready(aoe_spell),
            -- Check range to target area (we'll use target position or player position)
        }
        
        if require_still then
            table.insert(conditions, ConditionLibrary.not_(ConditionLibrary.player_is_moving))
        end
        
        -- Note: For true AOE positioning with prediction, we'd need to integrate
        -- with the spell prediction system. For now, we'll use simple targeting.
        
        return BT.sequence("aoe_" .. aoe_spell, {
            ConditionLibrary.and_(unpack(conditions)),
            -- Simple version: cast at target's position
            -- TODO: Enhance with spell prediction for optimal placement
            ActionLibrary.cast_position(aoe_spell, 
                function(bb)
                    local _, target = blackboard:get("player.object"), blackboard:get("combat.target") or blackboard:get("player.target")
                    if target then
                        return target:get_position()
                    end
                    local player = blackboard:get("player.object")
                    if player then
                        return player:get_position()
                    end
                    return {x=0, y=0, z=0}  -- Fallback
                end, 
                priority)
        })
    end
end

-- ============================================================================
-- BUFF MAINTENANCE SUBTREE
-- ============================================================================

--- Create a buff maintenance subtree for buffs that should be kept up
-- @param buffs table List of buff configurations
--   Each entry: { spell = "arcane_intellect", required = true, combat_only = false }
-- @return function Returns a function that takes blackboard and returns BT node
function SharedSubtrees.buff_maintenance(buffs)
    return function(blackboard)
        local buff_actions = {}
        
        for i, buff in ipairs(buffs) do
            local should_check = true
            if buff.combat_only then
                -- Only check in combat
                should_check = function(bb)
                    return bb:get("player.in_combat", false) == true
                end
            end
            
            local condition
            if type(should_check) == "function" then
                condition = ConditionLibrary.and_({
                    ConditionLibrary.not_(ConditionLibrary.has_buff(buff.spell)),
                    should_check
                })
            else
                condition = ConditionLibrary.not_(ConditionLibrary.has_buff(buff.spell))
            end
            
            table.insert(buff_actions, 
                BT.sequence("maintain_" .. buff.spell, {
                    condition,
                    ActionLibrary.cast_self(buff.spell, buff.priority or QueuePriorities.DEFAULT)
                }))
        end
        
        if #buff_actions == 0 then
            return BT.action("no_buffs", function() return Status.FAILURE end)
        elseif #buff_actions == 1 then
            return buff_actions[1]
        else
            return BT.selector("buff_options", buff_actions)
        end
    end
end

-- ============================================================================
-- MOVEMENT/KITING SUBTREE
-- ============================================================================

--- Create a simple kiting/movement helper
-- @param options table Configuration
--   - flee_when_hp_below: number (default: 0.3)
--   - use_snare: boolean (default: true) - apply snare to pursue target
--   - snare_spell: string (default: nil) - spell to use for snaring
--   - max_chase_distance: number (default: 30) - stop chasing if target goes further
-- @return function Returns a function that takes blackboard and returns BT node
function SharedSubtrees.kite_assist(options)
    options = options or {}
    local flee_hp = options.flee_when_hp_below or 0.3
    local use_snare = options.use_snare ~= false
    local snare_spell = options.snare_spell
    local max_distance = options.max_chase_distance or 30
    
    return function(blackboard)
        -- This would integrate with movement/kite controller
        -- For now, return a simple placeholder that maintains current behavior
        return BT.action("kite_placeholder", function() return Status.RUNNING end)
    end
end

return SharedSubtrees
