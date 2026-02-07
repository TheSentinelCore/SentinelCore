

-- Syntax / IntelliSense helper for: common/utility/control_panel_helper
-- Usage:
-- ---@type control_panel_helper
-- local cph = require("common/utility/control_panel_helper")
-- cph: -- IntelliSense
-- Warning: Access with ":", not "."

---@class control_panel_toggle
---@field name string          -- label shown in the Control Panel
---@field keybind keybind      -- keybind element
---@field id string|nil        -- optional unique id (used by insert_key_checkbox_)

---@class control_panel_combo
---@field name string          -- label shown in the Control Panel
---@field combobox combobox    -- combobox element
---@field preview_value any    -- text/value preview under the label
---@field max_items integer    -- number of items to preview

--- Control Panel Helper
--- Utilities to push menu keybinds/combos to the in-game Control Panel with optional drag-and-drop.
--- Tips:
---  • Return an empty table when your plugin/rotation is disabled so users don’t see clutter.
---  • Prefer `insert_toggle_` / `insert_combo_` when you don’t want to allocate a table elsewhere.
---  • Use `only_drag_drop=true` if you want an element to appear ONLY when the user drags it in.
---  • For “momentary hold” visuals, use `insert_key_checkbox_` and pass `is_hold=true`.
---@class control_panel_helper
---@field public on_update fun(self: control_panel_helper, menu: table): nil
---@field public insert_toggle fun(self: control_panel_helper, control_panel_table: table, toggle_table: control_panel_toggle, only_drag_drop?: boolean): boolean
---@field public insert_toggle_ fun(self: control_panel_helper, control_panel_table: table, display_name: string, keybind_element: keybind|userdata, only_drag_drop?: boolean, no_drag_and_drop?: boolean): boolean
---@field public insert_key_checkbox_ fun(self: control_panel_helper, control_panel_table: table, display_name: string, keybind_state: boolean, keybind_key_code: integer, is_hold: boolean, unique_id: string): boolean
---@field public insert_combo fun(self: control_panel_helper, control_panel_table: table, combo_table: control_panel_combo, increase_index_key: keybind|userdata, only_drag_drop?: boolean): boolean
---@field public insert_combo_ fun(self: control_panel_helper, control_panel_table: table, display_name: string, combobox_element: combobox|userdata, preview_value: any, max_items: integer, increase_index_key: keybind|userdata, only_drag_drop?: boolean): boolean

-- on_update(menu)
--   Call once per frame from your UI update path to process drag-and-drop labels.
--   Any keybind/combobox whose label matches the “current control panel element label”
--   will have its “showing on control panel” flag set internally.

-- insert_toggle(control_panel_table, toggle_table[, only_drag_drop])
--   Push a toggle (keybind) to the Control Panel.
--   • If only_drag_drop=false and the keybind has a real key (key_code ~= 7), it’s inserted directly.
--   • If only_drag_drop=true, it is added only when user dragged its label into the panel.
--   Returns true when inserted (or handled), false when a duplicate was detected.

-- insert_toggle_(control_panel_table, display_name, keybind_element[, only_drag_drop, no_drag_and_drop])
--   Convenience version that builds the toggle table for you.
--   • If no_drag_and_drop ~= true, the keybind becomes draggable.

-- insert_key_checkbox_(control_panel_table, display_name, keybind_state, keybind_key_code, is_hold, unique_id)
--   “Ephemeral” checkbox UI bound to a keybind code (e.g., per-ability on/off).
--   • Maintains a persistent keybind instance internally, indexed by unique_id + key_code + name.
--   • If is_hold=true, forces state visually while the key is held (or when “Always” mode).
--   • Returns boolean: the **current toggle state** to apply back to your logic/UI.

-- insert_combo(control_panel_table, combo_table, increase_index_key[, only_drag_drop])
-- insert_combo_(control_panel_table, display_name, combobox_element, preview_value, max_items, increase_index_key[, only_drag_drop])
--   Push a combobox control with an optional “increase index” key shortcut.
--   • If only_drag_drop=false and increase_index_key has a real key (key_code ~= 7), it’s inserted directly.
--   • Otherwise requires user drag-and-drop.
--   Returns true on insert (or handled), false if duplicate.

--======================================================
-- Quick patterns & tips (short, copy-paste friendly)
--======================================================

-- TIP 1: Return early when disabled to avoid panel bloat
-- local control_panel_helper = require("common/utility/control_panel_helper")
-- local function on_control_panel_render()
--     if not menu.main_boolean:get_state() then
--         return {}  -- keep Control Panel clean when disabled
--     end
--     local cp = {}
--     -- add elements below...
--     return cp
-- end

-- TIP 2: Insert a basic toggle (pre-built table form)
-- local cp = {}
-- control_panel_helper:insert_toggle(cp, {
--     name = "[" .. plugin_data.name .. "] Enable (" .. key_helper:get_key_name(menu.enable_toggle:get_key_code()) .. ") ",
--     keybind = menu.enable_toggle
-- })

-- TIP 3: Insert a toggle (convenience form)
-- control_panel_helper:insert_toggle_(cp,
--     "[" .. plugin_data.name .. "] Cooldowns (" .. key_helper:get_key_name(menu.cooldowns_toggle:get_key_code()) .. ") ",
--     menu.cooldowns_toggle,
--     false -- only_drag_drop: show even without drag
-- )

-- TIP 4: Combo with “increase index” key
-- control_panel_helper:insert_combo(cp, {
--     name = "[" .. plugin_data.name .. "] Combat Mode (" .. key_helper:get_key_name(menu.switch_combat_mode:get_key_code()) .. ") ",
--     combobox = menu.combat_mode,
--     preview_value = menu.combat_mode_options[menu.combat_mode:get()],
--     max_items = #menu.combat_mode_options
-- }, menu.switch_combat_mode)

-- TIP 5: Drag-and-drop only element (user must drag label into the panel)
-- control_panel_helper:insert_toggle(cp, {
--     name = "[MyPlugin] Experimental Toggle ",
--     keybind = menu.experimental_toggle
-- }, true)

-- TIP 6: Ephemeral “hold” checkbox (reflects key state each frame)
-- local hold_name = "[" .. plugin_data.name .. "] Eye of Tyr (" .. key_helper:get_key_name(kcode) .. ") "
-- local key_state = control_panel_helper:insert_key_checkbox_(cp, hold_name,
--     spells.eye_of_tyr.menu_elements.advanced_settings.semi_manual_keybind:get_keybind_state(),
--     kcode,  -- integer key code
--     true,   -- is_hold
--     "prot_pala_eye_of_tyr_control_panel_element"
-- )
-- spells.eye_of_tyr.menu_elements.advanced_settings.semi_manual_keybind:set_toggle_state(key_state)

-- TIP 7: Switch between SIMC/Manual layouts with minimal clutter
-- if menu_simc.fight_logic:get() == menu_simc.fight_logic_enum.SIMC then
--     -- lean SIMC panel
--     control_panel_helper:insert_toggle_(cp, "[" .. plugin_data.name .. "] Burst (" .. key_helper:get_key_name(menu_simc.burst_toggle:get_key_code()) .. ") ", menu_simc.burst_toggle)
-- else
--     -- manual panel
--     control_panel_helper:insert_toggle_(cp, "[" .. plugin_data.name .. "] Cooldowns (" .. key_helper:get_key_name(menu.cooldowns_toggle:get_key_code()) .. ") ", menu.cooldowns_toggle)
-- end

-- TIP 8: Logging without commas (use concatenation)
-- core.log("Control panel added elements: " .. tostring(#cp))

-- TIP 9: Avoid duplicates
-- • Labels are used to detect duplicates. Keep names stable and unique per function.
-- • For checkboxes, provide a stable unique_id (e.g., "prot_pala_consecration_control_panel_element").

-- TIP 10: Performance
-- • Build a fresh `cp` table each frame; helper functions already guard against duplicates.
-- • `on_update(menu)` should be called once per frame to support drag-and-drop label pickup.

---@type control_panel_helper
local tbl
return tbl
