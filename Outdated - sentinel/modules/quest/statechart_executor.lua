-- sentinel/modules/quest/statechart_executor.lua
-- StatechartExecutor: Hierarchical event-driven state machine runtime for quest profiles

local function get_keys(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    return keys
end

local StatechartExecutor = {}
StatechartExecutor.__index = StatechartExecutor

function StatechartExecutor.new(compiledProfile, context)
    local self = setmetatable({
        _compiled = compiledProfile,
        _context = context or {},
        _activeStates = {},      -- regionName -> stateId (leaf)
        _stateStack = {},        -- regionName -> {stateId1, stateId2, ...} (for history)
        _history = {},           -- compoundStateId -> {regionName -> lastActiveLeaf}
        _runningActions = {},    -- stateId -> {coroutine1, coroutine2, ...}
        _subscriptions = {},     -- stateId -> {subscriptionId1, subscriptionId2, ...} for cleanup
        _variableStore = {},     -- profile variables with bind expressions
        _started = false,
        _stopped = false,
    }, StatechartExecutor)
    
    -- Initialize variable store from compiled profile
    self:_initVariables()
    
    return self
end

function StatechartExecutor:_initVariables()
    local variables = self._compiled.variables or {}
    for varName, varDef in pairs(variables) do
        if varDef.init ~= nil then
            self._variableStore[varName] = varDef.init
        elseif varDef.type == "number" then
            self._variableStore[varName] = 0
        elseif varDef.type == "string" then
            self._variableStore[varName] = ""
        elseif varDef.type == "boolean" then
            self._variableStore[varName] = false
        end
    end
end

function StatechartExecutor:start()
    if self._started then return end
    self._started = true
    
    -- Enter initial state of each parallel region
    local regions = self._compiled.regions or {}
    for regionName, region in pairs(regions) do
        local initialState = region.initial
        if initialState then
            self:_enterState(regionName, initialState, {})
        end
    end
    
    -- Run onEnter actions for all entered states
    self:_runEnterActions()
end

function StatechartExecutor:stop()
    self._stopped = true
    self:_cancelAllActions()
    self._activeStates = {}
    self._stateStack = {}
    self._history = {}
end

function StatechartExecutor:handleEvent(eventName, payload)
    if self._stopped then return {handled = false} end
    if not self._started then return {handled = false} end
    
    -- Create event object
    local event = {
        name = eventName,
        payload = payload or {},
        timestamp = self._context.getTime and self._context.getTime() or 0
    }
    
    -- Update variable bindings (reactive)
    self:_updateBoundVariables()
    
    -- Collect all currently active leaf states (one per region)
    local activeLeaves = {}
    for regionName, stateId in pairs(self._activeStates) do
        table.insert(activeLeaves, {region = regionName, stateId = stateId})
    end
    
    -- Sort by depth (innermost first) for proper transition priority
    table.sort(activeLeaves, function(a, b)
        local depthA = self:_getStateDepth(a.stateId)
        local depthB = self:_getStateDepth(b.stateId)
        return depthA > depthB
    end)
    
    -- Evaluate transitions from innermost to outermost
    for _, leaf in ipairs(activeLeaves) do
        local stateId = leaf.stateId
        local state = self._compiled.states[stateId]
        
        print("DEBUG: Checking transitions for state " .. stateId .. " on event " .. eventName)
        if state and state.transitions then
            print("DEBUG: Available transitions: " .. table.concat(get_keys(state.transitions), ", "))
        end
        
        if state and state.transitions and state.transitions[eventName] then
            print("DEBUG: Found transitions for event " .. eventName .. " in state " .. stateId)
            for _, trans in ipairs(state.transitions[eventName]) do
                local guardPassed = true
                if trans.guard_fn then
                    local ok, result = pcall(trans.guard_fn, event.payload, self._context.bb, self._variableStore, state)
                    if not ok then
                        if self._context.logError then
                            self._context.logError("Guard error in " .. stateId .. ": " .. tostring(result))
                        end
                        guardPassed = false
                    else
                        guardPassed = result == true
                    end
                end
                
                if guardPassed then
                    return self:_executeTransition(stateId, trans, event)
                else
                    self:_publish("statechart:guard_failed", {
                        state = stateId,
                        event = eventName,
                        transition = trans.target,
                        region = state.region
                    })
                end
            end
        end
    end
    
    return {handled = false}
end

function StatechartExecutor:_executeTransition(fromStateId, transition, event)
    local targetStateId = transition.target
    local fromState = self._compiled.states[fromStateId]
    local toState = self._compiled.states[targetStateId]
    
    if not toState then
        if self._context.logError then
            self._context.logError("Transition target not found: " .. targetStateId)
        end
        return {handled = false, error = "target not found"}
    end
    
    local fromRegion = fromState and fromState.region or "?"
    local toRegion = toState and toState.region or "?"
    
    -- Exit source state (and ancestors up to LCA)
    local lca = self:_findLCA(fromStateId, targetStateId)
    self:_exitStateHierarchy(fromStateId, lca)
    
    -- Execute transition actions
    if transition.actions then
        self:_runActions(transition.actions, {event = event})
    end
    
    -- Enter target state (and ancestors down from LCA)
    self:_enterStateHierarchy(targetStateId, lca)
    
    -- Run entry actions for newly entered states
    self:_runEnterActions()
    
    -- Publish transition event for UI
    self._context.eventBus:publish("statechart:transition", {
        from = fromStateId,
        to = targetStateId,
        event = event.name,
        region = fromRegion,
        guard = transition.guard_fn and "passed" or "none"
    })
    
    -- Check for ProfileComplete
    if toState.type == "final" and self:_isInQuestingRegion(targetStateId) then
        self:_publish("ProfileComplete", {profile = self._compiled.profile.id})
        self:stop()
    end
    
    return {
        handled = true,
        from = fromStateId,
        to = targetStateId,
        event = event.name
    }
end

function StatechartExecutor:_publish(eventName, payload)
    if self._context and self._context.eventBus and self._context.eventBus.publish then
        self._context.eventBus:publish(eventName, payload)
    end
end

function StatechartExecutor:_findLCA(stateId1, stateId2)
    -- Find lowest common ancestor in state hierarchy
    local ancestors1 = {}
    local s1 = self._compiled.states[stateId1]
    while s1 do
        ancestors1[s1.id] = true
        s1 = s1.parent and self._compiled.states[s1.parent] or nil
    end
    
    local s2 = self._compiled.states[stateId2]
    while s2 do
        if ancestors1[s2.id] then
            return s2.id
        end
        s2 = s2.parent and self._compiled.states[s2.parent] or nil
    end
    
    return nil -- root
end

function StatechartExecutor:_exitStateHierarchy(fromStateId, lca)
    local stateId = fromStateId
    while stateId and stateId ~= lca do
        local state = self._compiled.states[stateId]
        if state then
            -- Cancel running actions
            self:_cancelStateActions(stateId)
            
            -- Run exit actions
            self:_runStateExitActions(stateId)
            
            -- Publish state exit event
            if state.region then
                self._context.eventBus:publish("statechart:event", {
                    name = "Exit:" .. stateId,
                    region = state.region,
                    state = stateId
                })
            end
            
            -- Update active state tracking
            if state.region then
                self._activeStates[state.region] = nil
            end
            
            stateId = state.parent
        else
            stateId = nil
        end
    end
    
    -- Save history for compound states we're exiting
    if lca then
        local lcaState = self._compiled.states[lca]
        if lcaState and lcaState.type == "compound" then
            self:_saveHistory(lca)
        end
    end
end

function StatechartExecutor:_enterStateHierarchy(targetStateId, lca)
    -- Build path from LCA to target
    local path = {}
    local stateId = targetStateId
    while stateId and stateId ~= lca do
        table.insert(path, 1, stateId)
        local state = self._compiled.states[stateId]
        if state then
            stateId = state.parent
        else
            stateId = nil
        end
    end
    
    -- Enter each state in path
    for _, stateId in ipairs(path) do
        local state = self._compiled.states[stateId]
        if state then
            -- Restore history for compound states
            if state.type == "compound" and self._history[stateId] then
                local history = self._history[stateId]
                for regionName, leafId in pairs(history) do
                    local leafState = self._compiled.states[leafId]
                    if leafState and leafState.region == regionName then
                        self:_enterState(regionName, leafId, {})
                    end
                end
            elseif state.type == "parallel" then
                -- Enter initial of each region
                local regions = self._compiled.regions[state.name] or state.regions
                if regions then
                    for regionName, region in pairs(regions) do
                        if region.initial then
                            self:_enterState(regionName, region.initial, {})
                        end
                    end
                end
            elseif state.type == "compound" or state.type == "exclusive" then
                -- Compound/Exclusive state: mark region entry, then descend to initial child
                -- Note: _enterState handles onEnter actions, but we need to descend first
                local regionName = state.region or self:_getRegionForState(stateId)
                local prevActive = self._activeStates[regionName]
                
                -- Push to stack and set as active (for history tracking)
                if not self._stateStack[regionName] then
                    self._stateStack[regionName] = {}
                end
                table.insert(self._stateStack[regionName], stateId)
                self._activeStates[regionName] = stateId
                
                -- Run onEnter actions
                if state.onEnter and #state.onEnter > 0 then
                    self:_runActions(state.onEnter, {currentStateId = stateId})
                end
                
                -- Recurse into initial child - this will overwrite _activeStates[regionName]
                -- with the actual leaf state, and run that leaf's onEnter
                if state.initial then
                    self:_enterStateHierarchy(state.initial, stateId)
                end
            else
                -- Atomic or final state - set as active leaf
                self:_enterState(state.region or self:_getRegionForState(stateId), stateId, {})
            end
        end
    end
end

function StatechartExecutor:_enterState(regionName, stateId, history)
    local state = self._compiled.states[stateId]
    if not state then return end
    
    -- If region already has active state, exit it first
    if self._activeStates[regionName] then
        self:_exitStateHierarchy(self._activeStates[regionName], state.parent)
    end
    
    -- Push to stack for history
    if not self._stateStack[regionName] then
        self._stateStack[regionName] = {}
    end
    table.insert(self._stateStack[regionName], stateId)
    
    -- Set as active
    self._activeStates[regionName] = stateId
    
    -- Publish state entry event
    self._context.eventBus:publish("statechart:event", {
        name = "Enter:" .. stateId,
        region = regionName,
        state = stateId
    })
    
    -- Run entry actions
    if state.onEnter and #state.onEnter > 0 then
        self:_runActions(state.onEnter, {})
    end
end

function StatechartExecutor:_runEnterActions()
    for regionName, stateId in pairs(self._activeStates) do
        local state = self._compiled.states[stateId]
        if state and state.onEnter and #state.onEnter > 0 then
            self:_runActions(state.onEnter, {})
        end
    end
end

function StatechartExecutor:_runStateExitActions(stateId)
    local state = self._compiled.states[stateId]
    if state and state.onExit and #state.onExit > 0 then
        self:_runActions(state.onExit, {})
    end
end

function StatechartExecutor:_runActions(actions, ctx)
    -- Build action context with access to profile variables, engine, etc.
    local actionCtx = {
        engine = self._context.engine,
        nav = self._context.nav,
        combat = self._context.combat,
        consume = self._context.consume,
        vendor = self._context.vendor,
        loot = self._context.loot,
        bb = self._context.bb,
        profile = self._variableStore,
        state = ctx.currentStateId or "unknown",
        -- Helper functions
        awaitEvent = function(eventName, filter, timeoutMs)
            local co = coroutine.running()
            if not co then error("awaitEvent must be called from coroutine") end
            
            local deadline = (self._context.getTime and self._context.getTime() or 0) + (timeoutMs or 30000)
            local subscriptionId
            local stateId = ctx.currentStateId or "unknown"
            
            subscriptionId = self._context.eventBus:subscribe(eventName, function(payload)
                -- Check if this state has been cancelled before resuming
                if self._subscriptions[stateId] == nil then
                    -- State was cancelled, ignore this event
                    return
                end
                
                if not filter or self:_matchFilter(payload, filter) then
                    if self._context.getTime and self._context.getTime() > deadline then
                        self._context.eventBus:unsubscribe(subscriptionId)
                        coroutine.resume(co, false, "timeout")
                    else
                        self._context.eventBus:unsubscribe(subscriptionId)
                        coroutine.resume(co, true, payload)
                    end
                end
            end)
            
            -- Track subscription for cleanup
            self._subscriptions[stateId] = self._subscriptions[stateId] or {}
            self._subscriptions[stateId][#self._subscriptions[stateId] + 1] = subscriptionId
            
            local ok, payload = coroutine.yield()
            return ok, payload
        end,
        publish = function(eventName, payload)
            self._context.eventBus:publish(eventName, payload)
        end,
        callAction = function(name, ...)
            return self._context.coreActions:call(name, self, ...)
        end,
        -- Allow calling core actions directly
        coreActions = self._context.coreActions,
        -- Also make profile available as global for inline actions
        profile = self._variableStore,
    }
    
    for _, action in ipairs(actions) do
        if action.type == "core" then
            local ok, err = self._context.coreActions:call(action.name, actionCtx, unpack(action.args or {}))
            if not ok and self._context.logError then
                self._context.logError("Core action " .. action.name .. " failed: " .. err)
            end
            self:_publish("statechart:action", {name = action.name, type = "core", state = ctx.currentStateId})
        elseif action.type == "inline" then
            local co = coroutine.create(action.fn)
            local stateId = ctx.currentStateId or "unknown"
            self._runningActions[stateId] = self._runningActions[stateId] or {}
            table.insert(self._runningActions[stateId], co)
            self:_publish("statechart:action", {name = action.name or "inline", type = "inline", state = ctx.currentStateId})
            
            local function resume(...)
                local ok, result = coroutine.resume(co, actionCtx, ...)
                if not ok then
                    if self._context.logError then
                        self._context.logError("Action error: " .. tostring(result))
                    end
                    return
                end
                if coroutine.status(co) == "dead" then
                    -- Action completed - clean up its subscriptions
                    self:_cleanupStateSubscriptions(stateId)
                else
                    -- Yielded (awaiting event) - subscriptions tracked
                end
            end
            -- Set environment for inline action to have access to profile as global
            if setfenv then
                setfenv(action.fn, {profile = self._variableStore, ctx = actionCtx})
            end
            resume()
        end
    end
end

-- Clean up subscriptions for a state (called when action completes or state exits)
function StatechartExecutor:_cleanupStateSubscriptions(stateId)
    local subs = self._subscriptions[stateId]
    if subs then
        for _, subId in ipairs(subs) do
            if self._context.eventBus and self._context.eventBus.unsubscribe then
                self._context.eventBus:unsubscribe(subId)
            end
        end
        self._subscriptions[stateId] = nil
    end
end

-- Cancel all coroutines and subscriptions for a state
function StatechartExecutor:_cancelStateActions(stateId)
    local actions = self._runningActions[stateId]
    if actions then
        for _, co in ipairs(actions) do
            if coroutine.status(co) ~= "dead" then
                -- Mark for cleanup - coroutine will be abandoned
                -- Subscriptions are cleaned up separately
            end
        end
        self._runningActions[stateId] = nil
    end
    -- Clean up subscriptions
    self:_cleanupStateSubscriptions(stateId)
end

function StatechartExecutor:_cancelAllActions()
    for stateId, _ in pairs(self._runningActions) do
        self:_cancelStateActions(stateId)
    end
end

function StatechartExecutor:_saveHistory(compoundStateId)
    local history = {}
    for regionName, activeLeaf in pairs(self._activeStates) do
        local leafState = self._compiled.states[activeLeaf]
        if leafState and self:_isDescendantOf(activeLeaf, compoundStateId) then
            history[regionName] = activeLeaf
        end
    end
    if next(history) then
        self._history[compoundStateId] = history
    end
end

function StatechartExecutor:_isDescendantOf(stateId, ancestorId)
    local state = self._compiled.states[stateId]
    while state do
        if state.id == ancestorId then return true end
        state = state.parent and self._compiled.states[state.parent] or nil
    end
    return false
end

function StatechartExecutor:_getStateDepth(stateId)
    local depth = 0
    local state = self._compiled.states[stateId]
    while state do
        depth = depth + 1
        state = state.parent and self._compiled.states[state.parent] or nil
    end
    return depth
end

function StatechartExecutor:_getRegionForState(stateId)
    local state = self._compiled.states[stateId]
    while state do
        if state.region then return state.region end
        state = state.parent and self._compiled.states[state.parent] or nil
    end
    return "Questing" -- default
end

function StatechartExecutor:_isInQuestingRegion(stateId)
    local state = self._compiled.states[stateId]
    while state do
        if state.region == "Questing" or state.parent == "Questing" then
            return true
        end
        state = state.parent and self._compiled.states[state.parent] or nil
    end
    return false
end

function StatechartExecutor:_updateBoundVariables()
    local variables = self._compiled.variables or {}
    for varName, varDef in pairs(variables) do
        if varDef.bind and self._context.bb then
            -- Evaluate bind expression: e.g., "player.level"
            local value = self._context.bb:get(varDef.bind)
            if value ~= nil then
                self._variableStore[varName] = value
            end
        end
    end
end

function StatechartExecutor:_publish(eventName, payload)
    if self._context.eventBus then
        self._context.eventBus:publish(eventName, payload)
    end
end

function StatechartExecutor:getActiveStates()
    local result = {}
    for regionName, stateId in pairs(self._activeStates) do
        result[regionName] = stateId
    end
    return result
end

function StatechartExecutor:getVariables()
    local result = {}
    for k, v in pairs(self._variableStore) do
        result[k] = v
    end
    return result
end

-- Context API for actions/guards
function StatechartExecutor.createContext(engine, nav, combat, consume, vendor, loot, bb, eventBus, coreActions)
    local ctx = {
        engine = engine,
        nav = nav,
        combat = combat,
        consume = consume,
        vendor = vendor,
        loot = loot,
        bb = bb,
        eventBus = eventBus,
        coreActions = coreActions,
        profile = {}, -- Will be set to executor._variableStore
    }
    
    function ctx:awaitEvent(eventName, filter, timeoutMs)
        -- Yield current coroutine, resume when event matches filter
        local co = coroutine.running()
        if not co then error("awaitEvent must be called from coroutine") end
        
        local deadline = (self._context.getTime and self._context.getTime() or 0) + (timeoutMs or 30000)
        local subscriptionId
        
        subscriptionId = self._context.eventBus:subscribe(eventName, function(payload)
            if not filter or self:_matchFilter(payload, filter) then
                if self._context.getTime and self._context.getTime() > deadline then
                    -- Timeout
                    coroutine.resume(co, false, "timeout")
                else
                    self._context.eventBus:unsubscribe(subscriptionId)
                    coroutine.resume(co, true, payload)
                end
            end
        end)
        
        -- Wait for resume
        local ok, payload = coroutine.yield()
        return ok, payload
    end
    
    function ctx:_matchFilter(payload, filter)
        -- Simple filter matching: {questId = 783} means payload.questId == 783
        for k, v in pairs(filter) do
            if payload[k] ~= v then return false end
        end
        return true
    end
    
    function ctx:callAction(name, ...)
        return self._context.coreActions:call(name, self, ...)
    end
    
    function ctx:publish(eventName, payload)
        self._context.eventBus:publish(eventName, payload)
    end
    
    return ctx
end

return StatechartExecutor