-- sentinel/modules/quest/profile_actions.lua
-- Core Action Registry: Stable engine action API for profiles

local CoreActions = {}
CoreActions.__index = CoreActions

-- Build action implementations using provided engine subsystems
local function build_actions(engine, nav, combat, consume, vendor, loot, quest, trainer, movement)
    return {
        -- Navigation
        ["nav.followPolicy"] = function(ctx, policyName)
            -- Use QueryClient to send followPolicy request to NavServer
            return ctx.engine.query:followPolicy(policyName, ctx.profile.goal)
        end,
        ["nav.cancel"] = function(ctx)
            return ctx.engine.query:cancelNavigation()
        end,

        -- Combat
        ["combat.setTargetFilter"] = function(ctx, npcIds)
            return ctx.engine.combat:setTargetFilter(npcIds)
        end,
        ["combat.clearTargetFilter"] = function(ctx)
            return ctx.engine.combat:clearTargetFilter()
        end,
        ["combat.engage"] = function(ctx, targetGUID)
            return ctx.engine.combat:engage(targetGUID)
        end,

        -- Interaction
        ["interact.acceptQuest"] = function(ctx, questId, npcId)
            return ctx.engine:acceptQuest(questId, npcId)
        end,
        ["interact.turnInQuest"] = function(ctx, questId, rewardIndex)
            return ctx.engine:turnInQuest(questId, rewardIndex)
        end,
        ["interact.bindHearthstone"] = function(ctx, npcId)
            return ctx.engine:bindHearthstone(npcId)
        end,

        -- Quest convenience actions (profile-level helpers)
        ["quest.acceptAllQuestsAtNpc"] = function(ctx, npcId)
            return ctx.engine:acceptAllQuestsAtNpc(npcId)
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

        -- Consumables
        ["consume.useFood"] = function(ctx)
            return ctx.engine.consume:useFood()
        end,
        ["consume.useWater"] = function(ctx)
            return ctx.engine.consume:useWater()
        end,
        ["consume.useBandage"] = function(ctx)
            return ctx.engine.consume:useBandage()
        end,
        ["consume.stop"] = function(ctx)
            return ctx.engine.consume:stop()
        end,

        -- Vendor
        ["vendor.sellJunk"] = function(ctx)
            return ctx.engine.vendor:sellJunk()
        end,
        ["vendor.repair"] = function(ctx)
            return ctx.engine.vendor:repair()
        end,
        ["vendor.buyConsumables"] = function(ctx, list)
            return ctx.engine.vendor:buyConsumables(list)
        end,

        -- Trainer
        ["trainer.trainAvailable"] = function(ctx)
            return ctx.engine.trainer:trainAvailable()
        end,

        -- Loot
        ["loot.lootAll"] = function(ctx)
            return ctx.engine.loot:lootAll()
        end,

        -- Movement
        ["movement.mount"] = function(ctx)
            return ctx.engine.movement:mount()
        end,
        ["movement.dismount"] = function(ctx)
            return ctx.engine.movement:dismount()
        end,

        -- Core logging
        ["core.log"] = function(ctx, message)
            if core and core.log then
                core.log("[Profile] " .. message)
            end
            return true
        end,
        ["core.logError"] = function(ctx, message)
            if core and core.log_error then
                core.log_error("[Profile] " .. message)
            end
            return true
        end,
    }
end

function CoreActions.new(engine, nav, combat, consume, vendor, loot, quest, trainer, movement)
    return setmetatable({
        _actions = build_actions(engine, nav, combat, consume, vendor, loot, quest, trainer, movement),
        _signatures = {
            ["nav.followPolicy"] = {params = {"policyName"}, doc = "Start dynamic navigation using routing policy"},
            ["nav.cancel"] = {params = {}, doc = "Cancel current navigation"},
            ["combat.setTargetFilter"] = {params = {"npcIds"}, doc = "Restrict combat targets to listed NPC IDs"},
            ["combat.clearTargetFilter"] = {params = {}, doc = "Remove combat target filter"},
            ["combat.engage"] = {params = {"targetGUID?"}, doc = "Start combat rotation"},
            ["interact.acceptQuest"] = {params = {"questId", "npcId"}, doc = "Accept quest from NPC"},
            ["interact.turnInQuest"] = {params = {"questId", "rewardIndex?"}, doc = "Turn in completed quest"},
            ["interact.bindHearthstone"] = {params = {"npcId"}, doc = "Bind hearthstone at innkeeper"},
            ["quest.acceptAllQuestsAtNpc"] = {params = {"npcId"}, doc = "Accept all available quests at NPC"},
            ["quest.turnInQuest"] = {params = {"questId", "rewardIndex?"}, doc = "Turn in completed quest"},
            ["quest.getAvailableQuests"] = {params = {"npcId"}, doc = "Get quests offered by NPC"},
            ["engine.selectBestReward"] = {params = {"questId", "class"}, doc = "Choose optimal quest reward"},
            ["consume.useFood"] = {params = {}, doc = "Eat to restore health"},
            ["consume.useWater"] = {params = {}, doc = "Drink to restore mana"},
            ["consume.useBandage"] = {params = {}, doc = "Apply bandage"},
            ["consume.stop"] = {params = {}, doc = "Stop eating/drinking/bandaging"},
            ["vendor.sellJunk"] = {params = {}, doc = "Sell gray items at vendor"},
            ["vendor.repair"] = {params = {}, doc = "Repair all equipped items"},
            ["vendor.buyConsumables"] = {params = {"list"}, doc = "Buy consumables from vendor"},
            ["trainer.trainAvailable"] = {params = {}, doc = "Learn all available spells"},
            ["loot.lootAll"] = {params = {}, doc = "Loot all items from current target"},
            ["movement.mount"] = {params = {}, doc = "Mount up"},
            ["movement.dismount"] = {params = {}, doc = "Dismount"},
            ["core.log"] = {params = {"message"}, doc = "Debug log message"},
            ["core.logError"] = {params = {"message"}, doc = "Error log message"},
        },
    }, CoreActions)
end

function CoreActions:validate(name)
    return self._actions[name] ~= nil
end

function CoreActions:get(name)
    return self._actions[name]
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