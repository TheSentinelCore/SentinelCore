-- sentinel/tests/statechart_executor_cancellation_test.lua
-- Tests for event subscription cleanup in statechart_executor.lua

local TestUtil = require("tests/test_util")

local CancellationTests = {}

-- Minimal mock event bus for testing
local function createMockEventBus()
    local subscriptions = {}
    local unsubscribes = {}
    
    return {
        _subscriptions = subscriptions,
        _unsubscribes = unsubscribes,
        
        subscribe = function(self, eventName, handler)
            local id = tostring(math.random(10000, 99999))
            subscriptions[id] = {event = eventName, handler = handler}
            return id
        end,
        
        unsubscribe = function(self, id)
            unsubscribes[#unsubscribes + 1] = id
            subscriptions[id] = nil
        end,
        
        published = {},
        publish = function(self, eventName, payload)
            self.published[#self.published + 1] = {event = eventName, payload = payload}
        end
    }
end

function CancellationTests.test_subscription_cancelled_on_state_exit()
    -- Test that subscriptions are cancelled when state actions are cancelled
    local StatechartExecutor = require("modules/quest/statechart_executor")
    
    local mockBus = createMockEventBus()
    
    local compiled = {
        profile = {id = "test", name = "Test"},
        variables = {},
        states = {
            ["StateA"] = {
                id = "StateA",
                name = "StateA",
                type = "atomic",
                onEnter = {
                    {type = "inline", fn = function(ctx)
                        -- Check if we can await (requires eventBus)
                        if ctx.awaitEvent then
                            ctx:awaitEvent("QuestAccepted", {}, 5000)
                        end
                    end}
                }
            }
        },
        regions = {
            Questing = {
                type = "exclusive",
                initial = "StateA"
            }
        }
    }
    
    local context = {
        eventBus = mockBus,
        bb = {
            get = function() return 0 end,
            getTime = function() return 0 end
        },
        coreActions = {
            call = function() return true end
        }
    }
    
    local executor = StatechartExecutor.new(compiled, context)
    
    -- Track subscriptions before cancellation
    local subCountBefore = 0
    for _ in pairs(mockBus._subscriptions) do subCountBefore = subCountBefore + 1 end
    
    -- Cancel state actions (simulating state exit)
    executor:_cancelStateActions("StateA")
    
    -- Check that subscriptions were cleaned up
    local subCountAfter = 0
    for _ in pairs(mockBus._subscriptions) do subCountAfter = subCountAfter + 1 end
    
    -- Subscriptions should be cancelled
    TestUtil.assert_equal(subCountAfter, 0, 
        "All subscriptions should be cancelled when state is exited")
    TestUtil.assert_equal(#mockBus._unsubscribes, subCountBefore,
        "Unsubscribe should have been called for each subscription")
end

function CancellationTests.test_running_actions_tracks_subscriptions()
    -- Test that _runningActions tracks subscription IDs (via _subscriptions table)
    local StatechartExecutor = require("modules/quest/statechart_executor")
    
    local compiled = {
        profile = {id = "test", name = "Test"},
        variables = {},
        states = {},
        regions = {}
    }
    
    local mockBus = createMockEventBus()
    
    local context = {
        eventBus = mockBus,
        bb = { get = function() return 0 end, getTime = function() return 0 end },
        coreActions = { call = function() return true end }
    }
    
    local executor = StatechartExecutor.new(compiled, context)
    
    -- After fix, _subscriptions should exist for tracking
    TestUtil.assert_not_nil(executor._subscriptions, "_subscriptions should exist for subscription tracking")
end

return CancellationTests