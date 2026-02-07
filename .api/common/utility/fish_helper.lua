
-- Syntax / IntelliSense helper for: common/utility/fish_helper
-- Usage:
-- ---@type fish_helper
-- local fish = require("common/utility/fish_helper")
-- fish: -- IntelliSense
-- Warning: Access with ":", not "."

---@class loot_slot
---@field index integer
---@field is_gold boolean
---@field item_id integer|nil
---@field item_name string|nil

--- Fish Helper Module
--- Utilities for identifying the local player's fishing bobber, tracking bite timing,
--- and handling loot in a flexible way (all, gold-only, whitelist, blacklist, or custom filter).

---@class fish_helper
---@field public bobber_cache table<game_object, number>  # key: bobber object, value: core.time() of last bite/animation
---@field public is_fish_bobber fun(self: fish_helper, obj: game_object): boolean
---@field public does_bobber_have_fish fun(self: fish_helper, obj: game_object): boolean
---@field public get_last_animation_time fun(self: fish_helper, obj: game_object): number
---@field public open_loot fun(self: fish_helper, target: game_object): boolean, string
---@field public loot_all fun(self: fish_helper): boolean, {looted:integer, skipped:integer, gold:integer}
---@field public loot_gold_only fun(self: fish_helper): boolean, {looted:integer, skipped:integer, gold:integer}
---@field public loot_items_whitelist fun(self: fish_helper, whitelist: number[], loot_gold?: boolean): boolean, {looted:integer, skipped:integer, gold:integer}
---@field public loot_items_excluding_blacklist fun(self: fish_helper, blacklist: number[], loot_gold?: boolean): boolean, {looted:integer, skipped:integer, gold:integer}
---@field public loot_with_filter fun(self: fish_helper, filter: fun(slot: loot_slot): boolean): boolean, {looted:integer, skipped:integer, gold:integer}

--========================
-- Bobber identification
--========================
-- is_fish_bobber(obj) -> true when:
--  - obj:get_health() == 0 and obj:get_max_health() == 0
--  - obj:is_basic_object() is true
--  - obj:get_creator_object() == local player

-- does_bobber_have_fish(obj) -> true when bobber_cache[obj] recorded within last 10s

-- get_last_animation_time(obj) -> core.time() of last recorded bite/animation (0.0 if none)

--========================
-- Looting
--========================
-- open_loot(target) uses `core.input.use_object(target)` and checks if the loot window is open.
--   Returns: (true, "opened") on success; (false, "loot window not open") otherwise.
--
-- loot_all() -> Loots gold + all items. Returns (success, stats).
-- loot_gold_only() -> Loots only gold. Returns (success, stats).
-- loot_items_whitelist(whitelist, loot_gold)
--   - Loots gold (default true) and only items whose id is present in whitelist.
--   - Set loot_gold=false to ignore gold.
-- loot_items_excluding_blacklist(blacklist, loot_gold)
--   - Loots gold (default true) and all items NOT present in blacklist.
--   - Set loot_gold=false to ignore gold.
-- loot_with_filter(filter)
--   - `filter(slot: loot_slot)` decides per-slot looting. Return true to loot that slot.

--========================
-- Examples
--========================

-- Example: Detect bite and loot everything
-- ---@type fish_helper
-- local fish = require("common/utility/fish_helper")
-- local objects = core.object_manager.get_objects()
-- for _, obj in ipairs(objects) do
--     if fish:is_fish_bobber(obj) and fish:does_bobber_have_fish(obj) then
--         local opened = fish:open_loot(obj)
--         if opened then
--             local success, stats = fish:loot_all()
--             if success then
--                 core.log("Looted " .. tostring(stats.looted) .. " slots (" .. tostring(stats.gold) .. " gold).")
--             else
--                 core.log("Loot failed")
--             end
--         else
--             core.log("Loot window not open yet")
--         end
--     end
-- end

-- Example: Loot gold only
-- if fish:open_loot(bobber) then
--     local ok, stats = fish:loot_gold_only()
--     core.log("Gold-only looting ok=" .. tostring(ok) .. " gold=" .. tostring(stats.gold))
-- end

-- Example: Loot only certain fish IDs (keep gold)
-- local whitelist = { 12345, 67890 }
-- if fish:open_loot(bobber) then
--     local ok, stats = fish:loot_items_whitelist(whitelist, true)
--     core.log("Whitelist looting ok=" .. tostring(ok) .. " looted=" .. tostring(stats.looted))
-- end

-- Example: Loot everything except trash IDs (ignore gold)
-- local blacklist = { 111, 222, 333 }
-- if fish:open_loot(bobber) then
--     local ok, stats = fish:loot_items_excluding_blacklist(blacklist, false)
--     core.log("Blacklist looting ok=" .. tostring(ok) .. " looted=" .. tostring(stats.looted) .. " gold=" .. tostring(stats.gold))
-- end

-- Example: Custom filter (gold + specific bait name)
-- if fish:open_loot(bobber) then
--     local ok, stats = fish:loot_with_filter(function(slot)
--         if slot.is_gold then return true end
--         return slot.item_name == "Fancy Bait"
--     end)
--     core.log("Filter looting ok=" .. tostring(ok) .. " looted=" .. tostring(stats.looted))
-- end

---@type fish_helper
local tbl
return tbl
