-- DuoWindow.lua — SentinelDuoFarm main UI window (SentinelUI canvas-based).
-- Creates a floating settings window with 5 tabs + a live control bar.

local SentinelUI = require("lib/SentinelUI")
local color      = SentinelUI.color
local vec2       = SentinelUI.vec2
local enums      = SentinelUI.enums
local LAYOUT     = SentinelUI.LAYOUT

-- Tab registration modules
local DashboardTab = require("ui/tabs/DashboardTab")
local CoordTab     = require("ui/tabs/CoordTab")
local StatsTab     = require("ui/tabs/StatsTab")
local ProfileTab   = require("ui/tabs/ProfileTab")
local DebugTab     = require("ui/tabs/DebugTab")

---@class DuoWindow
local DuoWindow = {}
DuoWindow.__index = DuoWindow

-- ---------------------------------------------------------------------------
-- Helpers shared across control bar and tabs
-- ---------------------------------------------------------------------------

--- Render a filled status card. Returns the bottom y after the card.
local function render_card(window, colors, x, y, w, label, value, state)
    local h = 44
    local bg
    if state == "good"  then bg = color.new(42, 130, 82, 185)
    elseif state == "warn"  then bg = color.new(160, 118, 28, 185)
    elseif state == "bad"   then bg = color.new(155, 58, 58, 185)
    elseif state == "blue"  then bg = color.new(46, 90, 160, 185)
    else                        bg = colors.bg_card or colors.section_bg
    end

    local s = vec2.new(x, y)
    local e = vec2.new(x + w, y + h)
    window:render_rect_filled(s, e, bg, LAYOUT.card_corner_radius)
    window:render_rect(s, e, colors.section_border, LAYOUT.card_corner_radius, 1)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,  vec2.new(x + 9, y + 5),  colors.text_secondary, label)
    window:render_text(enums.window_enums.font_id.FONT_SEMI_BIG, vec2.new(x + 9, y + 21), colors.text_primary,   value)
    return y + h + 6
end

--- Render an action button. Returns true if clicked.
local function render_btn(window, colors, x, y, w, h, label, enabled)
    local s = vec2.new(x, y)
    local e = vec2.new(x + w, y + h)
    local hov = window:is_mouse_hovering_rect(s, e)
    window:is_mouse_hovering_rect_block_movement(s, e)
    local r, g, b, a = colors.primary_accent:get()
    local bg = not enabled and (colors.checkbox_inactive)
        or hov and color.new(math.min(255, r + 22), math.min(255, g + 22), math.min(255, b + 22), a)
        or colors.primary_accent
    window:render_rect_filled(s, e, bg, 6)
    local ts = window:get_text_size(label)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + (w - ts.x) / 2, y + (h - ts.y) / 2),
        enabled and colors.text_primary or colors.text_disabled, label)
    return enabled and hov and window:is_rect_clicked(s, e)
end

--- Pill toggle — returns new state if clicked, else nil.
local function render_pill(window, colors, x, y, is_on, label)
    local tw = LAYOUT.toggle_width
    local th = LAYOUT.toggle_height
    local margin = LAYOUT.toggle_thumb_margin
    local radius = th / 2
    local track_color = is_on and (colors.toggle_track_on or colors.secondary_accent)
                               or  (colors.toggle_track_off or colors.checkbox_inactive)
    window:render_rect_filled(vec2.new(x, y), vec2.new(x + tw, y + th), track_color, radius)
    local tx = is_on and (x + tw - LAYOUT.toggle_thumb_size - margin) or (x + margin)
    window:render_rect_filled(
        vec2.new(tx, y + margin),
        vec2.new(tx + LAYOUT.toggle_thumb_size, y + margin + LAYOUT.toggle_thumb_size),
        colors.toggle_thumb or color.new(255, 255, 255, 255), LAYOUT.toggle_thumb_size / 2)
    local lx, ly = x + tw + 6, y + (th - 12) / 2
    local lc = is_on and colors.text_primary or colors.text_secondary
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(lx, ly), lc, label)
    local label_w = window:get_text_size(label).x
    local hs = vec2.new(x, y)
    local he = vec2.new(lx + label_w, y + th)
    local hov = window:is_mouse_hovering_rect(hs, he)
    if hov then window:is_mouse_hovering_rect_block_movement(hs, he) end
    if hov and window:is_rect_clicked(hs, he) then return not is_on end
    return nil
end

-- ---------------------------------------------------------------------------
-- Control bar: rendered above the tab bar each frame.
-- ---------------------------------------------------------------------------

local function render_control_bar(ui, bb, y_offset)
    local window  = ui.window
    local colors  = ui.colors
    local x       = LAYOUT.padding_side
    local ws      = window:get_size()
    local cw      = ws.x - 2 * LAYOUT.padding_side

    -- Gather live data
    local state      = bb:get("duo.current_state", "INIT")
    local running    = bb:get("duo.bot_running",   false)
    local paused     = bb:get("duo.user_paused",   false)
    local hp_a       = math.floor((bb:get("player.hp_pct",    1.0)) * 100)
    local mp_a       = math.floor((bb:get("player.mp_pct",    1.0)) * 100)
    local hp_b       = math.floor((bb:get("duo.partner_health_pct", 0)) * 100)
    local mp_b       = math.floor((bb:get("duo.partner_mana_pct",   0)) * 100)
    local p_phase    = bb:get("duo.partner_phase",     "offline")
    local p_conn     = bb:get("duo.partner_connected", false)
    local pull_idx   = bb:get("duo.pull_index", 0)
    local is_puller  = bb:get("duo.is_puller", false)

    -- Status card values
    local state_label = paused and "PAUSED" or (running and state or "STOPPED")
    local state_type  = paused and "warn" or (running and "good" or "bad")
    local role_str    = is_puller and "(Puller)" or "(Support)"
    local mage_a_val  = string.format("HP%d  MP%d  P%d", hp_a, mp_a, pull_idx)
    local mage_b_val  = p_conn
        and string.format("HP%d  MP%d  %s", hp_b, mp_b, p_phase)
        or "Offline"
    local mage_b_type = p_conn and "good" or "bad"

    -- Layout: 3 cards + pill toggle right-aligned
    local card_gap    = 8
    local card_h      = 44
    local toggle_label = running and (paused and "Resume" or "Pause") or "Start"
    local toggle_w    = LAYOUT.toggle_width + 6 + window:get_text_size(toggle_label).x
    local cards_avail = cw - toggle_w - card_gap
    local card_w      = math.floor((cards_avail - card_gap * 2) / 3)

    -- Cards
    render_card(window, colors, x,                  y_offset, card_w, "Session",
        state_label, state_type)
    render_card(window, colors, x + card_w + card_gap, y_offset, card_w,
        "Mage A " .. role_str, mage_a_val, "blue")
    render_card(window, colors, x + (card_w + card_gap) * 2, y_offset, card_w,
        "Mage B", mage_b_val, mage_b_type)

    -- Pill toggle (START/PAUSE/RESUME)
    local tog_x = x + cw - toggle_w
    local tog_y = y_offset + math.floor((card_h - LAYOUT.toggle_height) / 2)
    local new_state = render_pill(window, colors, tog_x, tog_y, running and not paused, toggle_label)
    if new_state ~= nil then
        if not running then
            bb:set("duo.bot_running", true)
            bb:set("duo.user_paused", false)
        else
            bb:set("duo.user_paused", not paused)
        end
    end

    -- Separator
    y_offset = y_offset + card_h + 6
    window:render_rect_filled(
        vec2.new(x, y_offset), vec2.new(x + cw, y_offset + 1), colors.separator, 0)
    return y_offset + 6
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param bb table Blackboard
---@return DuoWindow
function DuoWindow:new(bb)
    return setmetatable({ _bb = bb, _ui = nil }, DuoWindow)
end

function DuoWindow:initialize()
    local bb = self._bb

    self._ui = SentinelUI.new({
        id           = "sentinel_duo_farm",
        title        = "SentinelDuo",
        default_x    = 560,
        default_y    = 80,
        default_w    = 760,
        default_h    = 680,
        theme        = "sentinel",
        render_layer = 1,
    })

    -- Control bar above tab bar
    self._ui._before_tabs_fn = function(ui_ctx, y)
        return render_control_bar(ui_ctx, bb, y)
    end

    -- Register tabs (each file accepts ui + bb)
    DashboardTab.register(self._ui, bb)
    CoordTab.register(self._ui, bb)
    StatsTab.register(self._ui, bb)
    ProfileTab.register(self._ui, bb)
    DebugTab.register(self._ui, bb)

    -- Start visible
    self._ui.menu.enable:set(true)
end

--- Called from App:on_render() — renders the floating SentinelUI window.
function DuoWindow:on_render()
    if not self._ui then return end
    pcall(self._ui.on_render, self._ui)
end

--- Called from App:on_render_menu() — renders the PS menu toggle button.
function DuoWindow:render_menu()
    if not self._ui then return end
    pcall(self._ui.on_menu_render, self._ui)
end

--- Legacy no-op (blackboard is read directly from closures each frame).
function DuoWindow:sync(_bb) end

return DuoWindow
