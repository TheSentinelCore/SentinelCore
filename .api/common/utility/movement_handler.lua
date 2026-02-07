
-- Example:
-- ---@type movement_handler
-- local x = require("common/utility/movement_handler")
-- Pause movement for 5 seconds with a 0.5-second delay.
-- movement_handler:pause_movement(5, 0.5)
-- Schedule movement to resume in 1 second.
-- movement_handler:resume_movement(1)
-- x: -> IntelliSense
-- Warning: Access with ":", not "."

---@class movement_handler
---@field public pause_movement fun(self: movement_handler, pause_duration: number?, delay?: number): nil
---@field public pause_movement_light fun(self: movement_handler, pause_duration: number?, delay?: number): nil
---@field public resume_movement fun(self: movement_handler, action_delay?: number): nil
---@field public look_at_target fun(self: movement_handler, lock_duration: number?, delay?: number, target?: game_object): nil
---@field public look_at_position fun(self: movement_handler, lock_duration: number?, delay?: number, position: vec3): nil
---@field public unlock_look_at fun(self: movement_handler, action_delay?: number): nil
---@field public on_render fun(self: movement_handler): nil
---@field public get_state fun(self: movement_handler): table

---@type movement_handler
local tbl
return tbl
