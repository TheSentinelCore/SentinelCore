-- sentinel/ui/panels/npc_library_panel.lua
-- Searchable list of captured NPCs

local SentinelUI = require("shared/ui/sentinel_ui")

local NPCLibraryPanel = {}
NPCLibraryPanel.__index = NPCLibraryPanel

function NPCLibraryPanel:new(blackboard, event_bus)
    local o = setmetatable({}, NPCLibraryPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._search_query = ""
    o._role_filter = "all" -- all, vendor, questgiver, trainer, innkeeper, flightmaster, repair, mailbox, bank
    o._selected_entry = nil
    o._npcs = {} -- cached copy from blackboard
    o._npc_row_areas = {} -- { [index] = { x, y, w, h, entry } } for click detection
    o._list_start_y = nil -- y position where the NPC list starts rendering
    o._filtered_npcs = {} -- cached filtered list for click tracking
    return o
end

function NPCLibraryPanel:init()
    self._ui = SentinelUI.new({
        id = "npc_library_panel",
        title = "NPC Library",
        default_x = 200,
        default_y = 200,
        default_w = 500,
        default_h = 600,
        theme = "sentinel",
    })

    self:_build_ui()
    return true
end

function NPCLibraryPanel:_build_ui()
    self._ui:clear()
    self._ui:add_tab({ id = "main", label = "NPC Library" }, function(t)
        -- Search input (uses SentinelUI's built-in text input)
        t:text_input_list({
            label = "Search",
            id = "npc_search",
            elements = {
                {
                    label = "Filter:",
                    id = "npc_search_input",
                    value_fn = function() return self._search_query end,
                    on_change = function(value)
                        self._search_query = value or ""
                    end,
                    placeholder = "Type to filter by name...",
                }
            }
        })

        -- Role filter buttons
        t:custom_render({
            label = "Role Filters",
            render_fn = function(ui, y)
                return self:_render_role_filters(ui, y)
            end
        })

        -- NPC list
        t:custom_render({
            label = "NPC List",
            render_fn = function(ui, y)
                return self:_render_npc_list(ui, y)
            end
        })
    end)
end

local ROLE_DEFS = {
    { id = "all", label = "All" },
    { id = "vendor", label = "Vendor" },
    { id = "questgiver", label = "QuestGiver" },
    { id = "trainer", label = "Trainer" },
    { id = "innkeeper", label = "InnKeeper" },
    { id = "flightmaster", label = "FlightMaster" },
    { id = "repair", label = "Repair" },
    { id = "mailbox", label = "Mailbox" },
    { id = "bank", label = "Bank" },
}

function NPCLibraryPanel:_render_role_filters(ui, y)
    local window = ui.window
    local c = ui.colors
    local x_start = 16
    local bw = 76
    local bh = 20
    local spacing = 4

    -- Build fresh areas each frame
    self._role_button_areas = {}
    local x = x_start

    for _, role in ipairs(ROLE_DEFS) do
        local is_active = (self._role_filter == role.id)
        local start_pos = { x = x, y = y }
        local end_pos = { x = x + bw, y = y + bh }

        -- Background
        local bg = is_active and c.primary_accent or c.checkbox_inactive
        window:render_rect_filled(start_pos, end_pos, bg, 3.0)
        window:render_rect(start_pos, end_pos, c.section_border, 3.0, 1.0)

        -- Label
        local text_c = is_active and { r = 255, g = 255, b = 255, a = 255 } or c.text_secondary
        local ts = window:get_text_size(role.label)
        local tx = x + (bw - ts.x) / 2
        local ty = y + (bh - ts.y) / 2
        window:render_text(0, { x = tx, y = ty }, text_c, role.label)

        window:is_mouse_hovering_rect_block_movement(start_pos, end_pos)

        -- Store area for click detection in update()
        self._role_button_areas[role.id] = { x = x, y = y, w = bw, h = bh }
        x = x + bw + spacing
    end

    return y + bh + 8
end

function NPCLibraryPanel:_render_npc_list(ui, y)
    local window = ui.window
    local colors = ui.colors

    -- Update npcs from blackboard
    self._npcs = self._blackboard:get("module.ui.npc_library") or {}

    -- Filter npcs
    self._filtered_npcs = {}
    self._npc_row_areas = {}
    for _, npc in ipairs(self._npcs) do
        if self:_npc_matches_filter(npc) then
            table.insert(self._filtered_npcs, npc)
        end
    end

    self._list_start_y = y

    if #self._filtered_npcs == 0 then
        local empty_text = "No NPCs captured yet. Target an NPC in-game and use Capture (Ctrl+N)."
        local empty_size = window:get_text_size(empty_text)
        window:render_text(0, { x = 16, y = y }, colors.text_secondary, empty_text)
        return y + empty_size.y + 20
    end

    -- Table header
    local header_y = y
    window:render_text(0, { x = 16, y = header_y }, colors.text_primary, "Name")
    window:render_text(0, { x = 160, y = header_y }, colors.text_primary, "Entry")
    window:render_text(0, { x = 240, y = header_y }, colors.text_primary, "Zone")
    window:render_text(0, { x = 320, y = header_y }, colors.text_primary, "Roles")
    y = header_y + 20

    local row_height = 20
    local row_w = window:get_width() and window:get_width() - 24 or 200

    -- Draw each NPC as a row
    for i, npc in ipairs(self._filtered_npcs) do
        local is_selected = (self._selected_entry and self._selected_entry == npc.entry)
        local bg_color = is_selected and (colors.listbox_selected or colors.background_selected) or colors.background
        -- Draw background for selected row
        if is_selected then
            window:render_rect({ x = 12, y = y - 2, width = row_w, height = row_height }, bg_color)
        end

        local name = npc.name or "Unknown"
        local entry = npc.entry or 0
        local zone = npc.zone or "Unknown"
        local roles = npc.roles or {}
        local role_text = table.concat(roles, ", ")

        window:render_text(0, { x = 16, y = y }, colors.text_primary, name)
        window:render_text(0, { x = 160, y = y }, colors.text_primary, tostring(entry))
        window:render_text(0, { x = 240, y = y }, colors.text_primary, zone)
        window:render_text(0, { x = 320, y = y }, colors.text_primary, role_text)

        -- Store row area for click detection
        self._npc_row_areas[i] = {
            x = 12, y = y - 2, w = row_w, h = row_height,
            entry = npc.entry,
        }

        y = y + row_height
    end

    return y + 10
end

function NPCLibraryPanel:_npc_matches_filter(npc)
    -- Search filter
    if self._search_query and self._search_query ~= "" then
        local name = (npc.name or ""):lower()
        if not name:find(self._search_query:lower(), 1, true) then
            return false
        end
    end

    -- Role filter
    if self._role_filter ~= "all" then
        local roles = npc.roles or {}
        local found = false
        for _, role in pairs(roles) do
            if role == self._role_filter then
                found = true
                break
            end
        end
        if not found then return false end
    end

    return true
end

function NPCLibraryPanel:update()
    -- Update npcs from blackboard
    self._npcs = self._blackboard:get("module.ui.npc_library") or {}

    if self._ui and self._ui.update then
        self._ui:update()
    end

    -- Handle mouse clicks for role filters and NPC row selection.
    -- We read input state from the UI's own mouse query since these are ImGui-style
    -- windows that handle their own input; blackboard-based input is unreliable here.
    if self._ui and self._ui.window then
        local w = self._ui.window
        local mouse_clicked = false
        -- Check if the window itself was clicked (left mouse button clicked anywhere)
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
                -- Check role filter buttons
                if self._role_button_areas then
                    for role_id, area in pairs(self._role_button_areas) do
                        if mx >= area.x and mx <= area.x + area.w and
                           my >= area.y and my <= area.y + area.h then
                            self._role_filter = role_id
                            self:_build_ui()
                            return
                        end
                    end
                end

                -- Check NPC list row selection
                for _, row in ipairs(self._npc_row_areas or {}) do
                    if mx >= row.x and mx <= row.x + row.w and
                       my >= row.y and my <= row.y + row.h then
                        self._selected_entry = row.entry
                        return
                    end
                end
            end
        end
    end
end

function NPCLibraryPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function NPCLibraryPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function NPCLibraryPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function NPCLibraryPanel:shutdown()
    self._ui = nil
    self._role_button_areas = nil
    self._npc_row_areas = nil
    self._filtered_npcs = nil
end

return NPCLibraryPanel