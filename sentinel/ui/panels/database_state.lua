-- sentinel/ui/panels/database_state.lua
-- The Database panel's view-model for Spawn Scanner (F9) and
-- Grinding Area Generator (F13). Phase 4, PR-4a/4b.
--
-- All decision logic lives here; `database.lua` only renders whatever
-- `build()` returns.

local AsyncSlot = require("ui/async_slot")

local DatabaseState = {}
DatabaseState.__index = DatabaseState

-- ============================================================================
-- Construction
-- ============================================================================

function DatabaseState.new(opts)
    opts = opts or {}
    local state = setmetatable({
        -- Scan / spawns tab
        scan_results = opts.scan_results or {},  -- { entry, name, count, min_level, max_level, avg_distance, kind }[]
        selected_entry = nil,       -- NPC/object entry ID
        selected_detail = nil,      -- NpcDetail or ObjectInfo from QueryClient
        spawn_points = {},          -- [{ map, x, y, z }]

        -- Scan controls
        scan_range = 50,            -- default scan range in yards
        scan_filter = nil,          -- nil = all, "herb", "mining"
        scan_mode = "nearby",       -- "nearby" or "manual"

        -- Pending work flags
        _pending_scan = false,
        _pending_detail = false,
        _pending_grind = false,

        -- Grinding tab
        active_tab = "scanner",     -- "scanner" | "grinding"
        grinding_npc_entry = nil,   -- NPC entry for grinding area
        grinding_zone = nil,        -- zone name
        grinding_result = nil,      -- { spawn_density, xp_per_hour, gold_per_hour, safe_spots, route }

        -- UI state
        loading = false,
        error = nil,
        _dirty = true,
    }, DatabaseState)

    -- `scan` reads the object manager and resolves in the same tick; it still goes through a slot so
    -- every panel reports a failed refresh the same way, and so the F13 scanner can move to
    -- `/spawns/nearby` (PR10) without the caller changing shape.
    state._slots = {
        scan = AsyncSlot.new({ label = "spawn scan", owner = state }),
        detail = AsyncSlot.new({ label = "entry detail", owner = state }),
        grind = AsyncSlot.new({ label = "grind estimate", owner = state }),
    }
    return state
end

-- ============================================================================
-- Mutators — each marks dirty so the binding's tick picks it up
-- ============================================================================

function DatabaseState:set_tab(tab)
    if self.active_tab == tab then return end
    self.active_tab = tab
    self._dirty = true
end

function DatabaseState:set_scan_range(r)
    r = tonumber(r)
    if not r or r < 1 then return end
    if self.scan_range == r then return end
    self.scan_range = r
    self._dirty = true
end

function DatabaseState:set_scan_filter(filter)
    if self.scan_filter == filter then return end
    self.scan_filter = filter
    self._dirty = true
end

function DatabaseState:set_scan_mode(mode)
    if self.scan_mode == mode then return end
    self.scan_mode = mode
    self._dirty = true
end

function DatabaseState:request_scan()
    -- Marks that a nearby-scan should execute on next tick
    self.scan_results = {}
    self.selected_entry = nil
    self.selected_detail = nil
    self.spawn_points = {}
    self.loading = true
    self.error = nil
    self._slots.scan:reset()
    self._pending_scan = true
    self._dirty = true
end

function DatabaseState:select_entry(entry)
    entry = tonumber(entry)
    if not entry then return end
    if self.selected_entry == entry then return end
    self.selected_entry = entry
    self.selected_detail = nil
    self.spawn_points = {}
    self.loading = true
    -- Whatever is in flight is the previous entry's detail.
    self._slots.detail:reset()
    self._pending_detail = true
    self._dirty = true
end

function DatabaseState:set_grinding_npc(entry)
    entry = tonumber(entry)
    if self.grinding_npc_entry == entry then return end
    self.grinding_npc_entry = entry
    self._dirty = true
end

function DatabaseState:set_grinding_zone(zone)
    zone = tostring(zone or "")
    if self.grinding_zone == zone then return end
    self.grinding_zone = zone
    self._dirty = true
end

function DatabaseState:request_grind()
    if not self.grinding_npc_entry then
        self.error = "No NPC entry specified"
        self._dirty = true
        return
    end
    self.grinding_result = nil
    self.loading = true
    self.error = nil
    self._slots.grind:reset()
    self._pending_grind = true
    self._dirty = true
end

-- ============================================================================
-- Data loading (called from binding on_tick)
-- ============================================================================

---Execute a nearby scan, populating scan_results.
---
---Reads the object manager, which a dead QueryServer does not affect — `query_client` is accepted
---only so every `execute_*` has one shape, and PR10 can move this to `GET /spawns/nearby` without
---the caller changing.
---
---THERE IS NO OFFLINE FALLBACK. There used to be: with no scan source, this returned six invented
---rows — a wolf, a boar, a Defias bandit — and in the injector, where `dbg` is a debug plugin the
---operator may simply not have loaded, those rows are what the panel showed. Fabricated data is
---worse than an empty list precisely because nothing on screen distinguishes it from a real scan.
---@param query_client table|nil
function DatabaseState:execute_scan(query_client)
    local range = self.scan_range or 50
    local filter = self.scan_filter
    local state = self

    local status, results = self._slots.scan:poll(function()
        -- A raise is deliberate: the slot's pcall turns it into `spawn scan raised: <reason>` on
        -- `state.error`, which is the only honest answer when there is nothing to scan with.
        -- (`dbg.nearby` is today's source; task 3.20 replaces it with `core.object_manager`.)
        if type(dbg) ~= "table" or type(dbg.nearby) ~= "function" then
            error("no spawn source available (object manager)", 0)
        end
        local ok, entities = pcall(dbg.nearby, range, filter)
        if not ok or type(entities) ~= "table" then
            error(tostring(entities or "scan returned no data"), 0)
        end
        return state:_aggregate_nearby(entities)
    end)

    -- The flag stays ARMED while pending. The slot has already re-armed `_dirty`, so the next tick
    -- calls back in; clearing here is the exact bug this change removes.
    if status == "pending" then return end
    self._pending_scan = false
    if status == "ok" then
        self.scan_results = results
        self._dirty = true
    end
end

---Load detail for the selected entry via QueryClient.
---@param query_client table|nil
function DatabaseState:execute_load_detail(query_client)
    local entry = self.selected_entry
    if not entry or not query_client then
        -- Nothing to poll. The binding reports the absent client; this only stops the flag spinning.
        self.loading = false
        self._pending_detail = false
        return
    end

    local status, found = self._slots.detail:poll(function()
        -- Two endpoints, one slot: an entry is an NPC or an object, and the object lookup is only
        -- worth issuing once the NPC lookup has actually RESOLVED to nothing.
        local npc, npc_pending = query_client:get_npc(entry)
        if npc then return { kind = "npc", detail = npc } end
        if npc_pending then return nil, true end

        local object, object_pending = query_client:get_object(entry)
        if object then return { kind = "object", detail = object } end
        if object_pending then return nil, true end
        return nil
    end)

    if status == "pending" then return end
    self._pending_detail = false

    if status == "ok" then
        self.selected_detail = found.detail
        if found.kind == "npc" then
            self.spawn_points = found.detail.positions or {}
        else
            self.spawn_points = found.detail.position and { found.detail.position } or {}
        end
        return
    end
    if status == "timeout" then return end  -- the slot already named the lookup that never answered

    -- Reserved for a lookup that FINISHED and came back empty. A fetch still in flight must never
    -- reach this line: "not found" on a pending request is the freeze the operator sees.
    self.error = "Entry " .. tostring(entry) .. " not found"
    self._dirty = true
end

---Execute grinding area generation via QueryClient.
---@param query_client table|nil
function DatabaseState:execute_grind(query_client)
    local entry = self.grinding_npc_entry
    if not entry then
        self.loading = false
        self._pending_grind = false
        self.error = "No NPC entry specified"
        return
    end

    if not query_client then
        self.loading = false
        self._pending_grind = false
        -- Was: a fixed 12,450 XP/hour over an empty route. A grind estimate is a number the operator
        -- makes a decision on, and an invented one is a route they walk for an hour to find out.
        self.error = "grind estimate unavailable: no query server"
        return
    end

    local status, detail = self._slots.grind:poll(function() return query_client:get_npc(entry) end)
    if status == "pending" then return end
    self._pending_grind = false
    if status ~= "ok" then
        if status == "failed" then self.error = "NPC #" .. tostring(entry) .. " not found" end
        return
    end

    local positions = detail.positions or {}
    local spawn_count = #positions
    local zone = self.grinding_zone or detail.faction or "Unknown"

    -- Simplified estimate: each spawn point represents roughly one mob
    self.grinding_result = {
        spawn_density = spawn_count,
        xp_per_hour = spawn_count * 1200,
        gold_per_hour = math.floor(spawn_count * 1.5 * 100) / 100,
        kills_per_min = spawn_count * 0.34,
        safe_spots = math.max(1, math.floor(spawn_count / 3)),
        route = { zone = zone, waypoints = positions },
        pull_radius = 18,
    }
    self._dirty = true
end

-- ============================================================================
-- Internals
-- ============================================================================

---Aggregate raw nearby entities into grouped scan results.
function DatabaseState:_aggregate_nearby(entities)
    local grouped = {}
    local seen = {}
    for _, e in ipairs(entities or {}) do
        local key = tostring(e.entry or e.npc_id or "")
        if key ~= "" then
            if not seen[key] then
                seen[key] = {
                    entry = tonumber(key) or 0,
                    name = e.name or "Unknown",
                    count = 0,
                    min_level = e.level or 1,
                    max_level = e.level or 1,
                    total_distance = 0,
                    sample_count = 0,
                    kind = tostring(e.type or "creature"),
                }
                grouped[#grouped + 1] = seen[key]
            end
            local g = seen[key]
            g.count = g.count + 1
            if e.level then
                g.min_level = math.min(g.min_level, e.level)
                g.max_level = math.max(g.max_level, e.level)
            end
            if e.distance then
                g.total_distance = g.total_distance + e.distance
                g.sample_count = g.sample_count + 1
            end
        end
    end

    local results = {}
    for _, g in ipairs(grouped) do
        table.insert(results, {
            entry = g.entry,
            name = g.name,
            count = g.count,
            min_level = g.min_level,
            max_level = g.max_level,
            avg_distance = g.sample_count > 0 and math.floor(g.total_distance / g.sample_count + 0.5) or nil,
            kind = g.kind,
        })
    end
    table.sort(results, function(a, b)
        return (a.avg_distance or 999) < (b.avg_distance or 999)
    end)
    return results
end

-- `_mock_scan` and `_mock_grind_result` used to live here (spec: No Mock Data in Production Paths).
-- They are gone rather than moved behind a flag: a fixture reachable from `execute_*` is a fixture
-- that reaches the injector, and both of these did. Test fixtures now live in the tests that use
-- them, where nothing installed can call them.

-- ============================================================================
-- Build — produce the flat view the render layer draws
-- ============================================================================

function DatabaseState:build()
    return {
        active_tab = self.active_tab,
        scan_results = self.scan_results,
        selected_entry = self.selected_entry,
        selected_detail = self.selected_detail,
        spawn_points = self.spawn_points,
        scan_range = self.scan_range,
        scan_filter = self.scan_filter,
        scan_mode = self.scan_mode,
        grinding_npc_entry = self.grinding_npc_entry,
        grinding_zone = self.grinding_zone,
        grinding_result = self.grinding_result,
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
local SMALL_H = 14
local LINE_H = 16

local Theme = require("ui/theme")

local function fit_label(text, width)
    text = tostring(text or "")
    local max_chars = math.floor((width or 0) / CHAR_W)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

function DatabaseState.build_plan(view, bounds)
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

    -- Tab bar: Scanner | Grinding. Measured per label (Runner-panel formula): a fixed 90px
    -- clipped "Spawn Scanner" to "Spawn Sc...".
    local function tab_w(label)
        return math.min(#label * CHAR_W + Theme.space.xl, content_w * 0.5 - Theme.space.sm)
    end
    local scanner_w = tab_w("Spawn Scanner")
    push({
        kind = "chip", id = "tab_scanner",
        bounds = { x = text_x, y = y, w = scanner_w, h = CONTROL_H },
        label = "Spawn Scanner", selected = view.active_tab == "scanner",
    })
    push({
        kind = "chip", id = "tab_grinding",
        bounds = { x = text_x + scanner_w + Theme.space.sm, y = y, w = tab_w("Grinding"), h = CONTROL_H },
        label = "Grinding", selected = view.active_tab == "grinding",
    })
    y = y + CONTROL_H + Theme.space.sm

    -- Loading state
    if view.loading then
        text_item("body", "text_muted", "Loading...")
        return { items = items }
    end

    -- Error state
    if view.error and view.error ~= "" then
        text_item("body", "danger", "Error: " .. tostring(view.error))
        return { items = items }
    end

    -- =========================================================================
    -- SPAWN SCANNER TAB
    -- =========================================================================
    if view.active_tab == "scanner" then
        -- Toolbar: scan mode chip, range chip, Scan button
        local mode_label = "Mode: " .. (view.scan_mode == "nearby" and "Nearby" or "Filter")
        local mode_w = #mode_label * CHAR_W + Theme.space.lg
        push({
            kind = "chip", id = "cycle_scan_mode",
            bounds = { x = text_x, y = y, w = mode_w, h = CONTROL_H },
            label = mode_label, selected = true,
        })

        local range_label = "Range: " .. tostring(view.scan_range)
        local range_w = #range_label * CHAR_W + Theme.space.lg
        push({
            kind = "chip", id = "cycle_range",
            bounds = { x = text_x + mode_w + Theme.space.sm, y = y,
                      w = range_w, h = CONTROL_H },
            label = range_label, selected = true,
        })

        local scan_w = math.max(80, #"Scan!" * CHAR_W + Theme.space.xl)
        local scan_x = text_x + content_w - scan_w
        push({
            kind = "button", id = "scan",
            bounds = { x = scan_x, y = y, w = scan_w, h = CONTROL_H },
            label = "Scan!", variant = "primary",
        })
        y = y + CONTROL_H + Theme.space.sm

        -- Filter chips row
        local filter_items = { { id = "filter:all", label = "All", sel = view.scan_filter == nil },
                               { id = "filter:herb", label = "Herb", sel = view.scan_filter == "herb" },
                               { id = "filter:mining", label = "Mining", sel = view.scan_filter == "mining" } }
        local fx = text_x
        for _, f in ipairs(filter_items) do
            local fw = #f.label * CHAR_W + Theme.space.lg
            if fx + fw <= text_x + content_w then
                push({
                    kind = "chip", id = f.id,
                    bounds = { x = fx, y = y, w = fw, h = CONTROL_H },
                    label = f.label, selected = f.sel,
                })
                fx = fx + fw + Theme.space.sm
            end
        end
        y = y + CONTROL_H + Theme.space.md

        -- Results list
        local results = view.scan_results or {}
        if #results > 0 then
            section("Results (" .. #results .. ")")

            for _, r in ipairs(results) do
                local icon = (r.kind == "herb") and "H" or (r.kind == "mining") and "M" or "C"
                local level_str = ""
                if r.min_level and r.max_level and r.min_level ~= r.max_level then
                    if r.min_level > 0 then
                        level_str = " " .. r.min_level .. "-" .. r.max_level
                    end
                elseif r.min_level and r.min_level > 0 then
                    level_str = " " .. tostring(r.min_level)
                end
                local dist_str = r.avg_distance and (" [" .. r.avg_distance .. "m]" or "") or ""
                local line = string.format("%s %s%s x%d%s",
                    icon, fit_label(r.name, 16), level_str, r.count or 0, dist_str)

                push({
                    kind = "list_row", id = "select_entry:" .. tostring(r.entry),
                    bounds = { x = text_x, y = y, w = content_w, h = ROW_H + 4 },
                    label = fit_label(line, content_w),
                    selected = view.selected_entry == r.entry,
                })
                y = y + ROW_H + 4
            end

            -- Action buttons for selected entry
            if view.selected_entry then
                y = y + Theme.space.sm
                local half = math.max(60, (content_w - Theme.space.sm) * 0.5)
                push({
                    kind = "button", id = "add_as_kill:" .. tostring(view.selected_entry),
                    bounds = { x = text_x, y = y, w = half, h = CONTROL_H },
                    label = "Add as Kill Node", variant = "secondary",
                })
                push({
                    kind = "button", id = "view_detail:" .. tostring(view.selected_entry),
                    bounds = { x = text_x + half + Theme.space.sm, y = y, w = half, h = CONTROL_H },
                    label = "View NPC Detail", variant = "ghost",
                })
                y = y + CONTROL_H + Theme.space.sm
            end

            -- Detail display for selected entry
            if view.selected_detail then
                y = y + Theme.space.sm
                section("Detail")
                local detail = view.selected_detail
                local detail_name = detail.name or "Entry #" .. tostring(detail.entry or view.selected_entry)
                text_item("body", "text_primary", fit_label(detail_name, content_w))
                y = y + Theme.line_height.body + Theme.space.xs

                if detail.faction then
                    text_item("caption", "text_secondary",
                        fit_label("Faction: " .. tostring(detail.faction), content_w))
                    y = y + SMALL_H
                end

                local kind_str = detail.kind or (detail.roles and table.concat(detail.roles, ", ") or nil)
                if kind_str then
                    text_item("caption", "text_muted",
                        fit_label("Type: " .. tostring(kind_str), content_w))
                    y = y + SMALL_H
                end

                -- Spawn points
                local spawns = view.spawn_points or {}
                if #spawns > 0 then
                    y = y + Theme.space.xs
                    text_item("caption", "text_muted", "Spawns (" .. #spawns .. "):")
                    y = y + SMALL_H
                    local max_spawns = math.min(#spawns, 5)
                    for i = 1, max_spawns do
                        local sp = spawns[i]
                        local p = sp.position or sp
                        local text = string.format("  Map %s (%.0f, %.0f, %.0f)",
                            tostring(p.map or 0), p.x or 0, p.y or 0, p.z or 0)
                        text_item("caption", "text_muted",
                            fit_label(text, content_w - Theme.space.sm), Theme.space.sm)
                        y = y + SMALL_H
                    end
                    if #spawns > 5 then
                        text_item("caption", "text_muted",
                            "  ... and " .. (#spawns - 5) .. " more")
                        y = y + SMALL_H
                    end
                end
            end
        else
            -- Empty state
            push({
                kind = "empty_state",
                bounds = { x = bounds.x + Theme.space.sm, y = y,
                          w = bounds.w - Theme.space.sm * 2,
                          h = math.max(1, bounds.y + bounds.h - y - PAD) },
                title = "No Scan Results",
                message = "Press Scan! to discover nearby NPCs, herbs and veins",
            })
        end

    -- =========================================================================
    -- GRINDING TAB
    -- =========================================================================
    elseif view.active_tab == "grinding" then
        -- NPC Entry field (chip for editing)
        text_item("body", "text_secondary", "NPC Entry:")
        local entry_str = view.grinding_npc_entry and tostring(view.grinding_npc_entry) or "____"
        local entry_w = #entry_str * CHAR_W + Theme.space.lg
        push({
            kind = "chip", id = "grind_entry",
            bounds = { x = text_x + #"NPC Entry:" * CHAR_W + Theme.space.sm,
                      y = y - LINE_H, w = entry_w, h = CONTROL_H },
            label = entry_str, selected = true,
        })
        y = y + LINE_H + Theme.space.sm

        -- Zone field
        text_item("body", "text_secondary", "Zone:")
        local zone_str = view.grinding_zone or "Unknown"
        local zone_w = #zone_str * CHAR_W + Theme.space.lg
        push({
            kind = "chip", id = "grind_zone",
            bounds = { x = text_x + #"Zone:" * CHAR_W + Theme.space.sm,
                      y = y - LINE_H, w = zone_w, h = CONTROL_H },
            label = zone_str, selected = true,
        })
        y = y + LINE_H + Theme.space.md

        -- Generate button
        push({
            kind = "button", id = "generate_grind",
            bounds = { x = text_x, y = y, w = math.min(180, content_w), h = CONTROL_H },
            label = "Generate Grind Area", variant = "primary",
            disabled = not view.grinding_npc_entry,
        })
        y = y + CONTROL_H + Theme.space.md

        -- Grinding results
        if view.grinding_result then
            section("Grinding Estimate")
            local g = view.grinding_result

            if g.xp_per_hour then
                text_item("body", "text_primary",
                    fit_label("XP/hour:  " .. DatabaseState._fmt_num(g.xp_per_hour), content_w))
                y = y + LINE_H + Theme.space.xs
            end

            if g.gold_per_hour then
                text_item("body", "text_primary",
                    fit_label("Gold/hour:  " .. DatabaseState._fmt_gold(g.gold_per_hour), content_w))
                y = y + LINE_H + Theme.space.xs
            end

            if g.kills_per_min then
                text_item("body", "text_primary",
                    fit_label(string.format("Kills/min:  %.1f", g.kills_per_min), content_w))
                y = y + LINE_H + Theme.space.xs
            end

            if g.spawn_density then
                text_item("caption", "text_secondary",
                    fit_label("Density:  " .. g.spawn_density .. " spawns in zone", content_w))
                y = y + SMALL_H + Theme.space.xs
            end

            if g.safe_spots then
                text_item("body", "text_primary",
                    fit_label("Safe spots:  " .. g.safe_spots .. " identified", content_w))
                y = y + LINE_H + Theme.space.xs
            end

            if g.pull_radius then
                text_item("body", "text_primary",
                    fit_label(string.format("Pull radius:  %d yds avg", g.pull_radius), content_w))
                y = y + LINE_H + Theme.space.xs
            end

            -- Route info
            if g.route then
                text_item("caption", "text_muted",
                    fit_label("Zone: " .. tostring(g.route.zone or "Unknown"), content_w))
                y = y + SMALL_H
                text_item("caption", "text_muted",
                    fit_label("Waypoints: " .. tostring(#(g.route.waypoints or {})) .. " recorded", content_w))
                y = y + SMALL_H
            end
        end
    end

    return { items = items }
end

-- ============================================================================
-- Display helpers
-- ============================================================================

---Format a number with thousands separators.
function DatabaseState._fmt_num(n)
    if not n then return "0" end
    local s = tostring(math.floor(n))
    local groups = {}
    while #s > 3 do
        table.insert(groups, 1, s:sub(-3))
        s = s:sub(1, -4)
    end
    if #s > 0 then table.insert(groups, 1, s) end
    return table.concat(groups, ",")
end

---Format gold value as "Xg Ys".
function DatabaseState._fmt_gold(n)
    n = tonumber(n) or 0
    local gold = math.floor(n)
    local silver = math.floor((n - gold) * 100 + 0.5)
    return gold .. "g " .. silver .. "s"
end

-- ============================================================================
-- Reduce — map an activated control id to a command for the host
-- ============================================================================

function DatabaseState.reduce(action_id)
    if action_id == nil then return nil end

    -- Tabs
    if action_id == "tab_scanner"  then return { kind = "set_tab", tab = "scanner" } end
    if action_id == "tab_grinding" then return { kind = "set_tab", tab = "grinding" } end

    -- Scan controls
    if action_id == "scan"              then return { kind = "scan" } end
    if action_id == "cycle_scan_mode"   then return { kind = "cycle_scan_mode" } end
    if action_id == "cycle_range"       then return { kind = "cycle_range" } end

    -- Filter: "filter:all" | "filter:herb" | "filter:mining"
    local filter = action_id:match("^filter:(.+)$")
    if filter then
        local filter_val
        if filter ~= "all" then filter_val = filter end
        return { kind = "set_filter", filter = filter_val }
    end

    -- Select entry
    local entry = action_id:match("^select_entry:(%d+)$")
    if entry then return { kind = "select_entry", entry = tonumber(entry) } end

    -- Actions
    local kill = action_id:match("^add_as_kill:(%d+)$")
    if kill then return { kind = "add_as_kill", entry = tonumber(kill) } end

    local detail = action_id:match("^view_detail:(%d+)$")
    if detail then return { kind = "view_detail", entry = tonumber(detail) } end

    -- Grinding
    if action_id == "generate_grind" then return { kind = "generate_grind" } end
    if action_id == "grind_entry"    then return { kind = "edit_grind_entry" } end
    if action_id == "grind_zone"     then return { kind = "edit_grind_zone" } end

    return nil
end

return DatabaseState
