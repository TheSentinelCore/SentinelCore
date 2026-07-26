-- tests/modules/combat/test_retribution_tbc.lua
-- The retribution GCD tree's priority order, pinned across the kernel port.
--
-- ================================================================================
-- WHAT THE PORT CHANGED IN THIS FILE, LINE BY LINE
-- ================================================================================
-- EVERY ASSERTION IS UNCHANGED. `actions[n].action` and `actions[n].spell_id` mean exactly what they
-- meant before: which decision the tree chose, and which spell id it resolved. What changed is where
-- the log is written from.
--
--   BEFORE  the action called `H.queue_target`, which read `module.combat.dispatcher` off the
--           blackboard and called `d:queue_target(action_id, spell_id, target, priority, message)`.
--           The test's dispatcher double recorded `{ spell_id, action = message }`.
--
--   AFTER   the action emits a `cast` intent under a CASTING lease. At COMMIT the kernel's cast
--           executor calls `spell_queue:queue_spell_target(spell_id, unit, priority, message)` with
--           `message = payload.label` -- the SAME string the dispatcher carried
--           (`intent_executors.lua`: "The rotation's action name says WHICH decision cast").
--           The test's spell_queue double records the same two fields.
--
-- So the recorder moved one stage later and one layer down; the assertion did not have to move at
-- all. That is the property that makes this a port rather than a rewrite -- a pin written against
-- the MECHANISM would have needed rewriting to convert, and a rewritten pin measures nothing.
--
-- WHAT THIS FILE STILL CANNOT SEE, and now cannot see one more thing:
--   * WHEN the packet leaves. In the old era the SDK call happened inside the action; now it happens
--     at COMMIT. Every pin below commits before asserting, so that ordering difference is
--     deliberately invisible here. It is pinned in tests/kernel/test_scheduler.lua.
--   * WHETHER THE INTENT WOULD HAVE BEEN REFUSED IN THE CLIENT. `timing` is absent, so the GCD gate
--     permits (`intent_executors.lua:219`), and `is_spell_castable` is a fixture answering true.
--     Both were equally invisible to the dispatcher double, so nothing regressed -- but neither is
--     evidence about a live client.

local Api = require("kernel/api")
local IntentQueue = require("kernel/intent_queue")
local Executors = require("kernel/intent_executors")
local ControlBroker = require("kernel/control_broker")
local Snapshot = require("kernel/snapshot")
local Units = require("kernel/units")
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local Profile = require("rotations/paladin_retribution/retribution_tbc")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health_percentage() return opts.health_pct or 1.0 end
    function unit:is_dead() return false end
    function unit:get_target() return opts.target end
    function unit:has_buff(buff_id)
        local buffs = opts.buffs or {}
        if type(buff_id) == "table" then
            for _, id in ipairs(buff_id) do
                if buffs[id] then return true end
            end
            return false
        end
        return buffs[buff_id] == true
    end
    function unit:get_buff_data(spell_id)
        return { is_active = unit:has_buff(spell_id), stack_count = 0 }
    end
    function unit:get_buff_stacks(_spell_id) return 0 end
    function unit:get_buffs() return {} end
    function unit:is_casting_spell() return opts.casting == true end
    function unit:is_channelling_spell() return false end
    function unit:is_active_spell_interruptable() return opts.interruptible ~= false end
    return unit
end

--- Clear the log IN PLACE.
---
--- `actions = {}` would rebind the local and leave the recorder writing into the old table, which
--- the old dispatcher-era file could get away with because it rebuilt the double each time. The
--- recorder here is installed once per scenario, so the log has to be emptied rather than replaced.
local function clear(log)
    for i = #log, 1, -1 do log[i] = nil end
end

--- A live kernel with `_G.Sentinel` published over it, recording what reaches the spell queue.
---
--- ONE frozen snapshot for the whole scenario, so the tick a unit ref is MINTED under is the tick
--- COMMIT runs under. Two would make every cast stale -- which is the generation check working, but
--- it would be measuring the harness rather than the rotation.
---@return table h { actions, commit, restore }
local function install_kernel(bb, player, target)
    local saved_surface = _G.Sentinel

    local actions = {}
    local function record(spell_id, _aim, _priority, message)
        actions[#actions + 1] = { spell_id = spell_id, action = message }
        return true
    end

    local spell_queue = {}
    function spell_queue:queue_spell_target(id, unit, priority, message)
        return record(id, unit, priority, message)
    end
    function spell_queue:queue_spell_target_fast(id, unit, priority, message)
        return record(id, unit, priority, message)
    end
    function spell_queue:queue_spell_position(id, pos, priority, message)
        return record(id, pos, priority, message)
    end
    function spell_queue:queue_spell_position_fast(id, pos, priority, message)
        return record(id, pos, priority, message)
    end

    local units_by_guid = { [player:get_guid()] = player, [target:get_guid()] = target }

    local queue = IntentQueue:new()
    local broker = ControlBroker:new({ intent_queue = queue })
    queue:set_generation_validator(function(intent)
        return broker:is_generation_valid(intent)
    end)
    Executors.install({
        intent_queue = queue,
        spell_queue = spell_queue,
        object_manager = {
            get_local_player = function() return player end,
            get_object_from_guid = function(guid) return units_by_guid[guid] end,
        },
        unit_target = function() return bb:get("combat.target") or bb:get("player.target") end,
        -- The castable gate fails CLOSED without this, so an absent double would refuse every cast
        -- and every assertion below would read "the tree chose nothing" for a reason that has
        -- nothing to do with the tree.
        spell_helper = { is_spell_castable = function() return true end },
    })

    local frozen = Snapshot.empty(1)
    _G.Sentinel = Api.build({
        blackboard = bb, broker = broker, intent_queue = queue,
        scheduler = { current_snapshot = function() return frozen end },
        units = Units:new(),
    })

    return {
        actions = actions,
        commit = function() return queue:commit(frozen) end,
        restore = function() _G.Sentinel = saved_surface end,
    }
end

--- The blackboard both scenarios below start from. Identical in every field to the pre-port
--- fixture, minus `module.combat.dispatcher` -- the paladin package no longer contains a single
--- reference to a dispatcher, so seeding one would be describing a collaborator that is not there.
local function make_bb(player, target)
    local bb = Blackboard:new()
    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("player.is_auto_attacking", true)
    bb:set("player.attack_speed_s", 3.0)
    bb:set("combat.target", target)
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("combat.ally_count_30yd", 2)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("rotation.active_seal", "blood")
    bb:set("rotation.desired_seal", "blood")
    bb:set("combat.swing.remaining_ms", 999)
    bb:set("module.combat.twist_window_ms", 350)
    bb:set("module.combat.catalog", require("kernel/catalogs/spell"):new())
    bb:set("module.combat.cooldowns", {
        spell_ready = function() return true end,
        is_gcd_ready = function() return true end,
    })
    return bb
end

-- `M.run()` USED TO LIVE HERE, AND IT WAS THE REASON NEITHER TEST IN THIS FILE EVER RAN.
--
-- It was not a driver: it cleared two `package.loaded` entries and returned. The old harness asked
-- for `run` first and fell through to `test*` only if there was none -- so it executed the reset,
-- executed NEITHER test, and reported the suite as one pass. `test_dsl_path` had been failing the
-- whole time, on an assertion that could never have held (see the clock note in its body).
--
-- Deleted rather than kept, because both tests already perform the same reset as their first two
-- statements. A `run()` the runner now skips as a driver would be dead code that looks live.

function M.test_legacy_path()
    spell_helper = {
        is_spell_castable = function(_self, _spell_id, _source, _target, _ignore_facing, _ignore_range)
            return true
        end,
        get_spell_cooldown = function(_self, _spell_id)
            return 0
        end,
        is_spell_in_line_of_sight = function()
            return true
        end,
    }

    local player = make_unit({ guid = "player", position = { x = 0, y = 0, z = 0 }, buffs = { [31892] = true } })
    local target = make_unit({ guid = "target", position = { x = 3, y = 0, z = 0 }, health_pct = 0.50 })
    local bb = make_bb(player, target)
    local bus = EventBus:new()

    local h = install_kernel(bb, player, target)
    local actions = h.actions
    local ok, err = pcall(function()
        local profile = Profile.build(bb, bus)
        profile:tick_gcd(bb)
        h.commit()
        T.assert_equal(actions[1].action, "judgement")

        clear(actions)
        bb:set("system.now_ms", 1200)
        bb:set("rotation.after_judgement_reseal", true)
        bb:set("rotation.active_seal", nil)
        profile:tick_gcd(bb)
        h.commit()
        T.assert_equal(actions[1].action, "seal_of_blood")

        -- Test seal missing case in legacy path (the fix for combat not starting)
        clear(actions)
        bb:set("rotation.active_seal", nil)  -- No seal active
        bb:set("rotation.desired_seal", "blood")
        bb:set("system.now_ms", 1500)
        profile:tick_gcd(bb)
        h.commit()
        T.assert_equal(actions[1].action, "seal_of_blood", "Legacy path should queue seal when seal missing")
    end)
    h.restore()
    if not ok then error(err, 0) end
end

function M.test_dsl_path()
    package.loaded["rotations/paladin_retribution/retribution_tbc"] = nil
    package.loaded["kernel/lib/priority_builder"] = nil

    spell_helper = {
        is_spell_castable = function(_self, _spell_id, _source, _target, _ignore_facing, _ignore_range)
            return true
        end,
        get_spell_cooldown = function(_self, _spell_id)
            return 0
        end,
        is_spell_in_line_of_sight = function()
            return true
        end,
    }

    local player = make_unit({ guid = "player", position = { x = 0, y = 0, z = 0 }, buffs = { [31892] = true } })
    local target = make_unit({ guid = "target", position = { x = 3, y = 0, z = 0 }, health_pct = 0.50 })
    local bb = make_bb(player, target)
    local bus = EventBus:new()
    bb:set("module.combat.rotation_engine", "dsl")

    local h = install_kernel(bb, player, target)
    local actions = h.actions
    local ok, err = pcall(function()
        local profile = Profile.build(bb, bus)
        profile:tick_gcd(bb)
        h.commit()
        T.assert_equal(actions[1].action, "judgement", "DSL path should queue judgement")

        clear(actions)
        bb:set("system.now_ms", 1200)
        bb:set("rotation.after_judgement_reseal", true)
        bb:set("rotation.active_seal", nil)
        profile:tick_gcd(bb)
        h.commit()
        T.assert_equal(actions[1].action, "seal_of_blood", "DSL path should queue seal_of_blood after judgement")

        -- ========================================================================
        -- THE CLOCK HAS TO MOVE BETWEEN SIMULATED TICKS
        -- ========================================================================
        -- `build_gcd_root` wraps the WHOLE tree in
        -- `BT.cooldown("ret_gcd_cooldown", 75, ..., { key = "combat_ret_gcd" })`, and the Cooldown
        -- decorator stores its last-fired timestamp ON THE BLACKBOARD, under
        -- `module.bt.cooldown.combat_ret_gcd` -- not on the node. Three consequences, all of which
        -- this test fell foul of and none of which were visible while the harness never executed it:
        --
        --   * `now_ms - last_ms < 75` returns FAILURE before ANY condition in the tree is evaluated.
        --   * `profile:reset()` does not clear it, because it does not live on the profile.
        --   * A freshly built profile inherits it, because it lives on the blackboard they share --
        --     which is why `profile3` below changes nothing on its own.
        --
        -- So two `tick_gcd` calls at one `system.now_ms` are not two ticks: the second is refused by
        -- the gate, and any assertion about why it did nothing is answered by the gate rather than by
        -- the thing the assertion names.
        --
        -- BOTH BLOCKS BELOW WERE WRONG, in opposite directions. The invalid-target block asserted "no
        -- action" at the same 1200 ms as the seal cast above and PASSED WITHOUT EVER LOOKING AT THE
        -- TARGET. The seal-missing block asserted a cast at that same instant and could never have got
        -- one. Each simulated tick now advances the clock past the 75 ms window, which is what a real
        -- client does between frames.
        -- BOTH KEYS. `H.player_and_target` is
        -- `blackboard:get("combat.target") or blackboard:get("player.target")` -- the fallback pair the
        -- handle ledger records as shared by 14 of those two keys' 16 readers. Clearing `combat.target`
        -- alone leaves `player.target` answering, so the rotation still had a perfectly valid target and
        -- was right to act on it. This assertion only ever looked correct because the cooldown gate above
        -- was swallowing the tick before any condition ran.
        clear(actions)
        bb:set("system.now_ms", 1300)
        bb:set("combat.target", nil)
        bb:set("player.target", nil)
        profile:tick_gcd(bb)
        h.commit()
        T.assert_nil(actions[1], "DSL path should have no action when target invalid")

        -- Test seal missing case (the fix for combat not starting)
        package.loaded["rotations/paladin_retribution/retribution_tbc"] = nil
        package.loaded["kernel/lib/priority_builder"] = nil
        local profile3 = Profile.build(bb, bus)
        bb:set("system.now_ms", 1400)
        bb:set("combat.target", target)
        bb:set("rotation.active_seal", nil)  -- No seal active
        bb:set("rotation.desired_seal", "blood")
        clear(actions)
        profile3:tick_gcd(bb)
        h.commit()
        T.assert_equal(actions[1].action, "seal_of_blood", "Should queue seal when seal missing")
    end)
    h.restore()
    if not ok then error(err, 0) end
end

return M
