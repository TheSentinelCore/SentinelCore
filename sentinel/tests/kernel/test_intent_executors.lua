-- tests/kernel/test_intent_executors.lua
-- Casting becomes real (ADR 08 §3.2, §6.3, justified by §2.6).
--
-- §2.6, on the call this layer wraps: "`core.input.cast_target_spell` performs ZERO validation --
-- no range, no facing, no ready check; it only sends a packet. That is exactly the gap the commit
-- stage exists to fill."
--
-- So the tests here are not "does a cast happen". They are "does a cast that SHOULD NOT happen get
-- refused, by name, at the gate". Three things must hold before a packet leaves:
--   1. a lease authorised it            (generation check, §6.1)
--   2. the GCD is not running           (kernel/timing.lua, §2.5)
--   3. the SDK agrees it is castable    (range + facing, §2.6)
--
-- §6.3's band -> spell_queue mapping is pinned here too, including the colon call convention that
-- every `common/` module uses.

local IntentQueue = require("kernel/intent_queue")
local Executors = require("kernel/intent_executors")
local Timing = require("kernel/timing")
local ControlBroker = require("kernel/control_broker")
local EventBus = require("core/event_bus")
local Bands = require("kernel/bands")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- Doubles
-- ---------------------------------------------------------------------------

--- A spell_queue double that records HOW it was called, not just that it was. The colon convention
--- is load-bearing (§2.6: "it also uses the colon call convention, as do all `common/` modules"), so
--- the double asserts on the receiver rather than discarding it.
local function spell_queue_double()
    local sq = { calls = {} }
    function sq:queue_spell_target(spell_id, target, priority, message)
        self.calls[#self.calls + 1] = {
            receiver_ok = (self == sq),
            spell_id = spell_id, target = target, priority = priority, message = message,
        }
        return true
    end
    return sq
end

local PLAYER = { id = "player" }
local TARGET = { id = "target" }

---@param opts table { castable?, timing?, gcd_spell? }
local function harness(opts)
    opts = opts or {}
    local queue = IntentQueue:new()
    local timing = opts.timing or Timing:new({ now_ms = function() return 0 end })
    local sq = spell_queue_double()
    local castable_calls = {}

    Executors.install({
        intent_queue = queue,
        timing = timing,
        spell_queue = sq,
        object_manager = {
            get_local_player = function() return PLAYER end,
        },
        unit_target = function() return TARGET end,
        spell_helper = {
            is_spell_castable = function(spell_id, caster, target, skip_facing, skip_range)
                castable_calls[#castable_calls + 1] = {
                    spell_id = spell_id, caster = caster, target = target,
                    skip_facing = skip_facing, skip_range = skip_range,
                }
                if opts.castable == nil then return true end
                return opts.castable
            end,
        },
        input = { set_target = function(unit) sq.last_set_target = unit return true end },
    })

    return { queue = queue, timing = timing, sq = sq, castable_calls = castable_calls }
end

local function cast_intent(overrides)
    local intent = {
        type = "cast", owner = "rotations.mage_frost", band = Bands.BANDS.COMBAT.min,
        payload = { spell_id = 116, unit = "target" },
    }
    for k, v in pairs(overrides or {}) do intent[k] = v end
    return intent
end

local function first_rejection(report)
    local r = report.rejected[1]
    if not r then return nil end
    return r.gate, r.reason
end

-- ---------------------------------------------------------------------------
-- The band -> spell_queue mapping (§6.3)
-- ---------------------------------------------------------------------------

function M.test_a_combat_band_cast_queues_at_spell_queue_priority_1()
    local h = harness()
    h.queue:submit(cast_intent())
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 1, "a well-formed cast must commit")
    T.assert_equal(#h.sq.calls, 1)
    T.assert_equal(h.sq.calls[1].priority, 1, "§6.3: bands <= 69 map to spell_queue priority 1")
    T.assert_equal(h.sq.calls[1].spell_id, 116)
    T.assert_true(h.sq.calls[1].target == TARGET)
end

function M.test_a_survival_band_cast_queues_at_spell_queue_priority_7()
    local h = harness()
    h.queue:submit(cast_intent({ band = Bands.BANDS.SURVIVAL.min }))
    h.queue:commit({})
    T.assert_equal(h.sq.calls[1].priority, 7,
        "§6.3: survival and safety map to 7, the documented interrupt slot")
end

function M.test_a_safety_band_cast_queues_at_spell_queue_priority_7()
    local h = harness()
    h.queue:submit(cast_intent({ band = Bands.BANDS.SAFETY.min }))
    h.queue:commit({})
    T.assert_equal(h.sq.calls[1].priority, 7)
end

--- §2.6: every `common/` module uses `mod:fn()`. Calling with a dot silently shifts every argument
--- by one, which would put the spell id where the receiver belongs.
function M.test_the_spell_queue_is_called_with_the_colon_convention()
    local h = harness()
    h.queue:submit(cast_intent())
    h.queue:commit({})
    T.assert_true(h.sq.calls[1].receiver_ok,
        "spell_queue must receive itself as the receiver, not the spell id")
end

--- Priority 9 is reserved for manual player input (§6.3, and the SDK's own docs). The kernel must
--- never emit it, whatever band arithmetic produces.
function M.test_the_kernel_never_emits_the_reserved_manual_priority()
    for _, band in ipairs({ 0, 25, 49, 50, 69, 70, 89, 90, 99 }) do
        T.assert_true(Bands.spell_queue_priority(band) ~= 9,
            "band " .. band .. " must not map to the reserved manual-input priority 9")
    end
end

-- ---------------------------------------------------------------------------
-- The GCD gate (§2.5)
-- ---------------------------------------------------------------------------

--- The failure mode the whole Timing service exists to prevent.
function M.test_a_second_cast_inside_the_gcd_is_rejected()
    local clock = { ms = 0 }
    local timing = Timing:new({ now_ms = function() return clock.ms end })
    local saved = _G.core
    _G.core = { spell_book = { get_global_cooldown = function() return 1.5 end } }

    local ok, err = pcall(function()
        local h = harness({ timing = timing })

        h.queue:submit(cast_intent())
        T.assert_equal(#h.queue:commit({}).committed, 1, "the first cast goes through")

        clock.ms = 500
        h.queue:submit(cast_intent({ payload = { spell_id = 133, unit = "target" } }))
        local report = h.queue:commit({})

        T.assert_equal(#report.committed, 0, "the second cast must NOT reach the spell queue")
        local gate, reason = first_rejection(report)
        T.assert_equal(gate, "gcd")
        T.assert_equal(reason, "gcd_running")
        T.assert_equal(#h.sq.calls, 1, "and exactly one packet was sent, not two")

        clock.ms = 1500
        h.queue:submit(cast_intent({ payload = { spell_id = 133, unit = "target" } }))
        T.assert_equal(#h.queue:commit({}).committed, 1, "once the window closes it commits")
    end)

    _G.core = saved
    if not ok then error(err, 0) end
end

--- Ice Block is off-GCD. Gating it behind a GCD it does not use makes the panic button unreachable
--- exactly when it is needed.
function M.test_an_off_gcd_cast_is_not_held_by_the_gcd_gate()
    local clock = { ms = 0 }
    local timing = Timing:new({ now_ms = function() return clock.ms end })
    local saved = _G.core
    _G.core = { spell_book = { get_global_cooldown = function() return 1.5 end } }

    local ok, err = pcall(function()
        local h = harness({ timing = timing })
        h.queue:submit(cast_intent())
        h.queue:commit({})

        clock.ms = 200
        h.queue:submit(cast_intent({
            band = Bands.BANDS.SURVIVAL.min,
            payload = { spell_id = 45438, unit = "player", off_gcd = true },
        }))
        local report = h.queue:commit({})
        T.assert_equal(#report.committed, 1, "an off-GCD cast must pass the GCD gate")
    end)

    _G.core = saved
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- The castable gate: range and facing (§2.6)
-- ---------------------------------------------------------------------------

--- The ADR's exact justification for two-phase commit. `cast_target_spell` would have sent this.
function M.test_an_out_of_range_cast_is_rejected_at_the_gate()
    local h = harness({ castable = false })
    h.queue:submit(cast_intent())
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 0)
    T.assert_equal(#h.sq.calls, 0, "no packet may leave for an uncastable spell")
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "not_castable")
end

--- The gate must actually ASK about facing and range rather than skipping both checks, which would
--- make it a gate in name only.
function M.test_the_gate_asks_the_sdk_about_both_facing_and_range()
    local h = harness()
    h.queue:submit(cast_intent())
    h.queue:commit({})

    T.assert_equal(#h.castable_calls, 1)
    local call = h.castable_calls[1]
    T.assert_equal(call.spell_id, 116)
    T.assert_true(call.caster == PLAYER)
    T.assert_true(call.target == TARGET)
    T.assert_false(call.skip_facing, "skipping the facing check defeats the gate")
    T.assert_false(call.skip_range, "skipping the range check defeats the gate")
end

--- A self-cast has no meaningful facing or range. Forcing those checks would reject buffs.
function M.test_a_self_cast_skips_facing_and_range()
    local h = harness()
    h.queue:submit(cast_intent({ payload = { spell_id = 168, unit = "player" } }))
    h.queue:commit({})

    local call = h.castable_calls[1]
    T.assert_true(call.caster == PLAYER)
    T.assert_true(call.target == PLAYER)
    T.assert_true(call.skip_facing)
    T.assert_true(call.skip_range)
end

--- `shared/spell_helper.lua` returns the STRING `SpellHelper.UNKNOWN` when the spell-book helper is
--- unresolved -- deliberately, so callers can tell "no" from "cannot say". A truthy string is not
--- permission: anything other than a literal `true` must fail closed, or an unresolved helper
--- becomes a licence to cast at anything from anywhere.
function M.test_an_unknown_castability_verdict_is_refused_rather_than_trusted()
    local h = harness({ castable = "UNKNOWN" })
    h.queue:submit(cast_intent())
    local report = h.queue:commit({})

    T.assert_equal(#report.committed, 0, "an UNKNOWN verdict must not commit")
    T.assert_equal(#h.sq.calls, 0)
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "not_castable")
end

--- A target reference that resolves to nothing must be refused, not passed as nil into an SDK call
--- that "only sends a packet".
function M.test_a_cast_at_a_vanished_target_is_refused()
    local queue = IntentQueue:new()
    Executors.install({
        intent_queue = queue,
        timing = Timing:new({ now_ms = function() return 0 end }),
        spell_queue = spell_queue_double(),
        object_manager = { get_local_player = function() return PLAYER end },
        unit_target = function() return nil end,
        spell_helper = { is_spell_castable = function() return true end },
        input = {},
    })

    queue:submit(cast_intent())
    local report = queue:commit({})
    T.assert_equal(#report.committed, 0)
    local gate, reason = first_rejection(report)
    T.assert_equal(gate, "castable")
    T.assert_equal(reason, "unit_unresolved")
end

-- ---------------------------------------------------------------------------
-- Only a lease may cast (§6.1)
-- ---------------------------------------------------------------------------

--- Phase 2 established this; Phase 4 makes casting real, so it is re-pinned against the executor
--- that now actually sends packets.
function M.test_a_cast_without_a_lease_never_reaches_the_spell_queue()
    local bus = EventBus:new(function() end)
    local queue = IntentQueue:new()
    local broker = ControlBroker:new({ event_bus = bus, intent_queue = queue })
    queue:set_generation_validator(function(intent)
        return broker:is_generation_valid(intent)
    end)

    local sq = spell_queue_double()
    Executors.install({
        intent_queue = queue,
        timing = Timing:new({ now_ms = function() return 0 end }),
        spell_queue = sq,
        object_manager = { get_local_player = function() return PLAYER end },
        unit_target = function() return TARGET end,
        spell_helper = { is_spell_castable = function() return true end },
        input = {},
    })

    -- Submitted directly, bypassing any caretaker: no generation stamp.
    queue:submit(cast_intent())
    local report = queue:commit({})

    T.assert_equal(#report.committed, 0)
    T.assert_equal(#sq.calls, 0, "an unleased cast must not send a packet")
    local gate = first_rejection(report)
    T.assert_equal(gate, "generation")
end

-- ---------------------------------------------------------------------------
-- Targeting
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- The `core.input` blast radius
-- ---------------------------------------------------------------------------

--- Phase 2 established that the kernel had exactly ONE `core.input.*` resolution site
--- (kernel/movement_release.lua). Making casting real is the obvious moment for that to sprawl, so
--- the count is pinned mechanically rather than re-audited by hand each phase.
---
--- It did not grow, and the reason is structural: casts go through `spell_queue`, not
--- `core.input.cast_target_spell`, and the executors take `input` as an INJECTED dependency
--- resolved at the composition root. A kernel file reaching for the live `core.input` table itself
--- is what this test forbids.
function M.test_the_kernel_resolves_core_input_in_exactly_one_place()
    local files = {}
    local find = io.popen('find sentinel/kernel -type f -name "*.lua" | sort')
    if find then
        for line in find:lines() do files[#files + 1] = line end
        find:close()
    end
    T.assert_true(#files > 0, "expected kernel sources to audit")

    -- Comment stripping happens HERE rather than in a shell pipeline, because most `core.input`
    -- mentions in the kernel are prose explaining why a file does NOT call it -- including trailing
    -- comments on lines of real code, which no line-oriented grep filter handles correctly.
    local sites = {}
    for _, path in ipairs(files) do
        local handle = io.open(path, "r")
        if handle then
            local line_number = 0
            for line in handle:lines() do
                line_number = line_number + 1
                local code = line:match("^(.-)%-%-") or line
                if code:find("core%.input") then
                    sites[#sites + 1] = path .. ":" .. line_number .. ":" .. line
                end
            end
            handle:close()
        end
    end

    T.assert_equal(#sites, 1,
        "the kernel must resolve `core.input` in exactly one place; found:\n  "
        .. table.concat(sites, "\n  "))
    T.assert_true(sites[1]:find("movement_release") ~= nil,
        "and that place must remain kernel/movement_release.lua, got: " .. tostring(sites[1]))
end

function M.test_a_target_intent_routes_through_input_set_target()
    local h = harness()
    h.queue:submit({
        type = "target", owner = "rotations.mage_frost", band = Bands.BANDS.COMBAT.min,
        payload = { unit = "target" },
    })
    local report = h.queue:commit({})
    T.assert_equal(#report.committed, 1)
    T.assert_true(h.sq.last_set_target == TARGET)
end

return M
