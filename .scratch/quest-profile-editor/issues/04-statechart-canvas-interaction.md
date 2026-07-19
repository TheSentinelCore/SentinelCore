# 04 — Statechart Canvas: Interaction & Selection

**What to build:** Interactive behaviors for the statechart canvas: clicking to select states, dragging to reposition nodes, hovering for tooltips, and a property panel showing details of the selected state/transition.

**Blocked by:** 03 — Statechart Canvas: Render States & Transitions

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/components/property_panel.lua`
- [ ] Click state node to select (highlight border)
- [ ] Click transition edge to select (highlight curve)
- [ ] Click empty canvas to deselect
- [ ] Drag state node to reposition (update x, y in data model)
- [ ] Hover state node: show tooltip with state name, type, onEnter/onExit actions
- [ ] Hover transition edge: show tooltip with event, guard
- [ ] Property panel displays selected item's details:
  - State: name, type, parent, onEnter actions, onExit actions
  - Transition: event, guard, source, target, actions
- [ ] Property panel updates in real-time as selection changes
