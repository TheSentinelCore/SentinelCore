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

-- Mock core.inventory.get_total_repair_cost for testing
local _mock_repair_cost = 0
local _saved_core = _G.core
local _mock_inventory = { get_total_repair_cost = function() return _mock_repair_cost end }

local function setup_mock(cost)
    _mock_repair_cost = cost
    _G.core = _G.core or {}
    _G.core.inventory = _mock_inventory
end

local function teardown_mock()
    _G.core = _saved_core
end

function M.run()
    setup_mock(0)

    -- Repair cost = 0 → no repair needed
    do
        setup_mock(0)
        local dt = DurabilityTracker:new()
        local bb = mock_bb()
        dt:sample(bb, 0)
        T.assert_equal(bb:get("module.grind.repair_cost_copper"), 0, "repair cost 0 when no damage")
        T.assert_false(bb:get("module.grind.needs_repair"), "no repair at 0 cost")
    end

    -- Repair cost below threshold → no repair
    do
        setup_mock(3000) -- 30 silver, below default 50 silver threshold
        local dt = DurabilityTracker:new()
        local bb = mock_bb()
        dt:sample(bb, 0)
        T.assert_equal(bb:get("module.grind.repair_cost_copper"), 3000, "tracks repair cost")
        T.assert_false(bb:get("module.grind.needs_repair"), "no repair below threshold")
    end

    -- Repair cost at/above threshold → needs repair
    do
        setup_mock(5000) -- 50 silver = default threshold
        local dt = DurabilityTracker:new()
        local bb = mock_bb()
        dt:sample(bb, 0)
        T.assert_true(bb:get("module.grind.needs_repair"), "needs repair at threshold")
    end

    -- Custom threshold
    do
        setup_mock(2000) -- 20 silver
        local dt = DurabilityTracker:new()
        dt:set_threshold_copper(1000) -- 10 silver
        local bb = mock_bb()
        dt:sample(bb, 0)
        T.assert_true(bb:get("module.grind.needs_repair"), "needs repair with custom threshold")
    end

    -- Throttles to 5s intervals
    do
        setup_mock(0)
        local dt = DurabilityTracker:new()
        local bb = mock_bb()
        dt:sample(bb, 1000)
        T.assert_equal(bb:get("module.grind.repair_cost_copper"), 0, "first sample runs")

        setup_mock(9999)
        dt:sample(bb, 2000) -- only 1s later
        T.assert_equal(bb:get("module.grind.repair_cost_copper"), 0, "throttled, still old value")

        dt:sample(bb, 6001) -- 5s+ later
        T.assert_equal(bb:get("module.grind.repair_cost_copper"), 9999, "re-samples after 5s")
    end

    -- reset() forces re-sample
    do
        setup_mock(0)
        local dt = DurabilityTracker:new()
        local bb = mock_bb()
        dt:sample(bb, 1000)

        setup_mock(7000)
        dt:reset()
        dt:sample(bb, 2000) -- would normally be throttled
        T.assert_equal(bb:get("module.grind.repair_cost_copper"), 7000, "reset forces re-sample")
    end

    teardown_mock()
    T.log("[test_durability_tracker] all tests passed")
end

return M
