-- sentinel/ui/panels/properties_state.lua
-- The Properties panel's view-model (NPC Inspector, Vendor Editor, Condition Editor,
-- Inventory Rules, Loot Object Editor).
--
-- The panel is context-sensitive: it displays different editors depending on what the
-- user has selected. All state lives here; `properties.lua` only renders whatever
-- `build()` returns.
--
-- Decision logic (branches, layout arithmetic) lives in `build_plan`, which is in this
-- file — the one module tests CAN reach.

local AsyncSlot = require("ui/async_slot")

local PropertiesState = {}
PropertiesState.__index = PropertiesState

-- ============================================================================
-- Construction
-- ============================================================================

function PropertiesState.new(opts)
    opts = opts or {}
    local state = setmetatable({
        -- Current selection context (set by shell or other panels via dispatch)
        context = nil,  -- { panel_id, selection_type, selection_id }

        -- Dynamic data (loaded by on_tick based on context)
        npc_detail = nil,     -- NpcDetail from /npc/{entry}
        vendor_info = nil,    -- VendorInfo from /vendor/{entry}
        object_info = nil,    -- ObjectInfo from /object/{entry}
        npc_spawns = nil,     -- [{ map, x, y, z }]

        -- Graph node handed over by the selection bus's origin panel. There is no /node/{id}
        -- endpoint and there never will be: a node lives in the campaign the Graph panel holds.
        node_detail = nil,    -- { id, type, intent, preview }
        node_edit = nil,      -- { field, kind, draft, error } while a payload field is being edited

        -- NPC inspector tab
        npc_tab = "info",     -- "info" | "loot" | "quests" | "spawns"

        -- Vendor editor items  [{ entry, name, price, enabled, mode, threshold }]
        vendor_items = nil,

        -- Condition editor (tree of RuntimeCondition objects)
        condition_tree = nil,

        -- Inventory rules [{ entry, name, action }]
        inventory_rules = nil,
        inventory_default = nil,  -- { sell_grey, ignore_white }

        loading = false,
        error = nil,
        _dirty = true,
    }, PropertiesState)

    -- The inspector shows one context at a time, so one slot covers the npc/vendor/object fetches:
    -- they can never be in flight together, and `set_context` abandons whichever was.
    state._slots = { detail = AsyncSlot.new({ label = "inspector detail", owner = state }) }
    return state
end

-- ============================================================================
-- Mutators
-- ============================================================================

function PropertiesState:set_context(ctx)
    if ctx == nil then
        self.context = nil
        self.npc_detail = nil
        self.vendor_info = nil
        self.object_info = nil
        self.npc_spawns = nil
        self.vendor_items = nil
        self.node_detail = nil
        self.node_edit = nil
        self.condition_tree = nil
        self.inventory_rules = nil
        self.inventory_default = nil
        self.loading = false
        self.error = nil
        self._slots.detail:reset()
        self._dirty = true
        return
    end

    if self.context
        and self.context.selection_type == ctx.selection_type
        and self.context.selection_id == ctx.selection_id then
        return  -- same selection, no change
    end

    self.context = ctx
    self.npc_detail = nil
    self.vendor_info = nil
    self.object_info = nil
    self.npc_spawns = nil
    self.vendor_items = nil
    self.node_detail = nil
    self.node_edit = nil
    self.condition_tree = nil
    self.inventory_rules = nil
    self.inventory_default = nil
    self.error = nil
    self.npc_tab = "info"
    -- Whatever is in flight belongs to the selection being replaced.
    self._slots.detail:reset()
    self.loading = true
    self._dirty = true
end

function PropertiesState:set_npc_tab(tab)
    if self.npc_tab == tab then return end
    self.npc_tab = tab
end

---Hand a graph node to the inspector. Called by the binding when the selection bus reports
---`kind == "node"`: the bus stays content-free (`{kind, id}`), so the node table arrives by this
---separate door rather than riding on the event.
function PropertiesState:set_node(node)
    self.node_detail = node
    self.node_edit = nil
    self._dirty = true
end

---Begin editing one payload field. Refuses a field the node does not have, and refuses a list.
---@return boolean started
function PropertiesState:begin_node_edit(field_name)
    for _, field in ipairs(PropertiesState.node_fields(self.node_detail)) do
        if field.name == field_name then
            if not field.editable then
                self.node_edit = { field = field.name, kind = field.kind, draft = field.display,
                    error = "this field is a list; edit it in the graph" }
                return false
            end
            self.node_edit = { field = field.name, kind = field.kind, draft = tostring(field.value) }
            return true
        end
    end
    return false
end

---Replace the in-progress draft and re-validate it. This is the seam the `text_input` widget (PR6)
---feeds: the keystrokes are its problem, the meaning of the string is this file's. Validation runs
---per keystroke, not on commit, so a refusal is visible while it can still be corrected.
function PropertiesState:set_node_draft(text)
    if not self.node_edit then return end
    self.node_edit.draft = tostring(text or "")
    local _, err = PropertiesState.validate_node_field(self.node_edit.kind, self.node_edit.draft)
    self.node_edit.error = err
end

---Apply the draft to the node's intent.
---@return boolean applied, string|nil error, table|nil change { id, field, value } for the host
function PropertiesState:commit_node_edit()
    local edit = self.node_edit
    if not edit then return false, "nothing is being edited" end

    local value, err = PropertiesState.validate_node_field(edit.kind, edit.draft)
    if err then
        edit.error = err
        return false, err
    end

    local node = self.node_detail
    if type(node.intent) ~= "table" then node.intent = {} end
    node.intent[edit.field] = value
    self.node_edit = nil
    self._dirty = true
    -- The CHANGE is returned rather than written through: persisting it is a `PUT
    -- /editor/campaigns/{name}/nodes/{id}` the editor client owns (PR7), and this panel reporting a
    -- save it did not make is the phantom success the whole change is removing.
    return true, nil, { id = node.id, field = edit.field, value = value }
end

function PropertiesState:cancel_node_edit()
    self.node_edit = nil
    self._dirty = true
end

-- ============================================================================
-- Reduce — map an activated control id to a command for the host
-- ============================================================================

function PropertiesState.reduce(action_id)
    if action_id == nil then return nil end

    -- NPC tab switches
    if action_id == "npc_tab_info"   then return { kind = "set_npc_tab", tab = "info" } end
    if action_id == "npc_tab_loot"   then return { kind = "set_npc_tab", tab = "loot" } end
    if action_id == "npc_tab_quests" then return { kind = "set_npc_tab", tab = "quests" } end
    if action_id == "npc_tab_spawns" then return { kind = "set_npc_tab", tab = "spawns" } end

    -- Vendor item toggles
    local prefix, id_str = action_id:match("^(.-):(.+)$")
    if prefix == "vendor_toggle" then
        -- `item_entry`, not `entry`: `VendorInfo.entry` is the VENDOR's creature entry, and one
        -- field name meaning both is how a toggle ends up matching the wrong row.
        return { kind = "toggle_vendor_item", item_entry = tonumber(id_str) }
    end

    if prefix == "edit_node_field" then
        return { kind = "begin_node_edit", field = id_str }
    end
    if prefix == "select_condition" then
        return { kind = "select_condition", path = id_str }
    end

    -- Node payload editing
    if action_id == "commit_node_edit" then return { kind = "commit_node_edit" } end
    if action_id == "cancel_node_edit" then return { kind = "cancel_node_edit" } end

    -- Condition editor
    if action_id == "add_condition"   then return { kind = "add_condition" } end
    if action_id == "add_and_group"   then return { kind = "add_condition_group", group_type = "all" } end
    if action_id == "add_or_group"    then return { kind = "add_condition_group", group_type = "any" } end
    if action_id == "delete_condition" then return { kind = "delete_condition" } end

    -- Inventory rules
    if action_id == "add_inventory_rule"   then return { kind = "add_inventory_rule" } end
    if action_id == "clear_inventory_rules" then return { kind = "clear_inventory_rules" } end

    return nil
end

-- ============================================================================
-- Build — produce the flat view the render layer draws
-- ============================================================================

function PropertiesState:build()
    if not self.context then
        -- The error is carried through even with nothing selected. It used to be hard-coded nil
        -- here, which meant the inspector could only ever report a failure AFTER something had been
        -- selected -- so "the query server is down" was unsayable in the exact state an operator
        -- opens the panel in.
        return { context_type = nil, loading = self.loading or false, error = self.error }
    end

    local ctype = self.context.selection_type
    local view = {
        context_type = ctype,
        selection_id = self.context.selection_id,
        loading = self.loading,
        error = self.error,
    }

    if ctype == "npc" then
        view.npc_view = {
            detail = self.npc_detail,
            tab = self.npc_tab,
            spawns = self.npc_spawns,
        }
    elseif ctype == "vendor" then
        view.vendor_view = {
            info = self.vendor_info,
            items = self.vendor_items,
        }
    elseif ctype == "object" then
        view.object_view = {
            detail = self.object_info,
        }
    elseif ctype == "node" then
        view.node_view = {
            node = self.node_detail,
            edit = self.node_edit,
        }
    elseif ctype == "condition" then
        view.condition_view = {
            tree = self.condition_tree,
            path = self.condition_path,
            error = self.condition_error,
        }
    elseif ctype == "inventory" then
        view.inventory_view = {
            rules = self.inventory_rules,
            default = self.inventory_default,
            error = self.inventory_error,
        }
    end

    return view
end

-- ============================================================================
-- Server-shape projections
-- ============================================================================
-- `NpcDetail`, `VendorInfo` and `ObjectInfo` are Rust types (SentinelQuesting/query-types) and
-- reach Lua through serde, so their field names are fixed by the wire, not by this file.
--
-- Everything below reads the names serde ACTUALLY emits. The previous version read
-- `loot_entry.chance` and `quest.id` -- names no server type has ever carried -- so the loot and
-- quest tabs painted their header and then nothing, on every NPC, forever. A blank section under a
-- filled header is the worst possible failure here: it reads as "this NPC drops nothing".
--
-- These are module functions, not methods, for exactly one reason: they are where the panel's
-- decisions about server data live, and a test must be able to call them without a shell, a
-- window, or a fetch.

---`creature_template.Rank`, as the QueryServer maps it. FIVE values -- `rare elite` is ONE
---classification and does not decompose into `rare` plus `elite`. A map (rather than two boolean
---flags) is what stops a rare-elite from being reported as an elite.
local CLASSIFICATION_LABEL = {
    ["normal"]     = "Normal",
    ["elite"]      = "Elite",
    ["rare elite"] = "Rare Elite",
    ["boss"]       = "Boss",
    ["rare"]       = "Rare",
}
PropertiesState.CLASSIFICATION_LABEL = CLASSIFICATION_LABEL

---@param raw string|nil the server's `classification`
---@return string|nil display label, nil only when the server sent nothing
function PropertiesState.classification_label(raw)
    if raw == nil then return nil end
    -- An unrecognised rank is shown VERBATIM rather than folded into "Normal". Answering the
    -- least-dangerous label for a value the server added later is how an operator walks a boss.
    return CLASSIFICATION_LABEL[tostring(raw):lower()] or tostring(raw)
end

---`NpcDetail.level` is `creature_template.MinLevel`. For a spawn with a level RANGE that is the
---FLOOR, not the level you will meet. There is no range on the wire, and inventing one here would
---be a fabricated fact about a pull; it is labelled as a minimum instead.
function PropertiesState.level_label(level)
    if level == nil then return nil end
    return "Level " .. tostring(level) .. " (min)"
end

---`LootEntry.drop_chance` is a PERCENTAGE in 0..=100 (the QueryServer normalises mangos' negative
---"reference loot" chances before serialising), so these bounds are read as percent, not fraction.
local LOOT_BUCKETS = {
    { name = "Guaranteed", min = 100 },
    { name = "Common",     min = 25 },
    { name = "Uncommon",   min = 5 },
    { name = "Rare",       min = 1 },
    { name = "Very Rare",  min = 0 },
}
PropertiesState.LOOT_BUCKETS = LOOT_BUCKETS

---Group a server loot table into drop-chance buckets, densest first.
---
---Buckets rather than a flat list because a 40-row loot table sorted by item id tells an operator
---nothing about what they will actually see; the question the panel is asked is "is this farmable".
---@param loot table|nil Vec<LootEntry>
---@return table [{ name, entries }] -- empty buckets are omitted, order is LOOT_BUCKETS order
function PropertiesState.loot_buckets(loot)
    local by_name = {}
    for _, entry in ipairs(loot or {}) do
        local chance = tonumber(entry.drop_chance) or 0
        local bucket = LOOT_BUCKETS[#LOOT_BUCKETS].name
        for _, b in ipairs(LOOT_BUCKETS) do
            if chance >= b.min then
                bucket = b.name
                break
            end
        end
        if not by_name[bucket] then by_name[bucket] = { name = bucket, entries = {} } end
        local list = by_name[bucket].entries
        list[#list + 1] = entry
    end

    local out = {}
    for _, b in ipairs(LOOT_BUCKETS) do
        if by_name[b.name] then out[#out + 1] = by_name[b.name] end
    end
    return out
end

---Split `NpcDetail.quests` on `NpcQuestRef.role` ("starter" | "finisher").
---
---An NPC that both starts and turns in a quest appears in BOTH lists, which is the truth: they are
---two separate reasons to walk to it, at two different points in a guide.
---@return table starters, table finishers, table unknown_role
function PropertiesState.split_quests(quests)
    local starters, finishers, other = {}, {}, {}
    for _, q in ipairs(quests or {}) do
        local role = tostring(q.role or ""):lower()
        if role == "starter" then
            starters[#starters + 1] = q
        elseif role == "finisher" then
            finishers[#finishers + 1] = q
        else
            -- Not silently dropped: a quest ref with a role this panel does not know is still a
            -- quest this NPC is attached to, and hiding it is a missing step in a guide.
            other[#other + 1] = q
        end
    end
    return starters, finishers, other
end

---`VendorItem.price` is COPPER.
---
---A price of 0 is NOT free. It is an `ExtendedCost` row -- honor, arena points, a battleground
---mark, a badge -- for which mangos stores no copper equivalent, so the QueryServer sends 0 and the
---real cost is simply not on the wire. Painting "Free" there routes an operator to buy something
---they cannot afford, in a currency the panel never mentioned.
function PropertiesState.price_label(price)
    local copper = tonumber(price)
    if copper == nil then return "unknown cost" end
    if copper <= 0 then return "special cost" end

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end

---Merge the server's `sells` list with whatever local per-item rule state the binding has built.
---
---The rows are built from `VendorInfo.sells`, which is `Vec<VendorItem{item_entry, name, price}>`.
---It is NOT `Vec<u32>` and it carries no `mode` and no `threshold`: the panel used to read both,
---so every row fell to the `else` and reported "Ignore" for a vendor's entire stock.
---@param info table|nil VendorInfo { entry, name, repairs, sells }
---@param items table|nil local rules [{ item_entry, enabled }]
---@return table [{ item_entry, name, price_label, enabled }]
function PropertiesState.vendor_rows(info, items)
    local rule_of = {}
    for _, rule in ipairs(items or {}) do
        if rule.item_entry ~= nil then rule_of[rule.item_entry] = rule end
    end

    local rows = {}
    for _, item in ipairs((info and info.sells) or {}) do
        local rule = rule_of[item.item_entry]
        rows[#rows + 1] = {
            item_entry = item.item_entry,
            name = item.name,
            price_label = PropertiesState.price_label(item.price),
            -- No local rule means the item is simply on the vendor's list, so it defaults to ON.
            -- Defaulting OFF would render a stocked vendor as one that sells nothing worth buying.
            enabled = (rule == nil) or (rule.enabled ~= false),
        }
    end
    return rows
end

-- ============================================================================
-- Condition tree
-- ============================================================================
-- Conditions are `RuntimeCondition` values and reach the runtime ADJACENTLY TAGGED as
-- `{type, payload}` — every node built here carries a `type`, because an untagged one is the
-- fail-open `true` that made condition gating stop gating (see the repo's known-state notes).

local CONDITION_LABEL = {
    all            = function() return "ALL of:" end,
    any            = function() return "ANY of:" end,
    ["not"]        = function() return "NOT:" end,
    quest_accepted = function(c) return "QuestAccepted (" .. tostring(c.quest_id or "?") .. ")" end,
    quest_completed = function(c) return "QuestCompleted (" .. tostring(c.quest_id or "?") .. ")" end,
    quest_rewarded = function(c) return "QuestRewarded (" .. tostring(c.quest_id or "?") .. ")" end,
    has_item       = function(c) return "HasItem (" .. tostring(c.item_id or "?") .. ") x" .. tostring(c.count or 1) end,
    level_at_least = function(c) return "LevelAtLeast " .. tostring(c.level or "?") end,
    level_below    = function(c) return "LevelBelow " .. tostring(c.level or "?") end,
    class_is       = function(c) return "ClassIs " .. tostring(c.class or "?") end,
    race_is        = function(c) return "RaceIs " .. tostring(c.race or "?") end,
    faction_is     = function(c) return "FactionIs " .. tostring(c.faction or "?") end,
    always_true    = function() return "AlwaysTrue" end,
}

---One condition's display label. An unknown type renders its own tag rather than a blank row: a
---condition the panel cannot name is still a condition the runtime will evaluate.
function PropertiesState.condition_label(cond)
    if type(cond) ~= "table" then return "?" end
    local render = CONDITION_LABEL[cond.type]
    if render then return render(cond) end
    return tostring(cond.type or "?") .. " ("
        .. tostring(cond.quest_id or cond.item_id or cond.level or "?") .. ")"
end

---A tree position as a dotted index path into nested `conditions` lists. "" is the root.
local function resolve_condition(tree, path)
    if type(tree) ~= "table" then return nil end
    local node, parent, index = tree, nil, nil
    for part in tostring(path or ""):gmatch("[^%.]+") do
        local i = tonumber(part)
        local children = node and node.conditions
        if i == nil or type(children) ~= "table" or children[i] == nil then return nil end
        parent, index, node = node, i, children[i]
    end
    return node, parent, index
end

function PropertiesState:select_condition(path)
    self.condition_path = (path == "root") and "" or tostring(path or "")
    self.condition_error = nil
    self._dirty = true
end

function PropertiesState:_insert_condition(child)
    self.condition_error = nil
    if self.condition_tree == nil then
        -- The first condition becomes the tree. Wrapping it in an implicit ALL group would put a
        -- level of nesting on screen that the operator never asked for.
        self.condition_tree = child
        self.condition_path = ""
        self._dirty = true
        return true
    end

    local target = resolve_condition(self.condition_tree, self.condition_path) or self.condition_tree
    if type(target.conditions) ~= "table" then
        -- A LEAF cannot hold children, and silently promoting it to an AND group would change the
        -- meaning of a condition the operator did not touch.
        self.condition_error = "select an ALL or ANY group to add into"
        self._dirty = true
        return false, self.condition_error
    end
    target.conditions[#target.conditions + 1] = child
    self._dirty = true
    return true
end

function PropertiesState:add_condition()
    return self:_insert_condition({ type = "always_true" })
end

function PropertiesState:add_condition_group(group_type)
    if group_type ~= "all" and group_type ~= "any" then
        self.condition_error = "a condition group is ALL or ANY"
        return false, self.condition_error
    end
    return self:_insert_condition({ type = group_type, conditions = {} })
end

function PropertiesState:delete_condition()
    self.condition_error = nil
    local node, parent, index = resolve_condition(self.condition_tree, self.condition_path)
    if node == nil then
        self.condition_error = "select a condition to delete"
        self._dirty = true
        return false, self.condition_error
    end
    if parent == nil then
        self.condition_tree = nil
    else
        table.remove(parent.conditions, index)
    end
    self.condition_path = ""
    self._dirty = true
    return true
end

-- ============================================================================
-- Inventory rules
-- ============================================================================

---@param rule table|nil { entry, name, action }
function PropertiesState:add_inventory_rule(rule)
    if type(rule) ~= "table" or rule.entry == nil then
        -- A rule needs an ITEM, and this panel has no item picker: the Database is where items are
        -- found. Appending a blank row would put a rule in the list that matches nothing and reads
        -- like one that does.
        self.inventory_error = "pick an item in the Database to add a rule for"
        return false, self.inventory_error
    end
    self.inventory_error = nil
    self.inventory_rules = self.inventory_rules or {}
    self.inventory_rules[#self.inventory_rules + 1] = {
        entry = rule.entry, name = rule.name, action = rule.action or "sell",
    }
    self._dirty = true
    return true
end

function PropertiesState:clear_inventory_rules()
    self.inventory_rules = {}
    self.inventory_error = nil
    self._dirty = true
    return true
end

-- ============================================================================
-- Node payload projection and edit validation
-- ============================================================================
-- A graph node is `{ id, type, intent = {...}, preview }`. Its payload FIELDS are per kind, and the
-- authority on which fields a kind has is `graph_state`'s `default_intent` for that type -- not a
-- table copied into this file, which would drift the first time a node kind gained a field.

local function node_type_defaults(node_type)
    -- Deliberately soft: Properties must still render a node when the graph module is not loaded
    -- (the source-audit test loads this file with no SDK at all).
    local ok, GraphState = pcall(require, "ui/panels/graph_state")
    if not ok or type(GraphState) ~= "table" or type(GraphState.node_type_info) ~= "function" then
        return nil
    end
    local info = GraphState.node_type_info(node_type)
    return info and info.default_intent or nil
end

---Classify a payload value so an edit can be validated against it.
---A `table` value (a waypoint list, a spell list, a polygon) is NOT a scalar an inspector row can
---edit; claiming otherwise would let an operator overwrite a route with the string they typed.
local function field_kind(value)
    local t = type(value)
    if t == "number" or t == "boolean" or t == "string" then return t end
    return "table"
end

local function field_display(value)
    local t = type(value)
    if t == "table" then
        local n = #value
        return (n > 0) and (n .. " entries") or "list"
    end
    if t == "string" and value == "" then return "(empty)" end
    return tostring(value)
end

---The payload fields of one node, in a STABLE order.
---
---`intent` is a hash table, so `pairs` order varies between runs; the rows are sorted by name so a
---field does not move under the operator's cursor between two frames of the same node.
---@return table [{ name, value, kind, display, editable }]
function PropertiesState.node_fields(node)
    if type(node) ~= "table" then return {} end

    local values = {}
    -- The kind's declared payload comes first, so a field left at its default still gets a row
    -- instead of vanishing until someone sets it.
    for name, default in pairs(node_type_defaults(node.type) or {}) do values[name] = default end
    for name, value in pairs(type(node.intent) == "table" and node.intent or {}) do
        values[name] = value
    end

    local names = {}
    for name in pairs(values) do names[#names + 1] = name end
    table.sort(names)

    local fields = {}
    for _, name in ipairs(names) do
        local value = values[name]
        local kind = field_kind(value)
        fields[#fields + 1] = {
            name = name,
            value = value,
            kind = kind,
            display = field_display(value),
            editable = kind ~= "table",
        }
    end
    return fields
end

---Validate a typed draft against the field's declared kind.
---@return any value the coerced value, nil when invalid
---@return string|nil error why it was refused
function PropertiesState.validate_node_field(kind, raw)
    local text = tostring(raw or "")
    if kind == "number" then
        local n = tonumber(text)
        if n == nil then return nil, "must be a number" end
        return n
    elseif kind == "boolean" then
        local lowered = text:lower()
        if lowered == "true" then return true end
        if lowered == "false" then return false end
        return nil, "must be true or false"
    elseif kind == "string" then
        return text
    end
    return nil, "this field is a list; edit it in the graph"
end

-- ============================================================================
-- Build plan — produce the draw items for one frame
-- ============================================================================
-- Every if/elseif/while the render layer cannot have lives here, where tests
-- can reach it. This is the same pattern ExplorerState.build_plan follows.

local CHAR_W = 7
local PAD = 12
local CONTROL_H = 28
local SECTION_H = 20
local ROW_H = 18
local SMALL_H = 14
-- A `list_row` with a `secondary` line stacks body over caption, so it needs the taller box.
local ROW_TALL = 36

local Theme = require("ui/theme")

local function fit(text, width)
    text = tostring(text or "")
    local max_chars = math.floor((width or 0) / CHAR_W)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

function PropertiesState.build_plan(view, bounds)
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

    local function header(title, extra_y)
        push({
            kind = "section_header",
            bounds = { x = text_x, y = y, w = content_w, h = SECTION_H },
            title = title,
        })
        y = y + SECTION_H + (extra_y or Theme.space.xs)
    end

    -- -----------------------------------------------------------------------
    -- No context
    -- -----------------------------------------------------------------------
    if view.context_type == nil then
        -- An error outranks the invitation to select something: telling an operator to pick an NPC
        -- when the panel could not fetch one either way is an instruction that cannot be followed.
        push({
            kind = "empty_state",
            bounds = { x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h },
            title = view.error and "Unavailable" or "No Selection",
            message = view.error
                and ("Error: " .. tostring(view.error))
                or "Select an NPC, vendor, object or node to inspect",
        })
        return { items = items }
    end

    if view.loading then
        text_item("body", "text_muted", "Loading...")
        return { items = items }
    end

    if view.error then
        text_item("body", "danger", "Error: " .. tostring(view.error))
        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- NPC Inspector
    -- -----------------------------------------------------------------------
    if view.context_type == "npc" then
        local nv = view.npc_view
        if not nv or not nv.detail then
            text_item("body", "text_muted", "Select an NPC to inspect")
            return { items = items }
        end

        local d = nv.detail
        text_item("title", "text_primary", fit(d.name or "NPC", content_w))
        y = y + Theme.line_height.title + Theme.space.xs

        local info = "Entry: " .. tostring(d.entry or "?")
        local level = PropertiesState.level_label(d.level)
        if level then info = info .. "  " .. level end
        text_item("body", "text_secondary", fit(info, content_w))
        y = y + Theme.line_height.body + Theme.space.xs

        if d.faction then
            text_item("caption", "text_muted", fit("Faction: " .. tostring(d.faction), content_w))
            y = y + SMALL_H
        end
        y = y + Theme.space.sm

        -- Tab bar
        local tabs = {
            { id = "npc_tab_info",   label = "Info",   sel = nv.tab == "info" },
            { id = "npc_tab_loot",   label = "Loot",   sel = nv.tab == "loot" },
            { id = "npc_tab_quests", label = "Quests", sel = nv.tab == "quests" },
            { id = "npc_tab_spawns", label = "Spawns", sel = nv.tab == "spawns" },
        }
        local tx = text_x
        for _, t in ipairs(tabs) do
            local w = #t.label * CHAR_W + Theme.space.lg
            push({ kind = "chip", id = t.id,
                bounds = { x = tx, y = y, w = w, h = CONTROL_H },
                label = t.label, selected = t.sel })
            tx = tx + w + Theme.space.sm
        end
        y = y + CONTROL_H + Theme.space.md

        -- ---- Info tab ----
        if nv.tab == "info" then
            local classification = PropertiesState.classification_label(d.classification)
            if classification then
                header("Classification")
                text_item("body", "text_secondary", fit(classification, content_w), Theme.space.sm)
                y = y + ROW_H + Theme.space.sm
            end
            if d.roles and #d.roles > 0 then
                header("Roles")
                text_item("body", "text_secondary", fit(table.concat(d.roles, ", "), content_w), Theme.space.sm)
                y = y + ROW_H
            end

        -- ---- Spawns tab ----
        elseif nv.tab == "spawns" then
            -- `NpcDetail.positions` is Vec<WorldPos> {map,x,y,z}; `nv.spawns` is the same shape from
            -- a separate lookup when one has been made.
            local spawns = nv.spawns or d.positions or {}
            if #spawns > 0 then
                header("Spawns (" .. tostring(#spawns) .. ")")
                for _, sp in ipairs(spawns) do
                    local p = sp.position or sp
                    local s = string.format("  Map %s ( %.0f, %.0f, %.0f )",
                        tostring(p.map or 0), p.x or 0, p.y or 0, p.z or 0)
                    text_item("body", "text_secondary", fit(s, content_w))
                    y = y + ROW_H
                end
            else
                text_item("body", "text_muted", "No spawn data available")
                y = y + ROW_H
            end

        -- ---- Quests tab ----
        elseif nv.tab == "quests" then
            local starters, finishers, unknown = PropertiesState.split_quests(d.quests)
            local groups = {
                { title = "Starts (" .. #starters .. ")", quests = starters },
                { title = "Turns In (" .. #finishers .. ")", quests = finishers },
                { title = "Unclassified (" .. #unknown .. ")", quests = unknown },
            }
            local drew = false
            for _, group in ipairs(groups) do
                if #group.quests > 0 then
                    drew = true
                    header(group.title)
                    for _, q in ipairs(group.quests) do
                        -- `NpcQuestRef` carries `quest_id`, never `id`.
                        local label = string.format("  [%s] %s",
                            tostring(q.quest_id or "?"), tostring(q.title or ""))
                        text_item("body", "text_primary", fit(label, content_w))
                        y = y + ROW_H
                    end
                    y = y + Theme.space.sm
                end
            end
            if not drew then
                text_item("body", "text_muted", "No quest data available")
                y = y + ROW_H
            end

        -- ---- Loot tab ----
        elseif nv.tab == "loot" then
            local buckets = PropertiesState.loot_buckets(d.loot)
            if #buckets > 0 then
                for _, bucket in ipairs(buckets) do
                    header(bucket.name .. " (" .. tostring(#bucket.entries) .. ")")
                    for _, entry in ipairs(bucket.entries) do
                        -- `LootEntry` carries `item` and `drop_chance` (percent), never `chance`.
                        local chance = tonumber(entry.drop_chance)
                        local label = string.format("  [%s] %s  %s",
                            tostring(entry.item or "?"), tostring(entry.name or ""),
                            chance and string.format("%.1f%%", chance) or "?")
                        text_item("body", "text_secondary", fit(label, content_w))
                        y = y + ROW_H
                    end
                    y = y + Theme.space.sm
                end
            else
                text_item("body", "text_muted", "No loot data available")
                y = y + ROW_H
            end
        end

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Vendor Editor
    -- -----------------------------------------------------------------------
    if view.context_type == "vendor" then
        local vv = view.vendor_view
        if not vv or not vv.info then
            text_item("body", "text_muted", "Select a vendor to inspect")
            return { items = items }
        end

        local info = vv.info
        text_item("title", "text_primary", fit(info.name or "Vendor", content_w))
        y = y + Theme.line_height.title + Theme.space.xs
        text_item("body", "text_secondary", fit(
            string.format("Entry: %s    Repairs: %s", tostring(info.entry or "?"),
                info.repairs and "Yes" or "No"), content_w))
        y = y + Theme.line_height.body + Theme.space.md

        -- Rows, not text lines: the rule toggle only becomes reachable when something the operator
        -- can click carries its id. `reduce` has understood `vendor_toggle:<id>` since the panel
        -- was written, but nothing had ever pushed a control that emits one.
        local rows = PropertiesState.vendor_rows(info, vv.items)
        if #rows > 0 then
            header("Sells (" .. tostring(#rows) .. ")")
            for _, row in ipairs(rows) do
                push({
                    kind = "list_row",
                    id = "vendor_toggle:" .. tostring(row.item_entry or "?"),
                    bounds = { x = text_x, y = y, w = content_w, h = ROW_TALL },
                    label = fit(row.name or ("Item " .. tostring(row.item_entry or "?")), content_w),
                    secondary = row.price_label .. "    " .. (row.enabled and "Buy" or "Skip"),
                    selected = row.enabled,
                })
                y = y + ROW_TALL + Theme.space.xs
            end
        else
            text_item("body", "text_muted", "No inventory data available")
            y = y + ROW_H
        end

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Loot Object Editor
    -- -----------------------------------------------------------------------
    if view.context_type == "object" then
        local ov = view.object_view
        if not ov or not ov.detail then
            text_item("body", "text_muted", "Select an object to inspect")
            return { items = items }
        end

        -- `ObjectInfo` is `{entry, name, kind, position}` and nothing else. The `respawn` and `skill`
        -- lines that used to render here had no source on the wire at all -- they came from the
        -- panel's own fixture, which is exactly the "field absent from server types" the spec
        -- forbids rendering. A number an operator can read but the server never sent is worse than
        -- a gap, because a gap is visibly a gap.
        local obj = ov.detail
        text_item("title", "text_primary", fit(obj.name or "Object", content_w))
        y = y + Theme.line_height.title + Theme.space.xs
        text_item("body", "text_secondary", fit(
            string.format("Entry: %s    Type: %s", tostring(obj.entry or "?"), obj.kind or "?"), content_w))
        y = y + Theme.line_height.body + Theme.space.md

        local spawns = obj.positions or (obj.position and { obj.position }) or {}
        if #spawns > 0 then
            header("Spawns (" .. tostring(#spawns) .. ")")
            for _, p in ipairs(spawns) do
                text_item("body", "text_secondary", fit(
                    string.format("  Map %s ( %.0f, %.0f, %.0f )",
                        tostring(p.map or 0), p.x or 0, p.y or 0, p.z or 0), content_w))
                y = y + ROW_H
            end
            y = y + Theme.space.sm
        else
            text_item("body", "text_muted", "No spawn data available")
            y = y + ROW_H + Theme.space.sm
        end

        -- Tolerant of a `loot` field the endpoint does not serve TODAY, and explicit about its
        -- absence rather than silent: a lootable object with a blank loot section reads as "empty",
        -- and "we were never told" is a different fact from "there is nothing in it".
        local buckets = PropertiesState.loot_buckets(obj.loot)
        if #buckets > 0 then
            for _, bucket in ipairs(buckets) do
                header(bucket.name .. " (" .. tostring(#bucket.entries) .. ")")
                for _, entry in ipairs(bucket.entries) do
                    local chance = tonumber(entry.drop_chance)
                    text_item("body", "text_secondary", fit(string.format("  [%s] %s  %s",
                        tostring(entry.item or "?"), tostring(entry.name or ""),
                        chance and string.format("%.1f%%", chance) or "?"), content_w))
                    y = y + ROW_H
                end
                y = y + Theme.space.sm
            end
        else
            text_item("caption", "text_muted", fit("Loot is not served by /object/{entry}", content_w))
            y = y + SMALL_H
        end

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Node Inspector
    -- -----------------------------------------------------------------------
    if view.context_type == "node" then
        local nvw = view.node_view
        local node = nvw and nvw.node
        if not node then
            -- A node id alone is not a node, and saying so beats an empty pane that reads as a node
            -- with no payload.
            text_item("body", "text_muted", fit("The graph has not handed this node over", content_w))
            return { items = items }
        end

        text_item("title", "text_primary", fit(tostring(node.preview or node.type or "Node"), content_w))
        y = y + Theme.line_height.title + Theme.space.xs
        text_item("caption", "text_muted", fit(
            tostring(node.type or "?") .. "    " .. tostring(node.id or "?"), content_w))
        y = y + SMALL_H + Theme.space.md

        local fields = PropertiesState.node_fields(node)
        header("Payload (" .. tostring(#fields) .. ")")
        for _, field in ipairs(fields) do
            push({
                kind = "list_row",
                id = "edit_node_field:" .. field.name,
                bounds = { x = text_x, y = y, w = content_w, h = ROW_TALL },
                label = field.name,
                secondary = field.display .. "    " .. field.kind,
                selected = (nvw.edit and nvw.edit.field == field.name) or false,
                disabled = not field.editable,
            })
            y = y + ROW_TALL + Theme.space.xs
        end
        if #fields == 0 then
            text_item("body", "text_muted", fit("This node kind carries no payload", content_w))
            y = y + ROW_H
        end

        if nvw.edit then
            y = y + Theme.space.sm
            header("Editing " .. tostring(nvw.edit.field))
            text_item("body", "text_primary", fit(tostring(nvw.edit.draft or ""), content_w))
            y = y + ROW_H
            if nvw.edit.error then
                text_item("caption", "danger", fit(tostring(nvw.edit.error), content_w))
                y = y + SMALL_H
            end
            y = y + Theme.space.sm
            local half = (content_w - Theme.space.sm) * 0.5
            push({ kind = "button", id = "commit_node_edit",
                bounds = { x = text_x, y = y, w = half, h = CONTROL_H },
                label = "Apply", variant = "primary", disabled = nvw.edit.error ~= nil })
            push({ kind = "button", id = "cancel_node_edit",
                bounds = { x = text_x + half + Theme.space.sm, y = y, w = half, h = CONTROL_H },
                label = "Cancel", variant = "ghost" })
        end

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Condition Editor
    -- -----------------------------------------------------------------------
    if view.context_type == "condition" then
        local cv = view.condition_view
        header("Condition: " .. (cv and cv.tree and (cv.tree.type or "?") or "None"), Theme.space.md)

        if cv and cv.tree then
            -- ROWS, not text lines. `add`/`delete` act on a SELECTED node, and a tree drawn as
            -- unclickable text is a tree with no selection -- which is why those three buttons had
            -- nothing they could possibly do.
            local function render_cond(cond, depth, path)
                if not cond then return end
                push({
                    kind = "list_row",
                    id = "select_condition:" .. (path == "" and "root" or path),
                    bounds = { x = text_x + depth * Theme.space.md, y = y,
                               w = math.max(0, content_w - depth * Theme.space.md), h = CONTROL_H },
                    label = PropertiesState.condition_label(cond),
                    selected = (cv.path or "") == path,
                })
                y = y + CONTROL_H + Theme.space.xs
                for i, child in ipairs(cond.conditions or {}) do
                    render_cond(child, depth + 1, (path == "") and tostring(i) or (path .. "." .. i))
                end
                -- `not` holds ONE child under a different key; it is still a child and still needs
                -- a row, or a negated condition renders as a bare "NOT" with nothing under it.
                if cond.condition then
                    render_cond(cond.condition, depth + 1, (path == "") and "1" or (path .. ".1"))
                end
            end
            render_cond(cv.tree, 0, "")
        else
            text_item("body", "text_muted", "No condition defined")
            y = y + ROW_H
        end

        if cv and cv.error then
            text_item("caption", "danger", fit(tostring(cv.error), content_w))
            y = y + SMALL_H
        end

        y = y + Theme.space.md
        local half = (content_w - Theme.space.sm) * 0.5
        push({ kind = "button", id = "add_condition",
            bounds = { x = text_x, y = y, w = half, h = CONTROL_H }, label = "Add Condition", variant = "secondary" })
        push({ kind = "button", id = "add_and_group",
            bounds = { x = text_x + half + Theme.space.sm, y = y, w = half, h = CONTROL_H }, label = "Add Group (AND)", variant = "ghost" })
        y = y + CONTROL_H + Theme.space.sm
        push({ kind = "button", id = "add_or_group",
            bounds = { x = text_x, y = y, w = half, h = CONTROL_H }, label = "Add Group (OR)", variant = "ghost" })
        push({ kind = "button", id = "delete_condition",
            bounds = { x = text_x + half + Theme.space.sm, y = y, w = half, h = CONTROL_H }, label = "Delete", variant = "danger" })

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Inventory Rules
    -- -----------------------------------------------------------------------
    if view.context_type == "inventory" then
        local iv = view.inventory_view
        header("Inventory Rules", Theme.space.md)

        local rules = (iv and iv.rules) or {}
        if #rules > 0 then
            for _, rule in ipairs(rules) do
                local a = ""
                if rule.action == "sell" then a = "Sell"
                elseif rule.action == "keep" then a = "Keep"
                elseif rule.action == "mail" then a = "Mail to Alt"
                else a = tostring(rule.action) end
                text_item("body", "text_secondary", fit(
                    string.format("  [%s] %s    %s", tostring(rule.entry or ""), fit(rule.name or "", 18), a), content_w))
                y = y + ROW_H
            end
        else
            text_item("body", "text_muted", "No item rules defined")
            y = y + ROW_H
        end

        y = y + Theme.space.sm
        header("Default Behaviour", Theme.space.xs)

        local def = (iv and iv.default) or {}
        local sell_str = (def.sell_grey ~= false) and "Sell grey" or "Keep grey"
        local white_str = def.ignore_white and "Ignore white+" or "Keep white+"
        text_item("body", "text_secondary", fit(sell_str .. "    " .. white_str, content_w))
        y = y + ROW_H + Theme.space.sm

        if iv and iv.error then
            text_item("caption", "danger", fit(tostring(iv.error), content_w))
            y = y + SMALL_H
        end
        y = y + Theme.space.sm

        local half = (content_w - Theme.space.sm) * 0.5
        push({ kind = "button", id = "add_inventory_rule",
            bounds = { x = text_x, y = y, w = half, h = CONTROL_H }, label = "Add Rule", variant = "primary" })
        push({ kind = "button", id = "clear_inventory_rules",
            bounds = { x = text_x + half + Theme.space.sm, y = y, w = half, h = CONTROL_H }, label = "Clear All", variant = "danger" })

        return { items = items }
    end

    -- Fallback for unknown types
    text_item("body", "text_muted", fit("Unknown selection type: " .. tostring(view.context_type), content_w))
    return { items = items }
end

return PropertiesState
