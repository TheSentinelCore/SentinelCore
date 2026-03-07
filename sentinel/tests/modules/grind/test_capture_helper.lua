local T = require("tests/test_util")

local M = {}

function M.run()
    -- Setup mock core
    local _orig_core = core
    core = {
        object_manager = {
            get_local_player = function()
                return {
                    get_position = function() return { x = 100, y = 200, z = 10 } end,
                    get_level = function() return 35 end,
                    get_target = function()
                        return {
                            get_npc_id = function() return 1234 end,
                            get_name = function() return "Test Vendor" end,
                            get_position = function() return { x = 150, y = 250, z = 12 } end,
                            is_unit = function() return true end,
                            is_player = function() return false end,
                        }
                    end,
                }
            end,
        },
        get_map_id = function() return 530 end,
        log = function() end,
    }

    -- Force re-require with mocked core
    package.loaded["modules/grind/capture_helper"] = nil
    local CaptureHelper = require("modules/grind/capture_helper")

    -- capture_position() returns {x=100, y=200, z=10}
    do
        local pos = CaptureHelper.capture_position()
        T.assert_not_nil(pos, "capture_position should return non-nil")
        T.assert_equal(pos.x, 100, "capture_position x should be 100")
        T.assert_equal(pos.y, 200, "capture_position y should be 200")
        T.assert_equal(pos.z, 10, "capture_position z should be 10")
    end

    -- capture_hotspot(50, "Test Spot") returns table with correct coords and radius
    do
        local hs = CaptureHelper.capture_hotspot(50, "Test Spot")
        T.assert_not_nil(hs, "capture_hotspot should return non-nil")
        T.assert_equal(hs.x, 100, "capture_hotspot x should be player x")
        T.assert_equal(hs.y, 200, "capture_hotspot y should be player y")
        T.assert_equal(hs.z, 10, "capture_hotspot z should be player z")
        T.assert_equal(hs.radius, 50, "capture_hotspot radius should be 50")
        T.assert_equal(hs.label, "Test Spot", "capture_hotspot label should be 'Test Spot'")
    end

    -- capture_hotspot() auto-generates id from label
    do
        local hs = CaptureHelper.capture_hotspot(40, "My Cool Spot")
        T.assert_not_nil(hs, "capture_hotspot should return non-nil")
        T.assert_equal(hs.id, "my_cool_spot", "id should be auto-generated from label")
    end

    -- capture_mob_ref() returns {npc_id=1234, name="Test Vendor"}
    do
        local ref = CaptureHelper.capture_mob_ref()
        T.assert_not_nil(ref, "capture_mob_ref should return non-nil")
        T.assert_equal(ref.npc_id, 1234, "capture_mob_ref npc_id should be 1234")
        T.assert_equal(ref.name, "Test Vendor", "capture_mob_ref name should be 'Test Vendor'")
    end

    -- capture_vendor({"repair"}) returns vendor with NPC position (not player position)
    do
        local vendor = CaptureHelper.capture_vendor({ "repair" })
        T.assert_not_nil(vendor, "capture_vendor should return non-nil")
        T.assert_equal(vendor.npc_id, 1234, "capture_vendor npc_id should be 1234")
        T.assert_equal(vendor.name, "Test Vendor", "capture_vendor name should be 'Test Vendor'")
        T.assert_equal(vendor.x, 150, "capture_vendor x should be target x (150), not player x")
        T.assert_equal(vendor.y, 250, "capture_vendor y should be target y (250), not player y")
        T.assert_equal(vendor.z, 12, "capture_vendor z should be target z (12), not player z")
        T.assert_equal(vendor.services[1], "repair", "capture_vendor services should include 'repair'")
    end

    -- capture_blackspot(30, "Danger") returns correct data
    do
        local bs = CaptureHelper.capture_blackspot(30, "Danger")
        T.assert_not_nil(bs, "capture_blackspot should return non-nil")
        T.assert_equal(bs.x, 100, "capture_blackspot x should be player x")
        T.assert_equal(bs.y, 200, "capture_blackspot y should be player y")
        T.assert_equal(bs.z, 10, "capture_blackspot z should be player z")
        T.assert_equal(bs.radius, 30, "capture_blackspot radius should be 30")
        T.assert_equal(bs.reason, "Danger", "capture_blackspot reason should be 'Danger'")
    end

    -- capture_requirements() returns {map_id=530, min_level=35, max_level=40}
    do
        local req = CaptureHelper.capture_requirements()
        T.assert_not_nil(req, "capture_requirements should return non-nil")
        T.assert_equal(req.map_id, 530, "capture_requirements map_id should be 530")
        T.assert_equal(req.min_level, 35, "capture_requirements min_level should be 35")
        T.assert_equal(req.max_level, 40, "capture_requirements max_level should be 35+5=40")
    end

    -- Cleanup
    core = _orig_core
    package.loaded["modules/grind/capture_helper"] = nil
end

return M
