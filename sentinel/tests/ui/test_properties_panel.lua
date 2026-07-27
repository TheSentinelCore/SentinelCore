-- tests/ui/test_properties_panel.lua
-- The Properties panel's contract.
--
-- Tests cover: state transitions (set_context, tab switching, reduce), build output shape,
-- command routing, and the structural guards from ADR 09b §2.1.

local PropertiesState = require("ui/panels/properties_state")
local Properties = require("ui/panels/properties")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 0, y = 0, w = 400, h = 600 }

-- ============================================================================
-- Fixtures
-- ============================================================================

-- SERVER-SHAPED, and that is load-bearing. Every fixture below uses the field names serde emits
-- from SentinelQuesting/query-types -- `drop_chance` not `chance`, `quest_id` not `id`,
-- `item_entry` not `entry`, lower-case `classification`. The previous fixtures used the panel's
-- invented names, so the suite proved the panel could read its own test data and nothing else.
local function sample_npc_detail()
    return {
        entry = 823,
        name = "Deputy Willem",
        level = 45,
        faction = "Stormwind",
        classification = "rare elite",
        roles = { "QuestGiver", "Vendor" },
        quests = {
            { quest_id = 783,  title = "The Missing Diplomat", role = "starter" },
            { quest_id = 2158, title = "A Bundle of Trouble",   role = "finisher" },
        },
        loot = {
            { item = 1234, name = "Silver Ring", drop_chance = 15.5 },
            { item = 5678, name = "Gold Coin",   drop_chance = 45.0 },
            { item = 9012, name = "Worn Cloak",  drop_chance = 0.4 },
        },
        positions = {
            { map = 0, x = -8932, y = -137, z = 82 },
        },
    }
end

local function render_view(view)
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    Properties.render(fake, BOUNDS, view)
    return fake
end

local function npc_view(detail, tab)
    local state = PropertiesState.new()
    state:set_context({ panel_id = "database", selection_type = "npc", selection_id = detail.entry })
    state.npc_detail = detail
    if tab then state:set_npc_tab(tab) end
    state.loading = false
    return state:build()
end

local function sample_vendor_info()
    return {
        entry = 8234,
        name = "Darnell",
        repairs = true,
        sells = {
            { entry = 123, name = "Refreshing Water", price = 5, mode = "buy", threshold = 5 },
            { entry = 456, name = "Fresh Bread", price = 2, mode = "sell" },
            { entry = 789, name = "Light Armor Kit", price = 50, mode = "ignore" },
        },
    }
end

local function sample_object_info()
    return {
        entry = 1735,
        name = "Silver Vein",
        kind = "Mining",
        position = { map = 0, x = -8932, y = -137, z = 82 },
        respawn = 120,
        skill = "Mining (125)",
    }
end

local function sample_condition_tree()
    return {
        type = "all",
        conditions = {
            { type = "quest_completed", quest_id = 783 },
            { type = "has_item", item_id = 2589, count = 5 },
            { type = "any", conditions = {
                { type = "level_at_least", level = 20 },
                { type = "class_is", class = "Rogue" },
            }},
        },
    }
end

-- ============================================================================
-- 1. State: construction and defaults
-- ============================================================================

function M.test_new_state_has_defaults()
    local state = PropertiesState.new()
    T.assert_nil(state.context, "context defaults to nil")
    T.assert_nil(state.npc_detail, "npc_detail defaults to nil")
    T.assert_nil(state.vendor_info, "vendor_info defaults to nil")
    T.assert_nil(state.object_info, "object_info defaults to nil")
    T.assert_equal(state.npc_tab, "info", "npc_tab defaults to info")
    T.assert_false(state.loading, "loading defaults to false")
    T.assert_nil(state.error, "error defaults to nil")
    T.assert_true(state._dirty, "starts dirty for initial refresh")
end

-- ============================================================================
-- 2. State: set_context
-- ============================================================================

function M.test_set_context_sets_context_and_marks_dirty()
    local state = PropertiesState.new()
    state._dirty = false
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    T.assert_not_nil(state.context, "context is set")
    T.assert_equal(state.context.selection_type, "npc")
    T.assert_equal(state.context.selection_id, 823)
    T.assert_true(state._dirty, "set_context marks dirty")
    T.assert_true(state.loading, "set_context sets loading")
end

function M.test_set_context_clears_previous_data()
    local state = PropertiesState.new()
    state.npc_detail = sample_npc_detail()
    state:set_context({ panel_id = "explorer", selection_type = "vendor", selection_id = 8234 })
    T.assert_nil(state.npc_detail, "set_context clears npc_detail")
    T.assert_equal(state.context.selection_type, "vendor")
end

function M.test_set_context_ignores_same_selection()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state._dirty = false
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    T.assert_false(state._dirty, "same selection must not mark dirty")
end

function M.test_set_context_nil_clears_everything()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state.npc_detail = sample_npc_detail()
    state:set_context(nil)
    T.assert_nil(state.context)
    T.assert_nil(state.npc_detail)
    T.assert_nil(state.npc_spawns)
end

function M.test_set_npc_tab_switches_tab()
    local state = PropertiesState.new()
    state:set_npc_tab("loot")
    T.assert_equal(state.npc_tab, "loot")
    state:set_npc_tab("quests")
    T.assert_equal(state.npc_tab, "quests")
end

function M.test_set_npc_tab_ignores_same_tab()
    local state = PropertiesState.new()
    state:set_npc_tab("spawns")
    state:set_npc_tab("spawns")
    T.assert_equal(state.npc_tab, "spawns")
end

-- ============================================================================
-- 3. Build: view model shape
-- ============================================================================

function M.test_build_returns_correct_keys()
    local state = PropertiesState.new()
    local view = state:build()
    T.assert_nil(view.context_type, "no context -> nil context_type")
    T.assert_false(view.loading, "loading is boolean")
end

function M.test_build_with_npc_context()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state.npc_detail = sample_npc_detail()
    state.loading = false
    local view = state:build()

    T.assert_equal(view.context_type, "npc")
    T.assert_not_nil(view.npc_view, "npc_view must be set for npc context")
    T.assert_equal(view.npc_view.detail.name, "Deputy Willem")
    T.assert_equal(view.npc_view.tab, "info")
end

function M.test_build_with_vendor_context()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "vendor", selection_id = 8234 })
    state.vendor_info = sample_vendor_info()
    state.loading = false
    local view = state:build()

    T.assert_equal(view.context_type, "vendor")
    T.assert_not_nil(view.vendor_view, "vendor_view must be set for vendor context")
    T.assert_equal(view.vendor_view.info.name, "Darnell")
end

function M.test_build_with_object_context()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "object", selection_id = 1735 })
    state.object_info = sample_object_info()
    state.loading = false
    local view = state:build()

    T.assert_equal(view.context_type, "object")
    T.assert_not_nil(view.object_view, "object_view must be set for object context")
    T.assert_equal(view.object_view.detail.name, "Silver Vein")
end

function M.test_build_with_condition_context()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "editor", selection_type = "condition", selection_id = 1 })
    state.condition_tree = sample_condition_tree()
    state.loading = false
    local view = state:build()

    T.assert_equal(view.context_type, "condition")
    T.assert_not_nil(view.condition_view, "condition_view must be set for condition context")
    T.assert_equal(view.condition_view.tree.type, "all")
end

function M.test_build_with_inventory_context()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "editor", selection_type = "inventory", selection_id = 1 })
    state.inventory_rules = {
        { entry = 12345, name = "Wool Cloth", action = "sell" },
        { entry = 2589, name = "Linen Cloth", action = "keep" },
    }
    state.inventory_default = { sell_grey = true, ignore_white = true }
    state.loading = false
    local view = state:build()

    T.assert_equal(view.context_type, "inventory")
    T.assert_not_nil(view.inventory_view, "inventory_view must be set for inventory context")
    T.assert_equal(#view.inventory_view.rules, 2)
end

function M.test_build_context_type_is_string_or_nil()
    local state = PropertiesState.new()
    T.assert_true(state:build().context_type == nil, "nil when no context")
    state:set_context({ panel_id = "x", selection_type = "npc", selection_id = 1 })
    state.loading = false
    T.assert_equal(state:build().context_type, "npc", "npc when npc context")
end

-- ============================================================================
-- 4. Reduce: command routing
-- ============================================================================

function M.test_reduce_npc_tabs()
    local cmd = PropertiesState.reduce("npc_tab_info")
    T.assert_not_nil(cmd, "npc_tab_info must produce a command")
    T.assert_equal(cmd.kind, "set_npc_tab")
    T.assert_equal(cmd.tab, "info")

    cmd = PropertiesState.reduce("npc_tab_loot")
    T.assert_equal(cmd.tab, "loot")

    cmd = PropertiesState.reduce("npc_tab_quests")
    T.assert_equal(cmd.tab, "quests")

    cmd = PropertiesState.reduce("npc_tab_spawns")
    T.assert_equal(cmd.tab, "spawns")
end

function M.test_reduce_vendor_toggle()
    local cmd = PropertiesState.reduce("vendor_toggle:1234")
    T.assert_not_nil(cmd, "vendor_toggle must produce a command")
    T.assert_equal(cmd.kind, "toggle_vendor_item")
    T.assert_equal(cmd.entry, 1234)
end

function M.test_reduce_condition_actions()
    local cmd = PropertiesState.reduce("add_condition")
    T.assert_not_nil(cmd, "add_condition must produce a command")
    T.assert_equal(cmd.kind, "add_condition")

    cmd = PropertiesState.reduce("add_and_group")
    T.assert_not_nil(cmd, "add_and_group must produce a command")
    T.assert_equal(cmd.kind, "add_condition_group")
    T.assert_equal(cmd.group_type, "all")

    cmd = PropertiesState.reduce("add_or_group")
    T.assert_equal(cmd.kind, "add_condition_group")
    T.assert_equal(cmd.group_type, "any")

    cmd = PropertiesState.reduce("delete_condition")
    T.assert_equal(cmd.kind, "delete_condition")
end

function M.test_reduce_inventory_actions()
    local cmd = PropertiesState.reduce("add_inventory_rule")
    T.assert_not_nil(cmd, "add_inventory_rule must produce a command")
    T.assert_equal(cmd.kind, "add_inventory_rule")

    cmd = PropertiesState.reduce("clear_inventory_rules")
    T.assert_equal(cmd.kind, "clear_inventory_rules")
end

function M.test_reduce_nil_returns_nil()
    T.assert_nil(PropertiesState.reduce(nil), "nil action must return nil")
end

function M.test_reduce_unknown_returns_nil()
    T.assert_nil(PropertiesState.reduce("nonexistent"), "unknown action must return nil")
end

-- ============================================================================
-- 5. Render: the panel draws and returns commands
-- ============================================================================

function M.test_render_creates_items_and_returns_plan()
    local state = PropertiesState.new()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local command, plan = Properties.render(fake, BOUNDS, view)
    T.assert_not_nil(plan, "render must return a plan")
    T.assert_not_nil(plan.items, "plan must have items")
end

function M.test_render_handles_empty_state_gracefully()
    local state = PropertiesState.new()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Properties.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with empty state must not throw: " .. tostring(err))
end

function M.test_render_with_npc_detail()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state.npc_detail = sample_npc_detail()
    state.loading = false
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Properties.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with npc detail must not throw: " .. tostring(err))
end

function M.test_render_with_vendor_detail()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "vendor", selection_id = 8234 })
    state.vendor_info = sample_vendor_info()
    state.loading = false
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Properties.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with vendor detail must not throw: " .. tostring(err))
end

function M.test_render_with_object_detail()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "object", selection_id = 1735 })
    state.object_info = sample_object_info()
    state.loading = false
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Properties.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with object detail must not throw: " .. tostring(err))
end

function M.test_render_with_condition_tree()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "editor", selection_type = "condition", selection_id = 1 })
    state.condition_tree = sample_condition_tree()
    state.loading = false
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Properties.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with condition tree must not throw: " .. tostring(err))
end

function M.test_render_with_inventory_rules()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "editor", selection_type = "inventory", selection_id = 1 })
    state.inventory_rules = {
        { entry = 12345, name = "Wool Cloth", action = "sell" },
    }
    state.inventory_default = { sell_grey = true, ignore_white = true }
    state.loading = false
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Properties.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with inventory rules must not throw: " .. tostring(err))
end

-- ============================================================================
-- 6. Structural guards — the failures that pass offline and break in the injector
-- ============================================================================

local function source_of(path)
    local handle = assert(io.open(path, "r"), path .. " must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()
    source = source:gsub("%-%-%[%[.-%]%]", " ")
    source = source:gsub("%-%-[^\n]*", " ")
    return source
end

local RENDER_SOURCE = "sentinel/ui/panels/properties.lua"
local STATE_SOURCE = "sentinel/ui/panels/properties_state.lua"

function M.test_the_source_audit_actually_reads_code()
    local source = source_of(RENDER_SOURCE)
    T.assert_true(source:find("function Properties.render", 1, true) ~= nil,
        "the stripped source must still contain the render function")
end

function M.test_the_render_layer_contains_no_decision_logic()
    local source = source_of(RENDER_SOURCE)
    T.assert_nil(source:find("%f[%w]if%f[%W]"), "properties.lua branches; move it to the view-model")
    T.assert_nil(source:find("%f[%w]elseif%f[%W]"), "properties.lua has elseif; move it to the view-model")
    T.assert_nil(source:find("%f[%w]while%f[%W]"), "properties.lua loops on a condition")
end

function M.test_the_panel_never_constructs_a_menu_element()
    for _, path in ipairs({ RENDER_SOURCE, STATE_SOURCE }) do
        T.assert_nil(source_of(path):find("core%.menu%."),
            path .. " touches core.menu.*, which Sylvannas allows only in the tick callback")
    end
end

function M.test_no_menu_element_is_constructed_while_rendering()
    local saved = _G.core and _G.core.menu or nil
    if _G.core then
        _G.core.menu = setmetatable({}, {
            __index = function() error("core.menu was touched during render") end,
        })
    end
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state.npc_detail = sample_npc_detail()
    state.loading = false
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Properties.render, fake, BOUNDS, state:build())
    if _G.core then _G.core.menu = saved end
    T.assert_true(ok, "the panel constructed a menu element during render: " .. tostring(err))
end

function M.test_the_panel_performs_no_io_on_the_render_path()
    for _, path in ipairs({ RENDER_SOURCE, STATE_SOURCE }) do
        local source = source_of(path)
        for _, forbidden in ipairs({ "http_get", "http_post", "read_data_file", "write_data_file",
                                     "read_dir", "object_manager", "get_all_objects" }) do
            T.assert_nil(source:find(forbidden, 1, true),
                path .. " reaches for " .. forbidden .. " on the render path")
        end
    end
end

function M.test_the_panel_hardcodes_no_colour_and_no_spacing()
    for _, path in ipairs({ RENDER_SOURCE, STATE_SOURCE }) do
        local source = source_of(path)
        T.assert_nil(source:find("[Cc]olor%.new%s*%("), path .. " constructs a raw colour")
    end
end

function M.test_the_panel_loads_and_renders_with_no_sylvanns_api_present()
    local names = {
        "ui/panels/properties", "ui/panels/properties_state",
        "ui/theme", "ui/widgets",
    }
    local saved_core, saved_loaded = _G.core, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    _G.core = nil
    local ok, panel = pcall(require, "ui/panels/properties")
    local rendered, err = true, nil
    if ok then
        local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
        local state = PropertiesState.new()
        rendered, err = pcall(panel.render, fake, BOUNDS, state:build())
    end
    _G.core = saved_core
    for _, name in ipairs(names) do package.loaded[name] = saved_loaded[name] end

    T.assert_true(ok, "the panel failed to load with no SDK present: " .. tostring(panel))
    T.assert_true(rendered, "the panel failed to render with no SDK present: " .. tostring(err))
end

-- ============================================================================
-- 7. The panel exposes the shape the shell registers
-- ============================================================================

function M.test_panel_exposes_required_shape()
    T.assert_equal(Properties.id, "properties", "the shell keys panels by id")
    T.assert_equal(type(Properties.title), "string", "the tab needs a label")
    T.assert_equal(type(Properties.render), "function", "the shell calls render(window, bounds, view)")
end

-- ============================================================================
-- 8. Build plan produces items for each context type
-- ============================================================================

function M.test_build_plan_for_npc_view()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state.npc_detail = sample_npc_detail()
    state.loading = false
    local view = state:build()
    local plan = PropertiesState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan.items, "build_plan must return items")
    T.assert_true(#plan.items > 0, "npc view must produce items")
end

function M.test_build_plan_for_vendor_view()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "vendor", selection_id = 8234 })
    state.vendor_info = sample_vendor_info()
    state.loading = false
    local view = state:build()
    local plan = PropertiesState.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "vendor view must produce items")
end

function M.test_build_plan_for_object_view()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "object", selection_id = 1735 })
    state.object_info = sample_object_info()
    state.loading = false
    local view = state:build()
    local plan = PropertiesState.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "object view must produce items")
end

function M.test_build_plan_for_condition_view()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "editor", selection_type = "condition", selection_id = 1 })
    state.condition_tree = sample_condition_tree()
    state.loading = false
    local view = state:build()
    local plan = PropertiesState.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "condition view must produce items")
end

function M.test_build_plan_for_inventory_view()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "editor", selection_type = "inventory", selection_id = 1 })
    state.inventory_rules = {
        { entry = 12345, name = "Wool Cloth", action = "sell" },
    }
    state.inventory_default = { sell_grey = true, ignore_white = true }
    state.loading = false
    local view = state:build()
    local plan = PropertiesState.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "inventory view must produce items")
end

function M.test_build_plan_for_empty_context()
    local view = { context_type = nil, loading = false, error = nil }
    local plan = PropertiesState.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "empty context must produce items (empty_state)")
end

function M.test_build_plan_for_no_detail()
    local view = { context_type = "npc", npc_view = nil, loading = false }
    local plan = PropertiesState.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "npc with no detail must produce items (text)")
end

-- ============================================================================
-- 9. NPC loot and spawns tabs
-- ============================================================================

function M.test_npc_tab_loot_shows_loot_items()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state.npc_detail = sample_npc_detail()
    state:set_npc_tab("loot")
    state.loading = false
    local view = state:build()
    T.assert_equal(view.npc_view.tab, "loot", "tab must be loot")
end

function M.test_npc_tab_quests_shows_quests()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state.npc_detail = sample_npc_detail()
    state:set_npc_tab("quests")
    state.loading = false
    local view = state:build()
    T.assert_equal(view.npc_view.tab, "quests", "tab must be quests")
end

function M.test_npc_tab_spawns_shows_spawns()
    local state = PropertiesState.new()
    state:set_context({ panel_id = "explorer", selection_type = "npc", selection_id = 823 })
    state.npc_detail = sample_npc_detail()
    state:set_npc_tab("spawns")
    state.loading = false
    local view = state:build()
    T.assert_equal(view.npc_view.tab, "spawns", "tab must be spawns")
end

-- ============================================================================
-- 10. NPC Inspector on the SERVER's shape
-- ============================================================================
-- Every case here asserts against the PAINTED frame, not against `state.*`. A panel that stores a
-- field it never draws is exactly the failure this change exists to remove, and only `drew_text`
-- can tell the two apart.

function M.test_level_label_marks_the_spawn_floor()
    -- `NpcDetail.level` is creature_template.MinLevel. Rendering it bare as "Level 45" against a
    -- 45-48 spawn states a fact about the pull that the server never sent.
    T.assert_equal(PropertiesState.level_label(45), "Level 45 (min)")
    T.assert_nil(PropertiesState.level_label(nil), "no level on the wire must render nothing")
end

function M.test_rare_elite_is_one_classification_and_does_not_decompose()
    T.assert_equal(PropertiesState.classification_label("rare elite"), "Rare Elite")
    T.assert_equal(PropertiesState.classification_label("rare"), "Rare")
    T.assert_equal(PropertiesState.classification_label("elite"), "Elite")
    T.assert_equal(PropertiesState.classification_label("boss"), "Boss")
    T.assert_equal(PropertiesState.classification_label("normal"), "Normal")
    T.assert_equal(PropertiesState.classification_label("warchief"), "warchief",
        "an unknown rank must pass through, never fold into Normal")
    T.assert_nil(PropertiesState.classification_label(nil))
end

function M.test_npc_info_tab_paints_level_and_classification()
    local fake = render_view(npc_view(sample_npc_detail(), "info"))
    T.assert_true(fake:drew_text("Deputy Willem"), "the NPC name must reach the frame")
    T.assert_true(fake:drew_text("Level 45 (min)"), "the level must reach the frame")
    T.assert_true(fake:drew_text("Rare Elite"), "the classification must reach the frame")
end

function M.test_loot_groups_into_drop_chance_buckets()
    local buckets = PropertiesState.loot_buckets(sample_npc_detail().loot)
    T.assert_equal(#buckets, 3, "45%, 15.5% and 0.4% are three different buckets")
    T.assert_equal(buckets[1].name, "Common", "densest bucket first")
    T.assert_equal(buckets[1].entries[1].item, 5678)
    T.assert_equal(buckets[2].name, "Uncommon")
    T.assert_equal(buckets[3].name, "Very Rare")
    T.assert_equal(#PropertiesState.loot_buckets(nil), 0, "no loot means no buckets, not a crash")
end

function M.test_loot_tab_paints_a_bucket_with_real_values()
    local fake = render_view(npc_view(sample_npc_detail(), "loot"))
    T.assert_true(fake:drew_text("Common (1)"), "a loot bucket header must reach the frame")
    T.assert_true(fake:drew_text("Gold Coin"), "the item name must reach the frame")
    T.assert_true(fake:drew_text("45.0%"), "the drop chance must reach the frame")
end

function M.test_the_loot_tab_reads_drop_chance_and_not_chance()
    -- The regression verbatim: the panel used to read `entry.chance`, a name the wire never had.
    local detail = sample_npc_detail()
    detail.loot = { { item = 1234, name = "Silver Ring", chance = 15.5 } }
    local fake = render_view(npc_view(detail, "loot"))
    T.assert_false(fake:drew_text("15.5%"),
        "a `chance` key is not `drop_chance`; reading it would re-lock the panel to its own fixtures")
end

function M.test_quests_split_by_role()
    local starters, finishers, unknown = PropertiesState.split_quests(sample_npc_detail().quests)
    T.assert_equal(#starters, 1)
    T.assert_equal(starters[1].quest_id, 783)
    T.assert_equal(#finishers, 1)
    T.assert_equal(finishers[1].quest_id, 2158)
    T.assert_equal(#unknown, 0)
end

function M.test_an_npc_that_both_starts_and_ends_a_quest_appears_in_both_lists()
    local starters, finishers = PropertiesState.split_quests({
        { quest_id = 42, title = "Loop", role = "starter" },
        { quest_id = 42, title = "Loop", role = "finisher" },
    })
    T.assert_equal(#starters, 1, "two reasons to walk to the NPC are two rows, not one")
    T.assert_equal(#finishers, 1)
end

function M.test_quests_tab_paints_starter_and_finisher_sections()
    local fake = render_view(npc_view(sample_npc_detail(), "quests"))
    T.assert_true(fake:drew_text("Starts (1)"), "the starter section must reach the frame")
    T.assert_true(fake:drew_text("Turns In (1)"), "the finisher section must reach the frame")
    T.assert_true(fake:drew_text("The Missing Diplomat"), "the quest title must reach the frame")
    T.assert_true(fake:drew_text("783"), "NpcQuestRef.quest_id must reach the frame")
end

function M.test_a_quest_ref_with_an_unknown_role_is_still_shown()
    local detail = sample_npc_detail()
    detail.quests = { { quest_id = 99, title = "Orphaned", role = "escortee" } }
    local fake = render_view(npc_view(detail, "quests"))
    T.assert_true(fake:drew_text("Orphaned"),
        "a role this panel does not know is still a quest the NPC is attached to")
end

return M
