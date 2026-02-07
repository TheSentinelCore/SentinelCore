---@diagnostic disable: duplicate-doc-field
---@meta

---@alias color_helper color

-- =============================================================================
-- OPTION TYPES
-- =============================================================================

---@class window_checkbox_options
---@field border_padding? number
---@field checkbox_size? vec2
---@field line_spacing? number
---@field text_color? color
---@field text_hover_color? color
---@field text_active_color? color
---@field box_background? color
---@field box_background_active? color
---@field box_background_hover? color
---@field box_border? color
---@field box_border_active? color
---@field box_border_hover? color
---@field box_border_thickness? number
---@field box_rounding? number
---@field rounding_increase? number
---@field hover_border_bonus? number
---@field active_border_bonus? number
---@field hover_box_expand? number
---@field active_box_expand? number
---@field check_inset? number
---@field inset_animation_factor? number
---@field tick_thickness? number
---@field check_color? color
---@field check_fill? color
---@field check_fill_idle? color
---@field hover_outline? color
---@field hover_outline_idle? color
---@field font_small_id? integer
---@field font_default_id? integer
---@field animation_speed? number
---@field hover_animation_speed? number
---@field click_animation_speed? number
---@field on_changed? fun(state: boolean)

---@class window_slider_options
---@field border_padding? number
---@field margin? vec2
---@field font_label_id? integer
---@field font_value_id? integer
---@field fill_color? color
---@field fill_hover_color? color
---@field fill_active_color? color
---@field outline_color? color
---@field outline_hover_color? color
---@field outline_active_color? color
---@field label_color? color
---@field value_color? color
---@field animation_speed? number

---@class window_button_options
---@field border_padding? number
---@field margin? vec2
---@field font_id? integer
---@field border_radius? number
---@field border_thickness? number
---@field text_color? color
---@field text_hover_color? color
---@field text_active_color? color
---@field fill_color? color
---@field fill_hover_color? color
---@field fill_active_color? color
---@field fill_shadow_color? color
---@field outline_color? color
---@field pulse_color? color
---@field pulse_speed? number
---@field pulse_max_radius? number
---@field pulse_thickness? number
---@field pulse_segments? integer
---@field pulse_allow_bleed? boolean
---@field animation_speed? number
---@field hover_ease_speed? number
---@field press_ease_speed? number

---@class window_keybind_options
---@field border_padding? number
---@field margin? vec2
---@field border_radius? number
---@field font_label_id? integer
---@field font_value_id? integer
---@field fill_color? color
---@field fill_hover_color? color
---@field fill_active_color? color
---@field outline_color? color
---@field outline_hover_color? color
---@field outline_active_color? color
---@field label_color? color
---@field value_color? color
---@field animation_speed? number

---@class window_tree_options
---@field border_padding? number
---@field margin? vec2
---@field font_label_id? integer
---@field font_value_id? integer
---@field label_color? color
---@field label_color_hover? color
---@field label_color_selected? color
---@field arrow_color? color
---@field row_hover_color? color
---@field row_selected_color? color
---@field selected_grad_left? color
---@field selected_grad_right? color
---@field left_accent_color? color
---@field animation_speed? number
---@field hover_animation_speed? number
---@field main_animation_speed? number
---@field row_height? number
---@field indent_step? number
---@field max_depth? integer
---@field arrow_thickness? number
---@field main_brightness_scale? number
---@field sub_brightness_scale? number
---@field check_box_color? color
---@field check_box_outline? color
---@field check_tick_color? color
---@field check_box_size? number
---@field icon_tint? color
---@field id_prefix? string

---@class window_key_checkbox_options
---@field border_color? color

---@class window_text_input_options
---@field height? number
---@field pad? number
---@field font_id? integer
---@field placeholder? string
---@field numeric_only? boolean
---@field max_len? integer
---@field colors? table<string, color>
---@field multiline? boolean
---@field line_gap? number
---@field label? string
---@field initial? string
---@field cooldown? number
---@field cooldown_fast? number
---@field cooldown_min? number
---@field repeat_ramp? number
---@field on_change? fun(text: string)
---@field save_to_settings? boolean

-- =============================================================================
-- MENU ELEMENT INSTANCES
-- =============================================================================

---@class menu_tree_node
---@field id string The unique identifier for this tree node
---@field is_tree boolean Always true for tree nodes
---Renders the tree node with a header label and executes callback when open
---@field render fun(self: menu_tree_node, header: string, callback?: fun()): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_tree_node, window: window, header: string, callback?: fun()): nil
---Returns whether this tree node is currently expanded
---@field is_open fun(self: menu_tree_node): boolean
---Manually set the open/closed state
---@field set_open_state fun(self: menu_tree_node, state: boolean): nil
---Get the bounding box of the tree widget
---@field get_widget_bounds fun(self: menu_tree_node): { min: vec2, max: vec2 }
---Attach a texture icon to this tree node
---@field attach_texture fun(self: menu_tree_node, texture_id: integer, width: number, height: number, tint: color): nil
---Generic getter
---@field get fun(self: menu_tree_node): any
---Generic setter
---@field set fun(self: menu_tree_node, value: any): nil
---@field _window_side "left"|"right"|nil

---@class menu_checkbox
---@field id string The unique identifier
---Renders the checkbox with a label
---@field render fun(self: menu_checkbox, label: string): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_checkbox, window: window, label: string): any
---Returns the current checked state
---@field get fun(self: menu_checkbox): boolean
---Sets the checked state
---@field set fun(self: menu_checkbox, state: boolean): nil
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_checkbox, window: window): menu_checkbox
---@field _window_side "left"|"right"|nil

---@class menu_slider
---@field id string The unique identifier
---Renders the slider with a label
---@field render fun(self: menu_slider, label: string, step?: number): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_slider, window: window, label: string, step?: number): any
---Returns the current slider value
---@field get fun(self: menu_slider): number
---Sets the slider value
---@field set fun(self: menu_slider, value: number): nil
---Converts this slider to float mode. Returns self for chaining.
---@field as_float fun(self: menu_slider): menu_slider
---Converts this slider to integer mode. Returns self for chaining.
---@field as_int fun(self: menu_slider): menu_slider
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_slider, window: window): menu_slider
---@field _window_side "left"|"right"|nil
---@field is_float boolean Whether this slider uses float values
---@field min_value number Minimum slider value
---@field max_value number Maximum slider value
---@field default_value number Default slider value

---@class menu_button
---Renders the button with a label. Returns true when clicked.
---@field render fun(self: menu_button, label: string): boolean
---Renders directly to a specific window
---@field render_to_window fun(self: menu_button, window: window, label: string): boolean
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_button, window: window): menu_button
---@field _window_side "left"|"right"|nil

---@class menu_keybind
---@field id string The unique identifier
---Renders the keybind selector with a label
---@field render fun(self: menu_keybind, label: string): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_keybind, window: window, label: string): any
---Returns the currently bound key code
---@field get fun(self: menu_keybind): integer
---@field get_key_code fun(self: menu_keybind): integer
---Sets the bound key code
---@field set fun(self: menu_keybind, keycode: integer): nil
---@field set_key fun(self: menu_keybind, keycode: integer): nil
---Returns whether the key is currently pressed/active
---@field is_active fun(self: menu_keybind): boolean
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_keybind, window: window): menu_keybind
---@field _window_side "left"|"right"|nil

---@class menu_key_checkbox
---@field id string The unique identifier
---Renders the key checkbox (checkbox + keybind + dropdown combo) with a label
---@field render fun(self: menu_key_checkbox, label: string): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_key_checkbox, window: window, label: string): any
---Returns the keybind's active state
---@field get fun(self: menu_key_checkbox): boolean
---@field is_active fun(self: menu_key_checkbox): boolean
---Returns the bound key code
---@field get_key_code fun(self: menu_key_checkbox): integer
---Sets the bound key code
---@field set_key fun(self: menu_key_checkbox, keycode: integer): nil
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_key_checkbox, window: window): menu_key_checkbox
---@field keybind menu_keybind The internal keybind element
---@field dropdown menu_dropdown The internal dropdown element (Toggle/Hold)
---@field checkbox menu_checkbox The internal checkbox element (show in binds)
---@field _window_side "left"|"right"|nil

---@class menu_dropdown
---@field id string The unique identifier
---Renders the dropdown with a label
---@field render fun(self: menu_dropdown, label: string, options: string[]): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_dropdown, window: window, label: string): any
---Returns the currently selected index (1-based)
---@field get fun(self: menu_dropdown): integer
---Sets the selected index
---@field set fun(self: menu_dropdown, index: integer): nil
---Sets the list of items
---@field set_items fun(self: menu_dropdown, items: string[]): nil
---Register a callback for when selection changes
---@field on_changed fun(self: menu_dropdown, callback: fun()): nil
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_dropdown, window: window): menu_dropdown
---@field _window_side "left"|"right"|nil

---@class menu_multi_dropdown
---@field id string The unique identifier
---Renders the multi-select dropdown with a label
---@field render fun(self: menu_multi_dropdown, label: string): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_multi_dropdown, window: window, label: string): any
---Returns table of selected indices
---@field get fun(self: menu_multi_dropdown): integer[]
---Sets the selected indices
---@field set fun(self: menu_multi_dropdown, indices: integer[]): nil
---Sets the list of items
---@field set_items fun(self: menu_multi_dropdown, items: string[]): nil
---Returns all items (labels)
---@field get_items fun(self: menu_multi_dropdown): string[]
---Returns enabled item labels
---@field get_enabled_items fun(self: menu_multi_dropdown): string[]
---Returns disabled item labels
---@field get_disabled_items fun(self: menu_multi_dropdown): string[]
---Returns enabled item indices (1-based)
---@field get_enabled_indices fun(self: menu_multi_dropdown): integer[]
---Returns disabled item indices (1-based)
---@field get_disabled_indices fun(self: menu_multi_dropdown): integer[]
---Enables all items
---@field select_all fun(self: menu_multi_dropdown): nil
---Disables all items
---@field clear_all fun(self: menu_multi_dropdown): nil
---Opens the dropdown
---@field open fun(self: menu_multi_dropdown): nil
---Closes the dropdown
---@field close fun(self: menu_multi_dropdown): nil
---Toggles the dropdown open/closed state
---@field toggle fun(self: menu_multi_dropdown): nil
---Gets the currently selected item label
---@field get_selected_item fun(self: menu_multi_dropdown): string|nil
---Gets the total item count
---@field get_item_count fun(self: menu_multi_dropdown): integer
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_multi_dropdown, window: window): menu_multi_dropdown
---@field _window_side "left"|"right"|nil

---@class menu_colorpicker
---@field id string The unique identifier
---Renders the color picker with a label
---@field render fun(self: menu_colorpicker, label: string): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_colorpicker, window: window, label: string): any
---Returns the current color
---@field get fun(self: menu_colorpicker): color
---Sets the color
---@field set fun(self: menu_colorpicker, c: color): nil
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_colorpicker, window: window): menu_colorpicker
---@field _window_side "left"|"right"|nil

---@class menu_dropdown_reorderable
---@field id string The unique identifier
---Renders the reorderable dropdown with a label
---@field render fun(self: menu_dropdown_reorderable, label: string): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_dropdown_reorderable, window: window, label: string): any
---Returns the current order as array of values/indices
---@field get fun(self: menu_dropdown_reorderable): any[]
---Sets the order
---@field set fun(self: menu_dropdown_reorderable, order: any[]): nil
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_dropdown_reorderable, window: window): menu_dropdown_reorderable
---@field _window_side "left"|"right"|nil

---@class menu_text_input
---@field id string The unique identifier
---Renders the text input with a label
---@field render fun(self: menu_text_input, label: string): nil
---Renders directly to a specific window
---@field render_to_window fun(self: menu_text_input, window: window, label: string): any
---Returns the current text content
---@field get_text fun(self: menu_text_input): string
---Sets the text content
---@field set_text fun(self: menu_text_input, text: string): nil
---For numeric inputs, get the number value
---@field get_number fun(self: menu_text_input): number
---For numeric inputs, set the number value
---@field set_number fun(self: menu_text_input, value: number): nil
---Returns whether the input is currently focused
---@field is_focused fun(self: menu_text_input): boolean
---Binds this element to render on a specific window
---@field bind_window fun(self: menu_text_input, window: window): menu_text_input
---@field _window_side "left"|"right"|nil

-- =============================================================================
-- SEARCH RESULT TYPE
-- =============================================================================

---@class menu_search_result
---@field id string|number The element's unique identifier
---@field label string The element's display label
---@field parent_group table|nil The parent tree group (nil if root level)
---@field path_labels string[] Array of tree labels from root to parent
---@field rec table Internal record reference

-- =============================================================================
-- BOUND MENU FACTORY (returned by menu.bind)
-- =============================================================================

---@class menu_bound_factory
---@field window window The bound window
---Creates a checkbox bound to this window
---@field checkbox fun(id: string, default_state?: boolean, opts?: window_checkbox_options): menu_checkbox
---Creates a slider bound to this window
---@field slider fun(min_value: number, max_value: number, default_value: number, id: string, opts?: window_slider_options): menu_slider
---Creates a button bound to this window
---@field button fun(opts?: window_button_options): menu_button
---Creates a keybind bound to this window
---@field keybind fun(is_toggle: boolean, default_state: boolean, default_key_code: integer, id: string, opts?: window_keybind_options): menu_keybind
---Creates a dropdown bound to this window
---@field dropdown fun(default_index: integer, id: string): menu_dropdown
---Creates a tree node bound to this window
---@field tree fun(id: string, opts?: window_tree_options): menu_tree_node
---Creates a key checkbox bound to this window
---@field key_checkbox fun(id: string, default_is_toggle: boolean, default_show_in_binds: boolean, default_toggle_state: boolean, default_key_code: integer, opts?: window_key_checkbox_options): menu_key_checkbox
---Creates a multi dropdown bound to this window
---@field multi_dropdown fun(id: string): menu_multi_dropdown
---Creates a colorpicker bound to this window
---@field colorpicker fun(default_color: color, id: string): menu_colorpicker
---Creates a reorderable dropdown bound to this window
---@field dropdown_reorderable fun(id: string, items: string[]): menu_dropdown_reorderable
---Creates a text input bound to this window
---@field text_input fun(id: string, opts?: window_text_input_options): menu_text_input

-- =============================================================================
-- MAIN MENU API MODULE
-- =============================================================================

---@class menu_api
---@field _NAME string Module name
---@field _VERSION string Module version
---@field checkbox table Raw checkbox module
---@field slider table Raw slider module
---@field button table Raw button module
---@field keybind table Raw keybind module
---@field tree table Raw tree module
---@field key_checkbox table Raw key_checkbox module
---@field dropdown table Raw dropdown module
---@field multi_dropdown table Raw multi_dropdown module
---@field colorpicker table Raw colorpicker module
---@field dropdown_reorderable table Raw dropdown_reorderable module
---@field text_input table Raw text_input module
---@field combobox table Alias for dropdown
---@field i18n menu_i18n Internationalization subsystem
---@field _highlight_id string|nil Currently highlighted element ID
---@field _highlight_until number Timestamp when highlight ends
---@field _highlight_secs number Duration of highlight effect (default 1.5)
local menu_api = {}

-- =============================================================================
-- CONSTRUCTOR FUNCTIONS
-- =============================================================================

---Creates a new checkbox element
---@param id string Unique identifier for persistence
---@param default_state? boolean Initial checked state (default false)
---@param opts? window_checkbox_options Optional styling/behavior options
---@return menu_checkbox
function menu_api.new_checkbox(id, default_state, opts) end

---Creates a new slider element
---@param min_value number Minimum slider value
---@param max_value number Maximum slider value
---@param default_value number Initial slider value
---@param id string Unique identifier for persistence
---@param opts? window_slider_options Optional styling/behavior options
---@return menu_slider
function menu_api.new_slider(min_value, max_value, default_value, id, opts) end

---@return nil
function menu_api.enable_menu() end

---@return nil
function menu_api.disable_menu() end

---Creates a new button element
---@param opts? window_button_options Optional styling/behavior options
---@return menu_button
function menu_api.new_button(opts) end

---Creates a new keybind element
---@param is_toggle boolean Whether the keybind acts as a toggle (true) or hold (false)
---@param default_state boolean Default toggle state (if is_toggle is true)
---@param default_key_code integer Default key code
---@param id string Unique identifier for persistence
---@param opts? window_keybind_options Optional styling/behavior options
---@return menu_keybind
function menu_api.new_keybind(is_toggle, default_state, default_key_code, id, opts) end

---Creates a new dropdown element
---@param default_index integer Default selected index (1-based)
---@param id string Unique identifier for persistence
---@return menu_dropdown
function menu_api.new_dropdown(default_index, id) end

---Renders a header text element (no constructor needed)
---@param text string The header text to display
---@param text_color? color The text color (default white)
---@param opts? { font_id?: integer, padding_top?: number, padding_bottom?: number, padding_left?: number }
function menu_api.header(text, text_color, opts) end

---Renders a horizontal separator line (no constructor needed)
---@param opts? { color?: color, thickness?: number, padding_top?: number, padding_bottom?: number, margin_left?: number, margin_right?: number }
function menu_api.separator(opts) end

---Creates a new tree node element
---@param id string Unique identifier for persistence
---@param opts? window_tree_options Optional styling/behavior options
---@return menu_tree_node
function menu_api.new_tree(id, opts) end

---Creates a new key checkbox element (checkbox + keybind + toggle/hold dropdown combo)
---@param id string Unique identifier for persistence
---@param default_is_toggle boolean Whether keybind defaults to toggle mode
---@param default_show_in_binds boolean Whether to show in keybinds list by default
---@param default_toggle_state boolean Default toggle state
---@param default_key_code integer Default key code
---@param opts? window_key_checkbox_options Optional styling/behavior options
---@return menu_key_checkbox
function menu_api.new_key_checkbox(id, default_is_toggle, default_show_in_binds, default_toggle_state, default_key_code, opts) end

---Creates a new multi-select dropdown element
---@param id string Unique identifier for persistence
---@return menu_multi_dropdown
function menu_api.new_multi_dropdown(id) end

---Creates a new color picker element
---@param default_color color Default color value
---@param id string Unique identifier for persistence
---@return menu_colorpicker
function menu_api.new_colorpicker(default_color, id) end

---Creates a new reorderable dropdown element
---@param id string Unique identifier for persistence
---@param items string[] Initial list of items
---@return menu_dropdown_reorderable
function menu_api.new_dropdown_reorderable(id, items) end

---Creates a new text input element
---@param id string Unique identifier for persistence
---@param opts? window_text_input_options Optional styling/behavior options
---@return menu_text_input
function menu_api.new_text_input(id, opts) end

---Alias for new_dropdown
---@param default_index integer Default selected index (1-based)
---@param id string Unique identifier for persistence
---@return menu_dropdown
function menu_api.new_combobox(default_index, id) end

-- =============================================================================
-- FRAME LIFECYCLE
-- =============================================================================

---Clears all element tables. MUST be called at the start of each frame
---for elements to be properly ephemeral (only rendered when :render() is called).
function menu_api.begin_frame() end

---Returns the current tree roots and root-level elements for iteration
---@return table tree_roots Array of tree group objects
---@return table root_others Array of root-level non-tree elements
function menu_api.iter_layout() end

-- =============================================================================
-- WINDOW MANAGEMENT
-- =============================================================================

---Gets the currently set default window
---@return window|nil
function menu_api._get_window() end

---Sets the default window for elements that don't have an explicit binding
---@param win window The window to use as default
function menu_api.set_default_window(win) end

---Binds an element to a specific window
---@generic T
---@param obj T The menu element
---@param win window The window to bind to
---@return T obj The same element (for chaining)
function menu_api.bind_window(obj, win) end

---Creates a bound factory that automatically binds all created elements to the given window
---@param window window The window to bind all elements to
---@return menu_bound_factory factory Factory with element constructors
function menu_api.bind(window) end

-- =============================================================================
-- RENDERING
-- =============================================================================

---Renders all tree headers in the left window
---@param left_window? window Optional override for the left window
function menu_api.render_tree_headers(left_window) end

---Renders all attached (non-tree) elements in the right window
---@param right_window? window Optional override for the right window
function menu_api.render_attached_elements(right_window) end

---Convenience function that calls both render_tree_headers and render_attached_elements
function menu_api.render_layout() end

-- =============================================================================
-- SEARCH AND NAVIGATION
-- =============================================================================

---Searches for elements by label or path
---@param term string The search term
---@param opts? { match_paths?: boolean } Options. match_paths defaults to true
---@return menu_search_result[] results Array of matching elements
function menu_api.search(term, opts) end

---Navigates to and highlights a specific element by ID.
---Opens parent trees, scrolls to element, and applies highlight effect.
---@param id string|number The element ID to navigate to
---@return boolean success True if element was found and navigated to
function menu_api.navigate_to(id) end

---Renders search results as clickable entries (optional helper)
---@param win window The window to render in
---@param results menu_search_result[] The search results from menu_api.search()
function menu_api.render_search_results(win, results) end

-- =============================================================================
-- INTERNATIONALIZATION
-- =============================================================================

---@class menu_i18n
---@field language_files table<string, string> Map of language name to filename
---@field SHOULD_EXPORT boolean Whether to auto-export labels to files
menu_api.i18n = {}

---Writes collected labels to translation files
function menu_api.i18n.flush_new_labels_to_files() end

---Enable/disable label collection
---@param state boolean
function menu_api.i18n.set_collecting(state) end

---Get all collected labels
---@return string[]
function menu_api.i18n.get_collected_labels() end

return menu_api