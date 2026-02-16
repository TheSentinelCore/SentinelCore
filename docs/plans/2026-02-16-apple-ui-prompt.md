# NavLib Apple-Inspired UI/UX Design Prompt

> Two-phase prompt chain for redesigning NavLib's settings UI and 3D overlay with Apple/iOS design principles. Feed Phase 1 first, review the spec, then feed Phase 2 with the approved spec.

---

## Phase 1: UI/UX Design Specification

Copy everything below this line into a new Claude conversation.

---

```
[SYSTEM]
You are a senior UI/UX designer who has spent 15 years at Apple working on iOS Settings, System Preferences, and developer tools. You specialize in translating complex, parameter-heavy interfaces into minimal, intuitive designs that feel effortless. You understand Apple's Human Interface Guidelines deeply — not as rules to follow, but as design philosophy to embody: clarity through visual hierarchy, deference to content, depth through meaningful layering.

You are now consulting on a gaming automation tool's settings interface. The rendering engine is custom (ImGui-like), not native iOS — so you must adapt Apple's design language to the available primitives rather than expecting UIKit components.
```

```
[USER]

<context>
NavLib is a navigation plugin for a World of Warcraft automation framework called Sylvannas. It provides pathfinding (via an HTTP server called NavBuddy), path following with stuck recovery, obstacle avoidance, and a 3D in-world visualization overlay.

The settings UI is built using a custom widget library called AstroUI — a tab-based window framework with custom-rendered widgets (checkboxes, sliders, dropdowns, keybinds). It runs inside the game overlay and must feel native to a gaming context while being clean and professional.

The current UI has 57 settings across 4 tabs with a "Show Advanced" toggle. It works but feels dense, utilitarian, and overwhelming. The goal is to redesign it with Apple's design philosophy: progressive disclosure, generous whitespace, clear visual hierarchy, and a sense of calm precision.

The target user is a power-user gamer who values:
- Quick access to the 5-8 settings they actually change
- Confidence that defaults are sensible (they should rarely need to touch advanced settings)
- Visual feedback about what the system is doing (the 3D overlay)
- A UI that feels polished and intentional, not thrown together
</context>

<rendering_engine>
The Sylvannas rendering engine provides these primitives for the settings window:

WINDOW SYSTEM:
- Windows are created via core.menu.window(id) — independent, draggable, resizable
- Position/size persistence via menu slider elements
- Resizing: NO_RESIZE, RESIZE_WIDTH, RESIZE_HEIGHT, RESIZE_BOTH_AXIS
- Z-ordering via set_render_layer() and set_focus()

2D DRAWING (inside window callbacks):
- render_text(font_id, pos, color, text) — positioned text
- render_text_custom_size(font_id, pos, color, font_size, text) — custom size
- render_text_wrapped(text, color, max_wrap_width) — auto-wrapping text
- render_rect_filled(pos_min, pos_max, color, rounding) — filled rectangle
- render_rect(pos_min, pos_max, color, rounding, thickness) — outlined rectangle
- render_rect_filled_multicolor(pos_min, pos_max, col_ul, col_ur, col_br, col_bl, rounding) — gradient rect
- render_circle(center, radius, color, thickness) — circle outline
- render_circle_filled(center, radius, color) — filled circle
- render_line(p1, p2, color, thickness) — line segment
- render_triangle_filled(p1, p2, p3, color) — filled triangle
- render_bezier_cubic(p1, p2, p3, p4, color, segments, thickness) — cubic bezier curve
- push_clip_rect(min, max, intersect) / pop_clip_rect() — clipping regions
- push_font(font_id) / pop_font() — font switching
- get_text_size(text) — text measurement
- add_separator() — horizontal separator line

FONTS (via enums.window_enums.font_id):
- FONT_SMALL (0) — body text, labels
- FONT_NORMAL (1) — slightly larger
- FONT_SEMI_BIG (2) — section headers
- FONT_BIG (3) — titles
- FONT_ICONS_SMALL (4), FONT_ICONS_BIG (5), FONT_ICONS_VERY_BIG (6)

INTERACTIVE WIDGETS (menu elements, created once, persist across sessions):
- core.menu.checkbox(default, id) — boolean toggle → get_state() / set(bool)
- core.menu.slider_int(min, max, default, id) — integer slider → get() / set(int)
- core.menu.slider_float(min, max, default, id) — float slider → get() / set(float)
- core.menu.combobox(default_index, id) — dropdown → get() / set(index)
- core.menu.keybind(default_key, toggle, id) — keybind capture
- core.menu.colorpicker(default_color, id) — color selection

INPUT (inside window callbacks):
- is_mouse_hovering_rect(min, max) — hover detection
- is_rect_clicked(min, max) — click detection
- is_mouse_button_pressed(button) — held state
- is_mouse_button_clicked(button) — single click
- is_mouse_hovering_rect_block_movement(min, max) — prevent window drag while interacting
- block_input_capture() — prevent input propagation
- core.input.is_key_pressed(key_code) — keyboard state

COLORS:
- color.new(r, g, b, a) — RGBA, 0-255 each
- color:blend(other, alpha) — blending
- Predefined: color.white(a), color.black(a), color.red(a), color.green(a), color.blue(a), color.cyan(a), color.orange(a), color.yellow(a), color.gray(a), color.purple(a)

3D WORLD OVERLAY (for in-world visualization):
- core.graphics.line_3d(start, end, color, thickness, fade_factor)
- core.graphics.circle_3d(center, radius, color, thickness, fade_factor)
- core.graphics.circle_3d_filled(center, radius, color)
- core.graphics.circle_3d_percentage(center, radius, color, pct, thickness)
- core.graphics.text_3d(text, position, font_size, color, centered)
- core.graphics.rect_3d_filled(p1, p2, p3, p4, color)
- core.graphics.triangle_3d_filled(p1, p2, p3, color)
- core.graphics.w2s(world_pos) — world-to-screen projection

CONSTRAINTS:
- No native scrollviews — scrolling is custom-implemented via clip rects + offset
- No native buttons/toggles — all widgets are custom-drawn rectangles with click detection
- No text wrapping in positioned text — must use render_text_wrapped() or manual line breaking
- No native animations — must be implemented frame-by-frame with core.time() delta
- All menu elements must be created at init time (not inside render callbacks)
- Window titles appear in the title bar; no custom title bar rendering needed
</rendering_engine>

<current_theme_structure>
The AstroUI theme system uses this color structure. A new "apple" theme must define all these keys:

```lua
THEMES.apple = {
    background       = color.new(r, g, b, a),  -- window background
    border           = color.new(r, g, b, a),  -- window border
    section_bg       = color.new(r, g, b, a),  -- section/card background
    section_border   = color.new(r, g, b, a),  -- section/card border
    primary_accent   = color.new(r, g, b, a),  -- primary interactive color (active tabs, fills)
    secondary_accent = color.new(r, g, b, a),  -- secondary highlight (labels, indicators)
    text_primary     = color.new(r, g, b, a),  -- main text
    text_secondary   = color.new(r, g, b, a),  -- dimmed text, descriptions
    text_disabled    = color.new(r, g, b, a),  -- inactive/disabled text
    slider_fill      = color.new(r, g, b, a),  -- slider progress fill
    slider_bg        = color.new(r, g, b, a),  -- slider track background
    checkbox_active  = color.new(r, g, b, a),  -- checked checkbox fill
    checkbox_inactive = color.new(r, g, b, a), -- unchecked checkbox background
    checkbox_border  = color.new(r, g, b, a),  -- checkbox border
    keybind_bg       = color.new(r, g, b, a),  -- keybind badge background
    keybind_border   = color.new(r, g, b, a),  -- keybind badge border
    keybind_active   = color.new(r, g, b, a),  -- keybind active/enabled color
    keybind_inactive = color.new(r, g, b, a),  -- keybind disabled color
    separator        = color.new(r, g, b, a),  -- separator lines
}
```

For reference, the current "neutral" theme NavLib uses:
```lua
neutral = {
    background       = color.new(20, 24, 28, 220),
    border           = color.new(80, 120, 160, 255),
    section_bg       = color.new(28, 32, 38, 180),
    section_border   = color.new(80, 120, 160, 200),
    primary_accent   = color.new(100, 150, 200, 255),
    secondary_accent = color.new(150, 200, 100, 255),
    text_primary     = color.white(245),
    text_secondary   = color.new(200, 200, 210, 255),
    text_disabled    = color.new(120, 120, 125, 255),
    slider_fill      = color.new(100, 150, 200, 220),
    slider_bg        = color.new(40, 44, 50, 200),
    checkbox_active  = color.new(100, 150, 200, 255),
    checkbox_inactive = color.new(80, 84, 90, 200),
    checkbox_border  = color.new(80, 120, 160, 200),
    keybind_bg       = color.new(35, 39, 45, 220),
    keybind_border   = color.new(80, 120, 160, 180),
    keybind_active   = color.new(150, 200, 100, 255),
    keybind_inactive = color.new(60, 64, 70, 200),
    separator        = color.new(80, 120, 160, 200),
}
```
</current_theme_structure>

<layout_constants>
Current AstroUI layout constants (these can be overridden per-theme or globally):

```lua
LAYOUT = {
    padding_top = 10,
    padding_side = 15,
    padding_bottom = 15,
    tab_bar_height = 35,
    tab_button_height = 30,
    tab_button_min_width = 80,
    tab_button_max_width = 150,
    tab_button_spacing = 2,
    tab_bar_padding_top = 5,
    tab_content_padding_top = 15,
    section_spacing = 18,
    section_header_height = 0,
    section_padding_top = 8,
    section_padding_bottom = 10,
    element_height = 26,
    element_spacing = 6,
    column_spacing = 25,
    slider_bar_height = 16,
    checkbox_size = 16,
    keybind_badge_width = 60,
    keybind_status_width = 45,
    keybind_clear_width = 60,
    separator_height = 2,
}
```
</layout_constants>

<all_settings>
Every NavLib setting that must be accommodated in the redesign. Each entry shows: key, type, range, default, and current menu ID.

MOVEMENT SETTINGS (38):
- dynamic_speed: bool, default=false — Adjusts speed based on path curvature
- dynamic_speed_max_tolerance_scale: float 1.0-2.0, default=1.20 — Max tolerance multiplier at high speed
- dynamic_speed_max_tolerance_bonus: float 0.0-2.0, default=0.75 — Flat tolerance bonus at high speed
- dynamic_speed_ramp_z_delta: float 0.5-5.0, default=1.2 — Z-change threshold for speed ramp
- dynamic_speed_ramp_tolerance: float 0.5-5.0, default=1.8 — Tolerance ramp distance
- dynamic_speed_ramp_look_distance: float 2.0-15.0, default=6.0 yd — Lookahead distance for speed decisions
- waypoint_tolerance: float 0.5-10.0, default=3.0 yd — Distance to advance to next waypoint
- final_tolerance: float 0.5-5.0, default=1.5 yd — Distance to consider arrival complete
- anti_detection: bool, default=false — Random path deviations for anti-detection
- max_deviation: float 1.0-20.0, default=3.0 yd — Max random offset from path
- stuck_check_interval: float 0.25-5.0, default=0.25 s — How often to check if stuck
- stuck_distance_min: float 0.1-2.0, default=0.1 yd — Min distance between stuck checks
- max_stuck_attempts: int 1-10, default=6 — Recoveries before aborting
- path_check_interval: float 1.0-30.0, default=5.0 s — Revalidation interval
- deviation_check_interval: float 0.1-5.0, default=1.0 s — Deviation check frequency
- deviation_threshold: float 1.0-20.0, default=2.0 yd — Lateral drift repath trigger
- deviation_vertical_threshold: float 0.5-10.0, default=2.0 yd — Vertical drift trigger
- deviation_corridor_factor: float 0.1-2.0, default=0.75x — Corridor width fraction trigger
- repath_cooldown: float 0.1-5.0, default=0.1 s — Min time between repaths
- max_deviation_repaths: int 1-10, default=5 — Max consecutive repaths
- smoothing: combo {none, chaikin, catmull, bezier}, default=chaikin — Path smoothing algorithm
- smooth_iterations: int 1-5, default=3 — Chaikin subdivision passes
- smooth_samples: int 5-50, default=10 — Spline interpolation samples
- smooth_ratio: int 50-95, default=50% — Smoothing strength (Chaikin ratio)
- min_corner_angle: float 0-120, default=90° — Min angle to smooth
- keep_originals: bool, default=false — Preserve original waypoints
- optimize: bool, default=true — String-pulling path optimization
- allow_partial: bool, default=true — Accept partial paths when full path fails
- filter_ground: float 0.1-10.0, default=1.0x — Ground terrain cost multiplier
- filter_water: float 0.1-100.0, default=10.0x — Water terrain cost
- filter_lava: float 0.1-1000.0, default=100.0x — Lava terrain cost
- use_corridor_indoor: bool, default=true — Use corridor pathfinding indoors
- corridor_probe_dist: float 5.0-30.0, default=15.0 yd — Corridor detection distance
- wall_clearance_enabled: bool, default=true — Keep distance from walls
- wall_clearance: float 0.5-5.0, default=3.0 yd — Wall clearance distance
- proactive_obstacle_check: bool, default=true — Enable proactive obstacle scanning
- proactive_obstacle_interval: float 0.5-5.0, default=1.5 s — Proactive scan interval
- debug_verbose: bool, default=false — Verbose logging (defined in Defaults.movement)

OBSTACLE SETTINGS (11):
- avoidance_radius: float 1.0-10.0, default=3.0 yd — Obstacle zone radius
- max_zones: int 1-20, default=5 — Max simultaneous zones
- zone_ttl: float 30-300, default=120 s — Zone expiration time
- avoidance_cost: float 1.0-100.0, default=100.0 — Pathfinding cost for zones
- zone_prune_dist: float 50-500, default=100 yd — Remove zones beyond this
- probe_distance: float 2.0-20.0, default=8.0 yd — Reactive probe distance
- probe_spread_deg: float 5-45, default=20° — Reactive probe angle spread
- probe_height_offset: float 0.5-5.0, default=1.0 yd — Reactive probe height
- lookahead_height_offset: float 0.5-5.0, default=1.5 yd — Proactive scan height
- lookahead_spread_deg: float 5-45, default=15° — Proactive scan spread
- lookahead_segments: int 1-10, default=3 — Number of scan segments

DEBUG SETTINGS (7):
- debug_mode: int 0-12, default=0 — Navigation test mode selector
- viz_master: bool, default=false — Master visualization toggle
- viz_path: bool, default=true — Show path lines + waypoints
- viz_destination: bool, default=true — Show destination marker
- viz_obstacles: bool, default=true — Show obstacle zones
- viz_corridor: bool, default=true — Show corridor boundaries
- viz_state: bool, default=true — Show state indicators (stuck/requesting/arrived/failed)

WINDOW SETTINGS (1):
- show_advanced: bool, default=false — Show/hide advanced settings
</all_settings>

<current_3d_overlay>
The current 3D overlay uses these colors and rendering styles:

```lua
COLORS = {
    path_future_line = color.cyan(150),          -- upcoming path segments
    path_past_line   = color.new(80, 80, 90, 60), -- already-traversed path
    waypoint_current = color.orange(255),         -- current target waypoint
    waypoint_future  = color.cyan(180),           -- upcoming waypoints
    player_to_target = color.orange(120),         -- line from player to current waypoint
    destination_ring = color.green(220),           -- destination bullseye (2 concentric rings)
    destination_text = color.white(255),           -- distance text at destination
    obstacle_fill    = color.new(220, 40, 40, 50), -- semi-transparent obstacle zone
    obstacle_ring    = color.new(220, 40, 40, 150),-- obstacle outline
    obstacle_text    = color.new(220, 80, 80, 200),-- obstacle label
    corridor_line    = color.new(160, 140, 220, 120), -- corridor boundary lines
    requesting_ring  = color.yellow(180),          -- waiting-for-path indicator
    failed_ring      = color.red(220),             -- path failed X marker
    failed_text      = color.red(255),             -- "FAILED" text
}

Rendering styles:
- Path: line_3d segments, future=cyan, past=gray dim
- Waypoints: circle_3d, current=1.5yd orange, future=0.8yd cyan
- Destination: double concentric green rings (2.0 + 2.8 yd) + distance text
- Obstacles: circle_3d_filled (red, low alpha) + circle_3d outline
- Corridor: line_3d pairs (left/right perpendicular boundaries), purple tint
- State: stuck=pulsing red ring, requesting=yellow ring, arrived=expanding green ring, failed=red X lines + text
```
</current_3d_overlay>

<tabbuilder_api>
The AstroUI TabBuilder API for registering tabs. Each tab is a function that receives a builder:

```lua
-- Register a tab
ui:add_tab({ id = "tab_id", label = "Tab Label", visible_when = optional_fn }, function(t)
    -- Checkbox grid: multi-column boolean toggles
    t:checkbox_grid({
        label = "Section Name",     -- optional section header text
        columns = 2,                -- number of columns (default 2)
        elements = {
            { element = menu.some_checkbox, label = "Display Label", tooltip = "Hover description", visible_when = optional_fn },
        },
        visible_when = optional_fn, -- optional: hide entire group conditionally
    })

    -- Slider list: vertical list of sliders with labels
    t:slider_list({
        label = "Section Name",
        elements = {
            { element = menu.some_slider, label = "Display Label", suffix = " yd", tooltip = "Description", min = 0, max = 100 },
        },
        visible_when = optional_fn,
    })

    -- Combo list: vertical list of dropdowns (click to cycle options)
    t:combo_list({
        label = "Section Name",
        elements = {
            { element = menu.some_combo, label = "Display Label", options = {"A", "B", "C"}, tooltip = "Description" },
        },
        visible_when = optional_fn,
    })

    -- Keybind grid: keybind rows with badge + status + clear
    t:keybind_grid({
        elements = { menu.some_keybind },
        labels = { "Display Label" },
        visible_when = optional_fn,
    })

    -- Custom render: fully custom drawing
    t:custom_render({
        render_fn = function(self, y_offset)
            -- self = the RotationSettingsUI instance
            -- self.window = the window object (for rendering)
            -- self.colors = the theme color table
            -- Must return new y_offset after content
            return y_offset + content_height
        end,
        visible_when = optional_fn,
    })
end)
```

Key patterns:
- visible_when functions control progressive disclosure (return true/false)
- custom_render gives full drawing control for buttons, status displays, etc.
- Elements reference menu objects created at init time (not inline)
- Tooltips appear in a bar at the bottom of the window on hover
</tabbuilder_api>

<example_tab_implementation>
Here is a simplified tab implementation for reference (the real file has more sections and a longer reset list). This shows the code pattern and API usage:

```lua
-- movement_tab.lua
local vec2      = require("common/geometry/vector_2")
local enums     = require("common/enums")
local AstroUI   = require("shared/AstroUI")
local Defaults  = require("core/Defaults")

local LAYOUT = AstroUI.LAYOUT
local D = Defaults.movement

local MovementTab = {}

function MovementTab.register(ui, menu)
    local function anti_detection_on()
        return menu.anti_detection:get_state()
    end

    local function show_advanced()
        return menu.show_advanced:get_state()
    end

    ui:add_tab({ id = "movement", label = "Movement" }, function(t)
        t:checkbox_grid({
            label = "Speed",
            columns = 1,
            elements = {
                { element = menu.dynamic_speed, label = "Dynamic Speed", tooltip = "Adjusts movement speed based on path curvature and terrain" },
            }
        })

        t:slider_list({
            label = "Tolerances",
            elements = {
                { element = menu.waypoint_tolerance, label = "Waypoint", suffix = " yd", tooltip = "Distance from waypoint before advancing to the next one" },
                { element = menu.final_tolerance, label = "Final", suffix = " yd", tooltip = "Distance from destination to consider arrival complete" },
            }
        })

        t:checkbox_grid({
            label = "Anti-Detection",
            columns = 1,
            elements = {
                { element = menu.anti_detection, label = "Enable", tooltip = "Adds slight random deviations to movement path" },
            }
        })

        t:slider_list({
            visible_when = anti_detection_on,
            elements = {
                { element = menu.max_deviation, label = "Max Deviation", suffix = " yd", tooltip = "Maximum random offset from the path" },
            }
        })

        -- Advanced sections hidden by default
        t:slider_list({
            label = "Stuck Recovery",
            visible_when = show_advanced,
            elements = {
                { element = menu.stuck_interval, label = "Check Interval", suffix = " s" },
                { element = menu.stuck_distance, label = "Min Distance", suffix = " yd" },
                { element = menu.max_stuck, label = "Max Attempts" },
            }
        })

        -- Reset button (custom render)
        t:custom_render({
            render_fn = function(self, y_offset)
                local window = self.window
                local colors = self.colors
                local x = LAYOUT.padding_side
                local w = window:get_size().x - (2 * LAYOUT.padding_side)
                local h = 22
                local label = "Reset Defaults"
                local btn_start = vec2.new(x, y_offset)
                local btn_end = vec2.new(x + w, y_offset + h)
                local hovered = window:is_mouse_hovering_rect(btn_start, btn_end)
                window:is_mouse_hovering_rect_block_movement(btn_start, btn_end)

                local bg = hovered and colors.primary_accent or colors.slider_fill
                window:render_rect_filled(btn_start, btn_end, bg, 2)
                window:render_rect(btn_start, btn_end, colors.primary_accent, 2, 1.0)

                local text_size = window:get_text_size(label)
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x + (w - text_size.x) / 2, y_offset + (h - text_size.y) / 2),
                    colors.text_primary, label)

                if window:is_rect_clicked(btn_start, btn_end) then
                    Defaults.reset({
                        { menu.dynamic_speed, D.dynamic_speed },
                        { menu.waypoint_tolerance, D.waypoint_tolerance },
                        { menu.final_tolerance, D.final_tolerance },
                    })
                end
                return y_offset + h + 4
            end
        })
    end)
end

return MovementTab
```
</example_tab_implementation>

<apple_design_principles>
Translate these Apple Human Interface Guidelines principles into concrete design decisions for this context:

CLARITY:
- Text is legible at every size. Use FONT_SMALL for body, FONT_SEMI_BIG for section headers.
- Icons and labels are precise and lucid (we have limited icon fonts — use text labels and geometric shapes instead).
- Functionality drives the design — every pixel serves a purpose.

DEFERENCE:
- The UI helps users understand and interact with content but never competes with it.
- Fluid motion and a crisp interface help understanding without distraction.
- Content fills the full window — minimize chrome and decorative elements.

DEPTH:
- Visual layers and realistic motion convey hierarchy and position.
- Transitions provide a sense of depth as users navigate (tab transitions, expand/collapse).
- The active element should feel lifted; inactive elements recede.

PROGRESSIVE DISCLOSURE (iOS Settings pattern):
- Primary screen shows only the most important toggles (5-8 max).
- Tapping a row reveals its detail view (in our case: expanding sections or sub-tabs).
- Advanced settings are always accessible but never in the way.

VISUAL LANGUAGE:
- Use generous padding (16-20px side margins, 12px between elements).
- Rounded corners on all interactive elements (rounding >= 4.0).
- Subtle backgrounds with high-contrast text (not heavy borders).
- Section separators are thin (1px) and low-contrast.
- Active/selected states use a single accent color — consistency over variety.
- Disabled states are visually recessed (lower alpha, dimmer color).

COLOR PHILOSOPHY (Dark mode, suited to game overlay):
- Background: very dark, near-black with a cool undertone (think macOS Sonoma dark mode)
- Cards/sections: slightly elevated from background (2-4 brightness steps)
- Accent: a single, distinctive blue (iOS system blue: ~0, 122, 255 adapted for dark backgrounds)
- Success/error: green and red only for status indicators, never decorative
- Text hierarchy through alpha, not color — primary at 100%, secondary at 60%, disabled at 30%
</apple_design_principles>

<frontend_aesthetics>
You tend to converge toward generic, "on distribution" outputs. In UI design, this creates flat, uninspired interfaces. Make intentional, distinctive design choices that feel genuinely crafted.

Focus on:
- Color: Commit to a cohesive dark palette. One dominant accent with sharp contrast outperforms a scattered palette. Draw from macOS Sonoma dark mode and Xcode's dark theme for inspiration.
- Typography: Use size and weight (via alpha) to create clear hierarchy. Large jumps between heading and body sizes (3x+). Body text should breathe — never feel cramped.
- Whitespace: Treat whitespace as a design element, not wasted space. Apple uses 2-3x more padding than most interfaces. Every section should have room to breathe.
- Motion: Where the engine allows frame-based animation (expanding sections, fade-in), use it for single high-impact moments rather than constant motion.

Make design choices that feel like an Apple designer made them — restrained, confident, with every detail considered. The goal is that a user opens this settings panel and thinks "this feels premium."
</frontend_aesthetics>

<instructions>
Design the complete UI/UX specification for NavLib's settings window and 3D overlay. Work through this in two stages:

STAGE 1 — REASONING (output in <thinking> tags):

1. INFORMATION ARCHITECTURE
   - Given the 42 settings above, which 5-8 are essential for the default view?
   - How should the remaining settings be organized? Consider: fewer tabs with expanding sections vs more tabs with less content each.
   - What is the natural mental model for a user? (They think about "how the bot moves" not "movement parameters vs pathfinding parameters")
   - Should the Debug tab remain as a tab, or become a separate mode/panel?

2. VISUAL HIERARCHY
   - How does the tab bar differ from iOS-style segmented controls given our rectangle primitives?
   - How do section headers separate from widget labels given only 4 font sizes?
   - How does the "expanded/collapsed" state communicate visually?

3. INTERACTION PATTERNS
   - How does progressive disclosure work with the AstroUI TabBuilder API?
   - What happens when a user clicks a section header? (expand/collapse vs navigate)
   - How do sliders provide precise control? (direct manipulation + value display)

4. 3D OVERLAY
   - How does the overlay color palette harmonize with the new window theme?
   - What visual style communicates "premium" in a 3D game world overlay?
   - How do state indicators communicate status without being garish?

STAGE 2 — SPECIFICATION (output in <design_spec> tags):

For each of these sections, provide concrete, implementable details:

A. THEME: Complete "apple" theme color table (all 19 keys with exact RGBA values)

B. LAYOUT OVERRIDES: Any changes to the LAYOUT constants table for the Apple aesthetic

C. TAB STRUCTURE: For each tab:
   - Tab ID and label
   - Default-visible settings (the 5-8 essential ones)
   - Expandable/advanced sections with their settings
   - Custom render areas (status displays, buttons)
   - visible_when conditions

D. INTERACTION SPEC: How progressive disclosure works mechanically:
   - What triggers expansion (click target, toggle, etc.)
   - What animates (instant vs transition)
   - How expanded state persists

E. 3D OVERLAY PALETTE: Complete replacement color table for Visualizer.lua with:
   - New RGBA values for all overlay colors
   - Any changes to rendering style (line thickness, circle radius, fade values)
   - Design rationale for each color choice

F. WINDOW CONFIG: Default window size, position, and title
</instructions>

<output_format>
Structure your response as:
1. <thinking> — Your design reasoning for each of the 4 areas above
2. <design_spec> — The complete specification, organized by sections A through F, with exact values and clear implementation notes

For color values, always provide exact RGBA as color.new(r, g, b, a).
For layout values, provide exact pixel numbers.
For interaction patterns, describe the user flow step by step.
</output_format>
```

---

## Phase 2: Implementation Code

After reviewing and approving the Phase 1 design spec, copy the approved `<design_spec>` output and paste it into the context below, replacing `{PASTE_APPROVED_DESIGN_SPEC_HERE}`.

---

```
[SYSTEM]
You are an expert Lua developer specializing in custom UI frameworks. You write clean, well-structured code with clear separation between configuration and logic. You follow existing codebase patterns exactly — matching naming conventions, file structure, and API usage from the reference code provided.
```

```
[USER]

<context>
You are implementing an approved UI/UX design specification for NavLib, a navigation plugin built on the AstroUI custom widget library. The design has been reviewed and approved. Your job is to produce production-ready Lua code that implements it precisely.

The codebase uses:
- AstroUI TabBuilder API for tab registration
- Menu elements created via core.menu.* at init time
- Defaults.lua as single source of truth for all setting definitions
- window.lua as the orchestrator (creates UI, syncs settings to Facade)
- Separate tab files in ui/tabs/ for each tab's content
- Visualizer.lua for 3D in-world overlay colors and rendering
</context>

<approved_design_spec>
{PASTE_APPROVED_DESIGN_SPEC_HERE}
</approved_design_spec>

<reference_files>
These are the current implementations. Match their patterns exactly (file structure, require paths, naming, error handling with pcall, etc.):

CURRENT THEME DEFINITION (in AstroUI.lua — add the new theme alongside existing ones):
```lua
local THEMES = {
    rogue = { ... },
    neutral = { ... },
    hunter = { ... },
    astro = { ... },
    -- ADD: apple = { ... }
}
```

CURRENT WINDOW ORCHESTRATOR PATTERN (window.lua):
```lua
-- Creates menu elements from Defaults
-- Creates AstroUI.new({...}) with config
-- Registers tabs via TabModule.register(ui, menu)
-- Sets _before_tabs_fn for content above tabs
-- Syncs menu → Facade config every frame
```

CURRENT TAB PATTERN (movement_tab.lua):
```lua
local MovementTab = {}
function MovementTab.register(ui, menu)
    local function show_advanced()
        return menu.show_advanced:get_state()
    end

    ui:add_tab({ id = "movement", label = "Movement" }, function(t)
        t:checkbox_grid({ ... })
        t:slider_list({ ... })
        t:custom_render({ render_fn = function(self, y_offset) ... end })
    end)
end
return MovementTab
```

CURRENT VISUALIZER COLOR PATTERN (Visualizer.lua):
```lua
local COLORS = {
    path_future_line = color.cyan(150),
    -- ... all colors defined at require-time
}
-- Used as: core.graphics.circle_3d(pos, radius, COLORS.destination_ring, thickness, Z_OFFSET)
```
</reference_files>

<instructions>
Produce the following files as complete, ready-to-use Lua code. Each file should be a self-contained code block with the file path as a header comment.

1. **AstroUI.lua theme addition**: Output ONLY the new `apple` theme table to be added to the THEMES table in AstroUI.lua. Include exact placement instructions (after which existing theme).

2. **AstroUI.lua LAYOUT overrides** (if the design spec calls for layout changes): Output the modified LAYOUT table, or specify "no changes needed."

3. **window.lua**: Complete rewrite of the window orchestrator implementing the new tab structure, progressive disclosure system, and settings sync. Must create all menu elements, register all redesigned tabs, and sync to Facade.

4. **Each tab file** (ui/tabs/*.lua): One complete file per tab in the new information architecture. Follow the TabBuilder API exactly.

5. **Visualizer.lua COLORS update**: Output the replacement COLORS table with the new overlay palette. Include any changes to rendering constants (line thickness, circle radius, etc.).

For each file, ensure:
- All require() paths match the existing project structure
- All menu element IDs match Defaults.lua (the IDs must not change — they persist across sessions)
- All pcall() patterns match existing error handling
- visible_when functions implement the progressive disclosure from the spec
- Custom render functions use the theme's color table (self.colors), not hardcoded colors
- Reset Defaults buttons exist on each settings tab
</instructions>

<output_format>
For each file, output:
```lua
-- [file_path relative to NavLib/]
-- [brief description of changes]

[complete file contents]
```

Output files in dependency order: theme first, then window.lua, then tabs, then visualizer.
</output_format>
```
