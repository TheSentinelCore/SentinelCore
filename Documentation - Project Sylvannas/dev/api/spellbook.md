---
title: "Spell Book - Raw Functions"
source: "https://docs.project-sylvanas.net/dev/api/spellbook"
crawled: "2026-07-14"
---

# Spell Book - Raw Functions

## Overview

The `spell_book` module provides a comprehensive set of methods to interact with spells in your scripts. You can use these functions to query spell cooldowns, retrieve spell names, check if a spell is equipped, etc. However, same like with the Input module, using the raw functions directly might not be the best idea in most cases. For example, to check if a spell is castable, you would need to first check if the spell is equipped, if the spell is on cooldown, then range... As you can see, this is going to become an annoying task in most of your scripts. To make your life easier and centralize code as much as possible so the amount of bugs is reduced, we developed the Spell helper module.

> **tip**: Check the Spell helper module after checking the raw functions, provided below.

## Functions

### General Functions

### `get_specialization_id()`

Returns the specialization ID of the local player.

Returns: *number* — The specialization ID.

> **note**: This function is specially useful to decide whether to load or not your script. Here is an example to properly avoid loading scripts when they are not necessary (for example, your script is for rogues and the user is playing a monk).

```lua
--- this is the HEADER file
local plugin_info = require("plugin_info")
local plugin = {}
plugin["name"] = plugin_info.plugin_load_name
plugin["version"] = plugin_info.plugin_version
plugin["author"] = plugin_info.author

-- by default, we load the plugin always
plugin["load"] = true

-- if there is no local player (eg. user injected before being in-game or is in loading screen) then
-- we don't load the script
local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

-- we check if the class that is being played currently matches our script's intended class
local enums = require("common/enums")
local player_class = local_player:get_class()
local is_valid_class = player_class == enums.class_id.ROGUE
if not is_valid_class then
    plugin["load"] = false
    return plugin
end

-- then, we check if the spec id that is being currently played matches our script's intended spec
local player_spec_id = core.spell_book.get_specialization_id()
local is_valid_spec_id = player_spec_id == 3
if not is_valid_spec_id then
    plugin["load"] = false
    return plugin
end

return plugin
```

---

### Cooldowns and Charges

### `get_global_cooldown()`

Returns the duration of the global cooldown, which is the time between casting spells.

Returns: *number* — The global cooldown duration in seconds.

---

### `get_spell_cooldown(spell_id)`

Returns the cooldown duration of the specified spell in seconds.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *number* — The cooldown duration in seconds.

---

### `get_spell_charge(spell_id)`

Returns the current number of charges available for the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *integer* — The current number of charges.

---

### `get_spell_charge_max(spell_id)`

Returns the maximum number of charges available for the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *integer* — The maximum number of charges.

---

### `get_spell_charge_cooldown_start_time(spell_id)`

Returns the start time of the cooldown for a spell's charge.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *number* — The timestamp when the cooldown started.

---

### `get_spell_charge_cooldown_duration(spell_id)`

Returns the duration of the cooldown for a spell's charge.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *number* — The cooldown duration in seconds.

---

### `get_spell_cooldown_information(spell_id)`

Returns detailed cooldown information for a spell, including start time, total duration, and whether the cooldown is active.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *table* — A table containing cooldown details.

**`spell_cooldown_info` Properties:**

| Field | Type | Description |
|-------|------|-------------|
| `start_time` | `number` | The game time when the cooldown started |
| `duration` | `number` | The total duration of the cooldown in seconds |
| `enabled` | `boolean` | Whether the cooldown is currently active/enabled |

```lua
local cd_info = core.spell_book.get_spell_cooldown_information(12345)
if cd_info.enabled then
    local remaining = (cd_info.start_time + cd_info.duration) - core.game_time()
    core.log("Cooldown remaining: " .. string.format("%.1f", remaining / 1000) .. "s")
else
    core.log("Spell is ready!")
end
```

---

### Spell Information

### `get_spell_name(spell_id)`

Returns the name of the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *string* — The name of the spell.

---

### `get_spell_description(spell_id)`

Retrieves the tooltip text of the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *string* — The tooltip text.

---

### `get_buff_description(buff_ptr)`

> **Deprecated**: This function is deprecated after 03/2026. It will only return point values as strings. Use `buff.points` directly instead for accessing aura variable data (e.g. absorb remaining for shields).

Retrieves the tooltip text of a specific buff.

Parameters:
- **`buff_ptr`** (*buff*) — The buff object to get the description for.

Returns: *string* — The buff tooltip text.

---

### `get_spells()`

Returns a table containing all spells and their corresponding IDs.

Returns: table — A table mapping spell IDs to spell names.

---

### `has_spell(spell_id)`

Checks if the specified spell is equipped.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *boolean* — `true` if the spell is equipped; otherwise, `false`.

---

### `is_spell_learned(spell_id)`

Determines if the specified spell is learned.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *boolean* — `true` if the spell is learned; otherwise, `false`.

Note: `is_spell_learned` is more reliable than `has_spell` for checking talents.

---

### `is_spell_known(spell_id)`

Checks if the specified spell is known by the local player.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *boolean* — `true` if the spell is known; otherwise, `false`.

---

### `is_usable_spell(spell_id)`

Determines whether the specified spell can be cast at the current moment.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *boolean* — `true` if the spell is usable; otherwise, `false`.

---

### `is_important_spell(spell_id)`

Checks if a spell is flagged as important.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *boolean* — `true` if the spell is flagged as important; otherwise, `false`.

---

### `is_current_spell(spell_id)`

Checks if the specified spell is the one currently being cast.

Parameters:
- **`spell_id`** (*number*) — The ID of the spell.

Returns: *boolean* — `true` if the spell is currently being cast; otherwise, `false`.

---

### `spell_has_attribute(spell_id, n, flag)`

Checks if a spell has a specific attribute flag set.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.
- **`n`** (*integer*) — The attribute index.
- **`flag`** (*integer*) — The attribute flag to check.

Returns: *boolean* — `true` if the spell has the specified attribute; otherwise, `false`.

---

### `get_base_spell_id(spell_id)`

Returns the base (original) spell ID for a given spell. Useful for spells that get replaced by talents or other effects but still share a base identity.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *integer* — The base spell ID.

---

### `get_spell_required_aura(spell_id)`

Returns the required aura spell ID for a spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *integer* — The required aura spell ID.

---

### `get_override_spell_id(spell_id)`

Returns the override spell ID (e.g. talent-modified version).

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *integer* — The override spell ID.

---

### `get_spell_cast_count(spell_id)`

Returns the current cast count for a spell.

Parameters:
- **`spell_id`** (*number*) — The ID of the spell.

Returns: *number* — The cast count.

---

### `get_assisted_spell_id(target)`

Returns the spell ID that the engine recommends for assisting the given target.

Parameters:
- **`target`** (*game_object*) — The target game object.

Returns: *number* — The assisted spell ID.

---

### Spell Costs

### `get_spell_costs(spell_id)`

Returns a table containing the power cost details of the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *table* — A table containing power cost details.

**`spell_cost` Properties:**
- `min_cost`: Minimum cost required to cast the spell.
- `cost`: Standard cost to cast the spell.
- `cost_per_sec`: Cost per second if the spell is channeled.
- `cost_type`: Type of resource used (e.g., mana, energy).
- `required_buff_id`: ID of any buff required to modify the cost.

> **warning**: Do not use this function, as it returns a table that needs to be handled in a specific way. We still provide its functionality, but in general you wouldn't want to use it.

---

### Spell Range and Damage

### `get_spell_range_data(spell_id)`

Returns a table containing the minimum and maximum range of the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *table* — A table with `min_range` and `max_range`.

**Range Data Properties:**
- `min_range`: Minimum distance required to cast the spell.
- `max_range`: Maximum distance within which the spell can be cast.

---

### `get_spell_min_range(spell_id)`

Returns the minimum range of the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *number* — The minimum range.

---

### `get_spell_max_range(spell_id)`

Returns the maximum range of the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *number* — The maximum range.

---

### `is_spell_in_range(spell_id, target, caster)`

Checks whether a spell is in range from a specified caster to a target. If `caster` is not provided, it defaults to the local player. If `target` is not provided, it defaults to the current target of the local player.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell to check.
- **`target`** (*game_object*, optional) — The target game object to check range against. Defaults to the current target if omitted.
- **`caster`** (*game_object*, optional) — The caster game object. Defaults to the local player if omitted.

Returns: *boolean* — `true` if the target is within range for the specified spell; otherwise, `false`.

---

### `get_spell_damage(spell_id)`

Retrieves the damage value of the specified spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *number* — The damage value.

---

### Casting Types

### `is_melee_spell(spell_id)`

Determines if the specified spell is of melee type.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *boolean* — `true` if the spell is melee type; otherwise, `false`.

---

### `is_spell_position_cast(spell_id)`

Checks if the specified spell is a skillshot (position-cast spell).

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *boolean* — `true` if the spell is a skillshot; otherwise, `false`.

---

### `cursor_has_spell()`

Checks if the cursor is currently busy with a skillshot.

Returns: *boolean* — `true` if the cursor is busy; otherwise, `false`.

---

### `get_spell_school(spell_id)`

Determines the school of magic for a given spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *number* — The school of the spell (e.g., arcane, fire, shadow).

---

### `get_spell_cast_time(spell_id)`

Returns the cast time required for a specific spell.

Parameters:
- **`spell_id`** (*integer*) — The ID of the spell.

Returns: *number* — The spell's cast time in seconds.

---

### Talents

### `get_talent_name(talent_id)`

Returns the name of the specified talent.

Parameters:
- **`talent_id`** (*integer*) — The ID of the talent.

Returns: *string* — The name of the talent.

---

### `get_talent_spell_id(talent_id)`

Returns the spell ID associated with the specified talent.

Parameters:
- **`talent_id`** (*integer*) — The ID of the talent.

Returns: *number* — The spell ID.

---

### Item Functions

### `is_item_usable(item_id)`

Checks whether a specific item can be used at the current moment.

Parameters:
- **`item_id`** (*integer*) — The ID of the item.

Returns: *boolean* — `true` if the item is usable; otherwise, `false`.

---

### `has_item_range(item_id)`

Checks whether an item has a built-in range definition (e.g., targetable items). The engine resolves the item's underlying "use spell" and reports if range data exists.

Parameters:
- **`item_id`** (*integer*) — The ID of the item.

Returns: *boolean* — `true` if the item supports range checking; otherwise, `false`.

---

### `is_item_in_range(item_id, target)`

Checks whether an item can be used on a target with respect to range. Internally maps the item to its "use spell" and performs a spell range check.

Parameters:
- **`item_id`** (*integer*) — The ID of the item.
- **`target`** (*game_object*, optional) — The target game object. If omitted, the engine may default to the current target.

Returns: *boolean* — `true` if the target is in range for this item; otherwise, `false`.

---

### Pet Functions

### `get_pet_mode()`

Retrieves the current mode of the player's pet.

Returns: *number* — The pet's current mode (e.g., passive, aggressive).

---

### `get_pet_spells()`

Returns a table of spells available to the player's pet.

Returns: *table* — A table containing the pet's spell IDs and names.

---

### `get_pet_action_info(spell_id)`

Returns detailed information about a pet action.

Parameters:
- **`spell_id`** (*integer*) — The ID of the pet action spell.

Returns: *table* — A table containing pet action information.

**`pet_action_info` Properties:**
- `name`: (*string*) The name of the pet action.
- `texture`: (*string*) The texture path of the pet action icon.
- `is_active`: (*boolean*) Whether the pet action is currently active.
- `autocast_allowed`: (*boolean*) Whether autocast is allowed for this action.
- `autocast_enabled`: (*boolean*) Whether autocast is currently enabled for this action.

---

### `get_pet_happiness()`

Retrieves the current pet happiness information. Returns a table with the pet's happiness level, damage modifier, and loyalty rate.

Returns: *table* — A table containing the following fields:

**`pet_happiness_data` Properties:**
- `happiness`: (*integer*) The pet happiness level.
- `damage_percentage`: (*number*) The pet damage percentage modifier.
- `loyalty_rate`: (*number*) The pet loyalty rate.

```lua
local pet_data = core.spell_book.get_pet_happiness()
if pet_data then
    core.log("Happiness: " .. tostring(pet_data.happiness))
    core.log("Damage %: " .. tostring(pet_data.damage_percentage))
    core.log("Loyalty Rate: " .. tostring(pet_data.loyalty_rate))
end
```

---

### Mounts

### `get_mount_count()`

Returns the total number of mounts available to the player.

Returns: *integer* — The number of available mounts.

---

### `get_mount_info(mount_index)`

Returns detailed information about a specific mount.

Parameters:
- **`mount_index`** (*integer*) — The index of the mount.

Returns: *table|nil* — A table containing information about the mount, or `nil` if the index is invalid.

**`mount_info` Properties:**
- `mount_name`: (*string*) The name of the mount.
- `spell_id`: (*integer*) The spell ID associated with the mount.
- `mount_id`: (*integer*) The unique ID of the mount.
- `is_active`: (*boolean*) Whether the mount is currently active.
- `is_usable`: (*boolean*) Whether the mount is usable.
- `mount_type`: (*integer*) The type/category of the mount.

---

### `core.spell_book.get_gliding_info`

```
core.spell_book.get_gliding_info() -> gliding_info
```

Returns:
- `gliding_info`: A table containing gliding state and speed information.

**`gliding_info` Properties:**
- `is_gliding`: (*boolean*) Whether the local player is currently gliding.
- `can_glide`: (*boolean*) Whether the local player can currently glide.
- `forward_speed`: (*number*) The current forward speed in yards per second.

Description: Returns the local player's live gliding or skyriding state and current forward speed. This uses the client gliding info directly and is more current than `game_object:get_glide_speed()` while gliding.

**Example Usage**

```lua
local gliding = core.spell_book.get_gliding_info()
if gliding.is_gliding then
    core.log("Forward glide speed: " .. tostring(gliding.forward_speed))
end
```

---

### Totem Functions

### `get_totem_info(index)`

Returns information about a totem in the given slot.

Parameters:
- **`index`** (*integer*) — The totem slot index (1–4). Corresponds to the totem slot (e.g., Fire, Earth, Water, Air).

Returns: *table* — A table containing totem information.

**`totem_info` Properties:**
- `have_totem`: (*boolean*) Whether the totem exists in this slot.
- `totem_name`: (*string*) Name of the totem.
- `start_time`: (*number*) Start time of the totem.
- `duration`: (*number*) Duration of the totem.

```lua
for i = 1, 4 do
    local totem = core.spell_book.get_totem_info(i)
    if totem and totem.have_totem then
        core.log("Slot " .. i .. ": " .. totem.totem_name .. " (duration: " .. totem.duration .. ")")
    end
end
```

---

### Rune Functions (Death Knight)

### `get_rune_type(index)`

Returns the type of the rune at the given index.

Parameters:
- **`index`** (*integer*) — The rune index.

Returns: *integer* — The rune type: `1` = Blood, `2` = Unholy, `3` = Frost, `4` = Death.

---

### `is_rune_slot_active(index)`

Checks if the rune at the given index is currently active (not on cooldown).

Parameters:
- **`index`** (*integer*) — The rune index.

Returns: *boolean* — `true` if the rune is active; otherwise, `false`.

---

### `get_rune_info(slot)`

Retrieves detailed cooldown information for the rune in the given slot.

Parameters:
- **`slot`** (*integer*) — The rune slot (1–6).

Returns: *table* — A table containing rune cooldown info.

**`rune_info` Properties:**
- `start`: (*number*) Cooldown start time in seconds.
- `duration`: (*number*) Cooldown duration in seconds.
- `ready`: (*boolean*) `true` if the rune is ready to use.

```lua
for slot = 1, 6 do
    local rune = core.spell_book.get_rune_info(slot)
    local rune_type = core.spell_book.get_rune_type(slot)
    if rune.ready then
        core.log("Rune " .. slot .. " (type " .. rune_type .. ") is ready!")
    end
end
```

---

### Power Regeneration

### `get_base_power_regen()`

Retrieves the base (out-of-combat) power regeneration rate of the local player. This represents the passive regeneration rate when not casting or using abilities.

Returns: *number* — The base power regeneration per second.

---

### `get_casting_power_regen()`

Retrieves the power regeneration rate of the local player while casting. This may differ from the base regen due to talents, buffs, or class mechanics.

Returns: *number* — The casting power regeneration per second.

---

### Shapeshift Functions

### `get_shapeshift_form_id()`

Returns the current shapeshift form ID, or `0` if the player is not shapeshifted.

Returns: *integer* - The current shapeshift form ID.

```lua
local form_id = core.spell_book.get_shapeshift_form_id()
if form_id ~= 0 then
    core.log("Current shapeshift form: " .. form_id)
end
```

---

### `get_shapeshift_form(show_all_forms)`

Returns the 1-based index of the active shapeshift, stance, or aspect form on the shapeshift bar, or `0` if no form is active. Wraps the Blizzard global `GetShapeshiftForm`.

Unlike `get_shapeshift_form_id` (which returns a class-global form ID), this returns the **bar index** used by the other shapeshift APIs such as `cast_shapeshift_form`. The index-based form is available across more game versions and class layouts (warrior stances, druid/rogue forms, etc.), so prefer it for new logic.

Parameters:
- **`show_all_forms`** (*boolean*, optional) - When `true`, also counts forms that are not currently usable. Defaults to `false`.

Returns: *integer* - The 1-based active form index, or `0` if none.

```lua
local form_index = core.spell_book.get_shapeshift_form()
if form_index ~= 0 then
    core.log("Active form bar index: " .. form_index)
end
```

---

### `cast_shapeshift_form(index)`

Casts the shapeshift form at the given 1-based shapeshift or stance bar index. The actual form change is observed asynchronously via `UPDATE_SHAPESHIFT_FORM`.

Parameters:
- **`index`** (*integer*) - The 1-based shapeshift or stance bar index to cast.

Returns: *boolean* - `true` if the cast call was issued without a Lua error.

```lua
local issued = core.spell_book.cast_shapeshift_form(1)
if issued then
    core.log("Shapeshift cast issued")
end
```

---

### `is_player_in_control()`

Determines if the player is currently in full control of their character (not stunned, feared, or incapacitated).

Returns: *boolean* — `true` if the player is in control; otherwise, `false`.

---

### Professions

> **tip**: These return the player's learned professions independent of any open trade‑skill window. To drive the profession windows themselves (crafting, recipes, skill lines), see the Professions API.

### `get_professions()`

Returns the player's profession spell‑tab indices (`GetProfessions`). Only professions the player actually has are set; absent slots are `nil`, so the result is safe to test with `if profs.cooking then`. Returns an empty table where the API is unavailable.

Returns: *table* — A table of spell‑tab indices keyed by profession slot:

| Field | Type | Description |
|-------|------|-------------|
| `prof1` | *integer?* | Spell‑tab index of the first primary profession |
| `prof2` | *integer?* | Spell‑tab index of the second primary profession |
| `archaeology` | *integer?* | Spell‑tab index of Archaeology |
| `fishing` | *integer?* | Spell‑tab index of Fishing |
| `cooking` | *integer?* | Spell‑tab index of Cooking |

```lua
local profs = core.spell_book.get_professions()
if profs.cooking then
    local info = core.spell_book.get_profession_info(profs.cooking)
    core.log(("Cooking: %d/%d"):format(info.skill_level, info.max_skill_level))
end
```

---

### `get_profession_info(index)`

Returns detailed info for a profession spell‑tab index (`GetProfessionInfo`).

Parameters:
- **`index`** (*integer*) — A spell‑tab index obtained from `get_professions()`.

Returns: *table | nil* — The profession info, or `nil` if unavailable:

| Field | Type | Description |
|-------|------|-------------|
| `name` | *string* | Localized profession name |
| `icon` | *integer* | FileDataID of the profession icon texture |
| `skill_level` | *integer* | Current skill level |
| `max_skill_level` | *integer* | Maximum skill level at the current rank |
| `num_abilities` | *integer* | Number of abilities in the profession's spell‑book tab |
| `spell_offset` | *integer* | Spell‑book offset of the first ability |
| `skill_line` | *integer* | Skill‑line ID of the profession |
| `skill_modifier` | *integer* | Bonus skill from gear/buffs |
| `specialization_index` | *integer* | Chosen specialization index (0 if none) |
| `specialization_offset` | *integer* | Spell‑book offset of the specialization (0 if none) |
| `skill_line_name` | *string* | Localized skill‑line name |
