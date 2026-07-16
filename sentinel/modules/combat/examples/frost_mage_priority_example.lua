-- Example: How Frost Mage rotation would look with the new PriorityBuilder system
-- This is for demonstration purposes - actual integration would replace the existing frost_*.lua files

local PriorityBuilder = require("modules/combat/priority_builder")
local ConditionLibrary = require("modules/combat/condition_library")
local ActionLibrary = require("modules/combat/action_library")
local SharedSubtrees = require("modules/combat/shared_subtrees")

-- Example Frost Mage rotation using PriorityBuilder
local function build_frost_mage_rotation()
    local builder = PriorityBuilder.new("MAGE", "FROST")
    builder:set_icon(135846)  -- Frostbolt icon
    
    -- ============================================================================
    -- CORE ROTATION PRIORITIES
    -- ============================================================================
    
    -- Defensive cooldowns (high priority)
    builder:add_priority(
        "Ice Block Emergency",
        ConditionLibrary.health_below(0.15),  -- Below 15% health
        ActionLibrary.cast_self("ice_block", 6)  -- Priority 6 (high)
    )
    
    builder:add_priority(
        "Ice Block Incoming Damage",
        ConditionLibrary.and_({
            ConditionLibrary.health_below(0.25),  -- Below 25% health
            ConditionLibrary.incoming_damage_above(0.4, 3.0)  -- 40% inc damage in 3s
        }),
        ActionLibrary.cast_self("ice_block", 6)
    )
    
    -- Interrupts (very high priority)
    builder:add_priority(
        "Counterspell",
        ConditionLibrary.and_({
            ConditionLibrary.target_casting_interruptible,
            ConditionLibrary.spell_ready("counterspell"),
            ConditionLibrary.target_in_range(30)  -- 30 yard range
        }),
        ActionLibrary.cast_target("counterspell", nil, 7)  -- INTERRUPT priority
    )
    
    -- Emergency heal/protection
    builder:add_priority(
        "Mana Shield",
        ConditionLibrary.and_({
            ConditionLibrary.health_below(0.4),
            ConditionLibrary.not_(ConditionLibrary.has_buff("mana_shield")),
            ConditionLibrary.spell_ready("mana_shield")
        }),
        ActionLibrary.cast_self("mana_shield", 5)
    )
    
    -- AoE when appropriate
    builder:add_priority(
        "Blizzard AoE",
        ConditionLibrary.and_({
            ConditionLibrary.use_aoe_rotation,  -- From combat state
            ConditionLibrary.enemies_in_range(3, 8),  -- 3+ enemies in 8 yards
            ConditionLibrary.spell_ready("blizzard"),
            ConditionLibrary.not_(ConditionLibrary.player_is_moving)  -- Blizzard requires standing still
        }),
        ActionLibrary.cast_position("blizzard",  -- Would ideally use spell prediction for optimal placement
            function(bb)
                local _, target = bb:get("player.object"), bb:get("combat.target") or bb:get("player.target")
                if target then return target:get_position() end
                local player = bb:get("player.object")
                if player then return player:get_position() end
                return {x=0, y=0, z=0}
            end,
            3  -- Normal priority
        )
    )
    
    -- Standard rotation
    builder:add_priority(
        "Frostbolt",
        ConditionLibrary.and_({
            ConditionLibrary.target_valid,
            ConditionLibrary.target_in_range(30),  -- Frostbolt range
            ConditionLibrary.spell_ready("frostbolt"),
            ConditionLibrary.not_(ConditionLibrary.player_is_moving),  -- Or allow moving with proc
            ConditionLibrary.not_(ConditionLibrary.cast_is_overkill_or_channeling)  -- Not currently casting
        }),
        ActionLibrary.cast_target("frostbolt", nil, 1)  -- DEFAULT priority
    )
    
    -- Ice Lance proc (Fingers of Frost)
    builder:add_priority(
        "Ice Lance Proc",
        ConditionLibrary.and_({
            ConditionLibrary.target_valid,
            ConditionLibrary.target_in_range(30),
            ConditionLibrary.has_buff("fingers_of_frost"),  -- Proc buff
            ConditionLibrary.spell_ready("ice_lance")
        }),
        ActionLibrary.cast_target("ice_lance", nil, 2)  -- Slightly higher than Frostbolt
    )
    
    -- Frostfire Bolt proc (Brain Freeze)
    builder:add_priority(
        "Frostfire Bolt Proc",
        ConditionLibrary.and_({
            ConditionLibrary.target_valid,
            ConditionLibrary.target_in_range(30),
            ConditionLibrary.has_buff("brain_freeze"),  -- Proc buff
            ConditionLibrary.spell_ready("frostfire_bolt")
        }),
        ActionLibrary.cast_target("frostfire_bolt", nil, 2)
    )
    
    -- Maintain buffs
    builder:add_priority(
        "Molten Armor",
        ConditionLibrary.and_({
            ConditionLibrary.not_(ConditionLibrary.has_buff("molten_armor")),
            ConditionLibrary.player_in_combat,
            ConditionLibrary.spell_ready("molten_armor")
        }),
        ActionLibrary.cast_self("molten_armor", 4)
    )
    
    -- Water elemental
    builder:add_priority(
        "Summon Water Elemental",
        ConditionLibrary.and_({
            ConditionLibrary.not_(ConditionLibrary.has_water_elemental),
            ConditionLibrary.spell_ready("summon_water_elemental"),
            ConditionLibrary.not_(ConditionLibrary.player_is_moving)  -- Usually want to summon while stationary
        }),
        ActionLibrary.cast_target("summon_water_elemental", nil, 4)
    )
    
    return builder
end

-- Example of how this would be used in the combat module:
-- local rotation_builder = build_frost_mage_rotation()
-- local frost_mage_rotation = rotation_builder:build(blackboard)
-- -- Then in the combat tick, execute: frost_mage_rotation:execute(blackboard)

return {
    build_frost_mage_rotation = build_frost_mage_rotation
}