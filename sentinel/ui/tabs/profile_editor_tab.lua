local CaptureHelper = require("modules/grind/capture_helper")
local ProfileValidator = require("modules/grind/profile_validator")

local ProfileEditorTab = {}

-- Editor state (persists across renders, reset on new/load)
local _editor = {
    name = "",
    hotspots = {},
    vendors = {},
    blackspots = {},
    whitelist = {},
    blacklist = {},
    hotspot_radius = 40,
    filename = nil,
}

local function reset_editor()
    _editor.name = ""
    _editor.hotspots = {}
    _editor.vendors = {}
    _editor.blackspots = {}
    _editor.whitelist = {}
    _editor.blacklist = {}
    _editor.hotspot_radius = 40
    _editor.filename = nil
end

local function build_profile_from_editor()
    local reqs = CaptureHelper.capture_requirements() or { map_id = 0, min_level = 1, max_level = 70 }
    return {
        schema_version = "2.0",
        metadata = {
            name = _editor.name ~= "" and _editor.name or "Unnamed Profile",
            author = "Player",
            created_at = math.floor(core.time()),
            updated_at = math.floor(core.time()),
        },
        requirements = reqs,
        target_defaults = {
            npc_whitelist = _editor.whitelist,
            npc_blacklist = _editor.blacklist,
        },
        hotspots = _editor.hotspots,
        vendors = _editor.vendors,
        blackspots = _editor.blackspots,
        options = { loop = true, dry_spell_secs = 15, travel_engage = true },
    }
end

local function save_profile(app)
    local profile = build_profile_from_editor()
    local valid, errors = ProfileValidator.validate(profile)
    if not valid then
        if core and core.log then
            for _, err in ipairs(errors or {}) do
                core.log("[SentinelCore] Profile validation: " .. err)
            end
        end
        return
    end
    local grind = app:get_module("grind")
    if not grind or not grind.get_profile_manager then return end
    local pm = grind:get_profile_manager()
    if not pm then return end
    local fname = _editor.filename
    if not fname then
        local base = _editor.name
        if not base or base == "" then base = "profile" end
        base = base:lower():gsub("%s+", "_"):gsub("[^%w_]", "")
        if base == "" then base = "profile" end
        fname = base .. ".json"
    end
    pm:save_profile(profile, fname)
    _editor.filename = fname
end

local function delete_profile(app)
    if not _editor.filename then return end
    local grind = app:get_module("grind")
    if not grind or not grind.get_profile_manager then return end
    local pm = grind:get_profile_manager()
    if not pm then return end
    pm:delete_profile(_editor.filename)
    reset_editor()
end

local function status_summary()
    local parts = {}
    local nh = #_editor.hotspots
    if nh > 0 then parts[#parts + 1] = nh .. (nh == 1 and " hotspot" or " hotspots") end
    local nb = #_editor.blackspots
    if nb > 0 then parts[#parts + 1] = nb .. (nb == 1 and " blackspot" or " blackspots") end
    local nv = #_editor.vendors
    if nv > 0 then parts[#parts + 1] = nv .. (nv == 1 and " vendor" or " vendors") end
    local nw = #_editor.whitelist
    local nbl = #_editor.blacklist
    local nf = nw + nbl
    if nf > 0 then parts[#parts + 1] = nf .. (nf == 1 and " filter" or " filters") end
    if #parts == 0 then return "Empty" end
    return table.concat(parts, ", ")
end

function ProfileEditorTab.render(t, app, menu)
    -- Push editor state as preview for visualizer
    local grind = app and app.get_module and app:get_module("grind")
    if grind and grind.get_profile_manager then
        local pm = grind:get_profile_manager()
        if pm and not pm:is_profile_loaded() then
            pm:set_preview(_editor)
        end
    end

    -- ZONE 1: Profile Header
    t:text_input_list({
        label = "Profile Name",
        id = "profile_editor_name_input",
        elements = {
            {
                id = "profile_name",
                label = "Name",
                value_fn = function() return _editor.name end,
                placeholder = "My Grind Profile",
                tooltip = "Display name for this profile. Also used to generate the filename on first save.",
                on_change = function(value)
                    _editor.name = value or ""
                end,
            },
        },
    })

    t:row_list({
        label = "Profile",
        elements = {
            {
                type = "info",
                label = "File",
                value_fn = function()
                    return _editor.filename or "New (unsaved)"
                end,
            },
            {
                type = "info",
                label = "Status",
                value_fn = status_summary,
            },
            {
                type = "button",
                label = "New Profile",
                text = "New",
                on_click = function()
                    reset_editor()
                end,
            },
            {
                type = "button",
                label = "Save Profile",
                text = "Save",
                on_click = function()
                    save_profile(app)
                end,
            },
            {
                type = "button",
                label = "Delete Profile",
                text = "Delete",
                visible_when = function() return _editor.filename ~= nil end,
                on_click = function()
                    delete_profile(app)
                end,
            },
        },
    })

    -- ZONE 2: Hotspots + Blackspots (together)
    t:row_list({
        label = "Capture",
        elements = {
            {
                type = "stepper",
                label = "Radius",
                element = menu.profile_editor_hotspot_radius,
                min = 10,
                max = 100,
                step = 5,
                tooltip = "Radius for the next captured hotspot.",
            },
            {
                type = "button",
                label = "Capture Hotspot",
                text = "Hotspot",
                on_click = function()
                    local radius = 40
                    if menu.profile_editor_hotspot_radius then
                        local ok, val = pcall(function() return menu.profile_editor_hotspot_radius:get() end)
                        if ok and type(val) == "number" then radius = val end
                    end
                    local hotspot = CaptureHelper.capture_hotspot(radius)
                    if hotspot then
                        _editor.hotspots[#_editor.hotspots + 1] = hotspot
                    end
                end,
            },
            {
                type = "button",
                label = "Capture Blackspot",
                text = "Blackspot",
                on_click = function()
                    local spot = CaptureHelper.capture_blackspot()
                    if spot then
                        _editor.blackspots[#_editor.blackspots + 1] = spot
                    end
                end,
            },
        },
    })

    t:listbox({
        label = "Hotspots",
        footer = "Click to remove.",
        elements = {
            {
                id = "hotspot_list",
                visible_rows = 4,
                entries_fn = function()
                    local entries = {}
                    for i, hs in ipairs(_editor.hotspots) do
                        local lbl = hs.label or string.format("Hotspot %d", i)
                        local sub = string.format("r=%d  (%.0f, %.0f, %.0f)", hs.radius or 40, hs.x or 0, hs.y or 0, hs.z or 0)
                        entries[#entries + 1] = { label = lbl, sublabel = sub }
                    end
                    return entries
                end,
                on_select = function(index)
                    if _editor.hotspots[index] then
                        table.remove(_editor.hotspots, index)
                    end
                end,
            },
        },
    })

    t:listbox({
        label = "Blackspots",
        footer = "Click to remove.",
        elements = {
            {
                id = "blackspot_list",
                visible_rows = 3,
                entries_fn = function()
                    local entries = {}
                    for i, bs in ipairs(_editor.blackspots) do
                        entries[#entries + 1] = {
                            label = string.format("Blackspot %d", i),
                            sublabel = string.format("(%.0f, %.0f, %.0f) r=%d", bs.x or 0, bs.y or 0, bs.z or 0, bs.radius or 10),
                        }
                    end
                    return entries
                end,
                on_select = function(index)
                    if _editor.blackspots[index] then
                        table.remove(_editor.blackspots, index)
                    end
                end,
            },
        },
    })

    -- ZONE 3: Details (segmented)
    t:segmented_control({
        label = "Details",
        element = menu.profile_editor_detail_view,
        options = { "Vendors", "Mob Filters" },
    })

    local detail_view = menu.profile_editor_detail_view
    local function is_vendors_view()
        return (detail_view and detail_view:get() or 1) == 1
    end
    local function is_mobs_view()
        return (detail_view and detail_view:get() or 1) == 2
    end

    -- Vendors subview
    t:row_list({
        label = "Vendor Capture",
        footer = "Target an NPC, then click Repair or Food.",
        visible_when = is_vendors_view,
        elements = {
            {
                type = "button",
                label = "Capture Repair Vendor",
                text = "Repair",
                on_click = function()
                    local vendor = CaptureHelper.capture_vendor({"repair", "sell"})
                    if vendor then
                        _editor.vendors[#_editor.vendors + 1] = vendor
                    end
                end,
            },
            {
                type = "button",
                label = "Capture Food Vendor",
                text = "Food",
                on_click = function()
                    local vendor = CaptureHelper.capture_vendor({"food"})
                    if vendor then
                        _editor.vendors[#_editor.vendors + 1] = vendor
                    end
                end,
            },
        },
    })

    t:listbox({
        label = "Vendors",
        footer = "Click to remove.",
        visible_when = is_vendors_view,
        elements = {
            {
                id = "vendor_list",
                visible_rows = 3,
                entries_fn = function()
                    local entries = {}
                    for _, v in ipairs(_editor.vendors) do
                        entries[#entries + 1] = {
                            label = v.name or "Unknown",
                            sublabel = v.services and table.concat(v.services, ", ") or "vendor",
                        }
                    end
                    return entries
                end,
                on_select = function(index)
                    if _editor.vendors[index] then
                        table.remove(_editor.vendors, index)
                    end
                end,
            },
        },
    })

    -- Mob Filters subview
    t:row_list({
        label = "Mob Filter Capture",
        footer = "Target a mob, then click Whitelist or Blacklist.",
        visible_when = is_mobs_view,
        elements = {
            {
                type = "button",
                label = "Add to Whitelist",
                text = "Whitelist",
                on_click = function()
                    local npc = CaptureHelper.capture_mob_ref()
                    if npc then
                        _editor.whitelist[#_editor.whitelist + 1] = npc
                    end
                end,
            },
            {
                type = "button",
                label = "Add to Blacklist",
                text = "Blacklist",
                on_click = function()
                    local npc = CaptureHelper.capture_mob_ref()
                    if npc then
                        _editor.blacklist[#_editor.blacklist + 1] = npc
                    end
                end,
            },
        },
    })

    t:listbox({
        label = "Whitelist",
        footer = "Click to remove.",
        visible_when = is_mobs_view,
        elements = {
            {
                id = "whitelist",
                visible_rows = 3,
                entries_fn = function()
                    local entries = {}
                    for _, npc in ipairs(_editor.whitelist) do
                        entries[#entries + 1] = {
                            label = npc.name or "Unknown",
                            sublabel = npc.npc_id and ("ID: " .. tostring(npc.npc_id)) or nil,
                        }
                    end
                    return entries
                end,
                on_select = function(index)
                    if _editor.whitelist[index] then
                        table.remove(_editor.whitelist, index)
                    end
                end,
            },
        },
    })

    t:listbox({
        label = "Blacklist",
        footer = "Click to remove.",
        visible_when = is_mobs_view,
        elements = {
            {
                id = "blacklist",
                visible_rows = 3,
                entries_fn = function()
                    local entries = {}
                    for _, npc in ipairs(_editor.blacklist) do
                        entries[#entries + 1] = {
                            label = npc.name or "Unknown",
                            sublabel = npc.npc_id and ("ID: " .. tostring(npc.npc_id)) or nil,
                        }
                    end
                    return entries
                end,
                on_select = function(index)
                    if _editor.blacklist[index] then
                        table.remove(_editor.blacklist, index)
                    end
                end,
            },
        },
    })
end

return ProfileEditorTab
