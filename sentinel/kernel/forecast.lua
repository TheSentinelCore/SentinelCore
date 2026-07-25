-- kernel/forecast.lua
-- `Sentinel.forecast` -- the temporal-forecast service: how long this target lives, how much damage
-- is already in the air, what health the player will have when it lands.
--
-- ================================================================================
-- WHY THIS IS A KERNEL SERVICE AND NOT A BLACKBOARD KEY
-- ================================================================================
-- It used to be `module.combat.izi_bridge`: the combat module parked its live IziBridge on the
-- blackboard and six readers fetched it back out. That failed in two independent ways at once.
--
--   * THE GUARD REFUSED IT. IziBridge carries a metatable, and `core/blackboard.lua` refuses any
--     value carrying behaviour. `SentinelCombat:initialize()` therefore threw on its FIRST
--     statement, `initialize_all` swallowed the error, and combat was dead in every real boot from
--     Phase 4b until Phase 4c. Phase 4c reopened the guard by ledgering the key. That is the wrong
--     half: the guard was right, and the blackboard is for VALUES.
--   * FOUR OF THE SIX READERS CANNOT BE REACHED BY CONSTRUCTOR. `condition_library`,
--     `retribution_conditions`, `frost_combat_state` and `frost_conditions` are handed a blackboard
--     and nothing else, and combat does not construct any of them. So "pass it in" -- the fix the
--     retired ledger entry proposed -- was mechanically impossible for two thirds of the readers.
--
-- Publishing it as a service is the only route that empties the blackboard AND reaches all six. It
-- also collapses the TWO live IziBridge instances (one built by `SentinelApp:new`, a second by
-- `modules/combat/init.lua`) into one shared instance, which is what ADR 08 §5.1 asks for: shared
-- reference data is kernel precisely because "duplicating it costs memory and drifts".
--
-- THE NAME. ADR 08 §8.4.1 counts this exact group of blocked combinators as "temporal forecast (5)"
-- when it tallies what the declarative tier cannot yet express, and the injector module underneath
-- is literally `common/modules/combat_forecast` (docs/SylvannasAPI/user/modules/combat-forecast.md:
-- "prevent casting long cooldown spells ... on targets that are about to die"). `forecast` is the
-- word both the ADR and the SDK already use for this; `izi` is a vendor name and would put the
-- injector's branding on the public API.
--
-- ================================================================================
-- ABSENCE IS A NAMED STATE, NEVER A PLAUSIBLE ZERO
-- ================================================================================
-- ADR 08 §9.3: "without an explicit unavailable value, every unreadable field silently becomes a
-- plausible-looking zero". Every accessor here returns nil when it cannot answer, and `is_available`
-- is the only way to tell "no data" from "cannot read". A time-to-die of 0 means the target is dead;
-- a nil means nobody knows. Collapsing those would make every rotation treat an absent SDK as a
-- corpse.
--
-- ================================================================================
-- WHAT THIS SERVICE CANNOT SEE
-- ================================================================================
--  1. WHETHER THE NUMBERS ARE ANY GOOD. It forwards what `common/izi_sdk` and
--     `common/modules/{health_prediction,combat_forecast}` say. The Sylvannas docs are explicit that
--     the forecast "collects data throughout your gameplay session in order to become more accurate
--     over time" and is reset by an F6 reload -- so early in a session these answers are weak, and
--     nothing here can distinguish a weak answer from a strong one. There is no confidence channel
--     in the SDK to forward.
--  2. STALENESS. Every call goes straight through to the bridge; there is no per-tick memoisation
--     and no frozen snapshot. Two calls in one tick may disagree. That is deliberate for now --
--     these are not snapshot fields (`kernel/snapshot.lua` holds VALUES, and time-to-die is derived
--     from a live unit handle) -- but it means a rotation that asks twice is not asking about one
--     instant.
--  3. WHICH UNIT IT WAS ASKED ABOUT. `unit` is passed straight through to the SDK as a raw handle.
--     ADR 08 §2.7: that pointer can become invalid BETWEEN USES. This service never stores one, so
--     it cannot go stale here -- but it also cannot validate the one it is handed, and a dead handle
--     produces a pcall failure that reads as "cannot say" rather than as "you passed me garbage".
--  4. THAT ANYONE IS WIRED TO IT. `Api.CAPABILITY_BINDINGS` proves the members RESOLVE, not that a
--     real `SentinelApp` put a live bridge behind them. `tests/integration/test_kernel_end_to_end`
--     is what proves the boot wiring.

local Forecast = {}
Forecast.__index = Forecast

---@param opts table|nil { bridge = IziBridge|nil }
---
--- `bridge` is optional on purpose. Offline, and inside the injector when the IZI SDK is absent,
--- there is no bridge at all -- and a service that refused to be constructed would take the whole
--- composition root down with it, which is the debt `integrations/izi_bridge.lua` already cleared
--- once (ADR 08 §11.6).
function Forecast:new(opts)
    opts = opts or {}
    local o = setmetatable({}, Forecast)
    o._bridge = opts.bridge
    return o
end

--- The bridge method, or nil when this bridge does not have one.
---
--- NOT merely a nil-bridge check. `condition_library.incoming_damage_above` called
--- `izi_bridge:get_incoming_damage(...)`, a method `integrations/izi_bridge.lua` has never defined
--- -- so a present-but-incomplete collaborator is a real shape here, not a hypothetical, and it must
--- read as "cannot say" rather than as a call into nil.
local function method(bridge, name)
    if bridge == nil then return nil end
    local fn = bridge[name]
    if type(fn) ~= "function" then return nil end
    return fn
end

---@return number|nil the number the bridge returned, or nil for anything else
local function ask_number(bridge, name, ...)
    local fn = method(bridge, name)
    if fn == nil then return nil end
    local ok, value = pcall(fn, bridge, ...)
    if not ok or type(value) ~= "number" then return nil end
    return value
end

---Can this service answer at all? Callers that must distinguish "no data" from "cannot read" have
---to consult this -- see ADR 08 §9.3.
---@return boolean
function Forecast:is_available()
    local fn = method(self._bridge, "is_available")
    if fn == nil then return false end
    local ok, available = pcall(fn, self._bridge)
    return ok and available == true
end

---Seconds until `unit` dies at the current damage rate.
---@param unit table|nil a live unit handle
---@return number|nil nil when nobody can say -- NEVER 0, which means "already dead"
function Forecast:time_to_die(unit)
    if unit == nil then return nil end
    return ask_number(self._bridge, "get_time_to_die", unit)
end

---`unit`'s health as a fraction of its maximum, `seconds` from now, after predicted incoming damage.
---@return number|nil
function Forecast:predicted_health_pct(unit, seconds)
    if unit == nil then return nil end
    return ask_number(self._bridge, "predict_hp_pct", unit, seconds)
end

---Predicted incoming damage over `seconds`, as a fraction of `unit`'s maximum health.
---
---DERIVED, because the bridge has no such accessor. `predict_hp_pct` returns
---`(hp - incoming) / max_hp`, so `incoming / max_hp` is exactly `hp/max_hp - predicted`. The reader
---this replaces computed the same quantity by calling `izi_bridge:get_incoming_damage(...)` --
---a method that does not exist -- and then dividing by `max_hp` unguarded.
---@return number|nil nil when the prediction or the health figures are unreadable
function Forecast:incoming_damage_pct(unit, seconds)
    local predicted = self:predicted_health_pct(unit, seconds)
    if predicted == nil then return nil end

    local hp = ask_number(unit, "get_health")
    local max_hp = ask_number(unit, "get_max_health")
    if hp == nil or max_hp == nil or max_hp <= 0 then return nil end

    return (hp / max_hp) - predicted
end

---How long the SDK expects the current fight to last, in seconds.
---Used to refuse spending a long cooldown on a fight that will be over first.
---@return number|nil
function Forecast:fight_seconds_remaining()
    return ask_number(self._bridge, "get_forecast")
end

return Forecast
