---
id: 17
title: "Utility Panels — Action Palette + Variables + Validation + Console + Search"
state: open
labels: ["enhancement", "ready-for-agent", "size:large"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 17 — Utility Panels: Action Palette + Variables + Validation + Console + Search

**What to build:** The remaining IDE panels — action creation palette, variable management, validation display, log console, and a unified search. Also implements the Undo/Redo system via command pattern.

**Blocked by:** #15 (Panel System — panels register with the IDE)

**Acceptance criteria:**

**Action Palette:**
- [ ] Categorized list of all action types, grouped by domain:
  - Movement: GoTo, RecordPath
- [ ] Combat: GrindArea, KillTarget
  - Quest: PickupQuest, TurnInQuest
  - NPC Interaction: Vendor, Repair, Train, FlightPath, Mailbox, Bank
  - Inventory: UseItem
  - Flow Control: Branch, SetVariable, Wait
  - Special: DungeonMarker, DeathSkip
- [ ] Blueprint library: pre-built templates (e.g., "Level 5 Quest Chain", "Grind + Vendor Loop", "Flight Path Unlock")
- [ ] Drag from palette onto Timeline → adds action to current Operation at drop position
- [ ] Alternatively, double-click action type → appends to end of current Operation
- [ ] Blueprint drag → inserts collapsed Blueprint group

**Variables Panel:**
- [ ] Two tabs: "Global" (profile-level) and "Operation" (current Operation scope)
- [ ] List of variables with columns: Name, Type, Value, Scope
- [ ] Create button: opens dialog with name input, type selector (Bool/Integer/Float/String/Position), initial value
- [ ] Click variable → Inspector shows variable properties for editing
- [ ] Delete button (with confirmation)
- [ ] During execution: "Watch" column shows live variable values (read from Variable Store)
- [ ] Empty state: "No variables defined. Create one to use in Branch/SetVariable actions."

**Validation Panel:**
- [ ] Displays list of all validation errors and warnings from the compiler and profile manager
- [ ] Each entry: severity icon (red ERROR, yellow WARNING, blue INFO, green SUCCESS), error code, message, entity reference
- [ ] Click entry → select the offending object in Explorer/Timeline/Inspector
- [ ] Refresh on: profile load, compile, any edit
- [ ] Filter by severity (show/hide warnings, errors, info)
- [ ] Empty state with green checkmark: "No issues found. Profile is valid."
- [ ] Count badge on panel tab: "Validation (3)" showing number of issues

**Console Panel:**
- [ ] Three tabs: "Editor" (profile edits, captures), "Compiler" (compile output), "Runtime" (execution trace)
- [ ] Each log entry: timestamp, level (INFO/WARN/ERROR), message
- [ ] Editor tab: log profile saves, NPC captures, action additions/removals
- [ ] Compiler tab: log compile stages, duration per stage, diagnostics, success/failure summary
- [ ] Runtime tab: log action execution start/complete/fail, state transitions, errors
- [ ] Auto-scroll to bottom, with a "pin" toggle to stop auto-scroll
- [ ] Clear button per tab
- [ ] Export button: dump log to file

**Search Everywhere (Ctrl+P):**
- [ ] Modal dialog triggered by Ctrl+P
- [ ] Search input with live results
- [ ] Searches across: NPCs (by name/entry), Quests (by title/ID, via QueryServer), Operations (by name), Actions (by name/type), Variables (by name)
- [ ] Results grouped by type with icons
- [ ] Click result → navigate to entity (select in Explorer, scroll Timeline, update Inspector)
- [ ] Escape to close, Up/Down to navigate results, Enter to select

**Undo/Redo System:**
- [ ] Command pattern implementation: each reversible action creates a Command object with `execute()` and `undo()` methods
- [ ] Command types: AddAction, RemoveAction, MoveAction, EditActionField, CaptureNPC, DeleteNPC, CreateVariable, DeleteVariable, EditVariable
- [ ] History stack: unlimited undo until save (clear on save)
- [ ] Redo stack: cleared on new action (standard undo/redo behavior)
- [ ] Ctrl+Z → undo last command, Ctrl+Y → redo
- [ ] Each command publishes state change to event bus (so Explorer, Timeline, Inspector update)
- [ ] Tests: add action → undo → verify removed, redo → verify restored, edit field → undo → verify original value
