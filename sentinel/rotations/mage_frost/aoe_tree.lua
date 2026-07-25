local API = require("rotations/mage_frost/sentinel_api")
local BT = setmetatable({}, { __index = function(_, k) return API.bt and API.bt[k] or nil end })
local Cond = require("rotations/mage_frost/frost_conditions")
local Act = require("rotations/mage_frost/frost_actions")
local Status = setmetatable({}, { __index = function(_, k)
    return API.bt and API.bt.Status and API.bt.Status[k] or nil
end })

local AoeTree = {}

function AoeTree.build()
    return BT.selector("frost_aoe_pull", {
        -- Gather phase: tag mobs with fire blast until we have enough
        BT.sequence("gather_phase", {
            BT.condition("gcd_ready_gather", Cond.gcd_ready),
            BT.condition("need_more_mobs", function(bb)
                local gathered = tonumber(bb:get("module.grind.aoe_gathered_count", 0)) or 0
                local target_count = tonumber(bb:get("module.grind.aoe_target_count", 3)) or 3
                return gathered < target_count
            end),
            BT.condition("fire_blast_ready", Cond.spell_ready("fire_blast")),
            BT.action("queue_fire_blast", Act.queue_fire_blast),
        }),
        -- Nova and blink: freeze when mobs reach melee, then blink out
        BT.sequence("nova_and_blink", {
            BT.condition("gcd_ready_nova", Cond.gcd_ready),
            BT.condition("enemies_in_melee_2", Cond.enemies_in_melee(2)),
            BT.condition("frost_nova_ready", Cond.spell_ready("frost_nova")),
            BT.action("queue_frost_nova", Act.queue_frost_nova),
            -- Blink is best-effort: wrap in selector with noop fallback
            BT.selector("try_blink", {
                BT.sequence("blink_if_ready", {
                    BT.condition("blink_ready", Cond.spell_ready("blink")),
                    BT.action("queue_blink", Act.queue_blink),
                }),
                BT.action("blink_skip", function()
                    return Status.SUCCESS
                end),
            }),
        }),
        -- Blizzard the frozen pack
        BT.sequence("blizzard_pack", {
            BT.condition("gcd_ready_blizzard", Cond.gcd_ready),
            BT.condition("level_at_least_20", Cond.level_at_least(20)),
            BT.condition("blizzard_ready", Cond.spell_ready("blizzard")),
            BT.action("queue_blizzard", Act.queue_blizzard),
        }),
        -- Re-freeze when mobs close in again
        BT.sequence("re_freeze", {
            BT.condition("gcd_ready_refreeze", Cond.gcd_ready),
            BT.condition("enemies_in_melee_1", Cond.enemies_in_melee(1)),
            BT.selector("freeze_options", {
                BT.sequence("cone_of_cold", {
                    BT.condition("cone_of_cold_ready", Cond.spell_ready("cone_of_cold")),
                    BT.action("queue_cone_of_cold", Act.queue_cone_of_cold),
                }),
                BT.sequence("frost_nova_refreeze", {
                    BT.condition("frost_nova_ready_refreeze", Cond.spell_ready("frost_nova")),
                    BT.action("queue_frost_nova_refreeze", Act.queue_frost_nova),
                }),
            }),
        }),
        -- Emergency escape when low health
        BT.sequence("emergency_escape", {
            BT.condition("health_below_25", Cond.health_below(0.25)),
            BT.selector("escape_tools", {
                BT.sequence("ice_block_escape", {
                    BT.condition("ice_block_ready", Cond.spell_ready("ice_block")),
                    BT.action("queue_ice_block", Act.queue_ice_block),
                }),
                BT.sequence("blink_escape", {
                    BT.condition("blink_escape_ready", Cond.spell_ready("blink")),
                    BT.action("queue_blink_escape", Act.queue_blink),
                }),
            }),
        }),
    })
end

return AoeTree
