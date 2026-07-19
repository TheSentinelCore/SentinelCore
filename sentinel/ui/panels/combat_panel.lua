-- sentinel/ui/panels/combat_panel.lua
-- Combat module UI panel

local SentinelUI = require("shared/ui/sentinel_ui")

local CombatPanel = {}
CombatPanel.__index = CombatPanel

function CombatPanel:new(blackboard, event_bus)
    local o = setmetatable({}, CombatPanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._combat = nil
    return o
end

function CombatPanel:init(combat_module)
    self._combat = combat_module

    self._ui = SentinelUI.new({
        id = "combat_panel",
        title = "Sentinel Combat",
        default_x = 100,
        default_y = 100,
        default_w = 450,
        default_h = 600,
        theme = "sentinel",
    })

    -- Core settings tab
    self._ui:add_tab({ id = "core", label = "Core" }, function(t)
        -- Enable combat toggle
        local enable = self._ui.menu.checkbox(true, "sentinel_combat_enable")
        -- Auto engage (BG)
        local auto_engage = self._ui.menu.checkbox(false, "sentinel_combat_auto_engage")
        -- Auto engage (world)
        local auto_engage_world = self._ui.menu.checkbox(false, "sentinel_combat_auto_engage_world")
        -- Burst mode
        local burst = self._ui.menu.checkbox(true, "sentinel_combat_burst")

        t:keybind_grid({
            elements = { enable, auto_engage, burst },
            labels = { "Enable Combat", "Auto Engage (BG)", "Burst Mode" }
        })

        t:checkbox_grid({
            label = "Toggles",
            columns = 2,
            elements = {
                { element = self._ui.menu.checkbox(true, "sentinel_combat_kite"), label = "Enable Kiting" },
                { element = self._ui.menu.checkbox(true, "sentinel_combat_face_target"), label = "Face Target" },
                { element = self._ui.menu.checkbox(true, "sentinel_combat_line_of_sight"), label = "Require LoS" },
            }
        })
    end)

    -- Rotation tab
    self._ui:add_tab({ id = "rotation", label = "Rotation" }, function(t)
        t:custom_render({
            label = "Rotation Controls",
            render_fn = function(ui, y)
                return self:_render_rotation_controls(ui, y)
            end
        })
    end)

    -- Targeting tab
    self._ui:add_tab({ id = "targeting", label = "Targeting" }, function(t)
        t:slider_list({
            label = "Targeting",
            elements = {
                { element = self._ui.menu.slider_int(3, 40, 25, "sentinel_combat_range"), label = "Combat Range", suffix = " yd" },
                { element = self._ui.menu.slider_int(1, 10, 3, "sentinel_combat_max_enemies"), label = "Max Enemies (AoE)", suffix = "" },
                { element = self._ui.menu.slider_int(10, 100, 25, "sentinel_combat_leash_radius"), label = "Leash Radius", suffix = " yd" },
            }
        })
    end)

    -- Safety tab
    self._ui:add_tab({ id = "safety", label = "Safety" }, function(t)
        t:slider_list({
            label = "Safety Thresholds",
            elements = {
                { element = self._ui.menu.slider_int(10, 80, 35, "sentinel_combat_low_health"), label = "Low Health %", suffix = "%" },
                { element = self._ui.menu.slider_int(1, 5, 2, "sentinel_combat_outnumbered"), label = "Outnumbered Delta", suffix = "" },
            }
        })
    end)

    -- Debug tab
    self._ui:add_tab({ id = "debug", label = "Debug" }, function(t)
        t:custom_render({
            label = "Debug Info",
            render_fn = function(ui, y)
                return self:_render_debug(ui, y)
            end
        })
    end)

    return true
end

function CombatPanel:_render_rotation_controls(ui, y)
    local window = ui.window
    local colors = ui.colors

    if not self._combat then return y end

    local state = self._combat:get_state()
    local target = self._combat:get_current_target()

    -- Current state
    local text = "State: " .. (state or "IDLE")
    local text_size = window:get_text_size(text)
    window:render_text(0, { x = 16, y = y }, colors.text_primary, text)
    y = y + text_size.y + 4

    -- Current target
    if target then
        local name = "Unknown"
        if type(target.get_name) == "function" then
            local ok, n = pcall(target.get_name, target)
            if ok and n then name = n end
        end
        text = "Target: " .. name
        text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, colors.secondary_accent, text)
        y = y + text_size.y + 4
    end

    -- GCD status
    local gcd_until = self._blackboard:get("combat.gcd_until_ms", 0)
    local now = self._blackboard:get("system.now_ms", 0)
    local gcd_remaining = math.max(0, gcd_until - now)
    text = string.format("GCD: %.2fs", gcd_remaining / 1000)
    text_size = window:get_text_size(text)
    window:render_text(0, { x = 16, y = y }, colors.text_secondary, text)
    y = y + text_size.y + 4

    return y
end

function CombatPanel:_render_debug(ui, y)
    local window = ui.window
    local colors = ui.colors

    if not self._combat then return y end

    local profile = self._blackboard:get("module.combat.profile")
    if profile then
        local text = "Profile: " .. (profile.name or "unknown")
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, colors.text_primary, text)
        y = y + text_size.y + 4
    end

    local rotation = self._blackboard:get("rotation.profile_id")
    if rotation then
        local text = "Rotation: " .. rotation
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, colors.text_secondary, text)
        y = y + text_size.y + 4
    end

    local last_block = self._blackboard:get("rotation.last_block_reason")
    if last_block then
        local text = "Block: " .. last_block
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, colors.status_orange, text)
        y = y + text_size.y + 4
    end

    return y
end

function CombatPanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function CombatPanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function CombatPanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function CombatPanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function CombatPanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function CombatPanel:shutdown()
    self._ui = nil
    self._combat = nil
end

return CombatPanel