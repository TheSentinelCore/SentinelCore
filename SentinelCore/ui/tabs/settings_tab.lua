--[[
    SentinelCore Settings Tab

    Vendoring, quality filters, class-specific combat thresholds,
    advanced targeting, and save-to-profile controls.
]]

local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local color = require("common/color")
local AstroUI = require("lib/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local settings_tab = {}

local _last_settings_result = nil
local _show_expert_settings = false
local PALADIN_CLASS_ID = 2
local WARLOCK_CLASS_ID = 9

local TOOLTIPS = {
    vendor_enabled = "Enable or disable automatic vendoring entirely. When off, the bot will never seek a vendor.",
    min_free_slots = "Triggers vendoring when free bag slots are at or below this threshold.",
    return_to_anchor = "After vendoring, return to the last grind anchor before resuming combat logic.",
    repair_enabled = "If enabled, repair gear during vendor interaction when possible.",
    quality_filters = "Checked item qualities are eligible to be sold when vendoring.",
    quality_preset = "One-click quality presets. You can still fine-tune individual checkboxes after.",
    search_radius = "Max radius for querying nearby vendors from SentinelQueryServer.",
    expert_panel = "Shows advanced targeting and compatibility controls.",
    ret_flash_hp = "Flash of Light health threshold (fallback heal when mana too low for Holy Light).",
    ret_holy_hp = "Cast Holy Light as the primary sustain heal at or below this threshold.",
    ret_low_mana = "Below this mana threshold, the routine can downrank Flash of Light for efficiency.",
    ret_health_pot = "Use best health potion when HP is at or below this threshold in combat.",
    ret_mana_pot = "Use best mana potion when mana is at or below this threshold in combat.",
    ret_consec = "Minimum mana required to cast Consecration in single-target combat.",
    wl_drink = "Out-of-combat drink threshold for Warlock.",
    wl_eat = "Out-of-combat eat threshold for Warlock.",
    wl_lifetap_min_hp = "Minimum HP required before Life Tap is allowed.",
    wl_lifetap_max_mana = "In-combat mana cap up to which Life Tap is used.",
    wl_lifetap_ooc_max_mana = "Out-of-combat mana cap up to which Life Tap is used.",
    wl_death_coil_hp = "Emergency HP threshold for Death Coil.",
    wl_drain_life_hp = "HP threshold for defensive Drain Life usage.",
    wl_funnel_pet_hp = "Pet HP threshold for Health Funnel.",
    wl_health_pot = "Combat HP threshold for health potion usage.",
    wl_mana_pot = "Combat mana threshold for mana potion usage.",
    wl_mana_pot_min_hp = "Minimum HP required to allow mana potion usage.",
    wl_wand_mana = "Mana floor before wand fallback is preferred.",
    target_base = "Preferred baseline pull radius for target selection.",
    target_max = "Hard cap for target acquisition distance.",
    legacy_quality = "Backward-compat fallback. Used only when explicit quality toggles are missing.",
    save_settings = "Persists current runtime + policy values to the active profile JSON.",
}

local CLASS_NAMES = {
    [1] = "Warrior",
    [2] = "Paladin",
    [3] = "Hunter",
    [4] = "Rogue",
    [5] = "Priest",
    [6] = "Death Knight",
    [7] = "Shaman",
    [8] = "Mage",
    [9] = "Warlock",
    [11] = "Druid",
}

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

---@param class_id number|nil
---@return string
local function class_label(class_id)
    local normalized = tonumber(class_id) or 0
    if normalized <= 0 then
        return "Unknown"
    end
    return CLASS_NAMES[normalized] or ("Class " .. tostring(normalized))
end

---@param client SentinelClient|nil
---@return number
local function get_active_class_id(client)
    if not client or type(client.get_blackboard) ~= "function" then
        return 0
    end
    local ok_bb, bb = pcall(client.get_blackboard, client)
    if not ok_bb or not bb or type(bb.get) ~= "function" then
        return 0
    end
    return tonumber(bb:get("player.class_id", 0)) or 0
end

---@param client SentinelClient
---@param enabled_gray boolean
---@param enabled_white boolean
---@param enabled_green boolean
---@param enabled_blue boolean
---@param enabled_epic boolean
---@return boolean
---@return string|nil
local function apply_quality_preset(client, enabled_gray, enabled_white, enabled_green, enabled_blue, enabled_epic)
    local updates = {
        { "sell_gray", enabled_gray },
        { "sell_white", enabled_white },
        { "sell_green", enabled_green },
        { "sell_blue", enabled_blue },
        { "sell_epic", enabled_epic },
    }
    for i = 1, #updates do
        local update = updates[i]
        local ok, err = client:set_policy_setting(update[1], update[2], false)
        if not ok then
            return false, err
        end
    end
    return true, nil
end

-- ============================================================================
-- LIGHTWEIGHT WRAPPER OBJECTS FOR ROW_LIST
-- ============================================================================

--- Creates a toggle wrapper that reads/writes a policy setting via the client.
---@param client SentinelClient
---@param key string
---@return table element with get_state/set
local function policy_toggle(client, key)
    return {
        get_state = function()
            local p = client and client.get_policy_config and client:get_policy_config() or {}
            return p[key] == true
        end,
        set = function(_, v)
            local ok, err = client:set_policy_setting(key, v, false)
            _last_settings_result = ok and ("Updated " .. key) or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a toggle wrapper that reads/writes a policy setting, defaulting to true.
---@param client SentinelClient
---@param key string
---@return table element with get_state/set
local function policy_toggle_default_on(client, key)
    return {
        get_state = function()
            local p = client and client.get_policy_config and client:get_policy_config() or {}
            return p[key] ~= false
        end,
        set = function(_, v)
            local ok, err = client:set_policy_setting(key, v, true)
            _last_settings_result = ok and ("Updated " .. key) or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a toggle wrapper for a runtime setting path.
---@param client SentinelClient
---@param domain string
---@param key string
---@param default boolean
---@return table element with get_state/set
local function runtime_toggle(client, domain, key, default)
    return {
        get_state = function()
            local rt = client and client.get_runtime_config and client:get_runtime_config() or {}
            local section = rt[domain] or {}
            if section[key] == nil then return default end
            return section[key] == true
        end,
        set = function(_, v)
            local ok, err = client:set_runtime_setting(domain, key, v, false)
            _last_settings_result = ok and ("Updated " .. domain .. "." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper wrapper for a policy integer setting.
---@param client SentinelClient
---@param key string
---@param default number
---@return table element with get/set
local function policy_stepper(client, key, default)
    return {
        get = function()
            local p = client and client.get_policy_config and client:get_policy_config() or {}
            return tonumber(p[key]) or default
        end,
        set = function(_, v)
            local ok, err = client:set_policy_setting(key, math.floor(v), false)
            _last_settings_result = ok and ("Updated " .. key) or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper wrapper for a runtime setting.
---@param client SentinelClient
---@param domain string
---@param key string
---@param default number
---@return table element with get/set
local function runtime_stepper(client, domain, key, default)
    return {
        get = function()
            local rt = client and client.get_runtime_config and client:get_runtime_config() or {}
            local section = rt[domain] or {}
            return tonumber(section[key]) or default
        end,
        set = function(_, v)
            local ok, err = client:set_runtime_setting(domain, key, v, false)
            _last_settings_result = ok and ("Updated " .. domain .. "." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper wrapper for a nested rotation setting (paladin.retribution.*).
---@param client SentinelClient
---@param key string
---@param default number
---@return table element with get/set
local function retri_stepper(client, key, default)
    return {
        get = function()
            local rt = client and client.get_runtime_config and client:get_runtime_config() or {}
            local rotation = rt.rotation or {}
            local paladin = rotation.paladin or {}
            local retri = paladin.retribution or {}
            return tonumber(retri[key]) or default
        end,
        set = function(_, v)
            local rt = client and client.get_runtime_config and client:get_runtime_config() or {}
            local rotation = rt.rotation or {}
            local paladin_src = rotation.paladin or {}
            local retri_src = paladin_src.retribution or {}

            -- Shallow copy to avoid mutating cached config
            local new_paladin = {}
            for k2, v2 in pairs(paladin_src) do new_paladin[k2] = v2 end
            local new_retri = {}
            for k2, v2 in pairs(retri_src) do new_retri[k2] = v2 end
            new_retri[key] = v
            new_paladin.retribution = new_retri

            local ok, err = client:set_runtime_setting("rotation", "paladin", new_paladin, false)
            _last_settings_result = ok and ("Updated retribution." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper wrapper for a nested rotation setting (warlock.affliction.*).
---@param client SentinelClient
---@param key string
---@param default number
---@return table element with get/set
local function affli_stepper(client, key, default)
    return {
        get = function()
            local rt = client and client.get_runtime_config and client:get_runtime_config() or {}
            local rotation = rt.rotation or {}
            local warlock = rotation.warlock or {}
            local affli = warlock.affliction or {}
            return tonumber(affli[key]) or default
        end,
        set = function(_, v)
            local rt = client and client.get_runtime_config and client:get_runtime_config() or {}
            local rotation = rt.rotation or {}
            local warlock_src = rotation.warlock or {}
            local affli_src = warlock_src.affliction or {}

            local new_warlock = {}
            for k2, v2 in pairs(warlock_src) do new_warlock[k2] = v2 end
            local new_affli = {}
            for k2, v2 in pairs(affli_src) do new_affli[k2] = v2 end
            new_affli[key] = v
            new_warlock.affliction = new_affli

            local ok, err = client:set_runtime_setting("rotation", "warlock", new_warlock, false)
            _last_settings_result = ok and ("Updated affliction." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

--- Creates a stepper for targeting settings with clamping against the paired bound.
---@param client SentinelClient
---@param key string "base_radius" or "max_radius"
---@param paired_key string the other key
---@param default number
---@return table element with get/set
local function targeting_stepper(client, key, paired_key, default)
    return {
        get = function()
            local rt = client and client.get_runtime_config and client:get_runtime_config() or {}
            local targeting = rt.targeting or {}
            return tonumber(targeting[key]) or default
        end,
        set = function(_, v)
            local rt = client and client.get_runtime_config and client:get_runtime_config() or {}
            local targeting = rt.targeting or {}
            local paired = tonumber(targeting[paired_key]) or v
            local clamped = v
            if key == "base_radius" then
                clamped = math.min(v, paired)
            else
                clamped = math.max(v, paired)
            end
            local ok, err = client:set_runtime_setting("targeting", key, clamped, false)
            _last_settings_result = ok and ("Updated targeting." .. key)
                or ("Update failed: " .. tostring(err))
        end,
    }
end

-- ============================================================================
-- TAB RENDER
-- ============================================================================

---@param t any AstroUI tab builder
---@param client SentinelClient
function settings_tab.render(t, client)

    -- 1. Vendoring (row_list)
    t:row_list({
        label = "Vendoring",
        footer = "Controls when the bot visits a vendor and which items are sold.",
        elements = {
            {
                type = "toggle",
                label = "Auto-Vendor",
                tooltip = TOOLTIPS.vendor_enabled,
                element = policy_toggle_default_on(client, "vendor_enabled"),
            },
            {
                type = "toggle",
                label = "Repair Gear",
                tooltip = TOOLTIPS.repair_enabled,
                element = policy_toggle(client, "repair_enabled"),
            },
            {
                type = "toggle",
                label = "Return to Anchor",
                tooltip = TOOLTIPS.return_to_anchor,
                element = runtime_toggle(client, "vendor", "return_to_anchor", true),
            },
            {
                type = "stepper",
                label = "Min Free Slots",
                tooltip = TOOLTIPS.min_free_slots,
                element = policy_stepper(client, "min_free_slots", 2),
                min = 0, max = 20, step = 1, decimals = 0,
            },
            {
                type = "stepper",
                label = "Search Radius",
                tooltip = TOOLTIPS.search_radius,
                element = runtime_stepper(client, "vendor", "search_radius", 250),
                min = 50, max = 1000, step = 10, decimals = 0,
            },
        },
    })

    -- 2. Quality Filters (row_list type=toggle)
    t:row_list({
        label = "Quality Filters",
        footer = "Items matching enabled qualities will be sold at vendors.",
        elements = {
            {
                type = "toggle",
                label = "Gray (Trash)",
                tooltip = TOOLTIPS.quality_filters,
                element = policy_toggle(client, "sell_gray"),
            },
            {
                type = "toggle",
                label = "White (Common)",
                tooltip = TOOLTIPS.quality_filters,
                element = policy_toggle(client, "sell_white"),
            },
            {
                type = "toggle",
                label = "Green (Uncommon)",
                tooltip = TOOLTIPS.quality_filters,
                element = policy_toggle(client, "sell_green"),
            },
            {
                type = "toggle",
                label = "Blue (Rare)",
                tooltip = TOOLTIPS.quality_filters,
                element = policy_toggle(client, "sell_blue"),
            },
            {
                type = "toggle",
                label = "Epic",
                tooltip = TOOLTIPS.quality_filters,
                element = policy_toggle(client, "sell_epic"),
            },
        },
    })

    -- Quality presets (custom_render, compact row of buttons)
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local preset_gap = 8
            local preset_h = 28
            local preset_w = math.floor((width - (preset_gap * 2)) / 3)

            local function render_preset_btn(bx, bw, label)
                local s = vec2.new(bx, y_offset)
                local e = vec2.new(bx + bw, y_offset + preset_h)
                local hov = window:is_mouse_hovering_rect(s, e)
                if hov then window:is_mouse_hovering_rect_block_movement(s, e) end
                local bg = hov and lighten_color(colors.primary_accent, 15) or colors.primary_accent
                window:render_rect_filled(s, e, bg, 8)
                local ts = window:get_text_size(label)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(bx + (bw - ts.x) / 2, y_offset + (preset_h - ts.y) / 2),
                    colors.text_primary, label)
                return hov and window:is_rect_clicked(s, e)
            end

            if render_preset_btn(x, preset_w, "Trash Only") then
                local ok, err = apply_quality_preset(client, true, false, false, false, false)
                _last_settings_result = ok and "Applied preset: Trash Only" or ("Update failed: " .. tostring(err))
            end
            if render_preset_btn(x + preset_w + preset_gap, preset_w, "Common+") then
                local ok, err = apply_quality_preset(client, true, true, false, false, false)
                _last_settings_result = ok and "Applied preset: Common+" or ("Update failed: " .. tostring(err))
            end
            if render_preset_btn(x + (preset_w * 2) + (preset_gap * 2), preset_w, "Uncommon+") then
                local ok, err = apply_quality_preset(client, true, true, true, false, false)
                _last_settings_result = ok and "Applied preset: Uncommon+" or ("Update failed: " .. tostring(err))
            end

            if window:is_mouse_hovering_rect(vec2.new(x, y_offset), vec2.new(x + width, y_offset + preset_h)) then
                self._tooltip = TOOLTIPS.quality_preset
            end

            return y_offset + preset_h + 4
        end,
    })

    -- 3. Combat -- Paladin (Retribution)
    t:row_list({
        label = "Combat -- Paladin",
        footer = "Thresholds for healing, potions, and resource management.",
        visible_when = function()
            return get_active_class_id(client) == PALADIN_CLASS_ID
        end,
        elements = {
            {
                type = "stepper", label = "Holy Light HP",
                tooltip = TOOLTIPS.ret_holy_hp,
                element = retri_stepper(client, "holy_light_hp_pct", 0.65),
                min = 0.10, max = 0.90, step = 0.02, decimals = 2,
            },
            {
                type = "stepper", label = "Flash Heal HP",
                tooltip = TOOLTIPS.ret_flash_hp,
                element = retri_stepper(client, "flash_light_hp_pct", 0.65),
                min = 0.10, max = 0.80, step = 0.02, decimals = 2,
            },
            {
                type = "stepper", label = "Low Mana Downrank",
                tooltip = TOOLTIPS.ret_low_mana,
                element = retri_stepper(client, "heal_low_mana_threshold", 0.22),
                min = 0.05, max = 0.60, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Health Potion HP",
                tooltip = TOOLTIPS.ret_health_pot,
                element = retri_stepper(client, "health_potion_hp_pct", 0.30),
                min = 0.10, max = 0.90, step = 0.02, decimals = 2,
            },
            {
                type = "stepper", label = "Mana Potion Mana",
                tooltip = TOOLTIPS.ret_mana_pot,
                element = retri_stepper(client, "mana_potion_mana_pct", 0.15),
                min = 0.05, max = 0.80, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Consecration ST Mana",
                tooltip = TOOLTIPS.ret_consec,
                element = retri_stepper(client, "consecration_st_min_mana_pct", 0.35),
                min = 0.10, max = 0.90, step = 0.02, decimals = 2,
            },
        },
    })

    -- 3b. Combat -- Warlock (Affliction)
    t:row_list({
        label = "Combat -- Warlock",
        footer = "Thresholds for healing, potions, and resource management.",
        visible_when = function()
            return get_active_class_id(client) == WARLOCK_CLASS_ID
        end,
        elements = {
            {
                type = "stepper", label = "Drink Mana",
                tooltip = TOOLTIPS.wl_drink,
                element = affli_stepper(client, "drink_mana_pct", 0.40),
                min = 0.05, max = 0.95, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Eat Health",
                tooltip = TOOLTIPS.wl_eat,
                element = affli_stepper(client, "eat_health_pct", 0.65),
                min = 0.10, max = 0.95, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Life Tap Min HP",
                tooltip = TOOLTIPS.wl_lifetap_min_hp,
                element = affli_stepper(client, "life_tap_min_health_pct", 0.50),
                min = 0.10, max = 0.95, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Life Tap Max Mana",
                tooltip = TOOLTIPS.wl_lifetap_max_mana,
                element = affli_stepper(client, "life_tap_max_mana_pct", 0.60),
                min = 0.05, max = 0.95, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Life Tap OOC Mana",
                tooltip = TOOLTIPS.wl_lifetap_ooc_max_mana,
                element = affli_stepper(client, "life_tap_ooc_max_mana_pct", 0.85),
                min = 0.10, max = 0.99, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Death Coil HP",
                tooltip = TOOLTIPS.wl_death_coil_hp,
                element = affli_stepper(client, "death_coil_hp_pct", 0.25),
                min = 0.05, max = 0.80, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Drain Life HP",
                tooltip = TOOLTIPS.wl_drain_life_hp,
                element = affli_stepper(client, "drain_life_hp_pct", 0.45),
                min = 0.10, max = 0.90, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Health Funnel Pet HP",
                tooltip = TOOLTIPS.wl_funnel_pet_hp,
                element = affli_stepper(client, "health_funnel_pet_hp_pct", 0.30),
                min = 0.05, max = 0.90, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Health Potion HP",
                tooltip = TOOLTIPS.wl_health_pot,
                element = affli_stepper(client, "health_potion_hp_pct", 0.25),
                min = 0.05, max = 0.90, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Mana Potion Mana",
                tooltip = TOOLTIPS.wl_mana_pot,
                element = affli_stepper(client, "mana_potion_mana_pct", 0.15),
                min = 0.05, max = 0.80, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Mana Potion Min HP",
                tooltip = TOOLTIPS.wl_mana_pot_min_hp,
                element = affli_stepper(client, "mana_potion_min_hp_pct", 0.35),
                min = 0.05, max = 0.90, step = 0.01, decimals = 2,
            },
            {
                type = "stepper", label = "Wand Mana Floor",
                tooltip = TOOLTIPS.wl_wand_mana,
                element = affli_stepper(client, "wand_mana_pct", 0.08),
                min = 0.00, max = 0.50, step = 0.01, decimals = 2,
            },
        },
    })

    -- 3c. Combat -- unsupported class placeholder
    t:row_list({
        label = "Combat",
        visible_when = function()
            local cid = get_active_class_id(client)
            return cid ~= PALADIN_CLASS_ID and cid ~= WARLOCK_CLASS_ID
        end,
        elements = {
            {
                type = "info", label = "Active Class",
                value_fn = function()
                    return class_label(get_active_class_id(client))
                end,
            },
            {
                type = "info", label = "Routine Settings",
                value_fn = function()
                    local cid = get_active_class_id(client)
                    if cid <= 0 then
                        return "Waiting for class context"
                    end
                    return "No settings for current class"
                end,
            },
        },
    })

    -- 4. Advanced (row_list)
    t:row_list({
        label = "Advanced",
        elements = {
            {
                type = "toggle",
                label = "Show Advanced",
                tooltip = TOOLTIPS.expert_panel,
                element = {
                    get_state = function() return _show_expert_settings == true end,
                    set = function(_, v) _show_expert_settings = v == true end,
                },
            },
            {
                type = "stepper", label = "Target Base Radius",
                tooltip = TOOLTIPS.target_base,
                element = targeting_stepper(client, "base_radius", "max_radius", 45),
                min = 10, max = 100, step = 1, decimals = 0,
                visible_when = function() return _show_expert_settings end,
            },
            {
                type = "stepper", label = "Target Max Radius",
                tooltip = TOOLTIPS.target_max,
                element = targeting_stepper(client, "max_radius", "base_radius", 75),
                min = 10, max = 140, step = 1, decimals = 0,
                visible_when = function() return _show_expert_settings end,
            },
            {
                type = "stepper", label = "Legacy Sell Quality",
                tooltip = TOOLTIPS.legacy_quality,
                element = policy_stepper(client, "sell_quality_max", 1),
                min = 0, max = 6, step = 1, decimals = 0,
                visible_when = function() return _show_expert_settings end,
            },
        },
    })

    -- 5. Save (custom_render)
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)
            local button_h = 32

            local btn_start = vec2.new(x, y_offset)
            local btn_end = vec2.new(x + width, y_offset + button_h)
            local hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
            if hovered then
                window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)
                self._tooltip = TOOLTIPS.save_settings
            end

            local bg = hovered and lighten_color(colors.primary_accent, 15) or colors.primary_accent
            window:render_rect_filled(btn_start, btn_end, bg, 8)

            local label = "Save to Active Profile"
            local ts = window:get_text_size(label)
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x + (width - ts.x) / 2, y_offset + (button_h - ts.y) / 2),
                colors.text_primary, label)

            if hovered and window:is_rect_clicked(btn_start, btn_end) then
                local active = client and client.get_active_profile_id and client:get_active_profile_id() or ""
                local ok, err = false, "not_available"
                if client and client.save_profile then
                    ok, err = client:save_profile(active)
                end
                _last_settings_result = ok and "Settings saved" or ("Save failed: " .. tostring(err))
            end

            y_offset = y_offset + button_h + 6

            if _last_settings_result then
                local fb = "Status: " .. tostring(_last_settings_result)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_secondary, fb)
                y_offset = y_offset + window:get_text_size(fb).y + 4
            end

            return y_offset
        end,
    })
end

return settings_tab
