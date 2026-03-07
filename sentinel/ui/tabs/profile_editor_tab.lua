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
            created_at = os.time(),
            updated_at = os.time(),
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
        fname = (_editor.name or "profile"):lower():gsub("%s+", "_"):gsub("[^%w_]", "") .. ".json"
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

function ProfileEditorTab.render(t, app, menu)
    -- Profile Metadata
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
                label = "Name",
                value_fn = function()
                    return _editor.name ~= "" and _editor.name or "(auto from filename)"
                end,
            },
        },
    })

    -- Hotspots
    t:row_list({
        label = "Hotspots",
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
                text = "Capture",
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
        },
    })

    t:listbox({
        label = "Hotspot List",
        visible_rows = 3,
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
    })

    -- Mob Filters
    t:row_list({
        label = "Mob Filters",
        elements = {
            {
                type = "button",
                label = "Add to Whitelist",
                text = "Whitelist Target",
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
                text = "Blacklist Target",
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
    })

    t:listbox({
        label = "Blacklist",
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
    })

    -- Vendors
    t:row_list({
        label = "Vendors",
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
        label = "Vendor List",
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
    })

    -- Blackspots
    t:row_list({
        label = "Blackspots",
        elements = {
            {
                type = "button",
                label = "Capture Blackspot",
                text = "Capture",
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
        label = "Blackspot List",
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
    })

    -- Actions
    t:row_list({
        label = "Actions",
        elements = {
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
                on_click = function()
                    delete_profile(app)
                end,
            },
        },
    })
end

return ProfileEditorTab
