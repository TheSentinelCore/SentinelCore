local TestUtil = require("tests/test_util")

local mod = {}

function mod.run()
    -- Mock IZI SDK modules
    local mock_izi = {
        get_time_to_die_global = function(self, unit)
            if unit and unit.mock_ttd then
                return unit.mock_ttd
            end
            return 10.0
        end,
        get_player = function(self)
            return { mock_player = true }
        end,
        is_battleground = function(self, map_id)
            return map_id == 1681
        end,
    }

    local mock_health_pred = {
        get_incoming_damage = function(self, player, seconds)
            if player and player.mock_inc_dmg then
                return player.mock_inc_dmg
            end
            return 0
        end,
    }

    local mock_combat_forecast = {
        get_forecast = function(self)
            return 8.0
        end,
    }

    -- Mock require to return our mocks
    local original_require = require
    package.loaded["common/izi_sdk"] = mock_izi
    package.loaded["common/modules/health_prediction"] = mock_health_pred
    package.loaded["common/modules/combat_forecast"] = mock_combat_forecast

    -- Clear cached module to force re-require
    package.loaded["integrations/izi_bridge"] = nil

    local IziBridge = require("integrations/izi_bridge")

    -- Test 1: IziBridge:new() creates instance
    local bridge = IziBridge:new()
    TestUtil.assert_not_nil(bridge, "IziBridge:new() should create instance")
    TestUtil.assert_not_nil(bridge._izi, "Should have izi reference")
    TestUtil.assert_not_nil(bridge._health_pred, "Should have health_pred reference")
    TestUtil.assert_not_nil(bridge._combat_forecast, "Should have combat_forecast reference")

    -- Test 2: predict_hp_pct with valid player
    local player = { get_health = function() return 1000 end, get_max_health = function() return 2000 end, mock_inc_dmg = 500 }
    local hp_pct = bridge:predict_hp_pct(player, 3.0)
    TestUtil.assert_equal(hp_pct, 0.25, "predict_hp_pct should return (1000-500)/2000")

    -- Test 3: predict_hp_pct with nil player
    hp_pct = bridge:predict_hp_pct(nil, 3.0)
    TestUtil.assert_true(hp_pct == nil, "predict_hp_pct with nil player should return nil")

    -- Test 4: get_forecast
    local forecast = bridge:get_forecast()
    TestUtil.assert_equal(forecast, 8.0, "get_forecast should return 8.0")

    -- Test 5: get_time_to_die with unit
    local unit = { mock_ttd = 5.0 }
    local ttd = bridge:get_time_to_die(unit)
    TestUtil.assert_equal(ttd, 5.0, "get_time_to_die should return 5.0")

    -- Test 6: get_time_to_die with nil unit
    ttd = bridge:get_time_to_die(nil)
    TestUtil.assert_true(ttd == nil, "get_time_to_die with nil unit should return nil")

    -- Test 7: get_player
    local player_result = bridge:get_player()
    TestUtil.assert_not_nil(player_result, "get_player should return player")
    TestUtil.assert_true(player_result.mock_player == true, "get_player should return mock player")

    -- Test 8: is_battleground
    TestUtil.assert_true(bridge:is_battleground(1681), "is_battleground should return true for 1681")
    TestUtil.assert_true(not bridge:is_battleground(0), "is_battleground should return false for 0")

    -- Restore original require
    package.loaded["common/izi_sdk"] = nil
    package.loaded["common/modules/health_prediction"] = nil
    package.loaded["common/modules/combat_forecast"] = nil
    package.loaded["integrations/izi_bridge"] = nil
end

return mod