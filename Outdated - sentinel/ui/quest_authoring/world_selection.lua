-- sentinel/ui/quest_authoring/world_selection.lua
-- In-game world selector: pick NPCs/objects in the world to populate action
-- fields. When a target is picked and an action is selected, the pane
-- auto-fills the action's args with the target's name, coordinates, and type.

local Panel        = require("ui/quest_authoring/panel")
local Theme        = require("ui/quest_authoring/theme")
local ActionSchema = require("ui/quest_authoring/action_schema")

local WorldSelectionPane = setmetatable({}, { __index = Panel })
WorldSelectionPane.__index = WorldSelectionPane

function WorldSelectionPane.new(ctx)
    local self = setmetatable(Panel.new(ctx, "WorldSel"), WorldSelectionPane)
    self._picking = false
    return self
end

local function cur_zone(ctx)
    local ok, core = pcall(require, "core")
    if ok and core and core.object_manager then
        local p = core.object_manager.get_player and core.object_manager:get_player()
        if p and p.zone then return p.zone end
    end
    return ctx._currentZone or "Unknown"
end

local function travel_estimate(ctx, target)
    local ok, core = pcall(require, "core")
    if ok and core and core.object_manager then
        local p = core.object_manager.get_player and core.object_manager:get_player()
        if p and p.position and target and target.x then
            local d = math.sqrt((p.position.x - target.x) ^ 2 + (p.position.y - target.y) ^ 2)
            return string.format("%.0f yd (~%.0fs)", d, d / 7)
        end
    end
    return "n/a"
end

-- Apply a world pick to the currently selected action's args.
local function apply_pick_to_action(ctx, pick)
    local sel = ctx:getSelected()
    if not sel or sel.kind ~= "action" then return false end
    local act = ctx:getAction(sel.opName, sel.id)
    if not act then return false end
    act.args = act.args or {}
    local atype = act.action_type or act.type

    -- Fill in common fields based on what exists in the schema
    if pick.name then
        -- Try to match the name to a schema field
        if act.args.npc_name ~= nil or atype == "TalkToNPC" or atype == "AcceptQuest"
            or atype == "TurnInQuest" or atype == "Vendor" or atype == "Repair" then
            act.args.npc_name = pick.name
        elseif act.args.creature_name ~= nil or atype == "KillCreature" then
            act.args.creature_name = pick.name
        elseif act.args.item_name ~= nil or atype == "Loot" or atype == "CollectItem" then
            act.args.item_name = pick.name
        elseif act.args.gameobject_name ~= nil or atype == "GoToGameObject" then
            act.args.gameobject_name = pick.name
        else
            -- Fallback: set the first string field in the schema
            local schema = ActionSchema.get(atype)
            if schema then
                for _, f in ipairs(schema.fields) do
                    if f.type == "string" and act.args[f.key] == nil then
                        act.args[f.key] = pick.name
                        break
                    end
                end
            end
        end
    end

    -- Fill coordinates
    if pick.x and pick.y then
        if act.args.target ~= nil and type(act.args.target) == "table" then
            act.args.target = { x = pick.x, y = pick.y, z = pick.z or 0 }
        elseif act.args.x ~= nil then
            act.args.x = pick.x
            act.args.y = pick.y
            if act.args.z ~= nil then act.args.z = pick.z or 0 end
        elseif atype == "TravelTo" then
            act.args.to = string.format("%.0f,%.0f,%.0f", pick.x, pick.y, pick.z or 0)
        elseif atype == "Marker" then
            act.args.x = pick.x
            act.args.y = pick.y
            act.args.z = pick.z or 0
            act.args.label = pick.name or ""
        else
            -- Store as target coordinates in args
            local schema = ActionSchema.get(atype)
            if schema then
                for _, f in ipairs(schema.fields) do
                    if f.key == "x" and act.args.x == nil then
                        act.args.x = pick.x
                        act.args.y = pick.y
                        if act.args.z ~= nil then act.args.z = pick.z or 0 end
                        break
                    end
                end
            end
        end
    end

    ctx:markDirty()
    return true
end

function WorldSelectionPane:draw()
    local ctx = self.ctx
    Panel.draw(self)
    local w = self.window
    if not w then return end

    local px, py, pw, ph = self._x, self._y, self._w, self._h
    local pad = 8
    local theme = Theme.theme
    local cy = py + 24

    self:_text(w, px + pad, cy, theme.text, "Zone: " .. cur_zone(ctx))
    cy = cy + 20

    -- Pick buttons
    if self:_button(w, px + pad, cy, 80, 18,
        self._picking and "Picking..." or "Pick World", theme) then
        self._picking = not self._picking
        if ctx._pick_fn then ctx:_pick_fn(self._picking) end
    end
    if self:_button(w, px + pad + 86, cy, 80, 18, "Pick Target", theme) then
        if ctx._tryPickTarget then ctx:_tryPickTarget() end
    end
    cy = cy + 24

    -- Pending pick result
    if ctx._pendingPick then
        local pk = ctx._pendingPick
        self:_text(w, px + pad, cy, theme.accent, "Picked: " .. tostring(pk.name or pk.type or "?"))
        cy = cy + 16
        self:_text(w, px + pad, cy, theme.text_dim, "Type: " .. tostring(pk.type or "?"))
        cy = cy + 14
        if pk.x then
            self:_text(w, px + pad, cy, theme.text_dim,
                string.format("Pos: %.0f, %.0f, %.0f", pk.x, pk.y or 0, pk.z or 0))
            cy = cy + 14
            self:_text(w, px + pad, cy, theme.text_dim, "Travel: " .. travel_estimate(ctx, pk))
            cy = cy + 14
        end

        -- Action: apply pick to selected action
        local sel = ctx:getSelected()
        if sel and sel.kind == "action" then
            if self:_button(w, px + pad, cy, pw - pad * 2, 18, "Apply to Selected Action", theme) then
                local ok = apply_pick_to_action(ctx, pk)
                if ok and ctx.logError then
                    ctx:logError("Applied " .. tostring(pk.name) .. " to action")
                end
            end
            cy = cy + 22
        else
            self:_text(w, px + pad, cy, theme.text_dim, "Select an action to apply")
            cy = cy + 14
        end

        -- Action: jump to location
        if self:_button(w, px + pad, cy, 80, 18, "Jump To", theme) then
            if ctx._jump_fn then ctx:_jump_fn(pk) end
        end
        cy = cy + 24
    else
        self:_text(w, px + pad, cy, theme.text_dim, "No world target selected")
        cy = cy + 16
        self:_text(w, px + pad, cy, theme.text_dim, "Target an NPC/object,")
        cy = cy + 14
        self:_text(w, px + pad, cy, theme.text_dim, "then click Pick Target.")
    end
end

return WorldSelectionPane
