-- kernel/bands.lua
-- Priority bands. The single authority for "how important is this, and who may claim it".
--
-- ADR 08 §6.2: "Fixed bands so numbers are not folklore. Bare integers are the documented
-- failure mode in extensible systems -- LazyBot's priorities are magic numbers scattered
-- across state classes with nothing preventing collisions."
--
-- So a caller declares `{ band = "COMBAT", offset = 0 }` and `resolve()` hands back an
-- integer. A bare integer is REFUSED: if 55 can be passed directly, the band names are
-- decoration and the collisions come straight back.

local Bands = {}

--- Highest authority first. Order matters: the broker walks it, and callers read it.
Bands.ORDER = { "SAFETY", "SURVIVAL", "COMBAT", "GOAL", "HOUSEKEEP", "IDLE" }

Bands.BANDS = {
    SAFETY    = { min = 90, max = 99 }, -- death, corpse run, stuck, zone transition, loading screen
    SURVIVAL  = { min = 70, max = 89 }, -- defensive CDs, emergency heal, flee, escape
    COMBAT    = { min = 50, max = 69 }, -- rotation, pull
    GOAL      = { min = 30, max = 49 }, -- the active activity: grind / quest / gather
    HOUSEKEEP = { min = 10, max = 29 }, -- loot, vendor, repair, mail, mount
    IDLE      = { min = 0,  max = 9 },  -- rest, buff, afk
}

--- ADR 08 §3.2: `immediate = true` is "restricted to leases at band >= 70".
Bands.IMMEDIATE_MIN_PRIORITY = Bands.BANDS.SURVIVAL.min

-- ---------------------------------------------------------------------------
-- Tier permissions (ADR 08 §6.2)
-- ---------------------------------------------------------------------------

-- "The kernel REJECTS a manifest requesting a band its tier is not permitted -- an Ambient
-- plugin cannot declare SAFETY."
--
-- That sentence is the only hard constraint the ADR states. The rest of this table is
-- derived from the tier descriptions in §5.2/§5.3 and is deliberately NARROW, because
-- widening a permission later is safe and narrowing one after plugins depend on it is not:
--
--   rotation  COMBAT + SURVIVAL      -- §8.4 rotations carry `defense` entries at 70-89
--   activity  GOAL + HOUSEKEEP+IDLE  -- §6.2 "the active activity", plus its own chores
--   behavior  SAFETY..IDLE minus     -- §5.2: anti-stuck and corpse recovery "run as
--             COMBAT/GOAL               kernel-priority interrupts (band 90-99) even though
--                                       they are plugins"; loot/vendor sit at 10-29
--   strategy  none                   -- §5.3 strategies CHOOSE (target, pull); they do not
--                                       act, so they never hold a channel
--   sensor    HOUSEKEEP + IDLE       -- sensors mostly read, but see the caveat below
--   ambient   NONE                   -- see below; this is not "IDLE", it is nothing
--
-- WHY `ambient` GETS NOTHING RATHER THAN IDLE.
-- An ambient plugin that cannot acquire ANY control channel is the entire reason that tier is
-- safe to load arbitrarily: it can observe, log and advise, but it cannot move, cast, target or
-- open a window, so admitting an unknown one costs nothing but CPU. Granting it IDLE would make
-- "ambient" a privilege level rather than the absence of one, and the safety argument for
-- loading them freely would evaporate.
--
-- CAVEAT ON `sensor` -- A KNOWN GAP, NOT AN OVERSIGHT.
-- ADR 08 §2.2 records that `core.trade_skill.get_trade_skill_line()` maps to
-- `GetTradeSkillLine()`, so READING a profession's skill rank requires OPENING the profession
-- window -- a sensor read that needs a MODAL_UI claim. This table does not grant MODAL_UI to
-- any tier, so that particular read is currently UNIMPLEMENTABLE by design rather than merely
-- unimplemented. Phase 5 resolves it, when the behaviour tier that owns modal frames exists and
-- a sensor can ask it for the reading instead of taking the claim itself.
--
-- Phase 3's manifest validator is the first real consumer. The broker also enforces it
-- opportunistically, whenever a caller supplies a tier.
Bands.TIER_PERMISSIONS = {
    rotation = { COMBAT = true, SURVIVAL = true },
    activity = { GOAL = true, HOUSEKEEP = true, IDLE = true },
    behavior = { SAFETY = true, SURVIVAL = true, HOUSEKEEP = true, IDLE = true },
    strategy = {},
    sensor   = { HOUSEKEEP = true, IDLE = true },
    ambient  = {},
}

---@param tier string
---@param band string
---@return boolean permitted, string|nil reason
function Bands.permits(tier, band)
    local allowed = Bands.TIER_PERMISSIONS[tier]
    if allowed == nil then
        -- An unrecognised tier fails closed. Defaulting to "allow" would make every future
        -- typo in a manifest a silent privilege escalation.
        return false, "unknown_tier"
    end
    if not allowed[band] then
        return false, "band_not_permitted_for_tier"
    end
    return true, nil
end

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

---Turn a named band declaration into an integer priority.
---@param request table { band = "COMBAT", offset = 0, tier = "rotation"? }
---@return number|nil priority, string|nil reason
function Bands.resolve(request)
    if type(request) ~= "table" or type(request.band) ~= "string" then
        return nil, "band_must_be_named"
    end

    local range = Bands.BANDS[request.band]
    if range == nil then
        return nil, "unknown_band"
    end

    if request.tier ~= nil then
        local permitted, reason = Bands.permits(request.tier, request.band)
        if not permitted then
            return nil, reason
        end
    end

    local offset = request.offset or 0
    if type(offset) ~= "number" or offset ~= math.floor(offset) then
        return nil, "offset_must_be_an_integer"
    end
    -- An offset that overflows its band would silently promote the caller into the band
    -- above it -- e.g. COMBAT+20 landing in SURVIVAL. That is the collision §6.2 forbids.
    if offset < 0 or range.min + offset > range.max then
        return nil, "offset_out_of_band"
    end

    return range.min + offset, nil
end

---@param priority number
---@return string|nil band name, or nil when the priority is outside 0-99
function Bands.name_for(priority)
    if type(priority) ~= "number" then return nil end
    for _, band in ipairs(Bands.ORDER) do
        local range = Bands.BANDS[band]
        if priority >= range.min and priority <= range.max then
            return band
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- spell_queue mapping (ADR 08 §6.3) -- DATA. Nothing in Phase 2 consumes it.
-- ---------------------------------------------------------------------------

-- The kernel does not own the bottom of the casting stack (§2.6): `spell_queue` is already
-- a cross-plugin arbitration channel with a documented convention -- 1 for essentially
-- everything you author, 7 reserved for interrupts, 9 for manual player input. The commit
-- stage maps onto that convention rather than fighting it.
Bands.SPELL_QUEUE_PRIORITY = {
    SAFETY    = 7,
    SURVIVAL  = 7,
    COMBAT    = 1,
    GOAL      = 1,
    HOUSEKEEP = 1,
    IDLE      = 1,
}

--- Reserved for the human at the keyboard. Sentinel never emits it.
Bands.RESERVED_PLAYER_SPELL_QUEUE_PRIORITY = 9

---@param priority number
---@return number 1 or 7 -- never 9
function Bands.spell_queue_priority(priority)
    local band = Bands.name_for(priority)
    if band == nil then
        -- Out-of-range priorities get the authored value, not the interrupt slot: an
        -- unrecognised number must not be able to jump the queue.
        return 1
    end
    return Bands.SPELL_QUEUE_PRIORITY[band]
end

return Bands
