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
local Bands = require("kernel/bands")
local Snapshot = require("kernel/snapshot")
local Blackboard = require("core/blackboard")
local Status = require("core/bt/status")
local Act = require("rotations/mage_frost/frost_actions")
local T = require("tests/test_util")

local M = {}

--- TBC consumables. Real ids, so a reader can tell the two apart at a glance.
local HEALTH_POTION = 22829
local MANA_POTION = 22832

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
-- THE MEASURED DELTA -- ten pins that moved, and what each one measured
-- ---------------------------------------------------------------------------
--
-- Each function below was written against the UNCONVERTED file, watched pass, and then watched
-- FAIL after the conversion. Every docstring records the old behaviour it used to assert, so the
-- delta stays readable from the test rather than only from a commit message. The assertion is
-- the NEW behaviour; the `WAS:` line is what it replaced.
--
-- Six other pins in this file did NOT move. That matters as much: the conversion changed the
-- cooldown authority and the authorisation, and changed neither the item id that is sent nor the
-- refusal when there is no id to send.

--- THE SECOND SOURCE OF TRUTH ITSELF, now deleted.
--- WAS: after a use, `combat.potion_cd_until_ms` held `now + 120000`.
--- Correct: yes. Three files still READ that key and every one of those reads is now permanently
--- "ready" -- recorded as a finding, because a key with readers and no writer is a lie in slow
--- motion, not a tidy deletion.
function M.test_a_used_potion_no_longer_arms_a_two_minute_blackboard_timer()
    with_harness({ now_ms = 1000 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        h.commit()
        T.assert_nil(h.bb:get("combat.potion_cd_until_ms"),
            "the client owns this number -- the plugin must not keep a second copy")
    end)
end

--- WAS: FAILURE and no packet, because the plugin's own expiry was one millisecond away.
--- Correct: yes. The client reported ready; the blackboard's number was a stale local guess, and
--- a guess must not veto the authority.
function M.test_a_stale_blackboard_timer_no_longer_vetoes_a_ready_potion()
    with_harness({ now_ms = 499999, item_cooldown = 0 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        h.bb:set("combat.potion_cd_until_ms", 500000)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS,
            "the client says ready, so a leftover blackboard expiry is not a veto")
        h.commit()
        T.assert_not_nil(only_packet(h), "and the potion leaves")
    end)
end

--- WAS: the health potion armed the shared key and the mana potion was refused BY THE ACTION.
--- Correct: yes, with a cost worth naming. Health and mana potions really do share a cooldown in
--- TBC, and the old code got that rule right by hard-coding it. The rule has not been lost -- it
--- moved to the client, which is asked in the gate (`item_cooldown` is 0 in this fixture, which
--- is the fixture speaking, not the game). What genuinely changed is that the ACTION now forms an
--- intent it previously never formed: the rotation submits, and the gate refuses. That costs one
--- submission per off-GCD tick and buys a refusal the tick report can name.
function M.test_the_shared_potion_cooldown_is_now_the_clients_to_enforce()
    with_harness({ now_ms = 1000 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        h.bb:set("combat.mana_potion_id", MANA_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.SUCCESS, "the health potion goes")
        T.assert_equal(Act.use_mana_potion(h.bb), Status.SUCCESS,
            "and the mana potion is submitted rather than pre-refused from the blackboard")
    end)
end

--- THE DIVERGENCE THIS CONVERSION EXISTS TO CLOSE.
--- WAS: SUCCESS and a packet sent into a live 60-second cooldown, because the client was never
--- asked and the blackboard's copy was clear.
--- Correct: yes, unambiguously. This is the case a shared trinket cooldown produces in the game.
function M.test_the_clients_real_item_cooldown_now_refuses_the_potion()
    with_harness({ now_ms = 1000, item_cooldown = 60000 }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        local report = h.commit()
        T.assert_nil(only_packet(h), "the client says 60s remaining -- nothing may leave")
        T.assert_equal(#report.rejected, 1, "the refusal must be recorded, not silent")
        T.assert_equal(report.rejected[1].reason, "item_on_cooldown", "and recorded BY NAME")
    end)
end

--- WAS: SUCCESS and a packet for an item that was not in the bag -- the old action read an id off
--- the blackboard and fired without ever asking whether it was carried.
--- Correct: yes.
function M.test_a_potion_the_character_does_not_carry_is_now_refused()
    with_harness({ has_item = false }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        local report = h.commit()
        T.assert_nil(only_packet(h), "an absent potion cannot be drunk")
        T.assert_equal(#report.rejected, 1, "the refusal must be recorded")
        T.assert_equal(report.rejected[1].reason, "item_absent", "and named")
    end)
end

--- WAS: the SDK's refusal vanished. The old code discarded the return value inside a bare pcall
--- and reported SUCCESS, so a refusal and a drink were indistinguishable -- ADR 08 §12's
--- complaint about empty catch bodies, in this file.
--- Correct: yes.
function M.test_a_refused_item_use_is_now_visible_to_the_kernel()
    with_harness({ use_item_result = false }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        local report = h.commit()
        T.assert_equal(#report.failed, 1, "the SDK's refusal must reach the tick report")
        T.assert_equal(report.failed[1].reason, "use_item_refused", "by name")
    end)
end

--- INVARIANT 1: one intent per channel, one authorising lease.
--- WAS: nobody owned ITEMS. The potion was ambient authority -- a game-affecting call under no
--- claim at all.
--- Correct: yes.
function M.test_using_a_potion_acquires_the_items_channel()
    with_harness(nil, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_nil(h.broker:who_owns("ITEMS"), "nothing holds ITEMS before the action runs")
        Act.use_health_potion(h.bb)
        local owner = h.broker:who_owns("ITEMS")
        T.assert_not_nil(owner, "a use_item intent must be authorised by an ITEMS lease")
        T.assert_equal(owner, "sentinel.rotation.mage_frost", "and the rotation must own it")
    end)
end

--- WAS: the packet reached the SDK with the commit stage never seeing it -- no gate, no band, no
--- generation check.
---
--- ALSO THE ONE THAT IS EASY TO GET WRONG IN THE OTHER DIRECTION. Releasing the lease on the way
--- out of the action looks tidy and is fatal: `release` removes it from the broker's holdings,
--- and the commit stage validates an intent's generation by looking its lease UP in those
--- holdings. A polite release would make every potion intent fail its own generation check,
--- silently, one stage later. This pin is what would catch that.
function M.test_the_items_lease_outlives_the_action_so_the_intent_can_commit()
    with_harness(nil, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        local report = h.commit()
        T.assert_equal(#report.committed, 1,
            "the intent must still be authorised when COMMIT runs")
        T.assert_equal(#report.rejected, 0, "and must not be rejected as a stale generation")
        T.assert_not_nil(only_packet(h), "so the packet leaves through the kernel")
    end)
end

--- The band a potion competes at, pinned because nothing else pins it and it is a one-word edit
--- away from being wrong. `submit` stamps the intent with the LEASE's resolved priority, so this
--- is the number the dedupe and the band sort actually see. COMBAT.min, deliberately: a health
--- potion at 30% is arguably defensive, but promoting these two entries into SURVIVAL is a
--- separate arguable change and would not be measurable alongside the item conversion.
function M.test_a_potion_competes_at_the_rotations_own_combat_band()
    with_harness(nil, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        Act.use_health_potion(h.bb)
        local report = h.commit()
        T.assert_equal(#report.committed, 1, "the intent committed")
        T.assert_equal(report.committed[1].band, Bands.BANDS.COMBAT.min,
            "a potion arbitrates at COMBAT, not above it")
    end)
end

--- WAS: SUCCESS and a packet, because the old code never asked for a broker.
--- Correct: yes, and deliberately fail-CLOSED. The operational consequence is real and worth
--- stating: if the kernel is not up, potions stop. That is the same trade the castable gate makes
--- -- an absent validator is not permission.
function M.test_a_potion_without_a_control_broker_sends_nothing()
    with_harness({ no_broker = true }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.FAILURE,
            "no broker is no authority, and no authority is no packet")
        h.commit()
        T.assert_nil(only_packet(h), "nothing may leave unauthorised")
    end)
end

--- WAS: SUCCESS and a packet. A higher-band holder of ITEMS was invisible to the action.
--- Correct: yes. The rotation cannot preempt SAFETY, so it is refused at the BROKER rather than
--- at the gate -- which is the point of making ITEMS a channel at all.
function M.test_a_potion_refuses_when_a_higher_band_holds_the_items_channel()
    with_harness({ items_held_by = "sentinel.behavior.corpse_run" }, function(h)
        h.bb:set("combat.health_potion_id", HEALTH_POTION)
        T.assert_equal(Act.use_health_potion(h.bb), Status.FAILURE,
            "ITEMS is held at SAFETY -- the rotation waits")
        h.commit()
        T.assert_nil(only_packet(h), "nothing may leave without the channel")
        T.assert_equal(h.broker:who_owns("ITEMS"), "sentinel.behavior.corpse_run",
            "and the incumbent keeps the channel")
    end)
end

return M
