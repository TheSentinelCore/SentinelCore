local TargetService = {}
TargetService.__index = TargetService

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

local function contains(list, value)
    if type(list) ~= "table" then
        return false
    end
    local wanted = tonumber(value) or 0
    for i = 1, #list do
        if tonumber(list[i]) == wanted then
            return true
        end
    end
    return false
end

---@class TargetService
function TargetService:new(bb, cfg, logger)
    local o = setmetatable({}, TargetService)
    o._bb = bb
    o._cfg = cfg or {}
    o._log = logger
    o._current = nil
    return o
end

function TargetService:_visible_objects()
    if core and core.object_manager and core.object_manager.get_visible_objects then
        local ok, objects = pcall(core.object_manager.get_visible_objects)
        if ok and type(objects) == "table" then
            return objects
        end
    end
    return {}
end

function TargetService:_is_valid_enemy(unit, player)
    if not unit or safe_method(unit, "is_valid") ~= true then
        return false
    end
    if safe_method(unit, "is_dead") == true then
        return false
    end
    if safe_method(unit, "is_ghost") == true then
        return false
    end
    if safe_method(unit, "is_unit") ~= true then
        return false
    end
    if safe_method(unit, "is_basic_object") == true then
        return false
    end
    if safe_method(player, "can_attack", unit) ~= true then
        return false
    end

    local npc_id = tonumber(safe_method(unit, "get_npc_id")) or 0
    local tcfg = self._cfg.targeting or {}
    if contains(tcfg.npc_blacklist, npc_id) then
        return false
    end
    if type(tcfg.npc_whitelist) == "table" and #tcfg.npc_whitelist > 0 and not contains(tcfg.npc_whitelist, npc_id) then
        return false
    end

    return true
end

---@return any|nil
function TargetService:acquire_target()
    local player = self._bb:get("player.object")
    local player_pos = self._bb:get("player.position")
    if not player or not player_pos then
        return nil
    end

    local objects = self:_visible_objects()
    local best = nil
    local best_dist = math.huge
    local scan_radius = tonumber(self._cfg.targeting and self._cfg.targeting.scan_radius) or 55.0
    local focus_pos = self._bb:get("route.target_focus_position")
    local focus_radius = tonumber(self._bb:get("route.target_focus_radius", scan_radius)) or scan_radius
    local enemy_count = 0

    for i = 1, #objects do
        local unit = objects[i]
        if self:_is_valid_enemy(unit, player) then
            local pos = safe_method(unit, "get_position")
            local d_player = distance(player_pos, pos)
            if d_player <= scan_radius then
                local d_focus = 0
                local in_focus = true
                if focus_pos then
                    d_focus = distance(focus_pos, pos)
                    if d_focus > focus_radius then
                        in_focus = false
                    end
                end

                if in_focus then
                    enemy_count = enemy_count + 1
                    local score = d_player
                    if focus_pos then
                        score = (d_focus * 0.8) + (d_player * 0.2)
                    end
                    if score < best_dist then
                        best = unit
                        best_dist = score
                    end
                end
            end
        end
    end

    self._bb:set("combat.enemy_count", enemy_count)
    self._current = best
    self._bb:set("combat.target", best)
    self._bb:set("combat.target_distance", best_dist)
    return best
end

function TargetService:update()
    local target = self._bb:get("combat.target")
    if target and safe_method(target, "is_valid") == true and safe_method(target, "is_dead") ~= true then
        local player_pos = self._bb:get("player.position")
        local target_pos = safe_method(target, "get_position")
        self._bb:set("combat.target_distance", distance(player_pos, target_pos))
        return
    end
    self:acquire_target()
end

return TargetService
