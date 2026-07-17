-- sentinel/modules/quest/core_actions.lua
-- CoreActionRegistry: Stable engine action API for profiles

local CoreActions = {}
CoreActions.__index = CoreActions

-- Action signatures for validation
local SIGNATURES = {
    ["nav.followPolicy"] = {params = {"policyName"}, doc = "Start dynamic navigation using routing policy"},
    ["nav.cancel"] = {params = {}, doc = "Cancel current navigation"},
    ["combat.setTargetFilter"] = {params = {"npcIds"}, doc = "Restrict combat targets to listed NPC IDs"},
    ["combat.clearTargetFilter"] = {params = {}, doc = "Remove combat target filter"},
    ["combat.engage"] = {params = {"targetGUID?"}, doc = "Start combat rotation"},
    ["consume.useFood"] = {params = {}, doc = "Eat to restore health"},
    ["consume.useWater"] = {params = {}, doc = "Drink to restore mana"},
    ["consume.stop"] = {params = {}, doc = "Stop eating/drinking"},
    ["vendor.sellJunk"] = {params = {}, doc = "Sell gray items at vendor"},
    ["vendor.repair"] = {params = {}, doc = "Repair all equipped items"},
    ["vendor.buyConsumables"] = {params = {"list"}, doc = "Buy food/water/ammo from vendor"},
    ["loot.lootAll"] = {params = {}, doc = "Loot all items from current target"},
    ["quest.acceptQuest"] = {params = {"questId"}, doc = "Accept quest from NPC"},
    ["quest.turnInQuest"] = {params = {"questId", "rewardIndex?"}, doc = "Turn in completed quest"},
    ["quest.getAvailableQuests"] = {params = {"npcId"}, doc = "Get quests offered by NPC"},
    ["engine.selectBestReward"] = {params = {"questId", "class"}, doc = "Choose optimal quest reward"},
    ["core.log"] = {params = {"message"}, doc = "Debug log"},
    ["core.logError"] = {params = {"message"}, doc = "Error log"},
}

-- Build action implementations
local function build_actions(engine, nav, combat, consume, vendor, loot, quest)
    return {
        ["nav.followPolicy"] = function(ctx, policyName)
            return ctx.engine.nav:followPolicy(policyName)
        end,
        ["nav.cancel"] = function(ctx)
            return ctx.engine.nav:cancel()
        end,
        ["combat.setTargetFilter"] = function(ctx, npcIds)
            return ctx.engine.combat:setTargetFilter(npcIds)
        end,
        ["combat.clearTargetFilter"] = function(ctx)
            return ctx.engine.combat:clearTargetFilter()
        end,
        ["combat.engage"] = function(ctx, targetGUID)
            return ctx.engine.combat:engage(targetGUID)
        end,
        ["consume.useFood"] = function(ctx)
            return ctx.engine.consume:useFood()
        end,
        ["consume.useWater"] = function(ctx)
            return ctx.engine.consume:useWater()
        end,
        ["consume.stop"] = function(ctx)
            return ctx.engine.consume:stop()
        end,
        ["vendor.sellJunk"] = function(ctx)
            return ctx.engine.vendor:sellJunk()
        end,
        ["vendor.repair"] = function(ctx)
            return ctx.engine.vendor:repair()
        end,
        ["vendor.buyConsumables"] = function(ctx, list)
            return ctx.engine.vendor:buyConsumables(list)
        end,
        ["loot.lootAll"] = function(ctx)
            return ctx.engine.loot:lootAll()
        end,
        ["quest.acceptQuest"] = function(ctx, questId)
            return ctx.engine:acceptQuest(questId)
        end,
        ["quest.turnInQuest"] = function(ctx, questId, rewardIndex)
            return ctx.engine:turnInQuest(questId, rewardIndex)
        end,
        ["quest.getAvailableQuests"] = function(ctx, npcId)
            return ctx.engine:getAvailableQuestsAtNpc(npcId)
        end,
        ["engine.selectBestReward"] = function(ctx, questId, class)
            return ctx.engine:selectBestReward(questId, class)
        end,
        ["core.log"] = function(ctx, message)
            if core and core.log then core.log("[Profile] " .. message) end
            return true
        end,
        ["core.logError"] = function(ctx, message)
            if core and core.log_error then core.log_error("[Profile] " .. message) end
            return true
        end,
    }
end

function CoreActions.new(engine, nav, combat, consume, vendor, loot, quest)
    local self = setmetatable({
        _actions = build_actions(engine, nav, combat, consume, vendor, loot, quest),
        _signatures = SIGNATURES,
    }, CoreActions)
    
    -- Allow direct indexing: coreActions["nav.followPolicy"]
    getmetatable(self).__index = self._actions
    
    return self
end

function CoreActions:validate(name)
    if self._signatures[name] then
        return true, nil
    end
    return false, "Unknown core action: " .. name .. ". Available: " .. table.concat(self:all_names(), ", ")
end

function CoreActions:get(name)
    return self._actions[name], self._signatures[name]
end

function CoreActions:all()
    return self._actions
end

function CoreActions:all_names()
    local names = {}
    for name in pairs(self._signatures) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function CoreActions:call(name, ctx, ...)
    local action = self._actions[name]
    if not action then
        return false, "Action not found: " .. name
    end
    local ok, result = pcall(action, ctx, ...)
    if not ok then
        return false, "Action error: " .. tostring(result)
    end
    return true, result
end

return CoreActions