local TestUtil = require("tests/test_util")
local Lfg = require("modules/lfg/module")
local Settings = require("modules/lfg/settings")

local M = {}

function M.run()
    local previous_core = _G.core
    local calls = {}
    _G.core = {
        lfg_list = {
            search = function() calls[#calls + 1] = "search"; return true end,
            get_search_results = function() return { result_ids = { 11 } } end,
            has_search_result_info = function() return true end,
            get_search_result_info = function() return { is_delisted = false } end,
            get_search_result_member_counts = function() return { damager_remaining = 1 } end,
            apply_to_group = function() calls[#calls + 1] = "apply"; return true end,
            get_application_info = function() return { app_status = "invited" } end,
            accept_invite = function() calls[#calls + 1] = "accept"; return true end,
        },
    }

    local values = { ["system.now_ms"] = 20000 }
    local bb = {
        get = function(_, key, default) return values[key] == nil and default or values[key] end,
        set = function(_, key, value) values[key] = value end,
    }
    local bus = {
        subscribe = function() return "token" end,
        unsubscribe = function() end,
    }
    local module = Lfg.new(bus, bb)
    module:initialize()
    Settings.category_id = 1
    Settings.auto_accept_invite = true
    module:search()
    module._enabled = true
    module:_evaluate_results()
    module._pending_result_id = 11
    module._blackboard:set("module.lfg.enabled", true)
    module:_publish_application_state()

    TestUtil.assert_equal("search", calls[1])
    TestUtil.assert_equal("apply", calls[2])
    TestUtil.assert_equal("accept", calls[3])
    TestUtil.assert_equal("INVITE_ACCEPTED", values["module.lfg.state"])
    _G.core = previous_core
end

return M
