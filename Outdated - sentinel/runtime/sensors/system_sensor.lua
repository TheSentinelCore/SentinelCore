local Compat = require("shared/compat")
local num = Compat.num

local SystemSensor = {}
SystemSensor.__index = SystemSensor

function SystemSensor:new(blackboard)
    return setmetatable({ _blackboard = blackboard }, SystemSensor)
end

function SystemSensor:refresh(player, now_ms)
    local bb = self._blackboard
    bb:set("system.now_ms", now_ms)
    bb:set("system.delta_ms", math.floor(num(((core and core.delta_time and core.delta_time()) or 0) * 1000)))
    bb:set("system.ping_ms", num(core and core.get_ping and core.get_ping() or 0))
    bb:set("system.map_id", num(core and core.get_map_id and core.get_map_id() or 0))
    bb:set("system.map_name", tostring(core and core.get_map_name and core.get_map_name() or ""))
    bb:set("system.instance_id", num(core and core.get_instance_id and core.get_instance_id() or 0))
    bb:set("system.instance_name", tostring(core and core.get_instance_name and core.get_instance_name() or ""))
end

return SystemSensor
