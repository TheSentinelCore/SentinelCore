---
title: "Spell Queue"
source: "https://docs.project-sylvanas.net/modules/spell-queue"
crawled: "2026-07-14"
---

# Spell Queue

## Overview

The **Spell Queue** system in Sylvanas is designed to seamlessly integrate player inputs with the script's rotation. Unlike other projects where you might need to pause the rotation to cast your own spells or rely on macros, the **Spell Queue** hooks into the game's input system to detect when you try to cast a spell yourself. Even if your character is busy (e.g., under a global cooldown), your input is added to the queue, ensuring smooth gameplay between manual player actions and the script's automation.

With **Spell Queue**, you can cast your own spells on top of the rotation, without any interruption. For example, you can stun an enemy with **Hammer of Justice** as a Paladin whenever you choose, without breaking the flow of the script.

## 1 - Ground Spell Support

The **Spell Queue** system also supports ground-targeted spells like **Death Knight's Death and Decay**. You can configure how these spells should be cast by navigating to the following path: **Main Menu -> Core -> Spell Queue Settings**

In this menu, you'll find options like **Skillshot Mode**, which controls how ground-targeted spells behave.

### Casting Mode Options

1. **Tooltip Mode (default)** – Displays the green targeting indicator, letting you confirm the position before casting. During this time, the script's rotation will pause, which could lower your DPS output if you're not quick with your cast.

2. **Fast Cast Mode** – Skips the confirmation process, instantly casting the spell at your mouse's position when you issue the command. This mode is great for experienced players who want to minimize rotation downtime.

> **Note**
> 
> Fast Cast is a great option to ensure fluid rotation, especially for high-speed playstyles.
