-- DebugTab.lua — State trace, blackboard key dump, nav status.

local SentinelUI = require("lib/SentinelUI")
local color      = SentinelUI.color
local vec2       = SentinelUI.vec2
local enums      = SentinelUI.enums
local LAYOUT     = SentinelUI.LAYOUT

local DebugTab = {}

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

-- Key blackboard fields displayed in the dump panel
local BB_KEYS = {
    "duo.current_state",
    "duo.farm_sub_state",
    "duo.is_puller",
    "duo.my_client_id",
    "duo.puller_id",
    "duo.pull_index",
    "duo.coord_connected",
    "duo.coord_last_poll_ms",
    "duo.partner_phase",
    "duo.partner_connected",
    "duo.nav_stuck_count",
    "player.hp_pct",
    "player.mp_pct",
    "player.is_dead",
    "player.in_instance",
    "player.map_id",
}

---@param ui table SentinelUI instance
---@param bb table Blackboard
function DebugTab.register(ui, bb)
    ui:add_tab({ id = "debug", label = "Debug" }, function(t)

        -- ── Blackboard dump ───────────────────────────────────────────────
        t:custom_render({ render_fn = function(self, y)
            local window = self.window
            local colors = self.colors
            local x  = LAYOUT.padding_side

            y = section_label(window, colors, x, y, "BLACKBOARD")
            for _, k in ipairs(BB_KEYS) do
                local v = bb:get(k, nil)
                if v ~= nil then
                    local fmt = type(v) == "number"
                        and string.format("%.3f", v)
                        or tostring(v)
                    y = kv(window, colors, x, y, k, fmt)
                end
            end
            return y + 4
        end })

        -- ── State trace ───────────────────────────────────────────────────
        t:custom_render({ render_fn = function(self, y)
            local window = self.window
            local colors = self.colors
            local x  = LAYOUT.padding_side

            y = section_label(window, colors, x, y, "STATE TRACE (last 10)")

            local trace = bb:get("duo._state_trace", {})
            local n     = #trace
            if n == 0 then
                window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y),
                    colors.text_disabled, "(no transitions yet)")
                y = y + 14
            else
                for i = n, math.max(1, n - 9), -1 do
                    local e = trace[i]
                    if e then
                        local txt = string.format("  %s  ->  %s   pull=%d",
                            tostring(e.from), tostring(e.to), e.pull or 0)
                        window:render_text(enums.window_enums.font_id.FONT_SMALL,
                            vec2.new(x, y), colors.text_secondary, txt)
                        y = y + 14
                    end
                end
            end

            return y + 4
        end })

        -- ── Nav status ────────────────────────────────────────────────────
        t:custom_render({ render_fn = function(self, y)
            local window = self.window
            local colors = self.colors
            local x  = LAYOUT.padding_side

            y = section_label(window, colors, x, y, "NAVIGATION")
            y = kv(window, colors, x, y, "Stuck count", bb:get("duo.nav_stuck_count", 0))

            local nav_ok, nav_client = pcall(function()
                return _G.SentinelNavClient and _G.SentinelNavClient.client
            end)
            if nav_ok and nav_client then
                local ok_s, s = pcall(nav_client.get_state, nav_client)
                y = kv(window, colors, x, y, "Nav state", ok_s and s or "error")
            else
                y = kv(window, colors, x, y, "Nav client", "not loaded",
                    color.new(255, 159, 10, 255))
            end

            return y + 4
        end })
    end)
end

return DebugTab
