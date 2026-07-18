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
