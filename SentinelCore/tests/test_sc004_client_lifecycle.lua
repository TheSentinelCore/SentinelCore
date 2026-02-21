local T = require("tests/TestUtil")

local function run()
    local player = T.mock_object({
        level = 10,
        class_id = 2,
        spec_id = 0,
        position = { x = 1, y = 2, z = 3 },
        xp = 100,
        max_xp = 1000,
    })

    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return {} end,
        },
    })

    local Client = require("core/Client")

    local fake_nav = {
        update = function() end,
        is_available = function() return true, nil end,
        is_server_available = function() return true end,
        stop = function() end,
        move_to = function(_, _, cb) if cb then cb(true, nil, nil) end end,
        estimate_path_cost = function(_, _, _, cb) cb(true, 10, nil) end,
    }

    local fake_world = {
        update = function(_, _) end,
        resolve_context = function(_, _, cb)
            cb(true, { map_id = 530, zone_id = 3518, area_id = 3520, confidence = 1.0 }, nil)
        end,
    }

    local client = Client:new({
        navigation_adapter = fake_nav,
        world_data_adapter = fake_world,
    })
    local Events = require("events/Events")

    local started_event = nil
    client:get_event_bus():on(Events.STARTED, function(data)
        started_event = data
    end)

    local ok, err = client:start("grind")
    T.assert_true(ok == true, "client start failed: " .. tostring(err))
    T.assert_eq(client:get_state(), "running", "state should be running")
    T.assert_true(started_event ~= nil, "started event not emitted")
    T.assert_true(type(started_event.session_id) == "string" and started_event.session_id ~= "",
        "started event should include session_id")
    T.assert_true(type(started_event.state) == "string" and started_event.state ~= "",
        "started event should include state")

    local ok2 = client:start("grind")
    T.assert_true(ok2 == true, "start should be idempotent")

    local paused = client:pause("test")
    T.assert_true(paused == true, "pause failed")
    T.assert_eq(client:get_state(), "paused", "state should be paused")

    local resumed = client:resume()
    T.assert_true(resumed == true, "resume failed")
    T.assert_eq(client:get_state(), "running", "state should be running after resume")

    local stopped = client:stop("done")
    T.assert_true(stopped == true, "stop failed")
    T.assert_eq(client:get_state(), "idle", "state should be idle after stop")

    T.assert_true(client:stop("again") == true, "second stop should be idempotent")

    local feed = client:get_log_feed(50)
    T.assert_true(type(feed) == "table" and #feed > 0, "runtime log feed should have lifecycle entries")
    client:clear_log_feed()
    T.assert_eq(#client:get_log_feed(10), 0, "runtime log feed should clear")

    return {
        sc004_lifecycle = true,
    }
end

return { run = run }
