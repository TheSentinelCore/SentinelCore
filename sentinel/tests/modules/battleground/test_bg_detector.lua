local Detector = require("modules/battleground/bg_detector")
local T = require("tests/test_util")

local M = {}

function M.run()
    local detector = Detector:new()
    local key, _, reason = detector:detect(30, "Alterac Valley", 0, "")
    T.assert_equal(key, "AV")
    T.assert_equal(reason, "map_id")
    local live_key, _, live_reason = detector:detect(1459, "Alterac Valley", 0, "")
    T.assert_equal(live_key, "AV")
    T.assert_equal(live_reason, "map_name")
    local side = detector:resolve_side("WSG", { x = 1510, y = 1480, z = 352 })
    T.assert_equal(side, "ALLIANCE")
    T.assert_equal(detector:resolve_side("WSG", nil), nil)

    -- faction_id takes priority over position
    local alliance_player = { get_faction_id = function() return 1 end }
    local horde_player = { get_faction_id = function() return 2 end }
    local horde_pos = { x = 940, y = 1430, z = 345 }
    T.assert_equal(detector:resolve_side("WSG", horde_pos, alliance_player), "ALLIANCE",
        "faction_id should override proximity")
    T.assert_equal(detector:resolve_side("WSG", horde_pos, horde_player), "HORDE",
        "horde faction_id should return HORDE")

    -- ambiguous position (close to midpoint) returns nil without faction_id
    local midpoint = { x = 1228, y = 1457, z = 348 }
    T.assert_equal(detector:resolve_side("WSG", midpoint), nil,
        "ambiguous position should return nil")
    T.assert_equal(detector:resolve_side("WSG", midpoint, alliance_player), "ALLIANCE",
        "faction_id resolves ambiguous position")
end

return M
