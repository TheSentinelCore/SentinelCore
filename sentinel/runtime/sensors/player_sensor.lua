local Compat = require("shared/compat")
local safe_call = Compat.safe_call
local num = Compat.num

local PlayerSensor = {}
PlayerSensor.__index = PlayerSensor

function PlayerSensor:new(blackboard, izi)
    local o = setmetatable({}, PlayerSensor)
    o._blackboard = blackboard
    o._izi = izi
    local ok_unit, unit_helper = pcall(require, "common/utility/unit_helper")
    o._unit_helper = ok_unit and unit_helper or nil
    return o
end

function PlayerSensor:_unit_health_pct(unit)
    if not unit then return 1 end
    if self._unit_helper and type(self._unit_helper.get_health_percentage) == "function" then
        local ok, value = pcall(self._unit_helper.get_health_percentage, self._unit_helper, unit)
        if ok and type(value) == "number" then
            if value > 1 then value = value / 100 end
            return value
        end
    end
    local health = tonumber(safe_call(unit, "get_health") or 0) or 0
    local max_health = tonumber(safe_call(unit, "get_max_health") or 0) or 0
    if max_health <= 0 then return 1 end
    return health / max_health
end

function PlayerSensor:_unit_mana_pct(unit)
    if not unit then return 1 end
    local mana = tonumber(safe_call(unit, "get_power", 0) or 0) or 0
    local max_mana = tonumber(safe_call(unit, "get_max_power", 0) or 0) or 0
    if max_mana <= 0 then return 1 end
    return mana / max_mana
end

---Acquire the local player object.
---@return table|nil player
function PlayerSensor:acquire_player()
    local player = nil
    if self._izi and type(self._izi.get_player) == "function" then
        local ok, local_player = pcall(self._izi.get_player, self._izi)
        if ok then player = local_player end
    end
    if not player and core and core.object_manager and type(core.object_manager.get_local_player) == "function" then
        local ok, local_player = pcall(core.object_manager.get_local_player)
        if ok then player = local_player end
    end
    return player
end

function PlayerSensor:refresh(player, now_ms)
    local bb = self._blackboard
    bb:set("player.object", player)

    local target = safe_call(player, "get_target")
    local position = safe_call(player, "get_position")
    bb:set("player.target", target)
    -- MEASURED LIVE (first in-game run, 2026-07-26): get_position() returns a vec3 CLASS
    -- instance — plain x/y/z number fields carrying the injector's ~35-method vector metatable
    -- (dist_to, lerp, __add, ...). Offline mocks returned plain tables, so the purity guard's
    -- refusal ("the table carries a metatable, and `pairs` cannot see through `__index`") fired
    -- for the first time against the real SDK, and `player.position` was never written: every
    -- consumer — distance checks, navigation, the death sensor — read nil for the whole session.
    -- The blackboard holds VALUES (ADR 08 §2.7), so copy the three numbers out and drop the
    -- metatable rather than ledgering a methods-object as if it were a handle.
    if type(position) == "table" then
        local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z)
        position = (x and y) and { x = x, y = y, z = z } or nil
    end
    bb:set("player.position", position)
    bb:set("player.health_pct", player and self:_unit_health_pct(player) or 1)
    bb:set("player.mana_pct", player and self:_unit_mana_pct(player) or 1)
    bb:set("player.in_combat", safe_call(player, "is_in_combat") == true)
    bb:set("player.is_dead", safe_call(player, "is_dead") == true)
    bb:set("player.is_ghost", safe_call(player, "is_ghost") == true)
    bb:set("player.is_mounted", safe_call(player, "is_mounted") == true)
    local outdoors = safe_call(player, "is_outdoors")
    if outdoors == nil then outdoors = true end
    bb:set("player.is_outdoors", outdoors == true)
    bb:set("player.is_casting", safe_call(player, "is_casting_spell") == true)
    bb:set("player.is_channeling", safe_call(player, "is_channelling_spell") == true)
    bb:set("player.is_moving", safe_call(player, "is_moving") == true)
    bb:set("player.is_auto_attacking", safe_call(player, "is_auto_attacking") == true)
    bb:set("player.attack_speed_s", tonumber(safe_call(player, "get_attack_speed") or 0) or 0)

    local player_level = 0
    if player then
        local ok_lv, lv = pcall(player.get_level, player)
        if ok_lv and type(lv) == "number" then player_level = lv end
    end
    bb:set("player.level", player_level)

    -- Expose health/mana helpers for transition_detector
    self._last_health_pct = bb:get("player.health_pct", 1)
end

return PlayerSensor
