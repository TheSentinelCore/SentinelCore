-- tests/ui/test_text_input.lua
-- The key-capture text input's VIEW-MODEL: the buffer, the caret, and what each key means.
--
-- Sylvannas has no text-entry widget, so this control reads the keyboard itself. Every decision
-- that implies lives in `ui/text_input_state` rather than in the widget, because a decision taken
-- inside a render callback is a decision no offline test can reach (ADR 09b §2.1). This suite is
-- that half. The widget half -- drawing, focus, and the two UNDOCUMENTED calls it leans on -- is
-- `test_text_input_widget.lua`, registered straight after this one so a broken buffer fails here
-- first rather than as a widget that appears not to draw.

local TextInputState = require("ui/text_input_state")
local T = require("tests/test_util")

local M = {}

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
-- 1. The view-model: construction and focus
-- ============================================================================

function M.test_new_starts_unfocused_with_the_value_in_the_buffer()
    local model = TextInputState.new({ id = "search", value = "wolf" })
    T.assert_equal(model.value, "wolf", "the committed value is what it was constructed with")
    T.assert_equal(model.buffer, "wolf", "the buffer mirrors the value while unfocused")
    T.assert_equal(model.caret, 4, "the caret sits after the last character")
    T.assert_false(model.focused, "a field does not start focused")
end

function M.test_focus_starts_editing_from_the_committed_value()
    local model = TextInputState.new({ value = "abc" })
    model.buffer = "stale"
    model:focus()
    T.assert_true(model.focused)
    T.assert_equal(model.buffer, "abc", "focus reloads the buffer from the committed value")
    T.assert_equal(model.caret, 3)
end

function M.test_keys_are_ignored_while_unfocused()
    local model = TextInputState.new({ value = "" })
    model:apply_keys(keys_for("wolf"))
    T.assert_equal(model.buffer, "", "an unfocused field must not capture the keyboard")
end

-- ============================================================================
-- 2. The spec's scenarios
-- ============================================================================

function M.test_typing_edits_the_buffer_and_enter_submits()
    -- SPEC: "Typing edits the buffer" -- w, o, l, f then Enter yields "wolf" and a submit.
    local model = focused_model("")
    local result = model:apply_keys(keys_for("wolf"))
    T.assert_nil(result, "plain characters produce no command")
    T.assert_equal(model.buffer, "wolf", "the four keys build the buffer in order")

    local submit = model:apply_key({ vk = VK.ENTER })
    T.assert_not_nil(submit, "Enter must produce a command")
    T.assert_equal(submit.kind, "submit")
    T.assert_equal(submit.value, "wolf", "the submitted value is the buffer")
    T.assert_equal(model.value, "wolf", "Enter promotes the buffer to the committed value")
    T.assert_false(model.focused, "Enter releases focus")
end

function M.test_escape_cancels_and_restores_the_prior_value()
    -- SPEC: "Escape cancels" -- original "abc", edited to "abcd", Escape reverts and does not submit.
    local model = focused_model("abc")
    model:apply_key(key_for("d"))
    T.assert_equal(model.buffer, "abcd", "the edit landed before the cancel")

    local result = model:apply_key({ vk = VK.ESCAPE })
    T.assert_not_nil(result, "Escape must report itself")
    T.assert_equal(result.kind, "cancel", "Escape must NOT submit")
    T.assert_equal(model.buffer, "abc", "the buffer reverts to the prior value")
    T.assert_equal(model.value, "abc", "the committed value was never touched")
    T.assert_false(model.focused, "Escape releases focus")
end

function M.test_a_sequence_stops_at_the_first_terminal_key()
    -- Everything after Enter belongs to whatever took focus next.
    local model = focused_model("")
    local events = keys_for("ab")
    events[#events + 1] = { vk = VK.ENTER }
    events[#events + 1] = key_for("z")

    local result, consumed = model:apply_keys(events)
    T.assert_equal(result.kind, "submit")
    T.assert_equal(result.value, "ab")
    T.assert_equal(consumed, 3, "the key after Enter must not be applied")
    T.assert_equal(model.value, "ab", "'z' must not have reached the committed value")
end

-- ============================================================================
-- 3. Editing keys
-- ============================================================================

function M.test_backspace_deletes_before_the_caret()
    local model = focused_model("")
    model:apply_keys(keys_for("wolf"))
    model:apply_key({ vk = VK.BACKSPACE })
    T.assert_equal(model.buffer, "wol")
    T.assert_equal(model.caret, 3)
end

function M.test_backspace_at_the_start_is_a_no_op()
    local model = focused_model("ab")
    model:apply_key({ vk = VK.HOME })
    model:apply_key({ vk = VK.BACKSPACE })
    T.assert_equal(model.buffer, "ab", "there is nothing before the caret to delete")
    T.assert_equal(model.caret, 0, "the caret must not go negative")
end

function M.test_caret_movement_inserts_in_the_middle()
    local model = focused_model("")
    model:apply_keys(keys_for("wof"))
    model:apply_key({ vk = VK.LEFT })
    model:apply_key(key_for("l"))
    T.assert_equal(model.buffer, "wolf", "the character lands at the caret, not at the end")
    T.assert_equal(model.caret, 3)
end

function M.test_delete_removes_after_the_caret()
    local model = focused_model("")
    model:apply_keys(keys_for("wolf"))
    model:apply_key({ vk = VK.HOME })
    model:apply_key({ vk = VK.DELETE })
    T.assert_equal(model.buffer, "olf")
    T.assert_equal(model.caret, 0, "delete does not move the caret")
end

function M.test_home_and_end_bound_the_caret()
    local model = focused_model("wolf")
    model:apply_key({ vk = VK.HOME })
    T.assert_equal(model.caret, 0)
    model:apply_key({ vk = VK.END })
    T.assert_equal(model.caret, 4)
    model:apply_key({ vk = VK.RIGHT })
    T.assert_equal(model.caret, 4, "the caret must not run past the buffer")
end

function M.test_shift_types_the_upper_variant()
    local model = focused_model("")
    model:apply_key({ vk = string.byte("W"), shift = true })
    model:apply_key({ vk = string.byte("W"), shift = false })
    T.assert_equal(model.buffer, "Ww", "shift selects the upper mapping for the same vk")
end

function M.test_max_length_stops_insertion_without_raising()
    local model = TextInputState.new({ value = "", max_length = 3 })
    model:focus()
    model:apply_keys(keys_for("wolfs"))
    T.assert_equal(model.buffer, "wol", "insertion stops at max_length")
end

function M.test_an_unmapped_key_changes_nothing()
    local model = focused_model("ab")
    model:apply_key({ vk = 112 })  -- F1
    T.assert_equal(model.buffer, "ab", "a key with no character and no meaning is inert")
end

function M.test_blur_discards_the_edit()
    local model = focused_model("abc")
    model:apply_key(key_for("d"))
    model:blur()
    T.assert_equal(model.buffer, "abc", "losing focus must not leave a half-typed string on screen")
    T.assert_equal(model.value, "abc")
end

-- ============================================================================
-- 4. Structural guard
-- ============================================================================

function M.test_the_view_model_constructs_no_menu_element_and_does_no_io()
    local handle = assert(io.open("sentinel/ui/text_input_state.lua", "r"))
    local source = handle:read("*a")
    handle:close()
    source = source:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\n]*", " ")
    for _, forbidden in ipairs({ "core%.menu%.", "http_get", "http_post",
                                 "read_data_file", "write_data_file", "object_manager" }) do
        T.assert_nil(source:find(forbidden), "text_input_state reaches for " .. forbidden)
    end
    T.assert_nil(source:find("_G%.core"),
        "the view-model must take its input namespace as an argument, not read the global")
end

return M
