local Compat = require("shared/compat")
local num = Compat.num
local SystemSensor = require("runtime/sensors/system_sensor")
local PlayerSensor = require("runtime/sensors/player_sensor")
local DeathSensor = require("runtime/sensors/death_sensor")
local ProximitySensor = require("runtime/sensors/proximity_sensor")
local TransitionDetector = require("runtime/sensors/transition_detector")
local AuraSensor = require("runtime/sensors/aura_sensor")

local SensorHub = {}
SensorHub.__index = SensorHub

function SensorHub:new(blackboard, event_bus)
    local o = setmetatable({}, SensorHub)
    o._blackboard = blackboard
    o._event_bus = event_bus
    local ok_izi, izi = pcall(require, "common/izi_sdk")
    o._izi = ok_izi and izi or nil

    local ok_unit, unit_helper = pcall(require, "common/utility/unit_helper")
    o._unit_helper = ok_unit and unit_helper or nil

    o._system_sensor = SystemSensor:new(blackboard)
    o._player_sensor = PlayerSensor:new(blackboard, o._izi)
    o._transition_detector = TransitionDetector:new(blackboard, event_bus)
    o._death_sensor = DeathSensor:new(blackboard)
    o._proximity_sensor = ProximitySensor:new(blackboard)
    o._aura_sensor = AuraSensor:new(blackboard, event_bus, o._izi)

    return o
end

function SensorHub:refresh()
    local now_ms = num(core and core.game_time and core.game_time() or 0)

    -- 1. System clock (no player dependency)
    self._system_sensor:refresh(nil, now_ms)

    -- 2. Acquire player (no blackboard writes yet)
    local player = self._player_sensor:acquire_player()

    -- 3. Detect state transitions (reads PREVIOUS BB values + current player)
    --    Must run BEFORE player_sensor writes to detect actual transitions.
    self._transition_detector:refresh(player, now_ms, self._unit_helper)

    -- 4. Write player state to blackboard
    self._player_sensor:refresh(player, now_ms)

    -- 5. Death/corpse tracking
    self._death_sensor:refresh(player, now_ms)

    -- 6. Proximity counts (throttled every 3 frames)
    self._proximity_sensor:refresh(player, now_ms)

    -- 7. Aura/rotation seal detection + IZI callbacks
    self._aura_sensor:refresh(player, now_ms)

    -- Publish consolidated player snapshot for consumers
    local target = self._blackboard:get("player.target")
    local position = self._blackboard:get("player.position")
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

function SensorHub:shutdown()
    self._aura_sensor:shutdown()
end

return SensorHub
