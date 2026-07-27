-- tests/ui/test_text_input_widget.lua
-- The key-capture text input's WIDGET half: drawing, focus, and the two undocumented calls.
--
-- WHY THE UNDOCUMENTED HALF IS PINNED FROM BOTH SIDES
-- --------------------------------------------------
-- `window:block_input_capture()` and `core.input.is_key_down(16)` are NOT in
-- `docs/SylvannasAPI/dev/api/ui-custom.md`. The only evidence either exists is a plugin in this
-- workspace that works in the injector (`SentinelNavClient/lib/AstroUI.lua:2397-2403`). So the
-- widget must type with them present AND still type with them absent, and both are asserted below.
--
-- `fake_window` is deliberately NOT given a `block_input_capture`: it type-checks its arguments
-- against `api/ui-custom.md`, and a permissive fake is exactly how 1,568 green offline cases once
-- preceded a shell that crashed every frame in the injector. The injector path is stubbed onto a
-- single window INSTANCE in the one test that needs it.

local TextInputState = require("ui/text_input_state")
local Widgets = require("ui/widgets")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 20, y = 40, w = 240, h = 30 }
local VK = TextInputState.VK

---The vk that types `char` on a US layout, with the shift flag it needs.
local function key_for(char)
    for vk, chars in pairs(TextInputState.CHAR_MAP) do
        if chars.lower == char then return { vk = vk, shift = false } end
        if chars.upper == char then return { vk = vk, shift = true } end
    end
    error("no virtual key produces '" .. tostring(char) .. "'")
end

local function keys_for(text)
    local events = {}
    for i = 1, #text do events[#events + 1] = key_for(text:sub(i, i)) end
    return events
end

local function focused_model(value)
    local model = TextInputState.new({ id = "search", value = value })
    model:focus()
    return model
end

-- ============================================================================
-- 1. Reading the live keyboard
-- ============================================================================

function M.test_collect_turns_pressed_keys_into_events()
    local pressed = { [string.byte("W")] = true, [VK.ENTER] = true }
    local events = TextInputState.collect({
        is_key_pressed = function(vk) return pressed[vk] == true end,
        is_key_down = function(vk) return vk == VK.SHIFT end,
    })
    T.assert_equal(#events, 2, "both pressed keys must be collected")
    for _, event in ipairs(events) do
        T.assert_true(event.shift, "is_key_down(16) must set shift on every event of the frame")
    end
end

function M.test_collect_degrades_when_is_key_down_is_absent()
    -- `is_key_down` is UNDOCUMENTED. Without it the field must still type in lower case rather
    -- than raise inside a render callback.
    local events = TextInputState.collect({
        is_key_pressed = function(vk) return vk == string.byte("A") end,
    })
    T.assert_equal(#events, 1)
    T.assert_false(events[1].shift, "an absent is_key_down reads as 'shift is not held'")
end

function M.test_collect_survives_a_raising_input_api()
    local events = TextInputState.collect({
        is_key_pressed = function() error("no keyboard") end,
        is_key_down = function() error("no keyboard") end,
    })
    T.assert_equal(#events, 0, "a raising input namespace is no keys, not a dead frame")
end

function M.test_collect_with_no_input_namespace_is_empty()
    T.assert_equal(#TextInputState.collect(nil), 0)
    T.assert_equal(#TextInputState.collect({}), 0, "no is_key_pressed means no keyboard")
end

function M.test_every_polled_key_is_one_the_model_understands()
    local VK_SET = {}
    for _, vk in pairs(VK) do VK_SET[vk] = true end
    for _, vk in ipairs(TextInputState.POLLED_KEYS) do
        T.assert_true(TextInputState.CHAR_MAP[vk] ~= nil or VK_SET[vk] == true,
            "vk " .. vk .. " is polled but apply_key does nothing with it")
    end
    T.assert_false(VK_SET[VK.SHIFT] and TextInputState.POLLED_KEYS[1] == VK.SHIFT,
        "shift is a modifier read with is_key_down, never an is_key_pressed event")
end

-- ============================================================================
-- 2. The widget half
-- ============================================================================

function M.test_the_widget_draws_the_placeholder_when_empty()
    local model = TextInputState.new({ value = "" })
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    Widgets.text_input(fake, BOUNDS, { model = model, placeholder = "Search quests..." })
    T.assert_true(fake:drew_text("Search quests..."),
        "an empty field must say what it is for")
end

function M.test_the_widget_draws_the_value_over_the_placeholder()
    local model = TextInputState.new({ value = "wolf" })
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    Widgets.text_input(fake, BOUNDS, { model = model, placeholder = "Search quests..." })
    T.assert_true(fake:drew_text("wolf"), "the value must be drawn")
    T.assert_false(fake:drew_text("Search quests..."),
        "the placeholder must not sit under a real value")
end

function M.test_clicking_the_widget_takes_focus()
    local model = TextInputState.new({ value = "" })
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    fake:click(BOUNDS)
    Widgets.text_input(fake, BOUNDS, { model = model, events = {} })
    T.assert_true(model.focused, "a click inside the rect focuses the field")
end

function M.test_the_widget_probes_hover_exactly_once()
    -- Widget rule 1 (widgets.lua header): a pointer that goes dead over a control is how a user
    -- concludes the panel hung.
    local model = TextInputState.new({ value = "" })
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    Widgets.text_input(fake, BOUNDS, { model = model, events = {} })
    T.assert_equal(#fake:hover_tests(), 1, "exactly one hover probe per frame")
end

function M.test_a_disabled_widget_never_probes_the_click()
    -- Widget rule 2: probing `is_rect_clicked` swallows the click from whatever is behind.
    local model = TextInputState.new({ value = "" })
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    fake:click(BOUNDS)
    Widgets.text_input(fake, BOUNDS, { model = model, disabled = true, events = {} })
    T.assert_equal(#fake:click_tests(), 0, "a disabled field consumes no click")
    T.assert_false(model.focused, "and takes no focus")
end

function M.test_a_disabled_widget_swallows_no_keys()
    local model = focused_model("abc")
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    Widgets.text_input(fake, BOUNDS, { model = model, disabled = true, events = keys_for("d") })
    T.assert_equal(model.buffer, "abc", "a disabled field must not capture the keyboard")
end

function M.test_the_widget_forwards_injected_keys_and_returns_the_command()
    local model = focused_model("")
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    local events = keys_for("wolf")
    events[#events + 1] = { vk = VK.ENTER }

    local result = Widgets.text_input(fake, BOUNDS, { model = model, events = events })
    T.assert_not_nil(result, "the widget returns the model's command, never the effect")
    T.assert_equal(result.kind, "submit")
    T.assert_equal(result.value, "wolf")
end

function M.test_an_unfocused_widget_ignores_injected_keys()
    local model = TextInputState.new({ value = "" })
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    Widgets.text_input(fake, BOUNDS, { model = model, events = keys_for("wolf") })
    T.assert_equal(model.buffer, "", "keys go to the focused field only")
end

function M.test_the_widget_polls_the_injected_input_namespace_when_no_events_are_given()
    local model = focused_model("")
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    local asked = {}
    Widgets.text_input(fake, BOUNDS, {
        model = model,
        input = {
            is_key_pressed = function(vk) asked[vk] = true return vk == string.byte("A") end,
            is_key_down = function() return false end,
        },
    })
    T.assert_equal(model.buffer, "a", "the live path and the injected path share apply_keys")
    T.assert_true(asked[VK.ENTER], "the poller must ask about Enter, not only characters")
end

-- ============================================================================
-- 3. The undocumented calls, both ways round
-- ============================================================================

function M.test_the_widget_blocks_input_capture_when_the_window_offers_it()
    -- `block_input_capture` is undocumented; this is the injector path
    -- (SentinelNavClient/lib/AstroUI.lua:2397). It is stubbed onto the INSTANCE rather than added
    -- to `fake_window`, which type-checks against `api/ui-custom.md` and must keep doing so.
    local model = focused_model("")
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    local blocked = 0
    fake.block_input_capture = function() blocked = blocked + 1 end

    Widgets.text_input(fake, BOUNDS, { model = model, events = keys_for("a") })
    T.assert_equal(blocked, 1, "a focused field must keep its keys out of the game")
    T.assert_equal(model.buffer, "a")
end

function M.test_the_widget_still_types_when_block_input_capture_is_absent()
    -- The fallback the design names. `fake_window` has no `block_input_capture`, so this is what
    -- runs if the undocumented method turns out not to exist (tasks.md 3.2 confirms live).
    local model = focused_model("")
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    T.assert_nil(rawget(fake, "block_input_capture"),
        "fake_window must not grow an undocumented method to make this pass")

    local ok, err = pcall(Widgets.text_input, fake, BOUNDS, { model = model, events = keys_for("a") })
    T.assert_true(ok, "an absent block_input_capture must not raise in a render callback: " .. tostring(err))
    T.assert_equal(model.buffer, "a", "the field still types without it")
end

function M.test_an_unfocused_field_never_blocks_input_capture()
    local model = TextInputState.new({ value = "" })
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    local blocked = 0
    fake.block_input_capture = function() blocked = blocked + 1 end

    Widgets.text_input(fake, BOUNDS, { model = model, events = {} })
    T.assert_equal(blocked, 0, "capturing the keyboard with no focus would break movement keys")
end

-- ============================================================================
-- 4. Structural guard
-- ============================================================================

function M.test_the_widget_without_a_model_draws_a_frame_and_refuses_the_keyboard()
    local fake = FakeWindow.new({ size = { x = 400, y = 200 } })
    local ok, result = pcall(Widgets.text_input, fake, BOUNDS, { events = {} })
    T.assert_true(ok, "a missing model must not raise on the render path: " .. tostring(result))
    T.assert_nil(result, "and must produce no command")
end

return M
