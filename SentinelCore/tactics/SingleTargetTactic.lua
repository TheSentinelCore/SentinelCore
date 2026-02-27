local Tactic = require("ai/Tactic")
local BT = require("ai/BehaviorTree")

local SingleTargetTactic = {}
SingleTargetTactic.__index = SingleTargetTactic
setmetatable(SingleTargetTactic, { __index = Tactic })

function SingleTargetTactic:new()
    local o = Tactic.new(self, {
        name = "single_target",

        preconditions = function(ctx)
            return true  -- always available as fallback
        end,

        utility = function(ctx, advisor)
            local base = 0.5
            local enemy_count = tonumber(ctx.enemy_count) or 0
            local mana_pct = tonumber(ctx.player_mana_pct) or 1.0

            -- Higher utility when only 1 mob or low mana (safe choice)
            if enemy_count <= 1 then base = 0.7 end
            if mana_pct < 0.20 then base = math.max(base, 0.8) end

            -- Lower utility when cluster detected and we could AoE
            local pack_count = tonumber(ctx.pack_count) or 0
            if pack_count >= 3 and mana_pct > 0.40 then
                base = base * 0.6
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
                    -- Delegates to PullService BT node via deps.pull_node
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
                name = "combat",
                enter_if = function(ctx)
                    return ctx.in_combat
                end,
                tick = function(ctx, deps)
                    -- Delegates to CombatService BT node via deps.combat_node
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
            drink_below = 0.30,
            eat_below = 0.50,
            drink_until = 0.80,
            eat_until = 0.90,
        },
        target_config = {
            prefer_clusters = false,
        },
        explore_config = {
            mode = "frontier",
        },
    })
    return o
end

return SingleTargetTactic
