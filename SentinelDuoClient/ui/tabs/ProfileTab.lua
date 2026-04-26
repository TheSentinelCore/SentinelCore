-- ProfileTab.lua — Profile creator, editor, and loader.
-- Two views: "list" (browse/manage saved profiles) and "editor" (edit fields).

local SentinelUI     = require("lib/SentinelUI")
local ProfileManager = require("core/ProfileManager")
local color          = SentinelUI.color
local vec2           = SentinelUI.vec2
local enums          = SentinelUI.enums
local LAYOUT         = SentinelUI.LAYOUT

local ProfileTab = {}

-- ---------------------------------------------------------------------------
-- Shared UI helpers
-- ---------------------------------------------------------------------------

local function txt(window, colors, x, y, str, col)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), col or colors.text_primary, str)
    return y + 14
end

local function section(window, colors, x, y, label, cw)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.separator, label)
    window:render_rect_filled(vec2.new(x, y + 14), vec2.new(x + cw, y + 15), colors.row_separator or colors.separator, 0)
    return y + 20
end

local function kv(window, colors, x, y, key, val, vc)
    local lbl = key .. ":  "
    local ls  = window:get_text_size(lbl)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y), colors.text_secondary, lbl)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x + ls.x, y), vc or colors.text_primary, tostring(val))
    return y + ls.y + 4
end

--- Small action button. Returns true if clicked.
local function small_btn(window, colors, x, y, w, h, label, col)
    local s = vec2.new(x, y)
    local e = vec2.new(x + w, y + h)
    local hov = window:is_mouse_hovering_rect(s, e)
    window:is_mouse_hovering_rect_block_movement(s, e)
    local bg_base = col or colors.primary_accent
    local bg
    if hov then
        local r, g, b, a = bg_base:get()
        bg = color.new(math.min(255, r + 22), math.min(255, g + 22), math.min(255, b + 22), a)
    else
        bg = bg_base
    end
    window:render_rect_filled(s, e, bg, 4)
    local ts = window:get_text_size(label)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + (w - ts.x) / 2, y + (h - ts.y) / 2), colors.text_primary, label)
    return hov and window:is_rect_clicked(s, e)
end

--- Horizontal slider that stores drag state in a per-slider table.
--- Returns new_value.
local function slider(window, colors, x, y, track_w, value, min_v, max_v, drag)
    local th     = 4
    local tsz    = 10
    local row_h  = 18
    local ty     = y + (row_h - th) / 2
    local ty_t   = y + (row_h - tsz) / 2
    local pct    = math.max(0, math.min(1, (value - min_v) / math.max(max_v - min_v, 0.0001)))

    -- Track
    window:render_rect_filled(vec2.new(x, ty), vec2.new(x + track_w, ty + th),
        colors.row_separator or colors.separator, 2)
    -- Fill
    if pct > 0 then
        window:render_rect_filled(vec2.new(x, ty), vec2.new(x + track_w * pct, ty + th),
            colors.primary_accent or color.new(66, 165, 245, 200), 2)
    end
    -- Thumb
    local tx = x + track_w * pct - tsz / 2
    local hov_t = window:is_mouse_hovering_rect(vec2.new(tx, ty_t), vec2.new(tx + tsz, ty_t + tsz))
    window:is_mouse_hovering_rect_block_movement(vec2.new(x, y), vec2.new(x + track_w, y + row_h))
    window:render_rect_filled(vec2.new(tx, ty_t), vec2.new(tx + tsz, ty_t + tsz),
        hov_t and colors.text_primary or (colors.toggle_thumb or color.new(200, 200, 200, 230)),
        tsz / 2)

    -- Click to set value
    local hit_s = vec2.new(x, y)
    local hit_e = vec2.new(x + track_w, y + row_h)
    if window:is_mouse_hovering_rect(hit_s, hit_e) and window:is_rect_clicked(hit_s, hit_e) then
        drag.active = true
    end
    local new_val = value
    if drag.active then
        local ok_mp, mp = pcall(function() return window.get_mouse_pos and window:get_mouse_pos() or nil end)
        if ok_mp and mp then
            local rel = math.max(0, math.min(1, (mp.x - x) / math.max(track_w, 1)))
            new_val = min_v + rel * (max_v - min_v)
            if math.floor(max_v) == max_v and max_v >= 2 then
                new_val = math.floor(new_val + 0.5)
            end
            new_val = math.max(min_v, math.min(max_v, new_val))
        end
        if not window:is_mouse_hovering_rect(vec2.new(x - 20, y - 4), vec2.new(x + track_w + 20, y + row_h + 4)) then
            drag.active = false
        end
    end
    return new_val
end

--- A slider row with label on the left and value text on the right.
--- Returns (new_value, new_y).
local function slider_row(window, colors, x, y, cw, label, value, min_v, max_v, fmt, drag)
    local row_h    = 20
    local lbl_w    = 180
    local val_w    = 55
    local track_w  = cw - lbl_w - val_w - 8

    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x, y + 3), colors.text_secondary, label)
    local new_val = slider(window, colors, x + lbl_w, y + 1, track_w, value, min_v, max_v, drag)
    local val_str
    if type(fmt) == "function" then
        val_str = fmt(new_val)
    elseif fmt then
        val_str = string.format(fmt, new_val)
    else
        val_str = string.format("%.2f", new_val)
    end
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + lbl_w + track_w + 6, y + 3), colors.text_primary, val_str)
    return new_val, y + row_h + 4
end

--- Format a position for display.
local function fmt_pos(pos)
    if not pos then return "not captured" end
    local px = (pos.x or (pos[1])) or 0
    local py = (pos.y or (pos[2])) or 0
    local pz = (pos.z or (pos[3])) or 0
    return string.format("(%.1f, %.1f, %.1f)", px, py, pz)
end

--- Get current player position as {x,y,z} table.
local function capture_pos()
    local ok, player = pcall(core.object_manager.get_local_player)
    if not ok or not player then return nil end
    local ok2, pos = pcall(player.get_position, player)
    if not ok2 or not pos then return nil end
    return { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
end

--- Capture row: label, coordinates, [CAPTURE] button. Returns (clicked, new_y).
local function capture_row(window, colors, x, y, cw, label, pos)
    local row_h = 18
    local btn_w = 65
    local btn_h = 14

    local lbl_str = label .. ":"
    local lbl_sz  = window:get_text_size(lbl_str)
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(x, y + 2),
        colors.text_secondary, lbl_str)
    local pos_str = fmt_pos(pos)
    local pos_x   = x + lbl_sz.x + 4
    local avail_w = cw - lbl_sz.x - btn_w - 12
    -- Truncate pos string if too wide
    window:render_text(enums.window_enums.font_id.FONT_SMALL, vec2.new(pos_x, y + 2),
        pos and colors.text_primary or colors.text_disabled, pos_str)

    local btn_x = x + cw - btn_w
    local btn_y = y + (row_h - btn_h) / 2
    local clicked = small_btn(window, colors, btn_x, btn_y, btn_w, btn_h, "[CAPTURE]",
        colors.secondary_accent or colors.primary_accent)
    return clicked, y + row_h + 3
end

-- ---------------------------------------------------------------------------
-- Per-tab state (upvalues, persists for session)
-- ---------------------------------------------------------------------------
local _view          = "list"   -- "list" | "editor"
local _edit_name     = nil      -- filename of profile being edited (nil = new)
local _draft         = nil      -- deep-copy of profile being edited
local _status_msg    = ""       -- feedback message shown at top of views
local _status_err    = false
local _pull_edit_idx = 1        -- which pull is shown in editor

-- Slider drag states (one per editable field)
local _drag = {}
local function get_drag(key)
    if not _drag[key] then _drag[key] = { active = false } end
    return _drag[key]
end

-- ---------------------------------------------------------------------------
-- List View
-- ---------------------------------------------------------------------------

local function render_list(window, colors, x, y, cw, bb)
    -- Status message
    if _status_msg ~= "" then
        local mc = _status_err and color.new(255, 100, 100, 255) or color.new(66, 188, 90, 255)
        y = txt(window, colors, x, y, _status_msg, mc) + 4
    end

    y = section(window, colors, x, y, "SAVED PROFILES", cw)

    local profiles = ProfileManager.list()
    local row_h    = 22
    local btn_w    = 52
    local gap      = 4

    if #profiles == 0 then
        y = txt(window, colors, x, y, "(no profiles saved — create one below)", colors.text_disabled)
        y = y + 8
    else
        for _, name in ipairs(profiles) do
            -- Profile name
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x, y + 4), colors.text_primary, name)

            -- [LOAD] button
            local bx = x + cw - btn_w * 2 - gap
            if small_btn(window, colors, bx, y + 3, btn_w, 16, "[LOAD]", colors.secondary_accent or colors.primary_accent) then
                ProfileManager.set_active_name(name)
                _status_msg = "Active set to: " .. name .. " — reload plugin to apply"
                _status_err = false
            end

            -- [EDIT] button
            bx = bx + btn_w + gap
            if small_btn(window, colors, bx, y + 3, btn_w, 16, "[EDIT]") then
                local p, err = ProfileManager.load(name)
                if p then
                    _draft       = ProfileManager.deep_copy(p)
                    _edit_name   = name
                    _pull_edit_idx = 1
                    _view        = "editor"
                    _status_msg  = ""
                else
                    _status_msg = "Load error: " .. tostring(err)
                    _status_err = true
                end
            end

            y = y + row_h
        end
    end

    y = y + 8

    -- Buttons: New from current profile / New blank
    local active_id = bb:get("duo.profile_id", nil)

    if small_btn(window, colors, x, y, 160, 18, "[NEW FROM ACTIVE PROFILE]") then
        -- Copy active profile to a new draft
        local active_name = ProfileManager.get_active_name()
        local base_name   = (active_name and active_name ~= "") and active_name or "new_profile"
        local new_name    = ProfileManager.copy_name(base_name)
        -- Try to load current active or fall back to blank
        local p = nil
        if active_name and active_name ~= "" then
            p = ProfileManager.load(active_name)
        end
        if not p then
            -- minimal blank profile
            p = {
                id              = new_name,
                dungeon_name    = "New Profile",
                instance_map_id = 329,
                outdoor_map_id  = 0,
                entrance_position  = nil,
                gate_position      = nil,
                exit_position      = nil,
                entrance_walk_path = {},
                exit_use_death     = true,
                gate_object_id     = 175368,  -- GO_SERVICE_ENTRANCE (confirmed cmangos source)
                gate_key_item_id   = 12382,
                pulls              = {},
                vendor_route       = {},
                timing             = {
                    pull_to_ib_mob_count        = 5,
                    ice_block_cancel_delay_ms   = 2500,
                    loot_settle_ms              = 2000,
                    between_pulls_ms            = 1500,
                },
                min_mana_pct_to_pull  = 0.60,
                min_hp_pct_to_pull    = 0.50,
                bags_full_threshold   = 4,
            }
        end
        p.id = new_name
        _draft       = ProfileManager.deep_copy(p)
        _edit_name   = new_name
        _pull_edit_idx = 1
        _view        = "editor"
        _status_msg  = ""
    end

    return y + 30
end

-- ---------------------------------------------------------------------------
-- Editor helpers
-- ---------------------------------------------------------------------------

--- Ensure _draft.pulls[idx] exists with defaults.
local function ensure_pull(idx)
    if not _draft.pulls then _draft.pulls = {} end
    if not _draft.pulls[idx] then
        _draft.pulls[idx] = {
            id                     = idx,
            pull_path              = {},
            aggro_radius           = 18.0,
            pull_tag_spell         = "frostbolt_r1",
            expected_mob_count_min = 4,
            expected_mob_count_max = 12,
            ice_block_position     = nil,
            blizzard_center        = nil,
            safe_position          = nil,
            puller_reposition      = nil,
            mob_ids                = {},
            mob_ids_avoid          = {},
            timing = {
                pull_to_ib_mob_count      = 5,
                ice_block_cancel_delay_ms = 2500,
                loot_settle_ms            = 2000,
            },
        }
    end
    return _draft.pulls[idx]
end

-- ---------------------------------------------------------------------------
-- Editor View
-- ---------------------------------------------------------------------------

local function render_editor(window, colors, x, y, cw)
    if not _draft then
        y = txt(window, colors, x, y, "No profile loaded.", colors.text_disabled)
        return y
    end

    -- ── Top bar: back / save / save-as / revert ──────────────────────────
    local bar_h = 20
    local bw    = 52
    local gap   = 6

    if small_btn(window, colors, x, y, 60, bar_h, "[< BACK]", colors.checkbox_inactive or colors.separator) then
        _view = "list"
        _status_msg = ""
    end

    local profile_label = "Editing: " .. (_edit_name or "new")
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(x + 68, y + 4), colors.text_secondary, profile_label)

    -- [SAVE] button
    local sx = x + cw - bw * 3 - gap * 2
    if small_btn(window, colors, sx, y, bw, bar_h, "[SAVE]", color.new(42, 130, 82, 200)) then
        local name = _edit_name or ProfileManager.copy_name("profile")
        if ProfileManager.save(name, _draft) then
            _edit_name  = name
            _status_msg = "Saved: " .. name
            _status_err = false
        else
            _status_msg = "Save failed!"
            _status_err = true
        end
    end

    -- [SAVE COPY]
    sx = sx + bw + gap
    if small_btn(window, colors, sx, y, bw, bar_h, "[COPY]") then
        local copy_name = ProfileManager.copy_name(_edit_name or "profile")
        if ProfileManager.save(copy_name, _draft) then
            _edit_name  = copy_name
            _status_msg = "Saved copy: " .. copy_name
            _status_err = false
        else
            _status_msg = "Copy save failed!"
            _status_err = true
        end
    end

    -- [REVERT]
    sx = sx + bw + gap
    if small_btn(window, colors, sx, y, bw, bar_h, "[REVERT]", color.new(155, 58, 58, 200)) then
        if _edit_name then
            local p, err = ProfileManager.load(_edit_name)
            if p then
                _draft      = ProfileManager.deep_copy(p)
                _status_msg = "Reverted to saved"
                _status_err = false
            else
                _status_msg = "Revert failed: " .. tostring(err)
                _status_err = true
            end
        else
            _status_msg = "Nothing to revert"
        end
    end

    y = y + bar_h + 6

    -- Status message
    if _status_msg ~= "" then
        local mc = _status_err and color.new(255, 100, 100, 255) or color.new(66, 188, 90, 255)
        y = txt(window, colors, x, y, _status_msg, mc) + 4
    end

    -- ── Meta ─────────────────────────────────────────────────────────────
    y = section(window, colors, x, y, "META", cw)
    y = kv(window, colors, x, y, "Profile Name", _edit_name or "(unsaved)")
    y = kv(window, colors, x, y, "ID",           _draft.id or "")
    y = kv(window, colors, x, y, "Dungeon",      _draft.dungeon_name or "")
    y = kv(window, colors, x, y, "Instance map", _draft.instance_map_id or 0)
    y = y + 4

    -- ── Thresholds & Timing ──────────────────────────────────────────────
    y = section(window, colors, x, y, "THRESHOLDS & TIMING", cw)

    if not _draft.timing then _draft.timing = {} end

    local function sl(label, field, min_v, max_v, fmt)
        local cur = _draft.timing[field] or (field == "pull_to_ib_mob_count" and 5 or
                    field == "ice_block_cancel_delay_ms" and 2500 or
                    field == "loot_settle_ms" and 2000 or 0)
        local nv, ny = slider_row(window, colors, x, y, cw, label, cur, min_v, max_v, fmt, get_drag(field))
        _draft.timing[field] = nv
        y = ny
    end

    do
        local v, ny = slider_row(window, colors, x, y, cw,
            "Min mana to pull",
            _draft.min_mana_pct_to_pull or 0.60, 0.30, 0.90,
            function(n) return string.format("%d%%", math.floor(n * 100)) end,
            get_drag("g_min_mana"))
        _draft.min_mana_pct_to_pull = v; y = ny
    end
    do
        local v, ny = slider_row(window, colors, x, y, cw,
            "Min HP to pull",
            _draft.min_hp_pct_to_pull or 0.50, 0.20, 0.80,
            function(n) return string.format("%d%%", math.floor(n * 100)) end,
            get_drag("g_min_hp"))
        _draft.min_hp_pct_to_pull = v; y = ny
    end
    do
        local v, ny = slider_row(window, colors, x, y, cw,
            "Bags full threshold (slots)",
            _draft.bags_full_threshold or 4, 1, 16,
            function(n) return string.format("%d", math.floor(n)) end,
            get_drag("g_bags"))
        _draft.bags_full_threshold = math.floor(v); y = ny
    end
    do
        local v, ny = slider_row(window, colors, x, y, cw,
            "Mobs before IB",
            _draft.timing.pull_to_ib_mob_count or 5, 2, 15,
            function(n) return string.format("%d mobs", math.floor(n)) end,
            get_drag("t_ib_count"))
        _draft.timing.pull_to_ib_mob_count = math.floor(v); y = ny
    end
    do
        local v, ny = slider_row(window, colors, x, y, cw,
            "IB cancel delay",
            _draft.timing.ice_block_cancel_delay_ms or 2500, 500, 5000,
            function(n) return string.format("%dms", math.floor(n)) end,
            get_drag("t_ib_delay"))
        _draft.timing.ice_block_cancel_delay_ms = math.floor(v); y = ny
    end
    do
        local v, ny = slider_row(window, colors, x, y, cw,
            "Loot settle delay",
            _draft.timing.loot_settle_ms or 2000, 500, 4000,
            function(n) return string.format("%dms", math.floor(n)) end,
            get_drag("t_loot"))
        _draft.timing.loot_settle_ms = math.floor(v); y = ny
    end
    y = y + 4

    -- ── Global Positions ─────────────────────────────────────────────────
    y = section(window, colors, x, y, "GLOBAL POSITIONS", cw)
    local global_pos_defs = {
        { label = "Entrance",       key = "entrance_position" },
        { label = "Gate",           key = "gate_position"     },
        { label = "Exit (death)",   key = "exit_position"     },
    }
    for _, def in ipairs(global_pos_defs) do
        local clicked, ny = capture_row(window, colors, x, y, cw, def.label, _draft[def.key])
        if clicked then
            local pos = capture_pos()
            if pos then
                _draft[def.key] = pos
                _status_msg = def.label .. " captured"
                _status_err = false
            end
        end
        y = ny
    end
    y = y + 4

    -- ── Inside Walk Path ──────────────────────────────────────────────────
    -- Waypoints from the outdoor gate portal INTO the instance interior.
    -- Both mages follow this after the enter_instance barrier releases.
    y = section(window, colors, x, y, "INSIDE WALK PATH (gate → instance entry)", cw)
    local iw_count = _draft.inside_walk_path and #_draft.inside_walk_path or 0
    y = txt(window, colors, x, y + 2,
        string.format("Waypoints: %d  (lead from gate portal into dungeon)", iw_count),
        colors.text_secondary)
    if small_btn(window, colors, x, y, 100, 16, "[ADD WP]", color.new(42, 130, 82, 200)) then
        local pos = capture_pos()
        if pos then
            if not _draft.inside_walk_path then _draft.inside_walk_path = {} end
            table.insert(_draft.inside_walk_path, pos)
            _status_msg = "Inside walk WP " .. #_draft.inside_walk_path .. " added"
        end
    end
    if iw_count > 0 then
        if small_btn(window, colors, x + 106, y, 110, 16, "[REMOVE LAST WP]", color.new(155, 58, 58, 200)) then
            table.remove(_draft.inside_walk_path)
            _status_msg = "Removed last inside walk waypoint"
        end
    end
    y = y + 22

    -- ── Pull Editor ───────────────────────────────────────────────────────
    if not _draft.pulls then _draft.pulls = {} end
    local pull_count = math.max(1, #_draft.pulls)

    -- Ensure at least one pull slot
    ensure_pull(1)
    pull_count = #_draft.pulls

    -- Pull selector
    y = section(window, colors, x, y,
        string.format("PULL EDITOR  ( %d / %d )", _pull_edit_idx, pull_count), cw)

    local nav_h  = 18
    local nav_bw = 24
    if small_btn(window, colors, x, y, nav_bw, nav_h, " < ") then
        _pull_edit_idx = math.max(1, _pull_edit_idx - 1)
    end
    if small_btn(window, colors, x + nav_bw + 4, y, nav_bw, nav_h, " > ") then
        _pull_edit_idx = _pull_edit_idx + 1
        ensure_pull(_pull_edit_idx)
    end
    -- [ADD PULL] and [REMOVE PULL] buttons
    if small_btn(window, colors, x + nav_bw * 2 + 12, y, 80, nav_h, "[ADD PULL]", color.new(42, 130, 82, 200)) then
        local new_idx = #_draft.pulls + 1
        ensure_pull(new_idx)
        _pull_edit_idx = new_idx
        _status_msg = "Added pull " .. new_idx
    end
    if #_draft.pulls > 1 then
        if small_btn(window, colors, x + nav_bw * 2 + 98, y, 90, nav_h, "[REMOVE PULL]", color.new(155, 58, 58, 200)) then
            table.remove(_draft.pulls, _pull_edit_idx)
            _pull_edit_idx = math.max(1, _pull_edit_idx - 1)
            _status_msg = "Removed pull"
        end
    end
    y = y + nav_h + 6

    local pull = ensure_pull(_pull_edit_idx)

    -- Positions for this pull
    local pull_pos_defs = {
        { label = "Blizzard center",   key = "blizzard_center"    },
        { label = "IB position",       key = "ice_block_position" },
        { label = "Safe position",     key = "safe_position"      },
        { label = "Puller reposition", key = "puller_reposition"  },
    }
    for _, def in ipairs(pull_pos_defs) do
        local clicked, ny = capture_row(window, colors, x, y, cw, def.label, pull[def.key])
        if clicked then
            local pos = capture_pos()
            if pos then
                pull[def.key] = pos
                _status_msg = "Pull " .. _pull_edit_idx .. ": " .. def.label .. " captured"
            end
        end
        y = ny
    end

    -- Pull path waypoints
    local path_count = pull.pull_path and #pull.pull_path or 0
    y = txt(window, colors, x, y + 2,
        string.format("Pull path: %d waypoints", path_count), colors.text_secondary)
    if small_btn(window, colors, x, y, 100, 16, "[ADD WAYPOINT]", color.new(42, 130, 82, 200)) then
        local pos = capture_pos()
        if pos then
            if not pull.pull_path then pull.pull_path = {} end
            table.insert(pull.pull_path, pos)
            _status_msg = "Added waypoint " .. #pull.pull_path
        end
    end
    if path_count > 0 and small_btn(window, colors, x + 106, y, 110, 16, "[REMOVE LAST WP]", color.new(155, 58, 58, 200)) then
        table.remove(pull.pull_path)
        _status_msg = "Removed last waypoint"
    end
    y = y + 22

    -- Per-pull timing sliders
    if not pull.timing then pull.timing = {} end
    do
        local pkey = "p" .. _pull_edit_idx .. "_ib_count"
        local v, ny = slider_row(window, colors, x, y, cw,
            "  Mobs before IB (this pull)",
            pull.timing.pull_to_ib_mob_count or _draft.timing.pull_to_ib_mob_count or 5,
            2, 15,
            function(n) return string.format("%d mobs", math.floor(n)) end,
            get_drag(pkey))
        pull.timing.pull_to_ib_mob_count = math.floor(v); y = ny
    end
    do
        local pkey = "p" .. _pull_edit_idx .. "_aggro"
        local v, ny = slider_row(window, colors, x, y, cw,
            "  Aggro radius (yards)",
            pull.aggro_radius or 18.0, 5, 40,
            function(n) return string.format("%.0fyd", n) end,
            get_drag(pkey))
        pull.aggro_radius = v; y = ny
    end
    y = y + 4

    -- ── Vendor Route ─────────────────────────────────────────────────────
    y = section(window, colors, x, y, "VENDOR ROUTE", cw)
    if not _draft.vendor_route then _draft.vendor_route = {} end
    local vendor_pos_defs = {
        { label = "Vendor position",       key = "vendor_position"         },
        { label = "Flight master position", key = "flight_master_position" },
        { label = "Flight dest position",  key = "flight_dest_position"    },
        { label = "HS dest position",      key = "hearthstone_dest_position"},
    }
    for _, def in ipairs(vendor_pos_defs) do
        local clicked, ny = capture_row(window, colors, x, y, cw, def.label, _draft.vendor_route[def.key])
        if clicked then
            local pos = capture_pos()
            if pos then
                _draft.vendor_route[def.key] = pos
                _status_msg = def.label .. " captured"
            end
        end
        y = ny
    end
    -- Walkback path
    local wb_count = _draft.vendor_route.walkback_path and #_draft.vendor_route.walkback_path or 0
    y = txt(window, colors, x, y + 2,
        string.format("Walkback path: %d waypoints", wb_count), colors.text_secondary)
    if small_btn(window, colors, x, y, 110, 16, "[ADD WB WAYPOINT]", color.new(42, 130, 82, 200)) then
        local pos = capture_pos()
        if pos then
            if not _draft.vendor_route.walkback_path then _draft.vendor_route.walkback_path = {} end
            table.insert(_draft.vendor_route.walkback_path, pos)
            _status_msg = "Walkback waypoint " .. #_draft.vendor_route.walkback_path .. " added"
        end
    end
    if wb_count > 0 then
        if small_btn(window, colors, x + 116, y, 110, 16, "[REMOVE LAST WB]", color.new(155, 58, 58, 200)) then
            table.remove(_draft.vendor_route.walkback_path)
            _status_msg = "Removed last walkback waypoint"
        end
    end
    y = y + 22

    return y + 4
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

---@param ui table SentinelUI instance
---@param bb table Blackboard
function ProfileTab.register(ui, bb)
    ProfileManager.init()

    ui:add_tab({ id = "profile", label = "Profile" }, function(t)
        t:custom_render({ render_fn = function(self, y)
            local window = self.window
            local colors = self.colors
            local x  = LAYOUT.padding_side
            local cw = window:get_size().x - 2 * LAYOUT.padding_side

            if _view == "list" then
                return render_list(window, colors, x, y, cw, bb)
            else
                return render_editor(window, colors, x, y, cw)
            end
        end })
    end)
end

return ProfileTab
