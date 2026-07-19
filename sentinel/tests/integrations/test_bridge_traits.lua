-- sentinel/tests/integrations/test_bridge_traits.lua
-- Tests for Sylvanas Bridge traits - SENT-7.1 through SENT-7.7

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Sentinel Bridge Traits Tests ===")

    -- =====================================================================
    -- Test 1: QuestClientTrait interface exists
    -- =====================================================================
    print("Test 1: QuestClientTrait interface exists")
    package.loaded["integrations/sentinel_bridge/quest_client_trait"] = nil
    local QuestClientTrait = require("integrations/sentinel_bridge/quest_client_trait")

    T.assert_not_nil(QuestClientTrait.accept_quest, "should have accept_quest method")
    T.assert_not_nil(QuestClientTrait.turn_in_quest, "should have turn_in_quest method")
    T.assert_not_nil(QuestClientTrait.quest_log_entry, "should have quest_log_entry method")
    T.assert_not_nil(QuestClientTrait.objective_status, "should have objective_status method")
    T.assert_not_nil(QuestClientTrait.gossip_options, "should have gossip_options method")
    T.assert_not_nil(QuestClientTrait.select_gossip, "should have select_gossip method")
    T.assert_not_nil(QuestClientTrait.trainer_interact, "should have trainer_interact method")
    T.assert_not_nil(QuestClientTrait.QuestLogEntry, "should have QuestLogEntry structure")
    T.assert_not_nil(QuestClientTrait.ObjectiveStatus, "should have ObjectiveStatus structure")
    T.assert_not_nil(QuestClientTrait.GossipOption, "should have GossipOption structure")
    print("  PASS")

    -- =====================================================================
    -- Test 2: AddonsClientTrait interface exists
    -- =====================================================================
    print("Test 2: AddonsClientTrait interface exists")
    package.loaded["integrations/sentinel_bridge/addons_client_trait"] = nil
    local AddonsClientTrait = require("integrations/sentinel_bridge/addons_client_trait")

    T.assert_not_nil(AddonsClientTrait.subscribe, "should have subscribe method")
    T.assert_not_nil(AddonsClientTrait.unsubscribe, "should have unsubscribe method")
    T.assert_not_nil(AddonsClientTrait.current_target, "should have current_target method")
    T.assert_not_nil(AddonsClientTrait.player_position, "should have player_position method")
    T.assert_not_nil(AddonsClientTrait.nearby_units, "should have nearby_units method")
    T.assert_not_nil(AddonsClientTrait.nearby_game_objects, "should have nearby_game_objects method")
    T.assert_not_nil(AddonsClientTrait.unit_info, "should have unit_info method")
    T.assert_not_nil(AddonsClientTrait.Waypoint, "should have Waypoint structure")
    T.assert_not_nil(AddonsClientTrait.UnitInfo, "should have UnitInfo structure")
    print("  PASS")

    -- =====================================================================
    -- Test 3: RenderSurfaceTrait interface exists with headless mode
    -- =====================================================================
    print("Test 3: RenderSurfaceTrait interface exists with headless mode")
    package.loaded["integrations/sentinel_bridge/render_surface_trait"] = nil
    local RenderSurfaceTrait = require("integrations/sentinel_bridge/render_surface_trait")

    T.assert_not_nil(RenderSurfaceTrait.register_panel, "should have register_panel method")
    T.assert_not_nil(RenderSurfaceTrait.draw, "should have draw method")
    T.assert_not_nil(RenderSurfaceTrait.draw_map_overlay, "should have draw_map_overlay method")
    T.assert_not_nil(RenderSurfaceTrait.set_visible, "should have set_visible method")
    T.assert_not_nil(RenderSurfaceTrait.get_screen_size, "should have get_screen_size method")
    T.assert_not_nil(RenderSurfaceTrait.create_headless, "should have create_headless factory")
    print("  PASS")

    -- =====================================================================
    -- Test 4: RenderSurfaceTrait headless implementation works
    -- =====================================================================
    print("Test 4: RenderSurfaceTrait headless implementation works")
    local headless = RenderSurfaceTrait.create_headless()

    T.assert_not_nil(headless.register_panel, "headless should have register_panel")
    T.assert_not_nil(headless.draw, "headless should have draw")
    T.assert_not_nil(headless.draw_map_overlay, "headless should have draw_map_overlay")

    headless:register_panel({ id = "test-panel", title = "Test", w = 100, h = 100 }, function() end)
    headless:draw({})
    headless:draw_map_overlay({ { type = "waypoint", point = { x = 0, y = 0, z = 0 } } })
    headless:set_visible(false)
    local screen = headless:get_screen_size()
    T.assert_equal(screen.x, 1920, "screen width should be 1920")
    T.assert_equal(screen.y, 1080, "screen height should be 1080")
    print("  PASS")

    -- =====================================================================
    -- Test 5: BridgeError types exist and are correct format
    -- =====================================================================
    print("Test 5: BridgeError types exist and are correct format")
    package.loaded["integrations/sentinel_bridge/bridge_error"] = nil
    local BridgeError = require("integrations/sentinel_bridge/bridge_error")

    T.assert_not_nil(BridgeError.api_unavailable, "should have api_unavailable factory")
    T.assert_not_nil(BridgeError.npc_not_found, "should have npc_not_found factory")
    T.assert_not_nil(BridgeError.quest_not_found, "should have quest_not_found factory")
    T.assert_not_nil(BridgeError.interaction_out_of_range, "should have interaction_out_of_range factory")
    T.assert_not_nil(BridgeError.timeout, "should have timeout factory")
    T.assert_not_nil(BridgeError.unexpected_game_state, "should have unexpected_game_state factory")
    T.assert_not_nil(BridgeError.is_fatal, "should have is_fatal predicate")
    T.assert_not_nil(BridgeError.format, "should have format helper")

    local api_err = BridgeError.api_unavailable()
    T.assert_equal(api_err.code, "API_UNAVAILABLE", "api_unavailable should have correct code")
    T.assert_true(BridgeError.is_fatal(api_err), "api_unavailable should be fatal")

    local npc_err = BridgeError.npc_not_found("test-guid")
    T.assert_equal(npc_err.code, "NPC_NOT_FOUND", "npc_not_found should have correct code")
    T.assert_false(BridgeError.is_fatal(npc_err), "npc_not_found should not be fatal")

    local timeout_err = BridgeError.timeout("accept_quest")
    T.assert_equal(timeout_err.code, "TIMEOUT", "timeout should have correct code")
    print("  PASS")

    -- =====================================================================
    -- Test 6: EventBridge translation table works
    -- =====================================================================
    print("Test 6: EventBridge translation table works")
    package.loaded["integrations/sentinel_bridge/event_bridge"] = nil
    package.loaded["integrations/sentinel_bridge/bridge_error"] = nil
    local EventBridge = require("integrations/sentinel_bridge/event_bridge")

    T.assert_not_nil(EventBridge.translate_event, "should have translate_event function")
    T.assert_not_nil(EventBridge.diff_quest_log, "should have diff_quest_log function")

    local semantic, data = EventBridge.translate_event("BAG_UPDATE", {})
    T.assert_equal(semantic, "inventory_changed", "BAG_UPDATE should translate to inventory_changed")

    semantic, data = EventBridge.translate_event("PLAYER_STOPPED_MOVING", {})
    T.assert_equal(semantic, "player_stopped_moving", "PLAYER_STOPPED_MOVING should translate correctly")

    semantic, data = EventBridge.translate_event("QUEST_LOG_UPDATE", {})
    T.assert_nil(semantic, "QUEST_LOG_UPDATE should return nil (requires diffing)")
    print("  PASS")

    -- =====================================================================
    -- Test 7: EventBridge quest log diffing works
    -- =====================================================================
    print("Test 7: EventBridge quest log diffing works")
    local old_log = { [123] = false, [456] = true }
    local new_log = { [123] = true, [789] = false }

    local changes = EventBridge.diff_quest_log(old_log, new_log)
    T.assert_true(T.table_contains(changes.completed, 123), "should detect quest 123 completed")
    T.assert_true(T.table_contains(changes.accepted, 789), "should detect quest 789 accepted")

    print("  PASS")

    -- =====================================================================
    -- Test 8: ApiVersion checking works
    -- =====================================================================
    print("Test 8: ApiVersion checking works")
    package.loaded["integrations/sentinel_bridge/api_version"] = nil
    local ApiVersion = require("integrations/sentinel_bridge/api_version")

    T.assert_not_nil(ApiVersion.check_availability, "should have check_availability")
    T.assert_not_nil(ApiVersion.verify_version, "should have verify_version")
    T.assert_not_nil(ApiVersion.get_quest_client, "should have get_quest_client")
    T.assert_not_nil(ApiVersion.get_addons_client, "should have get_addons_client")
    T.assert_not_nil(ApiVersion.CURRENT_API_VERSION, "should have CURRENT_API_VERSION constant")

    local available, err = ApiVersion.check_availability()
    if not _G.core then
        T.assert_false(available, "should report unavailable when core not present")
    end
    print("  PASS")

    -- =====================================================================
    -- Test 9: MockBridge implements traits correctly
    -- =====================================================================
    print("Test 9: MockBridge implements traits correctly")
    package.loaded["integrations/sentinel_bridge/mock_bridge"] = nil
    package.loaded["integrations/sentinel_bridge/bridge_error"] = nil
    local MockBridge = require("integrations/sentinel_bridge/mock_bridge")

    local mock = MockBridge:new(nil)
    local quest_client = mock:get_quest_client()
    local addons_client = mock:get_addons_client()

    T.assert_not_nil(quest_client.accept_quest, "mock quest_client should have accept_quest")
    T.assert_not_nil(quest_client.turn_in_quest, "mock quest_client should have turn_in_quest")
    T.assert_not_nil(quest_client.quest_log_entry, "mock quest_client should have quest_log_entry")
    T.assert_not_nil(addons_client.subscribe, "mock addons_client should have subscribe")
    T.assert_not_nil(addons_client.current_target, "mock addons_client should have current_target")
    T.assert_not_nil(addons_client.player_position, "mock addons_client should have player_position")
    print("  PASS")

    -- =====================================================================
    -- Test 10: MockBridge quest operations work
    -- =====================================================================
    print("Test 10: MockBridge quest operations work")
    local mock2 = MockBridge:new(nil)
    local qc = mock2:get_quest_client()

    local success, err = qc:accept_quest({ guid = "npc-1" }, 123)
    T.assert_true(success, "accept_quest should succeed")
    T.assert_nil(err, "accept_quest should not return error")

    local entry = qc:quest_log_entry(123)
    T.assert_not_nil(entry, "quest_log_entry should return entry")
    T.assert_equal(entry.quest_id, 123, "entry should have correct quest_id")
    T.assert_false(entry.is_complete, "quest should not be complete")

    success, err = qc:turn_in_quest({ guid = "npc-1" }, 123)
    T.assert_true(success, "turn_in_quest should succeed")

    entry = qc:quest_log_entry(123)
    T.assert_true(entry.is_complete, "quest should be complete after turn in")
    print("  PASS")

    -- =====================================================================
    -- Test 11: MockBridge addons operations work
    -- =====================================================================
    print("Test 11: MockBridge addons operations work")
    local mock3 = MockBridge:new(nil)
    local ac = mock3:get_addons_client()

    mock3:set_position(100, 200, 300)
    local pos = ac:player_position()
    T.assert_equal(pos.x, 100, "player_position should return correct x")

    mock3:add_unit("unit-1", { npc_id = 55, name = "Test NPC", position = { x = 10, y = 20, z = 0 } })
    local units = ac:nearby_units(40)
    T.assert_true(#units >= 1, "nearby_units should return units")

    local info = ac:unit_info({ guid = "unit-1" })
    T.assert_equal(info.npc_id, 55, "unit_info should return correct npc_id")
    print("  PASS")

    -- =====================================================================
    -- Test 12: SentinelBridge init uses traits
    -- =====================================================================
    print("Test 12: SentinelBridge init uses traits")
    package.loaded["integrations/sentinel_bridge/init"] = nil
    package.loaded["integrations/sentinel_bridge/quest_bridge"] = nil
    package.loaded["integrations/sentinel_bridge/addons_bridge"] = nil
    package.loaded["integrations/sentinel_bridge/render_bridge"] = nil
    package.loaded["integrations/sentinel_bridge/event_bridge"] = nil
    package.loaded["integrations/sentinel_bridge/api_version"] = nil

    local Blackboard = require("core/blackboard")
    local EventBus = require("core/event_bus")
    local SentinelBridge = require("integrations/sentinel_bridge/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()

    local bridge = SentinelBridge:create_mock(eb)
    T.assert_not_nil(bridge, "create_mock should return a bridge")
    T.assert_not_nil(bridge.accept_quest, "mock bridge should have accept_quest")
    T.assert_not_nil(bridge.turn_in_quest, "mock bridge should have turn_in_quest")
    T.assert_not_nil(bridge.current_target, "mock bridge should have current_target")
    T.assert_not_nil(bridge.player_position, "mock bridge should have player_position")

    local success = bridge:accept_quest("npc-test", 999)
    T.assert_true(success, "mock bridge accept_quest should work")
    print("  PASS")

    print("\n=== All Bridge Trait Tests PASSED ===")
    return true
end

return M