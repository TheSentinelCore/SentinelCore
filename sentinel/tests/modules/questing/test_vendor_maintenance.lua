-- tests/modules/questing/test_vendor_maintenance.lua
-- Unattended vendor maintenance: bags-full detection via UI_ERROR_MESSAGE,
-- grey-selling through use_container_item + QueryServer quality, and the
-- QuestingModule detour state machine's fail-safe paths.

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local QuestingModule = require("modules/questing/module")
local RuntimeAction = require("modules/questing/runtime_action")
local T = require("tests/test_util")

local M = {}

local function make_item(item_id)
    local obj = {}
    function obj:get_item_id() return item_id end
    return obj
end

--- A bag that actually loses what it sells.
---
--- The previous fixture returned a fresh three-item list on EVERY call, so
--- use_container_item removed nothing and bag 0 reported the same grey forever. No game
--- state can produce that. It only started to matter once execute_vendor began re-scanning
--- after the sell pass to prove the sale landed: against an immutable bag the re-scan
--- always finds the grey it just sold, so the stop can never complete.
---
--- get_items_in_bag hands back a COPY, mirroring an API that rebuilds its list from live
--- game state per call -- so selling mid-scan cannot disturb the loop in flight, while the
--- next scan correctly sees the item gone.
---
--- opts.merchant_window_closed models the live failure mode: interact_with_object opens the
--- merchant window ASYNCHRONOUSLY, so the sell call is issued but nothing leaves the bag.
local function install_bags(sold, opts)
    opts = opts or {}
    local bags = {
        [0] = {
            { object = make_item(100), slot_id = 1 }, -- grey
            { object = make_item(200), slot_id = 2 }, -- white
            { object = make_item(300), slot_id = 3 }, -- unknown to QueryServer
        },
    }

    local function remove(bag, slot_id)
        local contents = bags[bag]
        if not contents then return end
        for i, si in ipairs(contents) do
            if si.slot_id == slot_id then
                table.remove(contents, i)
                return
            end
        end
    end

    _G.core.input = {
        interact_with_object = function() end,
        use_container_item = function(bag, slot)
            sold[#sold + 1] = { bag = bag, slot = slot }
            if not opts.merchant_window_closed then remove(bag, slot) end
        end,
        repair_all_items = function() end,
    }
    _G.core.inventory = {
        get_items_in_bag = function(bag)
            local snapshot = {}
            for i, si in ipairs(bags[bag] or {}) do snapshot[i] = si end
            return snapshot
        end,
    }
end

--- ctx double for execute_vendor: at the NPC, with a scripted item-quality lookup.
local function make_vendor_ctx(qualities)
    local ctx = {
        persist = {},
        query = {
            get_item = function(_self, item_id)
                local q = qualities[item_id]
                if q == nil then return nil end
                return { entry = item_id, quality = q, name = "", sell_price = 1 }
            end,
        },
    }
    function ctx:is_at_npc(_entry, _range) return true end
    return ctx
end

function M.test_ui_error_sets_bags_full_flag()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    QuestingModule:new(bb, bus)
    bus:publish("game:ui_error", { error_type = 4, message = "Inventory is full." })
    T.assert_true(bb:get("player.bags_full") == true,
        "an inventory-full UI error must set player.bags_full")

    local bb2 = Blackboard:new()
    local bus2 = EventBus:new()
    QuestingModule:new(bb2, bus2)
    bus2:publish("game:ui_error", { error_type = 1, message = "You are too far away." })
    T.assert_false(bb2:get("player.bags_full") == true,
        "unrelated UI errors must not set the flag")
end

function M.test_vendor_sells_only_known_greys()
    local sold = {}
    _G.core = _G.core or {}
    local prev_input, prev_inv = _G.core.input, _G.core.inventory
    install_bags(sold)
    _G.core.object_manager = _G.core.object_manager or {}

    local ctx = make_vendor_ctx({ [100] = 0, [200] = 1 }) -- 300 intentionally missing
    local status = RuntimeAction.execute_vendor({ npc_entry = 5, sell_grey = true }, ctx)

    T.assert_equal(status, "success", "vendor stop should report success")
    T.assert_equal(#sold, 1, "exactly one item (the grey) must be sold")
    T.assert_equal(sold[1].bag, 0, "sold from the right bag")
    T.assert_equal(sold[1].slot, 1, "sold from the right slot")
    T.assert_equal(ctx.persist._item_quality[300], -1,
        "unknown quality must be cached as unsellable, never sold")

    -- Async pending: the lookup is in flight — hold the vendor stop and do NOT cache.
    -- Restock the bag: the case above genuinely sold item 100, and this assertion is only
    -- meaningful while the grey is still there to have its quality looked up.
    install_bags({})
    local ctx2 = make_vendor_ctx({})
    ctx2.query.get_item = function(_self, _item_id) return nil, true end
    local status2 = RuntimeAction.execute_vendor({ npc_entry = 5, sell_grey = true }, ctx2)
    T.assert_equal(status2, "retry", "pending quality lookups must hold the vendor stop")
    T.assert_equal(ctx2.persist._item_quality[100], nil,
        "a pending lookup must never be cached as unsellable")

    _G.core.input = prev_input
    _G.core.inventory = prev_inv
end

--- The live-caught fail-open. interact_with_object opens the merchant window
--- ASYNCHRONOUSLY, so the first tick's use_container_item calls are issued into a window
--- that is not open yet and sell nothing. execute_vendor reported "success" regardless,
--- which cleared player.bags_full and sent the bot back on route with the bags still
--- 16/16 full and unable to loot. The stop must hold until the greys have actually gone.
function M.test_vendor_holds_the_stop_until_greys_actually_leave_the_bag()
    local sold = {}
    _G.core = _G.core or {}
    local prev_input, prev_inv = _G.core.input, _G.core.inventory
    install_bags(sold, { merchant_window_closed = true })
    _G.core.object_manager = _G.core.object_manager or {}

    local ctx = make_vendor_ctx({ [100] = 0, [200] = 1 })
    local status = RuntimeAction.execute_vendor({ npc_entry = 5, sell_grey = true }, ctx)

    T.assert_equal(status, "retry",
        "a known grey still in the bag after the sell pass means the sale never landed")
    T.assert_equal(#sold, 1, "the sell call must still have been issued")

    _G.core.input = prev_input
    _G.core.inventory = prev_inv
end

--- ...and that hold is BOUNDED. A grey the merchant genuinely refuses must not wedge the
--- detour forever; after the tick budget the stop completes and the route resumes.
function M.test_vendor_stop_gives_up_on_a_grey_that_never_sells()
    local sold = {}
    _G.core = _G.core or {}
    local prev_input, prev_inv = _G.core.input, _G.core.inventory
    install_bags(sold, { merchant_window_closed = true })
    _G.core.object_manager = _G.core.object_manager or {}

    local ctx = make_vendor_ctx({ [100] = 0, [200] = 1 })
    local status
    for _ = 1, 12 do
        status = RuntimeAction.execute_vendor({ npc_entry = 5, sell_grey = true }, ctx)
    end

    T.assert_equal(status, "success",
        "an unsellable grey must not wedge the vendor detour forever")

    _G.core.input = prev_input
    _G.core.inventory = prev_inv
end

function M.test_maintenance_needed_reads_flag_and_repair_cost()
    _G.core = _G.core or {}
    local prev_inv = _G.core.inventory
    _G.core.inventory = { get_total_repair_cost = function() return 9999 end }

    local bb = Blackboard:new()
    local q = QuestingModule:new(bb, EventBus:new())
    T.assert_true(q:_maintenance_needed(), "a repair bill over the threshold must trigger maintenance")

    _G.core.inventory = { get_total_repair_cost = function() return 0 end }
    local bb2 = Blackboard:new()
    local q2 = QuestingModule:new(bb2, EventBus:new())
    T.assert_false(q2:_maintenance_needed(), "no flag and no repair bill: no maintenance")
    bb2:set("player.bags_full", true)
    T.assert_true(q2:_maintenance_needed(), "bags_full flag must trigger maintenance")

    _G.core.inventory = prev_inv
end

function M.test_maintenance_fails_safe_without_vendor()
    local bb = Blackboard:new()
    local q = QuestingModule:new(bb, EventBus:new())
    -- Executor double with no query client and no object manager access.
    q._executor = { _query = nil }
    bb:set("player.bags_full", true)
    T.assert_false(q:_run_vendor_maintenance(),
        "no visible vendor must NOT capture the tick — the route keeps moving")
    T.assert_equal(q._maintenance.state, "idle", "detour must stay idle without a vendor")
    T.assert_equal(bb:get("module.questing.maintenance"), "triggered, no vendor known",
        "the cockpit must surface WHY maintenance is pending (neither visible nor a known route vendor)")
end

local tests = {
    test_ui_error_sets_bags_full_flag = M.test_ui_error_sets_bags_full_flag,
    test_vendor_sells_only_known_greys = M.test_vendor_sells_only_known_greys,
    test_vendor_holds_the_stop_until_greys_actually_leave_the_bag =
        M.test_vendor_holds_the_stop_until_greys_actually_leave_the_bag,
    test_vendor_stop_gives_up_on_a_grey_that_never_sells =
        M.test_vendor_stop_gives_up_on_a_grey_that_never_sells,
    test_maintenance_needed_reads_flag_and_repair_cost = M.test_maintenance_needed_reads_flag_and_repair_cost,
    test_maintenance_fails_safe_without_vendor = M.test_maintenance_fails_safe_without_vendor,
}

function M.run()
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
