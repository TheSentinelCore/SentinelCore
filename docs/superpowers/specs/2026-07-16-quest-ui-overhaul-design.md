# Quest UI Overhaul Design

## Overview
This design overhauls the existing `sentinel/ui/quest_ui/window.lua` to fit the new questing module (ADR-0004), transitioning from simple configuration tabs to a powerful runtime dashboard using a split-pane layout.

## Goals
- Expose the Statechart Executor's inner workings to the player visually.
- Allow quick adjustments to common settings (Skip Elites, Flee Thresholds) while actively monitoring the statechart.
- Keep the UI clean but informative.

## Architecture & Layout
- **Layout Approach**: Split-Pane Layout.
- **Header**: Contains a Hamburger Menu to toggle the Sidebar, current profile name, and a Start/Stop toggle button.
- **Sidebar (Collapsible)**:
  - Settings sections for Questing, Survival, and Logistics.
  - Controls to adjust options like `quest_skip_elites`, `quest_max_travel`, `health_flee` thresholds.
- **Main Dashboard**:
  - **Top Bar**: Shows Active Routing Policy and Current Goal.
  - **Statechart Visualization**: Renders the 3 parallel regions (Questing, Survival, Logistics) side-by-side, displaying the current active leaf state in each region.
  - **Event/Transition Log**: A scrolling text console showing `StatechartExecutor` events and state transitions.

## Data Flow
- The UI will read from the `app:get_blackboard()` and listen to the `event_bus` for state transitions (`TRANSITION`, `EVENT`).
- Settings changes in the sidebar will immediately update the blackboard (e.g., `module.quest.skip_elites`) or the module settings table.
- The Statechart visualizer will query the `StatechartExecutor` (via `get_active_states()`) to update the active nodes in the UI.

## Components
- `sentinel/ui/quest_ui/window.lua`: Will be rewritten to handle the new split-pane container and hamburger menu logic.
- `sentinel/ui/quest_ui/sidebar.lua`: New component isolating the settings sliders and checkboxes.
- `sentinel/ui/quest_ui/dashboard.lua`: New component encapsulating the top info bar, statechart regions visualizer, and the log console.

## Error Handling
- Invalid profiles or missing statecharts will display a graceful "No Profile Loaded" or "Statechart Offline" message in the dashboard area.
- If the `event_bus` is spammed, the log console will prune old messages (e.g., keeping only the last 50 events) to prevent UI lag.

## Testing
- Unit tests are not available for the Sylvannas UI environment.
- Manual testing will be performed in-game by loading `Elwynn_Forest_1_10` (or similar) and verifying that transitions (e.g., entering combat -> Fleeing) reflect immediately in the UI.
