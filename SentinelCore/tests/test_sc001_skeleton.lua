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
    local enter_ctx = {
        dependencies_ok = true,
        canonical_context = { map_id = 530, zone_id = 3518, area_id = 3520 },
    }

    local quest = QuestMode:new()
    local gather = GatherMode:new()
    local bg = BgMode:new()

    T.assert_true(quest:can_enter(enter_ctx) == true, "quest mode should be functional")
    T.assert_true(gather:can_enter(enter_ctx) == true, "gather mode should be functional")
    T.assert_true(bg:can_enter(enter_ctx) == true, "bg mode should be functional")

    local quest_def = quest:get_definition()
    T.assert_eq(quest_def.id, "quest", "quest mode definition id mismatch")
    T.assert_true(type(quest_def.phases) == "table" and #quest_def.phases > 0, "quest mode phases missing")
    T.assert_true(type(quest:get_objective_provider()) == "table", "quest objective provider missing")
    T.assert_true(type(gather:get_objective_provider()) == "table", "gather objective provider missing")
    T.assert_true(type(bg:get_objective_provider()) == "table", "bg objective provider missing")

    return {
        sc001_layout_loads = true,
    }
end

return { run = run }
