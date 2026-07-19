-- sentinel/tests/runtime/test_query_client.lua
-- Tests for runtime/query_client.lua (offline/mock mode)

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Runtime QueryClient Tests ===")

    -- Set up mock core with synchronous http_get that calls callback immediately
    local _http_calls = {}
    local _http_responses = {}  -- path_pattern → { http_code, content_type, body }

    _G.core = _G.core or {}
    _G.core.game_time = function() return 1000 end
    _G.core.http_get = function(url, callback)
        table.insert(_http_calls, url)
        -- Find matching response
        for pattern, resp in pairs(_http_responses) do
            if url:find(pattern, 1, true) then
                callback(resp[1], resp[2], resp[3], resp[4])
                return
            end
        end
        -- Default: 404
        callback(404, "text/plain", "Not Found", "")
    end

    local function set_http_response(pattern, http_code, body)
        _http_responses[pattern] = { http_code, "application/json", body, "" }
    end

    local function clear_http()
        _http_calls = {}
        _http_responses = {}
    end

    -- Clear package cache so fresh instance loads
    package.loaded["runtime/query_client"] = nil
    local QueryClient = require("runtime/query_client")

    -- =====================================================================
    -- Test 1: Construction and defaults
    -- =====================================================================
    print("Test 1: Construction and defaults")
    local qc = QueryClient.new()
    T.assert_equal(qc:get_base_url(), "http://127.0.0.1:3000")
    local stats = qc:get_stats()
    T.assert_equal(stats.entries, 0)
    T.assert_equal(stats.ttl_s, 300)
    T.assert_equal(stats.request_count, 0)
    T.assert_equal(stats.cache_hits, 0)
    print("  PASS")

    -- =====================================================================
    -- Test 2: Custom configuration
    -- =====================================================================
    print("Test 2: Custom configuration")
    local qc2 = QueryClient.new({ base_url = "http://localhost:8080", cache_ttl_s = 60 })
    T.assert_equal(qc2:get_base_url(), "http://localhost:8080")
    qc2:set_base_url("http://example.com")
    T.assert_equal(qc2:get_base_url(), "http://example.com")
    qc2:set_cache_ttl(120)
    stats = qc2:get_stats()
    T.assert_equal(stats.ttl_s, 120)
    print("  PASS")

    -- =====================================================================
    -- Test 3: Health check
    -- =====================================================================
    print("Test 3: Health check")
    clear_http()
    local qc3 = QueryClient.new()
    local result, err
    set_http_response("/health", 200, '{"status":"ok"}')
    qc3:health(function(data, e)
        result = data
        err = e
    end)
    T.assert_not_nil(result, "health should return data")
    T.assert_nil(err, "health should have no error")
    T.assert_equal(#_http_calls, 1, "should fire one HTTP request")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Quest search
    -- =====================================================================
    print("Test 4: Quest search")
    clear_http()
    local qc4 = QueryClient.new()
    local search_result
    set_http_response("/api/v1/quests/search", 200, '[{"id":33,"title":"Wolves Across the Border"}]')
    qc4:search_quests("wolves", function(data, e)
        search_result = data
    end)
    T.assert_not_nil(search_result, "search should return data")
    T.assert_equal(#search_result, 1)
    T.assert_equal(search_result[1].id, 33)
    T.assert_equal(search_result[1].title, "Wolves Across the Border")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Get quest by ID
    -- =====================================================================
    print("Test 5: Get quest by ID")
    clear_http()
    local qc5 = QueryClient.new()
    local quest
    set_http_response("/api/v1/quests/33", 200, '{"id":33,"title":"Wolves Across the Border","level":2}')
    qc5:get_quest(33, function(data, e)
        quest = data
    end)
    T.assert_not_nil(quest, "get_quest should return data")
    T.assert_equal(quest.id, 33)
    T.assert_equal(quest.level, 2)
    print("  PASS")

    -- =====================================================================
    -- Test 6: Invalid quest ID
    -- =====================================================================
    print("Test 6: Invalid quest ID")
    local qc6 = QueryClient.new()
    local q6_result, q6_err
    qc6:get_quest("not_a_number", function(data, e)
        q6_result = data
        q6_err = e
    end)
    T.assert_nil(q6_result, "should return nil data for invalid ID")
    T.assert_not_nil(q6_err, "should return error for invalid ID")
    print("  PASS")

    -- =====================================================================
    -- Test 7: NPC search
    -- =====================================================================
    print("Test 7: NPC search")
    clear_http()
    local qc7 = QueryClient.new()
    local npc_result
    set_http_response("/api/v1/npcs/search", 200, '[{"entry":197,"name":"Marshal McBride"}]')
    qc7:search_npcs("marshal", function(data, e)
        npc_result = data
    end)
    T.assert_not_nil(npc_result, "NPC search should return data")
    T.assert_equal(npc_result[1].entry, 197)
    print("  PASS")

    -- =====================================================================
    -- Test 8: Get NPC by entry
    -- =====================================================================
    print("Test 8: Get NPC by entry")
    clear_http()
    local qc8 = QueryClient.new()
    local npc
    set_http_response("/api/v1/npcs/197", 200, '{"entry":197,"name":"Marshal McBride","roles":["QuestGiver"]}')
    qc8:get_npc(197, function(data, e)
        npc = data
    end)
    T.assert_not_nil(npc, "get_npc should return data")
    T.assert_equal(npc.entry, 197)
    T.assert_equal(npc.name, "Marshal McBride")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Get creature by entry
    -- =====================================================================
    print("Test 9: Get creature by entry")
    clear_http()
    local qc9 = QueryClient.new()
    local creature
    set_http_response("/api/v1/creatures/", 200, '{"entry":1985,"name":"Young Wolf","level":1}')
    qc9:get_creature(1985, function(data, e)
        creature = data
    end)
    T.assert_not_nil(creature, "get_creature should return data")
    T.assert_equal(creature.entry, 1985)
    print("  PASS")

    -- =====================================================================
    -- Test 10: Caching — second call returns from cache
    -- =====================================================================
    print("Test 10: Caching")
    clear_http()
    local qc10 = QueryClient.new()
    set_http_response("/api/v1/quests/33", 200, '{"id":33,"title":"Wolves"}')
    -- First call — fires HTTP
    qc10:get_quest(33, function() end)
    T.assert_equal(#_http_calls, 1, "first call fires HTTP")

    -- Second call — should use cache
    local cached_quest
    qc10:get_quest(33, function(data, e)
        cached_quest = data
    end)
    T.assert_equal(#_http_calls, 1, "second call should use cache")
    T.assert_not_nil(cached_quest, "cached data should be returned")
    T.assert_equal(cached_quest.id, 33)

    stats = qc10:get_stats()
    T.assert_equal(stats.cache_hits, 1, "should have 1 cache hit")
    T.assert_equal(stats.request_count, 1, "should have only 1 request")
    print("  PASS")

    -- =====================================================================
    -- Test 11: Cache expiration
    -- =====================================================================
    print("Test 11: Cache expiration")
    clear_http()
    local qc11 = QueryClient.new({ cache_ttl_s = 1 })  -- 1 second TTL
    local time_counter = { value = 0 }
    _G.core.game_time = function() return time_counter.value end

    set_http_response("/health", 200, '{"status":"ok"}')
    qc11:health(function() end)
    T.assert_equal(#_http_calls, 1)

    -- Advance time beyond TTL (1 second = 1000ms)
    time_counter.value = 2000
    qc11:health(function() end)
    T.assert_equal(#_http_calls, 2, "should re-fetch after TTL expiry")

    -- Restore time
    _G.core.game_time = function() return 1000 end
    print("  PASS")

    -- =====================================================================
    -- Test 12: Cache invalidation
    -- =====================================================================
    print("Test 12: Cache invalidation")
    clear_http()
    local qc12 = QueryClient.new()
    set_http_response("/api/v1/quests/1", 200, '{"id":1}')
    qc12:get_quest(1, function() end)
    T.assert_equal(#_http_calls, 1)

    qc12:invalidate_cache()
    stats = qc12:get_stats()
    T.assert_equal(stats.entries, 0, "cache should be empty after invalidation")

    qc12:get_quest(1, function() end)
    T.assert_equal(#_http_calls, 2, "should re-fetch after invalidation")
    print("  PASS")

    -- =====================================================================
    -- Test 13: Pattern-based invalidation
    -- =====================================================================
    print("Test 13: Pattern-based invalidation")
    clear_http()
    local qc13 = QueryClient.new()
    set_http_response("/api/v1/quests/1", 200, '{"id":1}')
    set_http_response("/api/v1/npcs/100", 200, '{"entry":100}')
    qc13:get_quest(1, function() end)
    qc13:get_npc(100, function() end)
    T.assert_equal(#_http_calls, 2)

    -- Invalidate only quests
    qc13:invalidate_matching("^quests:")
    stats = qc13:get_stats()
    T.assert_equal(stats.entries, 1, "only quests should be invalidated")

    -- Quest should be re-fetched
    qc13:get_quest(1, function() end)
    T.assert_equal(#_http_calls, 3)
    -- NPC should still be cached
    qc13:get_npc(100, function() end)
    T.assert_equal(#_http_calls, 3, "NPC should still be cached")
    print("  PASS")

    -- =====================================================================
    -- Test 14: HTTP error handling
    -- =====================================================================
    print("Test 14: HTTP error handling")
    clear_http()
    local qc14 = QueryClient.new()
    local err_result, err_msg
    set_http_response("/health", 500, "Internal Server Error")
    qc14:health(function(data, e)
        err_result = data
        err_msg = e
    end)
    T.assert_nil(err_result, "should return nil data on HTTP error")
    T.assert_not_nil(err_msg, "should return error message")
    print("  PASS")

    -- =====================================================================
    -- Test 15: JSON parse error
    -- =====================================================================
    print("Test 15: JSON parse error")
    clear_http()
    local qc15 = QueryClient.new()
    local json_err_result, json_err_msg
    set_http_response("/health", 200, "not json at all {{{")
    qc15:health(function(data, e)
        json_err_result = data
        json_err_msg = e
    end)
    T.assert_nil(json_err_result, "should return nil on JSON error")
    T.assert_not_nil(json_err_msg, "should return parse error")
    print("  PASS")

    -- =====================================================================
    -- Test 16: In-flight deduplication
    -- =====================================================================
    print("Test 16: In-flight deduplication")
    clear_http()
    local qc16 = QueryClient.new()
    -- Replace http_get with one that does NOT call back immediately
    local pending_callbacks = {}
    _G.core.http_get = function(url, callback)
        table.insert(_http_calls, url)
        pending_callbacks[#pending_callbacks + 1] = callback
    end

    local r1, e1, r2, e2
    qc16:get_quest(50, function(data, e) r1 = data; e1 = e end)
    qc16:get_quest(50, function(data, e) r2 = data; e2 = e end)
    T.assert_equal(#_http_calls, 1, "should fire only one HTTP request")
    T.assert_equal(#pending_callbacks, 1, "should have one pending callback")

    -- Now resolve the request
    pending_callbacks[1](200, "application/json", '{"id":50}', "")
    T.assert_not_nil(r1, "first callback should have data")
    T.assert_not_nil(r2, "second callback should have data")
    T.assert_equal(r1.id, 50)
    T.assert_equal(r2.id, 50)

    -- Restore normal mock
    _G.core.http_get = function(url, callback)
        table.insert(_http_calls, url)
        for pattern, resp in pairs(_http_responses) do
            if url:find(pattern, 1, true) then
                callback(resp[1], resp[2], resp[3], resp[4])
                return
            end
        end
        callback(404, "text/plain", "Not Found", "")
    end
    print("  PASS")

    -- =====================================================================
    -- Test 17: URI encoding
    -- =====================================================================
    print("Test 17: URI encoding")
    local qc17 = QueryClient.new()
    T.assert_equal(qc17:_encode_uri("hello world"), "hello+world")
    T.assert_equal(qc17:_encode_uri("a&b=c"), "a%26b%3Dc")
    T.assert_equal(qc17:_encode_uri(nil), "")
    T.assert_equal(qc17:_encode_uri(""), "")
    print("  PASS")

    -- =====================================================================
    -- Test 18: No core.http_get available
    -- =====================================================================
    print("Test 18: No core.http_get available")
    local saved_http = _G.core.http_get
    _G.core.http_get = nil
    local qc18 = QueryClient.new()
    local no_result, no_err
    qc18:health(function(data, e)
        no_result = data
        no_err = e
    end)
    T.assert_nil(no_result, "should return nil when http_get unavailable")
    T.assert_not_nil(no_err, "should return error when http_get unavailable")
    _G.core.http_get = saved_http
    print("  PASS")

    -- =====================================================================
    -- Test 19: Route endpoint
    -- =====================================================================
    print("Test 19: Route endpoint")
    clear_http()
    local qc19 = QueryClient.new()
    local route_result
    set_http_response("/api/v1/route", 200, '{"distance":42,"waypoints":[]}')
    qc19:get_route(0, 50.0, 60.0, 1, 10.0, 20.0, function(data, e)
        route_result = data
    end)
    T.assert_not_nil(route_result, "route should return data")
    T.assert_equal(route_result.distance, 42)
    -- Verify URL contains parameters
    local route_url = _http_calls[#_http_calls]
    T.assert_true(route_url:find("from_map=0") ~= nil, "URL should contain from_map")
    T.assert_true(route_url:find("to_map=1") ~= nil, "URL should contain to_map")
    print("  PASS")

    -- =====================================================================
    -- Test 20: URL building
    -- =====================================================================
    print("Test 20: URL building")
    local qc20 = QueryClient.new({ base_url = "http://localhost:9090" })
    T.assert_equal(qc20:_build_url("/api/v1/test"), "http://localhost:9090/api/v1/test")
    T.assert_equal(qc20:_build_url("/health"), "http://localhost:9090/health")
    print("  PASS")

    print("\n=== All QueryClient Tests PASSED ===")
end

return M
