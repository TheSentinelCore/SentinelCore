---
title: "Target Selector"
source: "https://docs.project-sylvanas.net/modules/target-selector"
crawled: "2026-07-14"
---

# Target Selector

## Overview

The **Target Selector** is a Lua core library essential for **class rotations** in Sylvanas. Its main role is to determine which unit to attack or heal, ensuring your abilities are aimed at the right targets. In World of Warcraft, the term "target" usually refers to the unit you've manually selected (which we'll call **HUD Target**). However, the Target Selector operates independently of this, choosing its own targets for healing or attacking based on set rules and conditions. You could have no target selected in the game, and Sylvanas will still work—although melee classes may need an additional auto-attack handler to attack efficiently. Some melee plugins include this handler under the spells offensive section.

## Target and HUD Target

#### In Sylvanas, They are Not the Same!

Know the Difference:

The HUD Target is the one you have selected (the target you are used to on WoW). The other Target is the one that Sylvanas will use to cast spells. Unlike other scripts that you might have used in the past, Target and HUD Target do not necessarily have to be the same. Your scripts will automatically search for the best target, (depending on many things like class logics, AOE, immunities, etc.) although there are certain configurations that will allow you to make your main Target be the HUD Target or that will allow you to manually select the script's targets.

These configuration options, and more, will be explained below.

## Target Selector Module

The module that will dictaminate who your Target (not HUD Target) is, is called "Target Selector", for obvious reasons. Upon opening its menu, you will see it has many customization options. It is recommended that these options are not modified in most cases. Script developers have all the required tools to customize the Target Selector according to their scripts, therefore, it should be their task to modify it to generate the best possible output for their script.

### 1 - Navigating To The Target Selector Menu

The Target Selector menu is located under Core Modules. The path to arrive there is:
**Main Menu -> Target Selector**

### 2 - Target Selector Modes

The **Target Selector** offers three modes:

1. **Silent Auto** (default) – The Target Selector handles everything, as described above.
2. **Hard Target** – The system selects the target for you and automatically assigns it to your HUD.
3. **Manual** – Disables part of the Target Selector's functionality, allowing you to rely on manual target selection through the HUD. This is useful for experienced players who prefer a traditional WoW experience.

These modes ensure flexibility for both new and experienced players, offering automation while also catering to those who want more control.

> **Note**
> 
> These modes refer to the combobox "Mode" in the previous image.

### 3 - Targeting Modes

The **Target Selector** operates in two separate and different settings.
Technically, there are 2 different target selectors, although they both operate under the "Target Selector" module as one:

1. **Damage** selector selects the best enemy to attack.
2. **Heal** selector selects the best ally to heal.

The settings for the "Damage" Target Selector are under "Damage Settings", that you can see in the previous image. The settings for the "Heal" Target Selector are under "Healer Settings", as you can also see in the said image. Again, the settings for each mode (heal and dmg) are independent from each other.

The way it selects these targets is based on a system called **Weight**.

### 4 - Weight System

Weights are the foundation of the **Target Selector** system. They allow flexible target selection by assigning importance (weight) to different criteria. For example, you can give **lower current health** more weight, and the Target Selector will prioritize enemies with the least health.

When evaluating targets, the system sorts them by their total weight, and the **Target Selector** function returns the top 3 enemies to attack or allies to heal. Your rotation will go through them in order of priority, adapting based on the current situation (like enemies hiding behind walls).

### Common Weights Examples:

- **Health** (percentage, current, or max health)
- **Distance** (closer enemies or allies can be prioritized)
- **Threat** (useful for tank logic)
- **Angle** (good for human-like target selection)
- **Role** (tank, healer, damage dealer)
- **HUD Target** (adds weight if the manually selected target should be prioritized)

This weight-based system gives flexibility in how targets are chosen, allowing for quick adaptations based on the situation.

> **Tip**
> 
> By default, Sylvanas provides pre-configured weights for plug-and-play ease, but advanced users can personalize these weights to optimize performance for different scenarios.

## 4 - Advanced Target Selector Settings

You can further customize your Target Selector in **Target Selector > Advanced Settings > Weight Settings**. There, you'll find options such as:

- **Blacklist Settings** – Ignore specific targets entirely, useful for situations like ignoring a CC'd enemy marked with a skull or an enemy marked with a moon by the raid leader, allowing you to quickly adapt your target selector to whatever specific strategy your raid choose to do in any boss.
- **Override Settings** – Give priority to certain targets. For example, overriding the priority to attack a marked skull or focus target.

### Practical Use: PVP Healer Settings

For example, when playing as a healer in PvP (3v3 or Solo Shuffle), you might want to tweak the weights:

- Disable **Angle Weight** to focus less on positional logic, which isn't as important in small arenas.
- Increase **HP Decreasing Weight** (from 3 to 4) to prioritize healing low-health teammates.
- Enable **Max HP Weight** to prioritize targets with the highest max health, as they are often more geared.

These adjustments allow you to fine-tune the system to your playstyle, maximizing efficiency in specific game modes.

> **Note**
> 
> Weights are powerful but can be tricky. Make sure you understand what each weight does before making changes, as incorrect settings could lead to unexpected behavior in targeting.

## 5 - Democratizing Target Selection

**Sylvanas** is designed to help players of all skill levels perform better, without needing years of experience. Unlike other tools that focus on top-end player achievements, Sylvanas aims to make World of Warcraft more accessible to everyone.

Experienced players might prefer to adjust the settings or even rely on manual modes. However, for newer players, **Automatic Mode** provides a smooth experience right out of the box, allowing them to feel impactful from the very start.

To access the **Target Selector** settings, navigate to:
**Core Modules > Target Selector > Weight Settings**.
