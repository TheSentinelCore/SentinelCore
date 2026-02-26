local Tactic = require("ai/Tactic")
local BT = require("ai/BehaviorTree")

local AoEKiteTactic = {}
AoEKiteTactic.__index = AoEKiteTactic
setmetatable(AoEKiteTactic, { __index = Tactic })

function AoEKiteTactic:new()
    local o = Tactic.new(self, {
        name = "aoe_kite",

        preconditions = function(ctx)
            local pack_count = tonumber(ctx.pack_count) or 0
            local mana_pct = tonumber(ctx.player_mana_pct) or 0
            return pack_count >= 3 and mana_pct > 0.25
        end,

        utility = function(ctx, advisor)
            local base = 0.4
            local pack_count = tonumber(ctx.pack_count) or 0
            local mana_pct = tonumber(ctx.player_mana_pct) or 1.0

            if pack_count >= 5 then
                base = 0.85
            elseif pack_count >= 4 then
                base = 0.75
            elseif pack_count >= 3 then
                base = 0.65
            end

            if mana_pct < 0.35 then
                base = base * 0.5
            elseif mana_pct < 0.50 then
                base = base * 0.75
            end

            return base
        end,

        phases = {
            {
                name = "engage",
                enter_if = function(ctx)
                    return ctx.has_target and not ctx.in_combat
                end,
                tick = function(ctx, deps)
                    if deps.pull_node then
                        return deps.pull_node:tick()
                    end
                    return BT.Status.FAILURE
                end,
                exit_if = function(ctx)
                    return ctx.in_combat
                end,
            },
            {
                name = "aoe_combat",
                enter_if = function(ctx)
                    return ctx.in_combat
                end,
                tick = function(ctx, deps)
                    if deps.combat_node then
                        return deps.combat_node:tick()
                    end
                    return BT.Status.FAILURE
                end,
                exit_if = function(ctx)
                    return not ctx.in_combat and not ctx.target_alive
                end,
            },
        },

        rest_config = {
            drink_below = 0.40,
            eat_below = 0.60,
            drink_until = 0.90,
            eat_until = 0.90,
        },
        target_config = {
            prefer_clusters = true,
        },
        explore_config = {
            mode = "cluster_seek",
        },
    })
    return o
end

return AoEKiteTactic
