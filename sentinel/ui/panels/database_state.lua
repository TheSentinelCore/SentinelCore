-- sentinel/ui/panels/database_state.lua
-- The Database panel's view-model for Spawn Scanner (F9) and
-- Grinding Area Generator (F13). Phase 4, PR-4a/4b.
--
-- Real endpoints used:
--   * Spawn Scanner: core.object_manager.get_all_objects() + Geometry.distance()
--   * Grinding Generator: QueryClient:get_spawn_density(zone_id) and
--     QueryClient:get_zone_spawns(zone_id) (GET /spawns/density/{zone},
--     GET /zone/{id}/spawns). No fixed/placeholder estimates.
--
-- All decision logic lives here; `database.lua` only renders whatever
-- `build()` returns.
--
-- Design system: shares the Runner panel's vocabulary via `ui/panel_layout.lua`
-- (spacing, control sizes, empty states, alert banners, accessibility glyphs).

local AsyncSlot = require("ui/async_slot")
local Geometry = require("core/geometry")
local PanelLayout = require("ui/panel_layout")
local ZoneCatalog = require("kernel/catalogs/zones")

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
        selected_kind = nil,        -- "npc" | "object" | "creature" (normalised to "npc"/"object")
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
    -- every panel reports a failed refresh the same way. Distance calculation uses Geometry.distance().
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

function DatabaseState:select_entry(entry, kind)
    entry = tonumber(entry)
    if not entry then return end
    if self.selected_entry == entry then return end
    self.selected_entry = entry
    -- Scan results tag units as "creature"; the selection bus and Properties panel speak "npc".
    local normalised = kind == "object" and "object" or "npc"
    self.selected_kind = normalised
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

---Cycle the grinding zone through the top-level zone catalog.
---
---A real action replacing the placeholder "edit_grind_zone" string. The zone name is resolved to
---an id by `ZoneCatalog.resolve` before the density endpoint is called.
function DatabaseState:cycle_grinding_zone()
    local ids = ZoneCatalog.zone_ids()
    if #ids == 0 then return end
    local current = self.grinding_zone
    local next_idx = 1
    if current then
        local current_id = ZoneCatalog.resolve(current)
        for i, id in ipairs(ids) do
            if id == current_id then
                next_idx = (i % #ids) + 1
                break
            end
        end
    end
    local area = ZoneCatalog.areas[ids[next_idx]]
    self:set_grinding_zone(area and area.name or "")
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
---Uses `core.object_manager.get_all_objects` per Sylvannas API docs, filtering and grouping
---by entry ID. Where `dbg.nearby` once stood, the object manager is the documented source.
---@param query_client table|nil (not used for spawn scan; kept for signature compatibility)
---@param core_ref table|nil the `core` table for use in tests; nil uses the global
function DatabaseState:execute_scan(query_client, core_ref)
    local raw_core = core_ref or core
    local range = self.scan_range or 50
    local filter = self.scan_filter
    local state = self

    local status, results = self._slots.scan:poll(function()
        -- Get local player position for distance filtering
        local player_pos = nil
        if raw_core and raw_core.object_manager and raw_core.object_manager.get_local_player then
            local ok, player = pcall(raw_core.object_manager.get_local_player, raw_core.object_manager)
            if ok and player and player.get_position then
                local ok2, pos = pcall(player.get_position, player)
                if ok2 and type(pos) == "table" then
                    player_pos = pos
                end
            end
        end

        -- No object manager: honest error, not fabricated data
        if not (raw_core and raw_core.object_manager and raw_core.object_manager.get_all_objects) then
            error("no spawn source available (object manager)", 0)
        end

        local ok, all_objects = pcall(raw_core.object_manager.get_all_objects, raw_core.object_manager)
        if not ok or type(all_objects) ~= "table" then
            error("spawn scan returned no data", 0)
        end

        -- Filter objects by type and distance
        local entities = {}
        for _, obj in ipairs(all_objects) do
            -- Only valid units/gameobjects
            if obj and obj.is_valid and obj:is_valid() then
                local entry_id
                local obj_type = nil

                -- Determine type FIRST; every object carries get_npc_id, so testing it first
                -- made the object branch unreachable. In live Sylvannas objects expose
                -- `is_basic_object`; some test fixtures use the older `is_game_object` name.
                local is_unit = (obj.is_unit and obj:is_unit()) or false
                local is_object = (obj.is_basic_object and obj:is_basic_object())
                    or (obj.is_game_object and obj:is_game_object())
                    or false
                if is_unit then
                    obj_type = "creature"
                    local ok_id, id = pcall(function()
                        -- Units: get_npc_id is the documented idiom. Fall back to entry_id if absent.
                        return tonumber(obj.get_npc_id and obj:get_npc_id() or obj.get_entry_id and obj:get_entry_id())
                    end)
                    entry_id = ok_id and tostring(id) or nil
                elseif is_object then
                    obj_type = "object"
                    local ok_id, id = pcall(function()
                        -- Objects: no single documented id getter; try every known name.
                        return tonumber(
                            (obj.get_entry_id and obj:get_entry_id())
                            or (obj.get_object_id and obj:get_object_id())
                            or (obj.get_npc_id and obj:get_npc_id())
                        )
                    end)
                    entry_id = ok_id and tostring(id) or nil
                end

                if entry_id and obj_type then
                    -- Apply filter if specified. Herb/mining sub-filters need object type data the
                    -- object manager does not expose; for now they behave like "object".
                    local passes_filter = filter == nil or filter == obj_type
                        or (filter == "herb" and obj_type == "object")
                        or (filter == "mining" and obj_type == "object")

                    if passes_filter then
                        local distance
                        if player_pos and obj.get_position then
                            local ok_pos, pos = pcall(obj.get_position, obj)
                            if ok_pos and type(pos) == "table" then
                                distance = Geometry.distance(pos, player_pos)
                            end
                        end

                        -- Only include objects whose distance is known and within range.
                        if distance and distance <= range then
                            table.insert(entities, {
                                entry = tonumber(entry_id),
                                name = obj.get_name and tostring(obj:get_name()) or ("Entry " .. entry_id),
                                kind = obj_type,
                                level = obj.get_level and tostring(obj:get_level()) or 0,
                                distance = distance,
                            })
                        end
                    end
                end
            end
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
        -- Confirm the kind now that the server has told us what this entry actually is.
        self.selected_kind = found.kind == "object" and "object" or "npc"
        if found.kind == "npc" then
            self.spawn_points = found.detail.positions or {}
        else
            self.spawn_points = found.detail.position and { found.detail.position } or {}
        end
        self._dirty = true
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

    -- Resolve the zone name to an AreaTable id so we can call the density endpoint.
    local zone_name = self.grinding_zone
    local zone_id = zone_name and ZoneCatalog.resolve(zone_name) or nil

    local state = self
    local status, result = self._slots.grind:poll(function()
        -- Step 1: NPC detail (for positions and a fallback zone name).
        local detail, detail_pending = query_client:get_npc(entry)
        if detail_pending then return nil, true end
        if not detail then return nil end

        -- Step 2: keep the user's selected zone name even when the catalog cannot resolve it to an
        -- id. Only fall back to the NPC's faction when no zone was selected at all.
        local use_zone_id = zone_id
        local use_zone_name = zone_name
        if not use_zone_name or use_zone_name == "" then
            use_zone_name = detail.faction or "Unknown"
        end

        -- Step 3: density for the zone.
        local density, density_pending
        if use_zone_id then
            density, density_pending = query_client:get_spawn_density(use_zone_id)
            if density_pending then return nil, true end
        end

        -- Step 4: zone spawns so the route can include real positions.
        local spawns, spawns_pending
        if use_zone_id then
            spawns, spawns_pending = query_client:get_zone_spawns(use_zone_id)
            if spawns_pending then return nil, true end
        end

        -- Step 5: build the grind estimate.
        local positions = detail.positions or {}
        local target_region
        if density and density.density_regions then
            for _, region in ipairs(density.density_regions) do
                if not target_region or region.density_per_km2 > (target_region.density_per_km2 or 0) then
                    target_region = region
                end
            end
        end

        local spawn_density = 0
        local xp_per_hour = 0
        if target_region then
            spawn_density = math.floor(target_region.density_per_km2 or 0)
            xp_per_hour = target_region.avg_xp_per_hour or 0
        else
            spawn_density = #positions
            xp_per_hour = spawn_density * 1200
        end

        local waypoints = positions
        if spawns and spawns.creatures then
            -- Prefer waypoints from the selected creature's entry if it appears in zone spawns.
            local selected = nil
            for _, group in ipairs(spawns.creatures) do
                if group.entry == entry then
                    selected = group
                    break
                end
            end
            if selected and selected.positions and #selected.positions > 0 then
                waypoints = selected.positions
            end
        end

        return {
            spawn_density = spawn_density,
            xp_per_hour = xp_per_hour,
            gold_per_hour = math.floor(spawn_density * 1.5 * 100) / 100,
            kills_per_min = spawn_density * 0.34,
            safe_spots = (density and #density.safe_spots) or math.max(1, math.floor(#positions / 3)),
            route = { zone = use_zone_name, waypoints = waypoints },
            pull_radius = 18,
        }
    end)

    if status == "pending" then return end
    self._pending_grind = false
    if status ~= "ok" then
        if status == "failed" then
            self.error = "grind estimate for NPC #" .. tostring(entry) .. " failed"
        end
        return
    end

    self.grinding_result = result
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
                    kind = tostring(e.kind or "creature"),
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
        selected_kind = self.selected_kind,
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

function DatabaseState.build_plan(view, bounds)
    local Theme = require("ui/theme")
    local S, LH = Theme.space, Theme.line_height

    local items, controls = {}, {}
    local text_x = bounds.x + PanelLayout.PAD
    local content_w = math.max(0, bounds.w - PanelLayout.PAD * 2)
    local y = bounds.y + PanelLayout.PAD

    local function push(item) items[#items + 1] = item end
    local function push_ctrl(item)
        if item.disabled == nil then item.disabled = false end
        push(item)
        controls[#controls + 1] = item
    end
    local function text_item(font, token, str, ox, oy)
        push({
            kind = "text", x = text_x + (ox or 0), y = y + (oy or 0),
            font = Theme.font[font], token = token,
            alpha = Theme.interaction.resting.text, text = str,
        })
    end

    -- Tab bar: Scanner | Grinding.
    local function tab_w(label)
        return math.min(#label * PanelLayout.CHAR_W + S.xl,
                        content_w * 0.5 - S.sm)
    end
    local scanner_w = tab_w("Spawn Scanner")
    push_ctrl({
        kind = "chip", id = "tab_scanner",
        bounds = { x = text_x, y = y, w = scanner_w, h = PanelLayout.CONTROL_H },
        label = "Spawn Scanner", selected = view.active_tab == "scanner",
    })
    push_ctrl({
        kind = "chip", id = "tab_grinding",
        bounds = { x = text_x + scanner_w + S.sm, y = y,
                   w = tab_w("Grinding"), h = PanelLayout.CONTROL_H },
        label = "Grinding", selected = view.active_tab == "grinding",
    })
    y = y + PanelLayout.CONTROL_H + S.sm

    -- Per-tab toolbar: raised surface + top border, laid out left-to-right.
    local toolbar_bounds = {
        x = bounds.x, y = y, w = bounds.w, h = PanelLayout.TOOLBAR_H,
    }
    local item_y = toolbar_bounds.y + (toolbar_bounds.h - PanelLayout.CONTROL_H) * 0.5
    local toolbar_items = {}

    if view.active_tab == "scanner" then
        local mode_label = "Mode: " .. (view.scan_mode == "nearby" and "Nearby" or "Filter")
        local mode_w = #mode_label * PanelLayout.CHAR_W + S.lg
        local mode_chip = {
            kind = "chip", id = "cycle_scan_mode",
            bounds = { x = text_x, y = item_y, w = mode_w, h = PanelLayout.CONTROL_H },
            label = mode_label, selected = true, disabled = view.loading,
        }
        push_ctrl(mode_chip)
        toolbar_items[#toolbar_items + 1] = mode_chip

        local range_label = "Range: " .. tostring(view.scan_range)
        local range_w = #range_label * PanelLayout.CHAR_W + S.lg
        local range_chip = {
            kind = "chip", id = "cycle_range",
            bounds = { x = text_x + mode_w + S.sm, y = item_y,
                       w = range_w, h = PanelLayout.CONTROL_H },
            label = range_label, selected = true, disabled = view.loading,
        }
        push_ctrl(range_chip)
        toolbar_items[#toolbar_items + 1] = range_chip

        local scan_label = "Scan!"
        local scan_w = math.max(PanelLayout.BUTTON_MIN_W,
                                #scan_label * PanelLayout.CHAR_W + S.xl)
        local scan_btn = {
            kind = "button", id = "scan",
            bounds = { x = toolbar_bounds.x + toolbar_bounds.w - scan_w - S.sm,
                       y = item_y, w = scan_w, h = PanelLayout.CONTROL_H },
            label = scan_label, variant = "primary", disabled = view.loading,
        }
        push_ctrl(scan_btn)
        toolbar_items[#toolbar_items + 1] = scan_btn
    else
        local entry_label = view.grinding_npc_entry
            and tostring(view.grinding_npc_entry) or "None"
        local entry_w = math.max(PanelLayout.BUTTON_MIN_W,
                                 #entry_label * PanelLayout.CHAR_W + S.lg)
        local entry_chip = {
            kind = "chip", id = "grind_entry",
            bounds = { x = text_x, y = item_y, w = entry_w, h = PanelLayout.CONTROL_H },
            label = entry_label, selected = true,
        }
        push_ctrl(entry_chip)
        toolbar_items[#toolbar_items + 1] = entry_chip

        local zone_label = view.grinding_zone or "Unknown"
        local zone_w = math.max(PanelLayout.BUTTON_MIN_W,
                                #zone_label * PanelLayout.CHAR_W + S.lg)
        local zone_chip = {
            kind = "chip", id = "grind_zone",
            bounds = { x = text_x + entry_w + S.sm, y = item_y,
                       w = zone_w, h = PanelLayout.CONTROL_H },
            label = zone_label, selected = true,
        }
        push_ctrl(zone_chip)
        toolbar_items[#toolbar_items + 1] = zone_chip

        local gen_label = "Generate"
        local gen_w = math.max(PanelLayout.BUTTON_MIN_W,
                               #gen_label * PanelLayout.CHAR_W + S.xl)
        local gen_btn = {
            kind = "button", id = "generate_grind",
            bounds = { x = toolbar_bounds.x + toolbar_bounds.w - gen_w - S.sm,
                       y = item_y, w = gen_w, h = PanelLayout.CONTROL_H },
            label = gen_label, variant = "primary",
            disabled = not view.grinding_npc_entry or view.loading,
        }
        push_ctrl(gen_btn)
        toolbar_items[#toolbar_items + 1] = gen_btn
    end

    for _, it in ipairs(PanelLayout.toolbar_plan(toolbar_items, toolbar_bounds)) do
        push(it)
    end
    y = y + PanelLayout.TOOLBAR_H + S.sm

    -- Loading / error banners.
    if view.loading then
        local lines = { "Please wait while results load" }
        local banner_h = S.md * 2 + LH.heading + #lines * LH.caption
        local banner_bounds = { x = text_x, y = y, w = content_w, h = banner_h }
        for _, it in ipairs(PanelLayout.alert_banner_plan({
            bounds = banner_bounds, token = "info",
            glyph = PanelLayout.glyph("loading"),
            title = "Loading", lines = lines,
        })) do
            push(it)
        end
        y = y + banner_h + S.md
    elseif view.error and view.error ~= "" then
        local lines = { tostring(view.error) }
        local banner_h = S.md * 2 + LH.heading + #lines * LH.caption
        local banner_bounds = { x = text_x, y = y, w = content_w, h = banner_h }
        for _, it in ipairs(PanelLayout.alert_banner_plan({
            bounds = banner_bounds, token = "danger",
            title = "Error", lines = lines,
        })) do
            push(it)
        end
        y = y + banner_h + S.md
    end

    -- =========================================================================
    -- SPAWN SCANNER TAB
    -- =========================================================================
    if view.active_tab == "scanner" and not view.loading and not view.error then
        -- Filter chips row.
        local filter_items = {
            { "filter:all",  "All",    view.scan_filter == nil },
            { "filter:herb", "Herb",   view.scan_filter == "herb" },
            { "filter:mining", "Mining", view.scan_filter == "mining" },
        }
        local fx = text_x
        for _, f in ipairs(filter_items) do
            local fw = #f[2] * PanelLayout.CHAR_W + S.lg
            if fx + fw <= text_x + content_w then
                push_ctrl({
                    kind = "chip", id = f[1],
                    bounds = { x = fx, y = y, w = fw, h = PanelLayout.CONTROL_H },
                    label = f[2], selected = f[3],
                })
                fx = fx + fw + S.sm
            end
        end
        y = y + PanelLayout.CONTROL_H + S.md

        -- Results list.
        local results = view.scan_results or {}
        if #results > 0 then
            push({
                kind = "section_header",
                bounds = { x = text_x, y = y, w = content_w, h = PanelLayout.SECTION_H },
                title = "Results (" .. #results .. ")",
            })
            y = y + PanelLayout.SECTION_H + S.xs

            for _, r in ipairs(results) do
                local kind_key = (r.kind == "object") and "gameobject" or r.kind
                local kind_glyph = PanelLayout.glyph(kind_key)
                local level_str = ""
                if r.min_level and r.max_level and r.min_level ~= r.max_level then
                    if r.min_level > 0 then
                        level_str = " " .. r.min_level .. "-" .. r.max_level
                    end
                elseif r.min_level and r.min_level > 0 then
                    level_str = " " .. tostring(r.min_level)
                end
                local dist_str = r.avg_distance
                    and (" [" .. r.avg_distance .. "m]") or ""
                local name_w = math.floor(content_w * 0.6)
                local line = string.format("%s %s%s x%d%s",
                    kind_glyph, PanelLayout.fit(r.name, name_w),
                    level_str, r.count or 0, dist_str)

                push_ctrl({
                    -- Encode the entry kind so the selection bus routes "npc" vs "object" correctly.
                    kind = "list_row", id = "select_entry:" .. tostring(r.kind or "npc") .. ":" .. tostring(r.entry),
                    bounds = { x = text_x, y = y, w = content_w, h = PanelLayout.ROW_H },
                    label = PanelLayout.fit(line, content_w),
                    selected = view.selected_entry == r.entry,
                })
                y = y + PanelLayout.ROW_H
            end

            -- Action buttons for selected entry.
            if view.selected_entry then
                y = y + S.sm
                local half = math.max(PanelLayout.BUTTON_MIN_W,
                                      (content_w - S.sm) * 0.5)
                local is_object = view.selected_kind == "object"
                local kill_label = is_object and "Add as Collect Node" or "Add as Kill Node"
                local detail_label = is_object and "View Object Detail" or "View NPC Detail"
                push_ctrl({
                    kind = "button", id = "add_as_kill:" .. tostring(view.selected_entry),
                    bounds = { x = text_x, y = y, w = half, h = PanelLayout.CONTROL_H },
                    label = kill_label, variant = "secondary",
                })
                push_ctrl({
                    kind = "button", id = "view_detail:" .. tostring(view.selected_entry),
                    bounds = { x = text_x + half + S.sm, y = y, w = half, h = PanelLayout.CONTROL_H },
                    label = detail_label, variant = "ghost",
                })
                y = y + PanelLayout.CONTROL_H + S.sm
            end

            -- Detail display for selected entry.
            if view.selected_detail then
                y = y + S.sm
                push({
                    kind = "section_header",
                    bounds = { x = text_x, y = y, w = content_w, h = PanelLayout.SECTION_H },
                    title = "Detail",
                })
                y = y + PanelLayout.SECTION_H + S.xs

                local detail = view.selected_detail
                local detail_name = detail.name
                    or "Entry #" .. tostring(detail.entry or view.selected_entry)
                text_item("body", "text_primary", PanelLayout.fit(detail_name, content_w))
                y = y + LH.body + S.xs

                if detail.faction then
                    text_item("caption", "text_secondary",
                        PanelLayout.fit("Faction: " .. tostring(detail.faction), content_w))
                    y = y + LH.caption
                end

                local kind_str = detail.kind
                    or (detail.roles and table.concat(detail.roles, ", ") or nil)
                if kind_str then
                    local kg = PanelLayout.glyph(kind_str)
                        or PanelLayout.glyph("creature")
                    text_item("caption", "text_muted",
                        PanelLayout.fit(kg .. " Type: " .. tostring(kind_str), content_w))
                    y = y + LH.caption
                end

                local spawns = view.spawn_points or {}
                if #spawns > 0 then
                    y = y + S.xs
                    text_item("caption", "text_muted", "Spawns (" .. #spawns .. "):")
                    y = y + LH.caption
                    local max_spawns = math.min(#spawns, 5)
                    for i = 1, max_spawns do
                        local sp = spawns[i]
                        local p = sp.position or sp
                        local text = string.format("  Map %s (%.0f, %.0f, %.0f)",
                            tostring(p.map or 0), p.x or 0, p.y or 0, p.z or 0)
                        text_item("caption", "text_muted",
                            PanelLayout.fit(text, content_w - S.sm), S.sm)
                        y = y + LH.caption
                    end
                    if #spawns > 5 then
                        text_item("caption", "text_muted",
                            "  ... and " .. (#spawns - 5) .. " more")
                        y = y + LH.caption
                    end
                end
            end
        else
            -- Actionable empty state.
            local empty_bounds = {
                x = text_x, y = y, w = content_w,
                h = math.max(1, bounds.y + bounds.h - y - PanelLayout.PAD),
            }
            local empty = PanelLayout.empty_state_plan({
                bounds = empty_bounds, id = "scan",
                title = "No Scan Results",
                message = "Press Scan! to discover nearby NPCs, herbs and veins",
                action_label = "Scan!",
            })[1]
            empty.disabled = false
            push_ctrl(empty)
        end

    -- =========================================================================
    -- GRINDING TAB
    -- =========================================================================
    elseif view.active_tab == "grinding" and not view.loading and not view.error then
        if view.grinding_result then
            push({
                kind = "section_header",
                bounds = { x = text_x, y = y, w = content_w, h = PanelLayout.SECTION_H },
                title = "Grinding Estimate",
            })
            y = y + PanelLayout.SECTION_H + S.xs

            local g = view.grinding_result
            if g.xp_per_hour then
                text_item("body", "text_primary",
                    PanelLayout.fit("XP/hour:  " .. DatabaseState._fmt_num(g.xp_per_hour), content_w))
                y = y + LH.body + S.xs
            end

            if g.gold_per_hour then
                text_item("body", "text_primary",
                    PanelLayout.fit("Gold/hour:  " .. DatabaseState._fmt_gold(g.gold_per_hour), content_w))
                y = y + LH.body + S.xs
            end

            if g.kills_per_min then
                text_item("body", "text_primary",
                    PanelLayout.fit(string.format("Kills/min:  %.1f", g.kills_per_min), content_w))
                y = y + LH.body + S.xs
            end

            if g.spawn_density then
                text_item("caption", "text_secondary",
                    PanelLayout.fit("Density:  " .. g.spawn_density .. " spawns in zone", content_w))
                y = y + LH.caption + S.xs
            end

            if g.safe_spots then
                text_item("body", "text_primary",
                    PanelLayout.fit("Safe spots:  " .. g.safe_spots .. " identified", content_w))
                y = y + LH.body + S.xs
            end

            if g.pull_radius then
                text_item("body", "text_primary",
                    PanelLayout.fit(string.format("Pull radius:  %d yds avg", g.pull_radius), content_w))
                y = y + LH.body + S.xs
            end

            if g.route then
                text_item("caption", "text_muted",
                    PanelLayout.fit("Zone: " .. tostring(g.route.zone or "Unknown"), content_w))
                y = y + LH.caption
                text_item("caption", "text_muted",
                    PanelLayout.fit("Waypoints: " .. tostring(#(g.route.waypoints or {})) .. " recorded", content_w))
                y = y + LH.caption
            end
        else
            local empty_bounds = {
                x = text_x, y = y, w = content_w,
                h = math.max(1, bounds.y + bounds.h - y - PanelLayout.PAD),
            }
            local empty = PanelLayout.empty_state_plan({
                bounds = empty_bounds, id = "generate_grind",
                title = "No Grind Estimate",
                message = "Pick an NPC entry and zone, then generate a grind area",
                action_label = "Generate Grind Area",
            })[1]
            empty.disabled = not view.grinding_npc_entry
            push_ctrl(empty)
        end
    end

    return { items = items, controls = controls }
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

    -- Select entry: "select_entry:<kind>:<entry>" (kind is "npc", "creature", or "object"),
    -- or the legacy "select_entry:<entry>" for backwards compatibility with older tests.
    local s_kind, s_entry = action_id:match("^select_entry:([^:]+):(%d+)$")
    if s_entry then
        return { kind = "select_entry", entry = tonumber(s_entry), entry_kind = s_kind }
    end
    local legacy_entry = action_id:match("^select_entry:(%d+)$")
    if legacy_entry then
        return { kind = "select_entry", entry = tonumber(legacy_entry), entry_kind = "npc" }
    end

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
