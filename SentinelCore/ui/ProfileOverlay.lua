-- SentinelCore/ui/ProfileOverlay.lua
--
-- 3D world overlay for grinding profile visualization.
-- Draws hotspot circles, route lines, vendor/blackspot markers.
-- Registered via core.register_on_render_callback.

local color = require("common/color")

local ProfileOverlay = {}
ProfileOverlay.__index = ProfileOverlay

local COLORS = {
    hotspot           = color.new(48, 209, 88, 180),
    hotspot_selected  = color.new(255, 255, 255, 220),
    route_line        = color.new(50, 173, 230, 150),
    loop_line         = color.new(50, 173, 230, 80),
    blackspot         = color.new(255, 69, 58, 150),
    vendor            = color.new(255, 159, 10, 180),
    recording_pulse   = color.new(48, 209, 88, 120),
}

function ProfileOverlay:new(blackboard)
    local o = setmetatable({}, self)
    o._bb = blackboard
    o._enabled = true
    o._selected_index = 0
    o._pulse_phase = 0

    core.register_on_render_callback(function()
        if o._enabled then
            o:_render()
        end
    end)

    return o
end

function ProfileOverlay:set_selected_index(idx)
    self._selected_index = idx or 0
end

function ProfileOverlay:set_enabled(enabled)
    self._enabled = enabled
end

function ProfileOverlay:_render()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end

    local profile = nil
    local recorder_state = self._bb:get("recorder.state")

    if recorder_state == "recording" then
        profile = self._bb:get("recorder.working_profile")
    else
        profile = self._bb:get("profile.active")
    end

    if not profile then return end

    local player_pos = player:get_position()
    self._pulse_phase = self._pulse_phase + 0.05
    if self._pulse_phase > 6.28 then self._pulse_phase = 0 end

    self:_render_hotspots(profile)
    self:_render_route_lines(profile)
    self:_render_blackspots(profile)
    self:_render_vendors(profile)

    if recorder_state == "recording" then
        self:_render_recording_indicator(player_pos)
    end
end

function ProfileOverlay:_render_hotspots(profile)
    local hotspots = profile.hotspots
    if not hotspots then return end

    for i = 1, #hotspots do
        local hs = hotspots[i]
        local pos = { x = hs.x, y = hs.y, z = hs.z }
        local radius = hs.radius or 40
        local is_selected = (i == self._selected_index)
        local c = is_selected and COLORS.hotspot_selected or COLORS.hotspot
        local thickness = is_selected and 3 or 2

        core.graphics.circle_3d(pos, radius, c, thickness, 2.5)
        core.graphics.circle_3d(pos, 1.0, c, 2, 2.5)
    end
end

function ProfileOverlay:_render_route_lines(profile)
    local hotspots = profile.hotspots
    if not hotspots or #hotspots < 2 then return end

    for i = 1, #hotspots - 1 do
        local a = hotspots[i]
        local b = hotspots[i + 1]
        core.graphics.line_3d(
            { x = a.x, y = a.y, z = a.z },
            { x = b.x, y = b.y, z = b.z },
            COLORS.route_line, 2, 2.0
        )
    end

    if profile.loop and #hotspots >= 2 then
        local first = hotspots[1]
        local last = hotspots[#hotspots]
        core.graphics.line_3d(
            { x = last.x, y = last.y, z = last.z },
            { x = first.x, y = first.y, z = first.z },
            COLORS.loop_line, 1, 2.0
        )
    end
end

function ProfileOverlay:_render_blackspots(profile)
    local blackspots = profile.blackspots
    if not blackspots then return end

    for i = 1, #blackspots do
        local bs = blackspots[i]
        core.graphics.circle_3d(
            { x = bs.x, y = bs.y, z = bs.z },
            bs.radius or 20, COLORS.blackspot, 2, 2.0
        )
    end
end

function ProfileOverlay:_render_vendors(profile)
    local vendors = profile.vendors
    if not vendors then return end

    for i = 1, #vendors do
        local v = vendors[i]
        core.graphics.circle_3d(
            { x = v.x, y = v.y, z = v.z },
            3, COLORS.vendor, 2, 2.5
        )
    end
end

function ProfileOverlay:_render_recording_indicator(player_pos)
    local pulse = 2.0 + math.sin(self._pulse_phase) * 1.0
    core.graphics.circle_3d(player_pos, pulse, COLORS.recording_pulse, 2, 3.0)
end

return ProfileOverlay
