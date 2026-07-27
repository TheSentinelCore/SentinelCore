-- sentinel/ui/text_input_state.lua
-- The editable-buffer view-model behind `Widgets.text_input`.
--
-- Sylvannas has no text-entry widget. ADR 09b §1 lists `text_input` as available, but it is not in
-- `docs/SylvannasAPI/dev/api/ui-custom.md` and `widgets.lua::element_value` already probes for an
-- accessor it never finds -- which is why the Explorer's search box has been an untypeable
-- rectangle since it was drawn. The only way to type into this window is to read the keyboard, and
-- every decision that implies lives HERE, where an offline test can reach it (ADR 09b §2.1). The
-- widget half draws the buffer and forwards keys; it holds nothing.
--
-- `apply_key` takes `{ vk = <number>, shift = <boolean> }`. In the injector those come from polling
-- `core.input.is_key_pressed`; offline they are handed in literally. Both go through this one
-- function, so the offline test exercises the code the injector runs -- only the source of the
-- numbers differs.
--
-- Escape restores the COMMITTED value, not "": `focus()` snapshots it, Escape puts it back, Enter
-- promotes the buffer to it. A field that blanked itself on Escape would destroy an existing search
-- with the key people press to mean "leave this alone".

local TextInputState = {}
TextInputState.__index = TextInputState

-- ============================================================================
-- Virtual key codes
-- ============================================================================
-- Windows VK constants. Transcribed from the working in-repo consumer
-- (`SentinelNavClient/lib/AstroUI.lua:2400-2450`), which is the only evidence in this workspace of
-- what the injector actually delivers -- `core.input.is_key_pressed` is documented, but the codes
-- it answers to are not.

TextInputState.VK = {
    BACKSPACE = 8,
    ENTER     = 13,
    SHIFT     = 16,
    ESCAPE    = 27,
    SPACE     = 32,
    END       = 35,
    HOME      = 36,
    LEFT      = 37,
    RIGHT     = 39,
    DELETE    = 46,
}

---`vk -> { lower, upper }` for every key that produces a character. US layout, matching AstroUI.
local CHAR_MAP = {}
for vk = 65, 90 do
    CHAR_MAP[vk] = { lower = string.char(vk + 32), upper = string.char(vk) }
end
local DIGIT_SHIFT = {
    [48] = ")", [49] = "!", [50] = "@", [51] = "#", [52] = "$",
    [53] = "%", [54] = "^", [55] = "&", [56] = "*", [57] = "(",
}
for vk = 48, 57 do
    CHAR_MAP[vk] = { lower = string.char(vk), upper = DIGIT_SHIFT[vk] }
end
local SYMBOLS = {
    [32] = { " ", " " },   [186] = { ";", ":" },  [187] = { "=", "+" },  [188] = { ",", "<" },
    [189] = { "-", "_" },  [190] = { ".", ">" },  [191] = { "/", "?" },  [192] = { "`", "~" },
    [219] = { "[", "{" },  [220] = { "\\", "|" }, [221] = { "]", "}" },  [222] = { "'", "\"" },
}
for vk, pair in pairs(SYMBOLS) do
    CHAR_MAP[vk] = { lower = pair[1], upper = pair[2] }
end

TextInputState.CHAR_MAP = CHAR_MAP

TextInputState.DEFAULT_MAX_LENGTH = 128

-- ============================================================================
-- Construction
-- ============================================================================

---@param opts table|nil { id = string, value = string|nil, max_length = number|nil }
function TextInputState.new(opts)
    opts = opts or {}
    local value = tostring(opts.value or "")
    return setmetatable({
        id = tostring(opts.id or "text_input"),
        value = value,   -- the COMMITTED value; what the panel acts on
        buffer = value,  -- what is being typed; equals `value` while unfocused
        caret = #value,
        focused = false,
        max_length = tonumber(opts.max_length) or TextInputState.DEFAULT_MAX_LENGTH,
    }, TextInputState)
end

-- ============================================================================
-- Focus
-- ============================================================================

---Take focus and start editing from the committed value.
function TextInputState:focus()
    if self.focused then return end
    self.focused = true
    self.buffer = self.value
    self.caret = #self.buffer
end

---Release focus WITHOUT committing. The buffer goes back to the committed value, because a field
---that kept a half-typed string after the pointer moved away would show something the panel is not
---searching for.
function TextInputState:blur()
    self.focused = false
    self.buffer = self.value
    self.caret = #self.buffer
end

---Replace the committed value from outside (a Clear button, a reset). Never called from key input.
function TextInputState:set_value(value)
    value = tostring(value or "")
    self.value = value
    self.buffer = value
    self.caret = #value
end

-- ============================================================================
-- Key handling
-- ============================================================================

local function insert_char(self, ch)
    if #self.buffer >= self.max_length then return end
    self.buffer = self.buffer:sub(1, self.caret) .. ch .. self.buffer:sub(self.caret + 1)
    self.caret = self.caret + 1
end

---One key event against the buffer.
---
---Returns the RESULT of the key, never the effect: `nil` for an edit or a no-op, or a table the
---caller turns into a panel command. The widget cannot act on Enter itself -- it runs inside a
---render callback, and everything a submit leads to (an HTTP search) belongs on the tick.
---
---@param event table|nil { vk = number, shift = boolean|nil }
---@return table|nil result { kind = "submit"|"cancel", value = string }
function TextInputState:apply_key(event)
    if not self.focused then return nil end
    if type(event) ~= "table" then return nil end
    local vk = tonumber(event.vk)
    if not vk then return nil end

    local VK = TextInputState.VK

    if vk == VK.ESCAPE then
        local restored = self.value
        self:blur()
        return { kind = "cancel", value = restored }
    end

    if vk == VK.ENTER then
        local submitted = self.buffer
        self.value = submitted
        self.focused = false
        self.caret = #submitted
        return { kind = "submit", value = submitted }
    end

    if vk == VK.BACKSPACE then
        if self.caret > 0 then
            self.buffer = self.buffer:sub(1, self.caret - 1) .. self.buffer:sub(self.caret + 1)
            self.caret = self.caret - 1
        end
        return nil
    end

    if vk == VK.DELETE then
        if self.caret < #self.buffer then
            self.buffer = self.buffer:sub(1, self.caret) .. self.buffer:sub(self.caret + 2)
        end
        return nil
    end

    if vk == VK.LEFT  then self.caret = math.max(0, self.caret - 1) return nil end
    if vk == VK.RIGHT then self.caret = math.min(#self.buffer, self.caret + 1) return nil end
    if vk == VK.HOME  then self.caret = 0 return nil end
    if vk == VK.END   then self.caret = #self.buffer return nil end

    local chars = CHAR_MAP[vk]
    if chars then
        insert_char(self, event.shift and chars.upper or chars.lower)
    end
    return nil
end

---Feed a whole sequence, stopping at the first submit or cancel.
---
---A frame can only deliver one terminal key: everything after an Enter belongs to whatever took
---focus next, and applying it to a field that has already committed would type into the past.
---@param events table list of `{ vk, shift }`
---@return table|nil result the terminal result, if one fired
---@return number consumed how many events were applied
function TextInputState:apply_keys(events)
    for index, event in ipairs(events or {}) do
        local result = self:apply_key(event)
        if result then return result, index end
    end
    return nil, #(events or {})
end

-- ============================================================================
-- Reading the live keyboard
-- ============================================================================

---Every vk the widget has to ask about, derived from the two tables above rather than written out
---a third time, so the poller cannot drift away from what `apply_key` understands.
local POLLED_KEYS = {}
do
    local seen = { [TextInputState.VK.SHIFT] = true }  -- a modifier, read with is_key_down
    for _, vk in pairs(TextInputState.VK) do
        if not seen[vk] then seen[vk] = true; POLLED_KEYS[#POLLED_KEYS + 1] = vk end
    end
    for vk in pairs(CHAR_MAP) do
        if not seen[vk] then seen[vk] = true; POLLED_KEYS[#POLLED_KEYS + 1] = vk end
    end
    table.sort(POLLED_KEYS)
end
TextInputState.POLLED_KEYS = POLLED_KEYS

---Turn one frame of `core.input` into the same event list the offline tests hand to `apply_key`.
---
---`input` is passed in rather than read from `_G.core` so this stays a pure function of its
---argument and a test can drive it with a table. `is_key_down` is UNDOCUMENTED -- proven only by
---`SentinelNavClient/lib/AstroUI.lua:2403` -- so a missing one degrades to "shift is not held"
---(lower case still types) instead of raising and taking the whole frame down with it.
---@param input table|nil the `core.input` namespace
---@return table events list of `{ vk, shift }`
function TextInputState.collect(input)
    local events = {}
    if type(input) ~= "table" then return events end
    if type(input.is_key_pressed) ~= "function" then return events end

    local shift = false
    if type(input.is_key_down) == "function" then
        local ok, down = pcall(input.is_key_down, TextInputState.VK.SHIFT)
        shift = (ok and down) and true or false
    end

    for _, vk in ipairs(POLLED_KEYS) do
        local ok, pressed = pcall(input.is_key_pressed, vk)
        if ok and pressed then events[#events + 1] = { vk = vk, shift = shift } end
    end
    return events
end

-- ============================================================================
-- Projection
-- ============================================================================

---What the widget draws. `text` is the buffer while focused and the committed value otherwise, so
---an unfocused field can never show an edit the panel is not acting on.
---@return table { text, placeholder_shown, caret, focused }
function TextInputState:view()
    local text = self.focused and self.buffer or self.value
    return {
        text = text,
        placeholder_shown = text == "",
        caret = self.focused and math.min(self.caret, #text) or nil,
        focused = self.focused,
    }
end

return TextInputState
