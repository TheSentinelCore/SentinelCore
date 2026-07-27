-- sentinel/ui/panels/graph_state.lua
-- The Graph panel's view-model for the campaign graph editor with Smart Waypoint Editor,
-- Behavior Nodes, and Combat Area Editor (Phase 3, PR-3a/3b/3c).
--
-- All decision logic lives here; `graph.lua` only renders whatever `build()` returns.

local GraphState = {}
GraphState.__index = GraphState

-- ============================================================================
-- Node type metadata — labels, theme token, icon glyph, default intent
-- ============================================================================

local NODE_TYPES = {
    { type = "questing.Travel",         label = "Travel",        color = "#4A8BFF", icon = "T",
      token = "info",
      default_intent = { destination = "", x = 0, y = 0, z = 0, tolerance = 5, allow_flight = false, wait_time = 0 } },
    { type = "questing.AcceptQuest",    label = "AcceptQuest",   color = "#4ADE80", icon = "A",
      token = "success",
      default_intent = { quest_id = 0, npc_entry = 0, auto_complete_dialog = false } },
    { type = "questing.Kill",           label = "Kill",          color = "#FA8080", icon = "K",
      token = "danger",
      default_intent = { creature_entry = 0, count = 1, loot = false, ignore_elites = false } },
    { type = "questing.TurnInQuest",    label = "TurnInQuest",   color = "#FBBF24", icon = "T",
      token = "warning",
      default_intent = { quest_id = 0, npc_entry = 0, choose_reward = 0 } },
    { type = "questing.Wait",           label = "Wait",          color = "#A6ADBF", icon = "W",
      token = "text_muted",
      default_intent = { duration = 5 } },
    { type = "questing.Vendor",         label = "Vendor",        color = "#A78BFA", icon = "V",
      token = "accent",
      default_intent = { npc_entry = 0, sell_grey = true, repair = false, min_free_slots = 5 } },
    { type = "questing.Train",          label = "Train",         color = "#60A5FA", icon = "T",
      token = "info",
      default_intent = { npc_entry = 0, spells = {} } },
    { type = "questing.Repair",         label = "Repair",        color = "#FB923C", icon = "R",
      token = "warning",
      default_intent = { npc_entry = 0 } },
    { type = "questing.Flight",         label = "Flight",        color = "#2DD4BF", icon = "F",
      token = "info",
      default_intent = { npc_entry = 0, destination = "" } },
    { type = "questing.InteractNpc",    label = "Interact",      color = "#818CF8", icon = "I",
      token = "accent",
      default_intent = { npc_entry = 0, gossip = "" } },
    { type = "questing.UseItem",        label = "UseItem",       color = "#F472B6", icon = "U",
      token = "accent",
      default_intent = { item = 0, target_entry = 0 } },
    { type = "questing.Mailbox",        label = "Mailbox",       color = "#94A3B8", icon = "M",
      token = "text_muted",
      default_intent = { npc_entry = 0 } },
    { type = "questing.Hearth",         label = "Hearth",        color = "#FB7185", icon = "H",
      token = "danger",
      default_intent = { innkeeper_entry = 0, destination = "" } },
    { type = "questing.Escort",         label = "Escort",        color = "#F59E0B", icon = "E",
      token = "warning",
      default_intent = { npc_entry = 0, timeout = 120 } },
    { type = "questing.Patrol",         label = "Patrol",        color = "#34D399", icon = "P",
      token = "success",
      default_intent = { waypoints = {}, loop = false } },
    { type = "questing.Condition",      label = "Condition",     color = "#A3E635", icon = "C",
      token = "success",
      default_intent = { condition_type = "", value = "" } },
    { type = "questing.Comment",        label = "Comment",       color = "#78716C", icon = "#",
      token = "text_muted",
      default_intent = { text = "" } },
    { type = "questing.Grind",          label = "Grind",         color = "#FA8080", icon = "G",
      token = "danger",
      default_intent = { targets = {}, polygon = { x = 0, y = 0, z = 0, radius = 50 }, loot = false } },
    { type = "questing.Bank",           label = "Bank",          color = "#94A3B8", icon = "B",
      token = "text_muted",
      default_intent = { npc_entry = 0 } },
    { type = "questing.LearnFlightPath", label = "LearnFlightPath", color = "#2DD4BF", icon = "L",
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
    return setmetatable({
        campaign_name = nil,
        graph_name = nil,

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

        -- Loading / error
        loading = false,
        error = nil,
        _dirty = true,
    }, GraphState)
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

---Get the display colour for a node type.
function GraphState.node_color(type_str)
    local info = NODE_TYPE_INDEX[type_str]
    return info and info.color or "#94A3B8"
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
    self.nodes = {}
    self.edges = {}
    self.selected_node = nil
    self.selected_edge = nil
    self.expanded = {}
    self.error = nil
    self.loading = true
    self._dirty = true
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

local CHAR_W = 7
local PAD = 12
local CONTROL_H = 28
local SECTION_H = 20
local ROW_H = 18
local LINE_H = 16
local SMALL_H = 14

local Theme = require("ui/theme")

local function fit_label(text, width)
    text = tostring(text or "")
    local max_chars = math.floor((width or 0) / CHAR_W)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

local function intent_preview(node_type, intent)
    local info = NODE_TYPE_INDEX[node_type]
    if not info then return "" end
    local label = info.label
    if node_type == "questing.Travel" then
        return string.format("%s: %s", label, intent.destination or "")
    elseif node_type == "questing.AcceptQuest" then
        return string.format("%s: Q#%s", label, tostring(intent.quest_id or 0))
    elseif node_type == "questing.Kill" then
        return string.format("%s: x%s", label, tostring(intent.count or 1))
    elseif node_type == "questing.TurnInQuest" then
        return string.format("%s: Q#%s", label, tostring(intent.quest_id or 0))
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
        table.insert(fields, { key = "quest_id", label = "Quest ID", value = intent.quest_id or 0 })
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
        table.insert(fields, { key = "auto_complete_dialog", label = "Auto Dialog", value = intent.auto_complete_dialog or false })
    elseif node_type == "questing.Kill" then
        table.insert(fields, { key = "creature_entry", label = "Creature Entry", value = intent.creature_entry or 0 })
        table.insert(fields, { key = "count", label = "Count", value = intent.count or 1 })
        table.insert(fields, { key = "loot", label = "Loot", value = intent.loot or false })
        table.insert(fields, { key = "ignore_elites", label = "Ignore Elites", value = intent.ignore_elites or false })
    elseif node_type == "questing.TurnInQuest" then
        table.insert(fields, { key = "quest_id", label = "Quest ID", value = intent.quest_id or 0 })
        table.insert(fields, { key = "npc_entry", label = "NPC Entry", value = intent.npc_entry or 0 })
        table.insert(fields, { key = "choose_reward", label = "Reward Choice", value = intent.choose_reward or 0 })
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
---@return table { items }
function GraphState.build_plan(view, bounds)
    local items = {}
    local text_x = bounds.x + PAD
    local content_w = math.max(0, bounds.w - PAD * 2)
    local y = bounds.y + PAD

    local function push(item) items[#items + 1] = item end
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

    -- ====================================================================
    -- No campaign loaded
    -- ====================================================================
    if not view.campaign_name or view.campaign_name == "" then
        push({
            kind = "empty_state",
            bounds = { x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h },
            title = "No Campaign",
            message = "Open a campaign to edit its behavior graph",
        })
        return { items = items }
    end

    if view.loading then
        text_item("body", "text_muted", "Loading campaign data...")
        return { items = items }
    end

    if view.error then
        text_item("body", "danger", "Error: " .. tostring(view.error))
        return { items = items }
    end

    -- ====================================================================
    -- Toolbar row
    -- ====================================================================
    local node_types = GraphState.all_node_types()
    local add_label = "Add Node"
    if view.filter_type then
        local fi = NODE_TYPE_INDEX[view.filter_type]
        add_label = add_label .. " (" .. (fi and fi.label or view.filter_type) .. ")"
    end

    -- Add Node button + type chips row
    local chip_w = 0
    for i, nt in ipairs(node_types) do
        if i <= 5 then  -- Show first 5 as inline chips
            chip_w = chip_w + (#nt.label * CHAR_W + Theme.space.lg)
        end
    end
    local max_type_chips = math.floor(content_w / (64 + Theme.space.sm))
    local shown_types = 0

    push({
        kind = "button", id = "add_node_toggle",
        bounds = { x = text_x, y = y, w = math.min(100, content_w), h = CONTROL_H },
        label = add_label, variant = "primary",
    })
    local cx = text_x + math.min(100, content_w) + Theme.space.sm

    -- Type filter chips (limited to fit)
    for _, nt in ipairs(node_types) do
        if shown_types >= max_type_chips then break end
        local w = #nt.label * CHAR_W + Theme.space.lg
        if cx + w > text_x + content_w then break end
        push({
            kind = "chip", id = "filter_type:" .. nt.type,
            bounds = { x = cx, y = y, w = w, h = CONTROL_H },
            label = nt.label, selected = view.filter_type == nt.type,
            tone = nt.token,
        })
        cx = cx + w + Theme.space.sm
        shown_types = shown_types + 1
    end

    y = y + CONTROL_H + Theme.space.sm

    -- Second toolbar row: actions
    local actions = {}
    table.insert(actions, { kind = "button", id = "validate", label = "Validate", width = 80 })
    table.insert(actions, { kind = "button", id = "compile", label = "Compile", width = 80 })
    table.insert(actions, { kind = "spacer", id = "spacer1" })

    local escort_label = view.escort_mode and "Stop Escort" or "Escort Rec"
    table.insert(actions, {
        kind = "chip", id = "toggle_escort",
        label = escort_label, width = 90,
        tone = view.escort_mode and "warning" or nil,
        selected = view.escort_mode,
    })

    local wp_label = view.waypoint_mode and "Stop WP" or "Capture WP"
    table.insert(actions, {
        kind = "chip", id = "toggle_waypoint",
        label = wp_label, width = 90,
        tone = view.waypoint_mode and "info" or nil,
        selected = view.waypoint_mode,
    })

    push({
        kind = "toolbar", id = "graph_toolbar",
        bounds = { x = text_x, y = y, w = content_w, h = Theme.metrics.toolbar_height },
        items = actions,
    })
    y = y + Theme.metrics.toolbar_height + Theme.space.sm

    -- Waypoint capture indicator
    if view.waypoint_mode and view.current_position then
        local pos = view.current_position
        local pos_str = string.format("Position: (%.0f, %.0f, %.0f)", pos.x or 0, pos.y or 0, pos.z or 0)
        text_item("caption", "info", pos_str, 0, 0)
        y = y + SMALL_H

        push({
            kind = "button", id = "commit_waypoint",
            bounds = { x = text_x, y = y, w = math.min(140, content_w), h = CONTROL_H },
            label = "Commit Waypoint", variant = "primary",
        })
        y = y + CONTROL_H + Theme.space.sm
    end

    -- Escort recording indicator
    if view.escort_mode then
        text_item("caption", "warning",
            string.format("Recording escort: %d pts captured", view.escort_timeline_count or 0))
        y = y + SMALL_H

        push({
            kind = "button", id = "generate_escort_nodes",
            bounds = { x = text_x, y = y, w = math.min(160, content_w), h = CONTROL_H },
            label = "Generate Nodes from Recording", variant = "primary",
        })
        y = y + CONTROL_H + Theme.space.sm
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
            local icon = nt and nt.icon or "?"
            local preview = node.preview or intent_preview(node.type, node.intent or {})
            local is_selected = view.selected_node == node.id
            local is_expanded = view.expanded and view.expanded[node.id]

            -- Row click to select
            local row_bounds = {
                x = text_x, y = y,
                w = content_w, h = ROW_H + 4,
            }
            push({
                kind = "list_row", id = "select_node:" .. node.id,
                bounds = row_bounds, label = icon .. " " .. label .. ": " .. fit_label(preview, content_w - 20),
                selected = is_selected, tone = token,
            })
            y = y + ROW_H + 4

            -- If selected, add action buttons
            if is_selected then
                local btn_w = math.min(70, (content_w - Theme.space.sm) * 0.33)
                push({
                    kind = "button", id = "toggle_expand:" .. node.id,
                    bounds = { x = text_x, y = y, w = btn_w, h = CONTROL_H },
                    label = is_expanded and "Collapse" or "Edit",
                    variant = "secondary",
                })
                push({
                    kind = "button", id = "remove_node:" .. node.id,
                    bounds = { x = text_x + btn_w + Theme.space.sm, y = y, w = btn_w, h = CONTROL_H },
                    label = "Delete", variant = "danger",
                })
                y = y + CONTROL_H + Theme.space.xs
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

                    -- For editable fields, add a small edit button
                    if type(field.value) ~= "table" and field.key ~= "" then
                        local edit_id = string.format("edit_intent:%s:%s", node.id, field.key)
                        push({
                            kind = "button", id = edit_id,
                            bounds = { x = text_x + content_w - 50, y = y - SMALL_H, w = 48, h = SMALL_H - 2 },
                            label = "Edit", variant = "ghost",
                        })
                    end
                end

                -- Combat Area Editor (F18) — inline for Grind nodes
                if node.type == "questing.Grind" then
                    y = y + Theme.space.xs
                    section("Combat Area")
                    local combat_note = "Set spot coords, safe spot, pull & leash"
                    text_item("caption", "text_muted", combat_note)
                    y = y + SMALL_H
                end

                y = y + Theme.space.sm
            end
        end
    else
        push({
            kind = "empty_state",
            bounds = { x = bounds.x + Theme.space.sm, y = y,
                      w = bounds.w - Theme.space.sm * 2,
                      h = math.max(1, bounds.y + bounds.h - y - PAD) },
            title = "No Nodes",
            message = "Add a behavior node using the toolbar above",
        })
    end

    return { items = items }
end

-- ============================================================================
-- Reduce — map an activated control id to a command for the host
-- ============================================================================

function GraphState.reduce(action_id)
    if action_id == nil then return nil end

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

    -- Validate / Compile
    if action_id == "validate" then
        return { kind = "validate_graph" }
    end
    if action_id == "compile" then
        return { kind = "compile_graph" }
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
