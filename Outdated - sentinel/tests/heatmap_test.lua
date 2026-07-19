--- Unit tests for Heatmap
--- Run with: _G.SentinelCore.run_tests()

local Heatmap = require("modules/quest/heatmap")

local tests = {}

function tests.test_cell_key()
    local key = Heatmap._cell_key(100, 200)
    assert(key == "2:4", "Cell key should be '2:4' for (100,200) with size 50")
    
    key = Heatmap._cell_key(-10, -20)
    assert(key == "-1:-1", "Cell key should handle negatives")
    
    print("✓ test_cell_key passed")
end

function tests.test_add_spawn()
    local bb = {
        get = function(self, key, default) return default end
    }
    local heatmap = Heatmap.new(bb)
    
    heatmap:add_spawn(100, 100, 0, 1.0, 1)
    heatmap:add_spawn(110, 110, 0, 2.0, 2)
    
    local key = Heatmap._cell_key(100, 100)
    local cell = heatmap.cells[key]
    
    assert(cell, "Cell should exist")
    assert(cell.score == 3.0, "Score should be sum of weights (1.0 + 2.0)")
    assert(#cell.spawns == 2, "Should have 2 spawns")
    assert(cell.objectives[1] == true, "Objective 1 should be tracked")
    assert(cell.objectives[2] == true, "Objective 2 should be tracked")
    
    print("✓ test_add_spawn passed")
end

function tests.test_get_density()
    local bb = {get = function() return 0 end}
    local heatmap = Heatmap.new(bb)
    
    -- Add spawns in a 50yd area
    heatmap:add_spawn(100, 100, 0, 1.0)
    heatmap:add_spawn(120, 120, 0, 2.0)
    heatmap:add_spawn(140, 140, 0, 1.5)
    
    local density = heatmap:get_density(110, 110, 60)
    
    -- Should average all 3 spawns
    assert(density > 0, "Density should be positive")
    assert(math.abs(density - 1.5) < 0.1, "Average should be ~1.5")
    
    -- Far away should be 0
    local far = heatmap:get_density(1000, 1000, 100)
    assert(far == 0, "Far area should have 0 density")
    
    print("✓ test_get_density passed")
end

function tests.test_top_cells()
    local bb = {get = function() return 0 end}
    local heatmap = Heatmap.new(bb)
    
    heatmap:add_spawn(100, 100, 0, 5.0)  -- High density
    heatmap:add_spawn(200, 200, 0, 2.0)  -- Medium
    heatmap:add_spawn(300, 300, 0, 1.0)  -- Low
    
    local top = heatmap:get_top_cells(2)
    
    assert(#top == 2, "Should return top 2")
    assert(top[1].score > top[2].score, "First should have higher score")
    assert(top[1].center_x == 100, "Top cell center should match")
    
    print("✓ test_top_cells passed")
end

function tests.test_needs_rebuild()
    local bb = {get = function() return 10000 end}
    local heatmap = Heatmap.new(bb)
    
    heatmap.dirty = true
    assert(heatmap:needs_rebuild() == true, "Dirty should need rebuild")
    
    heatmap.dirty = false
    heatmap.last_rebuild = 5000
    assert(heatmap:needs_rebuild() == true, "Old rebuild should need rebuild")
    
    heatmap.last_rebuild = 9999
    assert(heatmap:needs_rebuild() == false, "Recent rebuild should not need rebuild")
    
    print("✓ test_needs_rebuild passed")
end

function tests.test_mark_dirty()
    local bb = {get = function() return 0 end}
    local heatmap = Heatmap.new(bb)
    
    heatmap.dirty = false
    heatmap:mark_dirty()
    assert(heatmap.dirty == true, "Should be marked dirty")
    
    print("✓ test_mark_dirty passed")
end

function tests.run_all()
    print("Running Heatmap tests...")
    tests.test_cell_key()
    tests.test_add_spawn()
    tests.test_get_density()
    tests.test_top_cells()
    tests.test_needs_rebuild()
    tests.test_mark_dirty()
    print("All Heatmap tests passed!")
end

return tests