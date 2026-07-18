-- sentinel/ui/quest_authoring/analytics_pane.lua
-- Profile complexity + coverage metrics derived from the last compile result.

local Panel = require("ui/quest_authoring/panel")
local Theme = require("ui/quest_authoring/theme")

local AnalyticsPane = setmetatable({}, { __index = Panel })
AnalyticsPane.__index = AnalyticsPane

function AnalyticsPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "Analytics"), AnalyticsPane)
    return self
end

local function metric(window, x, y, label, value, color)
    window:render_text(x, y, label, Theme.colors.text_dim)
    window:render_text(x, y + 16, tostring(value), color or Theme.colors.text)
end

function AnalyticsPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py = self._x, self._y
    local pad = 8
    local cy = py + 24

    local res = ctx.compileResult
    local profile = res and res.profile
    if not profile then
        w:render_text(px + pad, cy, "Compile to see analytics", Theme.colors.text_dim)
        return
    end

    local nStates = profile.states and (function()
        local n = 0; for _ in pairs(profile.states) do n = n + 1 end; return n
    end)() or 0
    local nRegions = profile.regions and (function()
        local n = 0; for _ in pairs(profile.regions) do n = n + 1 end; return n
    end)() or 0
    local nVars = profile.variables and (function()
        local n = 0; for _ in pairs(profile.variables) do n = n + 1 end; return n
    end)() or 0

    metric(w, px + pad, cy, "States", nStates, Theme.colors.accent); cy = cy + 40
    metric(w, px + pad + 120, py + 24, "Regions", nRegions, Theme.colors.accent)
    metric(w, px + pad + 240, py + 24, "Variables", nVars, Theme.colors.accent)

    -- Estimated completion: naive 30s/action placeholder.
    local nActions = 0
    if profile.states then
        for _id, st in pairs(profile.states) do
            if st.transitions and st.transitions.advance then
                nActions = nActions + 1
            end
        end
    end
    cy = py + 70
    metric(w, px + pad, cy, "Approx actions", nActions, Theme.colors.text); cy = cy + 40
    local estSec = nActions * 30
    local estMin = math.floor(estSec / 60)
    metric(w, px + pad, cy, "Est. completion", estMin .. " min (30s/act)", Theme.colors.warning); cy = cy + 40

    -- Eliminated (dead code) from the compiler
    local elim = res.eliminated or {}
    local nElim = 0
    for _k, v in pairs(elim) do
        if type(v) == "table" then nElim = nElim + #v else nElim = nElim + 1 end
    end
    metric(w, px + pad, cy, "Dead code removed", nElim, Theme.colors.green or Theme.colors.text)
    cy = cy + 40

    w:render_text(px + pad, cy, "Coverage: " .. (#(ctx.project and ctx.project.operations or {}) > 0 and "operations present" or "none"),
        Theme.colors.text_dim)
end

return AnalyticsPane
