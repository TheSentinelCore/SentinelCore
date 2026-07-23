-- tests/runtime/test_callback_bridge.lua
-- F6: publish_engine must skip building its payload when the target event has zero
-- subscribers, instead of building it 3x/frame regardless (see runtime/callback_bridge.lua).

local EventBus = require("core/event_bus")
local CallbackBridge = require("runtime/callback_bridge")
local T = require("tests/test_util")

local M = {}

--- Count SDK calls a payload build would trigger, without actually depending on any of them
--- being present (offline `core` has none of these mocked, matching the real gap this finding
--- describes: every call is unconditionally attempted before F6).
local function install_counting_core_time_apis()
    local calls = 0
    local saved = {
        game_time = core and core.game_time,
        delta_time = core and core.delta_time,
        get_ping = core and core.get_ping,
        get_map_id = core and core.get_map_id,
        get_map_name = core and core.get_map_name,
    }
    _G.core = _G.core or {}
    core.game_time = function() calls = calls + 1; return 123 end
    core.delta_time = function() calls = calls + 1; return 0.016 end
    core.get_ping = function() calls = calls + 1; return 50 end
    core.get_map_id = function() calls = calls + 1; return 1 end
    core.get_map_name = function() calls = calls + 1; return "Test Zone" end
    return function()
        calls = 0
        core.game_time = saved.game_time
        core.delta_time = saved.delta_time
        core.get_ping = saved.get_ping
        core.get_map_id = saved.get_map_id
        core.get_map_name = saved.get_map_name
    end, function() return calls end
end

function M.test_publish_engine_skips_payload_build_with_zero_subscribers()
    local restore, get_calls = install_counting_core_time_apis()
    local bus = EventBus:new()
    local bridge = CallbackBridge:new(bus)

    bridge:publish_engine("engine:pre_tick")

    local calls = get_calls()
    restore()
    T.assert_equal(calls, 0,
        "publish_engine must not call any engine time/map SDK function when nobody subscribed")
end

function M.test_publish_engine_still_builds_and_publishes_with_a_subscriber()
    local restore, get_calls = install_counting_core_time_apis()
    local bus = EventBus:new()
    local bridge = CallbackBridge:new(bus)

    local received = nil
    bus:subscribe("engine:pre_tick", function(payload) received = payload end)

    bridge:publish_engine("engine:pre_tick")

    local calls = get_calls()
    restore()
    T.assert_true(calls > 0, "publish_engine must build the real payload when a subscriber exists")
    T.assert_true(received ~= nil, "the subscriber must actually receive the published payload")
    T.assert_equal(received.now_ms, 123, "payload fields must be populated from the SDK, not stubbed out")
end

function M.run()
    M.test_publish_engine_skips_payload_build_with_zero_subscribers()
    M.test_publish_engine_still_builds_and_publishes_with_a_subscriber()
end

return M
