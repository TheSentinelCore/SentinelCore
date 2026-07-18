-- sentinel/ui/quest_authoring/init.lua
-- Quest Authoring IDE shell. Owns the application context, the compiler
-- service, and all panes; lays them out inside a Sylvannas window and renders
-- them every frame. Also wires hot-reload <-> the running ProfileExecutor.

local Context        = require("ui/quest_authoring/context")
local CompilerService = require("ui/quest_authoring/compiler_service")
local ProfileExecutor = require("modules/quest/profile_executor")
local SourceAST      = require("modules/quest/source_ast")
local Theme          = require("ui/quest_authoring/theme")

local ExplorerPane   = require("ui/quest_authoring/explorer_pane")
local PalettePane    = require("ui/quest_authoring/action_palette")
local MapPane        = require("ui/quest_authoring/map_pane")
local TimelinePane   = require("ui/quest_authoring/timeline_pane")
local PropertiesPane = require("ui/quest_authoring/properties_pane")
local ValidationPane = require("ui/quest_authoring/validation_pane")
local AnalyticsPane  = require("ui/quest_authoring/analytics_pane")
local HotReloadPane  = require("ui/quest_authoring/hot_reload")
local WorldSelPane   = require("ui/quest_authoring/world_selection")

local IDE = {}
IDE.__index = IDE

-- Adapt the real Sylvannas window to the conventions our panes use (scalar
-- coordinates for render_text / rect / hit-test helpers), while forwarding
-- every other method/field to the engine window with the engine window as
-- `self`. The engine expects vec2 pairs; panes sometimes pass vec2 directly
-- (via Panel helpers) and sometimes scalars (inline in panes), so the adapter
-- accepts both shapes.
local _adapter_cache = setmetatable({}, { __mode = "k" })  -- weak-key table keyed by real window

local function wrap_window(real)
  if real and _adapter_cache[real] then return _adapter_cache[real] end
  local v2 = Theme.vec2.new
  local font = 0
  local ok, enums = pcall(require, "enums")
  if ok and enums and enums.window_enums and enums.window_enums.font_id then
    font = enums.window_enums.font_id.FONT_SMALL or 0
  end

  -- rect drawing: Sylvannas API:
  --   render_rect_filled(min_vec2, max_vec2, color, rounding, [flags])
  --   render_rect(min_vec2, max_vec2, color, rounding, thickness, [flags])
  -- Pane code calls either:
  --   scalar:  w:render_rect(x, y, w, h, color, rounding, [thickness])
  --   vec2:    w:render_rect(v2_min, v2_max, color, rounding, [thickness])
  local function adapt_rect(method_name)
    return function(_self, a, b, c, d, e, f, ...)
      if type(a) == "table" then
        -- Vec2 path: (min, max, color, rounding, [thickness/flags], ...)
        return real[method_name](real, a, b, c, d or 0, e, f, ...)
      end
      -- Scalar path: (x, y, w, h, color, rounding, [thickness], ...)
      return real[method_name](real, v2(a, b), v2(a + c, b + d), e, f or 0, ...)
    end
  end
  -- hit tests: (x,y,w,h) OR (startV, endV)
  local function adapt_hit(method_name)
    return function(_self, a, b, c, d)
      if type(a) == "table" then
        return real[method_name](real, a, b)
      end
      return real[method_name](real, v2(a, b), v2(a + c, b + d))
    end
  end

  local adapter = {}
  setmetatable(adapter, {
    __index = function(_t, k)
      -- The engine window may only expose get_size(); panes read .width/.height.
      if k == "width" or k == "height" then
        local s = real:get_size()
        if s then return k == "width" and s.x or s.y end
      end
      -- Use adapter's wrapped methods first (they handle scalar/vec2 conversion).
      -- Use rawget to avoid re-triggering __index.
      local wrapped = rawget(adapter, k)
      if type(wrapped) == "function" then return wrapped end
      local v = real[k]
      if type(v) == "function" then
        return function(maybe_self, ...)
          -- Method syntax: w:method(args) passes adapter as first arg; skip it.
          if maybe_self == _t then return v(real, ...) end
          -- Function syntax: w.method(args) — no self arg.
          return v(real, maybe_self, ...)
        end
      end
      return v
    end,
  })
  adapter.render_text = function(_self, x, y, text_or_color, color_or_text)
    -- Support both pane convention (x, y, text, color) and engine convention (x, y, color, text)
    local text, color
    if type(text_or_color) == "table" and type(color_or_text) == "string" then
      -- Engine convention: (x, y, color, text)
      color, text = text_or_color, color_or_text
    else
      -- Pane convention: (x, y, text, color)
      text, color = text_or_color, color_or_text
    end
    real:render_text(font, v2(x, y), color, text)
  end
  adapter.render_rect_filled = adapt_rect("render_rect_filled")
  adapter.render_rect = adapt_rect("render_rect")
  adapter.is_rect_clicked = adapt_hit("is_rect_clicked")
  adapter.is_mouse_hovering_rect = adapt_hit("is_mouse_hovering_rect")
  adapter.is_mouse_hovering_rect_block_movement = adapt_hit("is_mouse_hovering_rect_block_movement")
  if real then _adapter_cache[real] = adapter end
  return adapter
end

function IDE.new()
    local self = setmetatable({}, IDE)
    self.ctx = Context.new()
    self.ctx.logError = function(msg) print("[QA-IDE] " .. tostring(msg)) end
    self.ctx._getTime = function()
        if os and os.clock then return os.clock() * 1000 end
        return 0
    end

    self.compiler = CompilerService.new()
    self:_build_sample_project()
    self:_wire_reload()
    self:_wire_world()
    self:_create_panes()
    return self
end

-- ---- Sample project so the IDE is usable without external files ----
function IDE:_build_sample_project()
    local proj = {
        name = "Sample Project",
        operations = {},
        blueprints = { QuestHub = { name = "QuestHub" } },
        variables = {},
    }
    proj.operations["Northshire Cleanup"] = {
        name = "Northshire Cleanup",
        actions = {
            { id = "Travel_1", action_type = "Travel", args = { target = { x = 0, y = 0, z = 0 } } },
            { id = "Pickup_1", action_type = "PickupQuest", args = { questId = 1 } },
            { id = "Kill_1",   action_type = "KillTarget", args = { count = 6 } },
            { id = "TurnIn_1", action_type = "TurnInQuest", args = { questId = 1 } },
        },
    }
    proj.operations["Goldshire Loop"] = {
        name = "Goldshire Loop",
        actions = {
            { id = "Travel_2", action_type = "Travel", args = { target = { x = 100, y = 50 } } },
            { id = "Vendor_1", action_type = "Vendor", args = {} },
            { id = "Repair_1", action_type = "Repair", args = {} },
        },
    }
    self.ctx:loadProject(proj)
end

-- Create a new empty project
function IDE:_new_project()
    local proj = {
        name = "Untitled Project",
        operations = {},
        blueprints = {},
        variables = {},
    }
    self.ctx.projectPath = nil
    self.ctx:loadProject(proj)
    print("[QA-IDE] New project created")
end

-- Load project dialog (simple - just tries common paths)
function IDE:_load_project_dialog()
    -- Try default project locations
    local paths = {
        "data/profiles/quests/ide_project.yaml",
        "data/profiles/quests/project.yaml",
        "data/profiles/quests/elwynn/project.yaml",
    }
    for _, path in ipairs(paths) do
        local ok, err = self.ctx:loadFromDisk(path)
        if ok then
            print("[QA-IDE] Loaded project from " .. path)
            return
        end
    end
    print("[QA-IDE] No project found in default locations")
end

-- ---- Hot reload wiring ----
-- Compile the current project (optionally re-parsing from disk via
-- SourceAST:parse_project) and push the result into the context, hot-swapping a
-- live executor if one is attached (Ticket 016).
function IDE:_recompile()
    local ctx = self.ctx
    -- Optionally re-parse the source project from disk (Gap #3 — real source).
    if ctx.projectPath then
        local ok, result = pcall(function()
            return SourceAST:parse_project(ctx.projectPath)
        end)
        if ok and result and result.ok and result.ast then
            ctx:loadProject(result.ast)
        elseif ok and result and not result.ok then
            if ctx.logError then
                ctx:logError("parse_project: " .. tostring(result.errors and result.errors[1] or "?"))
            end
        end
    end
    local res = self.compiler:compile(ctx.project)
    ctx:setCompileResult(res)
    if ctx._executor then
        local ok, err = pcall(function()
            ctx._executor:hotSwap(res.profile)
        end)
        if not ok and ctx.logError then
            ctx:logError("executor hotSwap: " .. tostring(err))
        end
    end
    return res
end

function IDE:_wire_reload()
    local self_ref = self
    self.ctx._reload_fn = function()
        self_ref:_recompile()
    end
end

-- Load a project from a directory on disk (SourceAST YAML model).
function IDE:loadProjectPath(path)
    self.ctx.projectPath = path
    return self:_recompile()
end

-- ---- World selection wiring (Gap #1) ----
-- Wires ctx._pick_fn / ctx._jump_fn / ctx._tryPickTarget to the live Sylvannas
-- input + object_manager. When picking is enabled, the IDE polls each frame for
-- a newly-targeted unit and captures it as ctx._pendingPick.
function IDE:_wire_world()
    local self_ref = self
    self._picking = false
    self._lastPickTargetId = nil
    self.ctx._pick_fn = function(enabled) self_ref._picking = enabled end
    self.ctx._jump_fn = function(target) self_ref:_jump_to(target) end
    self.ctx._tryPickTarget = function() return self_ref:_capture_target() end
end

function IDE:_capture_target()
    if not core or not core.object_manager then return nil end
    local ok, tgt = pcall(function()
        if core.object_manager.get_target then
            return core.object_manager:get_target()
        end
        return nil
    end)
    if ok and tgt and tgt.guid then
        local pk = {
            guid = tgt.guid,
            name = tgt.name or tgt.unit_name or "target",
            type = tgt.type or "unit",
            x = tgt.position and tgt.position.x,
            y = tgt.position and tgt.position.y,
            z = tgt.position and tgt.position.z,
        }
        self.ctx._pendingPick = pk
        return pk
    end
    return nil
end

function IDE:_jump_to(target)
    if not target then return end
    local nav = self._app and self._app._nav_adapter
    if nav and nav.move_to then
        pcall(function() nav:move_to(target.x, target.y, target.z) end)
    elseif core and core.input and core.input.move_to then
        pcall(function() core.input.move_to(target.x, target.y, target.z) end)
    end
end

function IDE:_poll_world_pick()
    if not self._picking then return end
    if not core or not core.object_manager then return end
    local ok, tgt = pcall(function()
        if core.object_manager.get_target then return core.object_manager:get_target() end
        return nil
    end)
    if ok and tgt and tgt.guid then
        if self._lastPickTargetId ~= tgt.guid then
            self._lastPickTargetId = tgt.guid
            self:_capture_target()
            self._picking = false
            if self.ctx.logError then
                self.ctx:logError("picked target: " .. tostring(tgt.name or tgt.guid))
            end
        end
    elseif ok and not tgt then
        self._lastPickTargetId = nil
    end
end

-- ---- Execute flow (Gap #5) ----
-- Build a ProfileExecutor from the compiled profile and start it. Requires the
-- app handle (set via IDE:setApp) so we can resolve blackboard / engine /
-- nav_adapter / event bus from the running SentinelCore runtime.
function IDE:setApp(app)
    self._app = app
end

function IDE:start()
    local app = self._app
    if not app then return false, "no app handle" end
    local bb = app.get_blackboard and app:get_blackboard() or nil
    local eb = app.get_event_bus and app:get_event_bus() or nil
    local engine = app.get_module and app:get_module("quest") or nil
    local nav = app._nav_adapter
    if not bb or not engine then return false, "missing blackboard/engine" end
    local res = self:_recompile()
    if not res or not res.ok then return false, "compile failed" end
    local exec = ProfileExecutor.new(bb, engine, nav, eb)
    local ok, err = pcall(function() exec:loadProfile(res.profile) end)
    if not ok then return false, tostring(err) end
    exec:start()
    self._executor = exec
    self.ctx._executor = exec
    return true
end

function IDE:stop()
    if self._executor then
        pcall(function() self._executor:stop() end)
        self._executor = nil
        self.ctx._executor = nil
    end
end

-- Attach a live ProfileExecutor (called by the quest module when it starts one).
function IDE:attachExecutor(executor)
    self.ctx._executor = executor
end

-- ---- Pane construction ----
function IDE:_create_panes()
    local c = self.ctx
    self.panes = {
        explorer   = ExplorerPane.new(c),
        palette    = PalettePane.new(c),
        map        = MapPane.new(c),
        timeline   = TimelinePane.new(c),
        properties = PropertiesPane.new(c),
        validation = ValidationPane.new(c),
        analytics  = AnalyticsPane.new(c),
        hotreload  = HotReloadPane.new(c),
        worldsel   = WorldSelPane.new(c),
    }
end

-- ---- Per-frame render ----
function IDE:render(window)
    if not window then return end
    local w = wrap_window(window)
    self._window = w
    local W, H = w.width, w.height

    -- Poll for an in-world target capture (Gap #1).
    self:_poll_world_pick()

    -- Toolbar
    w:render_rect_filled(0, 0, W, 22, Theme.colors.bg_alt)
    w:render_text(8, 5, "Quest Authoring IDE", Theme.colors.text)
    
    -- New Project
    if w:is_rect_clicked(160, 3, 70, 16) then
        self:_new_project()
    end
    w:render_rect_filled(160, 3, 70, 16, Theme.colors.button)
    w:render_text(164, 5, "New", Theme.colors.text)

    -- Load Project
    if w:is_rect_clicked(234, 3, 70, 16) then
        self:_load_project_dialog()
    end
    w:render_rect_filled(234, 3, 70, 16, Theme.colors.button)
    w:render_text(238, 5, "Load", Theme.colors.text)

    if w:is_rect_clicked(310, 3, 80, 16) then
        local res = self:_recompile()
    end
    w:render_rect_filled(310, 3, 80, 16, Theme.colors.button)
    w:render_text(316, 5, "Compile", Theme.colors.text)

    local running = self._executor ~= nil
    if w:is_rect_clicked(396, 3, 64, 16) then self:start() end
    w:render_rect_filled(396, 3, 64, 16, running and Theme.colors.border or Theme.colors.green)
    w:render_text(402, 5, "Run", Theme.colors.text)

    if w:is_rect_clicked(466, 3, 64, 16) then self:stop() end
    w:render_rect_filled(466, 3, 64, 16, running and Theme.colors.red or Theme.colors.border)
    w:render_text(472, 5, "Stop", Theme.colors.text)

    local dirtyTxt = self.ctx:isDirty() and " [unsaved*]" or " [saved]"
    w:render_text(540, 5, dirtyTxt, self.ctx:isDirty() and Theme.colors.warning or Theme.colors.text_dim)

    -- Save button
    if self.ctx:isDirty() then
        if w:is_rect_clicked(618, 3, 56, 16) then
            local path = self.ctx.projectPath or "data/profiles/quests/ide_project.yaml"
            local ok, err = self.ctx:saveToDisk(path)
            if not ok then
                print("[QA-IDE] Save failed: " .. tostring(err))
            else
                print("[QA-IDE] Saved to " .. path)
            end
        end
        w:render_rect_filled(618, 3, 56, 16, Theme.colors.accent)
        w:render_text(626, 5, "Save", Theme.colors.text)
    end

    -- Layout regions (below toolbar)
    local top = 26
    local colW = 230
    local rightW = 280
    local bottomH = 180

    local midX = colW
    local midW = W - colW - rightW
    local botY = H - bottomH

    -- Left column: explorer
    self:_draw(self.panes.explorer, 0, top, colW, botY - top)
    -- Middle: timeline (top) + map (bottom)
    self:_draw(self.panes.timeline, midX, top, midW, (botY - top) / 2)
    self:_draw(self.panes.map, midX, top + (botY - top) / 2, midW, (botY - top) / 2)
    -- Right column: properties / validation / analytics / hotreload / worldsel
    local rx = W - rightW
    self:_draw(self.panes.properties, rx, top, rightW, 150)
    self:_draw(self.panes.validation, rx, top + 154, rightW, 150)
    self:_draw(self.panes.analytics, rx, top + 308, rightW, 120)
    self:_draw(self.panes.hotreload, rx, top + 432, rightW, 70)
    self:_draw(self.panes.worldsel, rx, top + 506, rightW, bottomH - 506)
    -- Palette floats at bottom-left over the explorer tail
    self:_draw(self.panes.palette, 0, botY, colW, bottomH)
end

function IDE:_draw(pane, x, y, ww, hh)
    pane:begin(self._window, x, y, ww, hh)
    pane:draw()
end

-- Convenience used by external harness: wrap each frame with the real window.
function IDE:update(window)
    self._window = window
    self:render(window)
end

return IDE
