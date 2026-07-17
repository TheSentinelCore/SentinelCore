-- sentinel/modules/quest/profile_executor.lua
-- Profile Executor: Wraps StatechartExecutor for profile execution

local ProfileExecutor = {}
ProfileExecutor.__index = ProfileExecutor

function ProfileExecutor.new(blackboard, engine, nav_adapter, eventBus)
    local self = setmetatable({
        _blackboard = blackboard,
        _engine = engine,
        _nav_adapter = nav_adapter,
        _eventBus = eventBus,
        _executor = nil,
        _compiled = nil,
        _context = nil,
        _started = false,
        _swapping = false,
        lastSwapMs = 0,
        lastSwapFallback = false,
    }, ProfileExecutor)
    
    return self
end

function ProfileExecutor:loadProfile(compiledProfile)
    if not compiledProfile then
        return false, "No compiled profile provided"
    end
    
    self._compiled = compiledProfile
    
    -- Build execution context
    self._context = {
        engine = self._engine,
        nav = self._nav_adapter,
        combat = self._engine and self._engine.combat,
        consume = self._engine and self._engine.consume,
        vendor = self._engine and self._engine.vendor,
        loot = self._engine and self._engine.loot,
        trainer = self._engine and self._engine.trainer,
        movement = self._engine and self._engine.movement,
        bb = self._blackboard,
        profile = {
            variables = {},
            activeQuest = nil,
            phase = "start",
            hearthstoneBound = false,
            playerClass = self._blackboard:get("player.class_name", "WARRIOR"),
            playerLevel = self._blackboard:get("player.level", 1),
        },
        -- Helper functions
        awaitEvent = function(eventName, filter, timeoutMs)
            local co = coroutine.running()
            if not co then error("awaitEvent must be called from coroutine") end
            
            local deadline = (self._blackboard.getTime and self._blackboard.getTime() or 0) + (timeoutMs or 30000)
            local subscriptionId
            
            subscriptionId = self._eventBus:subscribe(eventName, function(payload)
                if not filter or self:_matchFilter(payload, filter) then
                    if (self._blackboard.getTime and self._blackboard.getTime() or 0) > deadline then
                        self._eventBus:unsubscribe(subscriptionId)
                        coroutine.resume(co, false, "timeout")
                    else
                        self._eventBus:unsubscribe(subscriptionId)
                        coroutine.resume(co, true, payload)
                    end
                end
            end)
            
            local ok, payload = coroutine.yield()
            return ok, payload
        end,
        publish = function(eventName, payload)
            self._eventBus:publish(eventName, payload)
        end,
        callAction = function(name, ...)
            -- Would call core actions
        end,
        bb = self._blackboard,
        eventBus = self._eventBus,  -- Add eventBus to context for StatechartExecutor
    }
    
    return self
end

function ProfileExecutor:_matchFilter(payload, filter)
    for k, v in pairs(filter) do
        if payload[k] ~= v then
            return false
        end
    end
    return true
end

function ProfileExecutor:start()
    if self._started then return end
    if not self._compiled then
        return false, "No compiled profile loaded"
    end
    
    local StatechartExecutor = require("modules/quest/statechart_executor")
    self._executor = StatechartExecutor.new(self._compiled, self._context)
    self._executor:start()
    self._started = true
    
    -- Publish ProfileStart event
    if self._context.eventBus then
        self._context.eventBus:publish("ProfileStart", {profile = self._compiled.profile.id})
    end
    
    return true
end

function ProfileExecutor:update(now_ms)
    if not self._started or not self._executor then return end
    if self._swapping then return end  -- re-entrancy guard during hot-swap
    self._executor:update(now_ms)
end

function ProfileExecutor:handleEvent(eventName, payload)
    if not self._started or not self._executor then return end
    if self._swapping then return end  -- re-entrancy guard during hot-swap
    return self._executor:handleEvent(eventName, payload)
end

function ProfileExecutor:stop()
    self._started = false
    if self._executor then
        self._executor:stop()
        self._executor = nil
    end
end

-- loadProfile is defined above (lines 21-79) - no duplicate needed
function ProfileExecutor:setProfile(compiledProfile)
    -- Delegate to loadProfile with full context building
    return self:loadProfile(compiledProfile)
end

function ProfileExecutor:isRunning()
    return self._started
end

function ProfileExecutor:getActiveStates()
    if self._executor then
        return self._executor:getActiveStates()
    end
    return {}
end

function ProfileExecutor:getVariables()
    if self._context and self._context.profile then
        return self._context.profile.variables
    end
    return {}
end

-- Hot-swap a new compiled profile with minimal interruption.
-- Preserves: runtime variables, active states, and the external blackboard
-- (player vars / quests / inventory / combat are held in the blackboard,
-- which loadProfile never mutates, so they survive automatically).
-- Falls back to a full stop+reload if the profiles are incompatible or the
-- swap throws. Measures swap time and reports whether a fallback occurred.
function ProfileExecutor:hotSwap(compiledProfile)
    if not self._started then
        -- Nothing is currently running; treat as a clean load.
        return self:loadProfile(compiledProfile)
    end

    self._swapping = true
    local t0 = self:_now()
    local ok, err = pcall(function()
        self:_performHotSwap(compiledProfile)
    end)
    local t1 = self:_now()
    self._swapping = false

    self.lastSwapMs = (t1 - t0)
    self.lastSwapFallback = not ok

    if not ok then
        -- Incompatible or failed: full reload is the safe path.
        self:stop()
        local loaded = self:loadProfile(compiledProfile)
        if loaded ~= false then
            self:start()
        end
        return false, tostring(err)
    end
    return true
end

function ProfileExecutor:_now()
    if self._blackboard and self._blackboard.getTime then
        return self._blackboard:getTime()
    end
    if os and os.clock then return os.clock() end
    return 0
end

function ProfileExecutor:_performHotSwap(newProfile)
    if not self:_compatible(newProfile) then
        error("profiles incompatible for hot-swap (schema/region mismatch)")
    end

    -- Snapshot runtime state from the live executor/context.
    local snapshot = { variables = {}, activeStates = {} }
    if self._context and self._context.profile then
        for k, v in pairs(self._context.profile.variables) do
            snapshot.variables[k] = v
        end
    end
    if self._executor then
        snapshot.activeStates = self._executor._activeStates or {}
        if self._executor.getActiveStates then
            snapshot.activeStates = self._executor:getActiveStates() or snapshot.activeStates
        end
    end

    -- Build the new executor on the new profile, reusing the same context
    -- (blackboard, engine, nav adapter, event bus all preserved).
    local StatechartExecutor = require("modules/quest/statechart_executor")
    local newExecutor = StatechartExecutor.new(newProfile, self._context)
    newExecutor:start()

    -- Restore runtime variables over the new profile's init values.
    for k, v in pairs(snapshot.variables) do
        newExecutor._variableStore[k] = v
    end

    -- Restore active states only where the state still exists in the new profile.
    for regionName, stateId in pairs(snapshot.activeStates) do
        if newProfile.states[stateId] then
            newExecutor._activeStates[regionName] = stateId
        end
    end

    self._compiled = newProfile
    self._executor = newExecutor
end

-- Compatibility gate: only safe to hot-swap in place when the new profile
-- shares the schema version and every currently-active state still exists.
function ProfileExecutor:_compatible(newProfile)
    if not newProfile or not newProfile.states then return false end
    if self._compiled and self._compiled.schemaVersion and newProfile.schemaVersion then
        if self._compiled.schemaVersion ~= newProfile.schemaVersion then
            return false
        end
    end
    if self._executor and self._executor._activeStates then
        for _regionName, stateId in pairs(self._executor._activeStates) do
            if not newProfile.states[stateId] then
                return false
            end
        end
    end
    return true
end

function ProfileExecutor:getLastSwapStats()
    return { ms = self.lastSwapMs, fallback = self.lastSwapFallback }
end

return ProfileExecutor