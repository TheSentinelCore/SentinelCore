
-- Example:
-- ---@type cooldown_tracker
-- local tracker = require("common/utility/cooldown_tracker")
-- tracker: -- IntelliSense
-- Warning: Access with ":", not "."

--- Cooldown Tracker Module
--- Tracks and manages cooldowns for spells, with public APIs
--- to extend the internal whitelists/lists safely at runtime.

---@class cooldown_tracker
---@field public has_any_relevant_defensive_up fun(self: cooldown_tracker, unit: game_object): boolean
---@field public is_spell_ready fun(self: cooldown_tracker, unit: game_object, spell_id: number): boolean
---@field public has_any_kick_up fun(self: cooldown_tracker, caster: game_object, target: game_object, include_los: boolean): boolean
---@field public is_any_kick_around fun(self: cooldown_tracker, enemy_list: game_objects_table, include_los: boolean): boolean
---@field public is_spell_castable_to_player fun(self: cooldown_tracker, spell_id: number, caster: game_object, target: game_object, include_los: boolean): boolean
---@field public is_spell_in_range fun(self: cooldown_tracker, spell_id: number, caster: game_object, target: game_object): boolean
---@field public is_spell_los fun(self: cooldown_tracker, spell_id: number, caster: game_object, target: game_object): boolean
--- This function is the base of everything and it will return the amount of seconds left of cooldown of the spell, however if the spell you request doesnt match class or spec of the unit then it will return 999.
---@field public get_remaining_cooldown fun(self: cooldown_tracker, unit: game_object, spell_id: number): number
---@field public get_last_cast_time fun(self: cooldown_tracker, unit: game_object, spell_id: number): number

-- NEW: whitelist/list extension APIs (safe to call every frame; duplicates rejected)
---@class cooldown_tracker
---@field public add_self_cast_spell fun(self: cooldown_tracker, spellDef: cooldown_tracker.SpellDef, overwrite?: boolean): boolean, string
---@field public add_target_spell fun(self: cooldown_tracker, spellDef: cooldown_tracker.SpellDef, overwrite?: boolean): boolean, string
---@field public add_relevant_kick fun(self: cooldown_tracker, spellId: number): boolean, string
---@field public add_relevant_defensive fun(self: cooldown_tracker, spellId: number): boolean, string

---@class cooldown_tracker.SpellDef
---@field name string       -- Display name (only cosmetic for the tracker)
---@field id number         -- Unique SpellID; used for duplicates
---@field cooldown number   -- Cooldown in seconds
---@field range number      -- Effective range in yards
---@field class_id number   -- enums.class_id.*
---@field class_spec number|nil -- enums.class_spec_id.spec_enum.* (nil = any spec)

-- Example Usage (runtime additions):
-- Note: You can run this on addon load, or every frame; it’s idempotent.
-- Returns (added:boolean, reason:string). Log 'reason' when added=false.

-- 1) Add to SELF-CAST whitelist
-- local ok, why = tracker:add_self_cast_spell({
--     name = "Shield Wall",
--     id = 871,
--     cooldown = 180,
--     range = 0,
--     class_id = enums.class_id.WARRIOR,
--     class_spec = nil
-- }, false)
-- if not ok then print("[ct] self add skipped:", why) end

-- 2) Add to TARGET-CAST whitelist
-- Example: A made-up interrupt for demo (replace with a real one)
-- local ok2, why2 = tracker:add_target_spell({
--     name = "Arcane Jolt",
--     id = 999001,
--     cooldown = 18,
--     range = 40,
--     class_id = enums.class_id.MAGE,
--     class_spec = nil
-- }, false)
-- if not ok2 then print("[ct] target add skipped:", why2) end

-- 3) Add to RELEVANT KICK list (plain ints)
-- local ok3, why3 = tracker:add_relevant_kick(2139)   -- Counterspell
-- if not ok3 then print("[ct] kick add skipped:", why3) end

-- 4) Add to RELEVANT DEFENSIVE list (plain ints)
-- local ok4, why4 = tracker:add_relevant_defensive(45438)  -- Ice Block
-- if not ok4 then print("[ct] def add skipped:", why4) end

-- Core Queries:
-- if tracker:has_any_relevant_defensive_up(unit) then
--     print("Relevant defensive is ready!")
-- end
-- if tracker:is_spell_ready(unit, spell_id) then
--     print("Spell is ready to cast!")
-- end
-- if tracker:has_any_kick_up(caster, target, true) then
--     print("Enemy can interrupt (LOS-checked).")
-- end

---@type cooldown_tracker
local tbl
return tbl
