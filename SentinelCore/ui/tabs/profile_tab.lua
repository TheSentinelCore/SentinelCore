-- SentinelCore/ui/tabs/profile_tab.lua
--
-- Profile browser + editor tab for the Sentinel Control Center.
-- Two modes: "browse" (list / load / unload / delete) and "edit" (record + metadata form).

local vec2   = require("common/geometry/vector_2")
local enums  = require("common/enums")
local color  = require("common/color")
local AstroUI = require("lib/AstroUI")
local TimeHelper = require("lib/TimeHelper")
local Schema    = require("profiles/ProfileSchema")
local Validator = require("profiles/ProfileValidator")

local LAYOUT = AstroUI.LAYOUT
local get_now = TimeHelper.get_now

--------------------------------------------------------------------------------
-- Module state
--------------------------------------------------------------------------------

local profile_tab = {}

local _editor_mode = "browse"   -- "browse" | "edit"
local _selected_profile_index = 1
local _last_profile_result = nil

-- Persistent menu elements (created once)
local _elements_created = false
local _el_name           = nil  ---@type text_input|nil
local _el_min_level      = nil  ---@type slider_int|nil
local _el_max_level      = nil  ---@type slider_int|nil
local _el_target_min     = nil  ---@type slider_int|nil
local _el_target_max     = nil  ---@type slider_int|nil
local _el_npc_blacklist  = nil  ---@type text_input|nil
local _el_npc_whitelist  = nil  ---@type text_input|nil
local _el_loop           = nil  ---@type checkbox|nil
local _el_dry_spell      = nil  ---@type slider_int|nil
local _el_hs_radius      = nil  ---@type slider_int|nil
local _el_filename       = nil  ---@type text_input|nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

---@param base_color color
---@param amount number
---@return color
local function lighten_color(base_color, amount)
    local r, g, b, a = base_color:get()
    return color.new(
        math.min(255, r + amount),
        math.min(255, g + amount),
        math.min(255, b + amount),
        a
    )
end

---@param window any
---@param colors table
---@param bx number
---@param bw number
---@param y_offset number
---@param button_h number
---@param label string
---@param enabled boolean
---@return boolean clicked
local function make_btn(window, colors, bx, bw, y_offset, button_h, label, enabled)
    local s = vec2.new(bx, y_offset)
    local e = vec2.new(bx + bw, y_offset + button_h)
    local hov = enabled and window:is_mouse_hovering_rect(s, e) or false
    if hov then window:is_mouse_hovering_rect_block_movement(s, e) end
    local bg = enabled
        and (hov and lighten_color(colors.primary_accent, 15) or colors.primary_accent)
        or colors.checkbox_inactive
    window:render_rect_filled(s, e, bg, 8)
    local ts = window:get_text_size(label)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(bx + (bw - ts.x) / 2, y_offset + (button_h - ts.y) / 2),
        enabled and colors.text_primary or colors.text_disabled, label)
    return enabled and hov and window:is_rect_clicked(s, e)
end

--- Parse a comma-separated string of integer IDs into a list.
---@param text string
---@return number[]
local function parse_id_list(text)
    local ids = {}
    if type(text) ~= "string" or text == "" then return ids end
    for token in text:gmatch("[^,]+") do
        local n = tonumber(token:match("^%s*(.-)%s*$"))
        if n and n > 0 then
            ids[#ids + 1] = math.floor(n)
        end
    end
    return ids
end

--- Join a list of numbers to comma-separated string.
---@param list number[]|nil
---@return string
local function join_id_list(list)
    if type(list) ~= "table" or #list == 0 then return "" end
    local parts = {}
    for i = 1, #list do
        parts[i] = tostring(list[i])
    end
    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Edit-mode lifecycle
--------------------------------------------------------------------------------

local function create_elements()
    if _elements_created then return end
    _el_name          = core.menu.text_input("sc_pe_name", false)
    _el_min_level     = core.menu.slider_int(1, 80, 1, "sc_pe_min_level")
    _el_max_level     = core.menu.slider_int(1, 80, 80, "sc_pe_max_level")
    _el_target_min    = core.menu.slider_int(1, 80, 1, "sc_pe_target_min")
    _el_target_max    = core.menu.slider_int(1, 80, 80, "sc_pe_target_max")
    _el_npc_blacklist = core.menu.text_input("sc_pe_npc_bl", false)
    _el_npc_whitelist = core.menu.text_input("sc_pe_npc_wl", false)
    _el_loop          = core.menu.checkbox(true, "sc_pe_loop")
    _el_dry_spell     = core.menu.slider_int(5, 120, 15, "sc_pe_dry_spell")
    _el_hs_radius     = core.menu.slider_int(5, 120, 40, "sc_pe_hs_radius")
    _el_filename      = core.menu.text_input("sc_pe_filename", false)
    _elements_created = true
end

--- Sync form element values into the working profile on blackboard every frame.
---@param client table
local function sync_form_to_profile(client)
    local recorder = client._services.profile_recorder
    local wp = recorder:get_working_profile()
    if not wp then return end

    -- Metadata
    wp.metadata.name = _el_name:get_text()

    -- Requirements
    wp.requirements.min_level = _el_min_level:get()
    wp.requirements.max_level = _el_max_level:get()

    -- Target defaults
    wp.target_defaults = wp.target_defaults or {}
    wp.target_defaults.level_min = _el_target_min:get()
    wp.target_defaults.level_max = _el_target_max:get()
    wp.target_defaults.npc_blacklist = parse_id_list(_el_npc_blacklist:get_text())
    wp.target_defaults.npc_whitelist = parse_id_list(_el_npc_whitelist:get_text())

    -- Behavior
    wp.loop = _el_loop:get_state()
    wp.dry_spell_secs = _el_dry_spell:get()

    -- Recorder hotspot radius
    recorder:set_hotspot_radius(_el_hs_radius:get())
end

--- Populate form elements FROM a profile table.
---@param profile table
local function populate_form(profile)
    local meta = profile.metadata or {}
    local req  = profile.requirements or {}
    local td   = profile.target_defaults or {}

    _el_name:set(meta.name or "New Profile")
    _el_min_level:set(req.min_level or 1)
    _el_max_level:set(req.max_level or 80)
    _el_target_min:set(td.level_min or 1)
    _el_target_max:set(td.level_max or 80)
    _el_npc_blacklist:set(join_id_list(td.npc_blacklist))
    _el_npc_whitelist:set(join_id_list(td.npc_whitelist))
    _el_loop:set(profile.loop ~= false)
    _el_dry_spell:set(profile.dry_spell_secs or 15)
    _el_hs_radius:set(40)
    _el_filename:set("")
end

--- Enter edit mode. If existing is provided, edits a copy; otherwise starts fresh.
---@param client table
---@param existing table|nil
local function enter_edit_mode(client, existing)
    create_elements()
    client:start_recording(existing)

    local wp = client._services.profile_recorder:get_working_profile()
    if wp then
        populate_form(wp)
    end

    _last_profile_result = nil
    _editor_mode = "edit"
end

--- Exit edit mode and optionally cancel recording.
---@param client table
local function exit_edit_mode(client)
    _editor_mode = "browse"
    if client:get_recorder_state() == "recording" then
        client:cancel_recording()
    end
end

--------------------------------------------------------------------------------
-- Browse-mode rendering
--------------------------------------------------------------------------------

---@param t any TabBuilder
---@param client table
local function render_browse(t, client)
    -- 1. Active Profile (row_list type=info)
    t:row_list({
        label = "Active Profile",
        elements = {
            {
                type = "info",
                label = "Profile ID",
                value_fn = function()
                    return client and client.get_active_profile_id
                        and client:get_active_profile_id() or "default"
                end,
            },
        },
    })

    -- 2. Grinding Profile status
    t:row_list({
        label = "Grinding Profile",
        elements = {
            {
                type = "info",
                label = "Status",
                tooltip = "Grinding profile FSM state (idle / at_hotspot / traveling / vendor_trip)",
                value_fn = function()
                    if not client then return "N/A" end
                    return client.get_grinding_profile_state
                        and client:get_grinding_profile_state() or "idle"
                end,
                color_fn = function()
                    if not client then return nil end
                    local state = client.get_grinding_profile_state
                        and client:get_grinding_profile_state() or "idle"
                    if state == "at_hotspot" then return color.new(48, 209, 88, 255) end
                    if state == "traveling" then return color.new(255, 214, 10, 255) end
                    if state == "vendor_trip" then return color.new(255, 159, 10, 255) end
                    return nil
                end,
            },
            {
                type = "info",
                label = "Current Hotspot",
                value_fn = function()
                    if not client then return "-" end
                    local bb = client._services and client._services.blackboard
                    local hs = bb and bb:get("profile.current_hotspot")
                    return hs and tostring(hs.label or hs.id) or "-"
                end,
            },
        },
    })

    -- 3. Saved Profiles (listbox)
    t:listbox({
        label = "Saved Profiles",
        id = "profiles_list",
        elements = {
            {
                id = "profile_listbox",
                visible_rows = 8,
                entries_fn = function()
                    local coordinator = client._services and client._services.profile_coordinator
                    local files = coordinator and coordinator:list_profile_files() or {}
                    local entries = {}
                    for i = 1, #files do
                        entries[#entries + 1] = {
                            label = tostring(files[i].name or files[i].filename),
                            sublabel = files[i].filename,
                        }
                    end
                    return entries
                end,
                on_select = function(idx, _entry)
                    _selected_profile_index = idx
                end,
            },
        },
    })

    -- 4. Actions (custom_render)
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local coordinator = client._services and client._services.profile_coordinator
            local files = coordinator and coordinator:list_profile_files() or {}

            local button_h = 28
            local gap = 8
            local btn_w = math.floor((width - gap * 4) / 5)
            local bx = x

            -- Clamp selection
            if _selected_profile_index < 1 then _selected_profile_index = 1 end
            if _selected_profile_index > #files then _selected_profile_index = math.max(1, #files) end
            local selected = files[_selected_profile_index]

            -- Load
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Load", selected ~= nil) then
                local ok, err = coordinator:load_profile_from_file(selected.filename)
                if ok then
                    client:load_grinding_profile(coordinator._profile)
                    _last_profile_result = "Loaded " .. tostring(selected.name)
                else
                    _last_profile_result = "Load failed: " .. tostring(err)
                end
            end

            -- Unload
            bx = bx + btn_w + gap
            local has_profile = client.get_grinding_profile_state
                and client:get_grinding_profile_state() ~= "idle"
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Unload", has_profile) then
                client:unload_grinding_profile()
                _last_profile_result = "Profile unloaded"
            end

            -- Delete
            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Delete", selected ~= nil and #files > 0) then
                -- Delete by removing from manifest (coordinator doesn't have delete_file)
                _last_profile_result = "Delete not yet implemented"
            end

            -- New
            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "New", true) then
                enter_edit_mode(client, nil)
            end

            -- Edit
            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Edit", selected ~= nil) then
                -- Load the selected profile from file, then enter edit mode with it
                local JSON = require("lib/JSON")
                local path = "SentinelCore/profiles/" .. selected.filename
                local content = core.read_data_file(path)
                if content and content ~= "" then
                    local profile = JSON.decode(content)
                    if profile then
                        enter_edit_mode(client, profile)
                    else
                        _last_profile_result = "Failed to parse profile JSON"
                    end
                else
                    _last_profile_result = "Failed to read profile file"
                end
            end

            y_offset = y_offset + button_h + 8

            -- Status feedback
            if _last_profile_result then
                local fb = "Status: " .. tostring(_last_profile_result)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_secondary, fb)
                y_offset = y_offset + window:get_text_size(fb).y + 4
            end

            return y_offset
        end,
    })
end

--------------------------------------------------------------------------------
-- Edit-mode rendering
--------------------------------------------------------------------------------

---@param t any TabBuilder
---@param client table
local function render_edit(t, client)
    local recorder = client._services.profile_recorder
    local wp = recorder:get_working_profile()

    -- Continuously sync form -> working profile
    if wp then
        sync_form_to_profile(client)
    end

    -- 1. Metadata section
    t:custom_render({
        label = "Metadata",
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)
            local line_h = 30

            -- Name
            _el_name:render("Profile Name", "Display name for this grinding profile")
            y_offset = y_offset + line_h

            -- Min/Max level
            _el_min_level:render("Min Level", "Minimum player level for this profile")
            y_offset = y_offset + line_h

            _el_max_level:render("Max Level", "Maximum player level for this profile")
            y_offset = y_offset + line_h

            -- Map ID (info only)
            local map_id = wp and wp.requirements and wp.requirements.map_id or 0
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x, y_offset),
                colors.text_secondary,
                string.format("Map ID: %d (auto-detected)", map_id))
            y_offset = y_offset + 20

            return y_offset
        end,
    })

    -- 2. Target filters
    t:custom_render({
        label = "Target Filters",
        render_fn = function(self, y_offset)
            local line_h = 30

            _el_target_min:render("Target Level Min", "Minimum target mob level")
            y_offset = y_offset + line_h

            _el_target_max:render("Target Level Max", "Maximum target mob level")
            y_offset = y_offset + line_h

            _el_npc_blacklist:render("NPC Blacklist (IDs)", "Comma-separated NPC IDs to ignore")
            y_offset = y_offset + line_h

            _el_npc_whitelist:render("NPC Whitelist (IDs)", "Comma-separated NPC IDs to prefer")
            y_offset = y_offset + line_h

            return y_offset
        end,
    })

    -- 3. Behavior
    t:custom_render({
        label = "Behavior",
        render_fn = function(self, y_offset)
            local line_h = 30

            _el_loop:render("Loop Hotspots", "Restart from the first hotspot after reaching the last")
            y_offset = y_offset + line_h

            _el_dry_spell:render("Dry Spell (secs)", "Seconds without kills before advancing to next hotspot")
            y_offset = y_offset + line_h

            return y_offset
        end,
    })

    -- 4. Hotspot list
    t:custom_render({
        label = "Hotspots",
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local hotspots = wp and wp.hotspots or {}

            if #hotspots == 0 then
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_disabled,
                    "No hotspots recorded. Use keybind or Add Hotspot button.")
                y_offset = y_offset + 20
                return y_offset
            end

            local overlay = client._services and client._services.profile_overlay
            local line_h = 22
            local del_btn_w = 50

            for i = 1, #hotspots do
                local hs = hotspots[i]
                local label = string.format("#%d  (%.0f, %.0f, %.0f)  r=%d",
                    i, hs.x or 0, hs.y or 0, hs.z or 0, hs.radius or 40)

                if hs.label and hs.label ~= "" then
                    label = string.format("#%d %s  (%.0f, %.0f, %.0f)  r=%d",
                        i, hs.label, hs.x or 0, hs.y or 0, hs.z or 0, hs.radius or 40)
                end

                -- Clickable row to select hotspot for overlay highlight
                local row_s = vec2.new(x, y_offset)
                local row_e = vec2.new(x + width - del_btn_w - 8, y_offset + line_h)
                local row_hov = window:is_mouse_hovering_rect(row_s, row_e)
                if row_hov then
                    window:is_mouse_hovering_rect_block_movement(row_s, row_e)
                end

                local text_col = row_hov and colors.text_primary or colors.text_secondary
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x + 4, y_offset + 2), text_col, label)

                if row_hov and window:is_rect_clicked(row_s, row_e) then
                    if overlay then
                        overlay:set_selected_index(i)
                    end
                end

                -- Per-item Delete button
                local dbx = x + width - del_btn_w
                if make_btn(window, colors, dbx, del_btn_w, y_offset, line_h, "Del", true) then
                    -- Remove this specific hotspot
                    table.remove(hotspots, i)
                    if overlay then overlay:set_selected_index(0) end
                    -- Break out since we mutated the list
                    y_offset = y_offset + line_h + 2
                    return y_offset
                end

                y_offset = y_offset + line_h + 2
            end

            return y_offset
        end,
    })

    -- 5. Recording controls
    t:custom_render({
        label = "Recording",
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local is_recording = recorder:get_state() == "recording"
            local hotspot_count = wp and wp.hotspots and #wp.hotspots or 0

            -- Recording status
            local status_text = is_recording
                and string.format("RECORDING  (%d hotspots)", hotspot_count)
                or "Not recording"
            local status_color = is_recording and color.new(255, 69, 58, 255) or colors.text_disabled
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x, y_offset), status_color, status_text)
            y_offset = y_offset + 22

            -- Hotspot radius slider
            _el_hs_radius:render("Hotspot Radius", "Radius for new hotspots (yards)")
            y_offset = y_offset + 30

            -- Action buttons row
            local button_h = 28
            local gap = 8
            local btn_w = math.floor((width - gap * 2) / 3)
            local bx = x

            -- Add Vendor
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Add Vendor", is_recording) then
                recorder:add_vendor()
            end

            -- Add Blackspot
            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Add Blackspot", is_recording) then
                recorder:add_blackspot()
            end

            -- Undo Last
            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Undo Last", is_recording) then
                recorder:remove_last()
            end

            y_offset = y_offset + button_h + 8

            -- Keybind render
            local keybind = recorder._keybind
            if keybind then
                keybind:render("Add Hotspot (keybind)", "Press to add a hotspot at your current position")
                y_offset = y_offset + 30
            end

            return y_offset
        end,
    })

    -- 6. Save / Cancel
    t:custom_render({
        label = "Save",
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            -- Filename input
            _el_filename:render("Filename", "Filename for the profile (e.g. my_profile.json)")
            y_offset = y_offset + 30

            -- Buttons row
            local button_h = 28
            local gap = 8
            local btn_w = math.floor((width - gap * 2) / 3)
            local bx = x

            local filename_raw = _el_filename:get_text()
            local has_filename = type(filename_raw) == "string" and filename_raw ~= ""

            -- Save
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Save", has_filename) then
                sync_form_to_profile(client)
                local profile, err = recorder:finish_recording()
                if profile then
                    local fname = filename_raw
                    if not fname:match("%.json$") then
                        fname = fname .. ".json"
                    end

                    -- Temporarily load into coordinator to save
                    local coordinator = client._services.profile_coordinator
                    local prev_profile = coordinator._profile
                    coordinator._profile = profile
                    local ok_save, save_err = coordinator:save_profile_to_file(fname)
                    coordinator._profile = prev_profile

                    if ok_save then
                        _last_profile_result = "Saved to " .. fname
                    else
                        _last_profile_result = "Save failed: " .. tostring(save_err)
                    end

                    _editor_mode = "browse"
                else
                    -- Validation failed, re-start recording with the working copy
                    _last_profile_result = "Validation failed: " .. tostring(err)
                    -- Profile was discarded by finish_recording; restart editing with current form data
                end
            end

            -- Save & Load
            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Save & Load", has_filename) then
                sync_form_to_profile(client)
                local profile, err = recorder:finish_recording()
                if profile then
                    local fname = filename_raw
                    if not fname:match("%.json$") then
                        fname = fname .. ".json"
                    end

                    local coordinator = client._services.profile_coordinator
                    local prev_profile = coordinator._profile
                    coordinator._profile = profile
                    local ok_save, save_err = coordinator:save_profile_to_file(fname)
                    coordinator._profile = prev_profile

                    if ok_save then
                        client:load_grinding_profile(profile)
                        _last_profile_result = "Saved and loaded " .. fname
                    else
                        _last_profile_result = "Save failed: " .. tostring(save_err)
                    end

                    _editor_mode = "browse"
                else
                    _last_profile_result = "Validation failed: " .. tostring(err)
                end
            end

            -- Cancel
            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Cancel", true) then
                exit_edit_mode(client)
            end

            y_offset = y_offset + button_h + 8

            -- Status feedback
            if _last_profile_result then
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_secondary,
                    "Status: " .. tostring(_last_profile_result))
                y_offset = y_offset + 20
            end

            return y_offset
        end,
    })
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@param t any TabBuilder
---@param client table
function profile_tab.render(t, client)
    if _editor_mode == "edit" then
        render_edit(t, client)
    else
        render_browse(t, client)
    end
end

return profile_tab
