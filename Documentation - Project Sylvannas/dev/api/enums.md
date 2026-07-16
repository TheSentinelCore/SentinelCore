---
title: "Enums"
source: "https://docs.project-sylvanas.net/dev/api/enums"
crawled: "2026-07-14"
---

# Enums

## Overview

The enums module provides a comprehensive collection of enumeration constants used throughout the API. These constants help make your code more readable and maintainable by replacing magic numbers with meaningful names.

## Importing The Module

```
---@type enumslocal enums = require("common/enums")
```

IZI SDK Shorthand

If you're using the IZI SDK, you can access enums directly:

```
local izi = require("common/izi_sdk")local enums = izi.enums
```

---

## Class Identification

### `class_id`

Constants for identifying player classes.

Constant

Value

Description

`ANY`

0

Matches any class

`WARRIOR`

1

Warrior

`PALADIN`

2

Paladin

`HUNTER`

3

Hunter

`ROGUE`

4

Rogue

`PRIEST`

5

Priest

`DEATHKNIGHT`

6

Death Knight

`SHAMAN`

7

Shaman

`MAGE`

8

Mage

`WARLOCK`

9

Warlock

`MONK`

10

Monk

`DRUID`

11

Druid

`DEMONHUNTER`

12

Demon Hunter

`EVOKER`

13

Evoker

**Example Usage**

```
local enums = require("common/enums")local me = core.object_manager.get_local_player()if me:get_class() == enums.class_id.PALADIN then    -- Paladin-specific logicend
```

---

### `class_id_to_name`

Lookup table to convert class IDs to their string names.

**Example Usage**

```
local class_name = enums.class_id_to_name[enums.class_id.WARRIOR]-- class_name = "WARRIOR"
```

---

## Specializations

### `spec_enum`

Constants for identifying specific class specializations.

**Warrior**

Constant

Description

`ARMS_WARRIOR`

Arms

`FURY_WARRIOR`

Fury

`PROTECTION_WARRIOR`

Protection

**Paladin**

Constant

Description

`HOLY_PALADIN`

Holy

`PROTECTION_PALADIN`

Protection

`RETRIBUTION_PALADIN`

Retribution

**Hunter**

Constant

Description

`BEAST_MASTERY_HUNTER`

Beast Mastery

`MARKSMANSHIP_HUNTER`

Marksmanship

`SURVIVAL_HUNTER`

Survival

**Rogue**

Constant

Description

`ASSASSINATION_ROGUE`

Assassination

`OUTLAW_ROGUE`

Outlaw

`SUBTLETY_ROGUE`

Subtlety

**Priest**

Constant

Description

`DISCIPLINE_PRIEST`

Discipline

`HOLY_PRIEST`

Holy

`SHADOW_PRIEST`

Shadow

**Death Knight**

Constant

Description

`BLOOD_DEATHKNIGHT`

Blood

`FROST_DEATHKNIGHT`

Frost

`UNHOLY_DEATHKNIGHT`

Unholy

**Shaman**

Constant

Description

`ELEMENTAL_SHAMAN`

Elemental

`ENHANCEMENT_SHAMAN`

Enhancement

`RESTORATION_SHAMAN`

Restoration

**Mage**

Constant

Description

`ARCANE_MAGE`

Arcane

`FIRE_MAGE`

Fire

`FROST_MAGE`

Frost

**Warlock**

Constant

Description

`AFFLICTION_WARLOCK`

Affliction

`DEMONOLOGY_WARLOCK`

Demonology

`DESTRUCTION_WARLOCK`

Destruction

**Monk**

Constant

Description

`BREWMASTER_MONK`

Brewmaster

`MISTWEAVER_MONK`

Mistweaver

`WINDWALKER_MONK`

Windwalker

**Druid**

Constant

Description

`BALANCE_DRUID`

Balance

`FERAL_DRUID`

Feral

`GUARDIAN_DRUID`

Guardian

`RESTORATION_DRUID`

Restoration

**Demon Hunter**

Constant

Description

`HAVOC_DEMON_HUNTER`

Havoc

`VENGEANCE_DEMON_HUNTER`

Vengeance

**Evoker**

Constant

Description

`EVOKER_DEVASTATION`

Devastation

`EVOKER_PRESERVATION`

Preservation

`EVOKER_AUGMENTATION`

Augmentation

**Example Usage**

```
local spec = enums.class_spec_id.spec_enumif player_spec == spec.FROST_MAGE then    -- Frost Mage specific logicend
```

---

### `class_spec_id`

Helper functions for working with class and specialization IDs.

**Methods**

Method

Description

`get_specialization_name(class_id, spec_id)`

Returns the spec name as a string

`get_specialization_enum(class_id, spec_id)`

Returns the spec_enum value

`get_spec_id_from_enum(spec_enum)`

Converts spec_enum back to numeric ID

**Example Usage**

```
local me = core.object_manager.get_local_player()local class_id = me:get_class()local spec_id = me:get_spec()local spec_name = enums.class_spec_id.get_specialization_name(class_id, spec_id)core.log("Playing as: " .. spec_name)
```

---

## Power Types

### `power_type`

Constants for identifying unit power/resource types.

Constant

Value

Description

`HEALTH`

-2

Health (special)

`NONE`

-1

No power type

`MANA`

0

Mana

`RAGE`

1

Rage

`FOCUS`

2

Focus

`ENERGY`

3

Energy

`COMBOPOINTS`

4

Combo Points

`RUNES`

5

Runes

`RUNICPOWER`

6

Runic Power

`SOULSHARDS`

7

Soul Shards

`LUNARPOWER`

8

Astral Power (Lunar Power)

`HOLYPOWER`

9

Holy Power

`ALTERNATE`

10

Alternate Power

`MAELSTROM`

11

Maelstrom

`CHI`

12

Chi

`INSANITY`

13

Insanity

`ARCANECHARGES`

16

Arcane Charges

`FURY`

17

Fury

`PAIN`

18

Pain

`ESSENCE`

19

Essence (Evoker)

`RUNEFORGEPOWER`

20

Runeforge Power

`COMBOPOINTS_TBC`

-

TBC Combo Points (Classic)

**Example Usage**

```
local enums = require("common/enums")local me = core.object_manager.get_local_player()local energy = me:get_power(enums.power_type.ENERGY)local max_energy = me:get_max_power(enums.power_type.ENERGY)
```

---

## Group Roles

### `group_role`

Constants for identifying unit roles in a group.

Constant

Value

Description

`NONE`

-1

No role / Unknown

`TANK`

0

Tank

`HEALER`

1

Healer

`DAMAGER`

2

Damage dealer

**Example Usage**

```
local enums = require("common/enums")if unit:get_role() == enums.group_role.HEALER then    -- Prioritize this targetend
```

---

## Unit Classification

### `classification`

Constants for unit classification (elite status).

Constant

Value

Description

`UNKNOWN`

-1

Unknown

`NORMAL`

0

Normal mob

`ELITE`

1

Elite mob

`RARE_ELITE`

2

Rare elite mob

`WORLD_BOSS`

3

World boss

`RARE`

4

Rare mob

`TRIVIAL`

5

Trivial (grey) mob

`MINUS`

6

Minus (weak) mob

---

## Creature Types

### `creature_type`

Constants for identifying creature types.

Constant

Value

Description

`ABERRATION`

0

Aberration

`BEAST`

1

Beast

`DRAGONKIN`

2

Dragonkin

`DEMON`

3

Demon

`ELEMENTAL`

4

Elemental

`GIANT`

5

Giant

`UNDEAD`

6

Undead

`HUMANOID`

7

Humanoid

`CRITTER`

8

Critter

`MECHANICAL`

9

Mechanical

`NOT_SPECIFIED`

10

Not specified

`TOTEM`

11

Totem

`NON_COMBAT_PET`

12

Non-combat pet

`GAS_CLOUD`

13

Gas cloud

`WILD_PET`

14

Wild pet

**Example Usage**

```
local enums = require("common/enums")-- Check if target is a demon (for Exorcism, etc.)if target:get_creature_type() == enums.creature_type.DEMON then    -- Use anti-demon abilitiesend
```

---

## Raid Markers

### `mark_index`

Constants for raid target icons.

Constant

Value

Icon

`NO_MARK`

-1

No mark (warning)

`NO_ICON`

0

No icon

`STAR`

1

Star

`CIRCLE`

2

Circle (Orange)

`DIAMOND`

3

Diamond (Purple)

`TRIANGLE`

4

Triangle (Green)

`MOON`

5

Moon

`SQUARE`

6

Square (Blue)

`CROSS`

7

Cross (Red X)

`SKULL`

8

Skull

`NO_MARK_2`

9

No mark (alternate)

---

## Loss of Control

### `loss_of_control_type`

Constants for loss of control effects.

Constant

Value

Description

`NONE`

0

No effect

`POSSES`

1

Possessed

`CONFUSE`

2

Confused

`CHARM`

3

Charmed

`FEAR`

4

Feared

`STUN`

5

Stunned

`PACIFY`

6

Pacified

`ROOT`

7

Rooted

`SILENCE`

8

Silenced

`PACIFY_SILENCE`

9

Pacified and silenced

`DISARM`

10

Disarmed

`SCHOOL_INTERRUPT`

11

School interrupted

`STUN_MECHANIC`

12

Stun (mechanic)

`FEAR_MECHANIC`

13

Fear (mechanic)

---

## Buff Types

### `buff_type`

Constants for categorizing buff/debuff types.

Constant

Value

Description

`EXCEPTION`

-2

Exception

`UNDEFINIED`

-1

Undefined

`UNKNOWN`

0

Unknown

`MAGIC`

1

Magic

`CURSE`

2

Curse

`DISEASE`

3

Disease

`POISON`

4

Poison

`STEALTH`

5

Stealth

`TO_BE_DETERMINED`

6

To be determined

`MAGIC_CURSE_DISEASE_POISON`

7

Multiple types

`SPECIAL`

8

Special

`ENRAGE`

9

Enrage

---

## Spell Schools

### `spell_schools_flags`

Bitmask constants for spell school types. Can be combined using bitwise OR.

**Base Schools**

Constant

Value

Description

`Physical`

1

Physical damage

`Holy`

2

Holy damage

`Fire`

4

Fire damage

`Nature`

8

Nature damage

`Frost`

16

Frost damage

`Shadow`

32

Shadow damage

`Arcane`

64

Arcane damage

**Combined Schools**

Constant

Combination

Description

`Frostfire`

Fire + Frost

Frostfire

`Shadowflame`

Fire + Shadow

Shadowflame

`Shadowfrost`

Frost + Shadow

Shadowfrost

`Spellfire`

Fire + Arcane

Spellfire

`Spellfrost`

Frost + Arcane

Spellfrost

`Astral`

Nature + Arcane

Astral

`Radiant`

Holy + Fire

Radiant

`Twilight`

Holy + Shadow

Twilight

`Divine`

Holy + Nature

Divine

`Plague`

Nature + Shadow

Plague

`Volcanic`

Fire + Nature

Volcanic

`Holyfrost`

Holy + Frost

Holyfrost

`Holystorm`

Holy + Nature

Holystorm

`Froststorm`

Frost + Nature

Froststorm

`Spellstrike`

Physical + Arcane

Spellstrike

`Flamestrike`

Physical + Fire

Flamestrike

`Froststrike`

Physical + Frost

Froststrike

`Holystrike`

Physical + Holy

Holystrike

`Stormstrike`

Physical + Nature

Stormstrike

`Shadowstrike`

Physical + Shadow

Shadowstrike

`Spellshadow`

Shadow + Arcane

Spellshadow

**Methods**

```
-- Combine multiple schoolslocal combined = enums.spell_schools_flags.combine("Fire", "Frost")-- Check if a school is presentlocal has_fire = enums.spell_schools_flags.contains(spell_school, enums.spell_schools_flags.Fire)
```

---

## Collision Flags

### `collision_flags`

Bitmask constants for collision detection.

Constant

Value

Description

`None`

0x0

No collision

`DoodadCollision`

0x1

Doodad collision

`DoodadRender`

-

Doodad render

`WmoCollision`

0x10

WMO collision

`WmoRender`

-

WMO render

`WmoNoCamCollision`

-

WMO no camera collision

`Terrain`

0x100

Terrain collision

`IgnoreWmoDoodad`

-

Ignore WMO doodads

`LiquidWaterWalkable`

-

Water walkable liquid

`LiquidAll`

-

All liquids

`Cull`

-

Culling

`EntityCollision`

0x100000

Entity collision

`EntityRender`

-

Entity render

`Collision`

-

General collision

`LineOfSight`

0x100010

Line of sight check

**Methods**

```
-- Combine flagslocal flags = enums.collision_flags.combine("WmoCollision", "Terrain")
```

---

## PvP Crowd Control

### `cc_flags`

Bitmask constants for crowd control types in PvP. Cross-expansion compatible.

Constant

Value

Description

`ROOT`

0x1

Root effects

`INCAPACITATE`

0x2

Incapacitate (breaks on damage)

`DISORIENT`

0x4

Disorient (breaks on damage)

`STUN`

0x8

Hard stun

`SILENCE`

0x10

Silence

`KNOCKBACK`

0x20

Knockback

`DISARM`

0x40

Disarm

`SAP`

0x80

Sap

`FEAR`

0x100

Fear

`CYCLONE`

0x200

Cyclone

`MORTAL_COIL`

-

Mortal Coil

`HORROR`

0x800

Horror

`MAGICAL`

0x1000

Magical source

`PHYSICAL`

0x2000

Physical source

`MIND_CONTROL`

-

Mind Control

`RANDOM_STUN`

-

Random stun procs

`RANDOM_ROOT`

-

Random root procs

`BLINDING_LIGHT`

-

Blinding Light

`KIDNEY_SHOT`

-

Kidney Shot

`SCATTER`

-

Scatter Shot

`BANISH`

-

Banish

`ANY`

0x1FFFFF

Match any CC

`ANY_BUT_ROOT`

(computed)

Any except roots

**Methods**

```
-- Combine multiple CC flagslocal stun_or_root = enums.cc_flags.combine(enums.cc_flags.STUN, enums.cc_flags.ROOT)-- Check if a mask contains a flagif enums.cc_flags.has(applied_mask, enums.cc_flags.STUN) then    -- Target is stunnedend
```

---

### `cc_source`

Constants for CC source filtering.

Constant

Value

Description

`ANY`

0

Matches any source

`PHYSICAL`

1

Physical CC source

`MAGICAL`

2

Magical CC source

---

## Damage Type Flags

### `damage_type_flags`

Bitmask constants for damage types (used for immunity checks).

Constant

Value

Description

`PHYSICAL`

0x1

Physical damage

`MAGICAL`

0x2

Magical damage

`ANY`

0x3

Any damage type

**Methods**

```
-- Combine damage typeslocal both = enums.damage_type_flags.combine(    enums.damage_type_flags.PHYSICAL,    enums.damage_type_flags.MAGICAL)-- Check if contains a typeif enums.damage_type_flags.has(mask, enums.damage_type_flags.MAGICAL) then    -- Includes magical damageend
```

---

## Spell Types

### `spell_type`

Constants for spell targeting types.

Constant

Value

Description

`TARGET`

1

Unit-targeted spell

`POSITION`

2

Position-targeted (ground) spell

---

## Trigger Mode

### `trigger_mode`

Constants for trigger/activation modes.

Constant

Value

Description

`BASIC`

-

Basic trigger mode

`PREDICTION`

-

Prediction-based trigger mode

---

## Font IDs

### `font_id`

Constants for graphics font selection.

Constant

Value

Description

`FONT_VERY_SMALL`

2

Very small font

`FONT_SMALL`

7

Small font

`FONT_SEMI_BIG`

1

Semi-big font

`FONT_BIG`

8

Big font

`FONT_ICONS_SMALL`

3

Small icons font

`FONT_ICONS_BIG`

4

Big icons font

`FONT_ICONS_VERY_BIG`

6

Very big icons font

`FONT_CN`

9

Chinese font

`FONT_RU`

10

Russian font

`FONT_JP`

11

Japanese font

`FONT_KR`

12

Korean font

---

## Menu Element Types

### `menu_element_type`

Constants for menu UI element types.

Constant

Value

Description

`BUTTON`

1

Button

`CHECKBOX`

2

Checkbox

`COLOR_PICKER`

3

Color picker

`COMBOBOX`

4

Dropdown combobox

`COMBOBOX_REORDERABLE`

5

Reorderable combobox

`KEY_CHECKBOX`

6

Key + checkbox

`KEYBIND`

7

Keybind

`SLIDER_FLOAT`

8

Float slider

`SLIDER_INT`

9

Integer slider

`TEXT_INPUT`

10

Text input

`TREE_NODE`

11

Tree node

`HEADER`

12

Header

`WINDOW`

13

Window

---

## Complete Example

```
local izi = require("common/izi_sdk")local enums = izi.enumslocal me = izi.me()local target = izi.target()-- Check if we're a caster classlocal caster_classes = {    [enums.class_id.MAGE] = true,    [enums.class_id.WARLOCK] = true,    [enums.class_id.PRIEST] = true,}if caster_classes[me:get_class()] then    -- Check target's magic immunity    local immune, remaining = target:is_damage_immune(enums.damage_type_flags.MAGICAL)    if immune then        izi.printf("Target immune to magic for %dms", remaining)    endend-- Check for CC on targetlocal is_cc, cc_mask, cc_remaining = target:is_cc(500, enums.cc_flags.ANY)if is_cc then    if enums.cc_flags.has(cc_mask, enums.cc_flags.STUN) then        izi.print("Target is stunned!")    endend-- Check creature type for special abilitiesif target:get_creature_type() == enums.creature_type.UNDEAD then    -- Use Turn Undead, Shackle, etc.end-- Check specializationlocal spec = enums.class_spec_id.get_specialization_enum(me:get_class(), me:get_spec())if spec == enums.class_spec_id.spec_enum.FROST_MAGE then    -- Frost Mage specific rotationend
```
