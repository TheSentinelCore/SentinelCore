-- sentinel/ui/panels/travel_editor_state.lua
-- Travel Editor view-model (Phase 5, F12).
--
-- Editing travel routes within a campaign: route list, waypoint selection and reordering.
-- Activated from the Explorer panel toolbar. Renders as a sub-panel listing routes with
-- inline waypoint editing. All decision logic lives here; `travel_editor.lua` renders it.

local TravelEditorState = {}
TravelEditorState.__index = TravelEditorState

-- ============================================================================
-- Construction
-- ============================================================================

function TravelEditorState.new(opts)
    opts = opts or {}
    return setmetatable({
        routes = {},              -- { id, from_node_id, to_node_id, from_label?, to_label?, waypoints[] }[]
        selected_route = nil,     -- route id string
        editing_waypoints = false,
        activated = false,         -- whether the editor is showing
        current_route_nodes = {},  -- node ids that form the selected route
        campaign_name = nil,
        -- `error` and `loading` are the two fields every panel state carries and every `build_plan`
        -- projects. They exist here so a refused capture and a refused estimate reach the screen
        -- instead of being swallowed by a dispatch that answered `true` anyway.
        error = nil,
        loading = false,
        -- The server's answer for the selected route: `{ route_id, segments[], total_s }`.
        -- nil until `/travel/route` has answered; never a locally invented number.
        estimate = nil,
        estimate_requested = false,
        _requests = {},
        _dirty = true,
    }, TravelEditorState)
end

---Drop any estimate and any in-flight request for it.
---
---Called whenever the route being measured CHANGES. An estimate left on screen after an edit is a
---number that describes a route the operator can no longer see.
function TravelEditorState:invalidate_estimate()
    self.estimate = nil
    self.estimate_requested = false
    self._requests = {}
    if self._slots and self._slots.estimate then self._slots.estimate:reset() end
end

---The currently selected route, or nil.
function TravelEditorState:_selected()
    if not self.selected_route then return nil end
    for _, route in ipairs(self.routes) do
        if route.id == self.selected_route then return route end
    end
    return nil
end

---Record a refusal on the state and answer it to the caller in one move.
---@return boolean false, string reason
function TravelEditorState:_refuse(reason)
    self.loading = false
    self.error = reason
    self._dirty = true
    return false, reason
end

-- ============================================================================
-- Waypoint capture (spec: Travel Editor and Stats Wiring — F12-R1)
-- ============================================================================
--
-- `travel_add_waypoint` used to answer `true, "(not yet implemented — requires player position)"`.
-- The shell now hands `ctx.player_position` to `dispatch` (sampled on the TICK, never inside a
-- render callback), so the capture is real. Every way it can fail is named:
--
--   * nil position  -- loading screen, between injections, dead object manager. A capture that
--                      substituted `{0,0,0}` would silently drop a waypoint in the middle of the map.
--   * no route      -- there is nowhere to put it.
--
-- The map id is RECORDED when the host has one and left nil when it does not. It is not required
-- here because a waypoint is useful to the runtime without one; it is required by
-- `build_segments`, which is where a missing map would otherwise become a fabricated `map = 0`.

---Append the player's current position to the selected route.
---@param position table|nil `ctx.player_position` — `{ x, y, z }` or nil when out of world
---@param map_id number|nil `core.get_map_id()`, read by the host on the tick
---@return boolean ok, string reason
function TravelEditorState:add_waypoint(position, map_id)
    local route = self:_selected()
    if not route then
        return self:_refuse("no route selected: a captured waypoint has nowhere to go")
    end
    if type(position) ~= "table" then
        return self:_refuse("no player position: the character is not in world")
    end
    local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z)
    if not (x and y and z) then
        return self:_refuse("the player position is incomplete: x/y/z are required")
    end

    route.waypoints = route.waypoints or {}
    route.waypoints[#route.waypoints + 1] = {
        x = x, y = y, z = z,
        map = tonumber(map_id),
        movement = "walk",
        destination = string.format("(%.0f, %.0f, %.0f)", x, y, z),
        captured = true,
    }

    -- A route that just grew a leg has an estimate that is now about a different route.
    self:invalidate_estimate()
    self.error = nil
    self.loading = false
    self._dirty = true
    return true, string.format("waypoint %d captured at (%.0f, %.0f, %.0f)",
        #route.waypoints, x, y, z)
end

-- ============================================================================
-- Loading
-- ============================================================================

---Turn one campaign node into a waypoint, or nil when it is not a leg of a route.
---
---Two node types are legs. `questing.Travel` carries coordinates and, on the Travel node,
---`allow_flight` — which means the runtime may use its OWN flight form for the leg, not that a
---flight master is involved. `questing.Flight` is the flight master's hop: it carries a destination
---NAME and no coordinates at all, so its position comes from the taxi catalog at estimate time.
---
---`map` is READ from the intent and left nil when the node does not carry one. `questing.Travel`'s
---`default_intent` has no `map` field today, so a campaign-derived waypoint normally has none — and
---`build_segments` refuses to measure it rather than defaulting to map 0, which would price a leg in
---Outland as if it were in Elwynn.
---@param node table|nil `{ id, type, intent }`
---@return table|nil waypoint
local function waypoint_from_node(node)
    if not node or not node.intent then return nil end
    local intent = node.intent

    if node.type == "questing.Flight" then
        return {
            x = 0, y = 0, z = 0,
            map = nil,
            movement = "taxi",
            destination = intent.destination or "",
            node_id = node.id,
        }
    end

    if node.type ~= "questing.Travel" then return nil end
    return {
        x = intent.x or 0, y = intent.y or 0, z = intent.z or 0,
        map = tonumber(intent.map),
        movement = intent.allow_flight and "flight" or "walk",
        destination = intent.destination
            or string.format("(%.0f, %.0f, %.0f)", intent.x or 0, intent.y or 0, intent.z or 0),
        node_id = node.id,
    }
end

---Load route data from campaign nodes and edges.
---Scans edges for Travel-type connections and builds route entries.
---@param campaign_name string
---@param nodes table[]  { id, type, intent }
---@param edges table[]  { id, from, to, guard? }
function TravelEditorState:load_from_campaign(campaign_name, nodes, edges)
    self.campaign_name = campaign_name or self.campaign_name
    self.routes = {}
    self.selected_route = nil
    self:invalidate_estimate()

    nodes = nodes or {}
    edges = edges or {}

    -- Build a lookup from node id to node data
    local node_index = {}
    for _, node in ipairs(nodes) do
        node_index[node.id] = node
    end

    -- Build routes from edges that have Travel nodes at either end
    for i, edge in ipairs(edges) do
        local from_node = node_index[edge.from]
        local to_node = node_index[edge.to]
        if from_node and to_node then
            local route_id = "route_" .. tostring(i)
            local waypoints = {}

            -- Extract waypoint data from Travel nodes
            local from_wp = waypoint_from_node(from_node)
            if from_wp then table.insert(waypoints, from_wp) end

            local to_wp = waypoint_from_node(to_node)
            if to_wp then table.insert(waypoints, to_wp) end

            table.insert(self.routes, {
                id = route_id,
                from_node_id = edge.from,
                to_node_id = edge.to,
                from_label = from_node.type and from_node.type:match("^questing%.(.+)$") or from_node.type or "",
                to_label = to_node.type and to_node.type:match("^questing%.(.+)$") or to_node.type or "",
                waypoints = waypoints,
            })
        end
    end

    self._dirty = true
    return #self.routes
end

-- ============================================================================
-- Mutators
-- ============================================================================

---@param id string route id
function TravelEditorState:select_route(id)
    if not id or id == "" then
        self.selected_route = nil
        self.editing_waypoints = false
        self:invalidate_estimate()
        self._dirty = true
        return
    end

    -- Verify the route exists
    local found = false
    for _, route in ipairs(self.routes) do
        if route.id == id then
            found = true
            break
        end
    end
    if not found then return end

    if self.selected_route == id then
        self.selected_route = nil
        self.editing_waypoints = false
    else
        self.selected_route = id
        self.editing_waypoints = false
    end
    self:invalidate_estimate()
    self._dirty = true
end

---Set the editing state for the currently selected route.
function TravelEditorState:set_editing(on)
    if not self.selected_route then
        self.editing_waypoints = false
        return
    end
    on = on and true or false
    if self.editing_waypoints == on then return end
    self.editing_waypoints = on
    self._dirty = true
end

---Reorder a waypoint within a route.
---@param route_id string
---@param from_idx number 1-based current index
---@param to_idx number 1-based target index
function TravelEditorState:reorder_waypoint(route_id, from_idx, to_idx)
    from_idx = tonumber(from_idx)
    to_idx = tonumber(to_idx)
    if not from_idx or not to_idx then return false end
    if from_idx < 1 or to_idx < 1 then return false end

    for _, route in ipairs(self.routes) do
        if route.id == route_id then
            local wps = route.waypoints
            if from_idx > #wps or to_idx > #wps then return false end
            if from_idx == to_idx then return true end

            local wp = table.remove(wps, from_idx)
            table.insert(wps, to_idx, wp)
            -- Reordering changes which legs exist, so the previous times measure a route that is
            -- no longer on screen.
            self:invalidate_estimate()
            self._dirty = true
            return true
        end
    end
    return false
end

---Move a waypoint up (decrease index) in a route.
function TravelEditorState:move_waypoint_up(route_id, idx)
    return self:reorder_waypoint(route_id, idx, idx - 1)
end

---Move a waypoint down (increase index) in a route.
function TravelEditorState:move_waypoint_down(route_id, idx)
    return self:reorder_waypoint(route_id, idx, idx + 1)
end

---Toggle the editor activation.
function TravelEditorState:toggle()
    self.activated = not self.activated
    if not self.activated then
        self.selected_route = nil
        self.editing_waypoints = false
        self:invalidate_estimate()
    end
    self._dirty = true
    return self.activated
end

---Append a LOCAL route so waypoints can be captured into it.
---
---Local on purpose: routes are derived from the campaign's Travel nodes, and persisting one is the
---editor client's job (`POST /editor/campaigns/{name}`), which the Graph panel owns. This is the
---scratch route a capture session builds; nothing here claims it was saved.
function TravelEditorState:add_route(from_id, to_id)
    local route_id = "route_new_" .. tostring(#self.routes + 1)
    table.insert(self.routes, {
        id = route_id,
        from_node_id = from_id or "",
        to_node_id = to_id or "",
        from_label = "Travel",
        to_label = "Travel",
        waypoints = {},
    })
    self._dirty = true
    return route_id
end

-- ============================================================================
-- The `POST /travel/route` request (spec: Travel Editor and Stats Wiring — F12-R2)
-- ============================================================================
--
-- The server measures the route; this file only decides which legs to ask about. Nothing here
-- computes a time, a speed or a distance, because a number produced locally and rendered next to
-- the server's would be indistinguishable from one the server returned.
--
-- TWO REFUSALS, AND WHY NEITHER IS PAPERED OVER
-- ---------------------------------------------
--  1. A WAYPOINT WITH NO MAP. `questing.Travel`'s intent carries `x/y/z` and no map, and the same
--     coordinates name different places on different maps. Defaulting to 0 would price a leg in
--     Outland as if it were in Elwynn and the total would still look computed.
--  2. A FLIGHT LEG WITH NO TAXI NODE. `/travel/route` has no taxi tables — it refuses a taxi segment
--     that arrives without positions rather than inventing a per-hop constant (see the QueryServer's
--     `plan_route`). The runtime owns those positions in `kernel/catalogs/taxi_nodes.lua`, so a
--     flight leg is only sent as `type = "taxi"` once its destination has RESOLVED to exactly one
--     node there. An unresolved or ambiguous destination is reported, never guessed: `resolve`
--     answers `needs_faction` for a faction-complement pair, and silently picking one of them would
--     fly the character to the wrong continent.

local TaxiNodes = require("kernel/catalogs/taxi_nodes")

---Look a flight waypoint's destination up in the taxi catalog.
---@param waypoint table
---@param faction string|nil "Alliance" | "Horde" | nil
---@return number|nil node_id, table|nil node, string|nil err
local function resolve_taxi_node(waypoint, faction)
    if waypoint.taxi_node then
        return waypoint.taxi_node, TaxiNodes.nodes[waypoint.taxi_node]
    end
    local id, err = TaxiNodes.resolve(waypoint.destination, faction)
    if not id then return nil, nil, err end
    return id, TaxiNodes.nodes[id]
end

---Build the segment list for one route's `POST /travel/route` body.
---@param route table
---@param faction string|nil the character's faction, when the host knows it
---@return table|nil segments, string|nil reason
function TravelEditorState.build_segments(route, faction)
    local waypoints = route and route.waypoints or {}
    if #waypoints < 2 then
        return nil, "a route needs at least two waypoints before it can be estimated"
    end

    local segments = {}
    for i = 2, #waypoints do
        local from, to = waypoints[i - 1], waypoints[i]
        -- `flight` is NOT `taxi`. A Travel node's `allow_flight` means the runtime may use its own
        -- flight form or mount for a leg it walks otherwise; a taxi leg is a flight master's hop, and
        -- only `questing.Flight` produces one.
        local taxi = (to.movement == "taxi")

        local to_map, to_pos = tonumber(to.map), nil
        if taxi then
            local node_id, node, err = resolve_taxi_node(to, faction)
            if not node then
                return nil, string.format(
                    "waypoint %d is a flight to %q that resolves to no taxi node (%s); "
                    .. "the server has no taxi tables and will not guess the hop",
                    i, tostring(to.destination), tostring(err or "unknown_destination"))
            end
            to_map = node.map
            to_pos = { map = node.map, x = node.x, y = node.y, z = node.z }
            to.taxi_node = node_id
        end

        local from_map = tonumber(from.map)
        if from_map == nil then
            return nil, string.format(
                "waypoint %d carries no map id, so its leg cannot be measured", i - 1)
        end
        if to_map == nil then
            return nil, string.format(
                "waypoint %d carries no map id, so its leg cannot be measured", i)
        end

        segments[#segments + 1] = {
            type = taxi and "taxi" or nil,
            from_node = taxi and from.taxi_node or nil,
            to_node = taxi and to.taxi_node or nil,
            from = { map = from_map, x = from.x or 0, y = from.y or 0, z = from.z or 0 },
            to = to_pos or { map = to_map, x = to.x or 0, y = to.y or 0, z = to.z or 0 },
        }
    end
    return segments
end

---A stable signature for a segment list, so an unchanged route is not re-requested every tick and a
---changed one is never answered from the previous route's cache.
function TravelEditorState.request_key(segments)
    local parts = {}
    for i, seg in ipairs(segments) do
        parts[i] = string.format("%s|%d,%.2f,%.2f,%.2f|%d,%.2f,%.2f,%.2f",
            seg.type or "walk",
            seg.from.map, seg.from.x, seg.from.y, seg.from.z,
            seg.to.map, seg.to.x, seg.to.y, seg.to.z)
    end
    return table.concat(parts, ";")
end

-- ============================================================================
-- Build — produce the flat view the render layer draws
-- ============================================================================

function TravelEditorState:build()
    -- Produce visible route data for the view
    local visible_routes = {}
    for _, route in ipairs(self.routes) do
        local entry = {
            id = route.id,
            from_label = route.from_label,
            to_label = route.to_label,
            waypoint_count = #(route.waypoints or {}),
            waypoints = route.waypoints,
            selected = (self.selected_route == route.id),
        }
        table.insert(visible_routes, entry)
    end

    -- waypoints of the selected route, for editing
    local active_waypoints = {}
    if self.selected_route then
        for _, route in ipairs(self.routes) do
            if route.id == self.selected_route then
                active_waypoints = route.waypoints or {}
                break
            end
        end
    end

    return {
        activated = self.activated,
        routes = visible_routes,
        route_count = #self.routes,
        selected_route = self.selected_route,
        editing_waypoints = self.editing_waypoints,
        active_waypoints = active_waypoints,
        campaign_name = self.campaign_name,
        error = self.error,
        loading = self.loading,
        estimate = self.estimate,
        estimate_requested = self.estimate_requested,
    }
end

-- ============================================================================
-- Build plan — produce the draw items for one frame
-- ============================================================================

local CHAR_W = 7
local PAD = 12
local CONTROL_H = 28
local ROW_H = 18
local SMALL_H = 14
local SECTION_H = 20

local Theme = require("ui/theme")

local function fit_label(text, width)
    text = tostring(text or "")
    local max_chars = math.floor((width or 0) / CHAR_W)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

---Build the draw plan items for the travel editor sub-panel.
---@param view table from build()
---@param bounds table { x, y, w, h }  — the area assigned to the editor within the parent panel
---@return table { items }
function TravelEditorState.build_plan(view, bounds)
    local items = {}
    local text_x = bounds.x + PAD
    local content_w = math.max(0, bounds.w - PAD * 2)
    local y = bounds.y + PAD

    local function push(item) items[#items + 1] = item end
    local function text_item(str, token, ox, oy)
        push({
            kind = "text", x = text_x + (ox or 0), y = y + (oy or 0),
            font = Theme.font.body, token = token or "text_primary",
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
            kind = "text", x = text_x, y = y,
            font = Theme.font.body, token = "text_muted",
            alpha = Theme.interaction.resting.text,
            text = "Open a campaign to edit travel routes",
        })
        return { items = items }
    end

    -- ====================================================================
    -- Toolbar: toggle button
    -- ====================================================================
    local toggle_label = view.activated and "Hide Routes" or "Show Routes"
    push({
        kind = "button", id = "travel_toggle",
        bounds = { x = text_x, y = y, w = math.min(120, content_w), h = CONTROL_H },
        label = toggle_label, variant = view.activated and "primary" or "secondary",
    })
    y = y + CONTROL_H + Theme.space.sm

    -- If not activated, stop here
    if not view.activated then
        return { items = items }
    end

    -- ====================================================================
    -- Route list
    -- ====================================================================
    local routes = view.routes or {}
    if #routes > 0 then
        section(string.format("Travel Routes (%d)", #routes))

        for ri, route in ipairs(routes) do
            local route_header = string.format("Route: %s → %s    (%d waypoints)",
                route.from_label or "?",
                route.to_label or "?",
                route.waypoint_count)

            -- Route selection row
            local row_bounds = {
                x = text_x, y = y,
                w = content_w, h = ROW_H + 4,
            }
            push({
                kind = "list_row", id = "travel_select_route:" .. route.id,
                bounds = row_bounds, label = route_header,
                selected = route.selected,
            })
            y = y + ROW_H + 4

            -- If this route is selected, show its waypoints
            if route.selected then
                -- Edit waypoints toggle
                local edit_label = view.editing_waypoints and "Close Editor" or "Edit Waypoints"
                push({
                    kind = "button", id = "travel_toggle_edit",
                    bounds = { x = text_x + Theme.space.md, y = y,
                              w = math.min(140, content_w - Theme.space.md), h = CONTROL_H },
                    label = edit_label, variant = view.editing_waypoints and "primary" or "secondary",
                })
                y = y + CONTROL_H + Theme.space.xs

                if view.editing_waypoints then
                    -- Waypoint list
                    local wps = route.waypoints or {}
                    for wi, wp in ipairs(wps) do
                        local pos_str = string.format("(%.0f, %.0f, %.0f)", wp.x or 0, wp.y or 0, wp.z or 0)
                        local mvmt = (wp.movement or "walk"):upper():sub(1, 1) .. (wp.movement or "walk"):sub(2)
                        local wp_label = string.format("  %d. %-20s  %s", wi, pos_str, mvmt)
                        text_item(wp_label, "text_secondary", Theme.space.md, 0)

                        -- Move up / Move down buttons
                        local btn_w = math.min(48, (content_w - Theme.space.md * 2) * 0.2)
                        local btn_y = y
                        local btn_x = text_x + content_w - (btn_w * 2 + Theme.space.sm * 2) - Theme.space.md

                        if wi > 1 then
                            push({
                                kind = "button", id = string.format("travel_wp_up:%s:%d", route.id, wi),
                                bounds = { x = btn_x, y = btn_y, w = btn_w, h = SMALL_H },
                                label = "Up", variant = "ghost",
                            })
                        end
                        btn_x = btn_x + btn_w + Theme.space.xs

                        if wi < #wps then
                            push({
                                kind = "button", id = string.format("travel_wp_down:%s:%d", route.id, wi),
                                bounds = { x = btn_x, y = btn_y, w = btn_w, h = SMALL_H },
                                label = "Dn", variant = "ghost",
                            })
                        end

                        y = y + ROW_H + 1
                    end

                    if #wps == 0 then
                        text_item("  No waypoints in this route", "text_muted", Theme.space.md, 0)
                        y = y + SMALL_H
                    end

                    -- Add waypoint at current position button
                    push({
                        kind = "button", id = "travel_add_waypoint",
                        bounds = { x = text_x + Theme.space.md, y = y,
                                  w = math.min(160, content_w - Theme.space.md), h = CONTROL_H },
                        label = "Capture Position", variant = "primary",
                    })
                    y = y + CONTROL_H + Theme.space.sm
                end

                y = y + Theme.space.xs
            end
        end
    else
        push({
            kind = "text", x = text_x, y = y,
            font = Theme.font.body, token = "text_muted",
            alpha = Theme.interaction.resting.text,
            text = "No travel routes found. Add Travel nodes to your campaign.",
        })
    end

    return { items = items }
end

-- ============================================================================
-- Reduce — map an activated control id to a command for the host
-- ============================================================================

function TravelEditorState.reduce(action_id)
    if action_id == nil then return nil end

    if action_id == "travel_toggle" then
        return { kind = "travel_toggle" }
    end
    if action_id == "travel_toggle_edit" then
        return { kind = "travel_toggle_edit" }
    end
    if action_id == "travel_add_waypoint" then
        return { kind = "travel_add_waypoint" }
    end

    -- Route selection
    local select_match = action_id:match("^travel_select_route:(.+)$")
    if select_match then
        return { kind = "travel_select_route", route_id = select_match }
    end

    -- Waypoint reorder
    local route_id_up, wp_idx_up = action_id:match("^travel_wp_up:([^:]+):(%d+)$")
    if route_id_up and wp_idx_up then
        return { kind = "travel_move_waypoint", route_id = route_id_up, index = tonumber(wp_idx_up), direction = "up" }
    end

    local route_id_dn, wp_idx_dn = action_id:match("^travel_wp_down:([^:]+):(%d+)$")
    if route_id_dn and wp_idx_dn then
        return { kind = "travel_move_waypoint", route_id = route_id_dn, index = tonumber(wp_idx_dn), direction = "down" }
    end

    return nil
end

return TravelEditorState
