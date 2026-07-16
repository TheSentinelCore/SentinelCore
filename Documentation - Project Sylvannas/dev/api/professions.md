---
title: "Professions"
source: "https://docs.project-sylvanas.net/dev/api/professions"
crawled: "2026-07-14"
---

# Profession Functions

## Overview

The profession API wraps the native Blizzard profession globals across every client. It is split into four namespaces:

- **`core.profession`** — an enum of profession constants plus `open_profession()`, a locale‑independent way to open a profession's window.
- **`core.trade_skill`** — the trade‑skill window API. It exposes both the **classic** index‑based functions (`GetTradeSkillInfo`, `DoTradeSkill`, …) and the **retail** `C_TradeSkillUI` functions (`GetRecipeInfo`, `CraftRecipe`, …). Classic callers use window indices; retail callers use recipe spell IDs.
- **`core.craft`** — the classic `Craft` window API (used by Enchanting and beast training on older clients).
- **`core.skill`** — the classic Skill window API (`GetSkillLineInfo`, trainer skill lines, …).

> **Version safety**: Every function routes through the secure Lua path and guards the underlying global in‑game. On clients where a given global does not exist (for example the classic index functions on retail, or `C_TradeSkillUI` on classic), the call returns a **safe default** (`0`, `false`, `nil`, or an empty table) instead of erroring.

> **Player professions**: To discover which professions the player has (independent of any open window), use `core.spell_book.get_professions` and `core.spell_book.get_profession_info`.

---

## core.profession

Profession enum constants plus the window opener. Enum values are **opaque ordinals** — always use the named constants, never the raw number.

### Profession constants

| Constant | Notes |
|----------|-------|
| `core.profession.ALCHEMY` | |
| `core.profession.BLACKSMITHING` | |
| `core.profession.COOKING` | |
| `core.profession.ENCHANTING` | |
| `core.profession.ENGINEERING` | |
| `core.profession.FIRST_AID` | |
| `core.profession.FISHING` | Starts the fishing cast rather than opening a window |
| `core.profession.INSCRIPTION` | |
| `core.profession.JEWELCRAFTING` | |
| `core.profession.LEATHERWORKING` | |
| `core.profession.MINING` | Opens the **Smelting** window (Mining itself has no craft window) |
| `core.profession.SKINNING` | Gathering skill — has no window |
| `core.profession.TAILORING` | |

---

### `core.profession.open_profession`

```
core.profession.open_profession(profession: integer) -> boolean
```

**Parameters**
- `profession`: `integer` - A `core.profession.*` enum value.

Returns:
- `boolean`: `true` if the open/cast was issued; `false` for an unknown enum value or when there is no local player.

Description: Opens the given profession's window by casting its stable Apprentice‑rank spell. Because the Apprentice spell ID is identical across every expansion **and** locale, this works regardless of the client's language — no spell‑name lookup required.

**Example Usage**

```lua
-- Open the Alchemy window
if not core.profession.open_profession(core.profession.ALCHEMY) then
    core.log_warning("Could not open Alchemy (no player or unknown profession).")
end
```

---

## core.trade_skill

The trade‑skill window API. The **classic** functions below are index‑based; the **retail `C_TradeSkillUI`** functions further down are recipe‑spell‑ID based.

**Example Usage — iterate the open trade‑skill window (classic)**

```lua
local count = core.trade_skill.get_num_trade_skills()
for index = 1, count do
    local info = core.trade_skill.get_trade_skill_info(index)
    if info and info.type ~= "header" then
        core.log(("%s x%d (skill-ups: %d)"):format(info.name, info.num_available, info.num_skill_ups))
    end
end
```

### `core.trade_skill.do_trade_skill`

```
core.trade_skill.do_trade_skill(index: integer, repeat_count?: integer)
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.
- `repeat_count`: `integer` *(optional)* - Number of copies to craft (default `1`).

Description: Crafts `repeat_count` copies of the trade‑skill at `index` (`DoTradeSkill`).

**Example Usage**

```lua
-- Craft 5 copies of the selected recipe
local selected = core.trade_skill.get_trade_skill_selection_index()
core.trade_skill.do_trade_skill(selected, 5)
```

---

### `core.trade_skill.get_num_trade_skills`

```
core.trade_skill.get_num_trade_skills() -> integer
```

Returns:
- `integer`: Number of trade‑skill list rows (0 if the window is closed).

Description: Returns the number of entries in the open trade‑skill window (`GetNumTradeSkills`).

---

### `core.trade_skill.get_trade_skill_info`

```
core.trade_skill.get_trade_skill_info(index: integer) -> trade_skill_info | nil
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `trade_skill_info | nil`: The row info, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Recipe/header name |
| `type` | `string` | Row type (`header`, `optimal`, `medium`, `easy`, `trivial`, …) |
| `num_available` | `integer` | Number of crafts the player can currently make |
| `is_expanded` | `boolean` | Whether this header row is expanded |
| `alt_verb` | `string` | Alternate action verb (e.g. `Enchant`), empty if none |
| `num_skill_ups` | `integer` | Skill points gained per craft |
| `indent_level` | `integer` | Tree indent level of the row |
| `show_progress_bar` | `boolean` | Whether the row shows a rank progress bar (MoP cooking) |
| `current_rank` | `integer` | Current specialization rank (0 on older clients) |
| `max_rank` | `integer` | Maximum specialization rank (0 on older clients) |
| `starting_rank` | `integer` | Starting specialization rank (0 on older clients) |

Description: Returns info for a trade‑skill list row (`GetTradeSkillInfo`). The last five fields are MoP cooking‑specialization extras and are `0`/`false` on older clients.

---

### `core.trade_skill.get_trade_skill_num_reagents`

```
core.trade_skill.get_trade_skill_num_reagents(index: integer) -> integer
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `integer`: Number of reagents.

Description: Returns the number of reagents for a trade‑skill (`GetTradeSkillNumReagents`).

---

### `core.trade_skill.get_trade_skill_reagent_info`

```
core.trade_skill.get_trade_skill_reagent_info(index: integer, reagent_index: integer) -> profession_reagent_info | nil
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.
- `reagent_index`: `integer` - 1‑based reagent index.

Returns:
- `profession_reagent_info | nil`: The reagent info, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Reagent item name |
| `texture` | `string` | Reagent icon texture path |
| `count` | `integer` | Quantity required for one craft |
| `player_count` | `integer` | Quantity the player currently owns |

Description: Returns reagent info for a trade‑skill (`GetTradeSkillReagentInfo`).

**Example Usage**

```lua
local index = core.trade_skill.get_trade_skill_selection_index()
for r = 1, core.trade_skill.get_trade_skill_num_reagents(index) do
    local reagent = core.trade_skill.get_trade_skill_reagent_info(index, r)
    if reagent then
        core.log(("%s: %d/%d"):format(reagent.name, reagent.player_count, reagent.count))
    end
end
```

---

### `core.trade_skill.get_trade_skill_line`

```
core.trade_skill.get_trade_skill_line() -> trade_skill_line | nil
```

Returns:
- `trade_skill_line | nil`: The skill‑line info, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Skill‑line (profession) name |
| `rank` | `integer` | Current skill rank |
| `max_rank` | `integer` | Maximum skill rank |
| `skill_line_modifier` | `integer` | Bonus skill from gear/buffs |

Description: Returns the current trade‑skill line (`GetTradeSkillLine`).

---

### `core.trade_skill.close`

```
core.trade_skill.close()
```

Description: Closes the trade‑skill window (`CloseTradeSkill`).

---

### `core.trade_skill.get_trade_skill_num_made`

```
core.trade_skill.get_trade_skill_num_made(index: integer) -> profession_num_made
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `profession_num_made`: Quantity produced per craft.

| Field | Type | Description |
|-------|------|-------------|
| `min_made` | `integer` | Minimum quantity produced per craft |
| `max_made` | `integer` | Maximum quantity produced per craft |

Description: Returns the min/max quantity a trade‑skill produces (`GetTradeSkillNumMade`).

---

### `core.trade_skill.get_trade_skill_cooldown`

```
core.trade_skill.get_trade_skill_cooldown(index: integer) -> integer
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `integer`: Seconds remaining (0 if none / no cooldown).

Description: Returns the remaining cooldown of a trade‑skill in seconds (`GetTradeSkillCooldown`).

---

### `core.trade_skill.select_trade_skill`

```
core.trade_skill.select_trade_skill(index: integer)
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Description: Selects a trade‑skill list row (`SelectTradeSkill`).

---

### `core.trade_skill.get_trade_skill_selection_index`

```
core.trade_skill.get_trade_skill_selection_index() -> integer
```

Returns:
- `integer`: Selected index (0 if none).

Description: Returns the currently selected trade‑skill index (`GetTradeSkillSelectionIndex`).

---

### `core.trade_skill.get_tradeskill_repeat_count`

```
core.trade_skill.get_tradeskill_repeat_count() -> integer
```

Returns:
- `integer`: Remaining queued crafts.

Description: Returns how many repeat crafts are queued (`GetTradeskillRepeatCount`).

---

### `core.trade_skill.get_first_trade_skill`

```
core.trade_skill.get_first_trade_skill() -> integer
```

Returns:
- `integer`: First craftable index (0 if none).

Description: Returns the index of the first non‑header trade‑skill (`GetFirstTradeSkill`).

---

### `core.trade_skill.get_num_primary_professions`

```
core.trade_skill.get_num_primary_professions() -> integer
```

Returns:
- `integer`: Maximum primary professions, always `2` (0 if the API is unavailable).

Description: Returns the max number of primary professions (`GetNumPrimaryProfessions`). Removed in Cataclysm.

---

### `core.trade_skill.expand_trade_skill_sub_class`

```
core.trade_skill.expand_trade_skill_sub_class(index: integer)
```

**Parameters**
- `index`: `integer` - Sub‑class header index.

Description: Expands a trade‑skill sub‑class header (`ExpandTradeSkillSubClass`).

---

### `core.trade_skill.collapse_trade_skill_sub_class`

```
core.trade_skill.collapse_trade_skill_sub_class(index: integer)
```

**Parameters**
- `index`: `integer` - Sub‑class header index.

Description: Collapses a trade‑skill sub‑class header (`CollapseTradeSkillSubClass`).

---

### `core.trade_skill.get_trade_skill_recipe_link`

```
core.trade_skill.get_trade_skill_recipe_link(index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `string | nil`: The recipe item link, or `nil` if unavailable.

Description: Returns the recipe item link for a trade‑skill (`GetTradeSkillRecipeLink`).

---

### `core.trade_skill.get_trade_skill_item_link`

```
core.trade_skill.get_trade_skill_item_link(index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `string | nil`: The crafted item link, or `nil` if unavailable.

Description: Returns the crafted item link for a trade‑skill (`GetTradeSkillItemLink`).

---

### `core.trade_skill.get_trade_skill_icon`

```
core.trade_skill.get_trade_skill_icon(index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `string | nil`: The icon texture path, or `nil` if unavailable.

Description: Returns the crafted item icon texture path for a trade‑skill (`GetTradeSkillIcon`).

---

### `core.trade_skill.get_trade_skill_tools`

```
core.trade_skill.get_trade_skill_tools(index: integer) -> string[]
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `string[]`: Array of required tool names (empty if none).

Description: Returns the required tools for a trade‑skill (`GetTradeSkillTools`).

---

### `core.trade_skill.get_trade_skill_item_stats`

```
core.trade_skill.get_trade_skill_item_stats(index: integer) -> string[]
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.

Returns:
- `string[]`: Array of stat strings (empty if none).

Description: Returns the crafted item's stat strings for a trade‑skill (`GetTradeSkillItemStats`).

---

### `core.trade_skill.get_trade_skill_sub_classes`

```
core.trade_skill.get_trade_skill_sub_classes() -> string[]
```

Returns:
- `string[]`: Array of sub‑class filter names.

Description: Returns the trade‑skill sub‑class filter names (`GetTradeSkillSubClasses`).

---

### `core.trade_skill.get_trade_skill_sub_class_filter`

```
core.trade_skill.get_trade_skill_sub_class_filter(index: integer) -> boolean
```

**Parameters**
- `index`: `integer` - Sub‑class filter index.

Returns:
- `boolean`: `true` if the filter is enabled.

Description: Returns whether a sub‑class filter is enabled (`GetTradeSkillSubClassFilter`).

---

### `core.trade_skill.set_trade_skill_sub_class_filter`

```
core.trade_skill.set_trade_skill_sub_class_filter(index: integer, on_off?: boolean, exclusive?: boolean)
```

**Parameters**
- `index`: `integer` - Sub‑class filter index.
- `on_off`: `boolean` *(optional)* - Whether the filter is enabled (default `true`).
- `exclusive`: `boolean` *(optional)* - Whether to make this the only active filter (default `false`).

Description: Sets a sub‑class filter (`SetTradeSkillSubClassFilter`).

---

### `core.trade_skill.get_trade_skill_inv_slots`

```
core.trade_skill.get_trade_skill_inv_slots() -> string[]
```

Returns:
- `string[]`: Array of inventory‑slot filter names.

Description: Returns the inventory‑slot filter names (`GetTradeSkillInvSlots`).

---

### `core.trade_skill.get_trade_skill_inv_slot_filter`

```
core.trade_skill.get_trade_skill_inv_slot_filter(index: integer) -> boolean
```

**Parameters**
- `index`: `integer` - Inventory‑slot filter index.

Returns:
- `boolean`: `true` if the filter is enabled.

Description: Returns whether an inventory‑slot filter is enabled (`GetTradeSkillInvSlotFilter`).

---

### `core.trade_skill.set_trade_skill_inv_slot_filter`

```
core.trade_skill.set_trade_skill_inv_slot_filter(index: integer, on_off?: boolean, exclusive?: boolean)
```

**Parameters**
- `index`: `integer` - Inventory‑slot filter index.
- `on_off`: `boolean` *(optional)* - Whether the filter is enabled (default `true`).
- `exclusive`: `boolean` *(optional)* - Whether to make this the only active filter (default `false`).

Description: Sets an inventory‑slot filter (`SetTradeSkillInvSlotFilter`).

---

### `core.trade_skill.get_trade_skill_reagent_item_link`

```
core.trade_skill.get_trade_skill_reagent_item_link(index: integer, reagent_index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Trade‑skill list index.
- `reagent_index`: `integer` - 1‑based reagent index.

Returns:
- `string | nil`: The reagent item link, or `nil` if unavailable.

Description: Returns a reagent's item link for a trade‑skill (`GetTradeSkillReagentItemLink`).

---

## core.trade_skill — retail (C_TradeSkillUI)

These functions wrap retail's `C_TradeSkillUI` (Legion 7.0.3+). They live under the same `core.trade_skill` namespace but take **recipe spell IDs** instead of window indices. On Classic they return safe defaults.

**Example Usage — enumerate learned recipes (retail)**

```lua
for _, recipe_id in ipairs(core.trade_skill.get_all_recipe_ids()) do
    local info = core.trade_skill.get_recipe_info(recipe_id)
    if info and info.learned and info.num_available > 0 then
        core.log(("Can craft %s (x%d)"):format(info.name, info.num_available))
    end
end
```

### `core.trade_skill.craft_recipe`

```
core.trade_skill.craft_recipe(recipe_spell_id: integer, num_casts?: integer, apply_concentration?: boolean)
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.
- `num_casts`: `integer` *(optional)* - Number of crafts to queue (default `1`).
- `apply_concentration`: `boolean` *(optional)* - Whether to spend concentration (default `false`).

Description: Crafts a recipe by spell ID (`C_TradeSkillUI.CraftRecipe`). The optional reagents, recipe level and order ID parameters are always passed as `nil`.

---

### `core.trade_skill.close_trade_skill`

```
core.trade_skill.close_trade_skill()
```

Description: Closes the retail trade‑skill window (`C_TradeSkillUI.CloseTradeSkill`).

---

### `core.trade_skill.open_trade_skill`

```
core.trade_skill.open_trade_skill(skill_line_id: integer) -> boolean
```

**Parameters**
- `skill_line_id`: `integer` - Skill‑line ID.

Returns:
- `boolean`: `true` if the window was opened.

Description: Opens the profession window for a skill line (`C_TradeSkillUI.OpenTradeSkill`).

---

### `core.trade_skill.open_recipe`

```
core.trade_skill.open_recipe(recipe_id: integer)
```

**Parameters**
- `recipe_id`: `integer` - Recipe spell ID.

Description: Opens a specific recipe in the profession window (`C_TradeSkillUI.OpenRecipe`).

---

### `core.trade_skill.get_recipe_info`

```
core.trade_skill.get_recipe_info(recipe_spell_id: integer, recipe_level?: integer) -> recipe_info | nil
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.
- `recipe_level`: `integer` *(optional)* - Recipe level (omit or `<= 0` for none).

Returns:
- `recipe_info | nil`: The recipe info, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `recipe_id` | `integer` | Recipe spell ID |
| `name` | `string` | Recipe name |
| `icon` | `integer` | FileDataID of the recipe icon |
| `num_available` | `integer` | Number of crafts the player can currently make |
| `num_skill_ups` | `integer` | Skill points gained per craft |
| `learned` | `boolean` | Whether the recipe is learned |
| `category_id` | `integer` | Recipe category ID |
| `is_recraft` | `boolean` | Whether the recipe supports recrafting |
| `is_enchant` | `boolean` | Whether the recipe is an enchant |
| `relative_difficulty` | `integer` | Relative difficulty enum value |
| `skill_line_ability_id` | `integer` | Skill‑line ability ID |

Description: Returns a curated scalar subset of a recipe's info (`C_TradeSkillUI.GetRecipeInfo`). The full nested `RecipeInfo` table cannot be marshalled, so only these scalar fields are exposed.

---

### `core.trade_skill.get_all_recipe_ids`

```
core.trade_skill.get_all_recipe_ids() -> integer[]
```

Returns:
- `integer[]`: Array of recipe spell IDs (empty if none).

Description: Returns all learned recipe spell IDs for the open profession (`C_TradeSkillUI.GetAllRecipeIDs`).

---

### `core.trade_skill.get_recipe_schematic`

```
core.trade_skill.get_recipe_schematic(recipe_spell_id: integer, is_recraft: boolean, recipe_level?: integer) -> recipe_schematic | nil
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.
- `is_recraft`: `boolean` - Whether to fetch the recraft schematic.
- `recipe_level`: `integer` *(optional)* - Recipe level (omit or `<= 0` for none).

Returns:
- `recipe_schematic | nil`: The schematic, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `recipe_id` | `integer` | Recipe spell ID |
| `name` | `string` | Recipe name |
| `quantity_min` | `integer` | Minimum quantity produced |
| `quantity_max` | `integer` | Maximum quantity produced |
| `item_id` | `integer` | Produced item ID |
| `has_crafting_operation_info` | `boolean` | Whether crafting‑operation info is present |
| `num_reagent_slots` | `integer` | Number of reagent slots (the slot array itself is not marshalled) |

Description: Returns a curated scalar subset of a recipe schematic (`C_TradeSkillUI.GetRecipeSchematic`).

---

### `core.trade_skill.get_craftable_count`

```
core.trade_skill.get_craftable_count(recipe_spell_id: integer, recipe_level?: integer) -> integer
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.
- `recipe_level`: `integer` *(optional)* - Recipe level (omit or `<= 0` for none).

Returns:
- `integer`: Number of craftable copies.

Description: Returns how many copies of a recipe the player can craft (`C_TradeSkillUI.GetCraftableCount`).

---

### `core.trade_skill.get_recipe_item_link`

```
core.trade_skill.get_recipe_item_link(recipe_spell_id: integer) -> string | nil
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.

Returns:
- `string | nil`: The item link, or `nil` if unavailable.

Description: Returns the produced item link for a recipe (`C_TradeSkillUI.GetRecipeItemLink`).

---

### `core.trade_skill.get_recipe_link`

```
core.trade_skill.get_recipe_link(recipe_spell_id: integer) -> string | nil
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.

Returns:
- `string | nil`: The recipe link, or `nil` if unavailable.

Description: Returns the recipe link for a recipe (`C_TradeSkillUI.GetRecipeLink`).

---

### `core.trade_skill.get_recipe_num_items_produced`

```
core.trade_skill.get_recipe_num_items_produced(recipe_spell_id: integer) -> profession_num_made
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.

Returns:
- `profession_num_made`: Quantity produced per craft (`min_made`, `max_made`).

Description: Returns the min/max quantity a recipe produces (`C_TradeSkillUI.GetRecipeNumItemsProduced`).

---

### `core.trade_skill.get_recipe_tools`

```
core.trade_skill.get_recipe_tools(recipe_spell_id: integer) -> string[]
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.

Returns:
- `string[]`: Array of required tool names (empty if none).

Description: Returns the required tools for a recipe (`C_TradeSkillUI.GetRecipeTools`).

---

### `core.trade_skill.get_recipe_cooldown`

```
core.trade_skill.get_recipe_cooldown(recipe_spell_id: integer) -> integer
```

**Parameters**
- `recipe_spell_id`: `integer` - Recipe spell ID.

Returns:
- `integer`: Seconds remaining (0 if none).

Description: Returns the remaining cooldown of a recipe in seconds (`C_TradeSkillUI.GetRecipeCooldown`).

---

### `core.trade_skill.get_remaining_recasts`

```
core.trade_skill.get_remaining_recasts() -> integer
```

Returns:
- `integer`: Remaining queued crafts.

Description: Returns how many queued recasts remain (`C_TradeSkillUI.GetRemainingRecasts`).

---

### `core.trade_skill.get_base_profession_info`

```
core.trade_skill.get_base_profession_info() -> trade_skill_profession_info | nil
```

Returns:
- `trade_skill_profession_info | nil`: The profession info, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `profession_name` | `string` | Localized profession name |
| `profession_id` | `integer` | Profession ID |
| `skill_level` | `integer` | Current skill level |
| `max_skill_level` | `integer` | Maximum skill level at the current rank |
| `skill_modifier` | `integer` | Bonus skill from gear/buffs |
| `skill_line_name` | `string` | Localized skill‑line name |

Description: Returns the base profession info for the open profession (`C_TradeSkillUI.GetBaseProfessionInfo`).

---

### `core.trade_skill.get_profession_info_by_skill_line_id`

```
core.trade_skill.get_profession_info_by_skill_line_id(skill_line_id: integer) -> trade_skill_profession_info | nil
```

**Parameters**
- `skill_line_id`: `integer` - Skill‑line ID.

Returns:
- `trade_skill_profession_info | nil`: The profession info (same fields as `get_base_profession_info`), or `nil` if unavailable.

Description: Returns profession info for a skill line (`C_TradeSkillUI.GetProfessionInfoBySkillLineID`).

---

### `core.trade_skill.get_all_profession_trade_skill_lines`

```
core.trade_skill.get_all_profession_trade_skill_lines() -> integer[]
```

Returns:
- `integer[]`: Array of skill‑line IDs (empty if none).

Description: Returns all trade‑skill line IDs for the player's professions (`C_TradeSkillUI.GetAllProfessionTradeSkillLines`).

---

## core.craft

The classic `Craft` window API — used by Enchanting and beast training on older clients. Returns safe defaults where the `Craft` globals are unavailable.

### `core.craft.do_craft`

```
core.craft.do_craft(index: integer)
```

**Parameters**
- `index`: `integer` - Craft list index.

Description: Performs the craft at the given index (`DoCraft`).

---

### `core.craft.get_num_crafts`

```
core.craft.get_num_crafts() -> integer
```

Returns:
- `integer`: Number of craft rows (0 if the window is closed).

Description: Returns the number of entries in the open craft window (`GetNumCrafts`).

---

### `core.craft.get_craft_info`

```
core.craft.get_craft_info(index: integer) -> craft_info | nil
```

**Parameters**
- `index`: `integer` - Craft list index.

Returns:
- `craft_info | nil`: The row info, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Craft/header name |
| `sub_spell_name` | `string` | Sub‑spell (rank) name, empty if none |
| `type` | `string` | Row type (`header`, `optimal`, `medium`, `easy`, `trivial`, …) |
| `num_available` | `integer` | Number of crafts the player can currently make |
| `is_expanded` | `boolean` | Whether this header row is expanded |
| `training_point_cost` | `integer` | Training‑point cost (0 if not applicable) |
| `required_level` | `integer` | Required level (0 if none) |

Description: Returns info for a craft list row (`GetCraftInfo`).

---

### `core.craft.get_craft_num_reagents`

```
core.craft.get_craft_num_reagents(index: integer) -> integer
```

**Parameters**
- `index`: `integer` - Craft list index.

Returns:
- `integer`: Number of reagents.

Description: Returns the number of reagents for a craft (`GetCraftNumReagents`).

---

### `core.craft.get_craft_reagent_info`

```
core.craft.get_craft_reagent_info(index: integer, reagent_index: integer) -> profession_reagent_info | nil
```

**Parameters**
- `index`: `integer` - Craft list index.
- `reagent_index`: `integer` - 1‑based reagent index.

Returns:
- `profession_reagent_info | nil`: The reagent info (`name`, `texture`, `count`, `player_count`), or `nil` if unavailable.

Description: Returns reagent info for a craft (`GetCraftReagentInfo`).

---

### `core.craft.close`

```
core.craft.close()
```

Description: Closes the craft window (`CloseCraft`).

---

### `core.craft.get_craft_item_link`

```
core.craft.get_craft_item_link(index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Craft list index.

Returns:
- `string | nil`: The crafted item link, or `nil` if unavailable.

Description: Returns the crafted item link for a craft (`GetCraftItemLink`).

---

### `core.craft.get_craft_description`

```
core.craft.get_craft_description(index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Craft list index.

Returns:
- `string | nil`: The description, or `nil` if unavailable.

Description: Returns the description text for a craft (`GetCraftDescription`).

---

### `core.craft.get_craft_name`

```
core.craft.get_craft_name() -> string | nil
```

Returns:
- `string | nil`: The craft window name, or `nil` if unavailable.

Description: Returns the name of the open craft window (`GetCraftName`).

---

### `core.craft.get_craft_display_skill_line`

```
core.craft.get_craft_display_skill_line() -> string | nil
```

Returns:
- `string | nil`: The display skill line, or `nil` if unavailable.

Description: Returns the display skill line of the open craft window (`GetCraftDisplaySkillLine`).

---

### `core.craft.get_craft_skill_line`

```
core.craft.get_craft_skill_line(index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Craft list index.

Returns:
- `string | nil`: The skill line, or `nil` if unavailable.

Description: Returns the skill line for a craft row (`GetCraftSkillLine`).

---

### `core.craft.get_craft_spell_focus`

```
core.craft.get_craft_spell_focus(index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Craft list index.

Returns:
- `string | nil`: The required focus/tool name, or `nil` if unavailable.

Description: Returns the required focus/tool for a craft (`GetCraftSpellFocus`).

---

### `core.craft.get_craft_selection_index`

```
core.craft.get_craft_selection_index() -> integer
```

Returns:
- `integer`: Selected index (0 if none).

Description: Returns the currently selected craft index (`GetCraftSelectionIndex`).

---

### `core.craft.select_craft`

```
core.craft.select_craft(index: integer)
```

**Parameters**
- `index`: `integer` - Craft list index.

Description: Selects a craft list row (`SelectCraft`).

---

### `core.craft.get_craft_reagent_item_link`

```
core.craft.get_craft_reagent_item_link(index: integer, reagent_index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Craft list index.
- `reagent_index`: `integer` - 1‑based reagent index.

Returns:
- `string | nil`: The reagent item link, or `nil` if unavailable.

Description: Returns a reagent's item link for a craft (`GetCraftReagentItemLink`).

---

### `core.craft.get_craft_icon`

```
core.craft.get_craft_icon(index: integer) -> string | nil
```

**Parameters**
- `index`: `integer` - Craft list index.

Returns:
- `string | nil`: The icon texture path, or `nil` if unavailable.

Description: Returns the icon texture path for a craft (`GetCraftIcon`).

---

### `core.craft.expand_craft_skill_line`

```
core.craft.expand_craft_skill_line(index: integer)
```

**Parameters**
- `index`: `integer` - Skill‑line header index.

Description: Expands a craft skill‑line header (`ExpandCraftSkillLine`).

---

### `core.craft.collapse_craft_skill_line`

```
core.craft.collapse_craft_skill_line(index: integer)
```

**Parameters**
- `index`: `integer` - Skill‑line header index.

Description: Collapses a craft skill‑line header (`CollapseCraftSkillLine`).

---

### `core.craft.get_craft_button_token`

```
core.craft.get_craft_button_token() -> string | nil
```

Returns:
- `string | nil`: The button token, or `nil` if unavailable.

Description: Returns the craft button token (`GetCraftButtonToken`).

---

## core.skill

The classic Skill window API (`GetSkillLineInfo`, trainer skill lines, …). Returns safe defaults where the skill globals are unavailable.

**Example Usage — list the player's skill lines**

```lua
for i = 1, core.skill.get_num_skill_lines() do
    local info = core.skill.get_skill_line_info(i)
    if info and not info.is_header then
        core.log(("%s: %d/%d"):format(info.name, info.skill_rank, info.skill_max_rank))
    end
end
```

### `core.skill.get_num_skill_lines`

```
core.skill.get_num_skill_lines() -> integer
```

Returns:
- `integer`: Number of skill lines (0 if unavailable).

Description: Returns the number of skill lines (`GetNumSkillLines`).

---

### `core.skill.get_skill_line_info`

```
core.skill.get_skill_line_info(index: integer) -> skill_line_info | nil
```

**Parameters**
- `index`: `integer` - Skill‑line index.

Returns:
- `skill_line_info | nil`: The skill‑line info, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Skill‑line or header name |
| `is_header` | `boolean` | Whether this row is a header |
| `is_expanded` | `boolean` | Whether the header is expanded |
| `skill_rank` | `integer` | Current skill rank |
| `num_temp_points` | `integer` | Temporary bonus points |
| `skill_modifier` | `integer` | Bonus skill from gear/buffs |
| `skill_max_rank` | `integer` | Maximum skill rank |
| `is_abandonable` | `boolean` | Whether the skill can be unlearned |
| `step_cost` | `integer` | Cost per skill‑up step |
| `rank_cost` | `integer` | Cost per rank |
| `min_level` | `integer` | Minimum level required |
| `skill_cost_type` | `integer` | Skill cost type enum value |
| `skill_description` | `string` | Skill description text |

Description: Returns info for a skill line (`GetSkillLineInfo`).

---

### `core.skill.get_selected_skill`

```
core.skill.get_selected_skill() -> integer
```

Returns:
- `integer`: Selected skill index (0 if none).

Description: Returns the currently selected skill index (`GetSelectedSkill`).

---

### `core.skill.set_selected_skill`

```
core.skill.set_selected_skill(index: integer)
```

**Parameters**
- `index`: `integer` - Skill‑line index.

Description: Selects a skill line (`SetSelectedSkill`).
