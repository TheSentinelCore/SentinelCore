local TestUtil = require("tests/test_util")
local Mail = require("modules/mail/module")

local M = {}

function M.run()
    local previous_core = _G.core
    local calls = {}
    _G.core = {
        game_time = function() return 10000 end,
        mail = {
            check_inbox = function() calls[#calls + 1] = "check" end,
            get_num_inbox_items = function() return 3 end,
            get_inbox_header_info = function(index)
                return {
                    cod_amount = 0,
                    money = index == 2 and 5000 or 0,
                    item_count = index == 1 and 1 or 0,
                    subject = index == 3 and "Cheap Gold" or "Legit Mail",
                    sender = "SomePlayer",
                }
            end,
            inbox_item_can_delete = function(index) return index == 3 end,
            take_inbox_money = function(index) calls[#calls + 1] = { take_money = index } end,
            auto_loot_mail_item = function(index) calls[#calls + 1] = { loot_item = index } end,
            delete_inbox_item = function(index) calls[#calls + 1] = { delete = index } end,
        },
    }

    local bb = {
        get = function(_, _, default) return default end,
        set = function(_, _, _) end,
    }
    local bus = {
        subscribe = function(_) return "token" end,
        unsubscribe = function() end,
    }

    local mail = Mail.new(bus, bb)
    mail:start()

    mail._is_at_mailbox = true
    mail:process_mail()

    TestUtil.assert_true(calls[1] == "check", "should check inbox")
    TestUtil.assert_true(calls[2].delete == 3, "should delete spam mail index 3 (processed first)")
    TestUtil.assert_true(calls[3].take_money == 2, "should take money from mail index 2")
    TestUtil.assert_true(calls[4].loot_item == 1, "should loot items from mail index 1")
    _G.core = previous_core
end

return M