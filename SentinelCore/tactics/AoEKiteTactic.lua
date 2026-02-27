local Tactic = require("ai/Tactic")
local BT = require("ai/BehaviorTree")

local AoEKiteTactic = {}
AoEKiteTactic.__index = AoEKiteTactic
setmetatable(AoEKiteTactic, { __index = Tactic })

-- Anti-detection: pack threshold varies between 3-4, re-rolls periodically
local _pack_threshold = 3
local _threshold_next_reroll = 0

function AoEKiteTactic:new()
    local o = Tactic.new(self, {
        name = "aoe_kite",

        preconditions = function(ctx)
            local pack_count = tonumber(ctx.pack_count) or 0
            local mana_pct = tonumber(ctx.player_mana_pct) or 0
            local level = tonumber(ctx.player_level) or 0

            -- Level gate: need AoE spells (Blizzard available ~20)
            if level < 20 then return false end

            -- Vary pack threshold for anti-detection (3 or 4)
            local now = os.clock and os.clock() or 0
            if now >= _threshold_next_reroll then
                _pack_threshold = 3 + (math.random() < 0.35 and 1 or 0)
                _threshold_next_reroll = now + 45 + math.random() * 30
            end

            return pack_count >= _pack_threshold and mana_pct > 0.25
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
