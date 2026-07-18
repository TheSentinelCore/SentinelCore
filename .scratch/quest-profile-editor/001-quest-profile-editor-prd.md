---
id: 1
title: "Quest Profile Editor — In-Game Authoring Suite"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "area:ui", "priority:high", "size:large"]
created: "2026-07-17T00:00:00Z"
updated: "2026-07-17T00:00:00Z"
---

# PRD: Quest Profile Editor — In-Game Authoring Suite

## Context

The Quest Profile v2 system (ADR-0004) introduced hand-authored declarative profiles executed by a statechart engine. The initial implementation included a basic profile selector dropdown and settings. The user now requests a full in-game profile editor with:

1. **Statechart canvas** — visual state machine editor for profile states/transitions
2. **Map overlay** — show quest locations, NPCs, and objective areas on a map
3. **Quest browser** — find and add quests from the database
4. **Dependency graph** — visualize quest prerequisites and chains
5. **YAML editor** — edit profile YAML directly with syntax highlighting
6. **Hot-reload** — save profile → recompile → executor hot-swaps

**Excluded:** Simulator panel (deferred to future work).

## Scope

### In Scope

1. **Profile Editor Window** — new Sylvannas ImGui window with tabbed interface (Statechart, Map, Quests, Dependencies, Code)
2. **Statechart Canvas** — node-based visualization of profile states, regions, and transitions with drag-and-drop
3. **Map Overlay** — render quest locations, NPC positions, and objective areas using Sylvannas graphics API
4. **Quest Browser** — query `QueryClient` for available quests, filter by zone/level/faction, preview quest data
5. **Dependency Graph** — visualize quest prerequisites as a directed acyclic graph
6. **YAML Code Editor** — text editor with line numbers, basic syntax highlighting, and error diagnostics
7. **Profile Save/Load** — save to `scripts_data/quest_profiles/`, trigger recompile and hot-reload
8. **Integration** — connect to existing `ProfileLoader`, `ProfileCompiler`, `StatechartExecutor`

### Out of Scope

- Simulator / Monte Carlo optimizer
- Multi-profile batch editing
- Route policy visual editor
- Collaborative editing
- Undo/redo (initial version)

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   ProfileEditorWindow                    │
│  ┌──────────┬──────────┬──────────┬──────────┬────────┐ │
│  │Statechart│   Map    │  Quests  │  Deps    │  Code  │ │
│  │  Canvas  │ Overlay  │ Browser  │  Graph   │ Editor │ │
│  └────┬─────┴────┬─────┴────┬─────┴────┬─────┴───┬────┘ │
│       │          │          │          │          │       │
│  ┌────▼──────────▼──────────▼──────────▼──────────▼────┐ │
│  │              ProfileEditorController                 │ │
│  │  (owns profile data, handles save/load/reload)      │ │
│  └──────────────────────┬──────────────────────────────┘ │
└─────────────────────────┼───────────────────────────────┘
                          │
              ┌───────────▼───────────┐
              │    ProfileLoader      │
              │    ProfileCompiler    │
              │    StatechartExecutor │
              └───────────────────────┘
```

### Component Details

#### 1. Statechart Canvas (`statechart_canvas.lua`)

Renders the profile's state hierarchy as a node-based graph.

**Data Model:**
```lua
-- Each state becomes a node
StateNode = {
    id = string,           -- "Questing.AcceptNorthshireQuests"
    label = string,        -- "Accept Northshire Quests"
    type = string,         -- "atomic" | "compound" | "parallel" | "final"
    x = number,            -- canvas position
    y = number,
    width = number,        -- auto-calculated from label
    height = number,
    parent_id = string?,   -- parent compound state
    region_id = string?,   -- parent parallel region
    is_initial = boolean,  -- has initial pseudo-state
    is_active = boolean,   -- currently executing state (runtime)
}

-- Each transition becomes a connection
TransitionEdge = {
    id = string,
    source_id = string,
    target_id = string,
    event = string?,
    guard = string?,
    label = string,        -- "[event] guard" display text
    control_points = {vec2}, -- bezier control points for routing
}
```

**Rendering:**
- States: rounded rectangles with color coding (atomic=blue, compound=green, parallel=purple, final=gold)
- Regions: nested rectangles within compound states
- Transitions: bezier curves with arrowheads
- Initial pseudo-state: filled circle
- Hover: highlight node, show tooltip with state details
- Selection: border highlight, property panel

**Interaction:**
- Click: select state
- Double-click: open state properties
- Drag: move state nodes
- Right-click: context menu (add/delete state, add transition)

#### 2. Map Overlay (`map_overlay.lua`)

Renders quest locations on a zoomable/pannable map view.

**Data Sources:**
- Quest turn-in/accept NPCs from `QueryClient`
- Objective areas from profile YAML (routing policies)
- Player position (runtime)

**Rendering:**
- Background: zone map texture (if available) or solid color grid
- Markers: circles/rectangles for NPCs, quest objectives, areas
- Lines: routing policy paths
- Player: arrow indicator

**Interaction:**
- Scroll: zoom in/out
- Drag: pan map
- Click marker: show quest details

#### 3. Quest Browser (`quest_browser.lua`)

Lists available quests from the database with filtering.

**Features:**
- Query `QueryClient` for quests by zone, level range, faction
- Display: quest name, level, required level, rewards, prerequisites
- Search: text filter on quest name
- Drag: drag quest to statechart canvas to create state

**Integration:**
- Uses existing `QueryClient:get_quests_by_zone()`, `QueryClient:get_quest_details()`
- Shows prerequisite chains

#### 4. Dependency Graph (`dependency_graph.lua`)

Visualizes quest prerequisite chains as a directed acyclic graph.

**Data:**
- Quest prerequisites from `QueryClient`
- Profile's quest sequence from YAML states

**Rendering:**
- Nodes: quests (colored by status: available, active, completed)
- Edges: prerequisite relationships (arrow from prereq to dependent)
- Layout: topological sort (left-to-right or top-to-bottom)

#### 5. YAML Code Editor (`yaml_editor.lua`)

Text editor for direct YAML editing with syntax awareness.

**Features:**
- Line numbers
- Basic syntax highlighting (keywords, strings, numbers, comments)
- Error diagnostics (YAML parse errors highlighted)
- Auto-indent
- Find/replace (basic)

**Limitations:**
- No full syntax highlighting (Sylvannas fonts are limited)
- No code completion
- Uses monospace font (FONT_SMALL=0)

#### 6. Profile Save/Hot-Reload (`profile_hot_reload.lua`)

Handles saving and hot-reloading profiles.

**Flow:**
1. User clicks "Save" or presses Ctrl+S
2. `yaml_editor` serializes current state to YAML string
3. `ProfileCompiler` validates and compiles
4. If errors: show diagnostics in editor
5. If success: write to `scripts_data/quest_profiles/<id>.json`
6. Signal `StatechartExecutor` to hot-swap `CompiledProfile`
7. Executor preserves current state stack (history states)

### Integration Points

**Existing modules (survive):**
- `ProfileLoader` — load/list profiles from filesystem
- `ProfileCompiler` — validate and compile profiles
- `StatechartExecutor` — runtime execution
- `QueryClient` — quest database queries

**New modules:**
- `ProfileEditorWindow` — main editor window
- `ProfileEditorController` — orchestrates components
- `StatechartCanvas` — visual state machine
- `MapOverlay` — quest location rendering
- `QuestBrowser` — quest discovery
- `DependencyGraph` — prerequisite visualization
- `YamlEditor` — text editing
- `ProfileHotReload` — save/reload pipeline

---

## Implementation Plan

### Phase 1: Editor Shell + YAML Editor

| Task | Description | Module |
|------|-------------|--------|
| 1.1 | `ProfileEditorWindow` — new Sylvannas window with tab bar (Statechart, Map, Quests, Deps, Code) | `sentinel/ui/quest_ui/profile_editor/` |
| 1.2 | `YamlEditor` — text editor with line numbers, basic highlighting, error display | `sentinel/ui/quest_ui/profile_editor/yaml_editor.lua` |
| 1.3 | `ProfileEditorController` — owns profile data, coordinates save/load between components | `sentinel/ui/quest_ui/profile_editor/controller.lua` |
| 1.4 | Wire controller to existing `ProfileLoader` for load/save | Integration |

### Phase 2: Statechart Canvas

| Task | Description | Module |
|------|-------------|--------|
| 2.1 | `StatechartCanvas` — render states as nodes, transitions as bezier curves | `sentinel/ui/quest_ui/profile_editor/statechart_canvas.lua` |
| 2.2 | Node selection, hover tooltips, drag-to-move | Interaction |
| 2.3 | State property panel (edit type, onEnter/onExit actions, transitions) | Property panel |
| 2.4 | Add/delete states and transitions via context menu | Editing |
| 2.5 | Auto-layout algorithm (hierarchical tree layout) | Layout |

### Phase 3: Quest Browser + Dependency Graph

| Task | Description | Module |
|------|-------------|--------|
| 3.1 | `QuestBrowser` — query quests, filter by zone/level, display list | `sentinel/ui/quest_ui/profile_editor/quest_browser.lua` |
| 3.2 | `DependencyGraph` — render prerequisite DAG from quest data | `sentinel/ui/quest_ui/profile_editor/dependency_graph.lua` |
| 3.3 | Drag quest from browser to canvas to create state | Integration |

### Phase 4: Map Overlay + Hot-Reload

| Task | Description | Module |
|------|-------------|--------|
| 4.1 | `MapOverlay` — render zone map with NPC/objective markers | `sentinel/ui/quest_ui/profile_editor/map_overlay.lua` |
| 4.2 | Zoom/pan interaction, marker click for details | Interaction |
| 4.3 | `ProfileHotReload` — save YAML → compile → swap in executor | `sentinel/ui/quest_ui/profile_editor/hot_reload.lua` |
| 4.4 | Error diagnostics display (compile errors shown in editor) | Integration |

### Phase 5: Polish + Integration

| Task | Description | Module |
|------|-------------|--------|
| 5.1 | Connect statechart canvas to profile data model (bidirectional sync) | Integration |
| 5.2 | Keyboard shortcuts (Ctrl+S save, Ctrl+Z undo, Delete remove) | UX |
| 5.3 | Window persistence (remember position, size, active tab) | UX |
| 5.4 | Testing with real profiles (alliance_human_01_10_elwynn) | Validation |

---

## Acceptance Criteria

### Functional

- [ ] Profile editor opens as a new Sylvannas window
- [ ] YAML editor displays profile with line numbers and basic highlighting
- [ ] Statechart canvas renders all states and transitions from profile
- [ ] States can be selected, moved, and their properties edited
- [ ] Transitions can be added/deleted with event and guard fields
- [ ] Quest browser queries database and lists available quests
- [ ] Dependency graph shows prerequisite chains
- [ ] Map overlay shows NPC locations and objective areas
- [ ] Save button writes YAML to filesystem and hot-reloads executor
- [ ] Compile errors are displayed as diagnostics in the editor
- [ ] Hot-reload preserves current execution state (history states)

### Non-Functional

- [ ] Editor renders at 60fps with 100+ state nodes
- [ ] YAML editor handles 1000+ line profiles without lag
- [ ] Map overlay zooms smoothly from zone to continent view
- [ ] Hot-reload completes in <500ms

---

## File Structure

```
sentinel/ui/quest_ui/profile_editor/
├── init.lua                  -- ProfileEditorWindow entry point
├── controller.lua            -- ProfileEditorController
├── statechart_canvas.lua     -- StatechartCanvas
├── map_overlay.lua           -- MapOverlay
├── quest_browser.lua         -- QuestBrowser
├── dependency_graph.lua      -- DependencyGraph
├── yaml_editor.lua           -- YamlEditor
├── hot_reload.lua            -- ProfileHotReload
├── components/
│   ├── node.lua              -- StateNode rendering
│   ├── edge.lua              -- TransitionEdge rendering
│   ├── property_panel.lua    -- State/transition properties
│   └── context_menu.lua      -- Right-click menus
└── utils/
    ├── layout.lua            -- Auto-layout algorithms
    ├── zoom_pan.lua          -- Zoom/pan controller
    └── highlight.lua         -- YAML syntax highlighting
```
