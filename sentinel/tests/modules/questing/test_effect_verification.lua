-- tests/modules/questing/test_effect_verification.lua
-- Train/Hearth/Loot must verify their observable effect instead of reporting
-- "success" after merely interacting (audit fix B).

local Blackboard = require("core/blackboard")
local RuntimeAction = require("modules/questing/runtime_action")
local T = require("tests/test_util")

local M = {}

-- Controllable clock + player position; restores every core.* field it touches.
local function with_world(setup, fn)
    local prev = {
        time = _G.core.time,
        object_manager = _G.core.object_manager,
        input = _G.core.input,
        spell_book = _G.core.spell_book,
    }
    local world = { now = 0, pos = { x = 0, y = 0, z = 0 } }
    _G.core.time = function() return world.now end
    _G.core.object_manager = {
        get_local_player = function()
            return {
                is_valid = function() return true end,
                get_position = function() return world.pos end,
            }
        end,
        get_all_objects = function() return world.objects or {} end,
    }
    _G.core.input = setup.input or {}
    _G.core.spell_book = setup.spell_book
    local ok, err = pcall(fn, world)
    _G.core.time = prev.time
    _G.core.object_manager = prev.object_manager
    _G.core.input = prev.input
    _G.core.spell_book = prev.spell_book
    if not ok then error(err) end
end

local function notes_ctx(extra)
    local ctx = extra or {}
    ctx.persist = ctx.persist or {}
    ctx.notes = {}
    ctx.event_bus = {
        publish = function(_self, topic, entry)
            ctx.notes[#ctx.notes + 1] = { topic = topic, entry = entry }
        end,
    }
    return ctx
end

-- ======================================================================
-- Train
-- ======================================================================

function M.test_train_verifies_spell_count_growth()
    local spells = { [133] = "Fireball", [168] = "Frost Armor" }
    with_world({ spell_book = { get_spells = function() return spells end } }, function(world)
        local ctx = notes_ctx()
        function ctx:is_at_npc() return true end

        T.assert_equal(RuntimeAction.execute_train({ npc_entry = 5 }, ctx), "retry",
            "no observable change yet: the attempt must not claim success")
        world.now = 3
        T.assert_equal(RuntimeAction.execute_train({ npc_entry = 5 }, ctx), "retry",
            "still nothing learned: keep burning the retry budget, never lie")

        spells[5504] = "Conjure Water"
        world.now = 6
        T.assert_equal(RuntimeAction.execute_train({ npc_entry = 5 }, ctx), "success",
            "a grown spell book is the observable proof of training")
        T.assert_equal(#ctx.notes, 0, "verified training must not log train_unverified")
    end)
end

function M.test_train_attempts_pace_on_real_time()
    local spells = { [133] = "Fireball" }
    with_world({ spell_book = { get_spells = function() return spells end } }, function(world)
        local ctx = notes_ctx()
        function ctx:is_at_npc() return true end
        T.assert_equal(RuntimeAction.execute_train({ npc_entry = 5 }, ctx), "retry", "first attempt fires")
        world.now = 0.5
        T.assert_equal(RuntimeAction.execute_train({ npc_entry = 5 }, ctx), "waiting",
            "attempts pace on real time, not frames")
    end)
end

function M.test_train_without_spell_api_logs_unverified_once()
    with_world({ spell_book = nil }, function()
        local ctx = notes_ctx()
        function ctx:is_at_npc() return true end
        T.assert_equal(RuntimeAction.execute_train({ npc_entry = 5 }, ctx), "success",
            "no verifiable signal: keep success, but say so in the log")
        T.assert_equal(RuntimeAction.execute_train({ npc_entry = 5 }, ctx), "success")
        local unverified = 0
        for _, n in ipairs(ctx.notes) do
            if n.entry and n.entry.event == "train_unverified" then unverified = unverified + 1 end
        end
        T.assert_equal(unverified, 1, "train_unverified is logged exactly once")
    end)
end

-- ======================================================================
-- Hearth
-- ======================================================================

function M.test_hearth_waits_then_succeeds_on_position_jump()
    local used = {}
    with_world({ input = { use_item = function(id) used[#used + 1] = id end } }, function(world)
        local ctx = notes_ctx()
        T.assert_equal(RuntimeAction.execute_hearth({}, ctx), "waiting",
            "hearth is a 10s cast: casting is not arriving")
        T.assert_equal(used[1], 6948, "hearthstone item used")
        world.now = 8
        T.assert_equal(RuntimeAction.execute_hearth({}, ctx), "waiting", "mid-cast holds")
        world.now = 12
        world.pos = { x = 2000, y = 0, z = 0 }
        T.assert_equal(RuntimeAction.execute_hearth({}, ctx), "success",
            "a >500yd position jump is the observable teleport")
        T.assert_equal(#used, 1, "no re-cast while the first cast is verifying")
    end)
end

function M.test_hearth_times_out_to_retry_and_recasts()
    local used = {}
    with_world({ input = { use_item = function(id) used[#used + 1] = id end } }, function(world)
        local ctx = notes_ctx()
        world.now = 100
        T.assert_equal(RuntimeAction.execute_hearth({}, ctx), "waiting")
        world.now = 119
        T.assert_equal(RuntimeAction.execute_hearth({}, ctx), "waiting", "under 20s still holds")
        world.now = 121
        T.assert_equal(RuntimeAction.execute_hearth({}, ctx), "retry",
            "20s with no teleport: hand the tick to the retry budget")
        T.assert_equal(RuntimeAction.execute_hearth({}, ctx), "waiting", "retry re-casts fresh")
        T.assert_equal(#used, 2, "the retry attempt casts again")
    end)
end

-- ======================================================================
-- Loot
-- ======================================================================

local function loot_world_object(entry)
    return {
        is_valid = function() return true end,
        is_unit = function() return false end,
        is_game_object = function() return true end,
        get_entry_id = function() return entry end,
        get_position = function() return { x = 1, y = 0, z = 0 } end,
    }
end

local function loot_ctx(counts)
    local bb = Blackboard:new()
    local ctx = notes_ctx({ blackboard = bb })
    function ctx:is_at_object() return true end
    function ctx:get_item_count(item_id) return counts[item_id] or 0 end
    return ctx, bb
end

function M.test_loot_verifies_item_count_increase()
    local looted = {}
    with_world({ input = { loot_object = function(obj) looted[#looted + 1] = obj end } }, function(world)
        world.objects = { loot_world_object(42) }
        local counts = { [777] = 0 }
        local ctx = loot_ctx(counts)
        T.assert_equal(RuntimeAction.execute_loot({ object_entry = 42, item_id = 777 }, ctx), "waiting",
            "interacting is not looting: hold until the item shows up")
        T.assert_equal(#looted, 1, "loot interaction issued once")
        world.now = 2
        counts[777] = 1
        T.assert_equal(RuntimeAction.execute_loot({ object_entry = 42, item_id = 777 }, ctx), "success",
            "the item count increase is the observable loot")
    end)
end

function M.test_loot_times_out_to_retry()
    with_world({ input = { loot_object = function() end } }, function(world)
        world.objects = { loot_world_object(42) }
        local ctx = loot_ctx({ [777] = 0 })
        T.assert_equal(RuntimeAction.execute_loot({ object_entry = 42, item_id = 777 }, ctx), "waiting")
        world.now = 6
        T.assert_equal(RuntimeAction.execute_loot({ object_entry = 42, item_id = 777 }, ctx), "retry",
            "5s with no item: retry (bounded by the action budget)")
    end)
end

function M.test_loot_bags_full_returns_retry_for_maintenance()
    with_world({ input = { loot_object = function() end } }, function(world)
        world.objects = { loot_world_object(42) }
        local ctx, bb = loot_ctx({ [777] = 0 })
        T.assert_equal(RuntimeAction.execute_loot({ object_entry = 42, item_id = 777 }, ctx), "waiting")
        bb:set("player.bags_full", true)
        world.now = 1
        T.assert_equal(RuntimeAction.execute_loot({ object_entry = 42, item_id = 777 }, ctx), "retry",
            "full bags during the wait must yield so the vendor detour can run")
    end)
end

function M.test_loot_without_item_id_logs_unverified_once()
    with_world({ input = { loot_object = function() end } }, function(world)
        world.objects = { loot_world_object(42) }
        local ctx = loot_ctx({})
        T.assert_equal(RuntimeAction.execute_loot({ object_entry = 42 }, ctx), "success",
            "no item id in the payload: current behavior, honestly logged")
        T.assert_equal(RuntimeAction.execute_loot({ object_entry = 42 }, ctx), "success")
        local unverified = 0
        for _, n in ipairs(ctx.notes) do
            if n.entry and n.entry.event == "loot_unverified" then unverified = unverified + 1 end
        end
        T.assert_equal(unverified, 1, "loot_unverified is logged exactly once")
    end)
end

local tests = {
    test_train_verifies_spell_count_growth = M.test_train_verifies_spell_count_growth,
    test_train_attempts_pace_on_real_time = M.test_train_attempts_pace_on_real_time,
    test_train_without_spell_api_logs_unverified_once = M.test_train_without_spell_api_logs_unverified_once,
    test_hearth_waits_then_succeeds_on_position_jump = M.test_hearth_waits_then_succeeds_on_position_jump,
    test_hearth_times_out_to_retry_and_recasts = M.test_hearth_times_out_to_retry_and_recasts,
    test_loot_verifies_item_count_increase = M.test_loot_verifies_item_count_increase,
    test_loot_times_out_to_retry = M.test_loot_times_out_to_retry,
    test_loot_bags_full_returns_retry_for_maintenance = M.test_loot_bags_full_returns_retry_for_maintenance,
    test_loot_without_item_id_logs_unverified_once = M.test_loot_without_item_id_logs_unverified_once,
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
