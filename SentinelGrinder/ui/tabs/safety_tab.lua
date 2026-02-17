local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local AstroUI = require("shared/AstroUI")

local LAYOUT = AstroUI.LAYOUT

local SafetyTab = {}

local _controller = nil

local function render_button(window, x, y, width, height, text, colors, accent_color)
    local btn_start = vec2.new(x, y)
    local btn_end = vec2.new(x + width, y + height)

    local is_hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
    window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

    local bg = is_hovered and accent_color or colors.section_bg
    window:render_rect_filled(btn_start, btn_end, bg, 3.0)
    window:render_rect(btn_start, btn_end, accent_color, 3.0, 1.0)

    local text_size = window:get_text_size(text)
    local text_x = x + (width - text_size.x) / 2
    local text_y = y + (height - text_size.y) / 2
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(text_x, text_y), color.white(245), text)

    return window:is_rect_clicked(btn_start, btn_end)
end

function SafetyTab.render_debug(ui, y_offset)
    if not _controller then
        return y_offset
    end

    local window = ui.window
    local colors = ui.colors
    local x_start = LAYOUT.padding_side

    y_offset = y_offset + LAYOUT.section_padding_top

    local btn_w = 170
    local btn_h = 24
    if render_button(window, x_start, y_offset, btn_w, btn_h, "Clear Runtime Blacklist", colors,
            color.new(180, 140, 70, 255)) then
        if _controller.clear_runtime_blacklists then
            local guid_count, zone_count = _controller:clear_runtime_blacklists()
            core.log(string.format("[GrindBuddy] Cleared runtime blacklist: %d guid, %d zones", guid_count or 0,
                zone_count or 0))
        end
    end

    return y_offset + btn_h + LAYOUT.section_padding_bottom
end

---@param ui any
---@param menu table
---@param controller any
function SafetyTab.register(ui, menu, controller)
    _controller = controller
    ui:add_tab({ id = "safety", label = "Safety" }, function(t)
        t:checkbox_grid({
            label = "Movement Recovery",
            columns = 1,
            elements = {
                { element = menu.unstuck_enabled, label = "Enable Unstuck", tooltip = "Attempt movement recovery when pathing stalls." },
                { element = menu.auto_mount_enabled, label = "Auto Mount On Patrol", tooltip = "Mount for long patrol moves and dismount before combat/pull." },
            },
        })

        t:slider_list({
            label = "Recovery Thresholds",
            elements = {
                { element = menu.unstuck_max_attempts, label = "Unstuck Max Attempts", tooltip = "Maximum retries before skipping/blackspot." },
                { element = menu.move_timeout, label = "Move Timeout", suffix = " s", tooltip = "Max duration for a move request." },
                { element = menu.move_stall_timeout, label = "Move Stall Timeout", suffix = " s", tooltip = "Stall duration before unstuck attempts." },
                { element = menu.move_progress_min, label = "Move Progress Min", suffix = " yd", tooltip = "Minimum movement to consider progress." },
                { element = menu.mount_threshold, label = "Mount Threshold", suffix = " yd", tooltip = "Patrol distance needed before mounting." },
            },
        })

        t:slider_list({
            label = "Blacklist",
            elements = {
                { element = menu.blacklist_ttl, label = "Target Blacklist TTL", suffix = " s", tooltip = "How long timed-out targets stay blacklisted." },
                { element = menu.zone_blacklist_ttl, label = "Zone Blacklist TTL", suffix = " s", tooltip = "How long problematic zones stay blacklisted." },
                { element = menu.zone_blacklist_radius, label = "Zone Blacklist Radius", suffix = " yd", tooltip = "Radius of temporary zone blacklist around failed target." },
                { element = menu.blackspot_radius, label = "Persistent Blackspot Radius", suffix = " yd", tooltip = "Radius for saved blackspots when unstuck fully fails." },
                { element = menu.blackspot_ttl, label = "Persistent Blackspot TTL", suffix = " s", tooltip = "0 means no expiration for persistent blackspots." },
            },
        })

        t:custom_render({ render_fn = SafetyTab.render_debug })
    end)
end

return SafetyTab
