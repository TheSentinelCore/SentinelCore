-- SentinelCore/ui/tabs/profile_tab.lua
--
-- Profile browser + editor tab for the Sentinel Control Center.
-- Two modes: "browse" (list / load / unload / delete) and "edit" (record + metadata form).
--
-- AstroUI's add_tab build_fn runs ONCE. We use visible_when guards to toggle
-- browse vs edit groups. All form inputs use AstroUI-native widgets (row_list
-- with stepper/toggle, text_input_list) — NOT raw core.menu.* elements.

local vec2   = require("common/geometry/vector_2")
local enums  = require("common/enums")
local color  = require("common/color")
local AstroUI = require("lib/AstroUI")

local LAYOUT = AstroUI.LAYOUT

--------------------------------------------------------------------------------
-- Module state
--------------------------------------------------------------------------------

local profile_tab = {}

local _editor_mode = "browse"   -- "browse" | "edit"
local _selected_profile_index = 1
local _last_profile_result = nil

-- Form state (plain Lua tables, synced to/from working profile)
local _form = {
    name = "New Profile",
    min_level = 1,
    max_level = 80,
    target_min = 1,
    target_max = 80,
    npc_blacklist = "",
    npc_whitelist = "",
    loop = true,
    dry_spell = 15,
    hs_radius = 40,
    filename = "",
}

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

local function is_browse() return _editor_mode == "browse" end
local function is_edit()   return _editor_mode == "edit" end

--- Grab current target's NPC ID and name.
---@return number|nil, string|nil
local function get_target_npc()
    if not core or not core.object_manager then return nil, nil end
    local player = core.object_manager.get_local_player()
    if not player then return nil, nil end
    local target = player:get_target()
    if not target or not target:is_valid() then return nil, nil end
    local npc_id = target:get_npc_id()
    if not npc_id or npc_id == 0 then return nil, nil end
    return npc_id, target:get_name() or ""
end

--- Add current target's NPC ID to a form field string.
---@param field_key string
local function add_npc_to_field(field_key)
    local npc_id = get_target_npc()
    if not npc_id then return end
    local ids = parse_id_list(_form[field_key])
    for i = 1, #ids do
        if ids[i] == npc_id then return end
    end
    ids[#ids + 1] = npc_id
    _form[field_key] = join_id_list(ids)
end

--------------------------------------------------------------------------------
-- Virtual element factories (AstroUI-compatible get/set wrappers)
--------------------------------------------------------------------------------

--- Creates a stepper element backed by _form[key].
local function form_stepper(key)
    return {
        get = function() return _form[key] end,
        set = function(_, v) _form[key] = v end,
    }
end

--- Creates a toggle element backed by _form[key].
local function form_toggle(key)
    return {
        get_state = function() return _form[key] == true end,
        set = function(_, v) _form[key] = v end,
    }
end

--------------------------------------------------------------------------------
-- Form ↔ profile sync
--------------------------------------------------------------------------------

--- Sync _form values into the working profile.
---@param client table
local function sync_form_to_profile(client)
    local recorder = client._services.profile_recorder
    local wp = recorder:get_working_profile()
    if not wp then return end

    wp.metadata.name = _form.name
    wp.requirements.min_level = _form.min_level
    wp.requirements.max_level = _form.max_level

    wp.target_defaults = wp.target_defaults or {}
    wp.target_defaults.level_min = _form.target_min
    wp.target_defaults.level_max = _form.target_max
    wp.target_defaults.npc_blacklist = parse_id_list(_form.npc_blacklist)
    wp.target_defaults.npc_whitelist = parse_id_list(_form.npc_whitelist)

    wp.loop = _form.loop
    wp.dry_spell_secs = _form.dry_spell

    recorder:set_hotspot_radius(_form.hs_radius)
end

--- Populate _form FROM a profile table.
---@param profile table
local function populate_form(profile)
    local meta = profile.metadata or {}
    local req  = profile.requirements or {}
    local td   = profile.target_defaults or {}

    _form.name = meta.name or "New Profile"
    _form.min_level = req.min_level or 1
    _form.max_level = req.max_level or 80
    _form.target_min = td.level_min or 1
    _form.target_max = td.level_max or 80
    _form.npc_blacklist = join_id_list(td.npc_blacklist)
    _form.npc_whitelist = join_id_list(td.npc_whitelist)
    _form.loop = profile.loop ~= false
    _form.dry_spell = profile.dry_spell_secs or 15
    _form.hs_radius = 40
    _form.filename = ""
end

--------------------------------------------------------------------------------
-- Edit-mode lifecycle
--------------------------------------------------------------------------------

--- Enter edit mode.
---@param client table
---@param existing table|nil
local function enter_edit_mode(client, existing)
    client:start_recording(existing)

    local wp = client._services.profile_recorder:get_working_profile()
    if wp then
        populate_form(wp)
    end

    _last_profile_result = nil
    _editor_mode = "edit"
end

--- Exit edit mode and cancel recording.
---@param client table
local function exit_edit_mode(client)
    _editor_mode = "browse"
    if client:get_recorder_state() == "recording" then
        client:cancel_recording()
    end
end

--------------------------------------------------------------------------------
-- Build: adds ALL groups (browse + edit) with visible_when guards
--------------------------------------------------------------------------------

---@param t any TabBuilder
---@param client table
function profile_tab.render(t, client)
    ---------------------------------------------------------------------------
    -- BROWSE MODE groups
    ---------------------------------------------------------------------------

    -- B1. Active Profile
    t:row_list({
        label = "Active Profile",
        visible_when = is_browse,
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

    -- B2. Grinding Profile status
    t:row_list({
        label = "Grinding Profile",
        visible_when = is_browse,
        elements = {
            {
                type = "info",
                label = "Status",
                tooltip = "Grinding profile FSM state",
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

    -- B3. Saved Profiles listbox
    t:listbox({
        label = "Saved Profiles",
        id = "profiles_list",
        visible_when = is_browse,
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

    -- B4. Browse actions (Load / Unload / Delete / New / Edit)
    t:custom_render({
        visible_when = is_browse,
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

            if _selected_profile_index < 1 then _selected_profile_index = 1 end
            if _selected_profile_index > #files then _selected_profile_index = math.max(1, #files) end
            local selected = files[_selected_profile_index]

            -- Load
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Load", selected ~= nil) then
                local ok, err = coordinator:load_profile_from_file(selected.filename)
                _last_profile_result = ok and ("Loaded " .. tostring(selected.name))
                    or ("Load failed: " .. tostring(err))
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

            if _last_profile_result then
                local fb = "Status: " .. tostring(_last_profile_result)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_secondary, fb)
                y_offset = y_offset + window:get_text_size(fb).y + 4
            end

            return y_offset
        end,
    })

    ---------------------------------------------------------------------------
    -- EDIT MODE groups (AstroUI-native widgets)
    ---------------------------------------------------------------------------

    -- E1. Metadata — text input for name, steppers for levels
    t:text_input_list({
        label = "Metadata",
        id = "pe_metadata_inputs",
        visible_when = is_edit,
        elements = {
            {
                label = "Profile Name",
                id = "pe_name",
                tooltip = "Display name for this grinding profile",
                value_fn = function() return _form.name end,
                on_change = function(v) _form.name = v end,
                placeholder = "Enter profile name...",
            },
        },
    })

    t:row_list({
        label = "Requirements",
        visible_when = is_edit,
        elements = {
            {
                type = "slider",
                label = "Min Level",
                tooltip = "Minimum player level for this profile",
                element = form_stepper("min_level"),
                min = 1, max = 80,
            },
            {
                type = "slider",
                label = "Max Level",
                tooltip = "Maximum player level for this profile",
                element = form_stepper("max_level"),
                min = 1, max = 80,
            },
        },
    })

    -- E2. Target filters
    t:row_list({
        label = "Target Filters",
        visible_when = is_edit,
        elements = {
            {
                type = "slider",
                label = "Level Min",
                tooltip = "Minimum target mob level",
                element = form_stepper("target_min"),
                min = 1, max = 80,
            },
            {
                type = "slider",
                label = "Level Max",
                tooltip = "Maximum target mob level",
                element = form_stepper("target_max"),
                min = 1, max = 80,
            },
        },
    })

    -- E2b. NPC Blacklist
    t:row_list({
        label = "NPC Blacklist",
        visible_when = is_edit,
        elements = {
            {
                type = "info",
                label = "IDs",
                value_fn = function()
                    return _form.npc_blacklist ~= "" and _form.npc_blacklist or "(none)"
                end,
            },
            {
                type = "button",
                label = "Add Target",
                text = "+ Add",
                on_click = function() add_npc_to_field("npc_blacklist") end,
            },
            {
                type = "button",
                label = "Clear List",
                text = "Clear",
                visible_when = function() return _form.npc_blacklist ~= "" end,
                on_click = function() _form.npc_blacklist = "" end,
            },
        },
    })

    -- E2c. NPC Whitelist
    t:row_list({
        label = "NPC Whitelist",
        visible_when = is_edit,
        elements = {
            {
                type = "info",
                label = "IDs",
                value_fn = function()
                    return _form.npc_whitelist ~= "" and _form.npc_whitelist or "(none)"
                end,
            },
            {
                type = "button",
                label = "Add Target",
                text = "+ Add",
                on_click = function() add_npc_to_field("npc_whitelist") end,
            },
            {
                type = "button",
                label = "Clear List",
                text = "Clear",
                visible_when = function() return _form.npc_whitelist ~= "" end,
                on_click = function() _form.npc_whitelist = "" end,
            },
        },
    })

    -- E3. Behavior
    t:row_list({
        label = "Behavior",
        visible_when = is_edit,
        elements = {
            {
                type = "toggle",
                label = "Loop Hotspots",
                tooltip = "Restart from the first hotspot after reaching the last",
                element = form_toggle("loop"),
            },
            {
                type = "stepper",
                label = "Dry Spell (secs)",
                tooltip = "Seconds without kills before advancing to next hotspot",
                element = form_stepper("dry_spell"),
                min = 5, max = 120, step = 5, decimals = 0,
            },
        },
    })

    -- E4. Hotspot list (custom render for dynamic list)
    t:custom_render({
        label = "Hotspots",
        visible_when = is_edit,
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            -- Sync form to profile each frame
            sync_form_to_profile(client)

            local recorder = client._services.profile_recorder
            local wp = recorder:get_working_profile()
            local hotspots = wp and wp.hotspots or {}

            if #hotspots == 0 then
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_disabled,
                    "No hotspots recorded. Use keybind or walk and press Insert.")
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
                    if overlay then overlay:set_selected_index(i) end
                end

                local dbx = x + width - del_btn_w
                if make_btn(window, colors, dbx, del_btn_w, y_offset, line_h, "Del", true) then
                    table.remove(hotspots, i)
                    if overlay then overlay:set_selected_index(0) end
                    y_offset = y_offset + line_h + 2
                    return y_offset
                end

                y_offset = y_offset + line_h + 2
            end

            return y_offset
        end,
    })

    -- E5. Recording controls
    t:row_list({
        label = "Recording",
        visible_when = is_edit,
        elements = {
            {
                type = "stepper",
                label = "Hotspot Radius",
                tooltip = "Radius for new hotspots (yards)",
                element = form_stepper("hs_radius"),
                min = 5, max = 120, step = 5, decimals = 0,
            },
        },
    })

    t:custom_render({
        visible_when = is_edit,
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local recorder = client._services.profile_recorder
            local wp = recorder:get_working_profile()
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

            -- Action buttons
            local button_h = 28
            local gap = 8
            local btn_w = math.floor((width - gap * 3) / 4)
            local bx = x

            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Add Hotspot", is_recording) then
                recorder:add_hotspot()
            end

            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Add Vendor", is_recording) then
                recorder:add_vendor()
            end

            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Add Blackspot", is_recording) then
                recorder:add_blackspot()
            end

            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Undo Last", is_recording) then
                recorder:remove_last()
            end

            y_offset = y_offset + button_h + 8

            -- Keybind info
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x, y_offset), colors.text_secondary,
                "Press Insert key to add hotspot at current position")
            y_offset = y_offset + 20

            return y_offset
        end,
    })

    -- E6. Save / Cancel
    t:text_input_list({
        label = "Save",
        id = "pe_save_inputs",
        visible_when = is_edit,
        elements = {
            {
                label = "Filename",
                id = "pe_filename",
                tooltip = "Filename for the profile (e.g. my_profile.json)",
                value_fn = function() return _form.filename end,
                on_change = function(v) _form.filename = v end,
                placeholder = "my_profile.json",
            },
        },
    })

    t:custom_render({
        visible_when = is_edit,
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local recorder = client._services.profile_recorder
            local button_h = 28
            local gap = 8
            local btn_w = math.floor((width - gap * 2) / 3)
            local bx = x

            local has_filename = type(_form.filename) == "string" and _form.filename ~= ""

            -- Save
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Save", has_filename) then
                sync_form_to_profile(client)
                local profile, err = recorder:finish_recording()
                if profile then
                    local fname = _form.filename
                    if not fname:match("%.json$") then fname = fname .. ".json" end

                    local coordinator = client._services.profile_coordinator
                    local ok_save, save_err = coordinator:save_profile(profile, fname)

                    if ok_save then
                        _last_profile_result = "Saved to " .. fname
                        _editor_mode = "browse"
                    else
                        _last_profile_result = "Save failed: " .. tostring(save_err)
                        recorder:start_recording(profile)
                    end
                else
                    _last_profile_result = "Validation failed: " .. tostring(err)
                end
            end

            -- Save & Load
            bx = bx + btn_w + gap
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Save & Load", has_filename) then
                sync_form_to_profile(client)
                local profile, err = recorder:finish_recording()
                if profile then
                    local fname = _form.filename
                    if not fname:match("%.json$") then fname = fname .. ".json" end

                    local coordinator = client._services.profile_coordinator
                    local ok_save, save_err = coordinator:save_profile(profile, fname)

                    if ok_save then
                        client:load_grinding_profile(profile)
                        _last_profile_result = "Saved and loaded " .. fname
                        _editor_mode = "browse"
                    else
                        _last_profile_result = "Save failed: " .. tostring(save_err)
                        recorder:start_recording(profile)
                    end
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

return profile_tab
