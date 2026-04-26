-- StatsTab.lua — Session statistics.

local SentinelUI = require("lib/SentinelUI")
local color      = SentinelUI.color
local vec2       = SentinelUI.vec2
local enums      = SentinelUI.enums
local LAYOUT     = SentinelUI.LAYOUT

local StatsTab = {}

local function kv(window, colors, x, y, key, val, vc)
    local lbl = key .. ":  "
    local ls  = window:get_text_size(lbl)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.text_secondary, lbl)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + ls.x, y), vc or colors.text_primary, tostring(val))
    return y + ls.y + 5
end

local function metric_card(window, colors, x, y, w, label, number, sub)
    local h = 54
    window:render_rect_filled(vec2.new(x, y), vec2.new(x + w, y + h),
        colors.bg_card or colors.section_bg, LAYOUT.card_corner_radius)
    window:render_rect(vec2.new(x, y), vec2.new(x + w, y + h),
        colors.section_border, LAYOUT.card_corner_radius, 1)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + 8, y + 6),
        colors.text_secondary, label)
    window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG, vec2.new(x + 8, y + 22),
        colors.text_primary, number)
    if sub and sub ~= "" then
        window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + 8, y + 38),
            colors.text_secondary, sub)
    end
    return y + h + 6
end

---@param ui table SentinelUI instance
---@param bb table Blackboard
function StatsTab.register(ui, bb)
    ui:add_tab({ id = "stats", label = "Stats" }, function(t)

        t:custom_render({ render_fn = function(self, y)
            local window = self.window
            local colors = self.colors
            local x  = LAYOUT.padding_side
            local cw = window:get_size().x - 2 * LAYOUT.padding_side

            local runs    = bb:get("duo.runs_completed",      0)
            local deaths  = bb:get("duo.deaths_this_session", 0)
            local start_ms = bb:get("duo.session_start_ms",   0)
            local ok_gt, gt = pcall(core.game_time)
            local gt_val = (ok_gt and gt) or 0
            local elapsed = math.max(0, math.floor((gt_val - start_ms) / 1000))

            local h_  = math.floor(elapsed / 3600)
            local m_  = math.floor((elapsed % 3600) / 60)
            local s_  = elapsed % 60
            local time_str = string.format("%02d:%02d:%02d", h_, m_, s_)
            local rph = (elapsed > 60) and (runs / (elapsed / 3600)) or 0

            -- 3 metric cards
            local gap  = 8
            local card_w = math.floor((cw - gap * 2) / 3)

            metric_card(window, colors, x, y, card_w,
                "Runs", tostring(runs), string.format("%.1f/hr", rph))
            metric_card(window, colors, x + card_w + gap, y, card_w,
                "Deaths", tostring(deaths), "this session")
            metric_card(window, colors, x + (card_w + gap) * 2, y, card_w,
                "Session", time_str, "")
            y = y + 60

            -- Extra stats
            y = kv(window, colors, x, y, "Bag slots free", bb:get("duo.free_bag_slots", 0))
            y = kv(window, colors, x, y, "Bags full",      tostring(bb:get("duo.bags_full_local", false)))
            y = kv(window, colors, x, y, "Nav stuck cnt",  bb:get("duo.nav_stuck_count", 0))

            -- Reset button
            y = y + 6
            local bw, bh = 120, 24
            local hov = window:is_mouse_hovering_rect(vec2.new(x, y), vec2.new(x + bw, y + bh))
            window:is_mouse_hovering_rect_block_movement(vec2.new(x, y), vec2.new(x + bw, y + bh))
            local r, g, b, a = colors.primary_accent:get()
            local bg = hov and color.new(math.min(255, r + 22), math.min(255, g + 22), math.min(255, b + 22), a)
                or colors.primary_accent
            window:render_rect_filled(vec2.new(x, y), vec2.new(x + bw, y + bh), bg, 6)
            local ts = window:get_text_size("Reset Stats")
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x + (bw - ts.x) / 2, y + (bh - ts.y) / 2),
                colors.text_primary, "Reset Stats")
            if hov and window:is_rect_clicked(vec2.new(x, y), vec2.new(x + bw, y + bh)) then
                bb:set("duo.runs_completed",      0)
                bb:set("duo.deaths_this_session", 0)
                local ok2, gt2 = pcall(core.game_time)
                bb:set("duo.session_start_ms", (ok2 and gt2) or 0)
            end
            y = y + bh + 4

            return y
        end })
    end)
end

return StatsTab
