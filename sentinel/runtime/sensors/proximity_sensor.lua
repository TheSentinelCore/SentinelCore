local ProximitySensor = {}
ProximitySensor.__index = ProximitySensor

function ProximitySensor:new(blackboard)
    local o = setmetatable({}, ProximitySensor)
    o._blackboard = blackboard
    local ok_unit, unit_helper = pcall(require, "common/utility/unit_helper")
    o._unit_helper = ok_unit and unit_helper or nil
    o._frame_count = 0
    o._cached_enemy_count_10 = 0
    o._cached_enemy_count_30 = 0
    o._cached_ally_count_30 = 0
    return o
end

function ProximitySensor:_count_units(position, radius, ally)
    if not self._unit_helper or not position then return 0 end
    local fn_name = ally and "get_ally_list_around" or "get_enemy_list_around"
    if type(self._unit_helper[fn_name]) ~= "function" then return 0 end
    local ok, list = pcall(self._unit_helper[fn_name], self._unit_helper, position, radius, true, false)
    if ok and type(list) == "table" then return #list end
    return 0
end

function ProximitySensor:_get_enemy_counts(position)
    if not self._unit_helper or not position then return 0, 0 end
    if type(self._unit_helper.get_enemy_list_around) ~= "function" then return 0, 0 end
    local ok, list = pcall(self._unit_helper.get_enemy_list_around, self._unit_helper, position, 30, true, false)
    if not ok or type(list) ~= "table" then return 0, 0 end
    local count_30 = #list
    local count_10 = 0
    local px, py, pz = position.x or 0, position.y or 0, position.z or 0
    for _, unit in ipairs(list) do
        local ok_pos, upos = pcall(unit.get_position, unit)
        if ok_pos and type(upos) == "table" then
            local dx = (upos.x or 0) - px
            local dy = (upos.y or 0) - py
            local dz = (upos.z or 0) - pz
            if dx * dx + dy * dy + dz * dz <= 100 then
                count_10 = count_10 + 1
            end
        end
    end
    return count_10, count_30
end

function ProximitySensor:refresh(player, now_ms)
    local bb = self._blackboard
    local position = bb:get("player.position")

    -- Throttle unit counts to every 3 frames (~50ms at 60fps). Recompute on
    -- the FIRST pass (frame 1), not the third — `frame_count % 3 == 0` would
    -- make frames 1-2 publish the constructor's zeros after every load or
    -- reload, suppressing AoE and the outnumbered check for two frames
    -- (audit B9).
    self._frame_count = self._frame_count + 1
    if (self._frame_count - 1) % 3 == 0 then
        local count_10, count_30 = self:_get_enemy_counts(position)
        self._cached_enemy_count_10 = count_10
        self._cached_enemy_count_30 = count_30
        self._cached_ally_count_30 = self:_count_units(position, 30, true)
    end
    bb:set("combat.enemy_count_10yd", self._cached_enemy_count_10)
    bb:set("combat.enemy_count_30yd", self._cached_enemy_count_30)
    bb:set("combat.ally_count_30yd", self._cached_ally_count_30)
end

return ProximitySensor
