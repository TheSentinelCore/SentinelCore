local TestUtil = require("tests/test_util")
local QueryClient = require("modules/quest/query_client")

local M = {}

function M.run()
    -- Test that query client can be constructed and handles errors gracefully
    local bb = {
        get = function(_, _, default) return default end,
        set = function(_, _, _) end,
    }
    
    local client = QueryClient.new(bb)
    TestUtil.assert_not_nil(client, "query client should be constructable")
    
    -- Test cache miss returns nil gracefully
    TestUtil.assert_nil(QueryClient.get_cached_quest(999999), "cache miss should return nil")
end

return M