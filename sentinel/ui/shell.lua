-- sentinel/ui/shell.lua
-- The IDE shell: one window, a panel switcher, and layout that survives an injection
-- (ADR 09b §2.2, §2.3, §4).
--
-- WHAT THIS FILE IS ALLOWED TO DO
-- ------------------------------
-- Paint. Every branch it appears to contain is a projection of `shell_state.lua`: which tabs
-- exist, which one is active, whether an empty pane replaces the body, whether the marker may
-- move. Nothing here is decided, because nothing inside `register_on_render_window_callback` can
-- be executed by a test (ADR 09b §2.1).
--
-- WHAT IT MUST NEVER DO
-- --------------------
--  1. CONSTRUCT A MENU ELEMENT OR A WINDOW DURING RENDER. Sylvannas forbids it; the failure is at
--     runtime in the injector, with the offline suite green. The ghost sliders below are built at
--     module scope and the window in `ensure_frames_created`, which `main.lua` drives from the
--     tick callback exactly as it already drives the runner cockpit's. `test_shell.lua` counts
--     constructions per phase and requires zero during render.
--  2. TOUCH THE NETWORK OR THE DISK. This runs every frame (ADR 09b §2.4).
--  3. NAME A PANEL. Panels arrive through `register_panel`; a shell that required one would have
--     to be edited by every unit that follows it, and simultaneous edits to one file is the
--     collision the ownership split exists to prevent.
--
-- THE PANEL CONTRACT
-- ------------------
--     shell:register_panel({
--         id                = "graph",          -- required, unique
--         render            = function(window, bounds, ctx) end,   -- required
--         title             = "Graph",          -- optional, defaults to the id, Title Cased
--         badge             = "3",              -- optional, drawn on the tab
--         order             = 2,                -- optional, overrides the declared slot
--         split             = "primary",        -- optional, a persisted divider key
--         split_axis        = "x",              -- optional, "x" (default) or "y"
--         requires_campaign = true,             -- optional, opts into the empty state
--     })
--
-- `ctx` carries `{ shell, state, split }`. `ctx.split` is `{ first, second, divider }` when the
-- panel declared one and nil otherwise.

local Theme = require("ui/theme")
local Widgets = require("ui/widgets")
local ShellState = require("ui/shell_state")

local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    if ok and mod ~= nil then return mod end
    return fallback
end

-- Guarded exactly as `theme.lua` and `widgets.lua` guard theirs: the whole UI layer stays
-- loadable with no injector present, which is what `tests/ui/test_offline_loadable.lua` pins.
local Vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y) return { x = x or 0, y = y or 0 } end,
})
local Enums = require_or("common/enums", nil)

local Shell = {}
Shell.__index = Shell

local function v2(x, y) return Vec2.new(x, y) end

-- ============================================================================
-- Ghost sliders — the only thing that survives an injection (ADR 09b §2.3)
-- ============================================================================
-- Per `guides/custom-ui.md` §Basics-1 Case 2. Menu elements are the sole resource that outlives
-- an injection: the file-IO surface persists DOCUMENTS, and re-reading a file every frame to
-- restore a window position is not a thing this render path may do. (No comment here spells the
-- file-IO calls out either — `test_shell.lua` greps this source for them.)
--
-- Constructed at MODULE SCOPE, which is both the Sylvannas rule and a necessity — the window's
-- initial geometry is read from these before the window exists.

local ELEMENT_PREFIX = "sentinel_ide_"

--- The menu API, or nil. Offline (and in every test in this repo) there is no injector at all, so
--- persistence has to degrade to none rather than take the whole UI layer down with it.
local function menu_api()
    if type(core) ~= "table" then return nil end
    if type(core.menu) ~= "table" then return nil end
    if type(core.menu.slider_int) ~= "function" then return nil end
    return core.menu
end

--- Screen coordinates and sizes in pixels. The ceiling is deliberately far beyond any monitor:
--- a slider that clamped below the window's real position would silently move the IDE on reload.
local COORD_MAX = 10000

local function build_elements()
    local menu = menu_api()
    if not menu then return nil end

    local elements = {
        position_x = menu.slider_int(0, COORD_MAX, ShellState.DEFAULT_POSITION.x, ELEMENT_PREFIX .. "position_x"),
        position_y = menu.slider_int(0, COORD_MAX, ShellState.DEFAULT_POSITION.y, ELEMENT_PREFIX .. "position_y"),
        size_x     = menu.slider_int(0, COORD_MAX, ShellState.DEFAULT_SIZE.x, ELEMENT_PREFIX .. "size_x"),
        size_y     = menu.slider_int(0, COORD_MAX, ShellState.DEFAULT_SIZE.y, ELEMENT_PREFIX .. "size_y"),
        -- The active panel travels as a slot index because a slider carries a number. See
        -- `ShellState:layout` for what that costs and why it is still the right trade.
        active_slot = menu.slider_int(1, #ShellState.TAB_ORDER, 1, ELEMENT_PREFIX .. "active_slot"),
    }
    -- Ratios persist as whole percent: `slider_int` is integral, and a `slider_float` would buy
    -- precision nobody can perceive in a divider position.
    for _, key in ipairs(ShellState.PERSISTED_SPLITS) do
        elements["split_" .. key] = menu.slider_int(0, 100,
            math.floor(ShellState.DEFAULT_SPLIT_RATIO * 100 + 0.5), ELEMENT_PREFIX .. "split_" .. key)
    end

    -- ADR 09b §5.2: "Escape closes, a keybind toggles. Hands stay near movement keys." Seeded
    -- unbound (7) per `api/ui-control-panel.md`, so the IDE cannot steal a key the operator is
    -- already using to play.
    if type(menu.keybind) == "function" then
        elements.toggle_keybind = menu.keybind(7, false, ELEMENT_PREFIX .. "toggle")
    end

    return elements
end

Shell.elements = build_elements()

-- ============================================================================
-- Persistence
-- ============================================================================
-- Static and element-driven so the round trip is testable against slider stand-ins. Layout that
-- is not proven to survive is layout the operator rearranges after every reload.

local function slider_get(element, fallback)
    if not element or type(element.get) ~= "function" then return fallback end
    local ok, value = pcall(element.get, element)
    if not ok or tonumber(value) == nil then return fallback end
    return tonumber(value)
end

local function slider_set(element, value)
    if not element or type(element.set) ~= "function" then return end
    pcall(element.set, element, value)
end

---@return table|nil snapshot
function Shell.load_layout(elements)
    if type(elements) ~= "table" then return nil end
    local splits = {}
    for _, key in ipairs(ShellState.PERSISTED_SPLITS) do
        splits[key] = slider_get(elements["split_" .. key],
            ShellState.DEFAULT_SPLIT_RATIO * 100) / 100
    end
    return {
        position = {
            x = slider_get(elements.position_x, ShellState.DEFAULT_POSITION.x),
            y = slider_get(elements.position_y, ShellState.DEFAULT_POSITION.y),
        },
        size = {
            x = slider_get(elements.size_x, ShellState.DEFAULT_SIZE.x),
            y = slider_get(elements.size_y, ShellState.DEFAULT_SIZE.y),
        },
        active_slot = slider_get(elements.active_slot, nil),
        splits = splits,
    }
end

function Shell.save_layout(elements, snapshot)
    if type(elements) ~= "table" or type(snapshot) ~= "table" then return false end
    slider_set(elements.position_x, math.floor((snapshot.position or {}).x or 0))
    slider_set(elements.position_y, math.floor((snapshot.position or {}).y or 0))
    slider_set(elements.size_x, math.floor((snapshot.size or {}).x or 0))
    slider_set(elements.size_y, math.floor((snapshot.size or {}).y or 0))
    if snapshot.active_slot then slider_set(elements.active_slot, math.floor(snapshot.active_slot)) end
    for _, key in ipairs(ShellState.PERSISTED_SPLITS) do
        local ratio = (snapshot.splits or {})[key]
        if ratio then slider_set(elements["split_" .. key], math.floor(ratio * 100 + 0.5)) end
    end
    return true
end

-- ============================================================================
-- Construction
-- ============================================================================

---@param opts table|nil { state, window, elements, on_action }
function Shell.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Shell)

    self._state = opts.state or ShellState.new()
    -- Injected in tests; nil in the injector until the tick callback builds one. Nothing in this
    -- constructor may touch the SDK, because `main.lua` runs it at module scope.
    self._window = opts.window
    self._elements = opts.elements
    if self._elements == nil and opts.elements == nil then self._elements = Shell.elements end
    self._on_action = opts.on_action

    self._geometry_applied = false
    self._saved_layout = nil
    self._tab_layout = {}
    self._empty_action_bounds = nil
    self._window_visible = nil

    -- Restore BEFORE any panel registers. `ShellState` holds the restored choice until the panel
    -- that owns it exists, which is the only ordering that honours a persisted tab.
    local snapshot = Shell.load_layout(self._elements)
    if snapshot then self._state:restore(snapshot) end

    return self
end

-- ============================================================================
-- Delegation to the view-model
-- ============================================================================
-- Thin on purpose: callers (and `main.lua`) talk to the shell, and the shell forwards. Two public
-- surfaces onto the same state is how they drift apart.

function Shell:state() return self._state end
function Shell:register_panel(spec) return self._state:register_panel(spec) end
function Shell:activate(id) return self._state:activate(id) end
function Shell:active_id() return self._state:active_id() end
function Shell:is_visible() return self._state:is_visible() end
function Shell:show() return self._state:show() end
function Shell:hide() return self._state:hide() end
function Shell:toggle() return self._state:toggle() end
function Shell:set_campaign(name) return self._state:set_campaign(name) end
function Shell:campaign() return self._state:campaign() end
function Shell:split_ratio(key) return self._state:split_ratio(key) end
function Shell:set_split_ratio(key, value) return self._state:set_split_ratio(key, value) end

---The switcher geometry from the last rendered frame, as `{ { id, bounds } }`.
---Exposed so a test can click the tab the shell actually drew rather than one it recomputed —
---a test that recomputed the layout would pass while the shell painted somewhere else.
function Shell:tab_layout() return self._tab_layout end
function Shell:empty_action_bounds() return self._empty_action_bounds end

-- ============================================================================
-- Tick context — the ONLY place anything is constructed
-- ============================================================================

function Shell:ensure_frames_created()
    if not self._window then
        -- Nothing is built for an IDE nobody has opened. `main.lua` calls this from every tick
        -- from the moment the plugin loads, and a user who only wants the bot running should not
        -- be paying for an authoring window they never asked for.
        if not self._state:is_visible() then return false end
        local menu = menu_api()
        if not menu or type(menu.window) ~= "function" then return false end
        self._window = menu.window("sentinel_ide_shell")
    end
    if self._geometry_applied then return true end

    local layout = self._state:layout()
    if type(self._window.set_initial_size) == "function" then
        self._window:set_initial_size(v2(layout.size.x, layout.size.y))
    end
    if type(self._window.set_initial_position) == "function" then
        self._window:set_initial_position(v2(layout.position.x, layout.position.y))
    end
    self._geometry_applied = true
    return true
end

-- `is_key_pressed` takes a virtual key code; ESCAPE is 0x1B. Named rather than inlined because a
-- wrong number here is silent — the IDE simply never closes on Escape, and the close cross still
-- works, so nothing looks broken enough to investigate.
local VK_ESCAPE = 0x1B

function Shell:_poll_input()
    local pressed = false
    if type(core) == "table" and type(core.input) == "table"
        and type(core.input.is_key_pressed) == "function" then
        local ok, down = pcall(core.input.is_key_pressed, VK_ESCAPE)
        pressed = ok and down and true or false
    end
    -- The edge is recorded every tick regardless of visibility, so releasing Escape while the
    -- shell is closed cannot leave a stale press that fires on the next open.
    if self._state:edge("escape", pressed) and self._state:is_visible() then
        self._state:hide()
    end

    local keybind = self._elements and self._elements.toggle_keybind
    if keybind and type(keybind.get_state) == "function" then
        local ok, down = pcall(keybind.get_state, keybind)
        if self._state:edge("toggle_keybind", ok and down) then self._state:toggle() end
    end
end

function Shell:_poll_combat()
    -- ADR 09b §5.7: nothing may animate during combat. Read in TICK context, never on the render
    -- path, and answered as false whenever the object manager is unavailable — a missing reading
    -- must suppress motion's precondition, not assert that the player is safe.
    local in_combat = false
    if type(core) == "table" and type(core.object_manager) == "table"
        and type(core.object_manager.get_local_player) == "function" then
        local ok, player = pcall(core.object_manager.get_local_player)
        if ok and player and type(player.is_in_combat) == "function" then
            local ok2, value = pcall(player.is_in_combat, player)
            in_combat = ok2 and value and true or false
        end
    end
    self._state:set_in_combat(in_combat)
end

function Shell:_apply_visibility()
    if not self._window or type(self._window.set_visibility) ~= "function" then return end
    local visible = self._state:is_visible()
    if self._window_visible == visible then return end
    self._window_visible = visible
    self._window:set_visibility(visible)
end

function Shell:_persist_layout()
    if not self._elements then return end
    if self._window then
        if type(self._window.get_position) == "function" and type(self._window.get_size) == "function" then
            self._state:set_window_geometry(self._window:get_position(), self._window:get_size())
        end
    end
    local snapshot = self._state:layout()
    if not ShellState.layout_differs(snapshot, self._saved_layout) then return end
    Shell.save_layout(self._elements, snapshot)
    self._saved_layout = snapshot
end

---Driven from `register_on_update_callback`. Everything with a construction, an SDK read, or a
---write to a persisted element happens here, so the render callback stays paint-only.
function Shell:on_tick()
    self:ensure_frames_created()
    self:_poll_input()
    self:_poll_combat()
    self:_apply_visibility()
    self:_persist_layout()
end

function Shell:destroy()
    self._window = nil
    self._geometry_applied = false
    self._window_visible = nil
end

-- ============================================================================
-- Render context — paint only
-- ============================================================================

local function tab_width(window, tab)
    local label = window:get_text_size(tab.title).x
    local badge = tab.badge and (window:get_text_size(tostring(tab.badge)).x + Theme.space.md) or 0
    return math.max(Theme.metrics.hit_min, label + badge + Theme.space.xl)
end

function Shell:_draw_switcher(window, vm, bounds)
    local items = {}
    for index, tab in ipairs(vm.tabs) do
        items[index] = {
            id = tab.id, kind = "button", label = tab.title,
            -- An active tab is a filled affordance; the rest recede. A strip of five filled
            -- buttons has no way left to say which one you are on.
            variant = tab.active and "primary" or "ghost",
            active = tab.active,
            width = tab_width(window, tab),
        }
    end

    local activated, layout = Widgets.toolbar(window, bounds, { items = items, elevation = "raised" })
    self._tab_layout = layout

    for index, tab in ipairs(vm.tabs) do
        local entry = layout[index]
        if entry and tab.badge then
            local text = tostring(tab.badge)
            local width = window:get_text_size(text).x + Theme.space.md
            Widgets.badge(window, {
                x = entry.bounds.x + entry.bounds.w - width - Theme.space.xs,
                y = entry.bounds.y + (entry.bounds.h - Theme.line_height.body) * 0.5,
                w = width, h = Theme.line_height.body,
            }, { label = text, tone = "accent" })
        end
        if tab.active and entry then
            self:_draw_active_marker(window, bounds, entry.bounds)
        end
    end

    if activated then self._state:activate(activated) end
end

function Shell:_draw_active_marker(window, strip, tab)
    local transition = self._state:marker_transition(tab.x)
    local x = transition.to
    if transition.animate then
        -- ADR 09b §5.7, "motion only to explain": the bar travelling to the tab you just clicked
        -- is what makes the switch legible. `marker_transition` has already refused the animation
        -- in combat, so there is no decision left here.
        local anim = window:animate_widget("sentinel_ide_tab_marker",
            transition.from, transition.to, Theme.interaction.resting.fill,
            Theme.interaction.active.fill, 1, 1, false)
        if anim and anim.current_position then x = anim.current_position end
    end

    window:render_rect_filled(
        v2(x, strip.y + strip.h - Theme.metrics.selection_marker),
        v2(x + tab.w, strip.y + strip.h),
        Theme.color.accent(), Theme.radius.none)
end

function Shell:_draw_body(window, vm, bounds)
    if vm.empty then
        local activated, _, action_bounds = Widgets.empty_state(window, bounds, vm.empty)
        self._empty_action_bounds = action_bounds
        if activated and vm.empty.action_id and self._on_action then
            self._on_action(vm.empty.action_id, self)
        end
        return
    end
    self._empty_action_bounds = nil

    local spec = vm.panel
    if not spec then return end

    local ctx = { shell = self, state = self._state }
    local body = bounds

    if spec.split then
        local pane = Widgets.split_pane(window, bounds, {
            ratio = self._state:split_ratio(spec.split),
            axis = spec.split_axis,
        })
        if pane.dragging then
            local ratio = ShellState.ratio_from_pointer(bounds, window:get_mouse_pos(), spec.split_axis)
            if ratio then self._state:set_split_ratio(spec.split, ratio) end
        end
        ctx.split = { first = pane.first, second = pane.second, divider = pane.divider }
        body = pane.first
    end

    spec.render(window, body, ctx)
end

---Driven from `register_on_render_window_callback`.
function Shell:_on_render_window()
    if not self._state:is_visible() then return end
    local window = self._window
    if not window then return end          -- created in tick context, never here

    -- ONE view for the whole frame, taken before any input is read. A tab clicked this frame
    -- therefore takes effect on the next one. That single-frame lag is deliberate: re-reading the
    -- model after the switcher would leave the active marker pointing at the old tab while the
    -- new panel's body was already drawn beneath it, and an inconsistent frame is far more
    -- visible at 60Hz than a 16ms delay nobody can perceive.
    local vm = self._state:view()
    local origin = window:get_position()
    local size = window:get_size()

    local strip = { x = origin.x, y = origin.y, w = size.x, h = Theme.metrics.toolbar_height }
    local content = {
        x = origin.x + Theme.space.md,
        y = strip.y + strip.h + Theme.space.md,
        w = size.x - Theme.space.md * 2,
        h = size.y - strip.h - Theme.space.md * 2,
    }

    window:begin(
        (Enums and Enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS) or 0,
        true,
        Theme.elevation.base.fill(),
        Theme.elevation.base.border(),
        (Enums and Enums.window_enums.window_cross_visuals.BLUE_THEME) or 0,
        function()
            self:_draw_switcher(window, vm, strip)
            self:_draw_body(window, vm, content)
        end
    )

    -- Sylvannas draws the close cross itself, so the only signal that the operator used it is
    -- `is_being_shown` going false. Without this the model and the window disagree and the
    -- toggle verb appears to do nothing on the next press.
    if type(window.is_being_shown) == "function" and not window:is_being_shown() then
        self._state:hide()
        self._window_visible = false
    end
end

return Shell
