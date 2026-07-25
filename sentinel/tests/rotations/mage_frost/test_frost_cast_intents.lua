-- tests/rotations/mage_frost/test_frost_cast_intents.lua
-- The frost cast path, PINNED BEFORE it moves onto the `cast` intent (Phase 4c D4).
--
-- ================================================================================
-- THE MEASUREMENT THIS FILE IS BUILT ON
-- ================================================================================
-- The plan carried a "38 cast sites" estimate from the `.object`-era survey. Re-measured:
--
--   H.queue_target(...)   in frost_actions.lua   30
--   H.queue_position(...) in frost_actions.lua    6
--   direct d:queue_target(...) bypassing both     2   (finish_low_add, emergency_escape)
--                                             ----
--                                                38
--
-- The COUNT was right and the UNIT was wrong. 36 of the 38 route through two functions in
-- frost_support.lua, so the conversion surface is FOUR places, not thirty-eight. That distinction is
-- the whole reason this file is small: one pin per behaviour, not one per call site.
--
-- ================================================================================
-- THE PINS RUN IN BOTH ERAS
-- ================================================================================
-- Following tests/rotations/mage_frost/test_frost_item_intents.lua. Each pin asks what a player
-- could see -- what did the action return, and what cast left carrying which spell at which
-- destination -- and names neither the dispatcher nor the intent queue. The recorder is installed
-- TWICE: as the combat module's SpellDispatcher (what the old code reaches through the blackboard)
-- and as the `spell_queue` the kernel's executor calls. One log, two eras.
--
-- A pin written against the mechanism would have to be rewritten in order to convert, and a
-- rewritten pin measures nothing.
--
-- ================================================================================
-- WHAT THESE PINS CANNOT SEE
-- ================================================================================
--  1. WHEN the packet leaves. In the old era the SDK call happens inside the action; in the new one
--     it happens at COMMIT, a stage later. Every pin here commits the queue before asserting, so
--     the ORDERING difference between the two eras is deliberately invisible to it. The two-phase
--     timing is pinned in tests/kernel/test_scheduler.lua, not here.
--  2. The dispatcher's own bookkeeping -- `rotation.last_queue_*` diagnostics, its dedupe
--     signatures, its post-queue snapshot verification. Those are SpellDispatcher behaviour that the
--     intent path deliberately does not reproduce, and pinning them here would pin the old
--     mechanism under a name that claims to be about casting.
--  3. Whether the spell ids are the RIGHT ranks. The catalog is a double returning fixed ids; rank
--     resolution is pinned in tests/modules/combat/test_spell_catalog*.lua.
--  4. Anything about the 132 pre-existing frost assertions. They observe the dispatcher directly and
--     are the conversion's blast radius, not its specification.
--
-- ================================================================================
-- PHASE 4d -- THE OFF-GCD BYPASS, AND WHAT THESE NEW PINS CANNOT SEE EITHER
-- ================================================================================
-- The GCD-bypass pins below observe the KERNEL'S ESTIMATE of the global cooldown, through a
-- `timing` double handed to `Executors.install`. Three things follow, and each is a real limit:
--
--  5. THE GCD HERE IS A FIXTURE, NOT A GAME. `opts.gcd_running` sets what `is_gcd_ready()` answers.
--     Nothing offline can tell whether the real client would have accepted the packet -- the kernel's
--     estimate is exact only for casts it committed itself (kernel/timing.lua's own header), and
--     these pins inherit that blindness whole.
--  6. THEY CANNOT SEE A WRONG CATALOG. `is_ogcd_spell` is asked of a double that answers exactly what
--     `kernel/catalogs/spell.lua` answers TODAY, wrong entries included -- see
--     `test_ice_barrier_is_not_granted_a_bypass_the_client_would_not_honour`, which exists precisely
--     because one of those entries is wrong and the DB proves it. If the kernel catalog and this
--     double drift apart, these pins keep passing while production changes behaviour. Nothing here
--     compares the two; only reading both does.
--  7. THEY CANNOT SEE WHETHER A SPELL IS ACTUALLY OFF THE GCD IN TBC. That fact lives in the game's
--     own data (`spell_template.StartRecoveryCategory`), not in any Lua this suite can run. The
--     measured query is recorded next to each pin so the next reader can re-run it rather than
--     re-guess it.
--
-- The mana-gem pins share limits 1-3 above with the potion suite, and add nothing about bag state:
-- `has_item` is a fixture answer, so "the character carries a gem" is asserted about the double.

local Api = require("kernel/api")
local IntentQueue = require("kernel/intent_queue")
local Executors = require("kernel/intent_executors")
local ControlBroker = require("kernel/control_broker")
local Blackboard = require("core/blackboard")
-- Phase 4d D5: a cast names its unit by a guid ref minted through `Sentinel.units` and stamped
-- with the tick index of the frozen snapshot. Both halves are harness wiring now: no `units`
-- component means no mint, and no snapshot means no tick to stamp with.
local Snapshot = require("kernel/snapshot")
local Units = require("kernel/units")
local Status = require("core/bt/status")
local Act = require("rotations/mage_frost/frost_actions")
local H = require("rotations/mage_frost/frost_support")
local T = require("tests/test_util")

local M = {}

-- Real TBC ids, so a reader can tell which spell a pin is about at a glance.
local FROSTBOLT = 27072
local FIRE_BLAST = 27079
local BLIZZARD = 27085
local ICE_BARRIER = 27134
local COUNTERSPELL = 2139
local POLYMORPH = 12826

local FROST_NOVA = 27088
local ICY_VEINS = 12472
local COLD_SNAP = 11958

--- A TBC mana gem. `frost_combat_state.lua:21` picks it off the bag, best-first.
local MANA_EMERALD = 22044

local SPELL_IDS = {
    frostbolt = FROSTBOLT,
    fire_blast = FIRE_BLAST,
    blizzard = BLIZZARD,
    ice_barrier = ICE_BARRIER,
    counterspell = COUNTERSPELL,
    polymorph = POLYMORPH,
    frost_nova = FROST_NOVA,
    icy_veins = ICY_VEINS,
    cold_snap = COLD_SNAP,
}

--- WHAT THE KERNEL'S SPELL CATALOG SAYS TODAY -- copied, not invented.
---
--- `kernel/catalogs/spell.lua` marks exactly three frost entries `ogcd = true`: `ice_barrier`
--- (:36), `cold_snap` (:43) and `icy_veins` (:44). This double reproduces that answer EXACTLY,
--- including the entry that disagrees with the game, so a pin that depends on the catalog being
--- wrong keeps working for the reason it was written rather than by accident.
local OGCD_PER_KERNEL_CATALOG = {
    ice_barrier = true,
    icy_veins = true,
    cold_snap = true,
}

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

local function make_unit(id, guid, position)
    local unit = { id = id }
    function unit:get_guid() return guid end
    function unit:get_position() return position or { x = 0, y = 0, z = 0 } end
    function unit:is_valid() return true end
    return unit
end

---Run `body(h)` against a live kernel with `_G.Sentinel` published over it.
---
---`h.casts` is the ONE log both eras write to. Each entry is
---`{ spell_id, unit, point, priority, fast }` -- the shape a player could describe.
---@param opts table|nil { castable?, no_catalog?, casting_held_by?, gcd_running?,
---                        no_kernel_catalog?, has_item? }
local function with_harness(opts, body)
    opts = opts or {}
    local saved_surface = _G.Sentinel

    local casts = {}
    local function record(spell_id, aim, priority, fast)
        local entry = { spell_id = spell_id, priority = priority, fast = fast or false }
        if type(aim) == "table" and type(aim.x) == "number" then
            entry.point = aim
        else
            entry.unit = aim
        end
        casts[#casts + 1] = entry
        return true
    end

    -- NEW ERA: the SDK verbs the kernel's cast executor calls.
    local spell_queue = {}
    function spell_queue:queue_spell_target(id, unit, priority) return record(id, unit, priority, false) end
    function spell_queue:queue_spell_position(id, pos, priority) return record(id, pos, priority, false) end
    function spell_queue:queue_spell_target_fast(id, unit, priority) return record(id, unit, priority, true) end
    function spell_queue:queue_spell_position_fast(id, pos, priority) return record(id, pos, priority, true) end

    -- ITEMS. The mana gem is an item, so the same log discipline applies one channel over: one
    -- recorder, and the assertion asks what left rather than which SDK verb carried it.
    local item_packets = {}
    local input = {
        use_item = function(item_id)
            item_packets[#item_packets + 1] = { item_id = item_id }
            return true
        end,
    }

    local player = make_unit("player", "guid-player", { x = 0, y = 0, z = 0 })
    local target = make_unit("target", "guid-target", { x = 10, y = 0, z = 0 })
    local add = make_unit("add", "guid-add", { x = 5, y = 5, z = 0 })

    -- The two questions the ITEMS gate asks the player, and nothing else asks. Both are FIXTURE
    -- answers: "the character carries a gem" is a statement about this table, not about a bag.
    function player:has_item(_item_id)
        if opts.has_item == nil then return true end
        return opts.has_item
    end
    function player:get_item_cooldown(_item_id) return opts.item_cooldown or 0 end

    local units_by_guid = {
        ["guid-player"] = player, ["guid-target"] = target, ["guid-add"] = add,
    }

    local bb = Blackboard:new()
    bb:set("player.object", player)
    bb:set("combat.target", target)

    -- OLD ERA: the combat module's SpellDispatcher, reached through the blackboard. Same log.
    --
    -- FAITHFUL, not merely recording. The real dispatcher resolves the key through
    -- `module.combat.catalog` (`spell_dispatcher.lua:94`) and refuses a nil target
    -- (`:166 missing_target_or_spell`). A double that accepted both would make the "no catalog" and
    -- "no target" pins pass in the old era for a reason the production code does not have -- and
    -- those are precisely the two refusals the conversion must preserve.
    local function resolve(spell_key)
        local catalog = bb:get("module.combat.catalog")
        if not catalog then return nil end
        return catalog:resolve_best_rank(spell_key)
    end
    if not opts.no_dispatcher then
        bb:set("module.combat.dispatcher", {
            queue_spell = function(_self, spell_key, unit, priority, _msg, o)
                local id = resolve(spell_key)
                if not id or not unit then return false end
                return record(id, unit, priority, o and o.fast or false)
            end,
            queue_position_spell = function(_self, spell_key, point, priority)
                local id = resolve(spell_key)
                if not id or type(point) ~= "table" then return false end
                return record(id, point, priority, false)
            end,
            queue_target = function(_self, _action_id, spell_id, unit, priority)
                if not spell_id or not unit then return false end
                return record(spell_id, unit, priority, false)
            end,
            queue_position = function(_self, _action_id, spell_id, point, priority)
                if not spell_id or type(point) ~= "table" then return false end
                return record(spell_id, point, priority, false)
            end,
        })
    end

    if not opts.no_catalog then
        bb:set("module.combat.catalog", {
            resolve_best_rank = function(_self, key) return SPELL_IDS[key] end,
            resolve_lowest_rank = function(_self, key) return SPELL_IDS[key] end,
        })
    end

    -- THE GCD, INSTALLED ONLY WHEN A PIN ASKS ABOUT IT.
    --
    -- `intent_executors.lua:219` treats an ABSENT `timing` as "the gate cannot ask, so it permits",
    -- which is the condition every pre-Phase-4d pin in this file ran under. Installing a timing
    -- double unconditionally would therefore change what those pins measure, so it is opt-in: the
    -- default harness is still the one they were written against.
    --
    -- `gcd_notes` records what the executor charged against the GCD estimate. That is the SECOND
    -- observable consequence of the off-GCD flag (`intent_executors.lua:438` skips `note_cast` for
    -- it), and pinning only the first would let a half-plumbed flag pass.
    local gcd_notes = {}
    local timing = nil
    if opts.gcd_running ~= nil then
        timing = {
            is_gcd_ready = function(_self) return not opts.gcd_running end,
            note_cast = function(_self, spell_id) gcd_notes[#gcd_notes + 1] = spell_id end,
        }
    end

    local queue = IntentQueue:new()
    local broker = ControlBroker:new({ intent_queue = queue })
    queue:set_generation_validator(function(intent)
        return broker:is_generation_valid(intent)
    end)
    Executors.install({
        intent_queue = queue,
        spell_queue = spell_queue,
        timing = timing,
        object_manager = {
            get_local_player = function() return player end,
            get_object_from_guid = function(guid) return units_by_guid[guid] end,
        },
        unit_target = function() return bb:get("combat.target") or bb:get("player.target") end,
        spell_helper = {
            is_spell_castable = function()
                if opts.castable == nil then return true end
                return opts.castable
            end,
        },
        input = input,
    })

    -- A rival on CASTING, so a refused acquisition is OBSERVED rather than assumed. SAFETY outranks
    -- the rotation's COMBAT, so it cannot be preempted.
    if opts.casting_held_by then
        broker:acquire({
            channel = "CASTING", owner = opts.casting_held_by, band = "SAFETY", ttl_ticks = 5,
        })
    end

    -- THE KERNEL'S SPELL CATALOG, which is a DIFFERENT object from the blackboard one above.
    --
    -- The blackboard catalog answers "which rank"; this one answers "is this ability off the global
    -- cooldown". `Support` deliberately asks two different authorities two different questions, and
    -- a single double would hide that -- so would silently survive the day one of the two goes away.
    local kernel_spell_catalog = nil
    if not opts.no_kernel_catalog then
        kernel_spell_catalog = {
            resolve_best_rank = function(_self, key) return SPELL_IDS[key] end,
            is_gcd_spell = function(_self, key) return not OGCD_PER_KERNEL_CATALOG[key] end,
            is_ogcd_spell = function(_self, key) return OGCD_PER_KERNEL_CATALOG[key] == true end,
        }
    end

    -- ONE snapshot for the whole scenario, so the tick a ref is MINTED under is the tick COMMIT
    -- runs under. Two would make every cast stale -- which is the check working, but it would be
    -- measuring the harness rather than the rotation.
    local frozen = Snapshot.empty(1)
    _G.Sentinel = Api.build({
        blackboard = bb, broker = broker, intent_queue = queue,
        spell_catalog = kernel_spell_catalog,
        scheduler = { current_snapshot = function() return frozen end },
        units = Units:new(),
    })

    local h = {
        bb = bb, casts = casts, queue = queue, broker = broker,
        player = player, target = target, add = add,
        item_packets = item_packets, gcd_notes = gcd_notes,
        --- Drain the queue. A no-op in the old era, where the packet already left.
        -- Committed against the SAME snapshot the mint read, for the reason above.
        commit = function() return queue:commit(frozen) end,
    }

    local ok, err = pcall(body, h)
    _G.Sentinel = saved_surface
    if not ok then error(err, 0) end
end

--- Every pin ends the same way: run the action, drain whatever it queued, then look at the log.
local function fire(h, action, ...)
    local status = action(h.bb, ...)
    h.commit()
    return status
end

--- As `fire`, but hands the commit report back so a refusal can be pinned BY NAME. A pin that only
--- checked "nothing left" would pass equally if the intent were never formed, which is a different
--- bug wearing the same silence.
local function fire_reporting(h, action, ...)
    local status = action(h.bb, ...)
    return status, h.commit()
end

-- ---------------------------------------------------------------------------
-- Unit-targeted casts -- 30 of the 38 sites
-- ---------------------------------------------------------------------------

function M.test_frostbolt_casts_at_the_rotations_target()
    with_harness(nil, function(h)
        local status = fire(h, Act.queue_frostbolt)
        T.assert_equal(status, Status.SUCCESS)
        T.assert_equal(#h.casts, 1, "exactly one cast must leave")
        T.assert_equal(h.casts[1].spell_id, FROSTBOLT)
        T.assert_true(h.casts[1].unit == h.target, "at the unit the rotation selected")
    end)
end

--- The rotation's target, NOT the client's. `combat.target` is the combat module's own selection and
--- the two diverge exactly when the module has chosen but the client has not caught up.
function M.test_a_cast_follows_combat_target_rather_than_the_clients()
    with_harness(nil, function(h)
        local other = make_unit("client-target", "guid-other")
        h.bb:set("player.target", other)
        fire(h, Act.queue_frostbolt)
        T.assert_true(h.casts[1].unit == h.target,
            "combat.target must win over player.target, as player_and_target already does")
    end)
end

function M.test_a_self_cast_targets_the_player()
    with_harness(nil, function(h)
        local status = fire(h, Act.queue_frost_nova)
        T.assert_equal(status, Status.SUCCESS)
        T.assert_true(h.casts[1].unit == h.player, "Frost Nova is centred on the caster")
    end)
end

--- Counterspell is the rotation's only INTERRUPT-priority entry. §6.3 maps that onto spell_queue
--- priority 7, the documented interrupt slot; everything else maps onto 1.
function M.test_counterspell_queues_at_the_interrupt_priority()
    with_harness(nil, function(h)
        fire(h, Act.queue_counterspell)
        T.assert_equal(h.casts[1].spell_id, COUNTERSPELL)
        T.assert_equal(h.casts[1].priority, H.QueuePriorities.INTERRUPT,
            "the interrupt slot must survive the conversion")
    end)
end

function M.test_an_ordinary_cast_queues_at_the_default_priority()
    with_harness(nil, function(h)
        fire(h, Act.queue_frostbolt)
        T.assert_equal(h.casts[1].priority, H.QueuePriorities.DEFAULT)
    end)
end

--- Ice Barrier, Icy Veins and Cold Snap pass `{ fast = true }`. That flag is the reason the fast
--- SDK verb exists; losing it in the conversion would be a silent behaviour change.
function M.test_a_fast_flagged_buff_keeps_its_fast_path()
    with_harness(nil, function(h)
        fire(h, Act.queue_ice_barrier)
        T.assert_equal(h.casts[1].spell_id, ICE_BARRIER)
        T.assert_true(h.casts[1].fast, "the fast flag must reach the SDK, not be dropped")
    end)
end

-- ---------------------------------------------------------------------------
-- Ground-targeted casts -- 6 of the 38 sites
-- ---------------------------------------------------------------------------

function M.test_blizzard_casts_at_a_point_not_a_unit()
    with_harness(nil, function(h)
        local status = fire(h, Act.queue_blizzard)
        T.assert_equal(status, Status.SUCCESS)
        T.assert_equal(h.casts[1].spell_id, BLIZZARD)
        T.assert_not_nil(h.casts[1].point, "a ground-targeted spell must carry a point")
        T.assert_nil(h.casts[1].unit, "and must not be sent at a unit")
    end)
end

-- ---------------------------------------------------------------------------
-- Units the symbolic vocabulary cannot name -- the 2 direct sites, and Polymorph
-- ---------------------------------------------------------------------------

--- `combat.low_health_add` is neither player, target nor pet. Before Phase 4c the intent had no way
--- to name it, which is why this site bypassed the helper and called the dispatcher directly.
function M.test_finishing_a_low_health_add_casts_at_that_add()
    with_harness(nil, function(h)
        h.bb:set("combat.low_health_add", h.add)
        local status = fire(h, Act.finish_low_add)
        T.assert_equal(status, Status.SUCCESS)
        T.assert_equal(h.casts[1].spell_id, FIRE_BLAST)
        T.assert_true(h.casts[1].unit == h.add,
            "the add, not the current target -- that is the entire point of the action")
    end)
end

function M.test_finishing_an_add_that_is_absent_fails_without_casting()
    with_harness(nil, function(h)
        local status = fire(h, Act.finish_low_add)
        T.assert_equal(status, Status.FAILURE)
        T.assert_equal(#h.casts, 0)
    end)
end

-- ---------------------------------------------------------------------------
-- Refusals
-- ---------------------------------------------------------------------------

--- No catalog means no spell id. ADR §6.3 forbids fallback logic on the cast path, so this must FAIL
--- rather than quietly reach for a different source of ranks.
function M.test_a_missing_catalog_fails_the_action_without_casting()
    with_harness({ no_catalog = true }, function(h)
        local status = fire(h, Act.queue_frostbolt)
        T.assert_equal(status, Status.FAILURE)
        T.assert_equal(#h.casts, 0)
    end)
end

function M.test_a_cast_with_no_target_fails_without_casting()
    with_harness(nil, function(h)
        h.bb:set("combat.target", nil)
        h.bb:set("player.target", nil)
        local status = fire(h, Act.queue_frostbolt)
        T.assert_equal(status, Status.FAILURE)
        T.assert_equal(#h.casts, 0)
    end)
end

-- ---------------------------------------------------------------------------
-- Phase 4d -- the panic buttons, and the GCD they do not use
-- ---------------------------------------------------------------------------
--
-- ============================================================================
-- THE BUG THESE FIVE PINS WERE WRITTEN AGAINST
-- ============================================================================
-- `intent_executors.lua:217` honours `payload.off_gcd`, and NOTHING in `sentinel/` ever set it. The
-- three off-GCD tree actions passed `{ fast = true }` and nothing more, so every one of them was
-- refused with `gcd_running` whenever the GCD was turning -- which is the only moment they are
-- reached for. The gate's own comment names the failure: "gating the panic button behind a GCD it
-- does not use makes it unreachable exactly when it is needed."
--
-- ============================================================================
-- THE TREE IS NOT THE CLAIM
-- ============================================================================
-- "The off-GCD TREE" is a SCHEDULING statement: `frost_tbc.lua:353` ticks that subtree every cycle
-- rather than once per global cooldown. "This spell is off the GCD" is a GAME statement about
-- `spell_template.StartRecoveryCategory`. They are not the same claim, and treating them as one is
-- how a GCD-bound spell would be handed a bypass.
--
-- Measured against the game's own data (tbcmangos.sqlite, `spell_template`, TBC 2.4.3):
--
--     SpellName      StartRecoveryCategory  StartRecoveryTime   -> on the GCD?
--     Icy Veins                          0                  0      NO
--     Cold Snap                          0                  0      NO
--     Ice Barrier (all 6 ranks)        133               1500      YES
--     Ice Block                        133               1500      YES
--     Frostbolt                        133               1500      YES
--
-- So TWO of the three off-GCD-tree actions may bypass, and the third may not. `queue_ice_barrier`
-- keeps its `{ fast = true }` and gains nothing else.

--- THE POSITIVE. Icy Veins is off the GCD in TBC, and a running GCD must not hide it.
function M.test_an_off_gcd_ability_casts_while_the_gcd_is_still_turning()
    with_harness({ gcd_running = true }, function(h)
        local status, report = fire_reporting(h, Act.queue_icy_veins)
        T.assert_equal(status, Status.SUCCESS, "the action accepted the intent")
        T.assert_equal(#report.rejected, 0, "and no gate refused it")
        T.assert_equal(#h.casts, 1, "the panic button is reachable with the GCD turning")
        T.assert_equal(h.casts[1].spell_id, ICY_VEINS)
        T.assert_equal(#h.gcd_notes, 0,
            "and it does not arm a GCD window it never triggers")
    end)
end

function M.test_cold_snap_also_casts_while_the_gcd_is_still_turning()
    with_harness({ gcd_running = true }, function(h)
        T.assert_equal(fire(h, Act.queue_cold_snap), Status.SUCCESS)
        T.assert_equal(#h.casts, 1, "the second genuinely off-GCD frost ability")
        T.assert_equal(h.casts[1].spell_id, COLD_SNAP)
    end)
end

--- THE NEGATIVE TWIN, and the reason it exists: the fix must not be a blanket bypass. Under the
--- IDENTICAL conditions -- same harness, same turning GCD -- an ability that does use the global
--- cooldown must still be refused, and refused BY NAME.
function M.test_a_gcd_bound_ability_is_still_refused_while_the_gcd_is_turning()
    with_harness({ gcd_running = true }, function(h)
        local status, report = fire_reporting(h, Act.queue_frostbolt)
        T.assert_equal(status, Status.SUCCESS, "the action still forms the intent")
        T.assert_equal(#h.casts, 0, "but nothing may leave into a running GCD")
        T.assert_equal(#report.rejected, 1, "the refusal is recorded, not silent")
        T.assert_equal(report.rejected[1].gate, "gcd")
        T.assert_equal(report.rejected[1].reason, "gcd_running", "and recorded BY NAME")
    end)
end

--- THE ENTRY THE CATALOG GETS WRONG, PINNED AS SUCH.
---
--- `kernel/catalogs/spell.lua:36` marks `ice_barrier` `gcd = false, ogcd = true`. The game disagrees:
--- every one of the six ranks (11426, 13031, 13032, 13033, 27134, 33405) carries
--- `StartRecoveryCategory = 133, StartRecoveryTime = 1500` -- Ice Barrier triggers the global
--- cooldown in TBC, exactly like every other mage shield.
---
--- This is why the rotation must ALSO declare the bypass rather than inheriting it from the catalog
--- alone: a catalog-only rule would hand Ice Barrier a bypass the client will not honour, and the
--- resulting packet is refused by the server rather than by the kernel. The harness double answers
--- `is_ogcd_spell("ice_barrier") == true` on purpose, so this pin fails the moment the corroboration
--- requirement is dropped.
---
--- WHAT IT CANNOT SEE: whether `kernel/catalogs/spell.lua` is ever corrected. If that entry is fixed
--- this pin keeps passing, for a second reason, and stops measuring the AND. Correcting the catalog
--- is out of this unit's file scope and is reported as a finding.
function M.test_ice_barrier_is_not_granted_a_bypass_the_client_would_not_honour()
    with_harness({ gcd_running = true }, function(h)
        local status, report = fire_reporting(h, Act.queue_ice_barrier)
        T.assert_equal(status, Status.SUCCESS, "the action forms the intent as before")
        T.assert_equal(#h.casts, 0,
            "Ice Barrier is on the GCD in TBC -- the catalog says otherwise and is wrong")
        T.assert_equal(report.rejected[1].reason, "gcd_running",
            "so it waits for the window like every other shield")
    end)
end

--- THE OTHER HALF OF THE AND, at the helper rather than through an action.
---
--- No frost action declares `off_gcd` for a GCD-bound spell, so the only way to pin the direction
--- "the rotation asked and the catalog refused" is to ask the helper directly. Drift can then only
--- ever make the gate STRICTER: a bypass needs two independent yeses, and either authority being
--- wrong on its own closes the gate rather than opening it.
function M.test_a_declared_bypass_the_catalog_denies_is_not_honoured()
    with_harness({ gcd_running = true }, function(h)
        local status = H.queue_target(h.bb, "frostbolt", "frostbolt", h.target,
            H.QueuePriorities.DEFAULT, { off_gcd = true })
        T.assert_equal(status, Status.SUCCESS, "the intent is formed")
        h.commit()
        T.assert_equal(#h.casts, 0,
            "a rotation cannot talk its way past the GCD without the catalog agreeing")
    end)
end

--- FAIL CLOSED WITH NO CATALOG AT ALL. An absent authority is not permission -- the same trade
--- `no_castable_check` and `no_item_check` make one layer down.
function M.test_without_a_kernel_catalog_no_ability_bypasses_the_gcd()
    with_harness({ gcd_running = true, no_kernel_catalog = true }, function(h)
        T.assert_equal(fire(h, Act.queue_icy_veins), Status.SUCCESS)
        T.assert_equal(#h.casts, 0,
            "nobody can confirm the ability is off the GCD, so it is treated as on it")
    end)
end

-- ---------------------------------------------------------------------------
-- Phase 4d -- the mana gem, which was calling an undefined global
-- ---------------------------------------------------------------------------
--
-- `Act.use_mana_gem` called `SpellQueue.call("queue_item_self", ...)` twice. There is no
-- `local SpellQueue = require(...)` anywhere in `frost_actions.lua` -- `spell_dispatcher.lua:2` has
-- one, that file never did -- so the action threw
-- `attempt to index a nil value (global 'SpellQueue')` the moment it got past its nil-id guard.
--
-- IT WAS UNTESTED AND IT AUDITED CLEAN. `test_plugin_core_access_audit.lua`'s CORE_ACCESS_LEDGER
-- matches `core.*`; an undefined global that is not spelled `core` is invisible to it. That is the
-- audit's blind spot, not a gap in this action's luck.
--
-- These pins live in the CAST-intent suite rather than the item suite only because
-- `test_frost_item_intents.lua` is outside this unit's file scope. They belong beside the potions.

--- The pin that was red: with a gem in the bag the action threw instead of doing anything.
function M.test_using_a_mana_gem_emits_an_item_intent()
    with_harness(nil, function(h)
        h.bb:set("combat.mana_gem_item_id", MANA_EMERALD)
        local status = Act.use_mana_gem(h.bb)
        T.assert_equal(status, Status.SUCCESS, "the intent was accepted for this tick")
        h.commit()
        T.assert_equal(#h.item_packets, 1, "exactly one item packet leaves")
        T.assert_equal(h.item_packets[1].item_id, MANA_EMERALD, "carrying the gem it was given")
        T.assert_equal(#h.casts, 0, "a gem is an item, not a spell -- nothing casts")
    end)
end

--- INVARIANT 1, matching the potions: a game-affecting call is authorised, never ambient.
function M.test_a_mana_gem_is_authorised_by_an_items_lease()
    with_harness(nil, function(h)
        h.bb:set("combat.mana_gem_item_id", MANA_EMERALD)
        T.assert_nil(h.broker:who_owns("ITEMS"), "nothing holds ITEMS before the action runs")
        Act.use_mana_gem(h.bb)
        T.assert_equal(h.broker:who_owns("ITEMS"), "sentinel.rotation.mage_frost",
            "the rotation must hold the channel it acted on")
        local report = h.commit()
        T.assert_equal(#report.committed, 1,
            "and the lease must outlive the action, or the generation check kills the intent")
    end)
end

--- STABLE ACROSS THE FIX. The nil-id guard runs before the broken line ever did, so this pin was
--- green before the conversion and is green after -- which is exactly what makes it worth keeping:
--- it says the fix did not move the refusal.
function M.test_a_mana_gem_with_no_id_sends_nothing()
    with_harness(nil, function(h)
        T.assert_equal(Act.use_mana_gem(h.bb), Status.FAILURE, "no id on the blackboard, no gem")
        h.commit()
        T.assert_equal(#h.item_packets, 0, "nothing may leave without an item id")
    end)
end

--- NEW BEHAVIOUR, and worth naming: the old line asked the bag nothing. The ITEMS gate does.
function M.test_a_mana_gem_the_character_does_not_carry_is_refused()
    with_harness({ has_item = false }, function(h)
        h.bb:set("combat.mana_gem_item_id", MANA_EMERALD)
        Act.use_mana_gem(h.bb)
        local report = h.commit()
        T.assert_equal(#h.item_packets, 0, "an absent gem cannot be used")
        T.assert_equal(report.rejected[1].reason, "item_absent", "and the refusal is named")
    end)
end

return M
