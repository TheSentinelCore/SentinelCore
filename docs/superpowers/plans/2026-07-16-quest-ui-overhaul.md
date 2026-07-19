# Quest UI Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul the existing Quest UI to use a Split-Pane layout featuring a settings sidebar and a runtime Statechart dashboard.

**Architecture:** Split the UI rendering logic into `sidebar.lua` and `dashboard.lua`. Refactor `window.lua` to draw the split-pane layout and coordinate between the sidebar and dashboard. Use the existing `window:render_rect` and `window:render_text` APIs. 

**Tech Stack:** SentinelCore Lua UI Framework (Sylvannas API)

## Global Constraints

- Sylvannas API only — never use WoW Lua APIs. API reference in Documentation - Project Sylvannas/dev/api/.
- Lua scripts are NOT built — loaded at runtime by Sylvannas injector. No compile step.
- Unit tests are not available for the Sylvannas UI environment. Manual testing will be performed in-game by loading a profile and verifying that transitions reflect immediately in the UI.

---

### Task 1: Create Sidebar Component

**Files:**
- Create: `sentinel/ui/quest_ui/sidebar.lua`

**Interfaces:**
- Produces: `Sidebar.draw(window, x, y, width, height, menu)`
- Consumes: The `menu` state table created in `window.lua`.

- [ ] **Step 1: Write the sidebar component**

```lua
local SentinelUI = require("ui/lib/sentinel_ui")
local Design = require("ui/quest_ui/design_system")
local vec2 = require("common/geometry/vector_2")

local Sidebar = {}

function Sidebar.draw(window, x, y, width, height, menu)
    -- Background
    window:render_rect(vec2.new(x, y), vec2.new(width, height), Design.Colors.neutral.surface, 0)
    window:render_rect_outline(vec2.new(x, y), vec2.new(width, height), Design.Colors.neutral.border, 1, 0)

    -- Settings Header
    window:render_text(0, vec2.new(x + 10, y + 10), Design.Colors.neutral.text_primary, "Settings")

    -- Checkbox logic using menu table
    local py = y + 40
    if menu.quest_skip_elites then
        local skip_elites = menu.quest_skip_elites:get_state()
        local color = skip_elites and Design.Colors.primary.main or Design.Colors.neutral.text_secondary
        window:render_text(0, vec2.new(x + 10, py), color, "Skip Elites: " .. tostring(skip_elites))
    end
end

return Sidebar
```

- [ ] **Step 2: Commit**

```bash
git add sentinel/ui/quest_ui/sidebar.lua
git commit -m "feat: add quest ui sidebar component"
```

---

### Task 2: Create Dashboard Component

**Files:**
- Create: `sentinel/ui/quest_ui/dashboard.lua`

**Interfaces:**
- Produces: `Dashboard.draw(window, x, y, width, height, app)`
- Consumes: `app:get_module("quest")` or `app:get_blackboard()`

- [ ] **Step 1: Write the dashboard component**

```lua
local SentinelUI = require("ui/lib/sentinel_ui")
local Design = require("ui/quest_ui/design_system")
local vec2 = require("common/geometry/vector_2")

local Dashboard = {}

function Dashboard.draw(window, x, y, width, height, app)
    -- Background
    window:render_rect(vec2.new(x, y), vec2.new(width, height), Design.Colors.neutral.background, 0)

    -- Top Info Bar
    window:render_text(0, vec2.new(x + 10, y + 10), Design.Colors.neutral.text_primary, "Active Routing Policy: N/A")

    -- Statechart Visualizer (Placeholder boxes for 3 regions)
    local box_y = y + 50
    local box_w = (width - 40) / 3
    
    -- Questing Region
    window:render_rect(vec2.new(x + 10, box_y), vec2.new(box_w, 100), Design.Colors.neutral.surface, 4)
    window:render_text(0, vec2.new(x + 15, box_y + 10), Design.Colors.neutral.text_primary, "Questing")
    
    -- Survival Region
    window:render_rect(vec2.new(x + 20 + box_w, box_y), vec2.new(box_w, 100), Design.Colors.neutral.surface, 4)
    window:render_text(0, vec2.new(x + 25 + box_w, box_y + 10), Design.Colors.neutral.text_primary, "Survival")
    
    -- Logistics Region
    window:render_rect(vec2.new(x + 30 + (box_w * 2), box_y), vec2.new(box_w, 100), Design.Colors.neutral.surface, 4)
    window:render_text(0, vec2.new(x + 35 + (box_w * 2), box_y + 10), Design.Colors.neutral.text_primary, "Logistics")
end

return Dashboard
```

- [ ] **Step 2: Commit**

```bash
git add sentinel/ui/quest_ui/dashboard.lua
git commit -m "feat: add quest ui dashboard component"
```

---

### Task 3: Refactor Main Window into Split-Pane

**Files:**
- Modify: `sentinel/ui/quest_ui/window.lua`

**Interfaces:**
- Consumes: `Sidebar` and `Dashboard` components.

- [ ] **Step 1: Refactor `window.lua` to draw the split pane**

```lua
-- Add these requires at the top:
local Sidebar = require("ui/quest_ui/sidebar")
local Dashboard = require("ui/quest_ui/dashboard")

-- In the draw function (or equivalent render loop inside the window layout):
-- Assume `window` is the rendering context, `app` is available via `_app`
-- and `_menu` holds the menu state.
function QuestWindow.draw_split_pane(window, x, y, width, height)
    local sidebar_w = 250
    local dashboard_x = x + sidebar_w
    local dashboard_w = width - sidebar_w
    
    Sidebar.draw(window, x, y, sidebar_w, height, _menu)
    Dashboard.draw(window, dashboard_x, y, dashboard_w, height, _app)
end
```
*(Note: As we don't have the exact draw method name from the current `window.lua` without full context, replace `QuestWindow.draw_split_pane` with the integration point used by the custom SentinelUI rendering system)*

- [ ] **Step 2: Remove old tab logic**
Remove `TABS` definition and tab-rendering loops from `sentinel/ui/quest_ui/window.lua`.

- [ ] **Step 3: Commit**

```bash
git add sentinel/ui/quest_ui/window.lua
git commit -m "refactor: integrate sidebar and dashboard in quest ui window"
```

---

### Task 4: Manual Testing (In-Game)

**Files:**
- N/A

- [ ] **Step 1: Launch Sylvannas and load the script**
- [ ] **Step 2: Open Sentinel UI and navigate to the Questing section**
- Verify the layout displays the Sidebar (250px) on the left and the Dashboard on the right.
- Verify settings toggle properly inside the sidebar.
- [ ] **Step 3: Start the Bot (Load a Profile)**
- Verify that the Statechart boxes (Questing, Survival, Logistics) correctly render their labels.
