# 05 — Statechart Canvas: Editing States & Transitions

**What to build:** Editing capabilities for the statechart canvas: adding/deleting states and transitions via context menus, editing state properties in the property panel, and creating transitions by dragging between states.

**Blocked by:** 04 — Statechart Canvas: Interaction & Selection

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/components/context_menu.lua`
- [ ] Right-click canvas: context menu with "Add State" option
- [ ] Right-click state node: context menu with "Delete State", "Add Transition", "Edit Properties"
- [ ] Right-click transition: context menu with "Delete Transition", "Edit Properties"
- [ ] "Add State" creates new state at click position with default name
- [ ] "Delete State" removes state and all connected transitions
- [ ] "Add Transition" enters transition-drawing mode (click source → click target)
- [ ] "Delete Transition" removes the selected transition
- [ ] Property panel becomes editable: modify event, guard, actions, onEnter/onExit
- [ ] Edits propagate back to profile data model
- [ ] Add "New Compound State" and "New Parallel Region" options
