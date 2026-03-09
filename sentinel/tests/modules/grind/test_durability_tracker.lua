local DurabilityTracker = require("modules/grind/durability_tracker")
local T = require("tests/test_util")

local M = {}

local function mock_bb()
    local data = {}
    return {
        get = function(self, key, default)
            local v = data[key]
            if v == nil then return default end
            return v
        end,
        set = function(self, key, value)
            data[key] = value
        end,
        _data = data,
    }
end

local function mock_player(durability_pcts)
    return {
        get_equipped_items = function(self)
            local slots = {}
            for i, pct in ipairs(durability_pcts) do
                slots[i] = {
                    object = {
                        get_durability = function(self) return pct end,
                        get_max_durability = function(self) return 100 end,
                        is_valid = function(self) return true end,
                    },
                    slot_id = i,
                }
            end
            return slots
        end,
    }
end

function M.run()
    -- -------------------------------------------------------
    -- Tracks lowest durability across equipment slots
    -- -------------------------------------------------------
    local tracker = DurabilityTracker:new()
    local bb = mock_bb()
    local player = mock_player({ 80, 50, 100, 30 })
    bb:set("player.object", player)

    tracker:sample(bb, 0)

    T.assert_equal(bb:get("module.grind.durability_pct"), 0.30,
        "durability_pct should be lowest slot (30/100 = 0.30)")

    -- -------------------------------------------------------
    -- Throttles sampling to 5s intervals
    -- -------------------------------------------------------
    local tracker2 = DurabilityTracker:new()
    local bb2 = mock_bb()
    local player2 = mock_player({ 90 })
    bb2:set("player.object", player2)

    tracker2:sample(bb2, 1000)
    T.assert_equal(bb2:get("module.grind.durability_pct"), 0.90,
        "first sample should run immediately")

    -- Replace player with worse durability
    bb2:set("player.object", mock_player({ 10 }))
    tracker2:sample(bb2, 3000) -- only 2s later
    T.assert_equal(bb2:get("module.grind.durability_pct"), 0.90,
        "should NOT resample before 5s interval")

    tracker2:sample(bb2, 6001) -- 5s+ later
    T.assert_equal(bb2:get("module.grind.durability_pct"), 0.10,
        "should resample after 5s interval")

    -- -------------------------------------------------------
    -- Sets needs_repair flag when below threshold
    -- -------------------------------------------------------
    local tracker3 = DurabilityTracker:new()
    local bb3 = mock_bb()
    bb3:set("player.object", mock_player({ 50, 80 }))

    tracker3:sample(bb3, 0)
    T.assert_false(bb3:get("module.grind.needs_repair"),
        "50% durability should NOT need repair at default 25% threshold")

    local tracker4 = DurabilityTracker:new()
    local bb4 = mock_bb()
    bb4:set("player.object", mock_player({ 20, 80 }))

    tracker4:sample(bb4, 0)
    T.assert_true(bb4:get("module.grind.needs_repair"),
        "20% durability should need repair at default 25% threshold")

    -- -------------------------------------------------------
    -- Custom threshold via set_threshold
    -- -------------------------------------------------------
    local tracker5 = DurabilityTracker:new()
    tracker5:set_threshold(0.50)
    local bb5 = mock_bb()
    bb5:set("player.object", mock_player({ 40, 80 }))

    tracker5:sample(bb5, 0)
    T.assert_true(bb5:get("module.grind.needs_repair"),
        "40% durability should need repair at 50% threshold")

    -- -------------------------------------------------------
    -- Handles missing player gracefully
    -- -------------------------------------------------------
    local tracker6 = DurabilityTracker:new()
    local bb6 = mock_bb()
    -- No player.object set

    tracker6:sample(bb6, 0)
    T.assert_equal(bb6:get("module.grind.durability_pct"), 1.0,
        "missing player should default to 1.0 durability")
    T.assert_false(bb6:get("module.grind.needs_repair"),
        "missing player should NOT need repair")

    -- -------------------------------------------------------
    -- Handles empty equipment
    -- -------------------------------------------------------
    local tracker7 = DurabilityTracker:new()
    local bb7 = mock_bb()
    local empty_player = {
        get_equipped_items = function(self) return {} end,
    }
    bb7:set("player.object", empty_player)

    tracker7:sample(bb7, 0)
    T.assert_equal(bb7:get("module.grind.durability_pct"), 1.0,
        "empty equipment should default to 1.0 durability")
    T.assert_false(bb7:get("module.grind.needs_repair"),
        "empty equipment should NOT need repair")
end

return M
