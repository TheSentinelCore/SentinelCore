-- CoordTab.lua — Coordination server status, partner heartbeat, lockout.

local SentinelUI = require("lib/SentinelUI")
local color      = SentinelUI.color
local vec2       = SentinelUI.vec2
local enums      = SentinelUI.enums
local LAYOUT     = SentinelUI.LAYOUT

local CoordTab = {}

local function kv(window, colors, x, y, key, val, vc)
    local lbl = key .. ":  "
    local ls  = window:get_text_size(lbl)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.text_secondary, lbl)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + ls.x, y), vc or colors.text_primary, tostring(val))
    return y + ls.y + 5
end

local function section_label(window, colors, x, y, text)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.separator, text)
    window:render_rect_filled(vec2.new(x, y + 14),
        vec2.new(x + window:get_size().x - 2 * LAYOUT.padding_side, y + 15),
        colors.row_separator or colors.separator, 0)
    return y + 20
end

---@param ui table SentinelUI instance
---@param bb table Blackboard
function CoordTab.register(ui, bb)
    ui:add_tab({ id = "coord", label = "Coord" }, function(t)

        t:custom_render({ render_fn = function(self, y)
            local window = self.window
            local colors = self.colors
            local x  = LAYOUT.padding_side

            -- Connection status
            y = section_label(window, colors, x, y, "SERVER")
            local conn    = bb:get("duo.coord_connected", false)
            local conn_c  = conn and color.new(48, 209, 88, 255) or color.new(255, 69, 58, 255)
            y = kv(window, colors, x, y, "Status",    conn and "Connected" or "Offline", conn_c)
            y = kv(window, colors, x, y, "Client ID", bb:get("duo.my_client_id", "(pending)"))
            y = kv(window, colors, x, y, "Role",      bb:get("duo.is_puller", false) and "Puller" or "Support")
            y = kv(window, colors, x, y, "Session",   bb:get("duo.session_phase", "—"))
            y = kv(window, colors, x, y, "Puller ID", bb:get("duo.puller_id", "—"))
            y = kv(window, colors, x, y, "Pull #",    bb:get("duo.pull_index", 0))

            -- Partner section
            y = section_label(window, colors, x, y, "PARTNER")
            local p_conn  = bb:get("duo.partner_connected",  false)
            local p_phase = bb:get("duo.partner_phase",      "offline")
            local p_hp    = math.floor(bb:get("duo.partner_health_pct", 0) * 100)
            local p_mp    = math.floor(bb:get("duo.partner_mana_pct",   0) * 100)
            local p_bags  = bb:get("duo.partner_bags_full", false)
            local pc_c    = p_conn and color.new(48, 209, 88, 255) or color.new(255, 69, 58, 255)
            y = kv(window, colors, x, y, "Online",    p_conn and "Yes" or "No",       pc_c)
            y = kv(window, colors, x, y, "Phase",     p_phase)
            y = kv(window, colors, x, y, "HP / MP",   string.format("%d%% / %d%%", p_hp, p_mp))
            y = kv(window, colors, x, y, "Bags full", tostring(p_bags))

            -- Lockout section
            y = section_label(window, colors, x, y, "LOCKOUT")
            local resets  = bb:get("duo.lockout.reset_count", 0)
            local near    = bb:get("duo.lockout.near_limit",  false)
            local wait_s  = bb:get("duo.lockout.wait_secs",   0)
            local nr_c    = near and color.new(255, 159, 10, 255) or colors.text_primary
            y = kv(window, colors, x, y, "Resets",     string.format("%d / 5  (hourly)", resets))
            y = kv(window, colors, x, y, "Near limit", tostring(near), nr_c)
            y = kv(window, colors, x, y, "Wait",       wait_s > 0 and (wait_s .. "s remaining") or "None")

            -- Vendor break
            if bb:get("duo.vendor_break_active", false) then
                y = y + 2
                local lbl = "  VENDOR BREAK ACTIVE  "
                local ls  = window:get_text_size(lbl)
                window:render_rect_filled(vec2.new(x, y), vec2.new(x + ls.x + 4, y + ls.y + 4),
                    color.new(180, 100, 30, 200), 4)
                window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + 2, y + 2),
                    colors.text_primary, lbl)
                y = y + ls.y + 8
            end

            return y + 4
        end })
    end)
end

return CoordTab
