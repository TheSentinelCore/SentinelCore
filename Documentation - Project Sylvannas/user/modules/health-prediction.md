---
title: "Health Prediction"
source: "https://docs.project-sylvanas.net/modules/health-prediction"
crawled: "2026-07-14"
---

# Health Prediction

## Overview

The **Health Prediction** library is designed to give Lua developers a more accurate and forward-looking picture of combat situations. By providing insight beyond just raw health or percentage data, **Health Prediction** improves the logic for using defensive spells, heals, and other survival-related mechanics.

Unlike Lua unlockers or addons that rely on combat logs to react to events, Sylvanas has a significant advantage due to its **exceptional speed** and **direct access** to the game memory. This allows Sylvanas to react faster and provide real-time information about **current health** and **incoming damage**—before the combat logs even register the event.

## 1 - The Advantage of On Spell Cast

In most Lua unlocker projects, **combat logs** serve as the primary way to detect incoming damage. Combat logs are processed **after** the spell has already hit, which allows these tools to store and analyze past damage for systems like **Time To Die (TTD)** estimates. While this method might work, it has a delay, as it relies on past data.

In contrast, Sylvanas uses a more advanced function called **On Spell Cast**, which is a preemptive event that triggers **before** the spell even fires. This function acts as an animation callback, allowing us to detect incoming damage with remarkable speed. Although it doesn't provide all the details (like the exact amount of damage), it offers enough insight to build a predictive system for incoming damage.

This feature makes **Health Prediction** extremely powerful for casting defensive spells or healing in advance. For example, instead of casting a defensive ability when you are already at 20% health, you could cast it when incoming damage is about to reduce your health by 30%—avoiding dangerous situations altogether.

## 2 - Integration and Usage

The **Health Prediction** library is highly flexible and can be easily integrated into existing spell logic. For example, within Sylvanas, we provide a helpful function in the **Unit Helper** library called `get_health_percentage_inc`. This function predicts your future health by analyzing incoming damage and gives you an estimated health percentage after the damage lands. You might currently have 100% health, but the function might return 20%, indicating that you will soon drop to 20% health due to incoming damage. Developers can customize many of the parameters for the predictions, like the "time window", making it simple to create defensive and healing systems that are far more accurate and reactive than ever before.

For developers, see the [Health Prediction Lib](/dev/libraries/modules/health-prediction)

> **Note**
> 
> This predictive logic is up to the developer, who can fine-tune it based on specific class or encounter needs.

## 3 - Debug Mode and Visual Indicators

Below is a short clip showcasing **Health Prediction** in action, with a debug mode enabled for clear visual feedback on incoming damage predictions.

> **Tip**
> 
> With Sylvanas' **Health Prediction**, developers can create more dynamic and intelligent defensive and healing rotations, leading to smoother and more effective gameplay. If you are a developer, check [Health Prediction Lib](/dev/api/object-manager)
