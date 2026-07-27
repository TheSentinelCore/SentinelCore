-- sentinel/ui/panels/stats_dashboard.lua
-- Profile Statistics dashboard/overlay (Phase 5, F20).
--
-- Toggle inside the Runner tab. When visible, renders as a floating overlay showing
-- node/edge counts, type breakdown, estimated duration, distance, and XP.
-- Does not render as a panel — rendered on top of the Runner panel content.

local Theme = require("ui/theme")
local Geometry = require("core/geometry")

local StatsDashboard = {}
StatsDashboard.__index = StatsDashboard

-- ============================================================================
-- What each badge counts, and where the count comes from
-- ============================================================================
--
-- The spec asks for quest / waypoint / NPC / object / vendor / flight counts computed from the
-- LOADED CAMPAIGN GRAPH. Every one of them is a `distinct` count over a field the graph already
-- carries, so the number is a fact about the campaign rather than an estimate of one.
--
-- The distinctions below are deliberate and are the reason the badges are worth reading:
--
--  * QUESTS counts distinct `quest_id`, not Accept/TurnIn NODES. A quest with both is one quest;
--    counting nodes reports every quest in the campaign twice.
--  * NPCS counts distinct `npc_entry` — the characters the route TALKS to. A Kill target is a
--    `creature_entry` and is not an NPC in this sense; folding the two together would report a
--    grind of forty wolves as forty NPCs to visit.
--  * OBJECTS counts distinct game-object entries: `UseItem.target_entry` and `Loot.object_entry`.
--    `questing.Loot` executes at runtime but is absent from the Graph palette, so a campaign can
--    legitimately contain one the editor cannot draw.
--  * FLIGHTS counts `questing.Flight` nodes — hops TAKEN. `LearnFlightPath` buys a node and takes
--    no flight, so it is not one.

---Distinct-entry accumulator: `add(set, value)` ignores nil, 0 and anything non-numeric, because a
---`default_intent` field left at 0 is an unfilled form and not an entity.
local function add_entry(set, value)
    local id = tonumber(value)
    if not id or id == 0 then return set end
    set[id] = true
    return set
end

local function count_of(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

-- ============================================================================
-- Construction
-- ============================================================================

function StatsDashboard.new()
    return setmetatable({
        visible = false,
        stats = {
            total_nodes = 0,
            total_edges = 0,
            node_types = {},        -- { type_name = count }
            total_kills = 0,
            total_xp_estimate = 0,
            total_quests = 0,
            estimated_duration_min = 0,
            distance_total_yds = 0,
            waypoint_count = 0,
            node_breakdown = {},    -- { { type, count, pct } }
            quest_count = 0,
            npc_count = 0,
            object_count = 0,
            vendor_count = 0,
            flight_count = 0,
        },
        campaign_name = nil,
        _dirty = true,
    }, StatsDashboard)
end

-- ============================================================================
-- Toggle
-- ============================================================================

function StatsDashboard:toggle()
    self.visible = not self.visible
    self._dirty = true
    return self.visible
end

-- ============================================================================
-- Compute
-- ============================================================================

---Compute all statistics from a campaign plan.
---@param campaign_plan table|nil { name?, nodes?, edges?, variables? }
function StatsDashboard:compute(campaign_plan)
    if not campaign_plan then
        self:reset()
        return
    end

    self.campaign_name = campaign_plan.name or nil

    local nodes = campaign_plan.nodes or {}
    local edges = campaign_plan.edges or {}

    -- Count by type
    local node_types = {}
    local total_nodes = #nodes
    local total_kills = 0
    local total_quests = 0
    local waypoint_count = 0
    local travel_count = 0
    local accept_count = 0
    local turnin_count = 0
    local wait_count = 0
    local vendor_count = 0
    local other_count = 0

    -- The badge counts, each a distinct set over a field the graph already carries.
    local quest_ids, npc_entries, object_entries, vendor_entries = {}, {}, {}, {}
    local flight_count = 0

    for _, node in ipairs(nodes) do
        local nt = node.type or "unknown"
        local intent = node.intent or {}
        node_types[nt] = (node_types[nt] or 0) + 1

        if nt == "questing.Kill" then
            total_kills = total_kills + (node.intent and node.intent.count or 1)
        elseif nt == "questing.AcceptQuest" or nt == "questing.TurnInQuest" then
            total_quests = total_quests + 1
        end

        if nt == "questing.Travel" then
            travel_count = travel_count + 1
            if node.intent then
                -- Count waypoints from Travel nodes with destination coords
                if node.intent.x and node.intent.y then
                    waypoint_count = waypoint_count + 1
                end
            end
        end

        add_entry(quest_ids, intent.quest_id)
        add_entry(npc_entries, intent.npc_entry)
        add_entry(npc_entries, intent.innkeeper_entry)
        add_entry(object_entries, intent.target_entry)
        add_entry(object_entries, intent.object_entry)
        if nt == "questing.Vendor" then add_entry(vendor_entries, intent.npc_entry) end
        if nt == "questing.Flight" then flight_count = flight_count + 1 end
    end

    -- Type breakdown for display
    local type_order = {
        "questing.Travel", "questing.Kill", "questing.AcceptQuest",
        "questing.TurnInQuest", "questing.Wait", "questing.Vendor",
    }
    local type_labels = {
        ["questing.Travel"] = "Travel",
        ["questing.Kill"] = "Kill",
        ["questing.AcceptQuest"] = "AcceptQ",
        ["questing.TurnInQuest"] = "TurnInQ",
        ["questing.Wait"] = "Wait",
        ["questing.Vendor"] = "Vendor",
    }

    local node_breakdown = {}
    local accounted = 0
    for _, t in ipairs(type_order) do
        local count = node_types[t] or 0
        if count > 0 then
            local pct = (total_nodes > 0) and math.floor(count / total_nodes * 100 + 0.5) or 0
            table.insert(node_breakdown, {
                type = type_labels[t] or t,
                type_key = t,
                count = count,
                pct = pct,
            })
            accounted = accounted + count
        end
    end

    -- Catch any remaining (like Comment, Grind, etc.)
    local remaining = total_nodes - accounted
    if remaining > 0 then
        -- Group all remaining into "Other"
        local other_count = 0
        for t, c in pairs(node_types) do
            local is_listed = false
            for _, lt in ipairs(type_order) do
                if t == lt then is_listed = true; break end
            end
            if not is_listed then other_count = other_count + c end
        end
        if other_count > 0 then
            local pct = (total_nodes > 0) and math.floor(other_count / total_nodes * 100 + 0.5) or 0
            table.insert(node_breakdown, {
                type = "Other",
                type_key = "other",
                count = other_count,
                pct = pct,
            })
        end
    end

    -- Distance estimation: sum distances between consecutive Travel nodes
    -- (In a real scenario this would use actual path distances)
    local distance_total_yds = 0
    local travel_nodes = {}
    for _, node in ipairs(nodes) do
        if node.type == "questing.Travel" and node.intent then
            if node.intent.x and node.intent.y then
                table.insert(travel_nodes, node.intent)
            end
        end
    end
    for i = 2, #travel_nodes do
        distance_total_yds = distance_total_yds
            + Geometry.distance(travel_nodes[i - 1], travel_nodes[i])
    end

    -- Duration estimate: 30s per kill + 60s per quest + 10s per travel waypoint + 10s per wait
    local estimated_duration_min = math.ceil(
        (total_kills * 30 + total_quests * 60 + waypoint_count * 10) / 60
    )

    -- XP estimate: rough heuristic — 200 XP per kill, 800 XP per quest
    local total_xp_estimate = total_kills * 200 + total_quests * 800

    self.stats = {
        total_nodes = total_nodes,
        total_edges = #edges,
        node_types = node_types,
        total_kills = total_kills,
        total_xp_estimate = total_xp_estimate,
        total_quests = total_quests,
        estimated_duration_min = estimated_duration_min,
        distance_total_yds = math.floor(distance_total_yds + 0.5),
        waypoint_count = waypoint_count,
        node_breakdown = node_breakdown,
        -- The badge counts (spec: F20-R1/R2).
        quest_count = count_of(quest_ids),
        npc_count = count_of(npc_entries),
        object_count = count_of(object_entries),
        vendor_count = count_of(vendor_entries),
        flight_count = flight_count,
    }
    self._dirty = true
end

-- ============================================================================
-- Badges — the header chips (spec: "render them as header badge chips")
-- ============================================================================

---The six counts, in a fixed order, as chips the header row draws.
---
---A count of ZERO is kept rather than dropped. "This campaign visits no vendors" is a fact an
---operator planning a run needs; a chip row that silently shortens itself makes the absence
---indistinguishable from a campaign that was never loaded.
---@param stats table
---@return table[] `{ { id, label, count } }`
function StatsDashboard.badges(stats)
    stats = stats or {}
    return {
        { id = "stats_badge_quests",    label = "Quests",   count = stats.quest_count or 0 },
        { id = "stats_badge_waypoints", label = "Waypts",   count = stats.waypoint_count or 0 },
        { id = "stats_badge_npcs",      label = "NPCs",     count = stats.npc_count or 0 },
        { id = "stats_badge_objects",   label = "Objects",  count = stats.object_count or 0 },
        { id = "stats_badge_vendors",   label = "Vendors",  count = stats.vendor_count or 0 },
        { id = "stats_badge_flights",   label = "Flights",  count = stats.flight_count or 0 },
    }
end

---Reset stats to zero.
function StatsDashboard:reset()
    self.stats = {
        total_nodes = 0,
        total_edges = 0,
        node_types = {},
        total_kills = 0,
        total_xp_estimate = 0,
        total_quests = 0,
        estimated_duration_min = 0,
        distance_total_yds = 0,
        waypoint_count = 0,
        node_breakdown = {},
        quest_count = 0,
        npc_count = 0,
        object_count = 0,
        vendor_count = 0,
        flight_count = 0,
    }
    self.campaign_name = nil
    self._dirty = true
end

-- ============================================================================
-- Build — produce the view
-- ============================================================================

function StatsDashboard:build()
    return {
        visible = self.visible,
        stats = self.stats,
        campaign_name = self.campaign_name,
    }
end

-- ============================================================================
-- Build plan — produce the draw items for the overlay
-- ============================================================================

local CHAR_W = 7
local PAD = 16
local LINE_H = 16
local CONTROL_H = 28

local function fit_label(text, width)
    text = tostring(text or "")
    local max_chars = math.floor((width or 0) / CHAR_W)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

---Build the draw plan for the stats overlay.
---@param view table from build()
---@param bounds table { x, y, w, h }  — the panel area to overlay
---@return table { items }
function StatsDashboard.build_plan(view, bounds)
    local items = {}
    if not view.visible then return { items = items } end

    local stats = view.stats or {}

    -- Overlay dimensions (approximate floating panel)
    local overlay_w = 320
    local overlay_h = 300
    local overlay_x = bounds.x + (bounds.w - overlay_w) * 0.5
    local overlay_y = bounds.y + (bounds.h - overlay_h) * 0.3
    local text_x = overlay_x + PAD
    local content_w = overlay_w - PAD * 2
    local y = overlay_y + PAD

    local function push(item) items[#items + 1] = item end
    local function text_item(str, token, ox, oy)
        push({
            kind = "text", x = text_x + (ox or 0), y = y + (oy or 0),
            font = Theme.font.body, token = token or "text_primary",
            alpha = Theme.interaction.resting.text, text = str,
        })
    end
    local function caption_item(str, token, ox, oy)
        push({
            kind = "text", x = text_x + (ox or 0), y = y + (oy or 0),
            font = Theme.font.caption, token = token or "text_secondary",
            alpha = Theme.interaction.resting.text, text = str,
        })
    end

    -- Overlay backdrop
    push({
        kind = "overlay_bg",
        bounds = { x = overlay_x, y = overlay_y, w = overlay_w, h = overlay_h },
    })

    -- Title bar
    push({
        kind = "section_header",
        bounds = { x = text_x, y = y, w = content_w, h = 22 },
        title = "Profile Statistics",
    })
    y = y + 26

    -- Campaign name
    if view.campaign_name then
        caption_item("Campaign: " .. tostring(view.campaign_name))
        y = y + 14
    end

    -- The header badge chips: what the campaign CONTAINS, counted from the graph. Drawn first and
    -- across the top because these are the six numbers an operator checks before starting a run;
    -- everything below them is derived or estimated.
    local chip_x = text_x
    local chip_h = 18
    for _, badge in ipairs(StatsDashboard.badges(stats)) do
        local label = string.format("%s %d", badge.label, badge.count)
        local chip_w = #label * CHAR_W + Theme.space.md
        if chip_x + chip_w > text_x + content_w then
            chip_x = text_x
            y = y + chip_h + Theme.space.xs
        end
        push({
            kind = "chip", id = badge.id,
            bounds = { x = chip_x, y = y, w = chip_w, h = chip_h },
            label = label,
            token = (badge.count > 0) and "accent" or "text_muted",
        })
        chip_x = chip_x + chip_w + Theme.space.xs
    end
    y = y + chip_h + Theme.space.sm

    -- Stats grid: two columns
    local left_x = text_x
    local right_x = text_x + math.floor(content_w * 0.5) + PAD

    -- Row helper
    local function stat_row(label, value, col_x)
        caption_item(label, "text_secondary", col_x - text_x, 0)
        local val_str = tostring(value or 0)
        text_item(val_str, "text_primary", col_x - text_x + 100, 0)
        y = y + LINE_H
    end

    stat_row("Nodes:", stats.total_nodes or 0, left_x)
    stat_row("Edges:", stats.total_edges or 0, right_x)
    stat_row("Kills:", stats.total_kills or 0, left_x)
    stat_row("Quests:", stats.total_quests or 0, right_x)
    stat_row("Waypts:", stats.waypoint_count or 0, left_x)
    stat_row("Duration:", (stats.estimated_duration_min and stats.estimated_duration_min .. "min") or "~?min", right_x)
    stat_row("XP est:", stats.total_xp_estimate and string.format("%d", stats.total_xp_estimate) or "0", left_x)
    stat_row("Distance:", (stats.distance_total_yds and string.format("~%dyds", stats.distance_total_yds)) or "~?yds", right_x)

    y = y + 8

    -- Node type breakdown
    push({
        kind = "section_header",
        bounds = { x = text_x, y = y, w = content_w, h = 20 },
        title = "By Type",
    })
    y = y + 22

    local breakdown = stats.node_breakdown or {}
    for i, entry in ipairs(breakdown) do
        if y + LINE_H <= overlay_y + overlay_h - PAD then
            local label = string.format("%-12s %3d  (%2d%%)", entry.type or "", entry.count or 0, entry.pct or 0)

            -- Bar visualization
            local bar_w = math.floor((entry.pct or 0) * 0.01 * (content_w - 120))
            bar_w = math.max(0, math.min(bar_w, content_w - 120))
            local bar_h = 8

            push({
                kind = "stats_bar",
                bar_bounds = {
                    x = text_x + 120,
                    y = y + (LINE_H - bar_h) * 0.5,
                    w = bar_w,
                    h = bar_h,
                },
                pct = entry.pct or 0,
            })

            text_item(label, "text_secondary")
            y = y + LINE_H
        end
    end

    return { items = items }
end

-- ============================================================================
-- Render — draw the stats overlay from plan items
-- ============================================================================

local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    return (ok and mod ~= nil and mod) or fallback
end

local Vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y) return { x = x or 0, y = y or 0 } end,
})

local function v2(x, y) return Vec2.new(x, y) end

---Render the stats dashboard overlay. Returns the activated action id, or nil.
---@return string|nil activated_id
function StatsDashboard.render(window, plan)
    local items = plan.items
    local fired = nil

    for i = 1, #items do
        local item = items[i]

        if item.kind == "overlay_bg" then
            -- Floating panel background
            window:render_rect_filled(
                v2(item.bounds.x, item.bounds.y),
                v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h),
                Theme.color.surface_overlay(255), Theme.radius.md)
            window:render_rect(
                v2(item.bounds.x, item.bounds.y),
                v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h),
                Theme.color.border_strong(255), Theme.radius.md, Theme.metrics.border_thickness)

        elseif item.kind == "chip" then
            local b = item.bounds
            window:render_rect_filled(
                v2(b.x, b.y), v2(b.x + b.w, b.y + b.h),
                Theme.color.surface_raised(255), Theme.radius.sm)
            window:render_text(Theme.font.caption,
                v2(b.x + Theme.space.xs, b.y + 2),
                Theme.color[item.token](Theme.interaction.resting.text), item.label)

        elseif item.kind == "stats_bar" then
            local b = item.bar_bounds
            if b.w > 0 then
                window:render_rect_filled(
                    v2(b.x, b.y), v2(b.x + b.w, b.y + b.h),
                    Theme.color.accent(200), Theme.radius.sm)
            end

        elseif item.kind == "text" then
            window:render_text(item.font, v2(item.x, item.y),
                Theme.color[item.token](item.alpha or 255), item.text)

        elseif item.kind == "section_header" then
            window:render_text(Theme.font.heading, v2(item.bounds.x, item.bounds.y),
                Theme.color.text_primary(255),
                item.title or "")
            -- Underline
            window:render_rect_filled(
                v2(item.bounds.x, item.bounds.y + item.bounds.h - 1),
                v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h),
                Theme.color.border(), Theme.radius.none)
        end
    end

    return fired
end

return StatsDashboard
