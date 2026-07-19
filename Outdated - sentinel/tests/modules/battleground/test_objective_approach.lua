local ObjectiveApproach = require("modules/battleground/objective_approach")
local EOTSObjectives = require("modules/battleground/data/objectives/eots")
local T = require("tests/test_util")

local M = {}

function M.run()
    local player_pos = { x = 2200.0, y = 1600.0, z = 1160.0 }
    local mage = EOTSObjectives.by_id.MAGE_TOWER
    local mage_runtime = ObjectiveApproach.new_runtime({
        objective_approach_mode = "adaptive_ring",
        objective_ring_radius_node = 8,
        objective_ring_variant_count = 6,
    })
    local mage_target = ObjectiveApproach.compute_nav_target(player_pos, mage, {
        objective_approach_mode = "adaptive_ring",
        objective_ring_radius_node = 8,
        objective_ring_variant_count = 6,
    }, mage_runtime)

    T.assert_not_nil(mage_target)
    T.assert_equal(string.format("%.2f", mage_target.x), string.format("%.2f", mage.approach_anchor.x))
    T.assert_equal(string.format("%.2f", mage_target.y), string.format("%.2f", mage.approach_anchor.y))

    mage_runtime = ObjectiveApproach.update_runtime(mage_runtime, mage, player_pos, "stuck", nil, {
        path_index = 1,
        distance_remaining = 40,
    }, {
        objective_approach_mode = "adaptive_ring",
        objective_ring_radius_node = 8,
        objective_ring_variant_count = 6,
        capture_radius = 12,
    }, 2000)
    local mage_ring_target = ObjectiveApproach.compute_nav_target(player_pos, mage, {
        objective_approach_mode = "adaptive_ring",
        objective_ring_radius_node = 8,
        objective_ring_variant_count = 6,
    }, mage_runtime)
    T.assert_equal(mage_runtime.stage, "ring")
    T.assert_false(
        string.format("%.2f", mage_ring_target.x) == string.format("%.2f", mage.approach_anchor.x)
        and string.format("%.2f", mage_ring_target.y) == string.format("%.2f", mage.approach_anchor.y)
    )

    local flag = EOTSObjectives.by_id.CENTER_FLAG
    local target = ObjectiveApproach.compute_nav_target(player_pos, flag, {
        objective_approach_mode = "adaptive_ring",
        objective_ring_radius_flag = 6,
        objective_ring_variant_count = 6,
    }, {
        variant = 2,
    })

    T.assert_not_nil(target)
    T.assert_false(target.x == flag.x and target.y == flag.y and target.z == flag.z)

    local route = {
        { x = 2200.0, y = 1600.0, z = 1160.0 },
        { x = flag.x, y = flag.y, z = flag.z },
    }
    local offset = ObjectiveApproach.offset_route_nodes(route, EOTSObjectives.by_id, {
        objective_approach_mode = "adaptive_ring",
        objective_ring_radius_flag = 6,
        objective_ring_variant_count = 6,
    })

    T.assert_not_nil(offset[2])
    T.assert_false(offset[2].x == flag.x and offset[2].y == flag.y and offset[2].z == flag.z)
end

return M
