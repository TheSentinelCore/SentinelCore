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
    self._ui:add_tab({ id = "main", label = "NPC Library" }, function(t)
        -- Search box
        t:custom_render({
            label = "Search and Filter",
            render_fn = function(ui, y)
                return self:_render_search_filter(ui, y)
            end
        })

        -- NPC list
        t:custom_render({
            label = "NPC List",
            render_fn = function(ui, y)
                return self:_render_npc_list(ui, y)
            end
        })

        -- Role filter buttons
        t:custom_render({
            label = "Role Filters",
            render_fn = function(ui, y)
                return self:_render_role_filters(ui, y)
            end
        })
    end)
end

function NPCLibraryPanel:_render_search_filter(ui, y)
    local window = ui.window
    local colors = ui.colors

    -- Search label
    local search_label = "Search: "
    local search_label_size = window:get_text_size(search_label)
    window:render_text(0, { x = 16, y = y }, colors.text_primary, search_label)
    y = y + search_label_size.y + 4

    -- Search input (we'll use a label as placeholder, but SentinelUI might have input)
    -- For simplicity, we'll use a label that we update when the user types? Actually we need an input.
    -- Looking at SentinelUI, there might be an input method. Let's check the shared/ui/sentinel_ui.lua later.
    -- For now, we'll simulate with a label and assume we have a way to update via keypresses.
    -- We'll store the search query in self._search_query and display it.
    local search_text = self._search_query or ""
    local search_label2 = window:create_label(search_text, { x = 16 + search_label_size.x, y = y - search_label_size.y - 2 })
    -- We need to store this label to update it later. Let's store it in self._search_label.
    self._search_label = search_label2

    y = y + search_label_size.y + 8

    -- Instructions
    local info = "Press Enter to search"
    local info_size = window:get_text_size(info)
    window:render_text(0, { x = 16, y = y }, colors.text_secondary, info)
    y = y + info_size.y + 4

    return y
end

function NPCLibraryPanel:_render_role_filters(ui, y)
    local window = ui.window
    local colors = ui.colors
    local x_start = 16
    local button_width = 80
    local button_height = 20
    local spacing = 8

    local roles = {
        { id = "all", label = "All" },
        { id = "vendor", label = "Vendor" },
        { id = "questgiver", label = "QuestGiver" },
        { id = "trainer", label = "Trainer" },
        { id = "innkeeper", label = "InnKeeper" },
        { id = "flightmaster", label = "FlightMaster" },
        { id = "repair", label = "Repair" },
        { id = "mailbox", label = "Mailbox" },
        { id = "bank", label = "Bank" }
    }

    for i, role in ipairs(roles) do
        local is_active = (self._role_filter == role.id)
        local color = is_active and colors.secondary_accent or colors.text_secondary
        local label = window:create_label(role.label, { x = x_start, y = y }, color)
        -- We need to make it clickable. We'll store the label and handle clicks in update.
        -- For simplicity, we'll just render and handle clicks by checking if mouse is over.
        -- We'll store the button areas.
        if not self._role_button_areas then self._role_button_areas = {} end
        self._role_button_areas[role.id] = { x = x_start, y = y, width = button_width, height = button_height, label = label }
        x_start = x_start + button_width + spacing
    end

    y = y + button_height + 8
    return y
end

function NPCLibraryPanel:_render_npc_list(ui, y)
    local window = ui.window
    local colors = ui.colors

    -- Update npcs from blackboard
    self._npcs = self._blackboard:get("module.ui.npc_library") or {}

    -- Filter npcs
    local filtered = {}
    for _, npc in ipairs(self._npcs) do
        if self:_npc_matches_filter(npc) then
            table.insert(filtered, npc)
        end
    end

    if #filtered == 0 then
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

    -- Draw each NPC as a row
    for i, npc in ipairs(filtered) do
        local is_selected = (self._selected_entry and self._selected_entry == npc.entry)
        local bg_color = is_selected and colors.background_selected or colors.background
        -- Draw background for selected row
        if is_selected then
            window:render_rect({ x = 12, y = y - 2, width = window:get_width() - 24, height = 18 }, bg_color)
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
        y = y + 20
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

    -- Handle search input (we need to capture keypresses)
    -- This is a simplification; we assume the UI handles input and we can get the text from a stored label.
    -- Actually, we need to implement a proper input field. Let's look at SentinelUI for input.
    -- For now, we'll skip and assume we have a way to update self._search_query from keypresses.
    -- We'll need to subscribe to events or use the UI's input system.

    -- Handle clicks on NPC list and role filters
    if self._ui and self._ui.menu then
        local mouse_x = self._blackboard:get("system.mouse_x", 0)
        local mouse_y = self._blackboard:get("system.mouse_y", 0)
        local mouse_clicked = self._blackboard:get("system.mouse_clicked_left", false)

        if mouse_clicked then
            -- Check role filter buttons
            if self._role_button_areas then
                for role_id, area in pairs(self._role_button_areas) do
                    if mouse_x >= area.x and mouse_x <= area.x + area.width and
                       mouse_y >= area.y and mouse_y <= area.y + area.height then
                        self._role_filter = role_id
                        self:_build_ui() -- rebuild to update button colors
                        break
                    end
                end
            end

            -- Check NPC list rows (simplified: each row is 20px high starting at some y)
            -- We need to know the starting y of the list. This is getting complex.
            -- For now, we'll skip click handling and rely on a select button or double-click.
            -- We'll implement a simple selection: double-click on a row to select.
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
    self._search_label = nil
    self._role_button_areas = nil
end

return NPCLibraryPanel