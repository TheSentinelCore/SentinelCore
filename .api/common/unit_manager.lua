
-- Example:
-- ---@type unit_manager
-- local unit_manager = require("root/core_lua/proxy/unit_manager")
-- Warning: Access with ":", not "."

---@alias health { max: number, current: number }
---@alias object_packet { ptr: game_object }

---@class unit_packet
---@field ptr game_object
---@field is_unit boolean
---@field is_player boolean
---@field is_ally boolean
---@field is_enemy boolean
---@field health health
---@field position vec3
---@field distance_to_player_sqr number

---@class unit_manager
---@field get_cache_unit_list_raw fun(self: unit_manager): unit_packet[]
---@field get_cache_objects_list_raw fun(self: unit_manager, only_basic?: boolean): object_packet[]
---@field get_cache_unit_list fun(self: unit_manager): unit_packet[]
---@field get_cache_object_list fun(self: unit_manager, only_basic?: boolean): object_packet[]
---@field get_enemies_around_point fun(self: unit_manager, point?: vec3, range?: number, players_only?: boolean, include_dead?: boolean): game_objects_table
---@field get_allies_around_point fun(self: unit_manager, point?: vec3, range?: number, players_only?: boolean, party_only?: boolean, include_dead?: boolean): game_objects_table
---@field process fun(self: unit_manager)

---@type unit_manager
local tbl
return tbl
