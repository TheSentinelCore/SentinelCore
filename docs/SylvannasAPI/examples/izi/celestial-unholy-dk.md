---
title: "Celestial Unholy Death Knight (IZI SDK)"
source: "https://docs.project-sylvanas.net/examples/izi/celestial-unholy-dk"
crawled: "2026-07-14"
---

# Celestial Unholy Death Knight Rotation (IZI SDK)

This example demonstrates how to create a complete, production-ready combat rotation plugin for an Unholy Death Knight using the **IZI SDK**. This is a comprehensive example that showcases advanced rotation techniques including cooldown management, defensive handling, artifact powers, and resource optimization.

> **Advanced Example:** This is a feature-complete rotation example designed for the Unholy Death Knight with Rider of Apocalypse hero tree support. It includes advanced features like Time To Die (TTD) validation, health forecasting, automatic pet management, and Remix Time artifact integration.

## Links

- **[Download from Plugin Marketplace](https://project-sylvanas.net/panel/plugins/detail/287)** - Get the latest version
- **[View Source Code on GitHub](https://github.com/bluesilvi/project-sylvanas/tree/main/izi/celestial_unholy_death_knight)** - Full source code

## What You'll Learn

- **Advanced Cooldown Management** - TTD validation, cooldown tracking, and optimal usage timing
- **Resource Management** - Runic Power and Rune optimization for maximum damage
- **Defensive Automation** - Health forecasting with Anti-Magic Shell, Lichborne, and Icebound Fortitude
- **Pet & Minion Tracking** - Automatic pet summoning and minion state detection
- **Artifact Powers** - Twisted Crusade and Remix Time integration for WoW Remix
- **Disease Management** - Pandemic-aware Virulent Plague and Frost Fever spreading
- **Menu System** - Comprehensive configuration with validators and control panel integration
- **DoT Spreading** - Using `izi.spread_dot()` for multi-target disease application
- **Target Filtering** - Using `izi_spell:cast_target_if()` and `izi_spell:cast_target_if_safe()` for smart target selection
- **AoE vs Single Target** - Dynamic rotation switching based on enemy count

## Recommended Talent Build

This rotation is optimized for AoE scenarios with the following talent string:

```
CwPAclESCN5uIs3wGGVadXqL3BwMDzYmxwMzMzMTDjZMzMGAAAAAAAAmZmZDzYmBAsNDzY2mZmxYGgFzihhMwsxQjFMAzAYA
```

**Hero Tree:** Rider of Apocalypse

## Plugin Structure

This rotation consists of four main files:

1. **header.lua** - Validates class/spec and determines if plugin should load
2. **spells.lua** - Defines all spells with IDs and debuff tracking
3. **menu.lua** - Creates menu interface with validators for rotation logic
4. **main.lua** - Contains the complete rotation logic

### header.lua

```lua
local plugin = {}
plugin.name = "Unholy Death Knight"
plugin.version = "1.0.0"
plugin.author = "Voltz"
plugin.load = true

local local_player = core.object_manager:get_local_player()
if not local_player or not local_player:is_valid() then
    plugin.load = false
    return plugin
end

---@type enums
local enums = require("common/enums")
local player_class = local_player:get_class()
local is_valid_class = player_class == enums.class_id.DEATHKNIGHT

if not is_valid_class then
    plugin.load = false
    return plugin
end

local spec_id = enums.class_spec_id
local player_spec_id = local_player:get_specialization_id()
local is_valid_spec = player_spec_id == spec_id.get_spec_id_from_enum(spec_id.spec_enum.UNHOLY_DEATHKNIGHT)

if not is_valid_spec then
    plugin.load = false
    return plugin
end

return plugin
```

### spells.lua

```lua
local izi = require("common/izi_sdk")
local enums = require("common/enums")
local spell = izi.spell

local BUFFS = enums.buff_db

---@class dk_unholy_spells
local SPELLS ={
    --Damage
    FESTERING_STRIKE = spell(85948),
    FESTERING_SCYTHE = spell(455397, 458128),
    CLAWING_SHADOWS = spell(207311),
    SOUL_REAPER = spell(343294),
    DEATH_COIL = spell(47541),
    EPIDEMIC = spell(207317),
    OUTBREAK = spell(77575),
    DEATH_AND_DECAY = spell(43265),
    DEATH_STRIKE = spell(49998),
    --Cooldowns
    LEGION_OF_SOULS = spell(383269),
    APOCALYPSE = spell(275699),
    RAISE_ABOMINATION = spell(455395),
    UNHOLY_ASSAULT = spell(207289),
    --Remix
    REMIX_TIME = spell(1236723),
    ARTIFACT_TWISTED_CRUSADE = spell(1237711),
    ARTIFACT_TWISTED_CRUSADE_FELSPIKE = spell(1242973),
    --Defensives
    ANTI_MAGIC_SHELL = spell(48707),
    ICEBOUND_FORTITUDE = spell(48792),
    LICHBORNE = spell(49039),
    --Utility
    RAISE_DEAD = spell(46584),
    --Passives (these are just used to check for talents)
    IMPROVED_DEATH_COIL = spell(377580),
    SUPERSTRAIN = spell(390283),
}

--For outbreak we want to track virulent plague for spreading dots with izi.spread_dot
SPELLS.OUTBREAK:track_debuff(BUFFS.VIRULENT_PLAGUE)

return SPELLS
```

### menu.lua

```lua
local m = core.menu
local color = require("common/color")
local key_helper = require("common/utility/key_helper")
local control_panel_utility = require("common/utility/control_panel_helper")

--Constants
local PLUGIN_PREFIX = "celestial_dk_unholy"
local WHITE = color.white(150)
local TTD_MIN = 1
local TTD_MAX = 120
local TTD_DEFAULT = 16
local TTD_DEFAULT_AOE = 20

---Creates an ID with prefix for our rotation so we don't need to type it every time
---@param key string
local function id(key)
    return string.format("%s_%s", PLUGIN_PREFIX, key)
end

---@class unholy_dk_menu
local menu ={
    --Global
    MAIN_TREE = m.tree_node(),
    GLOBAL_CHECK = m.checkbox(true, id("global_toggle")),
    --Keybinds
    KEYBIND_TREE = m.tree_node(),
    ROTATION_KEYBIND = m.keybind(999, false, id("rotation_toggle")),
    --Cooldowns
    COOLDOWNS_TREE = m.tree_node(),
    RAISE_ABOMINATION_TREE = m.tree_node(),
    RAISE_ABOMINATION_CHECK = m.checkbox(true, id("abomination_toggle")),
    RAISE_ABOMINATION_MIN_TTD = m.slider_float(TTD_MIN, TTD_MAX, TTD_DEFAULT, id("abomination_min_ttd")),
    RAISE_ABOMINATION_MIN_TTD_AOE = m.slider_float(TTD_MIN, TTD_MAX, TTD_DEFAULT_AOE, id("abomination_min_ttd_aoe")),
    --Defensives
    DEFENSIVES_TREE = m.tree_node(),
    ANTI_MAGIC_SHELL_TREE = m.tree_node(),
    ANTI_MAGIC_SHELL_CHECK = m.checkbox(true, id("anti_magic_shell_toggle")),
    ANTI_MAGIC_SHELL_MAX_HP = m.slider_int(1, 100, 95, id("anti_magic_shell_max_hp")),
    ANTI_MAGIC_SHELL_FUTURE_HP = m.slider_int(1, 100, 90, id("anti_magic_shell_max_future_hp")),
    --Utility
    UTILITY_TREE = m.tree_node(),
    AUTO_RAISE_DEAD_CHECK = m.checkbox(true, id("auto_raise_dead")),
    AUTO_REMIX_TIME_CHECK = m.checkbox(true, id("auto_remix_time")),
    AUTO_REMIX_TIME_MIN_TIME_STANDING = m.slider_float(0, 15, 2.5, id("auto_remix_time_min_time_standing")),
}

---@alias menu_validator_fn fun(value: number): boolean

---Creates a new validator function validating a checkbox and relevant slider value
---@param checkbox checkbox
---@param slider slider_int|slider_float
---@param type? "min"|"max"|"equal"
---@return menu_validator_fn
function menu.new_validator_fn(checkbox, slider, type)
    type = type or "min"
    return function(value)
        local is_checked = checkbox:get_state()
        if is_checked then
            local slider_value = slider:get()
            if type == "min" then
                return value >= slider_value
            elseif type == "max" then
                return value <= slider_value
            elseif type == "equal" then
                return value == slider_value
            end
        end
        return false
    end
end

--Returns true if the plugin is enabled
---@return boolean enabled
function menu:is_enabled()
    return self.GLOBAL_CHECK:get_state()
end

--Returns true if the plugin and rotation are enabled
---@return boolean enabled
function menu:is_rotation_enabled()
    return self.GLOBAL_CHECK:get_state() and self.ROTATION_KEYBIND:get_toggle_state()
end

--Cooldown Validators
menu.validate_raise_abomination = menu.new_validator_fn(menu.RAISE_ABOMINATION_CHECK, menu.RAISE_ABOMINATION_MIN_TTD)
menu.validate_raise_abomination_aoe = menu.new_validator_fn(menu.RAISE_ABOMINATION_CHECK, menu.RAISE_ABOMINATION_MIN_TTD_AOE)
-- ... (additional validators)

return menu
```

**Key Concept: Validators**

Validators are functions that check if an ability should be used based on menu settings:

```lua
-- Create validator
menu.validate_raise_abomination = menu.new_validator_fn(
    menu.RAISE_ABOMINATION_CHECK,  -- Is checkbox enabled?
    menu.RAISE_ABOMINATION_MIN_TTD -- Minimum TTD value
)

-- Use in rotation
local ttd = target:time_to_die()
if menu.validate_raise_abomination(ttd) then
    -- TTD is >= configured minimum, safe to use cooldown
end
```

## Core Rotation Features

### 1. Time To Die (TTD) Validation

The rotation uses TTD to determine if cooldowns should be used:

```lua
--Get TTD to check if we should use CDs
local ttd = target:time_to_die()
local raise_abomination_valid = menu.validate_raise_abomination(ttd)

--Cast Raise Abomination only if TTD is sufficient
if raise_abomination_valid and SPELLS.RAISE_ABOMINATION:cast_safe() then
    return true
end
```

**TTD Benefits:**
- Prevents wasting cooldowns on targets that will die quickly
- Separate thresholds for single target vs AoE scenarios
- Configurable per-ability for fine-tuned control

For AoE scenarios, use `izi.get_time_to_die_global()` to get the average TTD across all targets.

### 2. Minion Tracking

```lua
---Returns true if the unit has a minion with the given NPC ID
---@param unit game_object
---@param npc_id number
---@return boolean has_minion
local function unit_has_minion(unit, npc_id)
    local minions = unit:get_all_minions()
    for i = 1, #minions do
        local minion = minions[i]
        if minion:get_npc_id() == npc_id then
            return true
        end
    end
    return false
end

---Checks if the unit has an abomination active
---@param unit game_object
---@return boolean abomination_active
local function unit_has_abomination(unit)
    local abomination_npc_id = 149555
    return unit_has_minion(unit, abomination_npc_id)
end
```

**Usage in Rotation:**

```lua
--While Raise Abomination is active, you only cast Festering Strike when you are at 0 Festering Wounds
local has_abomination = unit_has_abomination(me)
local maximum_festering_wounds = has_abomination and 0 or 2
local should_festering_strike = target_festering_wound_stacks <= maximum_festering_wounds
```

### 3. Pandemic Disease Management

```lua
--Calculate the pandemic value for VIRULENT_PLAGUE
local VIRULENT_PLAGUE_PANDEMIC_THRESHOLD_SEC = 13.5 * 0.30
local VIRULENT_PLAGUE_PANDEMIC_THRESHOLD_MS = VIRULENT_PLAGUE_PANDEMIC_THRESHOLD_SEC * 1000

--Cast Outbreak if Virulent Plague can be refreshed (pandemic)
if target:debuff_remains_sec(BUFFS.VIRULENT_PLAGUE) < VIRULENT_PLAGUE_PANDEMIC_THRESHOLD_SEC then
    local should_apply_plague = not apocalypse_ready_soon and not raise_abomination_ready_soon
    if should_apply_plague then
        if SPELLS.OUTBREAK:cast_safe(target, "Refreshing Virulent Plague") then
            return true
        end
    end
end
```

**Pandemic Mechanics:**
- Refreshing DoTs early extends duration instead of overwriting
- Optimal refresh window is 30% of base duration
- Prevents wasting GCDs on unnecessary refreshes

### 4. DoT Spreading with IZI

```lua
--In spells.lua - Enable DoT tracking
SPELLS.OUTBREAK:track_debuff(BUFFS.VIRULENT_PLAGUE)

--In main.lua - Spread diseases to targets missing them
if izi.spread_dot(SPELLS.OUTBREAK, enemies, VIRULENT_PLAGUE_PANDEMIC_THRESHOLD_MS, nil, "Spread Plague") then
    return true
end
```

**How spread_dot Works:**
- Automatically finds targets missing the tracked debuff
- Respects pandemic thresholds for efficient refreshing
- Prioritizes targets based on remaining duration
- Only casts if a valid target is found

### 5. Defensive Automation with Health Forecasting

```lua
---@type defensive_filters
local anti_magic_shell_filters ={
    health_percentage_threshold_raw = menu.ANTI_MAGIC_SHELL_MAX_HP:get(),
    health_percentage_threshold_incoming = menu.ANTI_MAGIC_SHELL_FUTURE_HP:get(),
    magical_damage_percentage_threshold = 15,
}

if SPELLS.ANTI_MAGIC_SHELL:cast_defensive(me, anti_magic_shell_filters, "Anti-Magic Shell", { skip_gcd = true }) then
    return true
end
```

**Defensive Filter Options:**
- `health_percentage_threshold_raw` - Current HP threshold
- `health_percentage_threshold_incoming` - Forecasted HP threshold
- `magical_damage_percentage_threshold` - Minimum magical damage required
- `block_time` - Time window for damage prediction (seconds)

`cast_defensive()` analyzes incoming damage and predicts future health:
1. Checks current HP against `health_percentage_threshold_raw`
2. Forecasts HP after `block_time` seconds of current damage rate
3. Casts if either threshold is met and damage type matches

### 6. Target Selection with cast_target_if

```lua
---Filter function returns a value to compare
---@param enemy game_object
---@return number|nil
local function festering_wound_filter(enemy)
    if enemy:has_debuff(BUFFS.FESTERING_WOUND) then
        return enemy:get_debuff_stacks(BUFFS.FESTERING_WOUND)
    end
end

--Cast Apocalypse on the target with the least Festering Wounds
if apocalypse_valid and SPELLS.APOCALYPSE:cast_target_if_safe(enemies, "min", festering_wound_filter) then
    return true
end

--Cast Clawing Shadows if any target has a Festering Wound prioritizing the highest stack
if SPELLS.CLAWING_SHADOWS:cast_target_if_safe(enemies, "max", festering_wound_filter) then
    return true
end
```

**Target Selection Modes:**
- `"min"` - Select target with lowest filter value
- `"max"` - Select target with highest filter value

**Filter Function:**
- Returns a number to compare (or `nil` to skip target)
- IZI automatically finds the best target based on mode
- Validates target is castable before selecting

### 7. Artifact Powers (Remix Time)

The rotation includes automatic Remix Time usage to refresh cooldowns:

```lua
--Automatically remix time if cooldowns are not active and are on cooldown
local last_movement = time_since_last_movement_sec()

--Check if player has artifact trait that allows casting while moving
local can_cast_while_moving = me:has_aura(REMIX_CASTING_MOVE_BUFF_IDS)

--Check if we should remix time
local remix_time_valid = can_cast_while_moving or menu.validate_remix_time(last_movement)

if remix_time_valid then
    --Check cooldowns are active
    local has_legion_of_souls = me:has_buff(BUFFS.LEGION_OF_SOULS)
    local has_abomination = unit_has_abomination(me)
    local has_apocalypse = unit_has_apocalypse(me)
    local has_unholy_assault = me:has_buff(BUFFS.UNHOLY_ASSAULT)
    local has_twisted_crusade = me:has_buff(SPELLS.ARTIFACT_TWISTED_CRUSADE:id())

    --Make sure no cooldowns are active
    local cooldowns_inactive =
        not has_legion_of_souls and not has_abomination
        and not has_apocalypse and not has_unholy_assault
        and not has_twisted_crusade

    if cooldowns_inactive then
        --Get the cooldown remaining time for each CD
        local abomination_cooldown_sec = SPELLS.RAISE_ABOMINATION:cooldown_remains()
        local legion_of_souls_cooldown_sec = SPELLS.LEGION_OF_SOULS:cooldown_remains()
        local apocalypse_cooldown_sec = SPELLS.APOCALYPSE:cooldown_remains()
        local unholy_assault_cooldown_sec = SPELLS.UNHOLY_ASSAULT:cooldown_remains()
        local twisted_crusade_cooldown_sec = SPELLS.ARTIFACT_TWISTED_CRUSADE:cooldown_remains()

        --Get the highest cooldown remaining time
        local max_cooldown_sec = math.max(
            abomination_cooldown_sec,
            legion_of_souls_cooldown_sec,
            apocalypse_cooldown_sec,
            unholy_assault_cooldown_sec,
            twisted_crusade_cooldown_sec
        )

        --Check if the highest cooldown remaining time is greater than or equal to the minimum cooldown time
        local should_remix_time = max_cooldown_sec >= MINIMUM_COOLDOWN_SEC

        if should_remix_time then
            if SPELLS.REMIX_TIME:cast_safe(nil, "Remix Time (Refresh Cooldowns)") then
                return true
            end
        end
    end
end
```

**Twisted Crusade:**

```lua
--Cast Twisted Crusade Felspike before it falls off
local twisted_crusade_id = SPELLS.ARTIFACT_TWISTED_CRUSADE:id()
local has_twisted_crusade = me:has_buff(twisted_crusade_id)
if has_twisted_crusade then
    --Get the current GCD and account for ping to determine if we should cast Felspike
    local minimum_twisted_crusade_remaining_sec = gcd + ping_sec
    local twisted_crusade_remaining_sec = me:buff_remains_sec(twisted_crusade_id)
    --If the remaining duration of Twisted Crusade is less than the minimum required duration, cast Felspike
    if twisted_crusade_remaining_sec < minimum_twisted_crusade_remaining_sec then
        if SPELLS.ARTIFACT_TWISTED_CRUSADE_FELSPIKE:cast() then
            return true
        end
    end
end
```

## Single Target Rotation Priority

1. **Raise Abomination** - If TTD validation passes
2. **Legion of Souls** - If TTD validation passes
3. **Build Festering Wounds** - If Apocalypse is ready soon, build to 4 stacks
4. **Apocalypse** - With 4 Festering Wounds
5. **Unholy Assault** - If Apocalypse minions are active
6. **Outbreak** - If diseases need refreshing (pandemic) and cooldowns aren't ready soon
7. **Festering Scythe** - Off cooldown
8. **Soul Reaper** - If target is below 35% HP or will be when expires
9. **Death Coil** - With 80+ Runic Power or Sudden Doom proc
10. **Clawing Shadows** - With Festering Wounds and Rotten Touch
11. **Festering Strike** - With 2 or fewer Festering Wounds (0 with Abomination)
12. **Death Coil** - To refresh Death Rot before it expires
13. **Clawing Shadows** - With 3+ Festering Wounds
14. **Death Coil** - Fallback filler

## AoE Rotation Priority

**Building Phase (No Death and Decay):**
1. Festering Scythe - Off cooldown
2. Soul Reaper - On target below 35% HP (prioritize lowest HP)
3. Raise Abomination - If TTD validation passes
4. Legion of Souls - If TTD validation passes
5. Apocalypse - On target with least Festering Wounds
6. Unholy Assault - If TTD validation passes
7. Clawing Shadows - If Plaguebringer is not active
8. Outbreak - Spread diseases with `izi.spread_dot()`
9. Clawing Shadows - On target with Trollbane's Chains of Ice
10. Epidemic/Death Coil - With less than 4 Runes or Sudden Doom
11. Death and Decay - Place under enemies

**Burst Phase (Death and Decay Active):**
1. Unholy Assault - If TTD validation passes
2. Epidemic/Death Coil - With Sudden Doom proc
3. Clawing Shadows - On target with most Festering Wounds
4. Epidemic/Death Coil - If no targets have Festering Wounds
5. Clawing Shadows - Fallback
6. Epidemic/Death Coil - Fallback filler

**Epidemic vs Death Coil:**

```lua
--Switch to Epidemic at 3+ targets, 4+ with Improved Death Coil
local has_improved_death_coil = SPELLS.IMPROVED_DEATH_COIL:is_learned()
local minimum_epidemic_targets = has_improved_death_coil and 4 or 3
local virulent_plague_enemies = izi.enemies_if(8, function(enemy)
    return enemy:has_debuff(BUFFS.VIRULENT_PLAGUE)
end)
local epidemic_or_death_coil = #virulent_plague_enemies >= minimum_epidemic_targets
    and SPELLS.EPIDEMIC or SPELLS.DEATH_COIL
```

## Main Update Loop

### Update Loop Structure

```lua
core.register_on_update_callback(function()
    --Check if the rotation is enabled
    if not menu:is_enabled() then
        return
    end

    --Get the local player
    local me = izi.me()

    --Check if the local player exists and is valid
    if not (me and me.is_valid and me:is_valid()) then
        return
    end

    --Update our commonly used values
    ping_ms = core.get_ping()
    ping_sec = ping_ms / 1000
    game_time_ms = izi.now_game_time_ms()
    gcd = me:gcd()
    runic_power = me:get_power(enums.power_type.RUNICPOWER)
    runes = me:get_power(enums.power_type.RUNES)

    --Update the local player's last movement time
    if me:is_moving() then
        last_movement_time_ms = game_time_ms
    end

    --Update the local player's last mounted time
    if me:is_mounted() then
        last_mounted_time_ms = game_time_ms
        return
    end

    --Delay actions after dismounting
    local time_dismounted_ms = time_since_last_dismount_ms()
    if time_dismounted_ms < DISMOUNT_DELAY_MS then
        return
    end

    --If the rotation is paused let's return early
    if not menu:is_rotation_enabled() then
        return
    end

    --Get enemies that are in combat within 30 yards
    local enemies = me:get_enemies_in_range(30)

    --Get enemies within melee range
    local enemies_melee = me:get_enemies_in_melee_range(8)

    --Check if we are in an AoE scenario
    local is_aoe = #enemies > 1

    --Execute our utils
    if utility(me) then
        return
    end

    --Get target selector targets
    local targets = izi.get_ts_targets()

    --Iterate over targets and run rotation logic on each one
    for i = 1, #targets do
        local target = targets[i]

        --Check if the target is valid otherwise skip it
        if not (target and target.is_valid and target:is_valid()) then
            goto continue
        end

        --If the target is immune to any damage, skip it
        if target:is_damage_immune(target.DMG.ANY) then
            goto continue
        end

        --If the target is in a CC that breaks from damage, skip it
        if target:is_cc_weak() then
            goto continue
        end

        --Execute our defensives
        if defensives(me, target) then
            return
        end

        --Execute artifact powers (Remix)
        if artifact_powers(me, target, is_aoe) then
            return
        end

        --Damage rotation
        if is_aoe then
            if aoe(me, target, enemies, enemies_melee) then
                return
            end
        else
            if single_target(me, target) then
                return
            end
        end

        ::continue::
    end
end)
```

### Key Design Patterns

#### Pattern 1: Early Exit Strategy
```lua
if not condition then
    return
end
```
Reduces nesting depth and saves CPU by exiting as early as possible.

#### Pattern 2: Single Responsibility Functions
```lua
if utility(me) then return end
if defensives(me, target) then return end
if artifact_powers(me, target, is_aoe) then return end
```
Each function handles one aspect of rotation.

#### Pattern 3: Cached State
```lua
local ping_ms = core.get_ping()
local runic_power = me:get_power(enums.power_type.RUNICPOWER)
```
Single API call per tick instead of multiple.

#### Pattern 4: Priority-Based Execution
```lua
if most_important_action() then return end
if important_action() then return end
if filler_action() then return end
```
Clear priority hierarchy with first successful cast exiting loop.

### Common Pitfalls to Avoid

- **Don't Call Expensive Functions Repeatedly** - Cache values like `get_power()`, `get_ping()`, `gcd()` at the start of the update loop.
- **Don't Forget Target Validation** - Always validate targets before attempting to cast.
- **Use Early Returns** - Structure your code with early returns for invalid states.
- **Target Selector Prioritization** - `izi.get_ts_targets()` returns targets in priority order. Loop through them.

## Menu System Architecture

### Validator Pattern

The menu uses a validator pattern for clean rotation logic:

```lua
--Create validator function
menu.validate_apocalypse = menu.new_validator_fn(
    menu.APOCALYPSE_CHECK,      -- Checkbox: is feature enabled?
    menu.APOCALYPSE_MIN_TTD     -- Slider: minimum TTD threshold
)

--Use in rotation
local ttd = target:time_to_die()
if menu.validate_apocalypse(ttd) then
    -- Checkbox is enabled AND ttd >= threshold
    if SPELLS.APOCALYPSE:cast_safe() then
        return true
    end
end
```

**Validator Types:**
- `"min"` - Value must be >= slider (default)
- `"max"` - Value must be <= slider
- `"equal"` - Value must == slider

### Control Panel Integration

```lua
core.register_on_render_control_panel_callback(function()
    local rotation_toggle_key = M.ROTATION_KEYBIND:get_key_code()
    local rotation_toggle ={
        name = string.format("[Celestial] Enabled (%s)", key_helper:get_key_name(rotation_toggle_key)),
        keybind = M.ROTATION_KEYBIND,
    }
    local control_panel_elements = {}
    if M:is_enabled() then
        control_panel_utility:insert_toggle_(control_panel_elements, rotation_toggle.name, rotation_toggle.keybind, false)
    end
    return control_panel_elements
end)
```

## Performance Optimizations

### Early Returns

```lua
if not menu:is_enabled() then return end
if not (me and me.is_valid and me:is_valid()) then return end
if time_since_last_dismount_ms() < DISMOUNT_DELAY_MS then return end
```

### Conditional Cooldown Checks

```lua
--Only check TTD if spell is actually off cooldown
if SPELLS.SOUL_REAPER:cooldown_up() then
    if should_soul_reaper(target) then
        if SPELLS.SOUL_REAPER:cast_safe(target) then
            return true
        end
    end
end
```

This avoids calling health prediction when the spell couldn't be cast anyway.

## Tips

- **Start Simple** - Begin with basic rotation logic and gradually add features like TTD validation and defensive automation.
- **Use Validators** - The validator pattern keeps menu configuration separate from rotation logic, making both easier to maintain.
- **Cache Values** - Store frequently accessed values in variables updated once per tick.
- **Early Returns** - Use early returns to avoid deep nesting and improve readability.
- **Single Responsibility** - Break rotation into focused functions (defensives, utility, damage).

## Conclusion

This Celestial Unholy Death Knight rotation demonstrates advanced plugin development with the IZI SDK. Key takeaways:

- **TTD Validation** prevents wasting cooldowns on dying targets
- **Health Forecasting** enables proactive defensive usage
- **Validator Pattern** cleanly separates configuration from logic
- **Cached State** optimizes performance by reducing API calls
- **Early Exit Strategy** keeps code readable and performant

The IZI SDK provides powerful abstractions that make complex rotation logic manageable while maintaining full control when needed.

— Voltz
