-- Sensors.lua
-- Polls player state each frame and writes to Blackboard.
-- Keeps all player-related Blackboard keys up-to-date for BT conditions.

---@class Sensors
---@field private _bb table Blackboard instance
local Sensors = {}
Sensors.__index = Sensors

---Create a new Sensors instance.
---@param blackboard table Blackboard instance
---@return Sensors
function Sensors:new(blackboard)
    local o = setmetatable({}, Sensors)
    o._bb = blackboard
    return o
end

---Poll player state and write to Blackboard.
---Call once per frame in the update loop.
function Sensors:update()
    local bb = self._bb

    -- Update time for BT Throttle/Cooldown nodes
    bb:set("_time", core.time())
    bb:set("_tick", bb:get("_tick", 0) + 1)

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        -- Avoid stale sensor state when player is not available (loading screens, relog).
        bb:clear("player.position")
        bb:set("player.speed", 0)
        bb:set("player.is_casting", false)
        bb:set("player.is_mounted", false)
        return
    end

    bb:set("player.position", player:get_position())
    bb:set("player.speed", player:get_movement_speed() or 0)
    bb:set("player.is_casting",
        player:is_casting_spell() or player:is_channelling_spell() or false)
    bb:set("player.is_mounted", player:is_mounted() or false)
end

return Sensors
