# QuestingBuddy

QuestingBuddy is a Sylvanas Lua plugin that adds a Questie-aware objective loop for questing.

## Status

This is an MVP implementation focused on target detection, movement, and interaction flow.

## Features

- Questie integration through `common/utility/questie_tracker`
- Safe Questie guards:
  - `questie:is_hooked()`
  - `questie:is_quest_object(obj)`
- Objective scanner with scoring and blacklist cooldown
- Basic movement + interaction loop using `simple_movement`
- Runtime menu toggles in Sylvanas menu
- Fallback mode when Questie is unavailable (optional)

## Requirements

- Sylvanas API runtime
- `common/utility/questie_tracker` available in the environment
- Questie addon (or compatible provider) if `Require Questie Hook` is enabled

## File Layout

```
QuestingBuddy/
  header.lua
  init.lua
  main.lua
  modules/
    QuestieAdapter.lua
    ObjectiveScanner.lua
    QuestingManager.lua
  docs/
    QUESTIE_APPROACH.md
```

## Runtime Controls

The plugin exposes these menu entries:

- `Enable QuestingBuddy`
- `Require Questie Hook`
- `Fallback Hostile Units`
- `Scan Radius`
- `Interact Range`
- `Objective Timeout`
- `Debug Logs`

## Behavior Summary

1. Scan objects around player.
2. If Questie is hooked:
   - keep only objects where `is_quest_object(obj)` is true.
3. If Questie is not hooked:
   - strict mode (`Require Questie Hook`) => no objective selected.
   - fallback mode => use interactable/lootable/hostile heuristics.
4. Move to best objective.
5. Interact/loot/engage.
6. If no progress or timeout, temporary blacklist and retarget.

## Notes

- This version does not implement full quest chain logic yet.
- NavLib path routing integration can be added in the next iteration.
