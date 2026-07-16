--- Unit tests for NPCInteraction
--- Run with: _G.SentinelCore.run_tests()

local NPCInteraction = require("modules/quest/npc_interaction")

local tests = {}

function tests.test_build_service_queue_empty()
    local blackboard = {get = function() return nil end}
    local queue = NPCInteraction.build_service_queue(123, blackboard, nil)
    
    assert(type(queue) == "table", "Should return table")
    assert(#queue == 0, "Should be empty without engine")
    
    print("✓ test_build_service_queue_empty passed")
end

function tests.test_new_interaction()
    local blackboard = {get = function() return nil end}
    local interaction = NPCInteraction.new(blackboard)
    
    assert(interaction, "Should create interaction")
    assert(interaction.execute, "Should have execute method")
    assert(interaction.set_queue, "Should have set_queue method")
    assert(interaction.get_state, "Should have get_state method")
    
    print("✓ test_new_interaction passed")
end

function tests.test_execute_empty_queue()
    local interaction = NPCInteraction.new({get = function() return nil end})
    interaction:set_queue({})
    
    local result = interaction:execute()
    
    assert(result == "SUCCESS", "Empty queue should return SUCCESS")
    
    print("✓ test_execute_empty_queue passed")
end

function tests.test_service_types()
    local queue = {
        {type = "TURNIN", quest_id = 100, reward_choice = 1},
        {type = "ACCEPT", quest_id = 101},
        {type = "TRAIN", spell_id = 12345},
        {type = "VENDOR", npc_id = 123, delegate = true},
    }
    
    local interaction = NPCInteraction.new({get = function() return nil end})
    interaction:set_queue(queue)
    
    -- First service
    local result = interaction:execute()
    -- Will return RUNNING since we're mocking
    assert(result == "RUNNING" or result == "FAILURE", "Should return RUNNING or FAILURE")
    
    print("✓ test_service_types passed")
end

function tests.run_all()
    print("Running NPCInteraction tests...")
    tests.test_build_service_queue_empty()
    tests.test_new_interaction()
    tests.test_execute_empty_queue()
    tests.test_service_types()
    print("All NPCInteraction tests passed!")
end

return tests