-- kernel/snapshot_source.lua
-- The SENSE stage's extraction layer: live game_object handles in, frozen values out.
--
-- This is the ONLY place in the kernel that is allowed to hold a handle, and it holds one
-- for the duration of a single function call. ADR 08 §2.7: "handles held only transiently
-- inside the sensor that read them."
--
-- THREE RULES, all of them load-bearing:
--
-- 1. GUARD BEFORE EVERY USE, not just at acquisition (ADR 08 §2.7). The pointer can die
--    between two accessor calls on the same handle, in the same tick. Every read goes
--    through `read()`, which pcalls. A handle that dies partway through capture yields
--    `available = false` for the whole unit rather than a half-true record.
--
-- 2. UNAVAILABLE IS A VALUE (ADR 08 §9.3). "Without an explicit unavailable value, every
--    unreadable field silently becomes a plausible-looking zero." So an unreadable vital is
--    `nil` and the unit carries `available = false`. It is never 0 (dead) or 1 (healthy) --
--    both of those are decisions a sensor has no business making.
--
-- 3. RAW SYLVANAS TYPES STOP HERE (ADR 08 §9.3). `get_class()` returns a NUMERIC class id;
--    this repo has already been bitten by that (enums yield UPPERCASE while RestedXP class
--    tails are Title-Case). Both the raw id and the normalized name are captured.
--
-- Scope: HOT TIER only (ADR 08 §7) -- player vitals, target, cast state, position. Warm
-- (nearby units, auras) and cold (bags, quest log, poll-only) tiers arrive with the
-- subsystems that consume them.

local ClassNames = require("shared/class_names")

local SnapshotSource = {}

--- Call a handle accessor without letting a dead pointer escape.
--- @return boolean ok, any value
local function read(handle, method, ...)
    local fn = handle[method]
    if type(fn) ~= "function" then return false, nil end
    local ok, value = pcall(fn, handle, ...)
    if ok then return true, value end
    return false, nil
end

--- Sylvanas' own guidance is to check validity before every use. A handle that fails this
--- is garbage; a handle that passes may still die on the next line, which `read` absorbs.
local function is_alive(handle)
    if handle == nil then return false end
    local ok, valid = read(handle, "is_valid")
    if not ok then return false end
    -- Some handles do not expose is_valid; absence is not evidence of death.
    if valid == nil then return true end
    return valid == true
end

--- A ratio is only meaningful when the denominator was actually readable and positive.
--- 0/0 is "unknown", not "empty" and not "full".
local function ratio(current_ok, current, max_ok, max)
    if not current_ok or not max_ok then return nil end
    if type(current) ~= "number" or type(max) ~= "number" then return nil end
    if max <= 0 then return nil end
    return current / max
end

local function copy_position(ok, position)
    if not ok or type(position) ~= "table" then return nil end
    local x, y, z = position.x, position.y, position.z
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    -- Extracted as a fresh plain table: the SDK's position object may itself be a handle.
    return { x = x, y = y, z = z }
end

local function boolean_or_nil(ok, value)
    if not ok then return nil end
    return value == true
end

--- Extract one unit into `prefix.*` keys. Returns true when the unit was fully readable.
local function capture_unit(builder, prefix, handle)
    if not is_alive(handle) then
        builder:put(prefix .. ".available", false)
        return false
    end

    local pos_ok, position = read(handle, "get_position")
    local hp_ok, hp = read(handle, "get_health")
    local hp_max_ok, hp_max = read(handle, "get_max_health")
    local pw_ok, pw = read(handle, "get_power", 0)
    local pw_max_ok, pw_max = read(handle, "get_max_power", 0)
    local lvl_ok, level = read(handle, "get_level")
    local class_ok, class_id = read(handle, "get_class")

    -- Re-check AFTER the reads. If the pointer died partway through, the values collected
    -- so far describe a unit that no longer exists; publishing them as fact is worse than
    -- publishing nothing (ADR 08 §2.7 -- guard before EVERY use).
    if not is_alive(handle) then
        builder:put(prefix .. ".available", false)
        return false
    end

    builder:put(prefix .. ".available", true)
    builder:put(prefix .. ".position", copy_position(pos_ok, position))
    builder:put(prefix .. ".health_pct", ratio(hp_ok, hp, hp_max_ok, hp_max))
    builder:put(prefix .. ".power_pct", ratio(pw_ok, pw, pw_max_ok, pw_max))
    builder:put(prefix .. ".level", lvl_ok and type(level) == "number" and level or nil)

    -- Raw id preserved for the record; normalized name for everything that compares
    -- against Title-Case (ClassIs conditions, RestedXP class tails).
    local numeric_class = class_ok and type(class_id) == "number" and class_id or nil
    builder:put(prefix .. ".class_id", numeric_class)
    builder:put(prefix .. ".class", ClassNames.resolve(numeric_class))

    builder:put(prefix .. ".is_dead", boolean_or_nil(read(handle, "is_dead")))
    builder:put(prefix .. ".in_combat", boolean_or_nil(read(handle, "is_in_combat")))

    return true
end

---Capture the hot tier for the player and its current target.
---@param builder table Snapshot builder (kernel/snapshot.lua)
---@param player table|nil The local player handle -- consumed here, never stored
function SnapshotSource.capture_player(builder, player)
    local ok = capture_unit(builder, "player", player)

    if ok then
        builder:put("player.is_casting", boolean_or_nil(read(player, "is_casting_spell")))
        builder:put("player.is_channeling", boolean_or_nil(read(player, "is_channelling_spell")))
        builder:put("player.is_moving", boolean_or_nil(read(player, "is_moving")))
        builder:put("player.is_mounted", boolean_or_nil(read(player, "is_mounted")))
        builder:put("player.is_ghost", boolean_or_nil(read(player, "is_ghost")))
    end

    local target = nil
    if ok then
        local target_ok, handle = read(player, "get_target")
        if target_ok then target = handle end
    end
    capture_unit(builder, "target", target)
end

return SnapshotSource
