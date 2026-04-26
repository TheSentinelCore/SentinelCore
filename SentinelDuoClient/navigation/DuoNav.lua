-- DuoNav.lua — Thin navigation wrapper with stuck detection and jitter recovery.
-- Per design doc §8.5.

local helpers = require("lib/helpers")

---@class DuoNav
---@field _adapter  table  NavAdapter
---@field _bb       table  Blackboard
---@field _last_target  table|nil  vec3
local DuoNav = {}
DuoNav.__index = DuoNav

local STUCK_ESCALATION_THRESHOLD = 3

---@param nav_adapter table
---@param blackboard  table
---@return DuoNav
function DuoNav:new(nav_adapter, blackboard)
    return setmetatable({
        _adapter     = nav_adapter,
        _bb          = blackboard,
        _last_target = nil,
    }, DuoNav)
end

--- Begin movement to a single target position.
---@param target_vec3 table  {x,y,z}
function DuoNav:move_to(target_vec3)
    self._last_target = target_vec3
    self._bb:set("duo.nav_stuck_count", 0)
    self._adapter:move_to(target_vec3)
end

--- Follow a waypoint path.
---@param waypoints table  array of {x,y,z}
function DuoNav:follow_path(waypoints)
    if type(waypoints) == "table" and #waypoints > 0 then
        self._last_target = waypoints[#waypoints]
    end
    self._bb:set("duo.nav_stuck_count", 0)
    self._adapter:follow_path(waypoints)
end

--- Stop navigation.
---@param reason string|nil
function DuoNav:stop(reason)
    self._adapter:stop(reason)
end

--- Poll navigation and handle stuck recovery with lateral jitter.
--- Call every frame. Publishes "duo:stuck_escalation" after 3 consecutive stucks.
function DuoNav:poll()
    local state, progress = self._adapter:poll()

    if state == "stuck" then
        local count = (self._bb:get("duo.nav_stuck_count", 0)) + 1
        self._bb:set("duo.nav_stuck_count", count)

        helpers.log_warn("[DuoNav] stuck count=" .. count)

        if count >= STUCK_ESCALATION_THRESHOLD then
            helpers.log_warn("[DuoNav] stuck escalation after " .. count .. " attempts")
            self._bb:set("duo.nav_stuck_escalated", true)
        end

        -- Retry with lateral jitter if we have a target
        if self._last_target then
            local jittered = helpers.apply_lateral_jitter(self._last_target, 2.0)
            self._adapter:move_to(jittered)
        end
    elseif state == "moving" or state == "idle" then
        -- Clear stuck counter on successful movement
        self._bb:set("duo.nav_stuck_count", 0)
        self._bb:set("duo.nav_stuck_escalated", false)
    end

    return state, progress
end

--- Check if the player has arrived within threshold of the last target.
---@param threshold_yards number|nil  defaults to 3.0
---@return boolean
function DuoNav:is_arrived(threshold_yards)
    local thresh = threshold_yards or 3.0
    if not self._last_target then return false end

    local ok, player = pcall(core.object_manager.get_local_player)
    if not ok or not player then return false end

    local ok_pos, pos = pcall(player.get_position, player)
    if not ok_pos or not pos then return false end

    local dx = (pos.x or 0) - (self._last_target.x or 0)
    local dy = (pos.y or 0) - (self._last_target.y or 0)
    local dz = (pos.z or 0) - (self._last_target.z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz) <= thresh
end

---@return boolean
function DuoNav:is_active()
    return self._adapter:is_active()
end

---@return string
function DuoNav:get_state()
    return self._adapter:get_state()
end

return DuoNav
