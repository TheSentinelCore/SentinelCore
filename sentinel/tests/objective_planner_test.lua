--- Unit tests for ObjectivePlanner
--- Run with: _G.SentinelCore.run_tests()

local ObjectivePlanner = require("modules/quest/objective_planner")

local tests = {}

local function make_objective(opts)
    opts = opts or {}
    return {
        type = opts.type or "KILL",
        target_id = opts.target_id,
        item_id = opts.item_id,
        count = opts.count or 1,
        spawn_positions = opts.spawn_positions or {},
        questie_positions = opts.questie_positions,
        quest_id = opts.quest_id,
    }
end

function tests.test_dbscan_basic()
    local planner = ObjectivePlanner.new()
    
    -- Three points close together (should cluster)
    local objectives = {
        make_objective({spawn_positions = {{x=0, y=0, z=0}}}),
        make_objective({spawn_positions = {{x=10, y=10, z=0}}}),
        make_objective({spawn_positions = {{x=20, y=20, z=0}}}),
    }
    
    local clusters, noise = planner:cluster_objectives(objectives, 50, 3)
    
    assert(#clusters == 1, "Should form 1 cluster (3 pts, eps=50, min_pts=3)")
    assert(#clusters[1].objectives == 3, "Cluster should have 3 objectives")
    assert(#noise == 0, "No noise points")
    
    print("✓ test_dbscan_basic passed")
end

function tests.test_dbscan_separate_clusters()
    local planner = ObjectivePlanner.new()
    
    -- Two groups far apart
    local objectives = {
        make_objective({spawn_positions = {{x=0, y=0, z=0}, {x=10, y=10, z=0}}}),
        make_objective({spawn_positions = {{x=500, y=500, z=0}, {x=510, y=510, z=0}}}),
    }
    
    local clusters, noise = planner:cluster_objectives(objectives, 50, 2)
    
    assert(#clusters == 2, "Should form 2 clusters")
    assert(#noise == 0, "No noise with min_pts=2")
    
    print("✓ test_dbscan_separate_clusters passed")
end

function tests.test_dbscan_noise_points()
    local planner = ObjectivePlanner.new()
    
    -- One dense group + one isolated point
    local objectives = {
        make_objective({spawn_positions = {{x=0, y=0, z=0}, {x=10, y=10, z=0}, {x=20, y=20, z=0}}}),
        make_objective({spawn_positions = {{x=1000, y=1000, z=0}}}), -- Isolated
    }
    
    local clusters, noise = planner:cluster_objectives(objectives, 50, 3)
    
    assert(#clusters == 1, "Should form 1 cluster (3 pts)")
    assert(#noise == 1, "Isolated point should be noise")
    
    print("✓ test_dbscan_noise_points passed")
end

function tests.test_sequence_clusters()
    local planner = ObjectivePlanner.new()
    
    local clusters = {
        {id = 1, center = {x=100, y=100, z=0}},
        {id = 2, center = {x=200, y=200, z=0}},
        {id = 3, center = {x=0, y=0, z=0}},
    }
    
    local start = {x = -50, y = -50, z = 0}
    local ordered = planner:sequence_clusters(clusters, start)
    
    assert(#ordered == 3, "Should return 3 clusters")
    -- Should order: 3 (closest to start), 1, 2
    assert(ordered[1].id == 3, "Cluster 3 should be first (closest to start)")
    assert(ordered[2].id == 1, "Cluster 1 should be second")
    assert(ordered[2].id == 2, "Cluster 2 should be third")
    
    print("✓ test_sequence_clusters passed")
end

function tests.test_cluster_structure()
    local planner = ObjectivePlanner.new()
    
    local objectives = {
        make_objective({
            type = "KILL", 
            target_id = 100, 
            count = 10,
            spawn_positions = {{x=0, y=0, z=0, spawn_id=1}, {x=10, y=10, z=0, spawn_id=2}}
        }),
        make_objective({
            type = "COLLECT", 
            item_id = 200, 
            count = 5,
            spawn_positions = {{x=5, y=5, z=0, spawn_id=3}}
        }),
    }
    
    local clusters = planner:cluster_objectives(objectives, 50, 2)
    
    assert(#clusters >= 1, "Should have at least 1 cluster")
    local cluster = clusters[1]
    
    assert(cluster.center, "Cluster should have center")
    assert(cluster.radius, "Cluster should have radius")
    assert(#cluster.objectives >= 1, "Cluster should have objectives")
    assert(#cluster.spawn_ids >= 1, "Cluster should have spawn IDs")
    assert(#cluster.waypoints >= 1, "Cluster should have waypoints")
    
    print("✓ test_cluster_structure passed")
end

function tests.test_full_plan()
    local planner = ObjectivePlanner.new()
    
    local objectives = {
        make_objective({type = "KILL", target_id = 100, count = 10, spawn_positions = {{x=100, y=100, z=0}}}),
        make_objective({type = "COLLECT", item_id = 200, count = 5, spawn_positions = {{x=110, y=110, z=0}}}),
        make_objective({type = "KILL", target_id = 101, count = 8, spawn_positions = {{x=500, y=500, z=0}}}),
    }
    
    local start = {x = 0, y = 0, z = 0}
    local plan = planner:plan(objectives, start, nil, "cluster")
    
    assert(plan.clusters, "Plan should have clusters")
    assert(plan.total_clusters, "Plan should have total_clusters")
    assert(plan.estimated_time, "Plan should have estimated_time")
    assert(plan.strategy == "cluster", "Plan should have strategy")
    
    print("✓ test_full_plan passed")
end

function tests.test_strategy_maximize_overlap()
    local planner = ObjectivePlanner.new()
    
    local objectives = {
        make_objective({type = "KILL", target_id = 100, count = 10, spawn_positions = {{x=100, y=100, z=0}}}),
        make_objective({type = "KILL", target_id = 101, count = 5, spawn_positions = {{x=110, y=110, z=0}}}),
        make_objective({type = "COLLECT", item_id = 200, count = 3, spawn_positions = {{x=500, y=500, z=0}}}),
    }
    
    local start = {x = 0, y = 0, z = 0}
    local plan_cluster = planner:plan(objectives, start, nil, "cluster")
    local plan_overlap = planner:plan(objectives, start, nil, "maximize_overlap")
    
    -- maximize_overlap should sort by objective count per cluster
    assert(plan_overlap.strategy == "maximize_overlap", "Strategy should be maximize_overlap")
    
    print("✓ test_strategy_maximize_overlap passed")
end

function tests.run_all()
    print("Running ObjectivePlanner tests...")
    tests.test_dbscan_basic()
    tests.test_dbscan_separate_clusters()
    tests.test_dbscan_noise_points()
    tests.test_sequence_clusters()
    tests.test_cluster_structure()
    tests.test_full_plan()
    tests.test_strategy_maximize_overlap()
    print("All ObjectivePlanner tests passed!")
end

return tests