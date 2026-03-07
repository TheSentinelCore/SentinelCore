local color = require("common/color")

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local Z_OFFSET = 2.0
local Z_TEXT = 3.0
local CULL_ALL = 500
local CULL_TEXT = 100
local CULL_UNITS = 80

-- ---------------------------------------------------------------------------
-- Local helpers
-- ---------------------------------------------------------------------------

---2D distance between two vec3-like tables (ignores z).
---@param a table {x=number, y=number, z=number}
---@param b table {x=number, y=number, z=number}
---@return number
local function dist_2d(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

---Create a plain {x,y,z} table.
---@param x number
---@param y number
---@param z number
---@return table
local function make_vec3(x, y, z)
    return { x = x, y = y, z = z }
end

---Check whether a unit matches an NpcRef entry.
---Tries npc_id first (if nonzero), falls back to name.
---@param unit userdata Game object
---@param ref table NpcRef – may have .npc_id and/or .name
---@return boolean
local function unit_matches_npc_ref(unit, ref)
    if type(ref) ~= "table" then return false end

    -- Try npc_id match
    if ref.npc_id then
        local ok, npc_id = pcall(unit.get_npc_id, unit)
        if ok and npc_id and npc_id ~= 0 and npc_id == ref.npc_id then
            return true
        end
    end

    -- Fallback to name match
    if ref.name then
        local ok, name = pcall(unit.get_name, unit)
        if ok and name and name == ref.name then
            return true
        end
    end

    return false
end

---Check if a unit matches any NpcRef in a list.
---@param unit userdata
---@param list table[] Array of NpcRef
---@return boolean
local function unit_in_list(unit, list)
    if type(list) ~= "table" then return false end
    for _, ref in ipairs(list) do
        if unit_matches_npc_ref(unit, ref) then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- ProfileVisualizer
-- ---------------------------------------------------------------------------

local ProfileVisualizer = {}
ProfileVisualizer.__index = ProfileVisualizer

---Create a new ProfileVisualizer.
---@param blackboard table Blackboard instance
---@param profile_manager table ProfileManager instance
---@return table ProfileVisualizer
function ProfileVisualizer:new(blackboard, profile_manager)
    return setmetatable({
        _blackboard = blackboard,
        _profile_manager = profile_manager,
        _shutdown = false,
        _colors = nil,
    }, self)
end

---Pre-allocate colors and register the render callback.
function ProfileVisualizer:initialize()
    self._colors = {
        -- Current hotspot
        current_fill    = color.cyan(30),
        current_outline = color.cyan(200),
        current_text    = color.cyan(255),

        -- Other hotspots
        hotspot_fill    = color.green(20),
        hotspot_outline = color.green(140),
        hotspot_text    = color.green(180),

        -- Route
        route_line      = color.green(100),
        route_arrow     = color.green_pale(160),

        -- Blackspots
        blackspot_fill    = color.red(35),
        blackspot_outline = color.red(120),

        -- Vendors
        vendor_repair = color.gold(200),
        vendor_repair_text = color.gold(220),
        vendor_food   = color.blue_pale(200),
        vendor_food_text = color.blue_pale(220),

        -- Unit markers
        unit_whitelist = color.green(160),
        unit_blacklist = color.red(160),
    }

    local self_ref = self
    core.register_on_render_callback(function()
        self_ref:_on_render()
    end)
end

---Set the shutdown flag. The render callback will early-out.
function ProfileVisualizer:shutdown()
    self._shutdown = true
end

-- ---------------------------------------------------------------------------
-- Render entry point
-- ---------------------------------------------------------------------------

---Per-frame render callback. Checks enabled state, gathers context, draws layers.
function ProfileVisualizer:_on_render()
    if self._shutdown then return end

    -- Check overlay toggle
    local ok_bb, show = pcall(self._blackboard.get, self._blackboard, "module.grind.show_overlay")
    if not ok_bb or not show then return end

    -- Get player position
    local ok_p, player = pcall(core.object_manager.get_local_player)
    if not ok_p or not player then return end

    local ok_pos, player_pos = pcall(player.get_position, player)
    if not ok_pos or not player_pos then return end

    -- Get profile
    local ok_loaded, loaded = pcall(self._profile_manager.is_profile_loaded, self._profile_manager)
    if not ok_loaded or not loaded then return end

    local ok_prof, profile = pcall(self._profile_manager.get_active_profile, self._profile_manager)
    if not ok_prof or not profile then return end

    -- Current hotspot index
    local ok_idx, current_index = pcall(self._blackboard.get, self._blackboard, "module.grind.current_hotspot_index")
    if not ok_idx or not current_index then current_index = 1 end

    -- Draw layers
    self:_draw_ground_zones(profile, current_index, player_pos)
    self:_draw_route(profile, player_pos)
    self:_draw_outlines(profile, current_index, player_pos)
    self:_draw_unit_markers(profile, current_index, player_pos)
    self:_draw_labels(profile, current_index, player_pos)
end

-- ---------------------------------------------------------------------------
-- Layer 1 — Ground zones (filled circles)
-- ---------------------------------------------------------------------------

function ProfileVisualizer:_draw_ground_zones(profile, current_index, player_pos)
    local colors = self._colors

    -- Hotspots
    if profile.hotspots then
        for i, hs in ipairs(profile.hotspots) do
            local center = make_vec3(hs.x, hs.y, hs.z + Z_OFFSET)
            if dist_2d(player_pos, center) <= CULL_ALL then
                local fill = (i == current_index) and colors.current_fill or colors.hotspot_fill
                pcall(core.graphics.circle_3d_filled, center, hs.radius or 40, fill)
            end
        end
    end

    -- Blackspots
    if profile.blackspots then
        for _, bs in ipairs(profile.blackspots) do
            local center = make_vec3(bs.x, bs.y, bs.z + Z_OFFSET)
            if dist_2d(player_pos, center) <= CULL_ALL then
                pcall(core.graphics.circle_3d_filled, center, bs.radius or 20, colors.blackspot_fill)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layer 2 — Route lines with direction arrows
-- ---------------------------------------------------------------------------

function ProfileVisualizer:_draw_route(profile, player_pos)
    if not profile.hotspots or #profile.hotspots < 2 then return end

    local colors = self._colors
    local hotspots = profile.hotspots
    local count = #hotspots

    -- Determine segment count
    local loop = profile.options and profile.options.loop
    local segments = loop and count or (count - 1)

    for seg = 1, segments do
        local from = hotspots[seg]
        local to_idx = (seg % count) + 1
        local to = hotspots[to_idx]

        local start_pos = make_vec3(from.x, from.y, from.z + Z_OFFSET)
        local end_pos   = make_vec3(to.x,   to.y,   to.z   + Z_OFFSET)

        -- Cull: skip if both endpoints far
        if dist_2d(player_pos, start_pos) <= CULL_ALL or dist_2d(player_pos, end_pos) <= CULL_ALL then
            -- Line
            pcall(core.graphics.line_3d, start_pos, end_pos, colors.route_line, 1.5, 3.0)

            -- Direction arrow at midpoint
            local mid = make_vec3(
                (start_pos.x + end_pos.x) * 0.5,
                (start_pos.y + end_pos.y) * 0.5,
                (start_pos.z + end_pos.z) * 0.5
            )

            local dx = end_pos.x - start_pos.x
            local dy = end_pos.y - start_pos.y
            local len = math.sqrt(dx * dx + dy * dy)

            if len > 0.001 then
                local dir_x = dx / len
                local dir_y = dy / len
                -- Perpendicular (90 deg rotation in 2D)
                local perp_x = -dir_y
                local perp_y = dir_x

                local tip   = make_vec3(mid.x + dir_x * 1.5,  mid.y + dir_y * 1.5,  mid.z)
                local left  = make_vec3(mid.x - dir_x * 1.5 + perp_x * 1.0, mid.y - dir_y * 1.5 + perp_y * 1.0, mid.z)
                local right = make_vec3(mid.x - dir_x * 1.5 - perp_x * 1.0, mid.y - dir_y * 1.5 - perp_y * 1.0, mid.z)

                pcall(core.graphics.triangle_3d_filled, tip, left, right, colors.route_arrow)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layer 3 — Outlines
-- ---------------------------------------------------------------------------

function ProfileVisualizer:_draw_outlines(profile, current_index, player_pos)
    local colors = self._colors

    -- Hotspot outlines
    if profile.hotspots then
        for i, hs in ipairs(profile.hotspots) do
            local center = make_vec3(hs.x, hs.y, hs.z + Z_OFFSET)
            if dist_2d(player_pos, center) <= CULL_ALL then
                local is_current = (i == current_index)
                local outline = is_current and colors.current_outline or colors.hotspot_outline
                local thickness = is_current and 2 or 1
                pcall(core.graphics.circle_3d, center, hs.radius or 40, outline, thickness)
            end
        end
    end

    -- Blackspot outlines
    if profile.blackspots then
        for _, bs in ipairs(profile.blackspots) do
            local center = make_vec3(bs.x, bs.y, bs.z + Z_OFFSET)
            if dist_2d(player_pos, center) <= CULL_ALL then
                pcall(core.graphics.circle_3d, center, bs.radius or 20, colors.blackspot_outline, 1)
            end
        end
    end

    -- Vendor markers
    if profile.vendors then
        for _, vendor in ipairs(profile.vendors) do
            local center = make_vec3(vendor.x, vendor.y, vendor.z + Z_OFFSET)
            if dist_2d(player_pos, center) <= CULL_ALL then
                local has_food = false
                if vendor.services then
                    for _, svc in ipairs(vendor.services) do
                        if svc == "food" then
                            has_food = true
                            break
                        end
                    end
                end
                local vendor_color = has_food and colors.vendor_food or colors.vendor_repair
                pcall(core.graphics.circle_3d, center, 2, vendor_color, 2)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layer 4 — Live unit markers
-- ---------------------------------------------------------------------------

function ProfileVisualizer:_draw_unit_markers(profile, current_index, player_pos)
    if not profile.hotspots then return end

    local hotspot = profile.hotspots[current_index]
    if not hotspot then return end

    -- Check if player is close enough to the current hotspot
    local hs_center = make_vec3(hotspot.x, hotspot.y, hotspot.z)
    if dist_2d(player_pos, hs_center) > (hotspot.radius or 40) + CULL_UNITS then
        return
    end

    -- Get merged filters
    local ok_filt, filters = pcall(self._profile_manager.get_merged_filters, self._profile_manager, hotspot)
    if not ok_filt or not filters then return end

    local whitelist = filters.npc_whitelist
    local blacklist = filters.npc_blacklist

    -- Skip if no lists defined
    local has_whitelist = type(whitelist) == "table" and #whitelist > 0
    local has_blacklist = type(blacklist) == "table" and #blacklist > 0
    if not has_whitelist and not has_blacklist then return end

    local colors = self._colors

    -- Scan visible objects
    local ok_objs, objects = pcall(core.object_manager.get_visible_objects)
    if not ok_objs or not objects then return end

    for _, obj in ipairs(objects) do
        -- Filter to units that are not players
        local ok_unit, is_unit = pcall(obj.is_unit, obj)
        if ok_unit and is_unit then
            local ok_plr, is_player = pcall(obj.is_player, obj)
            if ok_plr and not is_player then
                local ok_upos, unit_pos = pcall(obj.get_position, obj)
                if ok_upos and unit_pos then
                    local ring_pos = make_vec3(unit_pos.x, unit_pos.y, unit_pos.z + Z_OFFSET)

                    if has_whitelist and unit_in_list(obj, whitelist) then
                        pcall(core.graphics.circle_3d, ring_pos, 1.5, colors.unit_whitelist, 2)
                    elseif has_blacklist and unit_in_list(obj, blacklist) then
                        pcall(core.graphics.circle_3d, ring_pos, 1.5, colors.unit_blacklist, 2)
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layer 5 — Text labels
-- ---------------------------------------------------------------------------

function ProfileVisualizer:_draw_labels(profile, current_index, player_pos)
    local colors = self._colors

    -- Hotspot labels
    if profile.hotspots then
        for i, hs in ipairs(profile.hotspots) do
            local center = make_vec3(hs.x, hs.y, hs.z + Z_TEXT)
            if dist_2d(player_pos, center) <= CULL_TEXT then
                local is_current = (i == current_index)
                local label = "[" .. i .. "] " .. (hs.label or hs.id or "")
                local font_size = is_current and 16 or 12
                local text_color = is_current and colors.current_text or colors.hotspot_text
                pcall(core.graphics.text_3d, label, center, font_size, text_color, true)
            end
        end
    end

    -- Vendor labels
    if profile.vendors then
        for _, vendor in ipairs(profile.vendors) do
            local center = make_vec3(vendor.x, vendor.y, vendor.z + Z_TEXT)
            if dist_2d(player_pos, center) <= CULL_TEXT then
                local has_food = false
                if vendor.services then
                    for _, svc in ipairs(vendor.services) do
                        if svc == "food" then
                            has_food = true
                            break
                        end
                    end
                end
                local text_color = has_food and colors.vendor_food_text or colors.vendor_repair_text
                pcall(core.graphics.text_3d, vendor.name or "", center, 11, text_color, true)
            end
        end
    end
end

return ProfileVisualizer
