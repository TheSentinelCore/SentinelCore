local BGCatalog = require("modules/battleground/data/bg_catalog")
local MapIds = require("shared/map_ids")
local Compat = require("shared/compat")

local safe_call0 = Compat.safe_call0
local safe_call2 = Compat.safe_call2
local num = Compat.num
local is_trueish = Compat.is_trueish

local SUPPORTED_BG_MAPS = {
    [MapIds.ALTERAC_VALLEY] = true,
    [MapIds.WARSONG_GULCH] = true,
    [MapIds.ARATHI_BASIN] = true,
    [MapIds.EYE_OF_THE_STORM] = true,
}

local function combined_name(map_name, instance_name)
    return (tostring(map_name or "") .. " " .. tostring(instance_name or "")):lower()
end

local function matches_bg_alias(data, haystack)
    local lowered = tostring(haystack or ""):lower()
    if lowered == "" or not data then
        return false
    end
    if lowered:find(tostring(data.name or ""):lower(), 1, true) then
        return true
    end
    for _, alias in ipairs(data.aliases or {}) do
        local normalized = tostring(alias or ""):lower()
        if normalized ~= "" and lowered:find(normalized, 1, true) then
            return true
        end
    end
    return false
end

local function matches_supported_bg_name(map_name, instance_name)
    local lowered_map = tostring(map_name or ""):lower()
    local lowered_instance = tostring(instance_name or ""):lower()
    local joined = combined_name(map_name, instance_name)
    for _, data in pairs(BGCatalog) do
        if matches_bg_alias(data, lowered_map)
            or matches_bg_alias(data, lowered_instance)
            or matches_bg_alias(data, joined) then
            return true
        end
    end
    return false
end

local KNOWN_BATTLEFIELD_STATUS = {
    none = true,
    queued = true,
    confirm = true,
    active = true,
}

local function normalize_battlefield_status(raw)
    if type(raw) == "table" then
        raw = raw.status or raw.state or raw[1] or ""
    end
    local lowered = tostring(raw or ""):lower()
    if KNOWN_BATTLEFIELD_STATUS[lowered] then
        return lowered
    end
    return "unknown"
end

local function normalize_queue_kind(kind)
    local lowered = tostring(kind or ""):lower()
    if lowered == "pvp" or lowered == "pve" then
        return lowered
    end
    return "unknown"
end

local function parse_queue_popup_result(a, b)
    if type(a) == "boolean" then
        if a == true then
            return true, b, true
        end
        return false, nil, true
    end
    if type(a) == "table" and a.has_popup ~= nil then
        local has_popup = is_trueish(a.has_popup)
        if has_popup then
            return true, a.info, true
        end
        return false, nil, true
    end
    return false, nil, false
end

local BattlegroundSensor = {}
BattlegroundSensor.__index = BattlegroundSensor

function BattlegroundSensor:new(blackboard, izi)
    return setmetatable({
        _blackboard = blackboard,
        _izi = izi,
        _queue_popup_seq = 0,
        _last_queue_popup = false,
        _battlefield_state_streak_5 = 0,
        _last_sensor_in_bg_ms = 0,
    }, BattlegroundSensor)
end

---Check if a map ID is a supported battleground zone.
---@param map_id number
---@param map_name string
---@param instance_name string
---@return boolean
function BattlegroundSensor:_is_bg_zone(map_id, map_name, instance_name, izi)
    local active_izi = izi or self._izi
    if active_izi then
        local ok, result = pcall(active_izi.is_battleground, active_izi, map_id)
        if ok and result == true then
            return true
        end
    end
    return SUPPORTED_BG_MAPS[tonumber(map_id)] == true
        or matches_supported_bg_name(map_name, instance_name)
end

function BattlegroundSensor:_read_battleground_snapshot(map_id, map_name, instance_name, now_ms, izi)
    local active_izi = izi or self._izi
    local snapshot = {
        in_bg = false,
        battlefield_state = nil,
        battlefield_winner = nil,
        battlefield_runtime_ms = 0,
        battlefield_state_streak_5 = self._battlefield_state_streak_5,
        in_prep = false,
        in_action = false,
        in_finished = false,
        queue_status_slots = { "unknown", "unknown", "unknown" },
        queue_status_summary = "unknown|unknown|unknown",
        queue_popup = false,
        queue_popup_kind = "unknown",
        queue_popup_source = "none",
        queue_popup_confidence = "none",
        queue_popup_seq = self._queue_popup_seq,
        queue_popup_age_ms = 0,
        queue_popup_slot_idx = nil,
    }

    local game_ui = core and core.game_ui or nil
    if game_ui then
        snapshot.battlefield_state = safe_call0(game_ui.get_battlefield_state, game_ui)
        snapshot.battlefield_winner = safe_call0(game_ui.get_battlefield_winner, game_ui)
        snapshot.battlefield_runtime_ms = num(safe_call0(game_ui.get_battlefield_run_time, game_ui))
        if type(game_ui.get_battlefield_status) == "function" then
            for index = 1, 3 do
                snapshot.queue_status_slots[index] = normalize_battlefield_status(safe_call2(game_ui.get_battlefield_status, game_ui, index))
            end
        end
    end
    snapshot.queue_status_summary = table.concat(snapshot.queue_status_slots, "|")

    local explicit_popup = false
    if active_izi and type(active_izi.queue_popup_info) == "function" then
        local ok, a, b = pcall(active_izi.queue_popup_info)
        if ok then
            local has_popup, info, explicit = parse_queue_popup_result(a, b)
            if explicit then
                explicit_popup = true
                snapshot.queue_popup = has_popup
                if has_popup then
                    snapshot.queue_popup_source = "queue_popup_info"
                    snapshot.queue_popup_confidence = "high"
                    snapshot.queue_popup_kind = normalize_queue_kind(info and info.kind)
                    snapshot.queue_popup_age_ms = num(info and (info.age_ms or info.since_ms) or 0)
                    local pvp = info and info.pvp or nil
                    if type(pvp) == "table" and type(pvp.slots) == "table" and #pvp.slots > 0 then
                        snapshot.queue_popup_slot_idx = pvp.slots[1] and pvp.slots[1].idx or nil
                    elseif type(info) == "table" then
                        snapshot.queue_popup_slot_idx = info.idx
                    end
                    if snapshot.queue_popup_kind == "unknown" and type(info) == "table" then
                        if type(info.pvp) == "table" then
                            snapshot.queue_popup_kind = "pvp"
                        elseif type(info.pve) == "table" then
                            snapshot.queue_popup_kind = "pve"
                        end
                    end
                end
            end
        end
    end

    if (not snapshot.queue_popup) and active_izi and type(active_izi.queue_has_popup) == "function" then
        snapshot.queue_popup = is_trueish(safe_call0(active_izi.queue_has_popup, active_izi))
        if snapshot.queue_popup then
            snapshot.queue_popup_source = explicit_popup and snapshot.queue_popup_source or "queue_has_popup"
            snapshot.queue_popup_confidence = explicit_popup and snapshot.queue_popup_confidence or "low"
        end
    end

    if snapshot.queue_popup and (not self._last_queue_popup) then
        self._queue_popup_seq = self._queue_popup_seq + 1
    end
    self._last_queue_popup = snapshot.queue_popup == true
    snapshot.queue_popup_seq = self._queue_popup_seq

    snapshot.in_prep = tonumber(snapshot.battlefield_state) == 2
    snapshot.in_action = tonumber(snapshot.battlefield_state) == 3
    snapshot.in_finished = tonumber(snapshot.battlefield_state) == 5

    if snapshot.in_finished then
        self._battlefield_state_streak_5 = self._battlefield_state_streak_5 + 1
    else
        self._battlefield_state_streak_5 = 0
    end
    snapshot.battlefield_state_streak_5 = self._battlefield_state_streak_5

    local has_active_like_status = false
    for index = 1, 3 do
        local status = snapshot.queue_status_slots[index]
        if status == "active" or status == "confirm" then
            has_active_like_status = true
            break
        end
    end

    snapshot.in_bg = snapshot.in_prep
        or snapshot.in_action
        or snapshot.in_finished
        or SUPPORTED_BG_MAPS[tonumber(map_id)] == true
        or matches_supported_bg_name(map_name, instance_name)
    if snapshot.in_bg then
        self._last_sensor_in_bg_ms = now_ms
    elseif has_active_like_status and (now_ms - self._last_sensor_in_bg_ms) <= 1000 then
        snapshot.in_bg = true
    end

    return snapshot
end

function BattlegroundSensor:refresh(map_id, map_name, instance_name, now_ms, izi)
    local bb = self._blackboard
    local active_izi = izi or self._izi

    if self:_is_bg_zone(map_id, map_name, instance_name, active_izi) then
        local bg = self:_read_battleground_snapshot(map_id, map_name, instance_name, now_ms, active_izi)
        bb:set("bg.sensor.in_bg", bg.in_bg)
        bb:set("bg.sensor.in_prep", bg.in_prep)
        bb:set("bg.sensor.in_action", bg.in_action)
        bb:set("bg.sensor.in_finished", bg.in_finished)
        bb:set("bg.sensor.battlefield_state", bg.battlefield_state)
        bb:set("bg.sensor.battlefield_winner", bg.battlefield_winner)
        bb:set("bg.sensor.battlefield_runtime_ms", bg.battlefield_runtime_ms)
        bb:set("bg.sensor.battlefield_state_streak_5", bg.battlefield_state_streak_5)
        bb:set("bg.sensor.queue_status_slots", bg.queue_status_slots)
        bb:set("bg.sensor.queue_status_summary", bg.queue_status_summary)
        bb:set("bg.sensor.queue_popup", bg.queue_popup)
        bb:set("bg.sensor.queue_popup_kind", bg.queue_popup_kind)
        bb:set("bg.sensor.queue_popup_source", bg.queue_popup_source)
        bb:set("bg.sensor.queue_popup_confidence", bg.queue_popup_confidence)
        bb:set("bg.sensor.queue_popup_seq", bg.queue_popup_seq)
        bb:set("bg.sensor.queue_popup_age_ms", bg.queue_popup_age_ms)
        bb:set("bg.sensor.queue_popup_slot_idx", bg.queue_popup_slot_idx)
    else
        bb:set("bg.sensor.in_bg", false)
        bb:set("bg.sensor.in_prep", false)
        bb:set("bg.sensor.in_action", false)
        bb:set("bg.sensor.in_finished", false)
        bb:set("bg.sensor.battlefield_state", nil)
        bb:set("bg.sensor.battlefield_winner", nil)
        bb:set("bg.sensor.battlefield_runtime_ms", 0)
        bb:set("bg.sensor.battlefield_state_streak_5", 0)
        bb:set("bg.sensor.queue_status_slots", { "unknown", "unknown", "unknown" })
        bb:set("bg.sensor.queue_status_summary", "unknown|unknown|unknown")
        bb:set("bg.sensor.queue_popup", false)
        bb:set("bg.sensor.queue_popup_kind", "unknown")
        bb:set("bg.sensor.queue_popup_source", "none")
        bb:set("bg.sensor.queue_popup_confidence", "none")
        bb:set("bg.sensor.queue_popup_seq", self._queue_popup_seq)
        bb:set("bg.sensor.queue_popup_age_ms", 0)
        bb:set("bg.sensor.queue_popup_slot_idx", nil)
    end
end

return BattlegroundSensor
