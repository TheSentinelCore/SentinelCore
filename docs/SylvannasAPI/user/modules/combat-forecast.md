---
title: "Combat Forecast"
source: "https://docs.project-sylvanas.net/modules/combat-forecast"
crawled: "2026-07-14"
---

# Combat Forecast

## Overview

The **Combat Forecast** is a simple yet powerful library used primarily by class rotation spell logic in Sylvanas. Its main function is to prevent casting long cooldown spells (such as those with 2-3 minute cooldowns) or long-duration damage over time spells (like **Agony**) on targets that are about to die. This helps optimize spell usage and avoid wasting important cooldowns on fights that won't last long enough for these spells to be effective.

While the **Combat Forecast** can also be used for other logical decisions—such as determining when to cast **Soul Reaper** for a Death Knight—it is primarily designed for these specific scenarios.

## Combat Forecast Data

The **Combat Forecast** library collects data throughout your gameplay session in order to become more accurate over time. If you encounter issues, it is recommended to **reload the Lua scripts** to reset the forecast history and clear any problems that may arise. The default keybind to reload Lua is **F6**. (See [menu keybinds](/modules/menu#3---keybinds-))

> **Note**
> 
> Keep in mind that reloading Lua will erase all session data, including the **Combat Forecast** history. This is not something you should do frequently, as the stored data is important for improving script accuracy over time.
