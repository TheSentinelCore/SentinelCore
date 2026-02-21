local T = require("tests/TestUtil")

local function run()
    local http_mode = "resolved"
    local last_url = nil
    local env = T.install_core_stub({
        http_get = function(url, cb)
            last_url = url
            if url:find("/context/resolve", 1, true) then
                if http_mode == "unresolved" then
                    cb(200, "application/json", [[{"resolved":false,"ambiguous":false}]], "")
                    return
                end
                if http_mode == "low_conf" then
                    cb(200, "application/json", [[{"resolved":true,"ambiguous":false,"diagnostic_confidence":0.2,"canonical_map_id":530,"zone_id":1,"area_id":2}]], "")
                    return
                end
                cb(200, "application/json", [[{"resolved":true,"ambiguous":false,"diagnostic_confidence":0.9,"canonical_map_id":530,"zone_id":1,"area_id":2}]], "")
                return
            end

            if url:find("/meta/dataset", 1, true) then
                cb(200, "application/json", [[{"game_version":"tbc","source":"cmangos"}]], "")
                return
            end

            if url:find("/vendors/nearby", 1, true) then
                cb(200, "application/json", [[{"items":[]}]], "")
                return
            end

            cb(200, "application/json", [[{"status":"ok"}]], "")
        end,
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local WorldDataAdapter = require("services/WorldDataAdapter")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local adapter = WorldDataAdapter:new(bus, bb, {
        base_url = "http://127.0.0.1:48100",
        api_version_prefix = "/api/v1",
        min_confidence = 0.6,
        expected_game_version = "tbc",
        expected_source = "cmangos",
    })

    local ctx = {
        ui_map_id = 1,
        instance_type = "none",
        position = { x = 1, y = 2, z = 3 },
    }

    http_mode = "unresolved"
    local ok1, err1 = nil, nil
    adapter:resolve_context(ctx, function(ok, _, err)
        ok1 = ok
        err1 = err
    end)
    T.assert_true(ok1 == false and err1 == ErrorCodes.CTX_UNRESOLVED, "unresolved context should fail")

    http_mode = "low_conf"
    local ok2, err2 = nil, nil
    adapter:resolve_context(ctx, function(ok, _, err)
        ok2 = ok
        err2 = err
    end)
    T.assert_true(ok2 == false and err2 == ErrorCodes.CTX_LOW_CONFIDENCE, "low confidence should fail")

    http_mode = "resolved"
    local ok3, canonical, err3 = nil, nil, nil
    adapter:resolve_context(ctx, function(ok, c, err)
        ok3 = ok
        canonical = c
        err3 = err
    end)
    T.assert_true(ok3 == true and canonical.map_id == 530 and err3 == nil, "resolved context should pass")

    local vendor_ok = nil
    adapter:get_nearby_vendors(
        { map_id = 530 },
        { position = { x = 1, y = 2, z = 3 }, radius = 100, require_sell = true, faction = 1 },
        function(ok)
            vendor_ok = ok
        end
    )
    T.assert_true(vendor_ok == true, "vendor query with player faction id should not fail")
    T.assert_true(last_url:find("faction=alliance", 1, true) ~= nil, "alliance faction template id should normalize")

    adapter:get_nearby_vendors(
        { map_id = 530 },
        { position = { x = 1, y = 2, z = 3 }, radius = 100, require_sell = true, faction = 469 },
        function() end
    )
    T.assert_true(last_url:find("faction=alliance", 1, true) ~= nil, "team filter should be normalized")

    adapter:get_nearby_vendors(
        { map_id = 530 },
        { position = { x = 1, y = 2, z = 3 }, radius = 100, require_sell = true, faction = 2 },
        function() end
    )
    T.assert_true(last_url:find("faction=horde", 1, true) ~= nil, "horde faction template id should normalize")

    adapter:get_nearby_vendors(
        { map_id = 530 },
        { position = { x = 1, y = 2, z = 3 }, radius = 100, require_sell = true, faction = 936 },
        function() end
    )
    T.assert_true(last_url:find("faction=neutral", 1, true) ~= nil, "neutral faction template id should normalize")

    return {
        sc006_context_resolve = true,
    }
end

return { run = run }
