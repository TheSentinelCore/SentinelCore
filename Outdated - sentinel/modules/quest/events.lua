-- sentinel/modules/quest/events.lua
-- Event name constants and payload builders for quest event system

local Events = {}

-- Event name constants (prefixed with "quest:")
Events.Names = {
    QuestAccepted = "quest:QuestAccepted",
    QuestCompleted = "quest:QuestCompleted",
    QuestTurnedIn = "quest:QuestTurnedIn",
    QuestFailed = "quest:QuestFailed",
    ObjectiveProgress = "quest:ObjectiveProgress",
    InventoryChanged = "quest:InventoryChanged",
    DurabilityChanged = "quest:DurabilityChanged",
    PlayerDied = "quest:PlayerDied",
    PlayerResurrected = "quest:PlayerResurrected",
    CombatStart = "quest:CombatStart",
    CombatEnd = "quest:CombatEnd",
    LootReady = "quest:LootReady",
    LevelUp = "quest:LevelUp",
    SkillUp = "quest:SkillUp",
    ReputationChanged = "quest:ReputationChanged",
    ZoneChanged = "quest:ZoneChanged",
    HearthstoneReady = "quest:HearthstoneReady",
    FlightPathDiscovered = "quest:FlightPathDiscovered",
    RareSeen = "quest:RareSeen",
    EliteSeen = "quest:EliteSeen",
    PlayerNearby = "quest:PlayerNearby",
    Stuck = "quest:Stuck",
    NavigationArrived = "quest:NavigationArrived",
    NavigationFailed = "quest:NavigationFailed",
    NavigationReplanned = "quest:NavigationReplanned",
    VendorDone = "quest:VendorDone",
    RepairDone = "quest:RepairDone",
    TrainDone = "quest:TrainDone",
    ProfileStart = "quest:ProfileStart",
    ProfileEvent = "quest:ProfileEvent",
}

-- Payload builders
Events.Payloads = {}

function Events.Payloads.QuestAccepted(questId, title, level)
    return {questId = questId, title = title, level = level}
end

function Events.Payloads.QuestCompleted(questId)
    return {questId = questId}
end

function Events.Payloads.QuestTurnedIn(questId, rewardChoice)
    return {questId = questId, rewardChoice = rewardChoice}
end

function Events.Payloads.QuestFailed(questId, reason)
    return {questId = questId, reason = reason}
end

function Events.Payloads.ObjectiveProgress(questId, objectiveIndex, current, required)
    return {questId = questId, objectiveIndex = objectiveIndex, current = current, required = required}
end

function Events.Payloads.InventoryChanged(freeSlots, totalSlots)
    return {freeSlots = freeSlots, totalSlots = totalSlots}
end

function Events.Payloads.DurabilityChanged(slot, current, max, pct)
    return {slot = slot, current = current, max = max, pct = pct}
end

function Events.Payloads.PlayerDied(mapId, x, y, z)
    return {mapId = mapId, x = x, y = y, z = z}
end

function Events.Payloads.PlayerResurrected(mapId, x, y, z)
    return {mapId = mapId, x = x, y = y, z = z}
end

function Events.Payloads.CombatStart(targetGUID)
    return {targetGUID = targetGUID}
end

function Events.Payloads.CombatEnd(targetGUID)
    return {targetGUID = targetGUID}
end

function Events.Payloads.LootReady(targetGUID, items)
    return {targetGUID = targetGUID, items = items}
end

function Events.Payloads.LevelUp(newLevel)
    return {newLevel = newLevel}
end

function Events.Payloads.SkillUp(skill, newValue)
    return {skill = skill, newValue = newValue}
end

function Events.Payloads.ReputationChanged(faction, standing)
    return {faction = faction, standing = standing}
end

function Events.Payloads.ZoneChanged(newZone, newMapId)
    return {newZone = newZone, newMapId = newMapId}
end

function Events.Payloads.HearthstoneReady(cooldownRemaining)
    return {cooldownRemaining = cooldownRemaining}
end

function Events.Payloads.FlightPathDiscovered(nodeId, name)
    return {nodeId = nodeId, name = name}
end

function Events.Payloads.RareSeen(npcId, name, x, y, z)
    return {npcId = npcId, name = name, x = x, y = y, z = z}
end

function Events.Payloads.EliteSeen(npcId, name, x, y, z)
    return {npcId = npcId, name = name, x = x, y = y, z = z}
end

function Events.Payloads.PlayerNearby(name, distance, isGM)
    return {name = name, distance = distance, isGM = isGM}
end

function Events.Payloads.Stuck(x, y, z, duration)
    return {x = x, y = y, z = z, duration = duration}
end

function Events.Payloads.NavigationArrived(policy, success)
    return {policy = policy, success = success}
end

function Events.Payloads.NavigationFailed(policy, reason)
    return {policy = policy, reason = reason}
end

function Events.Payloads.NavigationReplanned(policy, oldWaypoints, newWaypoints)
    return {policy = policy, oldWaypoints = oldWaypoints, newWaypoints = newWaypoints}
end

function Events.Payloads.VendorDone()
    return {}
end

function Events.Payloads.RepairDone()
    return {}
end

function Events.Payloads.TrainDone()
    return {}
end

function Events.Payloads.ProfileStart(profileId)
    return {profileId = profileId}
end

function Events.Payloads.ProfileEvent(eventName, payload)
    return {eventName = eventName, payload = payload}
end

-- Event detector interface
Events.Detector = {}
Events.Detector.__index = Events.Detector

function Events.Detector.new(eventBus, blackboard, engine)
    return setmetatable({
        _eventBus = eventBus,
        _blackboard = blackboard,
        _engine = engine,
        _prevState = {},
    }, Events.Detector)
end

function Events.Detector:update()
    local now = self._blackboard:get("system.now_ms", 0)
    
    -- Track quest log changes
    self:_detectQuestEvents()
    
    -- Track inventory changes
    self:_detectInventoryChanges()
    
    -- Track durability changes
    self:_detectDurabilityChanges()
    
    -- Track player state (level, health, position, etc.)
    self:_detectPlayerStateChanges()
    
    -- Track combat state
    self:_detectCombatChanges()
    
    -- Track zone/map changes
    self:_detectZoneChanges()
    
    -- Track stuck detection
    self:_detectStuck()
end

function Events.Detector:_publish(eventName, payload)
    self._eventBus:publish(eventName, payload)
end

function Events.Detector:_detectQuestEvents()
    -- Quest log tracking
    local quests = self._blackboard:get("module.quest.quests", {}) or {}
    local prevQuests = self._prevState.quests or {}
    
    -- Detect new quests (accepted)
    if type(quests) == "table" then
        for questId, quest in pairs(quests) do
            if type(quest) == "table" and not prevQuests[questId] then
                self:_publish(Events.Names.QuestAccepted, {
                    questId = questId,
                    title = quest.title,
                    level = quest.level
                })
            end
        end
    end
    
    -- Detect completed/turned in quests
    if type(prevQuests) == "table" then
        for questId, prevQuest in pairs(prevQuests) do
            if type(prevQuest) == "table" and not quests[questId] then
                -- Quest no longer in log - could be turned in or abandoned
                if prevQuest.is_complete then
                    self:_publish(Events.Names.QuestTurnedIn, {
                        questId = questId,
                        rewardChoice = prevQuest.rewardChoice or 0
                    })
                else
                    self:_publish(Events.Names.QuestFailed, {
                        questId = questId,
                        reason = "abandoned"
                    })
                end
            end
        end
    end
    
    -- Detect objective progress
    if type(quests) == "table" and type(prevQuests) == "table" then
        for questId, quest in pairs(quests) do
            if type(quest) == "table" then
                local prevQuest = prevQuests[questId]
                if type(prevQuest) == "table" and quest.objectives and prevQuest.objectives then
                    for i, obj in ipairs(quest.objectives) do
                        local prevObj = prevQuest.objectives[i]
                        if prevObj and obj.current ~= prevObj.current then
                            self:_publish(Events.Names.ObjectiveProgress, {
                                questId = questId,
                                objectiveIndex = i,
                                current = obj.current,
                                required = obj.required
                            })
                        end
                    end
                end
            end
        end
    end
    
    self._prevState.quests = quests
end

function Events.Detector:_detectInventoryChanges()
    -- Bag slot tracking
    local freeSlots = 0
    local totalSlots = 0
    
    -- Get bag info from blackboard (assuming it's tracked)
    local bagData = self._blackboard:get("player.bags", {}) or {}
    if type(bagData) == "table" then
        for _, bag in pairs(bagData) do
            if type(bag) == "table" then
                freeSlots = freeSlots + (bag.free or 0)
                totalSlots = totalSlots + (bag.total or 0)
            end
        end
    end
    
    local prev = self._prevState.inventory or {freeSlots = -1, totalSlots = -1}
    if freeSlots ~= prev.freeSlots or totalSlots ~= prev.totalSlots then
        self:_publish(Events.Names.InventoryChanged, {
            freeSlots = freeSlots,
            totalSlots = totalSlots
        })
        self._prevState.inventory = {freeSlots = freeSlots, totalSlots = totalSlots}
    end
end

function Events.Detector:_detectDurabilityChanges()
    -- Equipment durability tracking
    local items = self._blackboard:get("player.equipment", {}) or {}
    for slot, item in pairs(items) do
        if item.maxDurability and item.maxDurability > 0 then
            local pct = math.floor((item.durability / item.maxDurability) * 100)
            local key = "durability_" .. slot
            local prev = self._prevState[key] or {pct = -1}
            if pct ~= prev.pct then
                self:_publish(Events.Names.DurabilityChanged, {
                    slot = slot,
                    current = item.durability,
                    max = item.maxDurability,
                    pct = pct
                })
                self._prevState[key] = {pct = pct}
            end
        end
    end
end

function Events.Detector:_detectPlayerStateChanges()
    -- Level up
    local level = self._blackboard:get("player.level", 1)
    local prevLevel = self._prevState.level or 1
    if level > prevLevel then
        self:_publish(Events.Names.LevelUp, {newLevel = level})
        self._prevState.level = level
    end
    
    -- Health/mana for eating/drinking triggers
    local healthPct = self._blackboard:get("player.healthPct", 100)
    local prevHealth = self._prevState.healthPct or 100
    if healthPct ~= prevHealth then
        self._blackboard:set("event.healthPct", healthPct) -- for reactive bindings
        self._prevState.healthPct = healthPct
    end
    
    -- Mana
    local manaPct = self._blackboard:get("player.manaPct", 100)
    local prevMana = self._prevState.manaPct or 100
    if manaPct ~= prevMana then
        self._prevState.manaPct = manaPct
    end
end

function Events.Detector:_detectCombatChanges()
    -- Combat state tracking
    local inCombat = self._blackboard:get("player.inCombat", false)
    local prevCombat = self._prevState.inCombat or false
    if inCombat ~= prevCombat then
        if inCombat then
            local targetGUID = self._blackboard:get("player.targetGUID", "")
            self:_publish(Events.Names.CombatStart, {targetGUID = targetGUID})
        else
            local targetGUID = self._blackboard:get("player.lastTargetGUID", "")
            self:_publish(Events.Names.CombatEnd, {targetGUID = targetGUID})
        end
        self._prevState.inCombat = inCombat
    end
    
    -- Loot ready
    local hasLoot = self._blackboard:get("player.hasLoot", false)
    local prevLoot = self._prevState.hasLoot or false
    if hasLoot ~= prevLoot and hasLoot then
        local targetGUID = self._blackboard:get("player.lootTargetGUID", "")
        local items = self._blackboard:get("player.lootItems", {})
        self:_publish(Events.Names.LootReady, {targetGUID = targetGUID, items = items})
    end
    self._prevState.hasLoot = hasLoot
end

function Events.Detector:_detectZoneChanges()
    local mapId = self._blackboard:get("system.map_id", 0)
    local zone = self._blackboard:get("system.zone_name", "Unknown")
    local prevMap = self._prevState.mapId or 0
    local prevZone = self._prevState.zone or "Unknown"
    
    if mapId ~= prevMap then
        self:_publish(Events.Names.ZoneChanged, {newZone = zone, newMapId = mapId})
        self._prevState.mapId = mapId
        self._prevState.zone = zone
    end
end

function Events.Detector:_detectStuck()
    local pos = self._blackboard:get("player.position")
    if pos then
        local prevPos = self._prevState.position
        local prevTime = self._prevState.positionTime or 0
        local now = self._blackboard:get("system.now_ms", 0)
        
        if prevPos then
            local dist = math.sqrt(
                (pos.x - prevPos.x)^2 + 
                (pos.y - prevPos.y)^2 + 
                (pos.z - prevPos.z)^2
            )
            if dist < 0.5 then
                if now - prevTime > 30000 then -- 30 seconds
                    self:_publish(Events.Names.Stuck, {
                        x = pos.x, y = pos.y, z = pos.z,
                        duration = now - prevTime
                    })
                    -- Reset timer to prevent event storm
                    self._prevState.positionTime = now
                end
            else
                self._prevState.positionTime = now
            end
        else
            -- First position reading - initialize timer
            self._prevState.positionTime = now
        end
        self._prevState.position = {x = pos.x, y = pos.y, z = pos.z}
    end
end

return Events