-- sentinel/ui/panels/quest_browser_panel.lua
-- Browser for QueryServer quest data

local SentinelUI = require("shared/ui/sentinel_ui")
local JSON = require("lib/JSON")

local QuestBrowserPanel = {}
QuestBrowserPanel.__index = QuestBrowserPanel

function QuestBrowserPanel:new(blackboard, event_bus, query_client)
    local o = setmetatable({}, QuestBrowserPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._query_client = query_client
    o._ui = nil
    o._search_query = ""
    o._search_results = {} -- list of quests
    o._selected_quest = nil -- currently expanded quest
    o._is_searching = false
    o._result_row_areas = {} -- [index] = { x, y, w, h, quest_id } for click detection
    o._results_start_y = nil
    return o
end

function QuestBrowserPanel:init()
    self._ui = SentinelUI.new({
        id = "quest_browser_panel",
        title = "Quest Browser",
        default_x = 400,
        default_y = 100,
        default_w = 500,
        default_h = 600,
        theme = "sentinel",
    })

    self:_build_ui()
    return true
end

function QuestBrowserPanel:_build_ui()
    self._ui:clear()
    self._ui:add_tab({ id = "main", label = "Quest Search" }, function(t)
        -- Search input (uses SentinelUI's built-in text input)
        t:text_input_list({
            label = "Search",
            id = "quest_search",
            elements = {
                {
                    label = "Query:",
                    id = "quest_search_input",
                    value_fn = function() return self._search_query end,
                    on_change = function(value)
                        self._search_query = value or ""
                        self:_perform_search()
                    end,
                    placeholder = "Type quest name and press Enter...",
                }
            }
        })

        -- Search results
        t:custom_render({
            label = "Results",
            render_fn = function(ui, y)
                return self:_render_search_results(ui, y)
            end
        })

        -- Quest details (when selected)
        t:custom_render({
            label = "Quest Details",
            render_fn = function(ui, y)
                return self:_render_quest_details(ui, y)
            end
        })

        -- Action buttons
        t:custom_render({
            label = "Actions",
            render_fn = function(ui, y)
                return self:_render_action_buttons(ui, y)
            end
        })
    end)
end

function QuestBrowserPanel:_render_search_results(ui, y)
    local window = ui.window
    local colors = ui.colors

    if self._is_searching then
        local searching = "Searching..."
        local size = window:get_text_size(searching)
        window:render_text(0, { x = 16, y = y }, colors.text_secondary, searching)
        return y + size.y + 10
    end

    self._results_start_y = y
    self._result_row_areas = {}

    if #self._search_results == 0 then
        if self._search_query and self._search_query ~= "" then
            local none = "No quests found for '" .. self._search_query .. "'"
            local size = window:get_text_size(none)
            window:render_text(0, { x = 16, y = y }, colors.text_secondary, none)
            return y + size.y + 10
        else
            local empty = "Type to search quests..."
            local size = window:get_text_size(empty)
            window:render_text(0, { x = 16, y = y }, colors.text_secondary, empty)
            return y + size.y + 10
        end
    end

    -- Table header
    local header_y = y
    window:render_text(0, { x = 16, y = header_y }, colors.text_primary, "Title")
    window:render_text(0, { x = 260, y = header_y }, colors.text_primary, "Level")
    window:render_text(0, { x = 300, y = header_y }, colors.text_primary, "Zone")
    window:render_text(0, { x = 400, y = header_y }, colors.text_primary, "Giver")
    y = header_y + 20

    local row_h = 20
    local row_w = window:get_width() and window:get_width() - 24 or 300

    -- Results
    for i, quest in ipairs(self._search_results) do
        local is_selected = (self._selected_quest and self._selected_quest.id == quest.id)
        local bg_color = is_selected and (colors.listbox_selected or colors.background_selected) or colors.background
        if is_selected then
            window:render_rect({ x = 12, y = y - 2, width = row_w, height = row_h }, bg_color)
        end

        local title = quest.title or "Unknown"
        local level = quest.level or "?"
        local zone = quest.zone or "Unknown"
        local giver = quest.giver_name or "Unknown"

        window:render_text(0, { x = 16, y = y }, colors.text_primary, title)
        window:render_text(0, { x = 260, y = y }, colors.text_primary, tostring(level))
        window:render_text(0, { x = 300, y = y }, colors.text_primary, zone)
        window:render_text(0, { x = 400, y = y }, colors.text_primary, giver)

        -- Store clickable row area
        self._result_row_areas[i] = {
            x = 12, y = y - 2, w = row_w, h = row_h,
            quest = quest,
        }

        y = y + row_h
    end

    return y + 10
end

function QuestBrowserPanel:_render_quest_details(ui, y)
    local window = ui.window
    local colors = ui.colors

    if not self._selected_quest then
        local none = "Select a quest to see details"
        local size = window:get_text_size(none)
        window:render_text(0, { x = 16, y = y }, colors.text_secondary, none)
        return y + size.y + 10
    end

    local quest = self._selected_quest

    local function render_field(label, value)
        if value == nil then value = "N/A" end
        if type(value) == "table" then
            value = table.concat(value, ", ")
        end
        local text = label .. ": " .. tostring(value)
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, colors.text_primary, text)
        return y + text_size.y + 4
    end

    y = render_field("Title", quest.title)
    y = render_field("ID", quest.id)
    y = render_field("Level", quest.level)
    y = render_field("Zone", quest.zone)
    y = render_field("Giver", quest.giver_name)
    y = render_field("Required Level", quest.required_level)
    y = render_field("Repeatable", quest.repeatable and "Yes" or "No")
    y = render_field("Daily", quest.daily and "Yes" or "No")
    y = render_field("Quest Type", quest.quest_type)

    -- Objectives
    y = y + 10
    window:render_text(0, { x = 16, y = y }, colors.text_primary, "Objectives:")
    y = y + 20
    if quest.objectives and #quest.objectives > 0 then
        for _, obj in ipairs(quest.objectives) do
            local obj_text = "- " .. (obj.description or "Unknown objective")
            local obj_size = window:get_text_size(obj_text)
            window:render_text(0, { x = 20, y = y }, colors.text_secondary, obj_text)
            y = y + obj_size.y + 2
        end
else
            local none = "- None"
            local size = window:get_text_size(none)
            window:render_text(0, { x = 20, y = y }, colors.text_secondary, none)
            y = y + size.y + 2
    end

    -- Rewards
    y = y + 10
    window:render_text(0, { x = 16, y = y }, colors.text_primary, "Rewards:")
    y = y + 20
    if quest.rewards and #quest.rewards > 0 then
        for _, reward in ipairs(quest.rewards) do
            local reward_text = "- " .. (reward.description or "Unknown reward")
            local reward_size = window:get_text_size(reward_text)
            window:render_text(0, { x = 20, y = y }, colors.text_secondary, reward_text)
            y = y + reward_size.y + 2
        end
    else
        local none = "- None"
        local size = window:get_text_size(none)
        window:render_text(0, { x = 20, y = y }, colors.text_secondary, none)
        y = y + size.y + 2
    end

    return y + 10
end

function QuestBrowserPanel:_render_action_buttons(ui, y)
    local window = ui.window
    local colors = ui.colors
    local button_width = 120
    local button_height = 20
    local spacing = 10
    local x_start = 16

    -- Only show buttons if a quest is selected
    if self._selected_quest then
        local pickup_btn = window:create_button("Add PickupQuest", { x = x_start, y = y, width = button_width, height = button_height })
        self._pickup_button = pickup_btn
        x_start = x_start + button_width + spacing

        local turnin_btn = window:create_button("Add TurnInQuest", { x = x_start, y = y, width = button_width, height = button_height })
        self._turnin_button = turnin_btn
        x_start = x_start + button_width + spacing

        local preview_btn = window:create_button("Preview Chain", { x = x_start, y = y, width = button_width, height = button_height })
        self._preview_button = preview_btn
    end

    return y + button_height + 10
end

function QuestBrowserPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end

    -- Handle clicks on search result rows for selection
    if self._ui and self._ui.window then
        local w = self._ui.window
        local mouse_clicked = false
        if w.is_mouse_button_clicked then
            mouse_clicked = w:is_mouse_button_clicked(0)
        end

        if mouse_clicked then
            local mx, my = nil, nil
            if w.get_mouse_pos then
                local ok, pos = pcall(function() return w:get_mouse_pos() end)
                if ok and pos then
                    mx = pos.x
                    my = pos.y
                end
            end

            if mx and my then
                -- Check search result row clicks
                for _, row in ipairs(self._result_row_areas or {}) do
                    if mx >= row.x and mx <= row.x + row.w and
                       my >= row.y and my <= row.y + row.h then
                        self._selected_quest = row.quest
                        return
                    end
                end

                -- Check action button clicks
                if self._pickup_button and self._ui.window then
                    -- The button click is handled by the button creation callbacks
                    -- (SentinelUI button API handles its own click detection)
                end
            end
        end
    end
end

function QuestBrowserPanel:_perform_search()
    if not self._search_query or self._search_query == "" then
        self._search_results = {}
        return
    end

    self._is_searching = true
    self._query_client:search_quests(self._search_query, function(data, err)
        self._is_searching = false
        if err then
            if self._event_bus then
                self._event_bus:publish("log:editor", { level = "ERROR", message = "[QuestBrowser] Search error: " .. err })
            end
            self._search_results = {}
        else
            self._search_results = data or {}
        end
    end)
end

function QuestBrowserPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function QuestBrowserPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function QuestBrowserPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function QuestBrowserPanel:shutdown()
    self._ui = nil
    self._search_label = nil
    self._pickup_button = nil
    self._turnin_button = nil
    self._preview_button = nil
    self._result_row_areas = nil
end

return QuestBrowserPanel