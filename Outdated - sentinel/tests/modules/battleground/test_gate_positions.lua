local T = require("tests/test_util")
local GatePositions = require("modules/battleground/data/gate_positions")

local M = {}

function M.run()
    local expected_bgs = { "WSG", "AB", "AV", "EOTS" }
    local expected_sides = { "ALLIANCE", "HORDE" }

    for _, bg_key in ipairs(expected_bgs) do
        T.assert_not_nil(GatePositions[bg_key], "gate positions should exist for " .. bg_key)

        for _, side in ipairs(expected_sides) do
            local pos = GatePositions[bg_key][side]
            local label = bg_key .. "_" .. side
            T.assert_not_nil(pos, "gate position should exist for " .. label)
            T.assert_equal(type(pos.x), "number", label .. " should have numeric x")
            T.assert_equal(type(pos.y), "number", label .. " should have numeric y")
            T.assert_equal(type(pos.z), "number", label .. " should have numeric z")
        end
    end
end

return M
