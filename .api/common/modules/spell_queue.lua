
-- Example:
-- ---@type spell_queue
-- local sq = require("common/modules/spell_queue")
-- sq: -> IntelliSense
-- Warning: Access with ":", not "."

---@class spell_queue
---Queues an item for self-cast.
---@field public queue_item_self fun(self: spell_queue, item_id: number, priority: number, message?: string): nil
---Queues an item for self-cast that skips global cooldown.
---@field public queue_item_self_fast fun(self: spell_queue, item_id: number, priority: number, message?: string): nil
---Queues an item for a target.
---@field public queue_item_target fun(self: spell_queue, item_id: number, target: game_object, priority: number, message?: string): nil
---Queues an item for a target that skips global cooldown.
---@field public queue_item_target_fast fun(self: spell_queue, item_id: number, target: game_object, priority: number, message?: string): nil
---Queues an item for a position.
---@field public queue_item_position fun(self: spell_queue, item_id: number, position: vec3, priority: number, message?: string): nil
---Queues an item for a position that skips global cooldown.
---@field public queue_item_position_fast fun(self: spell_queue, item_id: number, position: vec3, priority: number, message?: string): nil
---Queues a spell with a target.
---@field public queue_spell_target fun(self: spell_queue, spell_id: number, target: any, priority: number, message?: string, allow_movement?: boolean): nil
---Queues a spell that skips global cooldown with a target.
---@field public queue_spell_target_fast fun(self: spell_queue, spell_id: number, target: any, priority: number, message?: string, allow_movement?: boolean): nil
---Queues a spell with a position.
---@field public queue_spell_position fun(self: spell_queue, spell_id: number, position: any, priority: number, message?: string, allow_movement?: boolean): nil
---Queues a spell that skips global cooldown with a position.
---@field public queue_spell_position_fast fun(self: spell_queue, spell_id: number, position: any, priority: number, message?: string, allow_movement?: boolean): nil

-- Example Usage:
-- local sq = require("common/modules/spell_queue")
-- sq:queue_item_self(12345, 1, "Example message") -- Queue an item for self-cast
-- sq:queue_item_self_fast(12345, 1, "Example message") -- Queue an item for self-cast with fast cooldown
-- sq:queue_item_target(12345, some_target, 1, "Targeted message") -- Queue an item for a specific target
-- sq:queue_item_target_fast(12345, some_target, 1, "Targeted message fast") -- Queue an item for a specific target with fast cooldown
-- sq:queue_item_position(12345, some_position, 1, "Position message") -- Queue an item for a specific position
-- sq:queue_item_position_fast(12345, some_position, 1, "Position message fast") -- Queue an item for a specific position with fast cooldown
-- sq:queue_spell_target(67890, some_target, 1, "Spell on target", true) -- Queue a spell with movement allowed
-- sq:queue_spell_target_fast(67890, some_target, 1, "Spell on target fast", false) -- Queue a spell for fast cooldown
-- sq:queue_spell_position(67890, some_position, 1, "Spell on position", true) -- Queue a spell for a position
-- sq:queue_spell_position_fast(67890, some_position, 1, "Spell on position fast", false) -- Queue a spell for a position with fast cooldown

---@class spell_queue
---Returns a shallow snapshot of the **normal** queue for debugging/telemetry.
---@field public get_queue_snapshot fun(self: spell_queue): { [number]: { spell_id: number, spell_type: integer, target: game_object|nil, position: vec3|nil, priority: number, timestamp: number, skips_global: boolean, is_item_exception: boolean, allow_movement: boolean } }
---Removes all entries from the **normal** queue that match `spell_id`. If `target` is provided, only entries for that exact target are removed. Returns the number removed.
---@field public purge_by_spell fun(self: spell_queue, spell_id: number, target?: game_object): integer

-- local sq = require("common/modules/spell_queue")
-- local snap = sq:get_queue_snapshot()
-- core.log(("queued entries: %d"):format(#snap))

-- local removed = sq:purge_by_spell(348, someTarget) -- only normal queue
-- core.log_warning(("purged %d immolate entries for target"):format(removed))

---@type spell_queue
local tbl
return tbl
