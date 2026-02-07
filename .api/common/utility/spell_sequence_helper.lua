
-- Example:
-- ---@type spell_sequence_helper
-- local cast_sequence = require("common/utility/spell_sequence_helper")
-- cast_sequence: -> IntelliSense
-- Warning: Access with ":", not "."

---@meta
---@diagnostic disable: undefined-global, missing-fields, lowercase-global

--------------------------------------------------------------------------------
-- Cast Policy Enum
--------------------------------------------------------------------------------

---@alias cast_policy
---| '"no_restrictions"'      # Can cast same spell repeatedly (default)
---| '"once_each_cycle"'      # Can only cast again after all spells in sequence evaluated
---| '"once_each_cycle_or_fill"' # Can cast again after cycle completes OR fill activates
---| '"once_each_cooldown"'   # Has internal cooldown before can cast again
---| '"once_each_switch"'     # Can cast again after any other base sequence spell casts
---| '"once_each_switch_or_fill"' # Can cast again after any other spell (base or fill) casts

--------------------------------------------------------------------------------
-- Entry Classes
--------------------------------------------------------------------------------

---@class advanced_spell_entry
---@field spell izi_spell The spell object
---@field target game_object|fun():game_object Target or function returning target
---@field condition fun():boolean Condition function (return true to allow cast)

---@class advanced_fill_entry
---@field spell izi_spell The fill spell object
---@field target game_object|fun():game_object Target or function returning target
---@field condition fun():boolean Condition function (return true to allow cast)

--------------------------------------------------------------------------------
-- Options Class
--------------------------------------------------------------------------------

---@class advanced_sequence_opts
---@field timeout? number Max time before auto-cancel (default 15)
---@field cooldown? number Cooldown after sequence ends (default 0)
---@field debug_name? string Name for logging (default "advanced_sequence")
---@field is_flexible_order? boolean If false, stop on first failed condition (default true)
---@field fill_entries? advanced_fill_entry[] Fill spells when main sequence stalls
---@field fill_delay_ms? number Ms to wait before using fill (default 100)
---@field cast_policy? cast_policy Controls spell re-cast behavior (default "no_restrictions")
---@field cast_policy_cooldown? number Internal cooldown for once_each_cooldown policy (default 4.0)

--------------------------------------------------------------------------------
-- Cast Policy Constants
--------------------------------------------------------------------------------

---@class cast_policy_enum
---@field NO_RESTRICTIONS string "no_restrictions"
---@field ONCE_EACH_CYCLE string "once_each_cycle"
---@field ONCE_EACH_CYCLE_OR_FILL string "once_each_cycle_or_fill"
---@field ONCE_EACH_COOLDOWN string "once_each_cooldown"
---@field ONCE_EACH_SWITCH string "once_each_switch"
---@field ONCE_EACH_SWITCH_OR_FILL string "once_each_switch_or_fill"

--------------------------------------------------------------------------------
-- Confirmed Sequence Types
--------------------------------------------------------------------------------

---@class confirmed_step
---@field spell izi_spell The spell to cast
---@field target game_object|fun():game_object Target for the spell (or function returning target)
---@field spell_id integer Spell ID for server callback matching
---@field opts? table Cast opts passed to cast_safe (e.g. { damage_type = ... })
---@field use_cast? boolean If true, uses spell:cast() instead of cast_safe() (for self-casts like Vanish, Stealth)

---@class confirmed_sequence_opts
---@field timeout? number Global timeout for the entire sequence (default 10)
---@field step_timeout? number Per-step timeout (default 3)
---@field debug_name? string Name for logging (default "confirmed_seq")
---@field cooldown? number Cooldown after sequence ends (default 0)
---@field player? game_object Local player for on_spell_cast filtering (auto-detected if nil)

--------------------------------------------------------------------------------
-- spell_sequence_helper
--------------------------------------------------------------------------------

-- Native sequence methods (proxied to engine module)
---@class spell_sequence_helper
---@field CAST_POLICY cast_policy_enum Cast policy constants
---@field a_into_b fun(self: spell_sequence_helper, spell_a: izi_spell, target_a: game_object, spell_b: izi_spell, target_b: game_object, delay?: number, timeout?: number, debug_name?: string, cooldown?: number): boolean
---@field simple_sequence fun(self: spell_sequence_helper, spells: izi_spell[], targets: game_object[], delay?: number, timeout?: number, debug_name?: string, cooldown?: number): boolean
---@field advanced_sequence fun(self: spell_sequence_helper, entries: advanced_spell_entry[], opts?: advanced_sequence_opts): boolean
---@field set_debug fun(self: spell_sequence_helper, enabled: boolean): nil
---@field get_debug fun(self: spell_sequence_helper): boolean

-- Confirmed sequence methods
---@class spell_sequence_helper
---@field confirmed_sequence fun(self: spell_sequence_helper, steps: confirmed_step[], opts?: confirmed_sequence_opts): boolean
---@field on_spell_cast fun(self: spell_sequence_helper, data: table): nil
---@field is_confirmed_active fun(self: spell_sequence_helper): boolean
---@field cancel_confirmed fun(self: spell_sequence_helper): nil
---@field get_confirmed_progress fun(self: spell_sequence_helper): integer|nil, integer|nil
---@field set_confirmed_debug fun(self: spell_sequence_helper, enabled: boolean): nil
---@field get_confirmed_debug fun(self: spell_sequence_helper): boolean

-- Combined state methods (check both native + confirmed)
---@class spell_sequence_helper
---@field is_active fun(self: spell_sequence_helper): boolean
---@field is_on_cooldown fun(self: spell_sequence_helper): boolean
---@field get_cooldown_remaining fun(self: spell_sequence_helper): number
---@field get_sequence_type fun(self: spell_sequence_helper): string|nil
---@field get_progress fun(self: spell_sequence_helper): integer|nil, integer|nil
---@field cancel fun(self: spell_sequence_helper): nil
---@field on_update fun(self: spell_sequence_helper): nil

-- Configuration
---@class spell_sequence_helper
---@field set_local_player_fn fun(self: spell_sequence_helper, fn: fun():game_object): nil
---@field bind_native fun(self: spell_sequence_helper, native_module: any): nil

--------------------------------------------------------------------------------
-- USAGE EXAMPLES
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
-- local cast_sequence = require("common/utility/spell_sequence_helper")
--
-- -- Enable debug logging
-- cast_sequence:set_debug(true)            -- native sequences
-- cast_sequence:set_confirmed_debug(true)  -- confirmed sequences
--
-- -------------------------------------------------------------------
-- -- A into B (cast spell A then immediately B)
-- -------------------------------------------------------------------
-- cast_sequence:a_into_b(
--     SPELLS.BUFF, player,
--     SPELLS.ATTACK, target,
--     0.0,              -- delay
--     3.0,              -- timeout
--     "Buff -> Attack", -- debug name
--     0.0               -- cooldown after sequence
-- )
--
-- -------------------------------------------------------------------
-- -- Simple sequence (strict order)
-- -------------------------------------------------------------------
-- cast_sequence:simple_sequence(
--     { SPELL_A, SPELL_B, SPELL_C },
--     { target, target, target },
--     0.0, 10.0, "A->B->C", 0.0
-- )
--
-- -------------------------------------------------------------------
-- -- Advanced sequence (conditions, flexible order, fill)
-- -------------------------------------------------------------------
-- cast_sequence:advanced_sequence({
--     { spell = SPELLS.COOLDOWN, target = player, condition = function() return true end },
--     { spell = SPELLS.BURST,    target = target, condition = function() return SPELLS.COOLDOWN:buff_up() end },
--     { spell = SPELLS.FINISHER, target = target, condition = function() return true end },
-- }, {
--     timeout = 20.0,
--     cooldown = 0.0,
--     debug_name = "Burst Combo",
--     is_flexible_order = true,
--     cast_policy = "no_restrictions",  -- or cast_sequence.CAST_POLICY.NO_RESTRICTIONS
--     fill_entries = {
--         { spell = SPELLS.FILLER_1, target = target, condition = function() return true end },
--         { spell = SPELLS.FILLER_2, target = target, condition = function() return true end },
--     },
--     fill_delay_ms = 120,
-- })
--
-- -------------------------------------------------------------------
-- -- Confirmed sequence (server-confirmed step-by-step)
-- -------------------------------------------------------------------
--
-- -- Wire the callback ONCE at plugin level:
-- core.register_on_spell_cast_callback(function(data)
--     cast_sequence:on_spell_cast(data)
-- end)
--
-- -- Start sequences (works directly, no izi SDK needed):
-- cast_sequence:confirmed_sequence({
--     { spell = SPELLS.VANISH, target = me, spell_id = 1857, use_cast = true },
--     { spell = SPELLS.SHADOWSTEP, target = target, spell_id = 36554 },
--     { spell = SPELLS.AMBUSH, target = target, spell_id = 11269, opts = { damage_type = 1 } },
-- }, {
--     debug_name = "Oneshot",
--     timeout = 5.0,
--     step_timeout = 3.0,
--     player = me,  -- recommended: local player for cast filtering
-- })
--
-- -- Targets can be functions for late-resolution:
-- cast_sequence:confirmed_sequence({
--     { spell = SPELLS.SHADOWSTEP, target = function() return izi.target() end, spell_id = 36554 },
--     { spell = SPELLS.AMBUSH,     target = function() return izi.target() end, spell_id = 11269 },
-- }, { debug_name = "Late-resolve target" })
--
-- -------------------------------------------------------------------
-- -- In on_update:
-- -------------------------------------------------------------------
-- cast_sequence:on_update()  -- advances both native and confirmed
-- if cast_sequence:is_active() then return end  -- checks BOTH
--
-- -------------------------------------------------------------------
-- -- Query functions
-- -------------------------------------------------------------------
-- local current, total = cast_sequence:get_progress()
-- local seq_type = cast_sequence:get_sequence_type()
-- if cast_sequence:is_on_cooldown() then
--     local remaining = cast_sequence:get_cooldown_remaining()
-- end
--
-- -------------------------------------------------------------------
-- -- Confirmed-only queries
-- -------------------------------------------------------------------
-- if cast_sequence:is_confirmed_active() then
--     local cur, tot = cast_sequence:get_confirmed_progress()
-- end
--
-- -------------------------------------------------------------------
-- -- Cancel
-- -------------------------------------------------------------------
-- cast_sequence:cancel()            -- cancels native sequence only
-- cast_sequence:cancel_confirmed()  -- cancels confirmed sequence only

---@type spell_sequence_helper
local tbl
return tbl
