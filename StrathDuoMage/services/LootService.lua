local LootService = {}
LootService.__index = LootService

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

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@class LootService
function LootService:new(bb, cfg, logger)
    local o = setmetatable({}, LootService)
    o._bb = bb
    o._cfg = cfg or {}
    o._log = logger
    o._last_attempt = 0
    return o
end

function LootService:_interact_target(target)
    if not core or not core.input then
        return false
    end

    if type(core.input.set_target) == "function" then
        pcall(core.input.set_target, target)
    end

    if type(core.input.interact_target) == "function" then
        local ok = pcall(core.input.interact_target, target)
        return ok == true
    end

    if type(core.input.interact_unit) == "function" then
        local ok = pcall(core.input.interact_unit, target)
        return ok == true
    end

    return false
end

---@param now number
function LootService:update(now)
    if self._cfg.farm and self._cfg.farm.loot_enabled == false then
        return
    end

    if self._bb:get("player.in_combat", false) then
        return
    end

    if (now - self._last_attempt) < 0.25 then
        return
    end

    local target = self._bb:get("combat.target")
    if not target then
        return
    end

    if safe_method(target, "is_dead") ~= true then
        return
    end

    local has_loot = safe_method(target, "has_loot") == true
        or safe_method(target, "can_be_looted") == true
    if not has_loot then
        self._bb:clear("combat.target")
        return
    end

    local player_pos = self._bb:get("player.position")
    local target_pos = safe_method(target, "get_position")
    if distance(player_pos, target_pos) > 5.0 then
        return
    end

    if self:_interact_target(target) then
        self._last_attempt = now
        self._bb:clear("combat.target")
    end
end

return LootService
