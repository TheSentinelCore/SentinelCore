-- FlightMasterInteractor.lua — Navigate to flight master, take taxi, detect landing.

local helpers = require("lib/helpers")

---@class FlightMasterInteractor
local FlightMasterInteractor = {}
FlightMasterInteractor.__index = FlightMasterInteractor

local LAND_DETECT_RANGE = 10.0

---@param duo_nav   table  DuoNav
---@param blackboard table Blackboard
---@param profile   table
---@return FlightMasterInteractor
function FlightMasterInteractor:new(duo_nav, blackboard, profile)
    return setmetatable({
        _nav          = duo_nav,
        _bb           = blackboard,
        _profile      = profile,
        _state        = "idle",  -- idle | traveling | interacting | interacting_wait | flying | done | failed
        _start_ms     = 0,
        _interact_ms  = 0,
    }, FlightMasterInteractor)
end

--- Start the flight process. Call poll() each frame.
---@param route_key string  key in profile.vendor_route for this leg
function FlightMasterInteractor:start(route_key)
    if self._state ~= "idle" then return end
    self._state    = "traveling"
    self._start_ms = helpers.game_time_ms()
    self._route_key = route_key or "return_flight"

    local route = self._profile and self._profile.vendor_route
    local fm_pos = route and route.flight_master_position
    if fm_pos then
        self._nav:move_to(fm_pos)
        helpers.log("[Flight] navigating to flight master")
    else
        helpers.log_warn("[Flight] no flight_master_position in profile")
        self._state = "failed"
    end
end

local function find_flight_master(npc_id)
    if not npc_id then return nil end
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return nil end
    for _, obj in ipairs(objects) do
        local ok_id, oid = pcall(obj.get_npc_id, obj)
        if ok_id and oid == npc_id then return obj end
    end
    return nil
end

--- Poll state machine. Returns current state string.
function FlightMasterInteractor:poll()
    local gt    = helpers.game_time_ms()
    local route = self._profile and self._profile.vendor_route

    if self._state == "traveling" then
        if self._nav:is_arrived(5.0) then
            self._state = "interacting"
            self._nav:stop("at_flight_master")
            helpers.log("[Flight] arrived at flight master")
        end
        if gt - self._start_ms > 90000 then
            self._state = "failed"
            helpers.log_err("[Flight] travel timeout")
        end
    end

    if self._state == "interacting" then
        local fm_npc_id = route and route.flight_master_npc_id
        if not fm_npc_id or fm_npc_id == 0 then
            helpers.log_warn("[Flight] flight_master_npc_id not configured — failing")
            self._state = "failed"
        else
            local npc = find_flight_master(fm_npc_id)
            if npc then
                pcall(core.input.interact_with_object, npc)
                -- Transition to wait state — the taxi window needs a frame to open
                -- before select_taxi_route can work.
                self._state      = "interacting_wait"
                self._interact_ms = gt
                helpers.log("[Flight] interacted with flight master — waiting for taxi window")
            else
                if gt - self._start_ms > 10000 then
                    helpers.log_warn("[Flight] flight master NPC not found")
                    self._state = "failed"
                end
            end
        end
    end

    if self._state == "interacting_wait" then
        if gt - self._interact_ms >= 500 then
            local dest_name = route and route.taxi_dest_name
            if dest_name then
                pcall(core.input.select_taxi_route, dest_name)
            end
            self._state    = "flying"
            self._start_ms = gt
            helpers.log("[Flight] taxi taken → " .. tostring(dest_name))
        end
    end

    if self._state == "flying" then
        local dest_map   = route and route.flight_dest_map_id
        local dest_pos   = route and route.flight_dest_position
        local timeout_ms = (route and route.flight_arrive_detect_timeout_ms) or 180000

        local ok_map, map_id = pcall(core.get_map_id)
        local at_dest_map = ok_map and dest_map and (map_id == dest_map)

        local at_dest_pos = false
        if at_dest_map and dest_pos then
            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if ok_pl and player then
                local ok_pos, pos = pcall(player.get_position, player)
                if ok_pos and pos then
                    local dx = (pos.x or 0) - (dest_pos.x or 0)
                    local dy = (pos.y or 0) - (dest_pos.y or 0)
                    local dz = (pos.z or 0) - (dest_pos.z or 0)
                    at_dest_pos = math.sqrt(dx*dx + dy*dy + dz*dz) <= LAND_DETECT_RANGE
                end
            end
        end

        if at_dest_pos or gt - self._start_ms >= timeout_ms then
            self._state = "done"
            helpers.log("[Flight] landed at destination")
        end
    end

    return self._state
end

---@return boolean
function FlightMasterInteractor:is_done()
    return self._state == "done"
end

function FlightMasterInteractor:reset()
    self._state       = "idle"
    self._start_ms    = 0
    self._interact_ms = 0
end

return FlightMasterInteractor
