
-- Example:
-- ---@type enums
-- local c = require("common/izi_sdk")

---@meta
---@diagnostic disable: undefined-global, missing-fields, lowercase-global

---@alias sort_mode '"max"'|'"min"'
---@alias aura_spec number|number[]|any
---@alias target_filter fun(u: game_object): number|nil
---@alias adv_condition boolean|fun(u: game_object): boolean

---@class cast_opts
---@field skip_charges? boolean
---@field skip_learned? boolean
---@field skip_usable? boolean
---@field skip_back? boolean validated in is_castable_to_unit
---@field skip_moving? boolean
---@field skip_mount? boolean
---@field skip_casting? boolean
---@field skip_channeling? boolean
---@field skip_immune_check? boolean             -- skip target immunity validation entirely
---@field damage_type? integer                   -- override damage type for immunity check (use enums.damage_type_flags.PHYSICAL or .MAGICAL)
-- IMMUNITY CHECK BEHAVIOR:
-- - Always blocks if target is immune to ALL damage (divine shield, ice block)
-- - Auto-detects damage type from spell school for obvious cases:
--   * Pure Physical school -> checks physical immunity
--   * Pure magical (Fire/Nature/Frost/Shadow/Arcane) -> checks magic immunity  
--   * Holy or mixed schools -> no auto-detection (ambiguous)
-- - Developer can override with damage_type field
-- - Use skip_immune_check = true to bypass entirely

---@class unit_cast_opts: cast_opts
---@field skip_facing? boolean
---@field skip_range? boolean
---@field skip_gcd? boolean
---@field cache_time_override? number -- to override prediction cache, default value 0.15s (150ms)

---@alias prediction_type_opt   "AUTO"|"ACCURACY"|"MOST_HITS"|number
---@alias geometry_type_opt "CIRCLE"|"LINE"|number

---@class pos_cast_opts: unit_cast_opts
---@field check_los? boolean
---@field use_prediction? boolean                 -- default true for position casts
---@field prediction_type? prediction_type_opt    -- "AUTO"|"ACCURACY"|"MOST_HITS"|number
---@field geometry? geometry_type_opt             -- "CIRCLE"|"LINE"|number
---@field aoe_radius? number                      -- overrides defaults & hardcoded
---@field min_hits? integer                       -- default 1
---@field source_position? vec3                   -- custom origin for prediction
---@field cast_time? number                       -- override cast time (milliseconds); skips SDK lookup
---@field projectile_speed? number                -- override projectile speed (game units/sec); 0 = instant
---@field is_heal? boolean                        -- prediction becomes for allies instead of enemies
---@field use_intersection? boolean               -- use intersection position instead of center (for accuracy type)
---@field max_range? number

---@alias unit_predicate fun(u: game_object): boolean
---@alias unit_predicate_list unit_predicate[]

--------------------------------------------------------------------------------
-- game_object (methods patched by izi_module.apply -> patch_game_object_methods)
--------------------------------------------------------------------------------

---@class game_object
---@field get_health_percentage       fun(self: game_object): number                           -- 1..100 (e.g., 90 means ~90% HP)
---@field is_dummy                    fun(self: game_object): boolean                          -- True if training dummy
---@field is_alive                    fun(self: game_object): boolean                          -- Convenience alive check
---@field is_valid_enemy              fun(self: game_object): boolean                          -- Enemy of local player
---@field is_valid_ally               fun(self: game_object): boolean                          -- Ally of local player
---@field get_incoming_damage         fun(self: game_object, deadline_time_in_seconds: number, is_exception?: boolean): number -- Heuristic incoming damage
---@field get_incoming_damage_types   fun(self: game_object, deadline_time_in_seconds?: number, is_exception?: boolean): damage_types_table   -- Recent+predicted dmg profile | note: params are optional if you dont understand them, dont fill them
---@field get_physical_damage_taken_percentage fun(self: game_object, deadline_time_in_seconds?: number, is_exception?: boolean): number  -- 0–100%% of incoming dmg that is PHYSICAL | note: params are optional if you dont understand them, dont fill them
---@field get_magical_damage_taken_percentage  fun(self: game_object, deadline_time_in_seconds?: number, is_exception?: boolean): number  -- 0–100%% of incoming dmg that is MAGICAL | note: params are optional if you dont understand them, dont fill them
---@field get_health_percentage_inc   fun(self: game_object, deadline_time_in_seconds?: number): (number, number, number, number) -- Future HP% (1..100), incoming, current HP%, incoming%
---@field is_damage_immune            fun(self: game_object, type_flags?: integer, min_remaining_ms?: number): (boolean, number, number) -- PvP immunity: (is, rem_ms, expire_time)
---@field is_cc_immune                fun(self: game_object, type_flags?: integer, min_remaining_ms?: number, ignore_dot?: boolean, dot_blacklist?: number[]): (boolean, number, number) -- PvP CC immunity
---@field has_burst_active            fun(self: game_object, min_remaining_ms?: number): boolean -- PvP burst window

---@class game_object
---@field get_buff_data               fun(self: game_object, spec: aura_spec): any|nil         -- Resolved buff data (cached)
---@field has_buff                    fun(self: game_object, spec: aura_spec): boolean         -- Buff present?
---@field buff_up                     fun(self: game_object, spec: aura_spec): boolean         -- Alias of has_buff
---@field buff_down                   fun(self: game_object, spec: aura_spec): boolean         -- not has_buff
---@field get_buff_stacks             fun(self: game_object, spec: aura_spec): number          -- Stacks (0 if absent)
---@field buff_remains                fun(self: game_object, spec: aura_spec): number          -- Remaining secs (>=0)
---@field buff_remains_ms             fun(self: game_object, spec: aura_spec): number          -- Remaining ms (>=0)
---@field buff_remains_sec            fun(self: game_object, spec: aura_spec): number          -- Alias of buff_remains
---@field get_all_buffs               fun(self: game_object): buff_manager_cache_data[]                            -- Buff cache snapshot

---@class game_object
---@field get_debuff_data             fun(self: game_object, spec: aura_spec): any|nil         -- Resolved debuff data (cached; includes fake window)
---@field has_debuff                  fun(self: game_object, spec: aura_spec): boolean         -- Debuff present?
---@field debuff_up                   fun(self: game_object, spec: aura_spec): boolean         -- Alias of has_debuff
---@field debuff_down                 fun(self: game_object, spec: aura_spec): boolean         -- not has_debuff
---@field get_debuff_stacks           fun(self: game_object, spec: aura_spec): number          -- Stacks (0 if absent; fake window => 1)
---@field debuff_remains              fun(self: game_object, spec: aura_spec): number          -- Remaining secs (>=0; fake window => ~10)
---@field debuff_remains_ms           fun(self: game_object, spec: aura_spec): number          -- Remaining ms (>=0; fake window => ~10000)
---@field debuff_remains_sec          fun(self: game_object, spec: aura_spec): number          -- Alias of debuff_remains
---@field get_all_debuffs             fun(self: game_object): any[]                            -- Debuff cache snapshot

---@class game_object
---@field get_aura_data               fun(self: game_object, spec: aura_spec): any|nil         -- Any aura via aura cache
---@field has_aura                    fun(self: game_object, spec: aura_spec): boolean         -- Any aura present?
---@field aura_up                     fun(self: game_object, spec: aura_spec): boolean         -- Alias of has_aura
---@field aura_down                   fun(self: game_object, spec: aura_spec): boolean         -- not has_aura
---@field get_aura_stacks             fun(self: game_object, spec: aura_spec): number          -- Stacks (0 if absent)
---@field aura_remains                fun(self: game_object, spec: aura_spec): number          -- Remaining secs (>=0)
---@field aura_remains_ms             fun(self: game_object, spec: aura_spec): number          -- Remaining ms (>=0)
---@field aura_remains_sec            fun(self: game_object, spec: aura_spec): number          -- Alias of aura_remains
---@field get_all_auras               fun(self: game_object): any[]                            -- Aura cache snapshot

---@class game_object
---@field is_tank                     fun(self: game_object): boolean                           -- Role heuristic
---@field is_dps                      fun(self: game_object): boolean                           -- Role heuristic
---@field is_healer                   fun(self: game_object): boolean                           -- Role heuristic
---@field affecting_combat            fun(self: game_object): boolean                           -- In combat?
---@field time_to_die                 fun(self: game_object): number                            -- Forecasted TTD (seconds)
---@field get_time_to_death           fun(self: game_object): number                            -- Forecasted TTD (seconds)
---@field is_spell_in_range           fun(self: game_object, spell: integer|izi_spell|{id:fun(self):integer}): boolean -- Range vs local player
---@field is_in_range                 fun(self: game_object, meters: number): boolean           -- Distance <= meters
---@field is_in_melee_range           fun(self: game_object, meters: number): boolean           -- Distance <= (meters + target_radius)
---@field distance                    fun(self: game_object): number                            -- Distance to local player

---@class game_object
---@field get_enemies_in_splash_range       fun(self: game_object, meters: number): game_objects_table -- Enemies within meters (+radius), PvP-aware
---@field get_enemies_in_splash_range_count fun(self: game_object, meters: number): number        -- Count enemies within meters (+radius)
---@field level                       fun(self: game_object): number                             -- Unit level
---@field get_guid                    fun(self: game_object): game_object                        -- Underlying game_object reference
---@field npc_id                      fun(self: game_object): integer                            -- NPC id (0 for players)
---@field is_dead_or_ghost            fun(self: game_object): boolean                            -- True if dead or ghost

---@class game_object
---@field is_casting                              fun(self: game_object): boolean                    -- True if casting
---@field is_channeling                           fun(self: game_object): boolean                    -- True if channeling
---@field is_channeling_or_casting                fun(self: game_object): boolean                    -- True if channeling or casting
---@field get_active_cast_or_channel_id           fun(self: game_object): number                     -- Active spell id, prefers channel id then cast id, 0 if none
-- Casting timing
---@field get_cast_start_ms                       fun(self: game_object): number                     -- Cast start, ms since epoch/game time, 0 if none
---@field get_cast_end_ms                         fun(self: game_object): number                     -- Cast end, ms, 0 if none
---@field get_cast_duration_ms                    fun(self: game_object): number                     -- Total cast duration in ms
---@field get_cast_elapsed_ms                     fun(self: game_object): number                     -- Elapsed cast time in ms, 0 if not casting
---@field get_cast_remaining_ms                   fun(self: game_object): number                     -- Remaining cast time in ms, 0 if not casting
---@field get_cast_remaining_sec                  fun(self: game_object): number                     -- Remaining cast time in seconds
---@field get_cast_ratio                          fun(self: game_object): number                     -- Cast progress ratio 0..1
---@field get_cast_pct                            fun(self: game_object): number                     -- Cast progress percentage 0..100
-- Channel timing
---@field get_channel_start_ms                    fun(self: game_object): number                     -- Channel start, ms, 0 if none
---@field get_channel_end_ms                      fun(self: game_object): number                     -- Channel end, ms, 0 if none
---@field get_channel_duration_ms                 fun(self: game_object): number                     -- Total channel duration in ms
---@field get_channel_elapsed_ms                  fun(self: game_object): number                     -- Elapsed channel time in ms, 0 if not channeling
---@field get_channel_remaining_ms                fun(self: game_object): number                     -- Remaining channel time in ms, 0 if not channeling
---@field get_channel_remaining_sec               fun(self: game_object): number                     -- Remaining channel time in seconds
---@field get_channel_ratio                       fun(self: game_object): number                     -- Channel progress ratio 0..1
---@field get_channel_pct                         fun(self: game_object): number                     -- Channel progress percentage 0..100
-- Combined helpers
---@field get_channeling_or_casting_remaining_ms  fun(self: game_object): number                     -- Remaining time in ms, prefers channel then cast
---@field get_channeling_or_casting_remaining_sec fun(self: game_object): number                     -- Remaining time in seconds, prefers channel then cast
---@field get_channeling_or_casting_pct           fun(self: game_object): number                     -- Progress percentage 0..100, prefers channel then cast
---@field get_channeling_or_casting_ratio         fun(self: game_object): number                     -- Progress ratio 0..1, prefers channel then cast
-- Friendly aliases
---@field casting_pct                             fun(self: game_object): number                     -- Alias of get_cast_pct
---@field channeling_pct                          fun(self: game_object): number                     -- Alias of get_channel_pct
---@field casting_percentage                      fun(self: game_object): number                     -- Alias of get_cast_pct
---@field channeling_percentage                   fun(self: game_object): number                     -- Alias of get_channel_pct
---@field get_any_remaining_ms                    fun(self: game_object): number                     -- Alias of get_channeling_or_casting_remaining_ms
---@field get_any_remaining_sec                   fun(self: game_object): number                     -- Alias of get_channeling_or_casting_remaining_sec
---@field get_any_active_spell_id                 fun(self: game_object): number                     -- Alias of get_active_cast_or_channel_id

---@class game_object
---@field power_max                   fun(self: game_object, power_type: integer): number        -- Max power for a given type
---@field power_current               fun(self: game_object, power_type: integer): number        -- Current power for a given type
---@field power_pct                   fun(self: game_object, power_type: integer): number        -- Power percentage 0..100
---@field power_deficit               fun(self: game_object, power_type: integer): number        -- Max - current power
---@field power_deficit_pct           fun(self: game_object, power_type: integer): number        -- Deficit / max * 100

---@class game_object
---@field mana_max                    fun(self: game_object): number
---@field mana_current                fun(self: game_object): number
---@field mana_pct                    fun(self: game_object): number
---@field mana_deficit                fun(self: game_object): number

---@class game_object
---@field rage_max                    fun(self: game_object): number
---@field rage_current                fun(self: game_object): number
---@field rage_pct                    fun(self: game_object): number
---@field rage_deficit                fun(self: game_object): number

---@class game_object
---@field focus_max                   fun(self: game_object): number
---@field focus_current               fun(self: game_object): number
---@field focus_pct                   fun(self: game_object): number
---@field focus_deficit               fun(self: game_object): number
---@field focus_regen                 fun(self: game_object): number
---@field focus_regen_pct             fun(self: game_object): number
---@field focus_time_to_max           fun(self: game_object): number
---@field focus_time_to_x             fun(self: game_object, amount: number): number
---@field focus_time_to_x_pct         fun(self: game_object, pct: number): number

---@class game_object
---@field energy_max                  fun(self: game_object, max_offset?: number): number
---@field energy_current              fun(self: game_object): number
---@field energy_pct                  fun(self: game_object, max_offset?: number): number
---@field energy_deficit              fun(self: game_object, max_offset?: number): number
---@field energy_deficit_pct          fun(self: game_object, max_offset?: number): number
---@field energy_regen                fun(self: game_object): number
---@field energy_regen_pct            fun(self: game_object, max_offset?: number): number
---@field energy_time_to_max          fun(self: game_object, max_offset?: number): number
---@field energy_time_to_x            fun(self: game_object, amount: number, offset?: number): number
---@field energy_time_to_x_pct        fun(self: game_object, pct: number): number
---@field energy_cast_regen           fun(self: game_object, offset?: number): number
---@field energy_predicted            fun(self: game_object, offset?: number, max_offset?: number): number
---@field energy_deficit_predicted    fun(self: game_object, offset?: number, max_offset?: number): number
---@field energy_time_to_max_predicted fun(self: game_object, offset?: number, max_offset?: number): number

---@class game_object
---@field runic_power_max             fun(self: game_object): number
---@field runic_power_current         fun(self: game_object): number
---@field runic_power_pct             fun(self: game_object): number
---@field runic_power_deficit         fun(self: game_object): number

---@class game_object
---@field soul_shards_max             fun(self: game_object): number
---@field soul_shards_current         fun(self: game_object): number
---@field soul_shards_deficit         fun(self: game_object): number

---@class game_object
---@field astral_power_max            fun(self: game_object): number
---@field astral_power_current        fun(self: game_object): number
---@field astral_power_pct            fun(self: game_object): number
---@field astral_power_deficit        fun(self: game_object): number
---@field astral_power_deficit_pct    fun(self: game_object): number

---@class game_object
---@field chi_max                     fun(self: game_object): number
---@field chi_current                 fun(self: game_object): number
---@field chi_pct                     fun(self: game_object): number
---@field chi_deficit                 fun(self: game_object): number
---@field chi_deficit_pct             fun(self: game_object): number

---@class game_object
---@field combo_points_max            fun(self: game_object): number
---@field combo_points_current        fun(self: game_object): number
---@field combo_points_deficit        fun(self: game_object): number
---@field charged_combo_points        fun(self: game_object): number

---@class game_object
---@field holy_power_max              fun(self: game_object): number
---@field holy_power_current          fun(self: game_object): number

---@class game_object
---@field haste_pct                   fun(self: game_object): number
---@field spell_haste_multiplier      fun(self: game_object): number
---@field gcd                         fun(self: game_object): number
---@field gcd_remains                 fun(self: game_object): number
---@field is_standing_still           fun(self: game_object, min_still?: number): boolean
---@field can_cast_while_moving       fun(self: game_object): boolean

---@class game_object
---@field rune_count                  fun(self: game_object): integer
---@field rune_time_to_x              fun(self: game_object, value: integer): number
---@field rune_type_count             fun(self: game_object, index: integer): integer

---@class game_object
---@field max_health                  fun(self: game_object): number
---@field stagger_amount              fun(self: game_object): number
---@field stagger_pct                 fun(self: game_object): number
---@field is_stagger_medium_or_more   fun(self: game_object): boolean
---@field is_stagger_heavy            fun(self: game_object): boolean
---@field get_aura_description_value  fun(self: game_object, spec: number|number[], search_type?: "buff"|"debuff"|"aura", as_percentage?: boolean): number -- Extract numeric value from aura description

---@class game_object
---@field time_in_combat              fun(self: game_object): number -- in seconds
---@field get_totem_info              fun(self: game_object, i: integer): (boolean, string, number, number)

---@class game_object
---@field get_enemies_in_range        fun(self: game_object, meters: number, players_only?: boolean): game_objects_table -- includes combat filter for non-player controlled units
---@field get_enemies_in_melee_range  fun(self: game_object, meters: number, players_only?: boolean): game_objects_table -- includes combat filter for non-player controlled units
---@field get_friends_in_range        fun(self: game_object, meters: number, players_only?: boolean): game_objects_table
---@field get_party_members_in_range  fun(self: game_object, meters: number, players_only?: boolean): game_objects_table
---@field get_all_minions             fun(self: game_object, meters?: number): game_objects_table

---@class game_object
---@field get_enemies_in_range_if fun(self: game_object, meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_objects_table -- includes units in combat, blacklisted and dead, you must perform all the filters yourself
---@field get_enemies_in_melee_range_if fun(self: game_object, meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_objects_table -- includes units in combat, blacklisted and dead, you must perform all the filters yourself
---@field get_friends_in_range_if fun(self: game_object, meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_objects_table

---@class game_object
---@field stealth_remains             fun(self: game_object, check_combat?: boolean, check_special?: boolean): number
---@field stealth_up                  fun(self: game_object, check_combat?: boolean, check_special?: boolean): boolean
---@field stealth_down                fun(self: game_object, check_combat?: boolean, check_special?: boolean): boolean
---@field is_behind_unit fun(self: game_object, unit: game_object): boolean  -- true if self is in the rear arc of `unit`
---@field is_behind      fun(self: game_object, unit: game_object): boolean  -- alias of is_behind_unit
---@field is_looking_at_position  fun(self: game_object, position: vec3, max_angle: number|nil): boolean -- true if `position` is in front arc (default 88°, override with max_angle)
---@field is_looking_at_unit      fun(self: game_object, unit: game_object, max_angle: number|nil): boolean -- true if `unit` is in front arc (default 88°, override with max_angle)
---@field is_looking_at           fun(self: game_object, target: game_object|vec3, max_angle: number|nil): boolean -- dispatches to unit/position version

---@class game_object
---@field predict_position fun(self: game_object, time?: number): vec3|nil  -- Predicted position after `time` seconds (default 1.0)
---@field distance_to fun(self: game_object, other: game_object): number     -- Distance to another unit
---@field distance_from_position fun(self: game_object, pos: vec3): number   -- Distance to a world position
---@field predict_distance fun(self: game_object, time?: number, other?: game_object): number  -- Predicted distance after `time` seconds, this unit moves, other stays
---@field los_to fun(self: game_object, other: game_object): boolean         -- True if line of sight exists between two units
---@field los_to_position fun(self: game_object, pos: vec3): boolean         -- True if line of sight exists from this unit to a position
---@field is_behind_future fun(self: game_object, unit: game_object, time?: number): boolean  -- True if behind unit's predicted facing after optional `time` offset
---@field is_moving_towards_me fun(self: game_object, unit: game_object, angle_limit?: number): (boolean, number)  -- Returns (is_towards, angle)

---@class game_object
-- True if incoming physical damage is relevant (heuristic: >= 3.3% of current health).
---@field is_physical_damage_taken_relevant fun(self: game_object): boolean

---@class game_object
-- True if incoming magical damage is relevant (heuristic: >= 3.3% of current health).
---@field is_magical_damage_taken_relevant fun(self: game_object): boolean

---@class game_object
-- True if any incoming damage (physical + magical) is relevant (heuristic: >= 3.3% of current health).
---@field is_any_damage_taken_relevant fun(self: game_object): boolean

-------------------------------------------------------------------------------
-- izi_spell (snake_case only; no CAPS aliases)
--------------------------------------------------------------------------------

---@class izi_spell
---@field ids                 integer[]                     -- Candidate spell IDs
---@field max_enemies         integer                       -- Utility knob for AoE heuristics
---@field last_cast_time      number                        -- Last time (sec) this spell was queued to cast
---@field minimum_range       number                        -- Spellbook min range (0 if none)
---@field maximum_range       number                        -- Spellbook max range (0 if none)
---@field _gcd_value          number|nil                    -- Cached per-spell GCD (nil → fallback to global)
---@field _tracked_debuff_spec (number|number[])|nil  -- override for target debuff spec
---@field _tracked_buff_spec   (number|number[])|nil  -- override for self/ally buff spec
---@field id                  fun(self: izi_spell): integer
---@field name                fun(self: izi_spell): string
---@field is_learned          fun(self: izi_spell): boolean
---@field is_usable           fun(self: izi_spell): boolean
---@field is_available        fun(self: izi_spell): boolean
---@field cast_time           fun(self: izi_spell): number
---@field cast_time_ms        fun(self: izi_spell): number
---@field charges             fun(self: izi_spell): integer
---@field max_charges         fun(self: izi_spell): integer
---@field charges_info        fun(self: izi_spell): (integer, integer, integer, integer, number) -- (cur, max, startMS, durationMS, modRate)
---@field charges_fractional  fun(self: izi_spell, recharge_ms?: number): number
---@field recharge            fun(self: izi_spell): number
---@field cooldown_remains    fun(self: izi_spell): number
---@field cooldown            fun(self: izi_spell): number
---@field cooldown_up         fun(self: izi_spell): boolean
---@field cooldown_down       fun(self: izi_spell): boolean
---@field get_gcd             fun(self: izi_spell): number
---@field skips_gcd           fun(self: izi_spell): boolean
---@field is_usable_while_moving fun(self: izi_spell): boolean
---@field requires_back       fun(self: izi_spell): boolean
---@field since_last_cast     fun(self: izi_spell): number
---@field in_gcd_window       fun(self: izi_spell, threshold?: number): boolean
---@field in_recharge         fun(self: izi_spell): boolean
---@field has_charges_at      fun(self: izi_spell, t?: number): boolean
---@field track_debuff        fun(self: izi_spell, spec: (number|number[])|nil): izi_spell
---@field track_buff          fun(self: izi_spell, spec: (number|number[])|nil): izi_spell
---@field get_tracked_debuff_spec fun(self: izi_spell): (number|number[])
---@field get_tracked_buff_spec   fun(self: izi_spell): (number|number[])

---@class izi_spell
---@field is_castable fun(self: izi_spell, opts?: cast_opts): boolean

---@class izi_spell
---@field is_castable_to_unit fun(
---   self: izi_spell,
---   target?: game_object,
---   opts?: unit_cast_opts ): boolean

---@class izi_spell
---@field is_castable_to_position fun(
---   self: izi_spell,
---   target?: game_object,         -- context (defaults to target/self)
---   cast_pos?: vec3,              -- if nil -> target:get_position()
---   opts?: pos_cast_opts ): boolean

---@class izi_cast_meta
---@field cast_position? vec3                    -- set if a skillshot was queued
---@field hit_time? number                       -- cast time plus projectile travel, if available
---@field predicted? boolean                     -- true if position came from prediction
---@field hits? integer                          -- predicted amount of hits, if available
---@field prediction_meta? table                 -- raw prediction block from _compute_cast_position
---@field target? game_object                    -- target for targeted casts
---@field unit? game_object                      -- candidate unit for *_target_if helpers
---@field rank_index? integer                    -- index chosen in ranked lists
---@field attempted? integer                     -- how many candidates were attempted
---@field reason? string                         -- failure reason code on false
---@field err? string                            -- optional lower level error string

---@class izi_spell
---@field cast fun(
---   self: izi_spell,
---   target?: game_object,
---   message?: string,
---   opts?: pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_spell
---@field cast_safe fun(
---   self: izi_spell,
---   target?: game_object,
---   message?: string,
---   opts?: unit_cast_opts|pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_spell
---@field cast_target_if fun(
---   self: izi_spell,
---   units: game_objects_table,
---   mode: "max"|"min",
---   filter: fun(u: game_object): (number|nil),
---   adv_condition?: (boolean|fun(u: game_object): boolean|nil),
---   another_condition?: boolean,
---   max_attempts?: integer,
---   message?: string): (boolean, izi_cast_meta)

---@class izi_spell
---@field cast_target_if_safe fun(
---   self: izi_spell,
---   units: game_objects_table,
---   mode: "max"|"min",
---   filter: fun(u: game_object): (number|nil),
---   adv_condition?: (boolean|fun(u: game_object): boolean|nil),
---   another_condition?: boolean,
---   max_attempts?: integer,
---   message?: string,
---   opts?: unit_cast_opts): (boolean, izi_cast_meta)

---@class izi_api
---@field cast fun(
---   spell: izi_spell,
---   target?: game_object,
---   message?: string,
---   opts?: pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_api
---@field cast_safe fun(
---   spell: izi_spell,
---   target?: game_object,
---   message?: string,
---   opts?: unit_cast_opts|pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_api
---@field cast_target_if fun(
---   spell: izi_spell,
---   units: game_objects_table,
---   mode: "max"|"min",
---   filter: fun(u: game_object): (number|nil),
---   adv_condition?: (boolean|fun(u: game_object): boolean|nil),
---   another_condition?: boolean,
---   max_attempts?: integer,
---   message?: string): (boolean, izi_cast_meta)

---@class izi_api
---@field cast_target_if_safe fun(
---   spell: izi_spell,
---   units: game_objects_table,
---   mode: "max"|"min",
---   filter: fun(u: game_object): (number|nil),
---   adv_condition?: (boolean|fun(u: game_object): boolean|nil),
---   another_condition?: boolean,
---   max_attempts?: integer,
---   message?: string,
---   opts?: unit_cast_opts): (boolean, izi_cast_meta)

---@class izi_spell
---@field cast_position fun(
---   self: izi_spell,
---   position: vec3,
---   message?: string,
---   opts?: pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_api
---@field cast_position fun(
---   spell: izi_spell,
---   position: vec3,
---   message?: string,
---   opts?: pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_module
---@field cast_charge_spell fun(
---   spell: izi_spell,                       -- the empower spell wrapper
---   stage: 1|2|3|4,                         -- target empower stage to release at
---   target?: game_object,                   -- optional target or nil to use player target or self
---   message?: string,                       -- optional queue message
---   opts?: unit_cast_opts|pos_cast_opts ): boolean      -- forwarded to :cast_safe for the initial press

---@class defensive_filters
---@field block_time? number                                        -- seconds to block further defensives after success (default 1)
---@field health_percentage_threshold_raw? number                   -- cast if current HP % <= this (default 50)
---@field health_percentage_threshold_incoming? number              -- cast if forecasted HP % <= this (default 40)
---@field physical_damage_percentage_threshold? number              -- if >0, cast if incoming physical % >= this and relevant (default 0, ignored)
---@field magical_damage_percentage_threshold? number               -- similar for magical (default 0, ignored)

---@class izi_spell
-- Cast this spell as a defensive on self with extra filters to decide if the cast should proceed.
-- Prevents casting more than one defensive within the block time.
-- See izi_module.cast_defensive for details on filters.
---@field cast_defensive fun(
---   self: izi_spell,
---   target: game_object,
---   filters?: defensive_filters,                            -- optional filters table
---   message?: string,                                       -- optional queue message
---   opts?: unit_cast_opts ): boolean                        -- forwarded to :cast_safe

---@class izi_api
-- Cast a defensive spell on self with extra filters to decide if the cast should proceed.
-- Prevents casting more than one defensive within the block time.
---@field cast_defensive fun(
---   spell: izi_spell,                                       -- the defensive spell wrapper
---   target: game_object,
---   filters?: defensive_filters,                            -- optional filters table
---   message?: string,                                       -- optional queue message
---   opts?: unit_cast_opts ): boolean                        -- forwarded to spell:cast_safe

--------------------------------------------------------------------------------
-- izi_api (module surface)
--------------------------------------------------------------------------------

---@class izi_api
---@field print fun(...: any): nil
---@field printf fun(fmt: string, ...: any): nil
---@field log fun(filename: string, ...: any): nil
---@field logf fun(filename: string, fmt: string, ...: any): nil

---@class izi_api
---@field on_buff_gain    fun(cb: fun(ev: { unit: game_object, buff_id: integer })) : (fun())      -- unsubscribe() return
---@field on_buff_lose    fun(cb: fun(ev: { unit: game_object, buff_id: integer })) : (fun())
---@field on_debuff_gain  fun(cb: fun(ev: { unit: game_object, debuff_id: integer })) : (fun())
---@field on_debuff_lose  fun(cb: fun(ev: { unit: game_object, debuff_id: integer })) : (fun())
---@field on_combat_start fun(cb: fun(ev: { unit: game_object })) : (fun())
---@field on_combat_finish fun(cb: fun(ev: { unit: game_object })) : (fun())
---@field on_spell_begin  fun(cb: fun(ev: { spell_id: integer, caster: game_object, target: game_object|nil })) : (fun())
---@field on_spell_success fun(cb: fun(ev: { spell_id: integer, caster: game_object, target: game_object|nil })) : (fun())
---@field on_spell_cancel fun(cb: fun(ev: { spell_id: integer, caster: game_object, target: game_object|nil })) : (fun())
---@field on_key_release  fun(key: integer|string, cb: fun(key: integer|string)) : (fun())

---@class izi_api
---@field get_ts_target  fun(): game_object|nil                    -- First TS target or nil
---@field get_ts_targets fun(limit?: integer): game_objects_table        -- Up to `limit` TS targets (game_objects)

---@class izi_api
---@field spell fun(...: any): izi_spell
---@overload fun(id: integer): izi_spell
---@overload fun(id1: integer, id2: integer, ...: integer): izi_spell
---@overload fun(ids: integer[]): izi_spell

---@class izi_api
---@field me                        fun(): game_object|nil                                          -- Local player or nil
---@field get_player                fun(): game_object|nil                                          -- Alias of me()
---@field is_arena                  fun(): boolean                                                  -- Return if local client is inside an arena map type
---@field in_arena                  fun(): boolean                                                  -- Return if local client is inside an arena map type
---@field is_in_arena               fun(): boolean                                                  -- Return if local client is inside an arena map type
---@field get_time_to_die_global    fun(): number                                                   -- Return global time to die in seconds
---@field target                    fun(): game_object|nil                                          -- Current target or nil
---@field ts                        fun(i?: integer): game_object|nil                               -- Target selector i (default 1)
---@field enemies                   fun(radius?: number, players_only?: boolean): game_objects_table     -- Enemies around player
---@field friends                   fun(radius?: number, players_only?: boolean): game_objects_table     -- Allies around player
---@field party                     fun(radius?: number): game_objects_table                             -- Party members around player
---@field after                     fun(seconds: number, fn: fun()): (fun())                        -- Schedule fn after N seconds; returns cancel()

---@class izi_api
---@field enemies_if fun(radius?: number, filter?: unit_predicate|unit_predicate_list): game_objects_table
---@field friends_if fun(radius?: number, filter?: unit_predicate|unit_predicate_list): game_objects_table

---@class izi_api
---@field pick_enemy  fun(radius?: number, players_only?: boolean, filter: fun(u: game_object): (number|nil), mode: sort_mode): game_object|nil
---@field spread_dot  fun(spell: izi_spell, enemies?: game_objects_table, refresh_below_ms?: number, max_attempts?: integer, message?: string): boolean

---@class izi_api
---@field now               fun(): number                     -- core timer seconds (same source as core.now())
---@field now_seconds       fun(): number                     -- alias of now()
---@field now_ms            fun(): number                     -- core timer milliseconds
---@field now_game_time_ms  fun(): number                     -- game_time() in ms (if available)

---@class izi_api
---@field item fun(...: any): izi_item

---@class izi_item
---@field id                    fun(self: izi_item): integer              -- resolved, preferred item id
---@field name                  fun(self: izi_item): string
---@field object                fun(self: izi_item): game_object|nil
---@field equipped_slot         fun(self: izi_item): integer|nil
---@field equipped              fun(self: izi_item): boolean
---@field count                 fun(self: izi_item): integer
---@field in_inventory          fun(self: izi_item): boolean
---@field is_usable             fun(self: izi_item): boolean
---@field cooldown_remains      fun(self: izi_item): number               -- seconds
---@field cooldown_up           fun(self: izi_item): boolean
---@field has_range             fun(self: izi_item): boolean
---@field is_in_range           fun(self: izi_item, target?: game_object): boolean
---@field use_self              fun(self: izi_item, message?: string, fast?: boolean): boolean
---@field use_on                fun(self: izi_item, target?: game_object, message?: string, fast?: boolean): boolean
---@field use_at_position       fun(self: izi_item, position: vec3, message?: string, fast?: boolean): boolean
---@field use_self_safe         fun(self: izi_item, message?: string, opts?: item_use_opts): boolean
---@field use_on_safe           fun(self: izi_item, target?: game_object, message?: string, opts?: item_use_opts): boolean
---@field use_at_position_safe  fun(self: izi_item, target?: game_object, position: vec3, message?: string, opts?: item_use_opts): boolean

---@alias item_id integer
---@alias item_ids integer[]

--- Create or fetch an izi_item. Accepts a single id or a list of fallback ids.
--- The object methods operate on the resolved id.
---@overload fun(id: item_id): izi_item
---@overload fun(ids: item_ids): izi_item

---@class item_use_opts
---@field skip_usable? boolean
---@field skip_cooldown? boolean
---@field skip_range? boolean
---@field skip_moving? boolean
---@field skip_mount? boolean
---@field skip_casting? boolean
---@field skip_channeling? boolean
---@field skip_gcd? boolean
---@field check_los? boolean

---@class izi_api
---@field best_health_potion_id fun(): integer|nil
---@field best_mana_potion_id fun(): integer|nil
---@field use_best_health_potion_safe fun(opts?: item_use_opts): boolean
---@field use_best_mana_potion_safe fun(opts?: item_use_opts): boolean

--------------------------------------------------------------------------------
-- PvP helpers
-- Notes:
-- • cc_flags and dmg_type flags are bitmasks, combine with bitwise OR.
-- • source_mask is a bitmask for source filters (for example player, pet, totem), engine-defined.
-- • Returns for is_cc-like queries: (active:boolean, applied_mask:integer, remaining_ms:integer [, immune:boolean] [, weak:boolean])
-- • DR, diminishing returns. get_dr returns the multiplicative DR, 1.0, 0.5, 0.25, 0.0. get_dr_time returns seconds to reset.
-- • Slows: movement multiplier (mult) in [0..1]. Example mult 0.6 means 40% slow. is_slowed(threshold) compares against 1 - mult.
-- • has_burst is a friendly alias of has_burst_active inside pvp_helper.
--------------------------------------------------------------------------------

---@alias CCFlagMask integer           -- Bitmask of CC flags
---@alias DMGTypeMask integer          -- Bitmask of damage-type flags
---@alias SourceMask integer           -- Bitmask of source filters
---@alias Milliseconds integer

---@class PurgeEntry
---@field buff_id integer
---@field buff_name string
---@field priority integer
---@field min_remaining number          -- seconds

---@class PurgeScanResult
---@field is_purgeable boolean
---@field table PurgeEntry[]            -- list of purge candidate buffs
---@field current_remaining_ms integer
---@field expire_time number            -- engine time in seconds when shortest candidate expires

--------------------------------------------------------------------------------
-- Scenario and basic typing helpers
--------------------------------------------------------------------------------

---@class game_object
--- True if in a PvP context, arena, battleground, duel, war mode versus player.
--- Aliases: isPvP, in_pvp, inPvP
---@field is_pvp fun(self: game_object): boolean
--- Treat special targets flagged like players as playerlike.
--- Aliases: isPlayerLike, is_player_or_dummy, isPlayerOrDummy
---@field is_playerlike fun(self: game_object): boolean

--------------------------------------------------------------------------------
-- Crowd control state
--------------------------------------------------------------------------------

---@class game_object
--- Generic CC query with optional filters.
--- Defaults: min_remaining_ms = 1000, cc_flags = CC.ANY, source_mask = ANY
--- Returns:
---   active: boolean, true if any matching CC is active
---   applied_mask: CCFlagMask, bitmask of matched CC categories
---   remaining_ms: Milliseconds, best remaining among matches
---   immune: boolean, true if currently immune to the queried CC set
---   weak: boolean, true if only weak CC is present, breaks on damage
--- Aliases: isCC, crowd_controlled, isCrowdControlled
---@field is_cc fun(self: game_object, min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)
--- Weak CC, breaks on damage, convenience wrapper.
--- Defaults: min_remaining_ms = 500
--- Returns: active, applied_mask, remaining_ms
--- Aliases: isWeakCC, weak_cc
---@field is_cc_weak fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Root check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.ROOT, remaining_ms
--- Aliases: rooted, isRooted
---@field is_rooted fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Stun check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.STUN, remaining_ms
--- Aliases: stunned, isStunned
---@field is_stunned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Fear check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.FEAR, remaining_ms
--- Aliases: feared, isFeared
---@field is_feared fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Sap check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.SAP, remaining_ms
--- Aliases: sapped, isSapped
---@field is_sapped fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Silence check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.SILENCE, remaining_ms
--- Aliases: silenced, isSilenced
---@field is_silenced fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Cyclone check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.CYCLONE, remaining_ms
--- Aliases: cycloned, isCycloned
---@field is_cycloned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Disarm check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.DISARM, remaining_ms
--- Aliases: disarmed, isDisarmed
---@field is_disarmed fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Disorient check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.DISORIENT, remaining_ms
--- Aliases: isDisorient, isDisoriented
---@field is_disoriented fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Incapacitate check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.INCAPACITATE, remaining_ms
--- Aliases: is_incapacitated, isIncapacitated
---@field is_incap fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

--------------------------------------------------------------------------------
-- Diminishing returns, DR
--------------------------------------------------------------------------------

---@class game_object
--- DR multiplier for a CC category.
--- category can be a CC flag integer or a case-insensitive name:
---   "stun", "root", "fear", "sap", "disorient", "incapacitate",
---   "silence", "disarm", "knockback", "cyclone", "horror", "mind_control"
--- Defaults: hit_at_sec = 0, pass 0 to evaluate now
--- Returns: 1.0, 0.5, 0.25, 0.0, values greater than 1.01 indicate not tracked yet
--- Aliases: dr, dr_for, getDR, DR
---@field get_dr fun(self: game_object, category: (integer|string), hit_at_sec?: number): number
--- Seconds left until DR fully resets for the category.
--- category accepts the same values as get_dr.
--- Aliases: dr_time, drTimeLeft, getDRTime
---@field get_dr_time fun(self: game_object, category: (integer|string)): number

--------------------------------------------------------------------------------
-- CC immunity and reduction
--------------------------------------------------------------------------------

---@class game_object
--- Immunity to CC.
--- Defaults: cc_flags = CC.ANY, min_remaining_ms = 100, ignore_dot = false, dot_blacklist = nil, source_mask = ANY
--- Returns:
---   immune: boolean, true if immune to the queried set
---   applied_mask: CCFlagMask, mask of immunity sources relevant to the queried set
---   remaining_ms: Milliseconds, best remaining among sources
--- Aliases: immune_cc, isCCImmune
---@field is_cc_immune fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- CC reduction percentage.
--- Defaults: cc_flags = CC.ANY, min_remaining_ms = 100
--- Returns:
---   percent: number, 0..100
---   applied_mask: CCFlagMask
---   remaining_ms: Milliseconds
--- Aliases: cc_reduction, getCCReduce, getCCReduction
---@field get_cc_reduction fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)

--------------------------------------------------------------------------------
-- Slows
--------------------------------------------------------------------------------

---@class game_object
--- Is slowed past a threshold.
--- Defaults: threshold = 0.30, min_remaining_ms = 2000
--- Returns:
---   is_slowed: boolean
---   mult: number, movement multiplier 0..1, example 0.6 means 40 percent slow
---   remaining_ms: Milliseconds
--- Aliases: isSlowed, slowed
---@field is_slowed fun(self: game_object, threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)
--- Get current slow multiplier and remaining time.
--- Defaults: min_remaining_ms = 2000
--- Returns: mult 0..1, remaining_ms
--- Aliases: slow_mult, getSlow
---@field get_slow fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)
--- Slow immunity.
--- Defaults: min_remaining_ms = 100
--- Returns: immune: boolean, remaining_ms
--- Aliases: slow_immune, isSlowImmune
---@field is_slow_immune fun(self: game_object, source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)

--------------------------------------------------------------------------------
-- Damage reduction and immunity
--------------------------------------------------------------------------------

---@class game_object
--- Damage reduction percentage for a set of damage types.
--- Defaults: type_flags = DMG.ANY, min_remaining_ms = 100
--- Returns: percent 0..100, type_mask: DMGTypeMask, remaining_ms
--- Aliases: getDRPct, dmg_reduction, dmgRed, getDamageReduction
---@field get_damage_reduction fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)
--- Damage immunity for a set of damage types.
--- Defaults: type_flags = DMG.ANY, min_remaining_ms = 25
--- Returns: immune: boolean, type_mask: DMGTypeMask, remaining_ms
--- Aliases: isImmune, isDamageImmune, immune_dmg
---@field is_damage_immune fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)

--------------------------------------------------------------------------------
-- Burst windows and text helpers
--------------------------------------------------------------------------------

---@class game_object
--- True if the unit has an offensive burst window active with at least min_remaining_ms left.
--- Defaults: min_remaining_ms = 1600
--- Aliases: is_bursting, bursting, hasBurst
---@field has_burst fun(self: game_object, min_remaining_ms?: Milliseconds): boolean
--- Human readable CC list for a mask, useful for HUDs.
--- Aliases: CCText, cc_desc
---@field cc_text fun(self: game_object, cc_mask: CCFlagMask): string
--- Human readable damage-type list for a mask, useful for HUDs.
--- Aliases: DMGText, dmg_desc
---@field dmg_text fun(self: game_object, dmg_mask: DMGTypeMask): string

--------------------------------------------------------------------------------
-- Purge and disarm
--------------------------------------------------------------------------------

---@class game_object
--- Scan for purgeable buffs on the target.
--- Defaults: min_remaining_ms = 250
--- Returns: PurgeScanResult table, see type above
--- Aliases, all map to the same function:
---   isPurgable, is_purgeable, isPurgeable, can_be_purged, canBePurged
---@field is_purgable fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
--- Whether the target can be disarmed now.
--- include_all: if supported by backend, include off-hand or special cases
--- Returns: boolean
--- Aliases: isDisarmable, can_be_disarmed, canBeDisarmed
---@field is_disarmable fun(self: game_object, include_all?: boolean): boolean

--------------------------------------------------------------------------------
-- Exposed flag tables, bitmask constants provided by runtime
--------------------------------------------------------------------------------

---@class game_object
---@field CC cc_flags              -- CC flags, for example CC.STUN, CC.ROOT, CC.ANY
---@field DMG damage_type_flags    -- DMG flags, for example DMG.PHYSICAL, DMG.MAGICAL, DMG.ANY

--------------------------------------------------------------------------------
-- Aliases section, optional helpers for IDEs that do not pick up alias names automatically.
-- You can copy these as @field entries to surface every alias with the same types.
--------------------------------------------------------------------------------

---@class game_object
---@field isPvP fun(self: game_object): boolean
---@field in_pvp fun(self: game_object): boolean
---@field inPvP fun(self: game_object): boolean

---@class game_object
---@field isPlayerLike fun(self: game_object): boolean
---@field is_player_or_dummy fun(self: game_object): boolean
---@field isPlayerOrDummy fun(self: game_object): boolean

---@class game_object
---@field isCC fun(self: game_object, min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)
---@field crowd_controlled fun(self: game_object, min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)
---@field isCrowdControlled fun(self: game_object, min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)

---@class game_object
---@field isWeakCC fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field weak_cc fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field rooted fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isRooted fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field stunned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isStunned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field feared fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isFeared fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field sapped fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isSapped fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field silenced fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isSilenced fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field cycloned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isCycloned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field disarmed fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isDisarmed fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field isDisorient fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isDisoriented fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field is_incapacitated fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isIncapacitated fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field dr fun(self: game_object, category: (integer|string), hit_at_sec?: number): number
---@field dr_for fun(self: game_object, category: (integer|string), hit_at_sec?: number): number
---@field getDR fun(self: game_object, category: (integer|string), hit_at_sec?: number): number
---@field DR fun(self: game_object, category: (integer|string), hit_at_sec?: number): number

---@class game_object
---@field dr_time fun(self: game_object, category: (integer|string)): number
---@field drTimeLeft fun(self: game_object, category: (integer|string)): number
---@field getDRTime fun(self: game_object, category: (integer|string)): number

---@class game_object
---@field immune_cc fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isCCImmune fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field cc_reduction fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)
---@field getCCReduce fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)
---@field getCCReduction fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)

---@class game_object
---@field isSlowed fun(self: game_object, threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)
---@field slowed fun(self: game_object, threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)

---@class game_object
---@field slow_mult fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)
---@field getSlow fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)

---@class game_object
---@field slow_immune fun(self: game_object, source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)
---@field isSlowImmune fun(self: game_object, source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)

---@class game_object
---@field getDRPct fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)
---@field dmg_reduction fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)
---@field dmgRed fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)
---@field getDamageReduction fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)

---@class game_object
---@field isImmune fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)
---@field isDamageImmune fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)
---@field immune_dmg fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)

---@class game_object
---@field is_bursting fun(self: game_object, min_remaining_ms?: Milliseconds): boolean
---@field bursting fun(self: game_object, min_remaining_ms?: Milliseconds): boolean
---@field hasBurst fun(self: game_object, min_remaining_ms?: Milliseconds): boolean

---@class game_object
---@field CCText fun(self: game_object, cc_mask: CCFlagMask): string
---@field cc_desc fun(self: game_object, cc_mask: CCFlagMask): string

---@class game_object
---@field DMGText fun(self: game_object, dmg_mask: DMGTypeMask): string
---@field dmg_desc fun(self: game_object, dmg_mask: DMGTypeMask): string

---@class game_object
---@field isPurgable fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
---@field is_purgeable fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
---@field isPurgeable fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
---@field can_be_purged fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
---@field canBePurged fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult

---@class game_object
---@field isDisarmable fun(self: game_object, include_all?: boolean): boolean
---@field can_be_disarmed fun(self: game_object, include_all?: boolean): boolean
---@field canBeDisarmed fun(self: game_object, include_all?: boolean): boolean

-- Cheatsheet
-- local me    = core.object_manager.get_local_player()
-- local enemy = me:get_target() -- just a quick example

-- -- quick flags
-- if enemy:is_stunned() or enemy:is_rooted() then ...
-- if enemy:is_cc() then ... end                         -- any CC
-- if enemy:is_cc_weak() then ... end                    -- breaks on damage

-- -- DR: multiplier and time until DR fully resets
-- local mult = enemy:get_dr("stun")                     -- 1, 0.5, 0.25, 0
-- local tsec = enemy:get_dr_time("stun")

-- -- slow & immunity
-- local slowed = enemy:is_slowed()                      -- true/false
-- local imm_slow = enemy:is_slow_immune()

-- -- damage reduction / immunities
-- local pct, type_mask, rem = enemy:get_damage_reduction()       -- defaults to ANY dmg
-- if enemy:is_damage_immune() then ... end

-- -- CC immunity / reduction (by type)
-- local immune_cc = enemy:is_cc_immune()                -- any CC
-- local cc_pct = select(1, enemy:get_cc_reduction())    -- % reduction (0–100)

-- -- burst windows (offensive cooldowns)
-- if enemy:has_burst() then ... end

-- -- constants for more control
-- if enemy:is_cc(750, enemy.CC.STUN) then ... end
-- if enemy:is_damage_immune(enemy.DMG.MAGICAL) then ... end

-- local enemy = me:get_target()
-- if enemy:is_purgable() then
--   local why = enemy:purge_text()
--   -- e.g., "Magic (Haste, Shield)" for UI
-- end

-- if enemy:is_disarmable() then
--   -- disarm now
-- end

-- local output = enemy:is_purgable()
-- if output.is_purgeable then
-- output.table
-- output.current_remaining_ms
-- evaluate / purge now
-- end

---@alias queue_kind '"none"'|'"pve"'|'"pvp"'

---@class queue_pve_meta
---@field proposal boolean

---@class queue_pvp_slot
---@field idx integer
---@field status any
---@field is_call boolean|nil
---@field expires_at_ms integer|nil

---@class queue_pvp_meta
---@field slots queue_pvp_slot[]

---@class queue_popup_info
---@field kind queue_kind
---@field since_sec number
---@field since_ms integer
---@field age_sec number
---@field age_ms integer
---@field expire_sec number|nil
---@field expire_ms integer|nil
---@field pve queue_pve_meta|nil
---@field pvp queue_pvp_meta|nil

---@class izi_api
---@field set_pvp_queue_provider fun(fn: fun(): queue_pvp_slot[]|nil): nil
---@field queue_popup_info fun(): (boolean, queue_popup_info)    -- has_popup, info
---@field queue_has_popup fun(): boolean
---@field queue_accept fun(kind?: queue_kind, idx?: integer): boolean
---@field queue_decline fun(kind?: queue_kind, idx?: integer): boolean

---@class izi_api
--- Cancel matching buffs on the local player.
--- Accepts a single buff id or a list; throttled with a call window (200ms*mult) and a post-cancel cooldown (400ms*mult).
---@field remove_buff fun(buff_ids: (integer|integer[]), cache_mult?: number): boolean

---@class izi_api
--- Time delta helpers
---@field time_since fun(past_time_in_seconds: number): number       -- Seconds elapsed since past_time
---@field time_since_ms fun(past_time_in_ms: number): number         -- Milliseconds elapsed since past_time (game time)
---@field time_until fun(future_time_in_seconds: number): number     -- Seconds until future_time (0 if past)
---@field time_until_ms fun(future_time_in_ms: number): number       -- Milliseconds until future_time (0 if past, game time)

---@class izi_api
--- Battleground / Arena detection
---@field is_battleground fun(map_id?: integer): boolean             -- True if map_id (or current map) is a BG/Arena
---@field is_bg fun(map_id?: integer): boolean                       -- Alias for is_battleground

--------------------------------------------------------------------------------
-- Geometry (callable + full module access)
--------------------------------------------------------------------------------

---@class izi_api
---@field vec2 vec2|fun(x: number, y: number): vec2
---@field vec3 vec3|fun(x: number, y: number, z: number): vec3
---@field circle circle|fun(center: vec3, radius: number): circle
---@field rectangle rectangle|fun(min: vec3, max: vec3): rectangle
---@field cone cone|fun(origin: vec3, direction: vec3, angle: number, range: number): cone
---@field is_vec2 fun(v: any): boolean
---@field is_vec3 fun(v: any): boolean
---@field is_vector fun(v: any): boolean

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - GEOMETRY
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
--
-- -- Shorthand constructor
-- local pos = izi.vec2(100, 200)
-- local world = izi.vec3(1234, 5678, 90)
--
-- -- Full module access (same as require("common/geometry/vector_2"))
-- local pos2 = izi.vec2.new(100, 200)
-- local dist = izi.vec3.distance(a, b)
--
-- -- Shapes
-- local c = izi.circle(center, 10)
-- local r = izi.rectangle(min, max)
-- local cone = izi.cone(origin, dir, 45, 30)
--
-- -- Validation
-- if izi.is_vec3(world) then ... end

--------------------------------------------------------------------------------
-- Coords / Map Helpers (from izi_game_ui via coords_helper)
--------------------------------------------------------------------------------

---@class izi_api
--- Get 3D world position from current cursor position on minimap.
--- This is the main one-liner function for "click on map, get world pos".
---
--- extra_height parameter controls vertical offset for terrain raycast:
---   nil/default (+4) = same floor as player, safe margin to avoid underground
---   positive (+20, +50) = find upper floors, rooftops, elevated platforms
---   negative (-10, -20) = find basements, lower floors, underground areas
---
--- How it works internally:
---   1. Gets normalized cursor position on minimap
---   2. Converts to world X,Y using C_Map.GetWorldPosFromMapPos
---   3. Raycast starts at (player.z + extra_height) going down
---   4. Returns first terrain hit below that point
---
--- Returns: vec3 world position, or nil + error string on failure
---
--- Error conditions:
---   - Cursor not on minimap
---   - Coords outside valid bounds (x/y > 0.99)
---   - Map ID not available
---   - Conversion failed
---@field get_cursor_world_pos fun(extra_height?: number): vec3|nil, string|nil

---@class izi_api
--- Convert a 2D map position to 3D world position using specified map ID.
--- Lower-level function if you already have map_id and normalized coords.
---
--- param1 map_id number The map ID to use for conversion
--- param2 map_pos vec2 Normalized map position (0-1 range for x and y)
--- param3 extra_height number Vertical offset for terrain raycast (default +4)
--- @return vec3|nil world_pos The 3D world position, or nil on failure
--- @return string|nil error Error message if conversion failed
---@field map_to_world fun(map_id: number, map_pos: vec2, extra_height?: number): vec3|nil, string|nil

---@class izi_api
--- Check if normalized coordinates are within valid map bounds.
--- Returns false if x or y > 0.99 (clicking outside map area).
--- Used internally to prevent far-away markers from edge clicks.
---
--- Param1 Cursor Vec2 = Normalized cursor position
--- @return boolean is_valid True if within bounds
---@field is_valid_map_coords fun(cursor: vec2): boolean

---@class izi_api
--- Get current minimap map ID.
--- @return number|nil map_id The current minimap ID, or nil if not available
---@field get_minimap_id fun(): number|nil

---@class izi_api
--- Get normalized cursor position (0-1 range).
--- @return vec2|nil cursor Normalized cursor position, or nil if not available
---@field get_cursor_normalized fun(): vec2|nil

---@class izi_api
--- Check if cursor is currently over the minimap.
--- @return boolean on_minimap True if cursor is on minimap
---@field is_cursor_on_minimap fun(): boolean

---@class izi_api
--- Get terrain height at a given 2D position.
--- Uses core.get_height_for_position internally.
--- param1 x number World X coordinate
--- param2 y number World Y coordinate
--- @return number height Terrain height at position
---@field get_terrain_height fun(x: number, y: number): number

--------------------------------------------------------------------------------
-- Coords Helper Usage Examples
--------------------------------------------------------------------------------

-- local izi = require("common/izi_sdk")
--
-- -- ONE-LINER: Get world position from map click
-- local world_pos = izi.get_cursor_world_pos()
-- if world_pos then
--     izi.print("Clicked at: ", world_pos.x, ", ", world_pos.y, ", ", world_pos.z)
-- end
--
-- -- extra_height parameter examples:
-- -- Same floor as player (default, safe for most cases)
-- local pos = izi.get_cursor_world_pos()
-- local pos = izi.get_cursor_world_pos(4)  -- equivalent
--
-- -- Find position on building roof (+50 from player height)
-- local roof_pos = izi.get_cursor_world_pos(50)
--
-- -- Find position in basement (-20 from player height)
-- local basement_pos = izi.get_cursor_world_pos(-20)
--
-- -- With error handling
-- local world_pos, err = izi.get_cursor_world_pos()
-- if not world_pos then
--     izi.print("Error: ", err)
--     -- Possible errors:
--     -- "cursor not on minimap"
--     -- "invalid map coords"
--     -- "no map id"
--     -- "conversion failed"
-- end
--
-- -- Check if cursor is on map before processing
-- if izi.is_cursor_on_minimap() then
--     local pos = izi.get_cursor_world_pos()
--     if pos then
--         -- Add marker, teleport, etc.
--     end
-- end
--
-- -- Get terrain height at any position
-- local height = izi.get_terrain_height(1234.5, 5678.9)
--
-- -- Full example: Map click to place marker
-- local VK_LBUTTON = 0x01
-- izi.on_key_release(VK_LBUTTON, function()
--     if not izi.is_cursor_on_minimap() then return end
--     
--     local world_pos = izi.get_cursor_world_pos()
--     if world_pos then
--         -- place_marker(world_pos)
--         izi.print("Marker placed at: ", world_pos.x, ", ", world_pos.y, ", ", world_pos.z)
--     end
-- end)

--------------------------------------------------------------------------------
-- ICON HELPER OPTIONS
--------------------------------------------------------------------------------

--- for icons_helper_draw_opts info look into icons_helper.lua

--------------------------------------------------------------------------------
-- Graphics / Assets / Icons
--------------------------------------------------------------------------------

---@class izi_api
---@field register_zip_pack fun(folder_name: string, zip_url: string, zip_file_name?: string): nil
---@field draw_local_texture fun(data_path: string, position: vec2|vec3, width: number, height: number, tint?: color, is_for_window?: boolean): boolean
---@field draw_http_texture fun(url: string, position: vec2|vec3, width: number, height: number, cache_path?: string, headers?: table<string, string>, tint?: color, is_for_window?: boolean): boolean
---@field load_local_data fun(data_path: string, default_value?: string): string
---@field load_http_data fun(url: string, callback: fun(ok: boolean, data: string, http_code: integer, content_type: string, response_headers: string), headers?: table<string, string>): nil
---@field draw_icon fun(icon_name_or_url: string, position: vec2|vec3, width: number, height: number, tint?: color, is_for_window?: boolean, opts?: icons_helper_draw_opts): boolean
---@field draw_spell_icon fun(spell_id: number, position: vec2|vec3, width: number, height: number, tint?: color, is_for_window?: boolean, opts?: icons_helper_draw_opts): boolean
---@field get_spell_icon_name fun(spell_id: number): string|nil
---@field clear_icon_cache fun(): nil
---@field assets_helper assets_helper
---@field icons_helper icons_helper

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - GRAPHICS / ASSETS / ICONS
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
-- local color = require("common/color")
--
-- -- Register ZIP pack (auto-downloads if missing)
-- izi.register_zip_pack("my_assets", "ps/12345-my_assets.zip")
--
-- -- Draw local texture from scripts_data folder
-- izi.draw_local_texture(
--     "my_assets\\icon.png",
--     izi.vec2(30, 30),
--     64, 64,
--     color.white(255),
--     false
-- )
--
-- -- Draw ZIP virtual texture (auto-downloaded)
-- izi.draw_local_texture(
--     "zip_test_assets\\classicon_paladin.png",
--     izi.vec2(100, 30),
--     64, 64,
--     color.red()
-- )
--
-- -- Draw texture from HTTP URL
-- izi.draw_http_texture(
--     "ps/some_image.png",
--     izi.vec2(200, 30),
--     64, 64
-- )
--
-- -- Draw icon by wowhead slug
-- izi.draw_icon(
--     "classicon-warlock",
--     izi.vec2(300, 30),
--     64, 64,
--     color.purple(),
--     false,
--     { size = "large", persist_to_disk = true }
-- )
--
-- -- Draw icon by direct URL
-- izi.draw_icon(
--     "https://wow.zamimg.com/images/wow/icons/large/classicon_warrior.jpg",
--     izi.vec2(400, 30),
--     64, 64,
--     color.red()
-- )
--
-- -- Draw at world position (vec3 -> w2s internally)
-- local world_pos = izi.vec3(1234, 5678, 90)
-- izi.draw_icon("inv_misc_food_72", world_pos, 32, 32)
--
-- -- Load local data file
-- local json_str = izi.load_local_data("my_config.json", "{}")
--
-- -- Load HTTP data asynchronously
-- izi.load_http_data("ps/my_data.json", function(ok, data, code, content_type, headers)
--     if ok then
--         izi.print("Loaded: ", #data, " bytes")
--     end
-- end)
--
-- -- Clear icon cache
-- izi.clear_icon_cache()

--------------------------------------------------------------------------------
-- Izi Sequences / Spell Sequences
--------------------------------------------------------------------------------

--- All sequence logic (including confirmed_sequence) lives in spell_sequence_helper.
--- izi forwards calls via izi_sequences. More info about datatypes like
--- cast_policy, cast_policy_enum, advanced_spell_entry, advanced_fill_entry,
--- advanced_sequence_opts, confirmed_step, confirmed_sequence_opts:
--- see utility/spell_sequence_helper

---@class izi_api
---@field sequence spell_sequence_helper                                   Direct access to the underlying spell_sequence_helper module
---@field CAST_POLICY cast_policy_enum                                     Cast policy constants
---@field a_into_b fun(spell_a: izi_spell, target_a: game_object, spell_b: izi_spell, target_b: game_object, delay?: number, timeout?: number, debug_name?: string, cooldown?: number): boolean
---@field simple_sequence fun(spells: izi_spell[], targets: game_object[], delay?: number, timeout?: number, debug_name?: string, cooldown?: number): boolean
---@field advanced_sequence fun(entries: advanced_spell_entry[], opts?: advanced_sequence_opts): boolean
---@field confirmed_sequence fun(steps: confirmed_step[], opts?: confirmed_sequence_opts): boolean  Server-confirmed step-by-step sequence
---@field on_spell_cast fun(data: table): nil                              Feed spell cast callback data (filters by local player)
---@field is_sequence_active fun(): boolean                                True if ANY sequence is active (native or confirmed)
---@field is_confirmed_active fun(): boolean                               True if a confirmed sequence is running
---@field cancel_sequence fun(): nil                                       Cancel the active native sequence
---@field cancel_confirmed fun(): nil                                      Cancel the active confirmed sequence
---@field get_sequence_progress fun(): integer|nil, integer|nil            Progress of active sequence (confirmed takes priority)
---@field get_confirmed_progress fun(): integer|nil, integer|nil           Progress of confirmed sequence only
---@field get_sequence_type fun(): string|nil                              "confirmed" | "a_into_b" | "simple" | "advanced" | nil
---@field is_sequence_on_cooldown fun(): boolean                           True if any cooldown active (native or confirmed)
---@field get_sequence_cooldown_remaining fun(): number                    Max remaining cooldown
---@field set_sequence_debug fun(enabled: boolean): nil                    Debug logging for native sequences
---@field get_sequence_debug fun(): boolean                                Get native debug state
---@field set_confirmed_debug fun(enabled: boolean): nil                   Debug logging for confirmed sequences
---@field get_confirmed_debug fun(): boolean                               Get confirmed debug state

-- enums and color
---@class izi_api
---@field enums enums
---@field color color

---@type izi_api
local tbl
return tbl

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - AURAS
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
-- local me = izi.me()
-- local target = izi.target()
--
-- -- Check single buff
-- if me:has_buff(12345) then ... end
-- if me:buff_up(12345) then ... end        -- alias
-- if me:buff_down(12345) then ... end      -- not has_buff
--
-- -- Check multiple buffs (any match)
-- if me:has_buff({12345, 67890}) then ... end
--
-- -- Get buff remaining time
-- local remains = me:buff_remains(12345)           -- seconds
-- local remains_ms = me:buff_remains_ms(12345)     -- milliseconds
--
-- -- Get buff stacks
-- local stacks = me:get_buff_stacks(12345)
--
-- -- Debuffs work the same way
-- if target:has_debuff(12345) then ... end
-- local debuff_remains = target:debuff_remains(12345)
--
-- -- Aura (checks both buffs and debuffs)
-- if target:has_aura(12345) then ... end

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - SPELLS
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
--
-- -- Create spell wrapper
-- local fireball = izi.spell(133)
--
-- -- Check spell state
-- if fireball:is_learned() then ... end
-- if fireball:is_usable() then ... end
-- if fireball:cooldown_up() then ... end
--
-- -- Get cooldown info
-- local cd = fireball:cooldown_remains()      -- seconds
-- local charges = fireball:charges()
--
-- -- Cast spell
-- fireball:cast(target)
-- fireball:cast_safe(target, "Fireball")      -- with safety checks
--
-- -- Cast on best target matching filter
-- fireball:cast_target_if(
--     izi.enemies(40),
--     "min",                                   -- sort mode
--     function(u) return u:get_health_percentage() end,
--     true,                                    -- adv_condition
--     true,                                    -- another_condition
--     3,                                       -- max_attempts
--     "Execute low HP"
-- )
--
-- -- Position cast with prediction
-- local blizzard = izi.spell(190356)
-- blizzard:cast_position(target_pos, "Blizzard", {
--     use_prediction = true,
--     min_hits = 3,
--     aoe_radius = 8
-- })

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - ITEMS
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
--
-- -- Create item wrapper
-- local trinket = izi.item(12345)
--
-- -- Check item state
-- if trinket:is_usable() then ... end
-- if trinket:cooldown_up() then ... end
-- if trinket:equipped() then ... end
-- if trinket:in_inventory() then ... end
--
-- -- Use item
-- trinket:use_self()
-- trinket:use_on(target)
-- trinket:use_at_position(pos)
--
-- -- Safe use with checks
-- trinket:use_self_safe("Using trinket", {skip_gcd = true})
--
-- -- Quick potion usage
-- izi.use_best_health_potion_safe()
-- izi.use_best_mana_potion_safe()

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - EVENTS
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
--
-- -- Subscribe to buff events
-- local unsub_gain = izi.on_buff_gain(function(ev)
--     izi.print("Gained buff: ", ev.buff_id, " on ", ev.unit:get_name())
-- end)
--
-- local unsub_lose = izi.on_buff_lose(function(ev)
--     izi.print("Lost buff: ", ev.buff_id)
-- end)
--
-- -- Subscribe to spell events
-- izi.on_spell_begin(function(ev)
--     izi.print("Spell started: ", ev.spell_id)
-- end)
--
-- izi.on_spell_success(function(ev)
--     izi.print("Spell succeeded: ", ev.spell_id)
-- end)
--
-- -- Key release (cleaner than polling)
-- local VK_LBUTTON = 0x01
-- izi.on_key_release(VK_LBUTTON, function()
--     izi.print("Left mouse released!")
-- end)
--
-- -- Delayed execution
-- local cancel = izi.after(2.0, function()
--     izi.print("2 seconds passed!")
-- end)
-- -- cancel() to abort
--
-- -- Unsubscribe later
-- unsub_gain()

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - UNIT QUERIES
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
-- local me = izi.me()
--
-- -- Get enemies in range
-- local enemies = izi.enemies(40)
-- local enemies_players = izi.enemies(40, true)  -- players only
--
-- -- Get friends in range
-- local friends = izi.friends(40)
-- local party = izi.party(40)
--
-- -- Filtered queries
-- local low_hp_enemies = izi.enemies_if(40, function(u)
--     return u:get_health_percentage() < 30
-- end)
--
-- local injured_friends = izi.friends_if(40, function(u)
--     return u:get_health_percentage() < 80
-- end)
--
-- -- Pick best target
-- local execute_target = izi.pick_enemy(40, false, function(u)
--     return u:get_health_percentage()
-- end, "min")  -- lowest HP
--
-- -- From game_object
-- local nearby_enemies = me:get_enemies_in_range(10)
-- local nearby_melee = me:get_enemies_in_melee_range(5)

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - DEFENSIVE CASTING
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
--
-- local pain_sup = izi.spell(33206)
--
-- local filters = {
--     block_time = 1,                             -- seconds between defensives
--     health_percentage_threshold_raw = 50,       -- cast if HP <= 50%
--     health_percentage_threshold_incoming = 40,  -- cast if predicted HP <= 40%
--     physical_damage_percentage_threshold = 0,   -- min physical damage %
--     magical_damage_percentage_threshold = 0,    -- min magical damage %
-- }
--
-- pain_sup:cast_defensive(target, filters, "Emergency PS")
-- -- or
-- izi.cast_defensive(pain_sup, target, filters, "Emergency PS")

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - TIME TO DIE
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
-- local target = izi.target()
--
-- -- Get TTD from unit
-- local ttd = target:time_to_die()
-- local ttd2 = target:get_time_to_death()  -- alias
--
-- -- Execute logic
-- if ttd < 5 then
--     -- Use execute abilities
-- end
--
-- -- Global TTD
-- local global_ttd = izi.get_time_to_die_global()

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - POWER/RESOURCES
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
-- local me = izi.me()
--
-- -- Mana
-- local mana = me:mana_current()
-- local mana_pct = me:mana_pct()
-- local mana_deficit = me:mana_deficit()
--
-- -- Energy (Rogue/Druid)
-- local energy = me:energy_current()
-- local energy_pct = me:energy_pct()
-- local time_to_max = me:energy_time_to_max()
-- local time_to_80 = me:energy_time_to_x(80)
--
-- -- Combo Points
-- local cp = me:combo_points_current()
-- local cp_max = me:combo_points_max()
--
-- -- Generic power
-- local power = me:power_current(3)  -- power type enum
-- local power_pct = me:power_pct(3)

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - POSITIONING
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
-- local me = izi.me()
-- local target = izi.target()
--
-- -- Distance
-- local dist = target:distance()
-- local dist2 = me:distance_to(target)
--
-- -- Range checks
-- if target:is_in_range(40) then ... end
-- if target:is_in_melee_range(5) then ... end
--
-- -- Line of sight
-- if me:los_to(target) then ... end
-- if me:los_to_position(some_pos) then ... end
--
-- -- Behind checks
-- if me:is_behind(target) then ... end
-- if me:is_behind_future(target, 1.0) then ... end  -- 1 sec prediction
--
-- -- Facing checks
-- if me:is_looking_at(target) then ... end
-- if me:is_looking_at_position(some_pos, 45) then ... end  -- 45 degree arc
--
-- -- Prediction
-- local future_pos = target:predict_position(0.5)  -- 0.5 sec ahead
-- local future_dist = me:predict_distance(0.5, target)

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - CASTING STATE
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
-- local target = izi.target()
--
-- -- Check casting
-- if target:is_casting() then
--     local spell_id = target:get_active_cast_or_channel_id()
--     local remaining = target:get_cast_remaining_ms()
--     local pct = target:get_cast_pct()
-- end
--
-- -- Check channeling
-- if target:is_channeling() then
--     local remaining = target:get_channel_remaining_ms()
-- end
--
-- -- Combined check
-- if target:is_channeling_or_casting() then
--     local remaining = target:get_any_remaining_ms()
-- end

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - DOT SPREAD
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
--
-- local swp = izi.spell(589):track_debuff(589)
--
-- -- Spread to targets missing the debuff
-- izi.spread_dot(
--     swp,
--     izi.enemies(40),    -- targets
--     3000,               -- refresh if < 3000ms remaining
--     3,                  -- max attempts
--     "Spreading SWP"
-- )

--------------------------------------------------------------------------------
-- USAGE EXAMPLES - QUEUE POPUP
--------------------------------------------------------------------------------
-- local izi = require("common/izi_sdk")
--
-- -- Check for dungeon/BG queue popup
-- if izi.queue_has_popup() then
--     local has, info = izi.queue_popup_info()
--     
--     if info.kind == "pve" then
--         izi.print("Dungeon ready! Age: ", info.age_sec, "s")
--         izi.queue_accept()
--     elseif info.kind == "pvp" then
--         izi.print("BG ready!")
--         izi.queue_accept()
--     end
-- end
