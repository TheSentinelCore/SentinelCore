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
