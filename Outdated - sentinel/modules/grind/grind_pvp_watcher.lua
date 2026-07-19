local ThreatTypes = require("modules/grind/threat_types")

local GrindPvPWatcher = {}
GrindPvPWatcher.__index = GrindPvPWatcher

local PVP_SCAN_INTERVAL_MS = 2000
local THREAT_GC_INTERVAL_MS = 60000
local PVP_DETECT_RADIUS = 60

---Scan for nearby enemy players and record threats.
---Extracted from SentinelGrind to isolate PvP scanning and threat recording.
function GrindPvPWatcher:new()
    return setmetatable({
        _last_scan_ms = 0,
        _last_threat_gc_ms = 0,
    }, self)
end

---Tick: scan for PvP threats and run threat map GC at throttled intervals.
---@param bb table Blackboard
---@param now_ms number Current time in milliseconds
---@param threat_map table ThreatMap instance
function GrindPvPWatcher:tick(bb, now_ms, threat_map)
    if not threat_map then return end

    -- Throttled PvP scan every PVP_SCAN_INTERVAL_MS
    if now_ms - self._last_scan_ms >= PVP_SCAN_INTERVAL_MS then
        self._last_scan_ms = now_ms
        self:_scan(bb, now_ms, threat_map)
    end

    -- Throttled threat map GC every THREAT_GC_INTERVAL_MS
    if now_ms - self._last_threat_gc_ms >= THREAT_GC_INTERVAL_MS then
        self._last_threat_gc_ms = now_ms
        threat_map:gc(now_ms)
    end
end

function GrindPvPWatcher:_scan(bb, now_ms, threat_map)
    if bb:get("module.grind.pvp_avoidance", true) ~= true then
        bb:set("module.grind.pvp_threat_nearby", false)
        return
    end

    local player = bb:get("player.object")
    if not player then
        bb:set("module.grind.pvp_threat_nearby", false)
        return
    end

    local player_pos = bb:get("player.position")
    if not player_pos then
        bb:set("module.grind.pvp_threat_nearby", false)
        return
    end

    local found = false
    if core and core.object_manager and core.object_manager.get_all_objects then
        local ok, objects = pcall(core.object_manager.get_all_objects)
        if ok and type(objects) == "table" then
            for _, obj in ipairs(objects) do
                local ok_p, is_p = pcall(obj.is_player, obj)
                if ok_p and is_p then
                    local ok_ga, ga = pcall(obj.get_guid, obj)
                    local ok_gb, gb = pcall(player.get_guid, player)
                    local is_self = ok_ga and ok_gb and tostring(ga) == tostring(gb)
                    if not is_self then
                        local ok_enemy, enemy = pcall(player.is_enemy_with, player, obj)
                        if ok_enemy and enemy then
                            local ok_alive, alive = pcall(obj.is_alive, obj)
                            if ok_alive and alive then
                                local ok_pos, pos = pcall(obj.get_position, obj)
                                if ok_pos and pos then
                                    local dx = (pos.x or 0) - (player_pos.x or 0)
                                    local dy = (pos.y or 0) - (player_pos.y or 0)
                                    local dz = (pos.z or 0) - (player_pos.z or 0)
                                    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                                    if dist <= PVP_DETECT_RADIUS then
                                        found = true
                                        threat_map:record(ThreatTypes.PVP_PLAYER, pos, nil, now_ms)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    bb:set("module.grind.pvp_threat_nearby", found)
end

return GrindPvPWatcher
