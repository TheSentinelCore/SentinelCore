local T = require("tests/TestUtil")

local function run()
    T.install_core_stub()

    local Init = require("init")
    local AstroUI = require("lib/AstroUI")
    local UIWindow = require("ui/window")
    local GrindMode = require("modes/GrindMode")
    local QuestMode = require("modes/QuestMode")
    local GatherMode = require("modes/GatherMode")
    local BgMode = require("modes/BgMode")

    T.assert_true(type(Init.initialize) == "function", "init.initialize missing")
    T.assert_true(type(Init.get_client) == "function", "init.get_client missing")
    T.assert_true(type(AstroUI.new) == "function", "AstroUI.new missing")
    T.assert_true(type(UIWindow.init) == "function", "UIWindow.init missing")

    local grind = GrindMode:new()
    T.assert_eq(grind:id(), "grind", "grind mode id mismatch")

    T.assert_true(QuestMode:new():can_enter({}) == false, "quest placeholder must be non-functional")
    T.assert_true(GatherMode:new():can_enter({}) == false, "gather placeholder must be non-functional")
    T.assert_true(BgMode:new():can_enter({}) == false, "bg placeholder must be non-functional")

    return {
        sc001_layout_loads = true,
    }
end

return { run = run }
