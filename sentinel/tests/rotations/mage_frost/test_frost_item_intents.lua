-- tests/rotations/mage_frost/test_frost_item_intents.lua
-- The two potion actions, PINNED BEFORE they move onto the `use_item` intent.
--
-- ================================================================================
-- WHY THESE PINS EXIST AND WHAT THEY ARE FOR
-- ================================================================================
-- `frost_actions.lua` tracks a HARD-CODED two-minute potion cooldown on the blackboard
-- (`combat.potion_cd_until_ms`). The kernel's ITEMS gate asks the client instead, through
-- `get_item_cooldown`. Those are two sources of truth for a number the client owns, and they
-- disagree the moment a potion shares its cooldown with a trinket, or the moment the character
-- drinks one by hand.
--
-- Converting therefore CHANGES BEHAVIOUR. So the behaviour was written down FIRST, as it is
-- today, and watched pass against the unconverted file. The pins that then go red are the
-- measured delta -- not tests that needed fixing.
--
-- Every function below the DELTA PINS banner is expected to move. Each is named for what the
-- code does TODAY, which is the only naming that makes the red meaningful.
--
-- ================================================================================
-- THE PINS ARE ON OUTCOMES, NOT ON MECHANISM
-- ================================================================================
-- Each pin asks three questions a player could answer by watching the character:
--
--   1. what did the action return,
--   2. did an item packet leave, carrying which id,
--   3. what did the blackboard hold afterwards.
--
-- None of them names the SDK entry point or the intent queue directly, which is what lets the
-- SAME assertion run against both the old direct-call path and the new commit-stage path. A pin
-- written against the mechanism would have to be rewritten in order to convert, and a rewritten
-- pin measures nothing.
--
-- The packet recorder is installed in BOTH places for that reason: as the SDK's item verb (what
-- the old code calls) and as the executor's injected `input` (what the new code reaches). One
-- log, two eras.

local Api = require("kernel/api")
local IntentQueue = require("kernel/intent_queue")
local Executors = require("kernel/intent_executors")
local ControlBroker = require("kernel/control_broker")
local Snapshot = require("kernel/snapshot")
local Blackboard = require("core/blackboard")
local Status = require("core/bt/status")
local Act = require("rotations/mage_frost/frost_actions")
local T = require("tests/test_util")

local M = {}

--- TBC consumables. Real ids, so a reader can tell the two apart at a glance.
local HEALTH_POTION = 22829
local MANA_POTION = 22832

local TWO_MINUTES_MS = 120000

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

---Run `body(h)` against a live kernel with `_G.Sentinel` published over it.
---
---The surface is REAL (`Api.build` with a real broker and a real IntentQueue), not a stub: the
---plugin reaches the kernel through `_G.Sentinel` and nothing else, so a stubbed surface would
---let the plugin pass against a shape the kernel does not have.
---
---Both globals are restored even when `body` throws -- these tests run inside the shared offline
---suite, and a leaked `_G.Sentinel` would silently reconfigure every suite that follows.
---@param opts table|nil { now_ms?, has_item?, item_cooldown?, use_item_result?, no_broker?,
---                        items_held_by? }
local function with_harness(opts, body)
    opts = opts or {}

    local packets = {}
    local record_use = function(item_id)
        packets[#packets + 1] = { item_id = item_id }
        if opts.use_item_result ~= nil then return opts.use_item_result end
        return true
    end
    --- The quarantined movement site presses this one directly. Recorded, not converted.
    local key_presses = {}
    local record_move = function()
        key_presses[#key_presses + 1] = "move_forward_start"
        return true
    end

    local input = { use_item = record_use, move_forward_start = record_move }

    local player = {}
    function player:has_item(_item_id)
        if opts.has_item == nil then return true end
        return opts.has_item
    end
    --- The client's own answer, in milliseconds remaining. Zero is "ready".
    function player:get_item_cooldown(_item_id)
        return opts.item_cooldown or 0
    end

    local queue = IntentQueue:new()
    local broker = ControlBroker:new({ input = input, intent_queue = queue })
    queue:set_generation_validator(function(intent)
        return broker:is_generation_valid(intent)
    end)
    Executors.install({
        intent_queue = queue,
        input = input,
        object_manager = { get_local_player = function() return player end },
    })

    -- A rival already sitting on ITEMS, so a refused acquisition can be OBSERVED rather than
    -- assumed. SAFETY outranks the rotation's COMBAT, so it cannot be preempted.
    if opts.items_held_by then
        broker:acquire({
            channel = "ITEMS",
            owner = opts.items_held_by,
            band = "SAFETY",
            ttl_ticks = 5,
        })
    end

    local bb = Blackboard:new()
    bb:set("system.now_ms", opts.now_ms or 1000)

    local h = {
        bb = bb,
        queue = queue,
        broker = broker,
        packets = packets,
        key_presses = key_presses,
        commit = function() return queue:commit(Snapshot.empty(0)) end,
    }

    -- THE SDK SURFACE IS REBUILT, NOT PATCHED. By the time the rotation suites run,
    -- `tests/runtime/test_sensor_hub.lua:156` has set the `core` global to nil -- under a comment
    -- claiming to "restore default core" -- and a later combat suite has re-created it as a bare
    -- table with no input surface. So the unconverted potion path, which guards on
    -- `type(<sdk>.input.use_item) == "function"`, is UNREACHABLE in the shared suite unless the
    -- harness puts that surface back. That is why the two item sites had no coverage before this
    -- file: not because they were hard to test, but because the harness had quietly removed the
    -- thing they call. Restored exactly as found, so the landmine is neither spread nor hidden.
    local saved_surface = _G.Sentinel
    local saved_core = _G.core
    local saved_input = saved_core and saved_core.input

    _G.core = saved_core or {}
    _G.core.input = input

    local kernel = { intent_queue = queue }
    if not opts.no_broker then kernel.broker = broker end
    _G.Sentinel = Api.build(kernel)

    local ok, err = pcall(body, h)

    if saved_core then
        saved_core.input = saved_input
    end
    _G.core = saved_core
    _G.Sentinel = saved_surface
    if not ok then error(err, 0) end
end

---The single packet the action was supposed to send, or nil.
local function only_packet(h)
    if #h.packets == 0 then return nil end
    T.assert_equal(#h.packets, 1, "expected at most one item packet, got " .. #h.packets)
    return h.packets[1]
end

-- ---------------------------------------------------------------------------
-- STABLE PINS -- behaviour the conversion must NOT change
-- ---------------------------------------------------------------------------

function M.test_a_health_potion_with_no_item_id_sends_nothing()
    with_harness(nil, function(h)
        T.assert_equal(Act.use_health_potion(h.bb), Status.FAILURE,
            "no id on the blackboard means no potion")
        h.commit()
        T.assert_nil(only_packet(h), "nothing may leave without an item id")
    end)
end

function M.test_a_mana_potion_with_no_item_id_sends_nothing()
    with_harness(nil, function(h)
        T.assert_equal(Act.use_mana_potion(h.bb), Status.FAILURE,
            "no id on the blackboard means no potion")
        h.commit()
        T.assert_nil(only_packet(h), "nothing may leave without an item id")
    end)
end

function M.test_a_health_potion_names_the_item_id_it_was_given()
    with_harness(nil, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS,
            "a carried, ready potion is used")
        h.commit()
        local packet = only_packet(h)
        T.assert_not_nil(packet, "a potion packet must leave")
        T.assert_equal(packet.item_id, HEALTH_POTION, "the packet carries the health potion id")
    end)
end

function M.test_a_mana_potion_names_the_item_id_it_was_given()
    with_harness(nil, function(h)
        h.bb:set("combat.mana_potion_id", MANA_POTION)
        T.assert_equal(Act.use_mana_potion(h.bb), Status.SUCCESS,
            "a carried, ready potion is used")
        h.commit()
        local packet = only_packet(h)
        T.assert_not_nil(packet, "a potion packet must leave")
        T.assert_equal(packet.item_id, MANA_POTION, "the packet carries the mana potion id")
    end)
end

--- The far edge of the old timer: the millisecond it expires is INCLUSIVE. Expected to stay
--- green across the conversion, but for two different reasons -- the old code compares
--- `now < cd`, and the new one does not consult that timer at all. A pin that only holds by
--- coincidence is still the pin that catches the day the coincidence ends.
function M.test_a_potion_is_admitted_on_the_exact_expiry_millisecond()
    with_harness({ now_ms = 500000 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        h.bb:set("combat.potion_cd_until_ms", 500000)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS,
            "now == cd is ready, not one millisecond early")
        h.commit()
        T.assert_not_nil(only_packet(h), "the potion leaves on the expiry millisecond")
    end)
end

--- `Act.cancel_current_cast` presses a movement key directly. It is NOT converted here: movement
--- is a separate channel with a separate track, and a follow-on decides whether this site should
--- become a `move` intent at all or delegate to NavClient. Pinned so the item conversion cannot
--- drift into it by accident.
function M.test_cast_cancellation_is_left_on_its_direct_movement_path()
    with_harness(nil, function(h)
        T.assert_equal(Act.cancel_current_cast(h.bb), Status.SUCCESS,
            "the movement site still works, unconverted")
        T.assert_true(h.bb:get("combat._cancel_cast_pending") == true,
            "and still records its own pending flag")
        T.assert_equal(#h.key_presses, 1, "the key is still pressed straight at the SDK")
        T.assert_nil(h.broker:who_owns("MOVEMENT"),
            "it takes no MOVEMENT lease -- that is Track A's conversion, not this one")
    end)
end

-- ---------------------------------------------------------------------------
-- DELTA PINS -- the hard-coded timer, as it behaves TODAY
-- ---------------------------------------------------------------------------
--
-- Everything below describes the UNCONVERTED file. These are the pins expected to go red, and
-- each red is a behaviour delta to be reported -- input, old behaviour, new behaviour, and
-- whether the new behaviour is correct -- before any of them is touched.

--- THE SECOND SOURCE OF TRUTH ITSELF. The action writes a two-minute expiry onto the blackboard
--- after every use, and three OTHER files read that key.
function M.test_a_used_potion_arms_a_two_minute_blackboard_timer()
    with_harness({ now_ms = 1000 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        h.commit()
        T.assert_equal(h.bb:get("combat.potion_cd_until_ms"), 1000 + TWO_MINUTES_MS,
            "the plugin keeps its own copy of a number the client owns")
    end)
end

--- The near edge of the old timer: one millisecond early is refused, whatever the client thinks.
function M.test_the_blackboard_timer_blocks_a_potion_one_millisecond_early()
    with_harness({ now_ms = 499999, item_cooldown = 0 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        h.bb:set("combat.potion_cd_until_ms", 500000)
        T.assert_equal(Act.use_health_potion(h.bb), Status.FAILURE,
            "the plugin's own timer vetoes, even though the client says ready")
        h.commit()
        T.assert_nil(only_packet(h), "nothing leaves")
    end)
end

--- Health and mana potions DO share a cooldown in TBC, and the old code models that by writing
--- one shared key from both actions.
function M.test_the_two_potions_share_one_hard_coded_timer()
    with_harness({ now_ms = 1000 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        h.bb:set("combat.mana_potion_id", MANA_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS, "the health potion goes")
        T.assert_equal(Act.use_mana_potion(h.bb), Status.FAILURE,
            "and blocks the mana potion for two minutes, from the blackboard")
    end)
end

--- THE DIVERGENCE, STATED DIRECTLY. The client reports a minute of cooldown left; the blackboard
--- timer is clear. The old code believes the blackboard and sends the packet anyway.
function M.test_the_clients_real_item_cooldown_is_ignored()
    with_harness({ now_ms = 1000, item_cooldown = 60000 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS,
            "the client is never asked")
        h.commit()
        T.assert_not_nil(only_packet(h), "so a packet leaves during a live cooldown")
    end)
end

--- The old code never asks whether the character is carrying the potion. It reads an id off the
--- blackboard and fires.
function M.test_a_potion_the_character_does_not_carry_is_still_sent()
    with_harness({ has_item = false }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS,
            "the bag is never consulted")
        h.commit()
        T.assert_not_nil(only_packet(h), "so a packet leaves for an item that is not there")
    end)
end

--- The old code wraps the SDK call in a bare `pcall` and returns SUCCESS regardless, so a
--- refusal is indistinguishable from a drink. ADR 08 §12's complaint about empty catch bodies.
function M.test_a_refused_item_use_is_invisible_to_the_kernel()
    with_harness({ use_item_result = false }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS,
            "a refusal still reads as success")
        local report = h.commit()
        T.assert_equal(#report.failed, 0, "and never reaches the tick report")
    end)
end

--- Invariant 1, as it is violated today: a game-affecting call under NO authority at all.
function M.test_using_a_potion_takes_no_control_lease()
    with_harness(nil, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        T.assert_nil(h.broker:who_owns("ITEMS"),
            "ambient authority: the potion goes without claiming the channel")
    end)
end

--- The packet reaches the SDK without the commit stage ever seeing it -- no gate, no band, no
--- generation check.
function M.test_a_potion_reaches_the_sdk_without_passing_through_the_kernel()
    with_harness(nil, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        local report = h.commit()
        T.assert_not_nil(only_packet(h), "the packet left")
        T.assert_equal(#report.committed, 0, "but the kernel committed nothing")
        T.assert_equal(h.queue:pending_count(), 0, "and nothing was ever submitted")
    end)
end

--- With no broker published at all, the old code is unaffected: it never asked for one.
function M.test_a_potion_is_sent_with_no_control_broker_present()
    with_harness({ no_broker = true }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS,
            "no broker, no problem -- which is the problem")
        h.commit()
        T.assert_not_nil(only_packet(h), "the packet leaves regardless")
    end)
end

--- ITEMS held by a higher band. Today that is invisible to the action.
function M.test_a_potion_is_sent_while_another_owner_holds_the_items_channel()
    with_harness({ items_held_by = "sentinel.behavior.corpse_run" }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS,
            "a SAFETY-band holder of ITEMS does not stop the rotation")
        h.commit()
        T.assert_not_nil(only_packet(h), "the packet leaves anyway")
    end)
end

return M
