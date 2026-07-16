--- Unit tests for QuestPhases
--- Run with: _G.SentinelCore.run_tests()

local QuestPhases = require("modules/quest/quest_phases")

local tests = {}

function tests.test_travel_phase_creation()
    local travel = QuestPhases.travel("TRAVEL_TO_GIVER")
    
    assert(travel, "Should create travel phase")
    assert(travel.tick, "Should have tick function")
    
    print("✓ test_travel_phase_creation passed")
end

function tests.test_interact_phase_creation()
    local interact = QuestPhases.interact("INTERACT_ACCEPT")
    
    assert(interact, "Should create interact phase")
    assert(interact.tick, "Should have tick function")
    
    print("✓ test_interact_phase_creation passed")
end

function tests.test_objective_kill_phase()
    local obj_kill = QuestPhases.objective_kill()
    
    assert(obj_kill, "Should create objective kill phase")
    
    print("✓ test_objective_kill_phase passed")
end

function tests.test_objective_collect_phase()
    local obj_collect = QuestPhases.objective_collect()
    
    assert(obj_collect, "Should create objective collect phase")
    
    print("✓ test_objective_collect_phase passed")
end

function tests.test_objective_escort_phase()
    local obj_escort = QuestPhases.objective_escort()
    
    assert(obj_escort, "Should create objective escort phase")
    
    print("✓ test_objective_escort_phase passed")
end

function tests.run_all()
    print("Running QuestPhases tests...")
    tests.test_travel_phase_creation()
    tests.test_interact_phase_creation()
    tests.test_objective_kill_phase()
    tests.test_objective_collect_phase()
    tests.test_objective_escort_phase()
    print("All QuestPhases tests passed!")
end

return tests