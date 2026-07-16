--- Unit tests for NPCInteraction
--- Run with: _G.SentinelCore.run_tests()

local NPCInteraction = require("modules/quest/npc_interaction")

local tests = {}

local function make_blackboard()
    return {
        get = function(self, key, default)
            if key == "module.grind.vendor_state_machine" then return nil end
            if key == "module.quest.engine" then return nil end
            return default
        end,
        set = function() end,
    }
end

function tests.test_new_interaction()
    local bb = make_blackboard()
    local interaction = NPCInteraction.new(bb)
    
    assert(interaction, "Should create interaction")
    assert(interaction.execute, "Should have execute method")
    assert(interaction.set_queue, "Should have set_queue method")
    assert(interaction.get_state, "Should have get_state method")
    
    print("✓ test_new_interaction passed")
end

function tests.test_build_service_queue_empty()
    local bb = make_blackboard()
    local queue = NPCInteraction.build_service_queue(123, bb, nil)
    
    assert(type(queue) == "table", "Should return table")
    assert(#queue == 0, "Should be empty without engine")
    
    print("✓ test_build_service_queue_empty passed")
end

function tests.test_execute_empty_queue()
    local bb = make_blackboard()
    local interaction = NPCInteraction.new(bb)
    interaction:set_queue({})
    
    local result = interaction:execute()
    assert(result == "SUCCESS", "Empty queue should return SUCCESS")
    
    print("✓ test_execute_empty_queue passed")
end

function tests.test_service_types()
    local bb = make_blackboard()
    local interaction = NPCInteraction.new(bb)
    
    -- Test with a simple queue
    local queue = {
        {type = "TURNIN", quest_id = 100, reward_choice = 1},
        {type = "ACCEPT", quest_id = 101},
        {type = "TRAIN", spell_id = 12345},
        {type = "VENDOR", npc_id = 123, delegate = true},
    }
    
    interaction:set_queue(queue)
    
    -- First execution will try first service
    -- Since we're mocking, it will return RUNNING or FAILURE
    local result = interaction:execute()
    assert(result == "RUNNING" or result == "FAILURE", "Should return RUNNING or FAILURE")
    
    print("✓ test_service_types passed")
end

function tests.test_is_trainer_vendor()
    -- These are internal helper functions
    assert(type(NPCInteraction._is_trainer) == "function", "_is_trainer should be function")
    assert(type(NPCInteraction._is_vendor) == "function", "_is_vendor should be function")
    
    print("✓ test_is_trainer_vendor passed")
end

function tests.run_all()
    print("Running NPCInteraction tests...")
    tests.test_new_interaction()
    tests.test_build_service_queue_empty()
    tests.test_execute_empty_queue()
    tests.test_service_types()
    tests.test_is_trainer_vendor()
    print("All NPCInteraction tests passed!")
end

return tests