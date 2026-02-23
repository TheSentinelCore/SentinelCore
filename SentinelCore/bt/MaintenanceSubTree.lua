local BT = require("ai/BehaviorTree")
local S = BT.Status

local MaintenanceSubTree = {}

function MaintenanceSubTree.build(bb)
    return BT.Sequence:new("maintenance", {
        -- Gate: not in combat
        BT.Condition:new("not_in_combat", function()
            return not bb:get("player.in_combat", false)
        end),

        -- Check and refresh buffs
        BT.Action:new("ensure_buffs", function()
            -- Check if missing critical buffs
            local needs_buff = bb:get("player.needs_aura", false)
                or bb:get("player.needs_blessing", false)
                or bb:get("player.needs_seal", false)

            if not needs_buff then
                return S.FAILURE  -- nothing to maintain, let tree continue
            end

            -- Apply buffs (Sensors populates which buffs are missing)
            if bb:get("player.needs_aura", false) and core.input then
                pcall(function() core.input.cast_self_spell(20218) end)  -- Sanctity Aura
                return S.SUCCESS
            end

            if bb:get("player.needs_blessing", false) and core.input then
                pcall(function() core.input.cast_self_spell(27140) end)  -- BoM R8
                return S.SUCCESS
            end

            if bb:get("player.needs_seal", false) and core.input then
                pcall(function() core.input.cast_self_spell(31892) end)  -- SoB
                return S.SUCCESS
            end

            return S.FAILURE
        end),
    })
end

return MaintenanceSubTree
