-- sentinel/ui/shell_state.lua
-- The IDE shell's view-model (ADR 09b §2.1).
--
-- Every decision the shell makes is made here: which panels exist, which one is active, what the
-- switcher shows, whether a pane is replaced by an empty state, where a dragged divider lands,
-- whether a keypress is an edge, and whether anything is allowed to move. `shell.lua` reads the
-- result and paints it.
--
-- The line is drawn here rather than at the widget boundary because `register_on_render_window_
-- callback` cannot be entered outside the injector. A branch written on the far side of it is a
-- branch nobody can execute in a test, which is how `runner_state.lua` came to exist and why ADR
-- 09b §2.1 makes the same split mandatory for the IDE. `test_shell_state.lua` scans this file for
-- the Sylvannas API prefix to keep the line where it is — which is why no comment below spells
-- one out either.
--
-- Nothing in here knows what a panel CONTAINS. U3-U7 hand over a spec and get a slot; a shell
-- that knew a panel's implementation would have to be edited by every unit that follows it.

local ShellState = {}
ShellState.__index = ShellState

-- ============================================================================
-- Declared topology
-- ============================================================================

--- The tab order from ADR 09b §4, with Runner first because "the bot running correctly matters
--- more often than authoring does".
---
--- This is a SLOT MAP, not a panel list. Nothing appears in the switcher because it is named
--- here; a panel appears because it registered, and an id absent from this table registers
--- perfectly well — it simply sorts after every declared slot. The distinction is the whole
--- point: a shell that took this list as its inventory would need an edit from every later unit,
--- which is precisely the collision the ownership split in ADR 09b §6 exists to prevent.
ShellState.TAB_ORDER = { "runner", "explorer", "graph", "properties", "database" }

--- The layout slots that survive an injection. Ghost sliders must be constructed at module scope
--- (ADR 09b §2.2), so the set of persisted dividers is necessarily finite and fixed; a panel may
--- hold as many transient ratios as it likes, but only these two come back after a reload.
ShellState.PERSISTED_SPLITS = { "primary", "secondary" }

ShellState.DEFAULT_SPLIT_RATIO = 0.32
-- A divider dragged flush to an edge leaves a pane too small to contain the divider's own hit
-- target, and there is then nothing left on screen to drag it back with. The clamp is the only
-- exit from that state.
ShellState.MIN_SPLIT_RATIO = 0.15
ShellState.MAX_SPLIT_RATIO = 0.85

ShellState.DEFAULT_POSITION = { x = 240, y = 180 }
ShellState.DEFAULT_SIZE = { x = 980, y = 640 }

-- Copy for the two states a user actually meets before anything exists. ADR 09b §5.5: an empty
-- pane that instructs beats a blank one, "especially while the corpus is empty" — which is the
-- literal condition of this project today.
local EMPTY_NO_PANELS = {
    title = "No panels loaded",
    message = "The IDE shell is running, but no panel has registered itself yet.",
}
local EMPTY_NO_CAMPAIGN = {
    title = "No campaign open",
    message = "Record one, or open an existing route.",
    action_label = "Start recording",
    action_id = "start_recording",
}

-- ============================================================================
-- Internals
-- ============================================================================

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function clamp_ratio(value)
    return clamp(value, ShellState.MIN_SPLIT_RATIO, ShellState.MAX_SPLIT_RATIO)
end

---`runner` -> `Runner`. A panel that supplies no title still has to be nameable in the switcher;
---falling back to the raw id would put a lowercase word among Title Case ones.
local function titleize(id)
    return id:sub(1, 1):upper() .. id:sub(2)
end

---The slot `id` occupies in the declared tab order, or nil if it declares none.
function ShellState.slot_index(id)
    for index, name in ipairs(ShellState.TAB_ORDER) do
        if name == id then return index end
    end
    return nil
end

-- Unlisted panels sort after every declared slot, in registration order. The offset is larger
-- than the declared order can ever grow to, so adding a slot cannot reorder them.
local UNLISTED_BASE = 1000

-- ============================================================================
-- Construction
-- ============================================================================

---@param opts table|nil { position, size }
function ShellState.new(opts)
    opts = opts or {}
    local self = setmetatable({}, ShellState)

    self._panels = {}          -- id -> spec
    self._order = {}           -- ordered ids, rebuilt on every registration
    self._sequence = 0         -- registration counter, the tie-break within a sort key
    self._active = nil
    -- Set by `restore` before any panel has had a chance to register. Without it the operator's
    -- persisted tab is overwritten by whichever unit happens to `require` first.
    self._pending_active = nil

    self._visible = false
    self._campaign = nil
    self._splits = {}
    self._edges = {}
    self._in_combat = false
    self._marker_x = nil

    self._position = { x = opts.position and opts.position.x or ShellState.DEFAULT_POSITION.x,
                       y = opts.position and opts.position.y or ShellState.DEFAULT_POSITION.y }
    self._size = { x = opts.size and opts.size.x or ShellState.DEFAULT_SIZE.x,
                   y = opts.size and opts.size.y or ShellState.DEFAULT_SIZE.y }

    return self
end

-- ============================================================================
-- Panel registry
-- ============================================================================

local function sort_key(self, spec)
    if spec.order then return spec.order end
    local slot = ShellState.slot_index(spec.id)
    if slot then return slot end
    return UNLISTED_BASE + spec.sequence
end

function ShellState:_reorder()
    local ids = {}
    for id in pairs(self._panels) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local ka, kb = sort_key(self, self._panels[a]), sort_key(self, self._panels[b])
        if ka ~= kb then return ka < kb end
        -- Registration order is the tie-break, so two panels claiming the same slot land in a
        -- stable arrangement instead of one that depends on `pairs` iteration order.
        return self._panels[a].sequence < self._panels[b].sequence
    end)
    self._order = ids
end

---Register a panel. This is the entire contract between the shell and U3-U7.
---
---@param spec table { id, render, title?, badge?, order?, split?, split_axis?, requires_campaign? }
---@return boolean ok, string|nil reason
function ShellState:register_panel(spec)
    if type(spec) ~= "table" then return false, "a panel spec must be a table" end
    if type(spec.id) ~= "string" or spec.id == "" then
        return false, "a panel needs a non-empty string id"
    end
    if type(spec.render) ~= "function" then
        -- Refused now rather than at the first frame the panel is selected: inside a render
        -- callback the only symptom of a missing render function is a blank pane.
        return false, "panel '" .. spec.id .. "' needs a render function"
    end

    self._sequence = self._sequence + 1
    -- Re-registration REPLACES. A plugin reload re-runs every unit's registration, and appending
    -- would grow the switcher by one tab per reload.
    self._panels[spec.id] = {
        id = spec.id,
        title = spec.title or titleize(spec.id),
        render = spec.render,
        badge = spec.badge,
        order = spec.order,
        split = spec.split,
        split_axis = spec.split_axis,
        requires_campaign = spec.requires_campaign and true or false,
        sequence = self._sequence,
    }
    self:_reorder()

    if self._pending_active == spec.id then
        self._active = spec.id
        self._pending_active = nil
    elseif self._active == nil then
        self._active = self._order[1]
    end

    return true
end

function ShellState:panel(id) return self._panels[id] end
function ShellState:active_id() return self._active end
function ShellState:active_panel() return self._active and self._panels[self._active] or nil end

---The switcher, as data. `shell.lua` turns this into rects and never computes it.
function ShellState:tabs()
    local out = {}
    for index, id in ipairs(self._order) do
        local spec = self._panels[id]
        out[index] = {
            id = id, title = spec.title, badge = spec.badge,
            active = (id == self._active), index = index,
        }
    end
    return out
end

---@return boolean changed
function ShellState:activate(id)
    local spec = self._panels[id]
    if not spec then return false end
    -- An explicit choice retires the restore. Otherwise a panel whose unit was removed would keep
    -- claiming the switcher every time it is late to register.
    self._pending_active = nil
    if self._active == id then return false end
    self._active = id
    return true
end

function ShellState:activate_index(index)
    local id = self._order[index]
    if not id then return false end
    return self:activate(id)
end

-- ============================================================================
-- Visibility
-- ============================================================================

function ShellState:is_visible() return self._visible end
function ShellState:show() self._visible = true; return true end
function ShellState:hide() self._visible = false; return false end

---@return boolean the new visibility
function ShellState:toggle()
    self._visible = not self._visible
    return self._visible
end

-- ============================================================================
-- Campaign and empty states
-- ============================================================================

function ShellState:campaign() return self._campaign end
function ShellState:set_campaign(name) self._campaign = name end

---The pane that replaces the active panel's body, or nil when the body should draw.
---
---Only panels that DECLARE `requires_campaign` are replaced. The Runner is useful with no
---campaign at all — it runs compiled profiles — and blanking it would hide a live run behind an
---authoring prompt.
function ShellState:empty_state()
    if #self._order == 0 then return EMPTY_NO_PANELS end
    local spec = self:active_panel()
    if spec and spec.requires_campaign and not self._campaign then return EMPTY_NO_CAMPAIGN end
    return nil
end

-- ============================================================================
-- Splits
-- ============================================================================

function ShellState:split_ratio(key)
    local value = self._splits[key]
    if value == nil then return ShellState.DEFAULT_SPLIT_RATIO end
    return value
end

---@return number the value actually stored, after clamping
function ShellState:set_split_ratio(key, value)
    local clamped = clamp_ratio(tonumber(value) or ShellState.DEFAULT_SPLIT_RATIO)
    self._splits[key] = clamped
    return clamped
end

---Where a dragged divider lands, as a ratio of `bounds` along `axis`.
---Static and pure: the shell supplies the rect and the pointer, both of which only exist inside a
---render callback, and gets back a number this file's tests can pin.
---@return number|nil
function ShellState.ratio_from_pointer(bounds, mouse, axis)
    if type(bounds) ~= "table" or type(mouse) ~= "table" then return nil end
    local total = (axis == "y") and bounds.h or bounds.w
    if not total or total <= 0 then return nil end
    local offset = (axis == "y") and (mouse.y - bounds.y) or (mouse.x - bounds.x)
    return clamp_ratio(offset / total)
end

-- ============================================================================
-- Layout persistence
-- ============================================================================

function ShellState:set_window_geometry(position, size)
    if position then
        self._position = { x = position.x or self._position.x, y = position.y or self._position.y }
    end
    if size then
        self._size = { x = size.x or self._size.x, y = size.y or self._size.y }
    end
end

---A snapshot of everything that must outlive an injection.
---
---The active panel travels as a SLOT INDEX rather than an id because a `slider_int` carries a
---number and nothing else. The index is into the declared tab order, which is fixed by ADR 09b
---§4, so it stays meaningful across releases; a panel outside that order does not persist its
---selection, which is the honest cost of the only persistence mechanism available.
function ShellState:layout()
    local splits = {}
    for _, key in ipairs(ShellState.PERSISTED_SPLITS) do splits[key] = self:split_ratio(key) end
    return {
        position = { x = self._position.x, y = self._position.y },
        size = { x = self._size.x, y = self._size.y },
        active_slot = self._active and ShellState.slot_index(self._active) or nil,
        splits = splits,
    }
end

function ShellState:restore(snapshot)
    if type(snapshot) ~= "table" then return false end
    self:set_window_geometry(snapshot.position, snapshot.size)

    if type(snapshot.splits) == "table" then
        for key, value in pairs(snapshot.splits) do
            if tonumber(value) then self:set_split_ratio(key, value) end
        end
    end

    local slot = tonumber(snapshot.active_slot)
    local id = slot and ShellState.TAB_ORDER[slot] or nil
    if id then
        if self._panels[id] then
            self._active = id
        else
            -- Restore runs at load, before any unit has registered. The choice is held until the
            -- panel exists rather than discarded, or the persisted tab could never be honoured.
            self._pending_active = id
        end
    end
    return true
end

---Whether two snapshots differ. The shell writes ghost sliders only when this says yes: writing
---every tick is cheap, but it means nothing ever compares, and nothing then notices that the
---geometry being written is stale.
function ShellState.layout_differs(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return true end
    if a.active_slot ~= b.active_slot then return true end
    for _, axis in ipairs({ "x", "y" }) do
        if (a.position or {})[axis] ~= (b.position or {})[axis] then return true end
        if (a.size or {})[axis] ~= (b.size or {})[axis] then return true end
    end
    for _, key in ipairs(ShellState.PERSISTED_SPLITS) do
        if (a.splits or {})[key] ~= (b.splits or {})[key] then return true end
    end
    return false
end

-- ============================================================================
-- Input edges
-- ============================================================================

---True on the frame `down` first becomes true for `name`.
---
---The injector's key predicate and `keybind:get_state()` are both LEVEL signals, polled every
---tick. Acting on the level would toggle the window on every frame the key is held, which reads
---as the IDE flickering rather than as a held key.
function ShellState:edge(name, down)
    down = down and true or false
    local was = self._edges[name] and true or false
    self._edges[name] = down
    return down and not was
end

-- ============================================================================
-- Motion (ADR 09b §5.7)
-- ============================================================================

function ShellState:set_in_combat(value) self._in_combat = value and true or false end
function ShellState:in_combat() return self._in_combat end

---Where the active-tab marker is coming from, where it is going, and whether the trip is worth
---animating.
---
---"Motion only to explain" — a marker sliding to the tab you just clicked explains the switch; a
---marker sliding while you are being hit explains nothing and costs attention, so combat
---suppresses it outright. A marker that has not moved never animates, or the transition would
---re-run every frame the pointer sits still.
---@return table { from, to, animate }
function ShellState:marker_transition(target_x)
    local from = self._marker_x
    self._marker_x = target_x
    local animate = (from ~= nil) and (from ~= target_x) and not self._in_combat
    return { from = from or target_x, to = target_x, animate = animate }
end

-- ============================================================================
-- The whole projection
-- ============================================================================

---Everything `shell.lua` needs for one frame, resolved in one place so the render layer has
---nothing left to decide.
function ShellState:view()
    local spec = self:active_panel()
    return {
        visible = self._visible,
        tabs = self:tabs(),
        active_id = self._active,
        panel = spec,
        empty = self:empty_state(),
        campaign = self._campaign,
        in_combat = self._in_combat,
    }
end

return ShellState
