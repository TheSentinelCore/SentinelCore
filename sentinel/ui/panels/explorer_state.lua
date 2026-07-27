-- sentinel/ui/panels/explorer_state.lua
-- The Explorer panel's view-model for browsing and inspecting quests.
--
-- The panel presents a two-pane layout: a searchable quest list on the left and a
-- detail view (info, chain, objectives, actions) on the right. All state lives here;
-- `explorer.lua` only renders whatever `build()` returns.

local AsyncSlot = require("ui/async_slot")
local TextInputState = require("ui/text_input_state")

local ExplorerState = {}
ExplorerState.__index = ExplorerState

-- How long the typing has to stop before the query goes out, in SECONDS -- the unit
-- `ide_panels.lua::default_clock` answers in, which reads `core.time()`. The spec asks for 300ms;
-- issuing one request per keystroke instead would put roughly ten in flight for a five-letter zone
-- name, and `AsyncSlot` holds one request per slot, so all but the last would be abandoned mid-poll.
ExplorerState.SEARCH_DEBOUNCE_S = 0.30

-- ============================================================================
-- Construction
-- ============================================================================

function ExplorerState.new(opts)
    opts = opts or {}
    local state = setmetatable({
        search_query = opts.search_query or "",
        results = opts.results or {},          -- { id, title, level, min_level }[]
        selected_id = nil,     -- selected quest ID
        selected_detail = nil, -- full QuestDetail from server
        chain_data = nil,      -- from /quest/{id}/chain
        objectives = nil,      -- from /quest/{id}/objectives
        zone_filter = nil,
        level_min = nil,
        level_max = nil,
        loading = false,
        error = nil,
        _dirty = true,          -- needs refresh
        _query_changed_at = nil, -- when the query last changed; nil means nothing is waiting
        _cache = {},            -- simple quest detail cache
    }, ExplorerState)

    -- The buffer the operator types into. It lives on the state rather than in the widget for the
    -- same reason everything else does: a buffer owned by a render callback is a buffer no offline
    -- test can read (ADR 09b §2.1).
    state.search_input = TextInputState.new({
        id = "explorer_search", value = state.search_query, max_length = 64,
    })

    -- One slot per in-flight request. They are independent because they resolve independently:
    -- the chain may still be pending long after the detail landed.
    state._slots = {
        detail = AsyncSlot.new({ label = "quest detail", owner = state }),
        chain = AsyncSlot.new({ label = "quest chain", owner = state }),
        objectives = AsyncSlot.new({ label = "quest objectives", owner = state }),
        search = AsyncSlot.new({ label = "quest search", owner = state }),
    }
    return state
end

-- ============================================================================
-- Mutators — each marks dirty so the binding's tick picks it up
-- ============================================================================

---@param q string the new query
---@param now number|nil the clock reading that stamps the debounce; nil means "fire immediately"
function ExplorerState:set_query(q, now)
    q = tostring(q or "")
    if self.search_query == q then return end
    self.search_query = q
    self._query_changed_at = tonumber(now)
    self._search_waiting = true
    self._dirty = true
end

---Pull whatever has been typed into the search box into the query. TICK CONTEXT.
---
---Typing happens inside a render callback, where the buffer can be mutated but nothing can be
---scheduled -- the binding's `on_tick` returns early unless `_dirty` is set, and the widget has no
---way to set it. So the tick reads the buffer instead, and this is deliberately called BEFORE the
---dirty gate rather than after it.
---@param now number|nil the clock reading, or nil when there is no clock
---@return boolean changed whether the query moved
function ExplorerState:sync_search_input(now)
    local input = self.search_input
    if not input then return false end
    -- The buffer while focused, the committed value once Enter or Escape has settled it. Reading
    -- `buffer` unconditionally would let an Escape'd edit search for the string it just discarded.
    local typed = input.focused and input.buffer or input.value
    if typed == self.search_query then return false end
    self:set_query(typed, now)
    return true
end

---Whether the debounced search should go out on this tick.
---
---Stays TRUE across the whole in-flight fetch, and is cleared only by `mark_search_served`. A gate
---that closed the moment the request was fired would starve `AsyncSlot`'s pending re-arm of the
---tick that collects the answer -- the exact freeze PR2 exists to have removed.
---@param now number|nil nil (no clock) reads as due, matching `ide_panels.lua::default_clock`
function ExplorerState:search_due(now)
    if not self._search_waiting then return false end
    if self.search_query == "" then return false end
    now = tonumber(now)
    if now == nil or self._query_changed_at == nil then return true end
    return (now - self._query_changed_at) >= ExplorerState.SEARCH_DEBOUNCE_S
end

---The results for the current query have landed; stop asking for them.
function ExplorerState:mark_search_served()
    self._search_waiting = false
    self._query_changed_at = nil
end

function ExplorerState:select(id)
    id = tonumber(id)
    if not id then return end
    if self.selected_id == id then return end
    self.selected_id = id
    self.selected_detail = nil
    self.chain_data = nil
    self.objectives = nil
    self.error = nil
    -- The three requests already in flight are for the PREVIOUS quest. Abandoning them here keeps
    -- their tick count from expiring the fetches this selection is about to start.
    self._slots.detail:reset()
    self._slots.chain:reset()
    self._slots.objectives:reset()
    self._dirty = true
end

function ExplorerState:set_zone_filter(zone)
    if self.zone_filter == zone then return end
    self.zone_filter = zone
    self._dirty = true
end

function ExplorerState:set_level_range(min_val, max_val)
    min_val = tonumber(min_val)
    max_val = tonumber(max_val)
    if self.level_min == min_val and self.level_max == max_val then return end
    self.level_min = min_val
    self.level_max = max_val
    self._dirty = true
end

function ExplorerState:reset()
    self.search_query = ""
    if self.search_input then self.search_input:set_value("") end
    self._search_waiting = false
    self._query_changed_at = nil
    self.results = {}
    self.selected_id = nil
    self.selected_detail = nil
    self.chain_data = nil
    self.objectives = nil
    self.zone_filter = nil
    self.level_min = nil
    self.level_max = nil
    self.loading = false
    self.error = nil
    self._dirty = true
end

-- ============================================================================
-- Reduce — map an activated control id to a command for the host
-- ============================================================================

---Convert a fired action ID into a command table.
---@param action_id string|nil the id from the activated widget
---@return table|nil command { kind, ... }
function ExplorerState.reduce(action_id)
    if action_id == nil then return nil end

    if action_id == "clear_search" then
        return { kind = "clear_search" }
    end
    -- The VALUE is not in the id: it is already on `state.search_input`, and threading a
    -- user-typed string through an id that `reduce` then has to split on ":" would break on the
    -- first quest name containing one.
    if action_id == "search_input_submit" then
        return { kind = "submit_search" }
    end
    if action_id == "search_input_cancel" then
        return { kind = "cancel_search" }
    end
    if action_id == "zone_filter" then
        return { kind = "cycle_zone_filter" }
    end
    if action_id == "level_filter" then
        return { kind = "cycle_level_filter" }
    end

    local prefix, id_str = action_id:match("^(.-):(%d+)$")
    if not prefix or not id_str then return nil end
    local num = tonumber(id_str)
    if not num then return nil end

    if prefix == "select_quest" then
        return { kind = "select_quest", id = num }
    end
    if prefix == "add_to_profile" then
        return { kind = "add_to_profile", quest_id = num }
    end
    if prefix == "add_chain" then
        return { kind = "add_chain", quest_id = num }
    end

    return nil
end

-- ============================================================================
-- Authoring — turning a quest into campaign nodes
-- ============================================================================

-- `/quest/{id}/objectives` answers `kind` as one of exactly three lowercase strings
-- (`query-types::ObjectiveResponseItem`). Anything else is data this build does not know how to
-- lower, and is skipped with a diagnostic rather than guessed at.
--
-- `collect` becomes a Loot rather than a Kill even when the item drops from a creature: the item is
-- what the objective is counted in, and `source_creatures` rides along on the node so the compiler
-- can lower it to a Kill-with-loot without a second lookup. Both are authoring nodes a human
-- reviews before compiling (F3-R4/R6), not runtime actions.
local OBJECTIVE_NODES = {
    kill = function(ob)
        return "questing.Kill",
            { creature_entry = ob.entry, count = ob.count or 1, loot = false, ignore_elites = false }
    end,
    collect = function(ob)
        return "questing.Loot",
            { item_id = ob.entry, object_entry = ob.entry, count = ob.count or 1,
              source_creatures = ob.source_creatures or {} }
    end,
    interact = function(ob)
        return "questing.Loot",
            { object_entry = ob.entry, item_id = 0, count = ob.count or 1, source_creatures = {} }
    end,
}

---The AcceptQuest → objectives → TurnInQuest subgraph for one quest.
---
---Ids are derived from the quest and the objective index rather than generated, so adding the same
---quest twice is visible as a duplicate instead of silently producing two indistinguishable copies.
---The editor assigns the real UUIDs on write.
---@param quest_id number
---@param detail table|nil the QuestDetail, for giver/finisher entries
---@param objectives table|nil the QuestObjectivesResponse
---@return table nodes, table skipped the objective kinds that had no mapping
function ExplorerState.build_quest_subgraph(quest_id, detail, objectives)
    quest_id = tonumber(quest_id) or 0
    detail = detail or {}
    local nodes, skipped = {}, {}
    local stem = "q" .. tostring(quest_id) .. "_"

    nodes[#nodes + 1] = {
        id = stem .. "accept", type = "questing.AcceptQuest",
        preview = "AcceptQuest " .. tostring(quest_id),
        intent = { quest_id = quest_id, npc_entry = detail.giver_entry or 0,
                   auto_complete_dialog = false },
    }

    for _, ob in ipairs((objectives or {}).objectives or {}) do
        local build = OBJECTIVE_NODES[tostring(ob.kind or "")]
        if build then
            local node_type, intent = build(ob)
            nodes[#nodes + 1] = {
                id = stem .. "obj" .. tostring(ob.index or #nodes),
                type = node_type, intent = intent,
                preview = (ob.name or node_type) .. " x" .. tostring(ob.count or 1),
            }
        else
            skipped[#skipped + 1] = tostring(ob.kind)
        end
    end

    nodes[#nodes + 1] = {
        id = stem .. "turnin", type = "questing.TurnInQuest",
        preview = "TurnInQuest " .. tostring(quest_id),
        intent = { quest_id = quest_id, npc_entry = detail.finisher_entry or 0, choose_reward = 0 },
    }
    return nodes, skipped
end

---Accept/turn-in pairs for every quest in a chain, in prerequisite → follow-up order.
---
---No objective nodes: `/quest/{id}/chain` carries `{ quest_id, title }` per entry and nothing more,
---and one fetch per chain member is a request storm the panel would have to hold pending. The
---human fills the middles in, which is what F3-R4's "reviewable before commit" is for.
---@param chain table|nil the chain response
---@return table nodes
function ExplorerState.build_chain_subgraph(chain)
    chain = chain or {}
    local nodes = {}

    local function pair_for(quest_id, title)
        quest_id = tonumber(quest_id)
        if not quest_id then return end
        local stem = "q" .. tostring(quest_id) .. "_"
        nodes[#nodes + 1] = {
            id = stem .. "accept", type = "questing.AcceptQuest",
            preview = "AcceptQuest " .. (title or tostring(quest_id)),
            intent = { quest_id = quest_id, npc_entry = 0, auto_complete_dialog = false },
        }
        nodes[#nodes + 1] = {
            id = stem .. "turnin", type = "questing.TurnInQuest",
            preview = "TurnInQuest " .. (title or tostring(quest_id)),
            intent = { quest_id = quest_id, npc_entry = 0, choose_reward = 0 },
        }
    end

    for _, pre in ipairs(chain.prerequisites or {}) do pair_for(pre.quest_id, pre.title) end
    pair_for(chain.quest_id, chain.title)
    for _, fu in ipairs(chain.follow_ups or {}) do pair_for(fu.quest_id, fu.title) end
    return nodes
end

-- ============================================================================
-- Build plan — produce the draw items for one frame
-- ============================================================================

-- Layout constants mirroring widget conventions
local CHAR_W = 7
local PAD = 12
local CONTROL_H = 28
local SECTION_H = 16 + 4
local ROW_H = 14 + 4
local SMALL_H = 12 + 4

---The caption line under a result: level, zone and faction from one `QuestSummary`.
---
---An ABSENT field is drawn as an em dash rather than skipped or guessed. `QuestSummary.zone` is
---deliberately the empty string when `quest_template.ZoneOrSort` is non-positive -- mangos overloads
---that column and a negative value is a *sort* bucket, not an area id -- so there is genuinely no
---zone to show, and inventing one would be the same class of fiction as the mock scans PR3 deleted.
---
---`faction` is not on `QuestSummary` at all today, so it renders as a dash until the server carries
---it; the field is read rather than fabricated so it lights up the moment it exists.
---@param result table a QuestSummary
---@return string
function ExplorerState.result_meta(result)
    local function shown(value)
        value = tostring(value or "")
        return value ~= "" and value or "—"
    end
    return string.format("Lv %s  ·  %s  ·  %s",
        shown(result.level), shown(result.zone), shown(result.faction))
end

---Build the draw plan items from a view and bounds.
---@param view table from build()
---@param bounds table { x, y, w, h }
---@return table { items }
--
-- NOTE: This function is NOT in explorer.lua because that module is subject to structural
-- audits (ADR 09b §2.1) forbidding `if`, `elseif`, and `while` — all decision logic must
-- live here in the view-model.
function ExplorerState.build_plan(view, bounds)
    local Theme = require("ui/theme")
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

    local function fit(text, width)
        text = tostring(text or "")
        local max_chars = math.floor((width or 0) / CHAR_W)
        if max_chars < 1 then return "" end
        if #text <= max_chars then return text end
        if max_chars <= 3 then return text:sub(1, max_chars) end
        return text:sub(1, max_chars - 3) .. "..."
    end

    local function centred_y(bounds_inner, role)
        return bounds_inner.y + (bounds_inner.h - Theme.line_height[role]) * 0.5
    end

    -- ---- 1. Toolbar: search + clear + filter chips -------------------------
    local search_w = content_w * 0.6

    -- A real editable field, not a label in a rounded rect. The rect it replaced looked identical
    -- and could not be typed into, which is how the search bar shipped inert.
    push({
        kind = "text_input", id = "search_input",
        bounds = { x = text_x, y = y, w = search_w, h = CONTROL_H },
        model = view.search_input, placeholder = "Search quests...",
    })

    local clear_x = text_x + search_w + Theme.space.sm
    local clear_w = math.max(70, math.min(80, content_w - search_w - Theme.space.sm))
    push({
        kind = "button", id = "clear_search",
        bounds = { x = clear_x, y = y, w = clear_w, h = CONTROL_H },
        label = "Clear", variant = "ghost", disabled = view.search_query == "",
    })

    y = y + CONTROL_H + Theme.space.sm

    -- Filter row
    local zone_label = view.zone_filter and ("Zone: " .. view.zone_filter) or "All Zones"
    local zone_w = #zone_label * CHAR_W + Theme.space.xl
    push({
        kind = "chip", id = "zone_filter",
        bounds = { x = text_x, y = y, w = zone_w, h = CONTROL_H },
        label = zone_label, selected = view.zone_filter ~= nil,
    })

    local lvl_label = "Levels"
    if view.level_min then
        lvl_label = lvl_label .. " " .. tostring(view.level_min)
        if view.level_max then lvl_label = lvl_label .. "-" .. tostring(view.level_max) end
    end
    local lvl_w = #lvl_label * CHAR_W + Theme.space.xl
    push({
        kind = "chip", id = "level_filter",
        bounds = { x = text_x + zone_w + Theme.space.sm, y = y, w = lvl_w, h = CONTROL_H },
        label = lvl_label, selected = view.level_min ~= nil,
    })

    y = y + CONTROL_H + Theme.space.md

    -- ---- 2. Split pane: list (left) | detail (right) -----------------------
    local divider_x = bounds.x + math.floor(bounds.w * 0.55)
    local list_w = divider_x - bounds.x - PAD
    local detail_x = divider_x + Theme.space.sm
    local detail_w = bounds.x + bounds.w - detail_x - PAD
    local list_bottom = bounds.y + bounds.h - PAD

    -- Divider line
    push({
        kind = "rect",
        bounds = { x = divider_x - 1, y = y, w = 2, h = math.max(1, list_bottom - y) },
        token = "border",
    })

    -- ---- 2a. Left: quest list ------------------------------------------------
    local visible = view.visible_results or {}
    if #visible > 0 then
        local row_y = y
        for _, result in ipairs(visible) do
            if row_y + ROW_H + 2 > list_bottom then break end
            local row_bounds = { x = bounds.x + Theme.space.sm, y = row_y,
                                w = list_w - Theme.space.sm, h = ROW_H + 4 }
            push({
                kind = "list_row", id = "select_quest:" .. tostring(result.id),
                bounds = row_bounds, label = result.title or "",
                secondary = ExplorerState.result_meta(result),
                selected = view.selected_id == result.id,
            })
            row_y = row_y + ROW_H + 2
        end
    else
        local title = view.loading and "Searching..." or "Explore quests"
        local message = view.loading and "Loading quest data..."
            or "Use the search bar above to find quests"
        push({
            kind = "empty_state",
            bounds = { x = bounds.x + Theme.space.sm, y = y, w = list_w, h = math.max(1, list_bottom - y) },
            title = title, message = message,
        })
    end

    -- ---- 2b. Right: detail panel --------------------------------------------
    if view.selected_detail then
        local dy = y
        local dw = detail_w

        -- Quest header
        text_item("title", "text_primary", fit(view.selected_detail.title or "Quest", dw))
        dy = dy + Theme.line_height.title + Theme.space.xs

        local info = string.format("Level: %s  Min Level: %s",
            tostring(view.selected_detail.level or "?"),
            tostring(view.selected_detail.min_level or "?"))
        text_item("body", "text_secondary", fit(info, dw), 0, dy - y)
        dy = dy + Theme.line_height.body + Theme.space.sm

        if view.selected_detail.giver_entry then
            text_item("caption", "text_muted",
                fit("Giver: NPC #" .. tostring(view.selected_detail.giver_entry), dw), 0, dy - y)
            dy = dy + SMALL_H
        end

        dy = dy + Theme.space.sm

        -- Chain section
        local chain = view.chain_viz
        if chain then
            push({
                kind = "section_header",
                bounds = { x = detail_x, y = dy, w = dw, h = SECTION_H },
                title = "Chain (" .. tostring(chain.chain_depth) .. " deep)",
            })
            dy = dy + SECTION_H + Theme.space.xs

            if #chain.prerequisites > 0 then
                text_item("caption", "text_muted", fit("Prerequisites:", dw), 0, dy - y)
                dy = dy + SMALL_H
                for _, pre in ipairs(chain.prerequisites) do
                    text_item("body", "text_secondary",
                        fit("  " .. (pre.title or ""), dw - Theme.space.md), Theme.space.md, dy - y)
                    dy = dy + ROW_H
                end
            end
            if #chain.follow_ups > 0 then
                text_item("caption", "text_muted", fit("Follow-ups:", dw), 0, dy - y)
                dy = dy + SMALL_H
                for _, fu in ipairs(chain.follow_ups) do
                    text_item("body", "text_secondary",
                        fit("  " .. (fu.title or ""), dw - Theme.space.md), Theme.space.md, dy - y)
                    dy = dy + ROW_H
                end
            end
            dy = dy + Theme.space.sm
        end

        -- Objectives section
        local obs = view.objectives_viz
        if obs then
            push({
                kind = "section_header",
                bounds = { x = detail_x, y = dy, w = dw, h = SECTION_H },
                title = "Objectives",
            })
            dy = dy + SECTION_H + Theme.space.xs
            for _, ob in ipairs(obs.items or {}) do
                local glyph = (ob.kind == "kill") and "K" or (ob.kind == "collect") and "C" or "I"
                local label = string.format(" %s  %s (%d)", glyph, ob.name or "", ob.count or 0)
                text_item("body", "text_primary",
                    fit(label, dw - Theme.space.sm), Theme.space.sm, dy - y)
                dy = dy + ROW_H
            end
            dy = dy + Theme.space.sm
        end

        -- Actions section
        dy = math.max(dy, list_bottom - CONTROL_H * 2 - Theme.space.md * 2)
        if dy + SECTION_H + Theme.space.sm + CONTROL_H <= list_bottom then
            push({
                kind = "section_header",
                bounds = { x = detail_x, y = dy, w = dw, h = SECTION_H },
                title = "Actions",
            })
            dy = dy + SECTION_H + Theme.space.sm

            local half_w = (dw - Theme.space.sm) * 0.5
            push({
                kind = "button", id = "add_to_profile:" .. tostring(view.selected_id),
                bounds = { x = detail_x, y = dy, w = half_w, h = CONTROL_H },
                label = "Add to Profile", variant = "primary",
            })
            push({
                kind = "button", id = "add_chain:" .. tostring(view.selected_id),
                bounds = { x = detail_x + half_w + Theme.space.sm, y = dy, w = half_w, h = CONTROL_H },
                label = "Add Chain", variant = "secondary",
            })
        end
    elseif view.loading then
        text_item("body", "text_muted",
            fit("Loading...", detail_w), 0,
            centred_y({ y = y, h = math.max(1, list_bottom - y) }, "body") - y)
    elseif view.selected_id and not view.selected_detail then
        text_item("body", "text_muted",
            fit("Loading quest details...", detail_w), 0,
            centred_y({ y = y, h = math.max(1, list_bottom - y) }, "body") - y)
    else
        text_item("body", "text_muted",
            fit("Select a quest to view details", detail_w), 0,
            centred_y({ y = y, h = math.max(1, list_bottom - y) }, "body") - y)
    end

    -- Error overlay
    if view.error and view.error ~= "" then
        text_item("body", "danger",
            fit("Error: " .. tostring(view.error), content_w), 0,
            centred_y({ y = bounds.y, h = bounds.h }, "body") - bounds.y - PAD)
    end

    return { items = items }
end

-- ============================================================================
-- Build — produce the flat view the render layer draws
-- ============================================================================

---Produce the view the render layer needs. Pure: reads state, returns a table.
---@return table { visible_results, selected_detail, chain_viz, objectives_viz,
---                 loading, error, selected_id, search_query }
function ExplorerState:build()
    -- Filter results by zone/level
    local visible = {}
    for _, r in ipairs(self.results or {}) do
        if self.zone_filter and r.zone ~= self.zone_filter then
            -- skip
        elseif self.level_min and (r.level or 0) < self.level_min then
            -- skip
        elseif self.level_max and (r.level or 0) > self.level_max then
            -- skip
        else
            visible[#visible + 1] = r
        end
    end

    -- Build chain visualization for the selected quest
    local chain_viz = nil
    if self.chain_data then
        chain_viz = {
            quest_id = self.chain_data.quest_id,
            title = self.chain_data.title,
            chain_depth = self.chain_data.chain_depth or 1,
            prerequisites = self.chain_data.prerequisites or {},
            follow_ups = self.chain_data.follow_ups or {},
            branches = self.chain_data.branches or {},
        }
    end

    -- Build objectives visualization
    local objectives_viz = nil
    if self.objectives and self.objectives.objectives then
        objectives_viz = {
            quest_id = self.objectives.quest_id,
            items = self.objectives.objectives,
            objective_text = self.objectives.objective_text or "",
        }
    end

    return {
        visible_results = visible,
        selected_detail = self.selected_detail,
        chain_viz = chain_viz,
        objectives_viz = objectives_viz,
        loading = self.loading,
        error = self.error,
        selected_id = self.selected_id,
        search_query = self.search_query,
        -- The live model, not a copy: the widget edits it in place and the tick reads what was
        -- typed. A snapshot here would make the field look editable and change nothing.
        search_input = self.search_input,
        zone_filter = self.zone_filter,
        level_min = self.level_min,
        level_max = self.level_max,
    }
end

return ExplorerState
