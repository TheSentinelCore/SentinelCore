-- sentinel/ui/panels/action_palette_panel.lua
-- Categorized list of all action types with drag/drop support

local SentinelUI = require("shared/ui/sentinel_ui")

local ActionPalettePanel = {}
ActionPalettePanel.__index = ActionPalettePanel

-- Action categories and types
local ACTION_CATEGORIES = {
    movement = {
        label = "Movement",
        icon = "👟",
        actions = {
            { type = "goto", label = "Go To", description = "Navigate to a position or target" },
            { type = "record_path", label = "Record Path", description = "Record a movement path" },
        },
    },
    combat = {
        label = "Combat",
        icon = "⚔️",
        actions = {
            { type = "grind_area", label = "Grind Area", description = "Kill mobs in area" },
            { type = "kill_target", label = "Kill Target", description = "Kill specific target" },
        },
    },
    quest = {
        label = "Quest",
        icon = "📜",
        actions = {
            { type = "pickup_quest", label = "Pickup Quest", description = "Accept a quest from NPC" },
            { type = "turn_in_quest", label = "Turn In Quest", description = "Complete a quest" },
        },
    },
    npc_interaction = {
        label = "NPC Interaction",
        icon = "👤",
        actions = {
            { type = "vendor", label = "Vendor", description = "Sell items to vendor" },
            { type = "repair", label = "Repair", description = "Repair equipment" },
            { type = "train", label = "Train", description = "Train spells/skills" },
            { type = "flight_path", label = "Flight Path", description = "Take flight path" },
            { type = "mailbox", label = "Mailbox", description = "Check/send mail" },
            { type = "bank", label = "Bank", description = "Use bank" },
            { type = "talk_to_npc", label = "Talk to NPC", description = "Interact with NPC" },
        },
    },
    inventory = {
        label = "Inventory",
        icon = "🎒",
        actions = {
            { type = "use_item", label = "Use Item", description = "Use an item" },
        },
    },
    flow_control = {
        label = "Flow Control",
        icon = "🔄",
        actions = {
            { type = "branch", label = "Branch", description = "Conditional branching" },
            { type = "set_variable", label = "Set Variable", description = "Set a variable value" },
            { type = "wait", label = "Wait", description = "Wait for duration" },
        },
    },
    special = {
        label = "Special",
        icon = "⭐",
        actions = {
            { type = "dungeon_marker", label = "Dungeon Marker", description = "Mark dungeon location" },
            { type = "death_skip", label = "Death Skip", description = "Release spirit and skip corpse" },
            { type = "hearth", label = "Hearth", description = "Use hearthstone" },
        },
    },
}

-- Blueprint templates
local BLUEPRINT_TEMPLATES = {
    {
        id = "level_quest_chain",
        name = "Level Quest Chain",
        description = "Complete a chain of quests for leveling",
    },
    {
        id = "grind_vendor_loop",
        name = "Grind + Vendor Loop",
        description = "Grind mobs, then vendor and repair",
    },
    {
        id = "flight_path_unlock",
        name = "Flight Path Unlock",
        description = "Unlock and use flight paths",
    },
}

function ActionPalettePanel:new(blackboard, event_bus)
    local o = setmetatable({}, ActionPalettePanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._expanded_categories = {} -- category_id -> bool
    o._search_text = ""
    o._show_blueprints = true
    return o
end

function ActionPalettePanel:init()
    self._ui = SentinelUI.new({
        id = "action_palette",
        title = "Action Palette",
        default_x = 100,
        default_y = 100,
        default_w = 300,
        default_h = 500,
        theme = "sentinel",
    })
    
    -- Initialize all categories as expanded
    for cat_id, _ in pairs(ACTION_CATEGORIES) do
        self._expanded_categories[cat_id] = true
    end
    
    -- Main Actions tab
    self._ui:add_tab({ id = "actions", label = "Actions" }, function(t)
        t:row_list({
            id = "search_row",
            elements = {
                {
                    type = "info",
                    label = "Search",
                    value = "",
                    on_change = function(new_val)
                        self._search_text = new_val
                    end,
                },
            },
        })
        
        -- Render categories
        for cat_id, category in pairs(ACTION_CATEGORIES) do
            local cat_visible = self:_is_category_visible(category)
            if cat_visible then
                t:row_list({
                    id = "cat_header_" .. cat_id,
                    elements = self:_build_category_header(category),
                })
                
                if self._expanded_categories[cat_id] then
                    t:listbox({
                        id = "cat_list_" .. cat_id,
                        entries_fn = function()
                            local entries = {}
                            for _, action in ipairs(category.actions) do
                                if self:_matches_search(action) then
                                    table.insert(entries, {
                                        label = action.label,
                                        sublabel = action.type,
                                        action_type = action.type,
                                        action_data = action,
                                    })
                                end
                            end
                            return entries
                        end,
                        on_select = function(idx, entry)
                            self:_on_action_selected(entry.action_data.type)
                        end,
                        visible_rows = 6,
                    })
                end
            end
        end
    end)
    
    -- Blueprints tab
    self._ui:add_tab({ id = "blueprints", label = "Blueprints" }, function(t)
        t:listbox({
            id = "blueprint_list",
            entries_fn = function()
                local entries = {}
                for _, bp in ipairs(BLUEPRINT_TEMPLATES) do
                    table.insert(entries, {
                        label = bp.name,
                        sublabel = bp.description,
                        blueprint_data = bp,
                    })
                end
                return entries
            end,
            on_select = function(idx, entry)
                self:_on_blueprint_selected(entry.blueprint_data)
            end,
            visible_rows = 8,
        })
    end)
    
    return true
end

function ActionPalettePanel:_is_category_visible(category)
    if self._search_text == "" then
        return true
    end
    for _, action in ipairs(category.actions) do
        if self:_matches_search(action) then
            return true
        end
    end
    return false
end

function ActionPalettePanel:_matches_search(action)
    if self._search_text == "" then
        return true
    end
    local search = string.lower(self._search_text)
    local label = string.lower(action.label or "")
    local desc = string.lower(action.description or "")
    local atype = string.lower(action.type or "")
    return label:find(search, 1, true) or desc:find(search, 1, true) or atype:find(search, 1, true)
end

function ActionPalettePanel:_build_category_header(category)
    local collapsed = not self._expanded_categories[category.label]
    return {
        {
            type = "button",
            label = category.label .. " " .. (collapsed and "▶" or "▼"),
            text = collapsed and "▶" or "▼",
            on_click = function()
                self._expanded_categories[category.label] = not self._expanded_categories[category.label]
            end,
        },
    }
end

function ActionPalettePanel:_on_action_selected(action_type)
    if self._event_bus and self._event_bus.publish then
        self._event_bus:publish("action:add", {
            type = action_type,
        })
    end
end

function ActionPalettePanel:_on_blueprint_selected(blueprint)
    if self._event_bus and self._event_bus.publish then
        self._event_bus:publish("blueprint:add", {
            blueprint_id = blueprint.id,
            blueprint_data = blueprint,
        })
    end
end

function ActionPalettePanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function ActionPalettePanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function ActionPalettePanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function ActionPalettePanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function ActionPalettePanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function ActionPalettePanel:shutdown()
    self._ui = nil
end

return ActionPalettePanel