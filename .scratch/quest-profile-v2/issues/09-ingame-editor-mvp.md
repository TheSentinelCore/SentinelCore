---
id: 9
title: "In-Game Profile Editor MVP — YAML Editor + Validator + Hot-Reload"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:medium", "size:large"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

# In-Game Profile Editor MVP — YAML Editor + Validator + Hot-Reload

## Description

Build the **Tier 0/1 MVP** of the in-game profile authoring tool using Sylvannas UI APIs. No node graph yet — a syntax-highlighted YAML text editor with real-time validation, diagnostics panel, and hot-reload into running executor.

## UI Layout

```
┌─────────────────────────────────────────────────────────────┐
│ Sentinel Quest Profile Editor                    [X]        │
├──────────────┬──────────────────────────────────┬───────────┤
│ File Tree    │ Editor (YAML)                    │ Diagnostics│
│              │                                  │            │
│ ▼ profiles/  │ schemaVersion: "2.0"             │ ● Error L12│
│   ▼ quests/  │ profile:                         │   Quest ID │
│     alliance_│   id: "alliance_human_01_10_...  │   99999 not│
│     _human_  │   name: "Human 1-10 Elwynn"      │   found    │
│     01_10... │   ...                            │            │
│     ▼routing/│ states:                          │ ⚠ Warn L45 │
│       northsh│   Questing:                      │   Unreachab│
│       ire_to_│     type: "exclusive"            │   state:   │
│       kobold │     initial: "Initialize"        │     Travel │
│     kobold_t │     states:                      │     To...  │
│              │       Initialize:                │            │
│   [New File] │         type: "atomic"           │ [Clear]    │
│   [Save]     │         onEnter:                 │            │
│   [Validate] │           - "log('...')"         │            │
│   [Hot Reload]│        transitions:             │            │
│              │             - event: "ProfileStart"│          │
└──────────────┴──────────────────────────────────┴───────────┘
```

## Features

### 1. File Tree
- Lists `sentinel/data/profiles/quests/*.yaml` and `sentinel/data/routing_policies/*.yaml`
- Double-click to open in editor
- "New File" creates profile or policy template

### 2. YAML Editor
- Syntax highlighting (keys, strings, numbers, comments)
- Line numbers
- Brace matching
- Auto-indent (2 spaces)
- Tab = 2 spaces

### 3. Diagnostics Panel
- Runs `ProfileCompiler.compile(editor_text)` on every keystroke (debounced 300ms)
- Shows errors/warnings with line numbers
- Click diagnostic → jump to line in editor
- Inline squiggles on error lines (red underline)

### 4. Hot-Reload
- "Save" button: writes YAML to file, runs compiler, if valid → sends `ProfileReload` event
- "Hot Reload" button: skips file write, compiles from editor buffer, if valid → swaps `CompiledProfile` in running `StatechartExecutor` preserving history state
- Toast notification: "Profile compiled ✓" / "Compile failed ✗ (3 errors)"

### 5. Profile Templates
- "New Profile" → inserts minimal valid profile skeleton
- "New Routing Policy" → inserts policy skeleton

## Sylvannas UI Components Needed

- `ScrollFrame` with `EditBox` (multi-line) for editor
- `ScrollFrame` with `FontString` lines for file tree (clickable)
- `ScrollFrame` for diagnostics (clickable entries)
- `Button` widgets for actions
- Font: `GameFontNormal`, `GameFontHighlight` for syntax highlighting (custom coloring via markup)

## Integration Points

- `ProfileCompiler` module (issue 01) — called from editor
- `StatechartExecutor` — `executor:hotSwap(compiledProfile)` preserves active state stack
- `event_bus` — `ProfileReload` event for full reload

## Acceptance Criteria

- [ ] Editor opens, shows file tree with existing profiles/policies
- [ ] YAML syntax highlighting works (keys=yellow, strings=green, numbers=orange, comments=gray)
- [ ] Typing invalid YAML shows parse error in diagnostics
- [ ] Typing valid YAML with bad quest ID shows semantic error (line, message)
- [ ] Click diagnostic → editor scrolls to line, highlights
- [ ] "Save" writes file to `sentinel/data/profiles/quests/`
- [ ] "Hot Reload" compiles from buffer, swaps executor profile, preserves state
- [ ] Toast notifications on compile success/failure
- [ ] New file templates work
- [ ] Editor window draggable, resizable, closable
- [ ] Performance: validation debounced, no FPS drop while typing

## Blocked by

- **01-profile-compiler** — validation backend
- **02-statechart-executor** — hot-swap API
- Sylvannas UI capability check (verify EditBox multi-line + markup works)

## Files to Create

- `sentinel/ui/profile_editor.lua` — main editor frame
- `sentinel/ui/profile_editor/editor.lua` — YAML edit box + highlighting
- `sentinel/ui/profile_editor/tree.lua` — file tree
- `sentinel/ui/profile_editor/diagnostics.lua` — diagnostics panel
- `sentinel/ui/profile_editor/hot_reload.lua` — hot-swap logic
- `sentinel/ui/profile_editor/templates.lua` — profile/policy templates