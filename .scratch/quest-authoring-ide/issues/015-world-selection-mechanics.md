# 015 — World Selection Mechanics

**What to build:** Implement the core feature that allows users to click on world objects in-game to populate action fields:
- Clicking an NPC in populates its ID in selected quest action's "npc" field
- Clicking a monster/creature populates its ID in "Kill Target" or "Gather Node" actions
- Clicking a game object (chest, node, etc.) populates its ID in "Loot Object" or "Interact" actions
- Click-drag on terrain/water creates polygon for area-based actions (farm, patrol, avoid zones)
- Shift-click to add to existing selection (for multi-select scenarios)
- Escape key clears current selection
- Visual feedback: selected object glows or highlights in world
- Tooltip shows object name, ID, type, location when hovering
- Integration with action palette: only enables when compatible action is selected
- Works with both editor camera and game camera (switchable via keybind)
- Respects line of sight and occlusion (doesn't select through walls)
- Filters by player's faction (can't select enemy faction NPCs for friendly actions)
- Range limit configurable (default: 100 yards, max: draw distance)
- Works in both editor mode and live gameplay mode
- Integrates with existing Sylvannas input system
- Doesn't interfere with normal gameplay when not in selection mode
- Provides alternative keyboard method: type ID or name to select
- Works with invisible or stealthed objects (with appropriate permissions)
- Handles duplicates: if multiple objects at same location, shows selection menu
- Supports controller/gamepad input in addition to mouse/keyboard
- Configurable selection highlight color and intensity
- Works with phasing/teaming (only shows objects in player's current phase)
- Respects stealth and invisibility mechanics (can't see through them unless appropriate)
- Performance: minimal impact on FPS when idle (<1ms per frame)
- Debug visualization option: shows collision bounds and selection radius
- Integration with existing targeting system: can use current target as source
- Configurable cooldown to prevent spamming (default: 250ms)
- Works with mounted and unmounted states
- Respects vehicle state: different selection rules when in vehicle
- Integration with minimap: clicking minimap icon selects corresponding world object
- Supports multiple selection modes: single, multiple, paint (drag to select many)
- Includes undo/redo for selection changes within editing session
- Provides haptic feedback on controllers when selection successful
- Accessibility: supports screen readers and alternative input devices
- Localization: works with non-English client languages
- Falls back to manual ID entry if world selection fails or is disabled

**Blocked by:** 001 — Source Format Specification

**Status:** ready-for-agent

- [ ] Integrate with existing Sylvannas input/event system for click detection
- [ ] Implement raycasting from camera to determine what object is under cursor
- [ ] Add filtering by object type: NPC, creature, gameobject, etc.
- [ ] Create selection visualization system (outline, glow, highlight)
- [ ] Implement tooltip system showing object details on hover
- [ ] Integrate with action system: only allow selection when compatible action active
- [ ] Add keyboard shortcuts: Escape to clear, Enter to accept, Tab to cycle
- [ ] Implement shift-click for multi-select, ctrl-click for toggle
- [ ] Add drag-to-pan when not in selection mode (right-click typically)
- [ ] Create selection menu for overlapping objects (same screen position)
- [ ] Implement range checking: ignore objects beyond configurable distance
- [ ] Add faction filtering: prevent selecting enemy NPCs for friendly actions
- [ ] Implement line-of-sight checking: don't select through walls/buildings
- [ ] Add configurable cooldown to prevent excessive server requests
- [ ] Provide alternative: text box to enter ID/name manually
- [ ] Handle special cases: stealthed, invisible, phased, summoned objects
- [ ] Integrate with existing targeting: "Use current target" button option
- [ ] Add support for controller triggers and bumpers for selection
- [ ] Make highlight color/intensity configurable in settings
- [ ] Ensure compatibility with phasing technology (WOTLK and later)
- [ ] Respect stealth mechanics: requires detection ability to see hidden
- [ ] Performance optimization: spatial partitioning for fast lookups
- [ ] Add debug mode: shows collision spheres and selection radius
- [ ] Integrate with existing targetting: can use current selection as source
- [ ] Implement debouncing to prevent excessive UI updates
- [ ] Add configuration options: enable/disable, range, filters, visuals
- [ ] Test with various object types: vendors, trainers, flight masters, quest givers
- [ ] Verify works in instances, battlegrounds, arenas, and open world
- [ ] Ensure compatibility with popular addons that modify targeting/combat
- [ ] Provide Lua API for other addons to hook into selection system
- [ ] Include comprehensive unit tests for edge cases and edge conditions
- [ ] Create documentation: how to use, limitations, troubleshooting
- [ ] Performance target: <1ms overhead per frame when not actively selecting
- [ ] Accessibility: works with screen readers and alternative input devices
- [ ] Localization: all prompts and labels translatable
- [ ] Fallback: if world selection unavailable, defaults to manual input