-- DashboardTab.lua — Bot control + local status overview.

local SentinelUI = require("lib/SentinelUI")
local color      = SentinelUI.color
local vec2       = SentinelUI.vec2
local enums      = SentinelUI.enums
local LAYOUT     = SentinelUI.LAYOUT

local DashboardTab = {}

-- Persistent menu element for overlay toggle (created once at load time)
local _overlay_cb = core.menu.checkbox(false, "duo_show_overlay")

-- ---------------------------------------------------------------------------
-- Render helpers (local to this tab)
-- ---------------------------------------------------------------------------

local function render_btn(ui, x, y, w, h, label, enabled)
    local window = ui.window
    local colors = ui.colors
    local s = vec2.new(x, y)
    local e = vec2.new(x + w, y + h)
    local hov = window:is_mouse_hovering_rect(s, e)
    window:is_mouse_hovering_rect_block_movement(s, e)
    local r, g, b, a = colors.primary_accent:get()
    local bg = not enabled and colors.checkbox_inactive
        or hov and color.new(math.min(255, r + 22), math.min(255, g + 22), math.min(255, b + 22), a)
        or colors.primary_accent
    window:render_rect_filled(s, e, bg, 6)
    local ts = window:get_text_size(label)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + (w - ts.x) / 2, y + (h - ts.y) / 2),
        enabled and colors.text_primary or colors.text_disabled, label)
    return enabled and hov and window:is_rect_clicked(s, e)
end

local function pct_bar(window, colors, x, y, w, h, pct, fill_color)
    window:render_rect_filled(vec2.new(x, y), vec2.new(x + w, y + h), colors.slider_bg, 3)
    local fw = math.max(0, math.min(1, pct)) * w
    if fw > 0 then
        window:render_rect_filled(vec2.new(x, y), vec2.new(x + fw, y + h), fill_color, 3)
    end
    window:render_rect(vec2.new(x, y), vec2.new(x + w, y + h), colors.section_border, 3, 1)
end

local function kv(window, colors, x, y, key, val, vc)
    local lbl = key .. ":  "
    local ls  = window:get_text_size(lbl)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.text_secondary, lbl)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + ls.x, y), vc or colors.text_primary, tostring(val))
    return y + ls.y + 5
end

local function section_label(window, colors, x, y, text)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.separator, text)
    window:render_rect_filled(vec2.new(x, y + 14), vec2.new(x + window:get_size().x - 2 * LAYOUT.padding_side, y + 15),
        colors.row_separator or colors.separator, 0)
    return y + 20
end

-- ---------------------------------------------------------------------------
-- Tab registration
-- ---------------------------------------------------------------------------

---@param ui table SentinelUI instance
---@param bb table Blackboard
function DashboardTab.register(ui, bb)
    ui:add_tab({ id = "dashboard", label = "Dashboard" }, function(t)

        -- ── Controls & Local Status (combined custom block) ───────────────
        t:custom_render({ render_fn = function(self, y)
            local window = self.window
            local colors = self.colors
            local x  = LAYOUT.padding_side
            local cw = window:get_size().x - 2 * LAYOUT.padding_side

            -- Sync overlay to blackboard every frame
            if _overlay_cb then
                bb:set("duo.show_overlay", _overlay_cb:get_state())
            end

            -- === Controls row ===
            y = section_label(window, colors, x, y, "CONTROLS")
            local bh = 26
            local bw = (cw - 12) / 4

            local running = bb:get("duo.bot_running",  false)
            local paused  = bb:get("duo.user_paused",  false)

            if render_btn(self, x, y, bw, bh, running and "Stop" or "Start", true) then
                bb:set("duo.bot_running", not running)
                if not running then bb:set("duo.user_paused", false) end
            end
            if render_btn(self, x + (bw + 4), y, bw, bh, paused and "Resume" or "Pause", running) then
                bb:set("duo.user_paused", not paused)
            end
            if render_btn(self, x + (bw + 4) * 2, y, bw, bh, "Vendor", running) then
                bb:set("duo.force_vendor", true)
            end
            if render_btn(self, x + (bw + 4) * 3, y, bw, bh, "E-Stop", true) then
                bb:set("duo.bot_running", false)
                bb:set("duo.user_paused", false)
            end
            y = y + bh + 10

            -- === Local Status ===
            y = section_label(window, colors, x, y, "LOCAL")

            local hp   = bb:get("player.hp_pct", 1.0)
            local mp   = bb:get("player.mp_pct", 1.0)
            local bar_h = 8

            -- HP / MP bars side by side
            local bw2 = (cw - 8) / 2
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x, y), colors.text_secondary, string.format("HP %d%%", math.floor(hp * 100)))
            pct_bar(window, colors, x + 32, y, bw2 - 32, bar_h, hp, color.new(66, 188, 90, 220))
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x + bw2 + 8, y), colors.text_secondary, string.format("MP %d%%", math.floor(mp * 100)))
            pct_bar(window, colors, x + bw2 + 40, y, bw2 - 32, bar_h, mp, color.new(68, 130, 226, 220))
            y = y + bar_h + 8

            y = kv(window, colors, x, y, "State",      bb:get("duo.current_state", "INIT"))
            y = kv(window, colors, x, y, "Farm phase", bb:get("duo.farm_sub_state", "—"))
            y = kv(window, colors, x, y, "Role",       bb:get("duo.is_puller", false) and "Puller" or "Support")
            y = kv(window, colors, x, y, "Client ID",  bb:get("duo.my_client_id", "(pending)"))
            y = kv(window, colors, x, y, "Pull #",     bb:get("duo.pull_index", 0))
            y = kv(window, colors, x, y, "Bag slots",  bb:get("duo.free_bag_slots", 0))
            y = kv(window, colors, x, y, "Map ID",     bb:get("player.map_id", 0))

            -- Lockout warning banner
            if bb:get("duo.lockout.near_limit", false) then
                local wait = bb:get("duo.lockout.wait_secs", 0)
                local warn = string.format("  LOCKOUT WARNING — must wait %ds  ", wait)
                local ws2  = window:get_text_size(warn)
                local banner_s = vec2.new(x, y)
                local banner_e = vec2.new(x + ws2.x + 4, y + ws2.y + 4)
                window:render_rect_filled(banner_s, banner_e, color.new(180, 100, 30, 200), 4)
                window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + 2, y + 2),
                    colors.text_primary, warn)
                y = y + ws2.y + 8
            end

            -- Overlay toggle (inline, simple)
            local ov_on  = _overlay_cb and _overlay_cb:get_state() or false
            local ov_col = ov_on and colors.secondary_accent or colors.text_secondary
            local ov_lbl = (ov_on and "[x]" or "[ ]") .. "  3D overlay"
            local ov_ts  = window:get_text_size(ov_lbl)
            local ov_s   = vec2.new(x, y)
            local ov_e   = vec2.new(x + ov_ts.x + 4, y + ov_ts.y + 2)
            window:is_mouse_hovering_rect_block_movement(ov_s, ov_e)
            if window:is_rect_clicked(ov_s, ov_e) and _overlay_cb then
                _overlay_cb:set(not ov_on)
            end
            window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), ov_col, ov_lbl)
            y = y + ov_ts.y + 8

            return y
        end })
    end)
end

return DashboardTab
