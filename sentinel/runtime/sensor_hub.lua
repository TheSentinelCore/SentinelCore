local AuraCatalog = require("modules/combat/aura_catalog")
local BGCatalog = require("modules/battleground/data/bg_catalog")
local MapIds = require("shared/map_ids")

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

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(obj[method], obj, ...)
    if not ok then
        return nil
    end
    return value
end

local function safe_call0(fn, owner)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    if owner ~= nil then
        ok, value = pcall(fn, owner)
        if ok then
            return value
        end
    end
    return nil
end

local function safe_call2(fn, owner, arg)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, arg)
    if ok then
        return value
    end
    if owner ~= nil then
        ok, value = pcall(fn, owner, arg)
        if ok then
            return value
        end
    end
    return nil
end

local function num(value)
    return tonumber(value) or 0
end

local function is_trueish(value)
    if value == true or value == 1 then
        return true
    end
    local lowered = tostring(value or ""):lower()
    return lowered == "true" or lowered == "1"
end

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

local SensorHub = {}
SensorHub.__index = SensorHub

function SensorHub:new(blackboard, event_bus)
    local o = setmetatable({}, SensorHub)
    o._blackboard = blackboard
    o._event_bus = event_bus
    local ok_unit, unit_helper = pcall(require, "common/utility/unit_helper")
    o._unit_helper = ok_unit and unit_helper or nil
    local ok_izi, izi = pcall(require, "common/izi_sdk")
    o._izi = ok_izi and izi or nil
    o._queue_popup_seq = 0
    o._last_queue_popup = false
    o._battlefield_state_streak_5 = 0
    o._last_sensor_in_bg_ms = 0
    return o
end

function SensorHub:_unit_health_pct(unit)
    if not unit then
        return 0
    end
    if self._unit_helper and type(self._unit_helper.get_health_percentage) == "function" then
        local ok, value = pcall(self._unit_helper.get_health_percentage, self._unit_helper, unit)
        if ok and type(value) == "number" then
            return value
        end
    end
    local health = tonumber(safe_call(unit, "get_health") or 0) or 0
    local max_health = tonumber(safe_call(unit, "get_max_health") or 0) or 0
    if max_health <= 0 then
        return 0
    end
    return health / max_health
end

function SensorHub:_unit_mana_pct(unit)
    if not unit then
        return 0
    end
    local mana = tonumber(safe_call(unit, "get_power", 0) or 0) or 0
    local max_mana = tonumber(safe_call(unit, "get_max_power", 0) or 0) or 0
    if max_mana <= 0 then
        return 0
    end
    return mana / max_mana
end

function SensorHub:_count_units(position, radius, ally)
    if not self._unit_helper or not position then
        return 0
    end
    local fn_name = ally and "get_ally_list_around" or "get_enemy_list_around"
    if type(self._unit_helper[fn_name]) ~= "function" then
        return 0
    end
    local ok, list = pcall(self._unit_helper[fn_name], self._unit_helper, position, radius, true, false)
    if ok and type(list) == "table" then
        return #list
    end
    return 0
end

function SensorHub:_read_battleground_snapshot(map_id, map_name, instance_name, now_ms)
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
    if self._izi and type(self._izi.queue_popup_info) == "function" then
        local ok, a, b = pcall(self._izi.queue_popup_info)
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

    if (not snapshot.queue_popup) and self._izi and type(self._izi.queue_has_popup) == "function" then
        snapshot.queue_popup = is_trueish(safe_call0(self._izi.queue_has_popup, self._izi))
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

function SensorHub:refresh()
    local player = nil
    if core and core.object_manager and type(core.object_manager.get_local_player) == "function" then
        local ok, local_player = pcall(core.object_manager.get_local_player)
        if ok then
            player = local_player
        end
    end

    local now_ms = num(core and core.game_time and core.game_time() or 0)
    local delta_ms = math.floor(num(((core and core.delta_time and core.delta_time()) or 0) * 1000))
    local ping_ms = num(core and core.get_ping and core.get_ping() or 0)
    local map_id = num(core and core.get_map_id and core.get_map_id() or 0)
    local map_name = tostring(core and core.get_map_name and core.get_map_name() or "")
    local instance_id = num(core and core.get_instance_id and core.get_instance_id() or 0)
    local instance_name = tostring(core and core.get_instance_name and core.get_instance_name() or "")

    self._blackboard:set("system.now_ms", now_ms)
    self._blackboard:set("system.delta_ms", delta_ms)
    self._blackboard:set("system.ping_ms", ping_ms)
    self._blackboard:set("system.map_id", map_id)
    self._blackboard:set("system.map_name", map_name)
    self._blackboard:set("system.instance_id", instance_id)
    self._blackboard:set("system.instance_name", instance_name)
    self._blackboard:set("player.object", player)

    local target = safe_call(player, "get_target")
    local position = safe_call(player, "get_position")
    self._blackboard:set("player.target", target)
    self._blackboard:set("player.position", position)
    self._blackboard:set("player.health_pct", self:_unit_health_pct(player))
    self._blackboard:set("player.mana_pct", self:_unit_mana_pct(player))
    self._blackboard:set("player.in_combat", safe_call(player, "is_in_combat") == true)
    self._blackboard:set("player.is_dead", safe_call(player, "is_dead") == true)
    self._blackboard:set("player.is_ghost", safe_call(player, "is_ghost") == true)
    self._blackboard:set("player.is_mounted", safe_call(player, "is_mounted") == true)
    local outdoors = safe_call(player, "is_outdoors")
    if outdoors == nil then
        outdoors = true
    end
    self._blackboard:set("player.is_outdoors", outdoors == true)
    self._blackboard:set("player.is_casting", safe_call(player, "is_casting_spell") == true)
    self._blackboard:set("player.is_channeling", safe_call(player, "is_channelling_spell") == true)
    self._blackboard:set("player.is_moving", safe_call(player, "is_moving") == true)
    self._blackboard:set("player.is_auto_attacking", safe_call(player, "is_auto_attacking") == true)
    self._blackboard:set("player.attack_speed_s", tonumber(safe_call(player, "get_attack_speed") or 0) or 0)

    local corpse_position = nil
    local resurrect_delay_s = 0
    local game_ui = core and core.game_ui or nil
    if game_ui then
        corpse_position = safe_call0(game_ui.get_corpse_position, game_ui)
        resurrect_delay_s = num(safe_call0(game_ui.get_resurrect_corpse_delay, game_ui))
    end
    self._blackboard:set("player.corpse_position", type(corpse_position) == "table" and corpse_position or nil)
    self._blackboard:set("player.resurrect_delay_s", resurrect_delay_s)

    self._blackboard:set("combat.enemy_count_10yd", self:_count_units(position, 10, false))
    self._blackboard:set("combat.enemy_count_30yd", self:_count_units(position, 30, false))
    self._blackboard:set("combat.ally_count_30yd", self:_count_units(position, 30, true))

    local active_seal = nil
    if player then
        if AuraCatalog.has_any(player, AuraCatalog.seal_of_blood) then
            active_seal = "blood"
        elseif AuraCatalog.has_any(player, AuraCatalog.seal_of_command_ranks) then
            active_seal = "command"
        end
    end
    self._blackboard:set("rotation.active_seal", active_seal)

    local bg = self:_read_battleground_snapshot(map_id, map_name, instance_name, now_ms)
    self._blackboard:set("bg.sensor.in_bg", bg.in_bg)
    self._blackboard:set("bg.sensor.in_prep", bg.in_prep)
    self._blackboard:set("bg.sensor.in_action", bg.in_action)
    self._blackboard:set("bg.sensor.in_finished", bg.in_finished)
    self._blackboard:set("bg.sensor.battlefield_state", bg.battlefield_state)
    self._blackboard:set("bg.sensor.battlefield_winner", bg.battlefield_winner)
    self._blackboard:set("bg.sensor.battlefield_runtime_ms", bg.battlefield_runtime_ms)
    self._blackboard:set("bg.sensor.battlefield_state_streak_5", bg.battlefield_state_streak_5)
    self._blackboard:set("bg.sensor.queue_status_slots", bg.queue_status_slots)
    self._blackboard:set("bg.sensor.queue_status_summary", bg.queue_status_summary)
    self._blackboard:set("bg.sensor.queue_popup", bg.queue_popup)
    self._blackboard:set("bg.sensor.queue_popup_kind", bg.queue_popup_kind)
    self._blackboard:set("bg.sensor.queue_popup_source", bg.queue_popup_source)
    self._blackboard:set("bg.sensor.queue_popup_confidence", bg.queue_popup_confidence)
    self._blackboard:set("bg.sensor.queue_popup_seq", bg.queue_popup_seq)
    self._blackboard:set("bg.sensor.queue_popup_age_ms", bg.queue_popup_age_ms)
    self._blackboard:set("bg.sensor.queue_popup_slot_idx", bg.queue_popup_slot_idx)

    self._event_bus:publish("player:profile_refreshed", {
        player = player,
        target = target,
        position = position,
        health_pct = self._blackboard:get("player.health_pct", 0),
        mana_pct = self._blackboard:get("player.mana_pct", 0),
        is_moving = self._blackboard:get("player.is_moving", false),
        is_casting = self._blackboard:get("player.is_casting", false),
        is_channeling = self._blackboard:get("player.is_channeling", false),
    })
end

return SensorHub
