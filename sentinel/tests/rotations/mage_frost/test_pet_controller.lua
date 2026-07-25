-- tests/rotations/mage_frost/test_pet_controller.lua
-- The frost mage's pet, as a kernel citizen (ADR 08 §2.2 PET, §3.2 intents, §6.1 leases).
--
-- ============================================================================
-- WHY THE REJECTIONS ARE THE SUBJECT AND THE SUCCESS PATH IS THE FOOTNOTE
-- ============================================================================
-- Every pet call this file covers used to be `pcall(core.input.pet_attack, target)` with the
-- result DISCARDED. With no pet, a dead pet, or a target that vanished between selection and
-- the packet, the old code did nothing and reported nothing -- §12's LazyBot complaint, in a
-- rotation. The conversion's entire return is that each of those now has a NAME, so this
-- suite asserts the named refusals at least as hard as the happy path.
--
-- ============================================================================
-- THE HARNESS RUNS THE REAL KERNEL, NOT A DOUBLE FOR IT
-- ============================================================================
-- The obvious shortcut is to hand PetController a fake intent queue and assert on what it was
-- handed. That proves the controller emits a table -- not that the kernel would accept it, gate
-- it, resolve its symbolic unit, or reach the SDK verb the rotation meant. So the harness
-- builds a REAL ControlBroker, a REAL IntentQueue with the REAL executors installed, and
-- publishes a REAL `_G.Sentinel` over them. The only doubles are the SDK boundary itself
-- (`core.input`, the object manager and the handles they hand back), because that boundary is
-- the one thing that cannot exist offline.

local Api = require("kernel/api")
local Blackboard = require("core/blackboard")
local ControlBroker = require("kernel/control_broker")
local Executors = require("kernel/intent_executors")
local IntentQueue = require("kernel/intent_queue")
local PetController = require("rotations/mage_frost/pet_controller")
local T = require("tests/test_util")

local M = {}

local FREEZE_SPELL_ID = 33395
local OWNER = "sentinel.rotation.mage_frost"

-- ---------------------------------------------------------------------------
-- Unit doubles (the SDK boundary)
-- ---------------------------------------------------------------------------

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:is_alive() return opts.alive ~= false end
    function unit:get_target() return opts.target end
    function unit:get_pet() return opts.pet end
    return unit
end

local function make_bb(overrides)
    overrides = overrides or {}

    local bb = Blackboard:new()
    local pet = overrides.pet and make_unit({
        guid = "pet",
        alive = overrides.pet_alive ~= false,
        target = overrides.pet_target,
    }) or nil

    bb:set("player.object", make_unit({ guid = "player", pet = pet }))
    return bb
end

-- ---------------------------------------------------------------------------
-- The kernel harness
-- ---------------------------------------------------------------------------

---Stand a real kernel up behind `_G.Sentinel`, run `fn(h)`, and put the surface back.
---
---`_G.Sentinel` is process-global and the offline runner publishes one for every plugin test,
---so the swap is undone through pcall: a throwing assertion must not leave the next suite
---looking at this one's broker.
---@param opts table|nil {
---   pet?, pet_alive?, target?, omit?, no_kernel?,
---   broker_has_no_queue?  -- a mis-wired kernel: leases are granted, submission has nowhere to go
---   refuse_submit_after?  -- accept N submissions, then refuse, to reach a PARTIAL failure
--- }
---@param fn fun(h: table)
local function with_kernel(opts, fn)
    opts = opts or {}

    local queue = IntentQueue:new()

    -- What the BROKER hands intents to. Usually the real queue; the two overrides exist because
    -- a refusal between "the lease was granted" and "the intent is pending" is otherwise
    -- unreachable from outside, and that is precisely the window in which a controller that
    -- discarded its submit result would look identical to one that checked it.
    local broker_queue = queue
    if opts.broker_has_no_queue then
        broker_queue = nil
    elseif opts.refuse_submit_after then
        local seen = 0
        broker_queue = {
            submit = function(_self, intent)
                seen = seen + 1
                if seen > opts.refuse_submit_after then return false, "queue_full" end
                return queue:submit(intent)
            end,
        }
    end

    local broker = ControlBroker:new({ intent_queue = broker_queue })
    -- ADR 08 §6.1 -- the revocation race check, wired exactly as runtime/app.lua wires it.
    queue:set_generation_validator(function(intent)
        return broker:is_generation_valid(intent)
    end)

    local calls = {}
    local pet = nil
    if opts.pet ~= false then
        pet = { id = "pet", is_alive = function() return opts.pet_alive ~= false end }
    end

    local target = nil
    if opts.target ~= false then target = { id = "target" } end

    local player = { get_pet = function() return pet end }

    local input = {
        pet_attack = function(unit)
            calls[#calls + 1] = { verb = "pet_attack", unit = unit }
            return true
        end,
        pet_cast_target_spell = function(spell_id, unit)
            calls[#calls + 1] = { verb = "pet_cast", spell_id = spell_id, unit = unit }
            return true
        end,
        set_pet_passive = function()
            calls[#calls + 1] = { verb = "set_pet_passive" }
            return true
        end,
        set_pet_follow = function()
            calls[#calls + 1] = { verb = "set_pet_follow" }
            return true
        end,
    }
    for _, name in ipairs(opts.omit or {}) do input[name] = nil end

    Executors.install({
        intent_queue = queue,
        object_manager = { get_local_player = function() return player end },
        unit_target = function() return target end,
        input = input,
    })

    local h = {
        queue = queue,
        broker = broker,
        calls = calls,
        input = input,
        target = target,
        pet = pet,
        commit = function() return queue:commit({}) end,
        called = function(verb)
            for _, c in ipairs(calls) do
                if c.verb == verb then return c end
            end
            return nil
        end,
    }

    local previous = _G.Sentinel
    if opts.no_kernel then
        _G.Sentinel = Api.build({})
    else
        _G.Sentinel = Api.build({ broker = broker, intent_queue = queue })
    end

    local ok, err = pcall(fn, h)
    _G.Sentinel = previous
    if not ok then error(err, 0) end
end

---The pet channel's holder, if any.
local function pet_owner(h)
    return h.broker:who_owns(ControlBroker.Channel.PET)
end

-- ---------------------------------------------------------------------------
-- Sensing: refresh() (unchanged by the conversion -- these are the pins)
-- ---------------------------------------------------------------------------

function M.test_a_new_controller_starts_idle()
    T.assert_equal(PetController:new():get_state(), "idle", "initial state should be idle")
end

function M.test_refresh_detects_a_live_pet()
    local pc = PetController:new()
    local bb = make_bb({ pet = true, pet_alive = true })
    pc:refresh(bb)
    T.assert_true(bb:get("combat.has_water_elemental"), "should detect live pet")
    T.assert_false(bb:get("combat.pet_is_attacking"), "pet without target should not be attacking")
end

function M.test_refresh_reports_a_pet_with_a_target_as_attacking()
    local pc = PetController:new()
    local bb = make_bb({ pet = true, pet_alive = true, pet_target = make_unit({ guid = "mob1" }) })
    pc:refresh(bb)
    T.assert_true(bb:get("combat.has_water_elemental"), "should detect live pet")
    T.assert_true(bb:get("combat.pet_is_attacking"), "pet with target should be attacking")
end

function M.test_refresh_with_no_pet_clears_both_flags()
    local pc = PetController:new()
    local bb = make_bb({ pet = false })
    pc:refresh(bb)
    T.assert_false(bb:get("combat.has_water_elemental"), "should detect no pet")
    T.assert_false(bb:get("combat.pet_is_attacking"), "no pet should not be attacking")
end

function M.test_refresh_with_a_dead_pet_clears_has_water_elemental()
    local pc = PetController:new()
    local bb = make_bb({ pet = true, pet_alive = false })
    pc:refresh(bb)
    T.assert_false(bb:get("combat.has_water_elemental"), "dead pet should set false")
end

function M.test_refresh_with_no_player_clears_both_flags()
    local pc = PetController:new()
    local bb = Blackboard:new()
    bb:set("player.object", nil)
    pc:refresh(bb)
    T.assert_false(bb:get("combat.has_water_elemental"), "no player should set false")
    T.assert_false(bb:get("combat.pet_is_attacking"), "no player should set pet_is_attacking false")
end

-- ---------------------------------------------------------------------------
-- Local state machine (pins -- deliberately unchanged by the conversion)
-- ---------------------------------------------------------------------------

function M.test_attack_transitions_to_attacking()
    with_kernel(nil, function()
        local pc = PetController:new()
        pc:attack(make_unit({ guid = "mob1" }))
        T.assert_equal(pc:get_state(), "attacking", "state should be attacking after attack")
    end)
end

function M.test_freeze_transitions_to_attacking()
    with_kernel(nil, function()
        local pc = PetController:new()
        pc:freeze(make_unit({ guid = "mob1" }))
        T.assert_equal(pc:get_state(), "attacking", "freeze should transition to attacking")
    end)
end

function M.test_passive_transitions_to_passive()
    with_kernel(nil, function()
        local pc = PetController:new()
        pc:attack(make_unit({ guid = "mob1" }))
        pc:passive()
        T.assert_equal(pc:get_state(), "passive", "state should be passive after passive")
    end)
end

function M.test_reset_returns_to_idle()
    with_kernel(nil, function()
        local pc = PetController:new()
        pc:attack(make_unit({ guid = "mob1" }))
        pc:reset()
        T.assert_equal(pc:get_state(), "idle", "state should be idle after reset")
    end)
end

function M.test_already_sent_to_matches_only_the_same_target()
    with_kernel(nil, function()
        local pc = PetController:new()
        local mob1, mob2 = make_unit({ guid = "mob1" }), make_unit({ guid = "mob2" })
        pc:attack(mob1)
        T.assert_true(pc:already_sent_to(mob1), "should recognize same target")
        T.assert_false(pc:already_sent_to(mob2), "should not match different target")
    end)
end

function M.test_already_sent_to_is_false_before_anything_was_sent()
    local pc = PetController:new()
    T.assert_false(pc:already_sent_to(make_unit({ guid = "mob1" })),
        "idle controller should not match any target")
end

function M.test_re_attacking_retargets_the_sent_marker()
    with_kernel(nil, function()
        local pc = PetController:new()
        local mob1, mob2 = make_unit({ guid = "mob1" }), make_unit({ guid = "mob2" })
        pc:attack(mob1)
        pc:passive()
        T.assert_equal(pc:get_state(), "passive", "should be passive")
        pc:attack(mob2)
        T.assert_equal(pc:get_state(), "attacking", "should be attacking again after re-attack")
        T.assert_true(pc:already_sent_to(mob2), "should track new target after re-attack")
        T.assert_false(pc:already_sent_to(mob1), "should not track old target after re-attack")
    end)
end

-- ---------------------------------------------------------------------------
-- The conversion: commands leave as intents, under a PET lease
-- ---------------------------------------------------------------------------

function M.test_an_attack_reaches_pet_attack_through_the_commit_stage()
    with_kernel(nil, function(h)
        local pc = PetController:new()
        local ok, reason = pc:attack(make_unit({ guid = "mob1" }))
        T.assert_true(ok, "the command must be accepted: " .. tostring(reason))
        T.assert_equal(h.called("pet_attack"), nil,
            "submission must NOT touch the SDK -- the commit stage does")

        local report = h.commit()
        T.assert_equal(#report.committed, 1, "one pet_command must commit")
        T.assert_equal(#report.rejected, 0, "and nothing may be rejected")
        local call = h.called("pet_attack")
        T.assert_not_nil(call, "core.input.pet_attack must be reached at commit")
        T.assert_true(call.unit == h.target, "the symbolic ref must resolve to the live handle")
    end)
end

--- ADR 08 §2.7 / invariant 2: a handle in an intent payload is a defect even when it works,
--- because the pointer can die inside the tick that produced it.
function M.test_an_intent_names_its_unit_symbolically_and_carries_no_handle()
    with_kernel(nil, function(h)
        local pc = PetController:new()
        local live_handle = make_unit({ guid = "mob1" })
        pc:attack(live_handle)

        T.assert_equal(h.queue:pending_count(), 1, "exactly one intent must be pending")
        local intent = h.queue._pending[1]
        T.assert_equal(intent.type, "pet_command")
        T.assert_equal(intent.payload.command, "attack")
        T.assert_equal(intent.payload.unit, "target", "the unit must be the symbolic reference")

        for key, value in pairs(intent.payload) do
            T.assert_true(type(value) ~= "table" and type(value) ~= "userdata",
                "payload field '" .. tostring(key) .. "' carries a handle-shaped value")
            T.assert_true(value ~= live_handle,
                "payload field '" .. tostring(key) .. "' is the live handle itself")
        end
    end)
end

function M.test_a_freeze_carries_the_water_elemental_freeze_spell()
    with_kernel(nil, function(h)
        local pc = PetController:new()
        local ok, reason = pc:freeze(make_unit({ guid = "mob1" }))
        T.assert_true(ok, "the freeze must be accepted: " .. tostring(reason))

        local report = h.commit()
        T.assert_equal(#report.committed, 1)
        local call = h.called("pet_cast")
        T.assert_not_nil(call, "pet_cast_target_spell must be reached")
        T.assert_equal(call.spell_id, FREEZE_SPELL_ID)
        T.assert_true(call.unit == h.target, "the freeze must land on the resolved target")
    end)
end

--- ADR 08 §2.2: PET is a channel precisely so a rotation holding CASTING does not implicitly
--- own the pet. A command that acquired nothing would be acting on ambient authority.
function M.test_a_pet_command_acquires_the_pet_channel()
    with_kernel(nil, function(h)
        T.assert_nil(pet_owner(h), "nothing may hold PET before the first command")
        PetController:new():attack(make_unit({ guid = "mob1" }))
        T.assert_equal(pet_owner(h), OWNER, "the command must hold PET under the plugin's id")
    end)
end

function M.test_a_pet_command_acquires_nothing_but_pet()
    with_kernel(nil, function(h)
        PetController:new():attack(make_unit({ guid = "mob1" }))
        for _, channel in ipairs(ControlBroker.CHANNELS) do
            if channel ~= ControlBroker.Channel.PET then
                T.assert_nil(h.broker:who_owns(channel),
                    "a pet command must not claim " .. channel)
            end
        end
    end)
end

--- Invariant 1: the intent must be authorised by the lease that produced it, and the commit
--- stage re-checks that generation. An intent whose generation does not match a live lease is
--- refused by name -- which is what makes "acquire PET" load-bearing rather than decorative.
function M.test_a_command_emitted_under_a_lease_that_was_released_dies_of_stale_generation()
    with_kernel(nil, function(h)
        local pc = PetController:new()
        pc:attack(make_unit({ guid = "mob1" }))

        -- Simulate the holder handing PET back before COMMIT ran.
        h.broker:revoke_owner(OWNER, "test")

        local report = h.commit()
        T.assert_equal(#report.committed, 0, "the command must not commit under a dead lease")
        T.assert_equal(#report.rejected, 1)
        T.assert_equal(report.rejected[1].gate, "generation")
        T.assert_equal(report.rejected[1].reason, "stale_generation")
        T.assert_nil(h.called("pet_attack"), "and the SDK must never be reached")
    end)
end

-- ---------------------------------------------------------------------------
-- passive() is TWO commands
-- ---------------------------------------------------------------------------

--- One intent doing two things cannot be individually rejected, gated or observed, which is
--- the whole reason a pet command is an intent. So `passive()` emits both, in order.
function M.test_passive_emits_passive_then_follow_as_separate_intents()
    with_kernel(nil, function(h)
        local ok, reason = PetController:new():passive()
        T.assert_true(ok, "both commands must be accepted: " .. tostring(reason))
        T.assert_equal(h.queue:pending_count(), 2, "passive and follow are two intents")

        local report = h.commit()
        T.assert_equal(#report.committed, 2, "both must commit")
        T.assert_equal(report.committed[1].payload.command, "passive", "passive goes first")
        T.assert_equal(report.committed[2].payload.command, "follow", "follow goes second")
        T.assert_not_nil(h.called("set_pet_passive"))
        T.assert_not_nil(h.called("set_pet_follow"))
    end)
end

--- The point of splitting them: each carries its OWN outcome. A compound command would have
--- one verdict for two verbs, so a follow that the SDK refused would hide behind a passive
--- that it accepted.
function M.test_passive_reports_each_command_separately()
    with_kernel({ omit = { "set_pet_follow" } }, function(h)
        local pc = PetController:new()
        local ok, reason, results = pc:passive()
        T.assert_true(ok, "both intents still SUBMIT -- the SDK gap shows up at commit")
        T.assert_nil(reason)
        T.assert_equal(#results, 2, "one result per command")
        T.assert_equal(results[1].command, "passive")
        T.assert_equal(results[2].command, "follow")

        local report = h.commit()
        T.assert_equal(#report.committed, 1, "passive still lands")
        T.assert_equal(#report.failed, 1, "follow fails on its own")
        T.assert_equal(report.failed[1].intent.payload.command, "follow")
        T.assert_equal(report.failed[1].reason, "no_set_pet_follow",
            "an absent SDK verb is a NAMED failure, not a silent no-op")
    end)
end

--- Two pet commands in one tick BOTH commit: the kernel's rule is one intent TYPE per channel
--- (Executors.CHANNEL_FOR), not one intent per channel per tick. Pinned because `passive()`
--- depends on it -- if the queue ever gained per-channel exclusivity, `follow` would be the
--- silent casualty and the pet would sit in place still set to passive.
function M.test_the_queue_permits_two_pet_commands_in_one_tick()
    with_kernel(nil, function(h)
        PetController:new():passive()
        local report = h.commit()
        T.assert_equal(#report.committed, 2,
            "the PET channel is not per-tick exclusive; passive() relies on that")
        T.assert_equal(#report.deduped, 0, "and the two are not the same action")
    end)
end

-- ---------------------------------------------------------------------------
-- THE REJECTIONS. This is what the conversion bought.
-- ---------------------------------------------------------------------------

--- Old behaviour: `pcall(core.input.pet_attack, target)` with no pet did nothing and said
--- nothing. Now the gate refuses it, by name, before the SDK is touched.
function M.test_a_command_with_no_pet_is_refused_by_name()
    with_kernel({ pet = false }, function(h)
        PetController:new():attack(make_unit({ guid = "mob1" }))
        local report = h.commit()
        T.assert_equal(#report.committed, 0)
        T.assert_equal(#report.rejected, 1)
        T.assert_equal(report.rejected[1].gate, "pet")
        T.assert_equal(report.rejected[1].reason, "no_pet")
        T.assert_nil(h.called("pet_attack"), "the SDK must not be reached without a pet")
    end)
end

function M.test_a_command_to_a_dead_pet_is_refused_by_name()
    with_kernel({ pet_alive = false }, function(h)
        PetController:new():freeze(make_unit({ guid = "mob1" }))
        local report = h.commit()
        T.assert_equal(#report.rejected, 1)
        T.assert_equal(report.rejected[1].reason, "pet_dead")
        T.assert_nil(h.called("pet_cast"))
    end)
end

--- The target the rotation picked can die, despawn or be deselected between the tick that
--- picked it and the commit that acts on it. The old code handed the SDK a nil and the SDK,
--- which "performs ZERO validation", sent a packet anyway.
function M.test_an_attack_at_a_vanished_target_is_refused_by_name()
    with_kernel({ target = false }, function(h)
        PetController:new():attack(make_unit({ guid = "mob1" }))
        local report = h.commit()
        T.assert_equal(#report.rejected, 1)
        T.assert_equal(report.rejected[1].gate, "pet")
        T.assert_equal(report.rejected[1].reason, "unit_unresolved")
        T.assert_nil(h.called("pet_attack"))
    end)
end

--- passive/follow name no unit, so a vanished target must NOT stop the pet being recalled --
--- which is exactly the moment a kiting mage needs it most.
function M.test_a_recall_still_works_with_no_target()
    with_kernel({ target = false }, function(h)
        PetController:new():passive()
        local report = h.commit()
        T.assert_equal(#report.committed, 2, "a recall names no unit and needs none")
        T.assert_not_nil(h.called("set_pet_follow"))
    end)
end

--- Without the kernel there is no lease, and without a lease the command must be REFUSED
--- rather than sent on ambient authority. The old code reached `core.input` directly and so
--- had no such moment to fail at.
function M.test_without_a_control_broker_the_command_is_refused_by_name()
    with_kernel({ no_kernel = true }, function(h)
        local pc = PetController:new()
        local ok, reason = pc:attack(make_unit({ guid = "mob1" }))
        T.assert_false(ok, "no broker means no authority")
        T.assert_equal(reason, "no_control")
        T.assert_equal(h.queue:pending_count(), 0, "and nothing may reach the queue")
        T.assert_nil(h.called("pet_attack"))
    end)
end

function M.test_without_a_control_broker_a_recall_is_refused_by_name()
    with_kernel({ no_kernel = true }, function()
        local ok, reason, results = PetController:new():passive()
        T.assert_false(ok)
        T.assert_equal(reason, "no_control")
        T.assert_equal(#results, 0, "a lease that was never granted commands nothing")
    end)
end

--- A higher-band holder owns PET; the rotation must not get it. This is the channel doing its
--- job -- the case a permission column on CASTING could not express.
function M.test_a_pet_channel_held_at_a_higher_band_refuses_the_rotation()
    with_kernel(nil, function(h)
        local held = h.broker:acquire({
            channel = ControlBroker.Channel.PET,
            owner = "sentinel.safety.leash",
            band = "SAFETY",
            ttl_ticks = 4,
        })
        T.assert_not_nil(held, "the safety holder must get PET")

        local ok, reason = PetController:new():attack(make_unit({ guid = "mob1" }))
        T.assert_false(ok, "the rotation must not outrank SAFETY on PET")
        T.assert_equal(reason, "channel_held")
        T.assert_equal(h.queue:pending_count(), 0)
        T.assert_equal(pet_owner(h), "sentinel.safety.leash", "and the holder keeps it")
    end)
end

--- A lease is not the same thing as delivery. The broker grants PET, and submission STILL
--- fails -- which is exactly the window a controller that discarded its submit result would
--- report as success, because it never got as far as a gate that could name anything.
function M.test_a_granted_lease_with_nowhere_to_submit_is_refused_by_name()
    with_kernel({ broker_has_no_queue = true }, function(h)
        local ok, reason, results = PetController:new():attack(make_unit({ guid = "mob1" }))
        T.assert_false(ok, "a granted lease is not delivery")
        T.assert_equal(reason, "no_intent_queue")
        T.assert_equal(#results, 1, "the refused command must still be reported")
        T.assert_false(results[1].ok)
        T.assert_equal(results[1].reason, "no_intent_queue")
        T.assert_equal(pet_owner(h), OWNER, "the lease was genuinely granted")
        T.assert_equal(h.queue:pending_count(), 0, "and nothing reached the queue")
    end)
end

--- THE PARTIAL FAILURE, which is the whole argument for two intents. `passive` lands, `follow`
--- is refused, and the caller can tell WHICH -- something a single compound command could not
--- express, because it would have one verdict for two verbs.
function M.test_passive_reports_which_of_the_two_commands_was_refused()
    with_kernel({ refuse_submit_after = 1 }, function(h)
        local ok, reason, results = PetController:new():passive()
        T.assert_false(ok, "a partial recall is not a success")
        T.assert_equal(reason, "queue_full", "the refusal must be named, not swallowed")

        T.assert_equal(#results, 2, "one result per command, refused or not")
        T.assert_equal(results[1].command, "passive")
        T.assert_true(results[1].ok, "passive was accepted")
        T.assert_nil(results[1].reason)
        T.assert_equal(results[2].command, "follow")
        T.assert_false(results[2].ok, "follow was refused")
        T.assert_equal(results[2].reason, "queue_full")

        local report = h.commit()
        T.assert_equal(#report.committed, 1, "only the accepted half may reach the SDK")
        T.assert_not_nil(h.called("set_pet_passive"))
        T.assert_nil(h.called("set_pet_follow"),
            "the pet must not be recorded as recalled when the recall never left")
    end)
end

--- A caretaker is valid for the tick that issued it and no longer (§6.1). Acquiring in one
--- tick and submitting in the next must be refused, not quietly honoured.
function M.test_a_caretaker_does_not_survive_the_tick_that_issued_it()
    with_kernel(nil, function(h)
        local pc = PetController:new()
        pc:attack(make_unit({ guid = "mob1" }))
        h.commit()

        h.broker:end_tick()
        h.broker:begin_tick(1)

        -- A fresh command on the new tick must acquire again rather than reuse the stale one.
        local ok, reason = pc:attack(make_unit({ guid = "mob2" }))
        T.assert_true(ok, "a new tick must yield a fresh caretaker: " .. tostring(reason))
        local report = h.commit()
        T.assert_equal(#report.committed, 1, "and its intent must still commit")
    end)
end

-- ---------------------------------------------------------------------------
-- The audit's own claim, checked from the plugin side
-- ---------------------------------------------------------------------------

--- tests/kernel/test_plugin_core_access_audit.lua asserts this across the whole package. This
--- is the same claim asserted where the change actually happened, so a regression in THIS file
--- is reported by THIS suite rather than only by an audit two directories away.
function M.test_the_controller_names_core_nowhere()
    local handle = io.open("sentinel/rotations/mage_frost/pet_controller.lua", "r")
    T.assert_not_nil(handle, "pet_controller.lua must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()

    local line_number = 0
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        line_number = line_number + 1
        if not line:match("^%s*%-%-") then
            T.assert_nil(line:match("%f[%w_]core%s*%."),
                "direct SDK access at pet_controller.lua:" .. line_number .. " -- " .. line)
        end
    end
end

return M
