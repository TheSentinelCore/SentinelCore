-- sentinel/ui/panels/graph_state.lua
-- The Graph panel's view-model for the campaign graph editor with Smart Waypoint Editor,
-- Behavior Nodes, and Combat Area Editor (Phase 3, PR-3a/3b/3c).
--
-- All decision logic lives here; `graph.lua` only renders whatever `build()` returns.
--
-- Design system: shares the Runner panel's vocabulary via `ui/panel_layout.lua`
-- (spacing, control sizes, empty states, alert banners, accessibility glyphs). Node colours
-- are theme tokens, not hex literals; node icons are single-byte accessibility glyphs.

local AsyncSlot = require("ui/async_slot")
local TextInputState = require("ui/text_input_state")
local Theme = require("ui/theme")
local PanelLayout = require("ui/panel_layout")

local GraphState = {}
GraphState.__index = GraphState

-- ============================================================================
-- Node type metadata — labels, theme token, icon glyph, default intent
-- ============================================================================

local NODE_TYPES = {
    -- Node colours are theme tokens, not hex literals. `icon` is a single-byte accessibility glyph;
    -- it must be unique within the palette so the panel remains readable in greyscale or for a
    -- colour-blind operator.
    { type = "questing.Travel",         label = "Travel",        icon = "T",
      token = "info",
      default_intent = { destination = "", x = 0, y = 0, z = 0, tolerance = 5, allow_flight = false, wait_time = 0 } },
    -- Intents use platform entity references (`{ref = "kind:id", label = ""}`) per ADR 09a §1.2,
    -- because the resolver/task registry expects `quest`/`from`/`to`/`target`/`object` refs, not raw
    -- numeric ids. `npc_entry` and `quest_id` fields are no longer read by the resolver.
    { type = "questing.AcceptQuest",    label = "AcceptQuest",   icon = "A",
      token = "success",
      default_intent = { quest = { ref = "quest:0", label = "" },
                         from = { ref = "npc:0", label = "" }, optional = false } },
    { type = "questing.Kill",           label = "Kill",          icon = "K",
      token = "danger",
      default_intent = { target = { ref = "npc:0", label = "" },
                         count = 1, loot = false, ignore_elites = false } },
    -- The resolver registers this as `questing.TurnIn`, not `questing.TurnInQuest`.
    { type = "questing.TurnIn",         label = "TurnInQuest",   icon = "Q",
      token = "warning",
      default_intent = { quest = { ref = "quest:0", label = "" },
                         to = { ref = "npc:0", label = "" }, choose_reward = 0, optional = false } },
    -- The resolver registers this as `questing.Collect`. It interacts with a gameobject.
    { type = "questing.Collect",        label = "Collect",       icon = "L",
      token = "warning",
      default_intent = { object = { ref = "object:0", label = "" }, count = 1 } },
    { type = "questing.Wait",           label = "Wait",          icon = "W",
      token = "text_muted",
      default_intent = { duration = 5 } },
    { type = "questing.Vendor",         label = "Vendor",        icon = "V",
      token = "accent",
      default_intent = { npc_entry = 0, sell_grey = true, repair = false, min_free_slots = 5 } },
    { type = "questing.Train",          label = "Train",         icon = "N",
      token = "info",
      default_intent = { npc_entry = 0, spells = {} } },
    { type = "questing.Repair",         label = "Repair",        icon = "R",
      token = "warning",
      default_intent = { npc_entry = 0 } },
    { type = "questing.Flight",         label = "Flight",        icon = "F",
      token = "info",
      default_intent = { npc_entry = 0, destination = "" } },
    { type = "questing.InteractNpc",    label = "Interact",      icon = "I",
      token = "accent",
      default_intent = { npc_entry = 0, gossip = "" } },
    { type = "questing.UseItem",        label = "UseItem",       icon = "U",
      token = "accent",
      default_intent = { item = 0, target_entry = 0 } },
    { type = "questing.Mailbox",        label = "Mailbox",       icon = "M",
      token = "text_muted",
      default_intent = { npc_entry = 0 } },
    { type = "questing.Hearth",         label = "Hearth",        icon = "H",
      token = "danger",
      default_intent = { innkeeper_entry = 0, destination = "" } },
    { type = "questing.Escort",         label = "Escort",        icon = "E",
      token = "warning",
      default_intent = { npc_entry = 0, timeout = 120 } },
    { type = "questing.Patrol",         label = "Patrol",        icon = "P",
      token = "success",
      default_intent = { waypoints = {}, loop = false } },
    { type = "questing.Condition",      label = "Condition",     icon = "C",
      token = "success",
      default_intent = { condition_type = "", value = "" } },
    { type = "questing.Comment",        label = "Comment",       icon = "#",
      token = "text_muted",
      default_intent = { text = "" } },
    { type = "questing.Grind",          label = "Grind",         icon = "G",
      token = "danger",
      default_intent = { targets = {}, polygon = { x = 0, y = 0, z = 0, radius = 50 }, loot = false } },
    { type = "questing.Bank",           label = "Bank",          icon = "B",
      token = "text_muted",
      default_intent = { npc_entry = 0 } },
    { type = "questing.LearnFlightPath", label = "LearnFlightPath", icon = ">",
      token = "info",
      default_intent = { npc_entry = 0 } },
}

local NODE_TYPE_INDEX = {}
for _, nt in ipairs(NODE_TYPES) do
    NODE_TYPE_INDEX[nt.type] = nt
end

-- ============================================================================
-- Construction
-- ============================================================================

function GraphState.new(opts)
    opts = opts or {}
    local state = setmetatable({
        campaign_name = nil,
        graph_name = nil,
        -- The editor's id for the graph a write lands in. A campaign can hold several; this panel
        -- edits the first, and every mutation has to name it because the editor addresses nodes by
        -- `(campaign, graph_id, node_id)` and answers "Graph not found" without it.
        graph_id = nil,

        -- The campaign chooser, which is all there IS before a campaign is open.
        campaigns = {},        -- CampaignSummary[] from GET /editor/campaigns
        campaigns_loaded = false,

        -- Campaign data
        nodes = {},     -- { id, type, intent, resolved, context }[]
        edges = {},     -- { id, from, to, guard? }[]

        -- Selection
        selected_node = nil,  -- node id string
        selected_edge = nil,
        expanded = {},        -- { [node_id] = true }

        -- Waypoint editing
        waypoint_mode = false,
        current_position = nil,

        -- Escort recording
        escort_mode = false,
        escort_timeline = {},
        escort_start_time = nil,

        -- Combat area (per-node)
        combat_areas = {},    -- { [node_id] = ... }

        -- Filters
        filter_type = nil,

        -- Validation (F19). `nil` and `{}` are different answers: nothing has been validated yet
        -- versus the editor found nothing wrong, and an operator acts differently on each.
        diagnostics = nil,
        compile_message = nil,

        -- The one intent field being edited, if any: { node_id, field }.
        editing = nil,

        -- Loading / error
        loading = false,
        error = nil,
        _dirty = true,
    }, GraphState)

    -- The name a new campaign is created under. On the state, not in the widget, for the reason
    -- every buffer in this tree is: a buffer owned by a render callback is a buffer no offline test
    -- can read (ADR 09b §2.1).
    state.name_input = TextInputState.new({ id = "graph_campaign_name", value = "", max_length = 64 })
    state.edit_input = TextInputState.new({ id = "graph_intent_value", value = "", max_length = 128 })

    -- Graph was the one data binding PR2 did NOT route through a slot, because its `_dirty` branch
    -- was a comment reading "in a real deployment this would refresh from /editor/campaigns/{name}"
    -- and a slot with nothing behind it is dead code no test can hold honest. There is a client
    -- behind it now.
    state._slots = {
        list = AsyncSlot.new({ label = "campaign list", owner = state }),
        campaign = AsyncSlot.new({ label = "campaign", owner = state }),
        create = AsyncSlot.new({ label = "create campaign", owner = state }),
        validate = AsyncSlot.new({ label = "validate", owner = state }),
        compile = AsyncSlot.new({ label = "compile", owner = state }),
    }
    return state
end

-- ============================================================================
-- Node type metadata lookup
-- ============================================================================

---Lookup metadata for a node type string.
function GraphState.node_type_info(type_str)
    return NODE_TYPE_INDEX[type_str]
end

---Get all known node types.
function GraphState.all_node_types()
    return NODE_TYPES
end

---Get the theme token for a node type.
function GraphState.node_token(type_str)
    local info = NODE_TYPE_INDEX[type_str]
    return info and info.token or "text_muted"
end

-- ============================================================================
-- Mutators
-- ============================================================================

function GraphState:set_campaign(name)
    name = tostring(name or "")
    if self.campaign_name == name then return end
    self.campaign_name = name
    self.graph_id = nil
    self.nodes = {}
    self.edges = {}
    self.selected_node = nil
    self.selected_edge = nil
    self.expanded = {}
    self.error = nil
    self.loading = true
    -- A verdict about the campaign being left behind says nothing about the one being opened.
    self:invalidate_validation()
    -- The fetch already in flight is for the PREVIOUS campaign; its tick count would otherwise
    -- expire the one this open is about to start.
    if self._slots then self._slots.campaign:reset() end
    self._dirty = true
end

---The campaign list came back from `GET /editor/campaigns`.
---
---Deliberately does NOT re-arm `_dirty`, and neither does `apply_campaign`. Both are called BY the
---tick with the answer already in hand; setting the tick's own gate from inside it would make the
---panel re-poll its own cached data on every frame forever.
function GraphState:set_campaigns(list)
    self.campaigns = type(list) == "table" and list or {}
    self.campaigns_loaded = true
end

---Take the editor's `Campaign` document and become it.
---
---The panel renders the SERVER's graph, never a locally guessed one: a node that appears because
---the client optimistically inserted it is indistinguishable on screen from a node the editor
---actually stored, and that is how the previous cycle shipped phantom writes.
---@param campaign table the decoded `Campaign` JSON
---@return boolean applied
function GraphState:apply_campaign(campaign)
    if type(campaign) ~= "table" then return false end
    self.campaign_name = tostring(campaign.name or self.campaign_name or "")

    -- `graphs` may legitimately be empty: `Campaign::new` mints a campaign with no graph at all,
    -- which is exactly the state a just-created campaign is in.
    local graph = (type(campaign.graphs) == "table") and campaign.graphs[1] or nil
    self.graph_id = graph and tostring(graph.id or "") or nil
    self.graph_name = graph and tostring(graph.name or "") or nil

    local nodes = {}
    for _, node in ipairs((graph or {}).nodes or {}) do
        nodes[#nodes + 1] = {
            -- Server ids are UUID strings. `tostring` rather than a bare read because every id this
            -- panel puts in a control id is concatenated, and a number there would silently produce
            -- an id no `reduce` pattern matches.
            id = tostring(node.id or ""),
            type = tostring(node.type or ""),
            intent = type(node.intent) == "table" and node.intent or {},
            resolved = node.resolved,
            context = node.context,
        }
    end
    local edges = {}
    for _, edge in ipairs((graph or {}).edges or {}) do
        edges[#edges + 1] = {
            id = tostring(edge.id or ""), from = tostring(edge.from or ""),
            to = tostring(edge.to or ""), guard = edge.guard and tostring(edge.guard) or nil,
        }
    end

    self.nodes = nodes
    self.edges = edges
    self.expanded = {}
    self.selected_node = nil
    self.selected_edge = nil
    self.loading = false
    return true
end

---The editor's answer to `POST .../validate`.
---
---Called BY the tick, so it does not re-arm `_dirty` for the same reason `apply_campaign` does not.
function GraphState:set_diagnostics(list)
    local out = {}
    for _, d in ipairs(type(list) == "table" and list or {}) do
        out[#out + 1] = {
            severity = tostring(d.severity or "error"),
            code = tostring(d.code or "UNKNOWN"),
            message = tostring(d.message or ""),
            -- Absent rather than empty-string: a diagnostic that blames no node must not produce a
            -- control that navigates nowhere.
            node_id = d.node_id and tostring(d.node_id) or nil,
        }
    end
    self.diagnostics = out
end

---The node a diagnostic blames, or nil when it blames none.
function GraphState:diagnostic_node(index)
    local d = (self.diagnostics or {})[tonumber(index) or 0]
    return d and d.node_id or nil
end

-- ============================================================================
-- Intent field editing (F7-R1..R5)
-- ============================================================================

function GraphState:node_by_id(id)
    id = tostring(id or "")
    for _, node in ipairs(self.nodes or {}) do
        if node.id == id then return node end
    end
    return nil
end

---Open the inline editor on one intent field, seeded with what is there now.
---@return boolean opened
function GraphState:begin_edit(node_id, field)
    field = tostring(field or "")
    local node = self:node_by_id(node_id)
    if not node or field == "" then return false end
    local current = (node.intent or {})[field]
    if type(current) == "table" then
        -- A list or a nested table is not editable as one line of text, and letting the operator
        -- type over one would replace a structure with a string the resolver cannot read.
        return false
    end
    self.editing = { node_id = node.id, field = field }
    self.edit_input:set_value(current == nil and "" or tostring(current))
    self.edit_input:focus()
    self._dirty = true
    return true
end

function GraphState:cancel_edit()
    self.editing = nil
    self.edit_input:set_value("")
    self._dirty = true
end

---Coerce a typed string back to the type the field already had.
---
---`IntentValue` is deserialized from the JSON type: a `count` sent as "12" arrives as Text, not
---Int, and the resolver then reads a field of the wrong shape with nothing raising anywhere. The
---current value is the schema this has, so it is the schema used.
function GraphState.coerce_intent_value(current, typed)
    typed = tostring(typed or "")
    if type(current) == "number" then
        local n = tonumber(typed)
        if n == nil then return nil, "'" .. typed .. "' is not a number" end
        return n
    end
    if type(current) == "boolean" then
        local lowered = typed:lower()
        if lowered == "true" or lowered == "yes" or lowered == "1" then return true end
        if lowered == "false" or lowered == "no" or lowered == "0" then return false end
        return nil, "'" .. typed .. "' is not true or false"
    end
    return typed
end

---The value the operator typed, coerced to the field's type.
---@return any value, string|nil reason
function GraphState:edited_value()
    local editing = self.editing
    if not editing then return nil, "nothing is being edited" end
    local node = self:node_by_id(editing.node_id)
    if not node then return nil, "the node being edited is gone" end
    local input = self.edit_input
    local typed = input.focused and input.buffer or input.value
    return GraphState.coerce_intent_value((node.intent or {})[editing.field], typed)
end

---A validate or compile answer no longer describes the graph on screen.
---
---Called by every mutation: showing yesterday's clean bill over a graph that has changed since is
---worse than showing nothing, because it is believed.
function GraphState:invalidate_validation()
    self.diagnostics = nil
    self.compile_message = nil
end

---Close the open campaign and go back to the chooser.
function GraphState:close_campaign()
    self.campaign_name = nil
    self.graph_id = nil
    self.graph_name = nil
    self.nodes = {}
    self.edges = {}
    self.expanded = {}
    self.selected_node = nil
    self.selected_edge = nil
    self.loading = false
    -- The campaign list is stale the moment a create lands, so make the chooser re-ask for it.
    self.campaigns_loaded = false
    if self._slots then self._slots.campaign:reset() end
    self._dirty = true
end

---The name typed into the chooser's field, trimmed. Empty when there is nothing to create.
function GraphState:pending_campaign_name()
    local input = self.name_input
    if not input then return "" end
    local typed = input.focused and input.buffer or input.value
    return (tostring(typed or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function GraphState:select_node(id)
    id = tostring(id or "")
    if id == "" then
        self.selected_node = nil
        return
    end
    if self.selected_node == id then return end
    self.selected_node = id
    self.selected_edge = nil
    self._dirty = true
end

function GraphState:toggle_expand_node(id)
    id = tostring(id or "")
    if id == "" then return end
    if self.expanded[id] then
        self.expanded[id] = nil
    else
        self.expanded[id] = true
    end
    self._dirty = true
end

function GraphState:select_edge(id)
    id = tostring(id or "")
    if self.selected_edge == id then return end
    self.selected_edge = id
    self.selected_node = nil
    self._dirty = true
end

function GraphState:add_node(node_type)
    local info = NODE_TYPE_INDEX[node_type]
    if not info then return nil end

    -- Generate a local id (the real one comes from the editor crate)
    local local_id = "node_" .. tostring(#self.nodes + 1) .. "_" .. tostring(os.clock()):gsub("%.", "")
    local node = {
        id = local_id,
        type = node_type,
        intent = {},
        preview = info.label,
    }
    -- Copy default intent
    for k, v in pairs(info.default_intent or {}) do
        node.intent[k] = v
    end

    table.insert(self.nodes, node)
    self._dirty = true
    return node
end

function GraphState:remove_node(id)
    id = tostring(id or "")
    if id == "" then return end
    local found = false
    for i = #self.nodes, 1, -1 do
        if self.nodes[i].id == id then
            table.remove(self.nodes, i)
            found = true
            break
        end
    end
    if not found then return end
    -- Remove connected edges
    for i = #self.edges, 1, -1 do
        if self.edges[i].from == id or self.edges[i].to == id then
            table.remove(self.edges, i)
        end
    end
    if self.selected_node == id then self.selected_node = nil end
    self.expanded[id] = nil
    self._dirty = true
end

function GraphState:update_node_intent(id, key, value)
    id = tostring(id or "")
    if id == "" then return end
    for _, node in ipairs(self.nodes) do
        if node.id == id then
            if type(node.intent) ~= "table" then
                node.intent = {}
            end
            node.intent[key] = value
            self._dirty = true
            return
        end
    end
end

function GraphState:add_edge(from_id, to_id, guard_id)
    from_id = tostring(from_id or "")
    to_id = tostring(to_id or "")
    if from_id == "" or to_id == "" then return nil end
    local edge = {
        id = "edge_" .. tostring(#self.edges + 1) .. "_" .. tostring(os.clock()):gsub("%.", ""),
        from = from_id,
        to = to_id,
        guard = guard_id and tostring(guard_id) or nil,
    }
    table.insert(self.edges, edge)
    self._dirty = true
    return edge
end

-- ============================================================================
-- Waypoint mode
-- ============================================================================

function GraphState:toggle_waypoint_mode()
    self.waypoint_mode = not self.waypoint_mode
    if self.waypoint_mode then
        self.current_position = nil
        self.escort_mode = false
    end
    self._dirty = true
end

function GraphState:capture_position(pos)
    if not self.waypoint_mode then return end
    self.current_position = pos
    self._dirty = true
end

function GraphState:commit_waypoint()
    if not self.current_position then return nil end
    local pos = self.current_position
    local node = self:add_node("questing.Travel")
    if node then
        node.intent.x = pos.x or 0
        node.intent.y = pos.y or 0
        node.intent.z = pos.z or 0
        node.intent.destination = string.format("(%.0f, %.0f, %.0f)", pos.x or 0, pos.y or 0, pos.z or 0)
        node.preview = string.format("(%.0f, %.0f, %.0f)", pos.x or 0, pos.y or 0, pos.z or 0)
    end
    self.current_position = nil
    self._dirty = true
    return node
end

-- ============================================================================
-- Escort recording
-- ============================================================================

function GraphState:set_escort_mode(on)
    on = on and true or false
    if self.escort_mode == on then return end
    self.escort_mode = on
    if on then
        self.escort_timeline = {}
        self.escort_start_time = os.clock()
        self.waypoint_mode = false
    else
        self.escort_start_time = nil
    end
    self._dirty = true
end

function GraphState:tick_escort_position(pos)
    if not self.escort_mode then return end
    local now = os.clock()
    local elapsed = self.escort_start_time and (now - self.escort_start_time) or 0
    table.insert(self.escort_timeline, {
        time = elapsed,
        position = pos and { x = pos.x, y = pos.y, z = pos.z } or nil,
        event_type = "position",
    })
end

function GraphState:generate_escort_nodes()
    -- Generate waypoint nodes from the escort timeline
    local generated = {}
    for i, entry in ipairs(self.escort_timeline) do
        if entry.position then
            local node = self:add_node("questing.Travel")
            if node then
                node.intent.x = entry.position.x or 0
                node.intent.y = entry.position.y or 0
                node.intent.z = entry.position.z or 0
                node.intent.destination = string.format("WP %d (%.0f, %.0f, %.0f)",
                    i, entry.position.x or 0, entry.position.y or 0, entry.position.z or 0)
                node.preview = string.format("(%.0f, %.0f, %.0f)",
                    entry.position.x or 0, entry.position.y or 0, entry.position.z or 0)
                table.insert(generated, node)
            end
        end
        -- Add a Wait node every 5 entries for pacing
        if i % 5 == 0 then
            local wait = self:add_node("questing.Wait")
            if wait then
                wait.intent.duration = 2
                table.insert(generated, wait)
            end
        end
    end
    self.escort_timeline = {}
    self.escort_mode = false
    self._dirty = true
    return generated
end

-- ============================================================================
-- Combat Area editing (per-node)
-- ============================================================================

function GraphState:set_combat_area(node_id, area)
    node_id = tostring(node_id or "")
    if node_id == "" then return end
    self.combat_areas[node_id] = area
    self._dirty = true
end

function GraphState:get_combat_area(node_id)
    node_id = tostring(node_id or "")
    if node_id == "" then return nil end
    return self.combat_areas[node_id]
end

-- ============================================================================
-- Filter
-- ============================================================================

function GraphState:set_filter(node_type)
    if self.filter_type == node_type then
        self.filter_type = nil
    else
        self.filter_type = node_type
    end
    self._dirty = true
end

-- ============================================================================
-- Build — produce the view from current state
-- ============================================================================

function GraphState:build()
    -- Filter nodes if a type filter is active
    local visible_nodes = {}
    for _, node in ipairs(self.nodes or {}) do
        if self.filter_type == nil or node.type == self.filter_type then
            table.insert(visible_nodes, node)
        end
    end

    -- Build edge references
    local edge_refs = {}
    for _, edge in ipairs(self.edges or {}) do
        table.insert(edge_refs, edge)
    end

    -- Build node type counts for the filter chips
    local type_counts = {}
    for _, node in ipairs(self.nodes or {}) do
        type_counts[node.type] = (type_counts[node.type] or 0) + 1
    end

    return {
        campaign_name = self.campaign_name,
        graph_name = self.graph_name,
        graph_id = self.graph_id,
        campaigns = self.campaigns or {},
        campaigns_loaded = self.campaigns_loaded,
        name_input = self.name_input,
        diagnostics = self.diagnostics,
        compile_message = self.compile_message,
        editing = self.editing,
        edit_input = self.edit_input,
        nodes = visible_nodes,
        all_nodes = self.nodes,
        edges = edge_refs,
        selected_node = self.selected_node,
        selected_edge = self.selected_edge,
        expanded = self.expanded,
        waypoint_mode = self.waypoint_mode,
        current_position = self.current_position,
        escort_mode = self.escort_mode,
        escort_timeline_count = #(self.escort_timeline or {}),
        filter_type = self.filter_type,
        type_counts = type_counts,
        loading = self.loading,
        error = self.error,
    }
end

-- ============================================================================
-- Build plan — produce the draw items for one frame
-- ============================================================================

local CHAR_W = PanelLayout.CHAR_W
local PAD = PanelLayout.PAD
local CONTROL_H = PanelLayout.CONTROL_H
local SECTION_H = PanelLayout.SECTION_H
local ROW_H = PanelLayout.ROW_H
local LINE_H = Theme.line_height.body
local SMALL_H = Theme.line_height.caption
local BUTTON_MIN_W = PanelLayout.BUTTON_MIN_W

local function fit_label(text, width)
    return PanelLayout.fit(text, width)
end

-- Map node kinds to the shared accessibility glyph vocabulary. Falls back to the
-- palette icon so every type stays drawable even when no semantic glyph exists.
local NODE_GLYPH_KEY = {
    ["questing.Travel"] = "flight",
    ["questing.Flight"] = "flight",
    ["questing.LearnFlightPath"] = "flight",
    ["questing.Kill"] = "kill",
    ["questing.Grind"] = "kill",
    ["questing.InteractNpc"] = "interact",
    ["questing.Collect"] = "loot",
    ["questing.Patrol"] = "patrol",
    ["questing.Vendor"] = "vendor",
}
local function node_glyph(node_type)
    local key = NODE_GLYPH_KEY[node_type]
    if key then return PanelLayout.glyph(key) end
    local info = NODE_TYPE_INDEX[node_type]
    return info and info.icon or "?"
end

local function intent_preview(node_type, intent)
    local info = NODE_TYPE_INDEX[node_type]
    if not info then return "" end
    local label = info.label
    local function ref_id(ref)
        if type(ref) == "table" and type(ref.ref) == "string" then
            return ref.ref:match("[^:]+:(.+)") or "?"
        end
        return tostring(ref or "?")
    end
    if node_type == "questing.Travel" then
        return string.format("%s: %s", label, intent.destination or "")
    elseif node_type == "questing.AcceptQuest" then
        return string.format("%s: Q#%s", label, ref_id(intent.quest))
    elseif node_type == "questing.Kill" then
        return string.format("%s: x%s", label, tostring(intent.count or 1))
    elseif node_type == "questing.TurnIn" then
        return string.format("%s: Q#%s", label, ref_id(intent.quest))
    elseif node_type == "questing.Collect" then
        return string.format("%s: O#%s", label, ref_id(intent.object))
    elseif node_type == "questing.Wait" then
        return string.format("%s: %ss", label, tostring(intent.duration or 5))
    elseif node_type == "questing.Vendor" then
        return string.format("%s: NPC#%s", label, tostring(intent.npc_entry or 0))
    elseif node_type == "questing.Repair" then
        return string.format("%s: NPC#%s", label, tostring(intent.npc_entry or 0))
    elseif node_type == "questing.Grind" then
        return string.format("%s: %d targets", label, #(intent.targets or {}))
    elseif node_type == "questing.Escort" then
        return string.format("%s: NPC#%s", label, tostring(intent.npc_entry or 0))
    elseif node_type == "questing.Patrol" then
        return string.format("%s: %d WPs", label, #(intent.waypoints or {}))
    else
        return label
    end
end

local function build_intent_fields(node_type, intent)
    -- Returns a list of { key, label, value } fields for the expanded form
    local fields = {}
    if node_type == "questing.Travel" then
        table.insert(fields, { key = "destination", label = "Destination", value = intent.destination or "" })
        table.insert(fields, { key = "x", label = "X", value = intent.x or 0 })
        table.insert(fields, { key = "y", label = "Y", value = intent.y or 0 })
        table.insert(fields, { key = "z", label = "Z", value = intent.z or 0 })
        table.insert(fields, { key = "tolerance", label = "Tolerance", value = intent.tolerance or 5 })
        table.insert(fields, { key = "allow_flight", label = "Allow Flight", value = intent.allow_flight or false })
        table.insert(fields, { key = "wait_time", label = "Wait Time", value = intent.wait_time or 0 })
    elseif node_type == "questing.AcceptQuest" then
        table.insert(fields, { key = "quest", label = "Quest", value = intent.quest })
        table.insert(fields, { key = "from", label = "From NPC", value = intent.from })
        table.insert(fields, { key = "optional", label = "Optional", value = intent.optional or false })
    elseif node_type == "questing.Kill" then
        table.insert(fields, { key = "target", label = "Target", value = intent.target })
        table.insert(fields, { key = "count", label = "Count", value = intent.count or 1 })
        table.insert(fields, { key = "loot", label = "Loot", value = intent.loot or false })
        table.insert(fields, { key = "ignore_elites", label = "Ignore Elites", value = intent.ignore_elites or false })
    elseif node_type == "questing.TurnIn" then
        table.insert(fields, { key = "quest", label = "Quest", value = intent.quest })
        table.insert(fields, { key = "to", label = "To NPC", value = intent.to })
        table.insert(fields, { key = "choose_reward", label = "Reward Choice", value = intent.choose_reward or 0 })
        table.insert(fields, { key = "optional", label = "Optional", value = intent.optional or false })
    elseif node_type == "questing.Collect" then
        table.insert(fields, { key = "object", label = "Object", value = intent.object })
        table.insert(fields, { key = "count", label = "Count", value = intent.count or 1 })
    elseif node_type == "questing.Wait" then
        table.insert(fields, { key = "duration", label = "Duration (s)", value = intent.duration or 5 })
    elseif node_type == "questing.Vendor" then
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
        table.insert(fields, { key = "sell_grey", label = "Sell Grey", value = intent.sell_grey or false })
        table.insert(fields, { key = "repair", label = "Repair", value = intent.repair or false })
        table.insert(fields, { key = "min_free_slots", label = "Min Free Slots", value = intent.min_free_slots or 5 })
    elseif node_type == "questing.Train" then
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
    elseif node_type == "questing.Repair" then
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
    elseif node_type == "questing.Flight" then
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
        table.insert(fields, { key = "destination", label = "Destination", value = intent.destination or "" })
    elseif node_type == "questing.InteractNpc" then
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
        table.insert(fields, { key = "gossip", label = "Gossip", value = intent.gossip or "" })
    elseif node_type == "questing.UseItem" then
        table.insert(fields, { key = "item", label = "Item ID", value = intent.item or 0 })
        table.insert(fields, { key = "target_entry", label = "Target Entry", value = intent.target_entry or 0 })
    elseif node_type == "questing.Mailbox" then
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
    elseif node_type == "questing.Hearth" then
        table.insert(fields, { key = "innkeeper_entry", label = "Innkeeper Entry", value = intent.innkeeper_entry or 0 })
        table.insert(fields, { key = "destination", label = "Destination", value = intent.destination or "" })
    elseif node_type == "questing.Escort" then
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
        table.insert(fields, { key = "timeout", label = "Timeout (s)", value = intent.timeout or 120 })
    elseif node_type == "questing.Patrol" then
        table.insert(fields, { key = "waypoints", label = "Waypoints", value = #(intent.waypoints or {}) })
        table.insert(fields, { key = "loop", label = "Loop", value = intent.loop or false })
    elseif node_type == "questing.Grind" then
        table.insert(fields, { key = "targets", label = "Target Entries", value = #(intent.targets or {}) })
        table.insert(fields, { key = "polygon", label = "Area Radius", value = (intent.polygon and intent.polygon.radius) or 50 })
        table.insert(fields, { key = "loot", label = "Loot", value = intent.loot or false })
        -- Combat Area Editor fields (F18)
        table.insert(fields, { key = "_spot_x", label = "Spot X", value = (intent.spot_position and intent.spot_position.x) or 0 })
        table.insert(fields, { key = "_spot_y", label = "Spot Y", value = (intent.spot_position and intent.spot_position.y) or 0 })
        table.insert(fields, { key = "_spot_z", label = "Spot Z", value = (intent.spot_position and intent.spot_position.z) or 0 })
        table.insert(fields, { key = "_safe_x", label = "Safe Spot X", value = (intent.safe_spot and intent.safe_spot.x) or 0 })
        table.insert(fields, { key = "_safe_y", label = "Safe Spot Y", value = (intent.safe_spot and intent.safe_spot.y) or 0 })
        table.insert(fields, { key = "_safe_z", label = "Safe Spot Z", value = (intent.safe_spot and intent.safe_spot.z) or 0 })
        table.insert(fields, { key = "max_pull", label = "Max Pull", value = intent.max_pull or 3 })
        table.insert(fields, { key = "leash_radius", label = "Leash Radius", value = intent.leash_radius or 50 })
    elseif node_type == "questing.Comment" then
        table.insert(fields, { key = "text", label = "Text", value = intent.text or "" })
    else
        -- Fallback: show all intent keys
        for k, v in pairs(intent) do
            table.insert(fields, { key = k, label = k, value = v })
        end
    end
    return fields
end

---Build the draw plan items from a view and bounds.
---@param view table from build()
---@param bounds table { x, y, w, h }
---@return table { items, controls }
function GraphState.build_plan(view, bounds)
    local items = {}
    local controls = {}
    local text_x = bounds.x + PAD
    local content_w = math.max(0, bounds.w - PAD * 2)
    local y = bounds.y + PAD

    local function push(item) items[#items + 1] = item; return item end
    local function text_item(font, token, str, ox, oy)
        push({
            kind = "text", x = text_x + (ox or 0), y = y + (oy or 0),
            font = Theme.font[font], token = token,
            alpha = Theme.interaction.resting.text, text = str,
        })
    end

    local function section(title)
        push({
            kind = "section_header",
            bounds = { x = text_x, y = y, w = content_w, h = SECTION_H },
            title = title,
        })
        y = y + SECTION_H + Theme.space.xs
    end

    local function control(item)
        controls[#controls + 1] = {
            id = item.id,
            kind = item.kind,
            bounds = item.bounds,
            disabled = item.disabled and true or false,
        }
        return item
    end

    local function alert_banner_bounds(lines)
        local h = Theme.space.md * 2 + Theme.line_height.heading + #lines * Theme.line_height.caption
        return { x = text_x, y = y, w = content_w, h = h }
    end

    local function pending_name(input)
        if not input then return "" end
        local typed = input.focused and input.buffer or input.value
        return (tostring(typed or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    -- ====================================================================
    -- No campaign loaded: the chooser. Create and open both have to work from HERE, with no
    -- hand-edited file anywhere in the loop -- there was no Lua caller for :3031 at all before,
    -- so this was the one screen from which nothing was reachable.
    -- ====================================================================
    if not view.campaign_name or view.campaign_name == "" then
        push(control({
            kind = "text_input", id = "campaign_name",
            bounds = { x = text_x, y = y, w = content_w, h = CONTROL_H },
            model = view.name_input, placeholder = "New campaign name...",
            disabled = false,
        }))
        y = y + CONTROL_H + Theme.space.sm

        local campaigns = view.campaigns or {}
        section(string.format("Campaigns (%d)", #campaigns))
        for _, summary in ipairs(campaigns) do
            local name = tostring(summary.name or "")
            push(control({
                kind = "list_row", id = "open_campaign:" .. name,
                bounds = { x = text_x, y = y, w = content_w, h = ROW_H },
                label = string.format("%s  ·  %d node(s)", name, tonumber(summary.node_count) or 0),
                tone = "info", disabled = false,
            }))
            y = y + ROW_H
        end
        if #campaigns == 0 then
            -- "none yet" and "not asked yet" are different facts and an operator acts differently on
            -- each, so they are never collapsed into one line.
            local glyph = PanelLayout.glyph(view.campaigns_loaded and "empty" or "loading")
            text_item("caption", "text_muted",
                glyph .. "  " .. (view.campaigns_loaded and "No campaigns on the editor yet"
                                       or "Asking the editor for campaigns..."))
            y = y + SMALL_H + Theme.space.sm
        end

        local empty = PanelLayout.empty_state_plan({
            bounds = { x = bounds.x, y = y, w = bounds.w,
                       h = math.max(1, bounds.y + bounds.h - y - PAD) },
            id = "new_campaign",
            title = PanelLayout.glyph("empty") .. "  No Campaign",
            message = "Name a campaign above and create it, or open one from the list",
            action_label = "New Campaign",
        })
        empty[1].disabled = pending_name(view.name_input) == ""
        push(control(empty[1]))
        return { items = items, controls = controls }
    end

    if view.loading then
        local banner = PanelLayout.alert_banner_plan({
            bounds = alert_banner_bounds({ "Loading campaign data..." }),
            token = "info",
            glyph = PanelLayout.glyph("loading"),
            title = "Loading",
            lines = { "Loading campaign data..." },
        })
        for _, item in ipairs(banner) do push(item) end
        return { items = items, controls = controls }
    end

    if view.error then
        local banner = PanelLayout.alert_banner_plan({
            bounds = alert_banner_bounds({ tostring(view.error) }),
            token = "danger",
            glyph = PanelLayout.glyph("error"),
            title = "Error",
            lines = { tostring(view.error) },
        })
        for _, item in ipairs(banner) do push(item) end
        return { items = items, controls = controls }
    end

    -- ====================================================================
    -- Toolbar: Add Node + type filter chips (the main control/filter bar)
    -- ====================================================================
    local node_types = GraphState.all_node_types()
    local add_label = "Add Node"
    if view.filter_type then
        local fi = NODE_TYPE_INDEX[view.filter_type]
        add_label = add_label .. " (" .. (fi and fi.label or view.filter_type) .. ")"
    end

    local max_type_chips = math.floor(content_w / (64 + Theme.space.sm))
    local shown_types = 0

    -- Stable width: accommodate the longest type label (typically 10-12 chars),
    -- but never wider than the pane itself.
    local add_w = math.min(content_w, math.max(
        BUTTON_MIN_W,
        #"Add Node (LearnFlightPath)" * CHAR_W + Theme.space.xl
    ))

    local toolbar_y = y
    local toolbar_h = Theme.metrics.toolbar_height
    local control_y = toolbar_y + (toolbar_h - CONTROL_H) * 0.5

    local toolbar_items = {}
    toolbar_items[#toolbar_items + 1] = control({
        kind = "button", id = "add_node_toggle",
        bounds = { x = text_x, y = control_y, w = add_w, h = CONTROL_H },
        label = add_label, variant = "primary", disabled = false,
    })
    local cx = text_x + add_w + Theme.space.sm

    -- Type filter chips (limited to fit)
    for _, nt in ipairs(node_types) do
        if shown_types >= max_type_chips then break end
        local w = #nt.label * CHAR_W + Theme.space.lg
        if cx + w > text_x + content_w then break end
        toolbar_items[#toolbar_items + 1] = control({
            kind = "chip", id = "filter_type:" .. nt.type,
            bounds = { x = cx, y = control_y, w = w, h = CONTROL_H },
            label = nt.label, selected = view.filter_type == nt.type,
            tone = nt.token, disabled = false,
        })
        cx = cx + w + Theme.space.sm
        shown_types = shown_types + 1
    end

    local toolbar_bounds = { x = bounds.x, y = toolbar_y, w = bounds.w, h = toolbar_h }
    for _, item in ipairs(PanelLayout.toolbar_plan(toolbar_items, toolbar_bounds)) do
        push(item)
    end
    y = y + toolbar_h + Theme.space.sm

    -- ====================================================================
    -- Save button (full width, above the action toolbar)
    -- ====================================================================
    local has_graph = view.graph_id ~= nil
    local save_w = math.min(content_w, math.max(BUTTON_MIN_W, #"Save Campaign" * CHAR_W + Theme.space.xl))
    push(control({
        kind = "button", id = "save_graph", label = "Save Campaign",
        bounds = { x = text_x, y = control_y, w = save_w, h = CONTROL_H },
        variant = "primary", disabled = not has_graph,
    }))
    y = y + toolbar_h + Theme.space.sm

    -- ====================================================================
    -- Actions toolbar
    -- ====================================================================
    -- Recalculate the centred control row for THIS toolbar; reusing the first
    -- toolbar's control_y would place these buttons on top of the Add Node row.
    control_y = y + (toolbar_h - CONTROL_H) * 0.5

    local close_w = math.min(content_w, math.max(BUTTON_MIN_W, #"Campaigns" * CHAR_W + Theme.space.xl))
    local validate_w = math.min(content_w, math.max(BUTTON_MIN_W, #"Validate" * CHAR_W + Theme.space.xl))
    local compile_w = math.min(content_w, math.max(BUTTON_MIN_W, #"Compile" * CHAR_W + Theme.space.xl))
    local escort_label = view.escort_mode and "Stop Escort" or "Escort Rec"
    local escort_w = math.min(content_w, math.max(BUTTON_MIN_W, #escort_label * CHAR_W + Theme.space.lg))
    local wp_label = view.waypoint_mode and "Stop WP" or "Capture WP"
    local wp_w = math.min(content_w, math.max(BUTTON_MIN_W, #wp_label * CHAR_W + Theme.space.lg))

    local left_w = close_w + validate_w + compile_w + Theme.space.sm * 2
    local right_w = escort_w + wp_w + Theme.space.sm
    local action_items = {}

    -- If the panel is too narrow to hold both groups side-by-side, stack the right group
    -- underneath so the buttons never overlap or run off the edge.
    local two_row = left_w + Theme.space.md + right_w > content_w
    local action_h = toolbar_h
    if two_row then
        action_h = toolbar_h * 2 + Theme.space.sm
    end

    local row1_y = y + (action_h - CONTROL_H) * 0.5
    local row2_y = row1_y
    if two_row then
        row1_y = y + (toolbar_h - CONTROL_H) * 0.5
        row2_y = y + toolbar_h + Theme.space.sm + (toolbar_h - CONTROL_H) * 0.5
    end

    action_items[#action_items + 1] = control({
        kind = "button", id = "close_campaign", label = "Campaigns",
        bounds = { x = text_x, y = row1_y, w = close_w, h = CONTROL_H },
        variant = "secondary", disabled = false,
    })
    action_items[#action_items + 1] = control({
        kind = "button", id = "validate", label = "Validate",
        bounds = { x = text_x + close_w + Theme.space.sm, y = row1_y, w = validate_w, h = CONTROL_H },
        variant = "secondary", disabled = not has_graph,
    })
    action_items[#action_items + 1] = control({
        kind = "button", id = "compile", label = "Compile",
        bounds = { x = text_x + close_w + validate_w + Theme.space.sm * 2, y = row1_y, w = compile_w, h = CONTROL_H },
        variant = "secondary", disabled = not has_graph,
    })

    local right_x = text_x + content_w - right_w
    action_items[#action_items + 1] = control({
        kind = "chip", id = "toggle_escort",
        label = escort_label,
        bounds = { x = right_x, y = row2_y, w = escort_w, h = CONTROL_H },
        tone = view.escort_mode and "warning" or nil,
        selected = view.escort_mode, disabled = false,
    })
    action_items[#action_items + 1] = control({
        kind = "chip", id = "toggle_waypoint",
        label = wp_label,
        bounds = { x = right_x + escort_w + Theme.space.sm, y = row2_y, w = wp_w, h = CONTROL_H },
        tone = view.waypoint_mode and "info" or nil,
        selected = view.waypoint_mode, disabled = false,
    })

    local action_bounds = { x = bounds.x, y = y, w = bounds.w, h = action_h }
    for _, item in ipairs(PanelLayout.toolbar_plan(action_items, action_bounds)) do
        push(item)
    end
    y = y + action_h + Theme.space.sm

    -- Waypoint capture indicator
    if view.waypoint_mode and view.current_position then
        local pos = view.current_position
        local pos_str = string.format("Position: (%.0f, %.0f, %.0f)", pos.x or 0, pos.y or 0, pos.z or 0)
        text_item("caption", "info", PanelLayout.glyph("info") .. "  " .. pos_str)
        y = y + SMALL_H

        push(control({
            kind = "button", id = "commit_waypoint",
            bounds = { x = text_x, y = y, w = math.min(content_w, math.max(BUTTON_MIN_W, #"Commit Waypoint" * CHAR_W + Theme.space.xl)), h = CONTROL_H },
            label = "Commit Waypoint", variant = "primary",
            disabled = not view.current_position,
        }))
        y = y + CONTROL_H + Theme.space.sm
    end

    -- Escort recording indicator
    if view.escort_mode then
        text_item("caption", "warning",
            PanelLayout.glyph("warning") .. "  " ..
            string.format("Recording escort: %d pts captured", view.escort_timeline_count or 0))
        y = y + SMALL_H

        local gen_label = "Generate from Recording"
        local gen_w = math.max(BUTTON_MIN_W, #gen_label * CHAR_W + Theme.space.xl)
        gen_w = math.min(gen_w, content_w)
        push(control({
            kind = "button", id = "generate_escort_nodes",
            bounds = { x = text_x, y = y, w = gen_w, h = CONTROL_H },
            label = gen_label, variant = "primary",
            disabled = (view.escort_timeline_count or 0) == 0,
        }))
        y = y + CONTROL_H + Theme.space.sm
    end

    -- ====================================================================
    -- Validation bar (F19-R1/R3)
    -- ====================================================================
    if view.compile_message then
        text_item("caption", "info",
            PanelLayout.glyph("info") .. "  " .. fit_label(tostring(view.compile_message), content_w - 16))
        y = y + SMALL_H + Theme.space.xs
    end
    if view.diagnostics then
        local diagnostics = view.diagnostics
        if #diagnostics == 0 then
            text_item("caption", "success",
                PanelLayout.glyph("success") .. "  Validation passed")
            y = y + SMALL_H + Theme.space.sm
        else
            section(string.format("Diagnostics (%d)", #diagnostics))
            for index, d in ipairs(diagnostics) do
                push(control({
                    kind = "list_row", id = "diagnostic:" .. tostring(index),
                    bounds = { x = text_x, y = y, w = content_w, h = ROW_H },
                    label = fit_label(d.code .. ": " .. d.message, content_w - 8),
                    tone = d.severity == "warning" and "warning" or "danger",
                    -- Selected when it blames the node the operator is already looking at, so the
                    -- link reads both ways.
                    selected = d.node_id ~= nil and view.selected_node == d.node_id,
                    disabled = false,
                }))
                y = y + ROW_H
            end
            y = y + Theme.space.xs
        end
    end

    -- ====================================================================
    -- Node list
    -- ====================================================================
    local nodes = view.nodes or {}
    if #nodes > 0 then
        section(string.format("Nodes (%d)", #nodes))

        for _, node in ipairs(nodes) do
            local nt = NODE_TYPE_INDEX[node.type]
            local label = nt and nt.label or node.type
            local token = nt and nt.token or "text_muted"
            local icon = node_glyph(node.type)
            local preview = node.preview or intent_preview(node.type, node.intent or {})
            local is_selected = view.selected_node == node.id
            local is_expanded = view.expanded and view.expanded[node.id]

            -- Row click to select
            local row_bounds = {
                x = text_x, y = y,
                w = content_w, h = ROW_H,
            }
            push(control({
                kind = "list_row", id = "select_node:" .. node.id,
                bounds = row_bounds,
                label = icon .. " " .. label .. ": " .. fit_label(preview, content_w - 20),
                selected = is_selected, tone = token, disabled = false,
            }))
            y = y + ROW_H

            -- If selected, add action buttons. NO TRUNCATION: buttons are wide enough for labels.
            -- If there isn't enough horizontal space for two side-by-side buttons, stack vertically.
            if is_selected then
                local expand_label = is_expanded and "Collapse" or "Edit"
                local expand_w = #expand_label * CHAR_W + Theme.space.xl
                local delete_w = #"Delete" * CHAR_W + Theme.space.xl
                local btn_w = math.max(expand_w, delete_w)
                local available = (content_w - Theme.space.sm) * 0.5

                if btn_w > available then
                    -- Stack vertically: one button per row
                    push(control({
                        kind = "button", id = "toggle_expand:" .. node.id,
                        bounds = { x = text_x, y = y, w = content_w, h = CONTROL_H },
                        label = expand_label, variant = "secondary", disabled = false,
                    }))
                    y = y + CONTROL_H + Theme.space.xs
                    push(control({
                        kind = "button", id = "remove_node:" .. node.id,
                        bounds = { x = text_x, y = y, w = content_w, h = CONTROL_H },
                        label = "Delete", variant = "danger", disabled = false,
                    }))
                    y = y + CONTROL_H + Theme.space.xs
                else
                    -- Side by side
                    push(control({
                        kind = "button", id = "toggle_expand:" .. node.id,
                        bounds = { x = text_x, y = y, w = btn_w, h = CONTROL_H },
                        label = expand_label, variant = "secondary", disabled = false,
                    }))
                    push(control({
                        kind = "button", id = "remove_node:" .. node.id,
                        bounds = { x = text_x + available + Theme.space.sm, y = y, w = btn_w, h = CONTROL_H },
                        label = "Delete", variant = "danger", disabled = false,
                    }))
                    y = y + CONTROL_H + Theme.space.xs
                end
            end

            -- Expanded properties form
            if is_expanded then
                local fields = build_intent_fields(node.type, node.intent or {})
                for _, field in ipairs(fields) do
                    local val_str
                    if type(field.value) == "boolean" then
                        val_str = field.value and "Yes" or "No"
                    else
                        val_str = tostring(field.value)
                    end
                    local field_label = string.format("  %s: %s", field.label, val_str)
                    push({
                        kind = "text", x = text_x + Theme.space.md, y = y,
                        font = Theme.font.caption, token = "text_secondary",
                        alpha = Theme.interaction.resting.text,
                        text = fit_label(field_label, content_w - Theme.space.md),
                    })
                    y = y + SMALL_H

                    local editing = view.editing
                    local under_edit = editing and editing.node_id == node.id
                                       and editing.field == field.key
                    if under_edit then
                        -- The field being edited swaps its label row for a real typeable box, so
                        -- "Edit" leads somewhere instead of only announcing an intention.
                        push(control({
                            kind = "text_input", id = "edit_value",
                            bounds = { x = text_x + Theme.space.md, y = y,
                                       w = math.max(BUTTON_MIN_W * 2, content_w - Theme.space.md), h = CONTROL_H },
                            model = view.edit_input,
                            placeholder = field.label,
                            disabled = false,
                        }))
                        y = y + CONTROL_H + Theme.space.xs
                    elseif type(field.value) ~= "table" and field.key ~= "" then
                        -- Measured, and hit_min tall centred on the text row: `hit_bounds`
                        -- floors the click region to 30px either way, so a 12px visual was an
                        -- 18px lie about where the pointer lands.
                        local edit_id = string.format("edit_intent:%s:%s", node.id, field.key)
                        local edit_w = #"Edit" * CHAR_W + Theme.space.xl
                        push(control({
                            kind = "button", id = edit_id,
                            bounds = { x = text_x + content_w - edit_w,
                                       y = y - SMALL_H + (SMALL_H - Theme.metrics.hit_min) * 0.5,
                                       w = edit_w, h = Theme.metrics.hit_min },
                            label = "Edit", variant = "ghost", disabled = false,
                        }))
                    end
                end

                -- Combat Area Editor (F18) — inline for Grind nodes
                if node.type == "questing.Grind" then
                    y = y + Theme.space.xs
                    section("Combat Area")
                    text_item("caption", "text_muted",
                        PanelLayout.glyph("info") .. "  Set spot coords, safe spot, pull & leash")
                    y = y + SMALL_H
                end

                y = y + Theme.space.sm
            end
        end
    else
        local empty = PanelLayout.empty_state_plan({
            bounds = { x = bounds.x + Theme.space.sm, y = y,
                      w = bounds.w - Theme.space.sm * 2,
                      h = math.max(1, bounds.y + bounds.h - y - PAD) },
            id = "add_node_toggle",
            title = PanelLayout.glyph("empty") .. "  No Nodes",
            message = "Add a behavior node using the toolbar above",
            action_label = "Add Node",
        })
        empty[1].disabled = false
        push(control(empty[1]))
    end

    return { items = items, controls = controls }
end

-- ============================================================================
-- Reduce — map an activated control id to a command for the host
-- ============================================================================

function GraphState.reduce(action_id)
    if action_id == nil then return nil end

    -- Campaign lifecycle. The typed name is NOT threaded through the id: it is already on
    -- `state.name_input`, and putting a user-typed string into a control id would make `reduce`
    -- responsible for splitting it back out of one.
    if action_id == "new_campaign" or action_id == "campaign_name_submit" then
        return { kind = "create_campaign" }
    end
    if action_id == "campaign_name_cancel" then
        return { kind = "cancel_campaign_name" }
    end
    if action_id == "close_campaign" then
        return { kind = "close_campaign" }
    end
    local open_match = action_id:match("^open_campaign:(.+)$")
    if open_match then
        return { kind = "open_campaign", name = open_match }
    end

    -- Add node toggle
    if action_id == "add_node_toggle" then
        return { kind = "show_add_node_menu" }
    end

    -- Waypoint
    if action_id == "toggle_waypoint" then
        return { kind = "toggle_waypoint" }
    end
    if action_id == "commit_waypoint" then
        return { kind = "commit_waypoint" }
    end

    -- Escort
    if action_id == "toggle_escort" then
        return { kind = "toggle_escort" }
    end
    if action_id == "generate_escort_nodes" then
        return { kind = "generate_escort_nodes" }
    end

    -- Save / Validate / Compile
    if action_id == "save_graph" then
        return { kind = "save_graph" }
    end
    if action_id == "validate" then
        return { kind = "validate_graph" }
    end
    if action_id == "compile" then
        return { kind = "compile_graph" }
    end

    -- The inline intent editor. Enter writes the field through the editor; Escape abandons it.
    if action_id == "edit_value_submit" then
        return { kind = "commit_intent" }
    end
    if action_id == "edit_value_cancel" then
        return { kind = "cancel_intent" }
    end

    -- A diagnostic navigates to the node it blames (F19-R3).
    local diagnostic_match = action_id:match("^diagnostic:(%d+)$")
    if diagnostic_match then
        return { kind = "select_diagnostic", index = tonumber(diagnostic_match) }
    end

    -- Filter type
    local filter_match = action_id:match("^filter_type:(.+)$")
    if filter_match then
        return { kind = "set_filter", node_type = filter_match }
    end

    -- Select node
    local select_match = action_id:match("^select_node:(.+)$")
    if select_match then
        return { kind = "select_node", node_id = select_match }
    end

    -- Toggle expand
    local expand_match = action_id:match("^toggle_expand:(.+)$")
    if expand_match then
        return { kind = "toggle_expand", node_id = expand_match }
    end

    -- Remove node
    local remove_match = action_id:match("^remove_node:(.+)$")
    if remove_match then
        return { kind = "remove_node", node_id = remove_match }
    end

    -- Edit intent field: edit_intent:<node_id>:<field_name>
    local _, _, nid, fld = action_id:find("^edit_intent:([^:]+):([^:]+)$")
    if nid and fld then
        return { kind = "edit_intent", node_id = nid, field = fld }
    end

    return nil
end

return GraphState
