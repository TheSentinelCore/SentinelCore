local SensorService = {}
SensorService.__index = SensorService

local function safe_method(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(obj[method], obj, ...)
    if ok then
        return value
    end
    return nil
end

local function resolve_player()
    if core and core.object_manager and core.object_manager.get_local_player then
        return core.object_manager.get_local_player()
    end
    return nil
end

local function resolve_money(player)
    local methods = {
        "get_money",
        "get_coinage",
        "get_copper",
        "get_gold_amount",
    }
    for i = 1, #methods do
        local value = tonumber(safe_method(player, methods[i]))
        if value and value >= 0 then
            return value
        end
    end
    return nil
end

---@class SensorService
function SensorService:new(bb, cfg, logger)
    local o = setmetatable({}, SensorService)
    o._bb = bb
    o._cfg = cfg or {}
    o._log = logger
    return o
end

function SensorService:update(now)
    local player = resolve_player()
    local valid = player and safe_method(player, "is_valid") ~= false

    self._bb:set("player.object", player)
    self._bb:set("player.valid", valid == true)

    if not valid then
        self._bb:set("player.in_combat", false)
        self._bb:set("player.is_dead", false)
        return
    end

    local pos = safe_method(player, "get_position")
    self._bb:set("player.position", pos)

    local hp = tonumber(safe_method(player, "get_health")) or 0
    local hp_max = tonumber(safe_method(player, "get_max_health")) or math.max(1, hp)
    local mana = tonumber(safe_method(player, "get_power", 0)) or tonumber(safe_method(player, "get_mana")) or 0
    local mana_max = tonumber(safe_method(player, "get_max_power", 0)) or tonumber(safe_method(player, "get_max_mana")) or math.max(1, mana)

    self._bb:set("player.health", hp)
    self._bb:set("player.max_health", hp_max)
    self._bb:set("player.health_pct", hp_max > 0 and (hp / hp_max) or 0)
    self._bb:set("player.mana", mana)
    self._bb:set("player.max_mana", mana_max)
    self._bb:set("player.mana_pct", mana_max > 0 and (mana / mana_max) or 0)

    self._bb:set("player.level", tonumber(safe_method(player, "get_level")) or 0)
    self._bb:set("player.guid", tostring(safe_method(player, "get_guid") or ""))
    self._bb:set("player.is_dead", safe_method(player, "is_dead") == true)
    self._bb:set("player.in_combat", safe_method(player, "is_in_combat") == true)
    self._bb:set("player.is_casting", safe_method(player, "is_casting_spell") == true)
    self._bb:set("player.is_moving", safe_method(player, "is_moving") == true)

    local money = resolve_money(player)
    if money ~= nil then
        self._bb:set("player.money_copper", money)
    end
end

return SensorService
