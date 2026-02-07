
--------------------------------------------------------------------------------
-- Syntax / IntelliSense helper for: common/utility/coords_helper
--
-- Usage:
--   ---@type coords_helper
--   local coords = require("common/utility/coords_helper")
--   local world_pos = coords:get_cursor_world_pos()
--
-- Warning: Access methods with ":", not "."
--------------------------------------------------------------------------------

---Coords Helper - Converts 2D map coordinates to 3D world positions.
---@class coords_helper
---@field public get_cursor_world_pos fun(self: coords_helper, extra_height?: number): vec3|nil, string|nil Gets 3D world pos from current cursor on minimap
---@field public map_to_world fun(self: coords_helper, map_id: number, map_pos: vec2, extra_height?: number): vec3|nil, string|nil Converts map pos to world pos
---@field public is_valid_map_coords fun(self: coords_helper, cursor: vec2): boolean Checks if coords are within valid map bounds (rejects > 0.99)
---@field public get_current_map_id fun(self: coords_helper): number|nil Gets current minimap map ID
---@field public get_cursor_normalized fun(self: coords_helper): vec2|nil Gets normalized cursor position
---@field public is_cursor_on_minimap fun(self: coords_helper): boolean Checks if cursor is on minimap
---@field public get_terrain_height fun(self: coords_helper, x: number, y: number): number Gets terrain height at position
---@field public to_3d fun(self: coords_helper, map_pos: vec2, extra_height?: number): vec3 Legacy: converts map pos to world pos

--========================
-- extra_height Parameter
--========================
-- The extra_height parameter controls WHERE the terrain raycast starts.
-- It's an OFFSET from your current player Z position.
--
-- How it works:
--   raycast_start_z = player.z + extra_height
--   terrain_z = first solid ground found below raycast_start_z
--
-- Values:
--   nil or 0  -> Default +4, safe margin to avoid underground clipping
--   +20, +50  -> Find upper floors, rooftops, elevated platforms
--   -10, -20  -> Find lower floors, basements, underground areas
--
-- Examples:
--   coords:get_cursor_world_pos()      -- Default +4, same floor as player
--   coords:get_cursor_world_pos(50)    -- Find roof/upper floor (+50 from player)
--   coords:get_cursor_world_pos(-15)   -- Find basement/lower floor (-15 from player)

--========================
-- Quick Examples
--========================

-- Example 1: One-liner to get world position from map click (same floor)
-- local coords = require("common/utility/coords_helper")
-- local world_pos = coords:get_cursor_world_pos()
-- if world_pos then
--     core.log("Clicked at: " .. world_pos.x .. ", " .. world_pos.y .. ", " .. world_pos.z)
-- end

-- Example 2: Find position on building roof
-- local roof_pos = coords:get_cursor_world_pos(40)

-- Example 3: Find position in basement
-- local basement_pos = coords:get_cursor_world_pos(-20)

-- Example 4: With error handling
-- local world_pos, err = coords:get_cursor_world_pos()
-- if not world_pos then
--     core.log_error("Conversion failed: " .. err)
-- end

---@type coords_helper
local tbl
return tbl
