---
id: 15
title: "IDE Core — Panel System + Toolbar + Explorer + Inspector + Timeline"
state: open
labels: ["enhancement", "ready-for-agent", "size:large"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 15 — IDE Core: Panel System + Toolbar + Explorer + Inspector + Timeline

**What to build:** The foundational UI layer for the in-game IDE — a panel registration system on the existing SentinelWindow, a toolbar for common actions, and the three most critical panels: Explorer (project tree), Inspector (property editor), and Timeline (action sequence).

**Blocked by:** #13 (Variable Store + Event Dispatcher + State Machine — IDE observes runtime state)

**Acceptance criteria:**

**Panel System:**
- [ ] Extend existing `sentinel/ui/window.lua` with a panel registration API:
  - `register_panel(name, render_fn, options)` — options: default_visible, dock_position, width, height
  - `show_panel(name)` / `hide_panel(name)` / `toggle_panel(name)`
  - `get_panel(name)` — returns panel state
- [ ] Layout persistence: panel visibility and sizes saved to `scripts_data/sentinel/layout.json`, restored on load
- [ ] Panel rendering integrated into existing SentinelWindow frame update loop

**Toolbar:**
- [ ] Horizontal toolbar rendered at top of SentinelWindow
- [ ] Buttons: Save (Ctrl+S), Compile (Ctrl+Shift+C), Validate, Undo (Ctrl+Z), Redo (Ctrl+Y), Dry Run toggle, Start (Ctrl+Shift+R), Stop (Ctrl+Shift+X)
- [ ] Capture buttons: Record NPC (Ctrl+N), Record Path (Ctrl+Shift+P), Record Area (Ctrl+Shift+A)
- [ ] View button: dropdown to toggle panel visibility
- [ ] Each button invokes its action via the event bus or direct function call

**Explorer Panel:**
- [ ] Hierarchical tree view: Profile → Operations → Actions
- [ ] Expand/collapse nodes (click arrow or double-click)
- [ ] Click to select → updates Inspector and Timeline to show selection
- [ ] Right-click context menu on Operations: Rename, Delete, Duplicate, Enable/Disable, Move Up, Move Down
- [ ] Right-click context menu on Actions: Rename, Delete, Duplicate, Enable/Disable, Move Up, Move Down
- [ ] Color coding: normal text = enabled, grey = disabled, red icon = has validation error
- [ ] Drag/drop to reorder Operations (within profile level only)
- [ ] Syncs with profile data: adding/removing Operations in code updates the tree

**Inspector Panel:**
- [ ] Displays properties of the currently selected object (Action, Operation, or Variable)
- [ ] Common fields shown for all Actions: name (editable text), enabled (checkbox), notes (multiline text), retry_policy (retry_count, retry_delay_ms, backoff_multiplier), timeout_ms (number)
- [ ] Type-specific fields per ActionPayload variant:
  - GoTo: destination x/y/zone, movement_type
  - GrindArea: polygon vertices (list), target creature entries (list), stop_condition
  - PickupQuest/TurnInQuest: quest reference (NPC selector)
  - Vendor: NPC reference, sell list, buy list
  - Branch: condition expression editor
  - SetVariable: variable name, value, scope
  - etc.
- [ ] Edits write directly to the active profile data model
- [ ] Condition editor: add/remove conditions from a list, each with field/operator/value

**Timeline Panel:**
- [ ] Vertical list of Actions for the currently selected Operation
- [ ] Each action row: icon (by type), name, status indicator (grey=pending, green=done, blue=active, red=failed)
- [ ] Click to select → Inspector updates to show that action's properties
- [ ] Drag/drop to reorder actions within the Operation
- [ ] Blueprint nodes shown as collapsible groups with a summary label (e.g., "Blueprint: Level 5 Quest Chain (12 actions)")
- [ ] Color coding by action type: Movement=blue, Combat=red, Quest=yellow, NPC=green, Utility=grey
- [ ] Add Action button at bottom → opens Action Palette (from #17)
- [ ] Syncs with profile data: edits in Timeline update the profile model

**Keyboard Shortcuts:**
- [ ] Ctrl+S → Save profile
- [ ] Ctrl+Shift+C → Compile
- [ ] Ctrl+Z → Undo (placeholder until #17 wires up the command system)
- [ ] Ctrl+Y → Redo (placeholder)
- [ ] Ctrl+N → Capture NPC
- [ ] Delete → Delete selected item (with confirmation)
