-- rotations/mage_frost/pet_controller.lua
-- The water elemental, commanded through the kernel (ADR 08 §2.2, §3.2, §6.1).
--
-- ============================================================================
-- WHAT THIS FILE USED TO BE, AND WHY THAT WAS THE PROBLEM
-- ============================================================================
-- Every command here was `pcall(core.input.pet_attack, target)` with the result DISCARDED.
-- The SDK "performs ZERO validation -- it only sends a packet" (§2.6), so with no pet, a dead
-- pet, or a target that despawned between selection and the packet, the old code did nothing
-- and reported nothing. That is §12's LazyBot complaint -- an empty catch block -- inside a
-- rotation. Nobody could tell a working pet from a missing one by reading the logs, because
-- both produced silence.
--
-- Commands now leave as `pet_command` intents. The gain is not indirection: it is that
-- kernel/intent_executors.lua refuses each of those cases BY NAME (`no_pet`, `pet_dead`,
-- `unit_unresolved`) before the SDK is touched, and that the refusal is a value this file can
-- return rather than a silence it swallows.
--
-- ============================================================================
-- PET IS A CHANNEL, SO IT MUST BE ACQUIRED
-- ============================================================================
-- §2.2: PET is a channel rather than a column on some permission table "because a rotation
-- that holds CASTING would otherwise implicitly own the pet -- exactly the ambient authority
-- the channel split exists to remove". So every command acquires PET first, and a command that
-- cannot get the channel is REFUSED. A safety plugin leashing the pet at band SAFETY outranks
-- the rotation, and the rotation finds out rather than fighting it packet-for-packet.
--
-- THE LEASE IS NOT RELEASED HERE, AND THAT IS DELIBERATE. §6.1's generation check re-validates
-- an intent against a LIVE lease at commit time, which happens later in the same tick. Handing
-- PET back immediately after submitting would kill the very command that was just emitted, as
-- `stale_generation`. The TTL is what ends the lease, one tick later -- long enough for the
-- commit stage, short enough that a faulting rotation cannot sit on the channel.
--
-- ============================================================================
-- WHAT IS STILL A LIVE HANDLE, AND WHY
-- ============================================================================
-- `refresh` reads `player.object` off the blackboard and walks `get_pet -> is_alive`. The
-- frozen snapshot (§2.7) carries no pet tier at all -- there is nothing to read -- and
-- inventing a live read to make the conversion look complete is the failure mode §2.7 exists
-- to prevent. It stays as it is, and the gap is logged rather than papered over.
--
-- The intents themselves carry NO handle: the unit is named symbolically and resolved one
-- stage later, because a game_object pointer "can become invalid BETWEEN USES".

local API = require("rotations/mage_frost/sentinel_api")

local PetController = {}
PetController.__index = PetController

local FREEZE_SPELL_ID = 33395

--- Identity and band, mirroring manifest.lua. Duplicated rather than read from it because
--- manifest.lua requires frost_tbc.lua, which requires this file -- reading it back would be a
--- require cycle. A mismatch is caught by the lease itself: the broker records the owner, and
--- a second identity would show up as two competitors for one channel.
local OWNER = "sentinel.rotation.mage_frost"
local BAND, OFFSET, TIER = "COMBAT", 0, "rotation"

--- One tick. The lease has to outlive submission (COMMIT runs later in the same tick) and
--- nothing more -- a longer TTL would park PET on a rotation that faulted mid-tick.
local LEASE_TTL_TICKS = 1

--- The symbolic unit reference the commit stage resolves.
---
--- HARDCODED, because the kernel's closed unit vocabulary (`Executors.UNIT_PLAYER/TARGET/PET`)
--- is not published on `_G.Sentinel` -- only `Channel`, `Band` and `Status` are. So a plugin
--- that must not require the kernel has no way to name the set it is required to draw from.
--- Logged as an API gap; the string is isolated here so there is one place to change.
local UNIT_TARGET = "target"

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function get_guid(unit)
    local ok, guid = safe_call(unit, "get_guid")
    if ok and guid then
        return guid
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Dispatch
-- ---------------------------------------------------------------------------

---Acquire PET and submit one intent per command, in the order given.
---
---ONE LEASE, N INTENTS. Each command is its own intent so it can be gated, refused and
---observed on its own -- a compound command would have a single verdict for two verbs, and the
---one the SDK refused would hide behind the one it accepted. They share a lease because they
---share a channel and an authorising generation; §3.2's rule is one intent TYPE per channel,
---not one intent per channel per tick.
---@param commands table[] intent payloads, each with a `command` field
---@return boolean ok  every command was accepted
---@return string|nil reason  the first refusal, named
---@return table results  { { command, ok, reason }, ... } -- empty when no lease was granted
local function dispatch(commands)
    local results = {}

    local control = API.control
    if control == nil then
        -- No kernel means no lease, and no lease means no authority. The old code had no such
        -- moment to fail at: it reached `core.input` directly, so "the kernel is not up" and
        -- "the command worked" were indistinguishable.
        return false, "no_control", results
    end

    local channels = API.Channel
    if channels == nil or channels.PET == nil then
        return false, "no_pet_channel", results
    end

    local caretaker, acquire_reason = control:acquire({
        channel = channels.PET,
        owner = OWNER,
        band = BAND,
        offset = OFFSET,
        tier = TIER,
        ttl_ticks = LEASE_TTL_TICKS,
    })
    if caretaker == nil then
        return false, acquire_reason or "pet_unavailable", results
    end

    local all_ok, first_reason = true, nil
    for _, payload in ipairs(commands) do
        local ok, reason = caretaker:submit({ type = "pet_command", payload = payload })
        local result = { command = payload.command, ok = ok == true }
        if not result.ok then
            -- Spelled out rather than `ok and nil or reason`: that idiom collapses to the
            -- fallback whenever the middle term is nil, so every ACCEPTED command would have
            -- carried a refusal reason. A result that names a failure on a success is worse
            -- than no result at all, because it reads exactly like a real one.
            result.reason = reason or "submit_refused"
            all_ok = false
            if first_reason == nil then first_reason = result.reason end
        end
        results[#results + 1] = result
    end

    return all_ok, first_reason, results
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function PetController:new()
    local o = setmetatable({}, PetController)
    o._state = "idle"
    o._sent_guid = nil
    return o
end

function PetController:get_state()
    return self._state
end

---Sense the pet off the live player handle.
---
---UNCONVERTED, and that is the honest outcome rather than an oversight: the frozen snapshot
---carries no pet tier, so there is no value to read instead of this handle. Adding a live read
---somewhere else would move the problem, not solve it.
function PetController:refresh(bb)
    local player = bb:get("player.object")
    if not player then
        bb:set("combat.has_water_elemental", false)
        bb:set("combat.pet_is_attacking", false)
        return
    end

    local ok_pet, pet = safe_call(player, "get_pet")
    if not ok_pet or not pet then
        bb:set("combat.has_water_elemental", false)
        bb:set("combat.pet_is_attacking", false)
        return
    end

    local ok_alive, alive = safe_call(pet, "is_alive")
    local is_alive = ok_alive and alive == true
    bb:set("combat.has_water_elemental", is_alive)

    if is_alive then
        local ok_target, pet_target = safe_call(pet, "get_target")
        bb:set("combat.pet_is_attacking", ok_target and pet_target ~= nil)
    else
        bb:set("combat.pet_is_attacking", false)
    end
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
--
-- `_state` and `_sent_guid` are still set BEFORE the outcome is known, which is the shape the
-- pre-conversion code had and the shape its tests pin. It is not correct -- a refused command
-- still marks the target as "sent", so `already_sent_to` suppresses the retry -- but changing
-- it changes a pin, and a pin is changed by agreement rather than by whoever is editing.
-- Recorded as a finding; the fix belongs with whatever teaches this file to read the commit
-- report, since submission acceptance is not commit success either.

---@return boolean ok, string|nil reason, table results
function PetController:attack(target)
    self._state = "attacking"
    self._sent_guid = get_guid(target)
    return dispatch({
        { command = "attack", unit = UNIT_TARGET },
    })
end

---@return boolean ok, string|nil reason, table results
function PetController:freeze(target)
    self._state = "attacking"
    self._sent_guid = get_guid(target)
    return dispatch({
        { command = "cast", spell_id = FREEZE_SPELL_ID, unit = UNIT_TARGET },
    })
end

---Recall the pet: stop attacking, AND come back. Two commands, so two intents.
---@return boolean ok, string|nil reason, table results
function PetController:passive()
    self._state = "passive"
    return dispatch({
        { command = "passive" },
        { command = "follow" },
    })
end

function PetController:reset()
    self._state = "idle"
    self._sent_guid = nil
end

function PetController:already_sent_to(target)
    if not target or not self._sent_guid then
        return false
    end
    return self._sent_guid == get_guid(target)
end

return PetController
