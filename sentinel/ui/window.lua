-- sentinel/ui/window.lua
-- Quest Authoring IDE entry point.
-- Owns the Sylvannas engine window and drives the in-game Quest Authoring IDE
-- (ui.quest_authoring.init). This is the single UI surface for the quest
-- system; the old tabbed quest/dashboard UI has been removed.

local IDE = require("ui.quest_authoring")
local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")

local Window = {}

local _initialized = false
local _app = nil
local _ide = nil
local _window = nil
local _window_epoch = 0

function Window.init(app)
    if _initialized then return end
    _app = app

    -- Build the IDE (sample project + compiler + panes).
    _ide = IDE.new()

    -- Create the engine window once.
    _window_epoch = _window_epoch + 1
    _window = core.menu.window("Sentinel Quest Authoring##" .. _window_epoch)
    _window:set_initial_position(vec2.new(100, 100))
    _window:set_initial_size(vec2.new(1000, 700))

    _initialized = true
    print("[QuestAuthoring UI] Initialized")
end

function Window.shutdown()
    _initialized = false
    _ide = nil
    _window = nil
    _app = nil
end

-- Per-frame logic. The IDE's panes (incl. hot-reload auto mode) do their work
-- during render, so there is nothing to tick here.
function Window.on_update()
    if not _initialized then return end
end

-- Reserved (engine window is rendered via on_render_window).
function Window.on_render()
    if not _initialized then return end
end

-- Render into the engine window. The engine calls our render_callback while
-- the window is open; we hand the engine window to the IDE, which adapts the
-- engine's (font, vec2, ...) drawing API to the panes' (x, y, ...) convention.
function Window.on_render_window()
    if not _initialized or not _window then return end
    local ok, err = pcall(function()
        _window:begin(
            enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS,
            true,
            color.new(14, 16, 20, 240),
            color.new(52, 60, 72, 200),
            enums.window_enums.window_cross_visuals.DEFAULT,
            enums.window_enums.window_behaviour_flags.NO_SCROLLBAR,
            function()
                _ide:render(_window)
            end
        )
    end)
    if not ok then
        print("[QuestAuthoring UI] render error: " .. tostring(err))
    end
end

-- Reserved (no in-engine menu widgets for the authoring IDE).
function Window.on_menu_render()
    if not _initialized then return end
end

-- The authoring IDE is not a SentinelUI object; return nil so callers that
-- expected the old UI simply no-op.
function Window.get_menu()
    return nil
end

function Window.get_ui()
    return nil
end

function Window.reload_ui()
    if _initialized then
        Window.shutdown()
    end
    if _app then
        Window.init(_app)
    end
    return _initialized
end

return Window
