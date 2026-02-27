local BT = require("ai/BehaviorTree")
local BTStatus = BT.Status
local Helpers = require("lib/Helpers")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")
local get_now = require("lib/TimeHelper").get_now
local PathEntropy = require("ai/PathEntropy")

---@private
---@param pos vec3|nil
---@return boolean
local function is_valid_position(pos)
    if type(pos) ~= "table" then
        return false
    end
    return tonumber(pos.x) ~= nil and tonumber(pos.y) ~= nil and tonumber(pos.z) ~= nil
end

---@private
---@param value any
---@return string|nil
local function normalize_mode(value)
    local mode = tostring(value or ""):lower()
    if mode == "" then
        return nil
    end
    return mode
end

---@private
---@param opts table|nil
---@param key string
---@param fallback number
---@return number
local function cfg_number(opts, key, fallback)
    local value = tonumber(opts and opts[key])
    if value == nil then
        return fallback
    end
    return value
end

---@class ExplorationService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _nav NavigationAdapter|nil
---@field private _targeting TargetingService|nil
---@field private _cfg table
---@field private _cells table<string, table>
---@field private _recent_cells string[]
---@field private _active table|nil
---@field private _last_frontier_phase number
local ExplorationService = {}
ExplorationService.__index = ExplorationService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table|nil
---@param navigation NavigationAdapter|nil
---@param targeting TargetingService|nil
---@return ExplorationService
function ExplorationService:new(event_bus, blackboard, cfg, navigation, targeting, logger)
    local o = setmetatable({}, ExplorationService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._nav = navigation
    o._targeting = targeting
    o._cells = {}
    o._recent_cells = {}
    o._active = nil
    o._last_frontier_phase = 0
    o._path_entropy = PathEntropy:new()
    o._log = logger or { debug=function()end, info=function()end, warn=function()end, error=function()end }
    -- Global nav-failure backoff: consecutive frontier failures (no navmesh coverage)
    -- arm a cooldown to prevent infinite 422 churn.
    o._nav_fail_streak = 0
    o._nav_backoff_until = 0
    o:_write_state("idle", nil, nil, nil)
    return o
end

---@private
---@return boolean
function ExplorationService:_is_enabled()
    if self._cfg.enabled == false then
        return false
    end

    -- Suppress during profile traveling/vendor states
    local profile_state = self._blackboard:get("profile.state")
    if profile_state == "traveling" or profile_state == "vendor_trip" then
        return false
    end

    local mode = normalize_mode(self._blackboard:get("core.mode"))
    if not mode then
        return true
    end

    local enabled_modes = self._cfg.enabled_modes
    if type(enabled_modes) ~= "table" or #enabled_modes == 0 then
        return true
    end

    for i = 1, #enabled_modes do
        if normalize_mode(enabled_modes[i]) == mode then
            return true
        end
    end

    return false
end

---@private
---@return vec3|nil
function ExplorationService:_get_player_position()
    local pos = self._blackboard:get("player.position")
    if is_valid_position(pos) then
        return {
            x = tonumber(pos.x) or 0,
            y = tonumber(pos.y) or 0,
            z = tonumber(pos.z) or 0,
        }
    end
    return nil
end

---@private
---@param player_pos vec3|nil
---@return vec3|nil
function ExplorationService:_resolve_anchor(player_pos)
    local anchor = self._blackboard:get("grind.anchor")
    if not is_valid_position(anchor) then
        anchor = self._blackboard:get("core.mode_anchor")
    end
    if is_valid_position(anchor) then
        return {
            x = tonumber(anchor.x) or 0,
            y = tonumber(anchor.y) or 0,
            z = tonumber(anchor.z) or 0,
        }
    end
    return player_pos
end

---@private
---@param cell_size number
---@param pos vec3
---@return number
---@return number
function ExplorationService:_cell_index(cell_size, pos)
    local x = tonumber(pos.x) or 0
    local y = tonumber(pos.y) or 0
    local cx = math.floor((x / cell_size) + 0.5)
    local cy = math.floor((y / cell_size) + 0.5)
    return cx, cy
end

---@private
---@param cx number
---@param cy number
---@return string
function ExplorationService:_cell_key(cx, cy)
    return tostring(cx) .. ":" .. tostring(cy)
end

---@private
---@param key string
function ExplorationService:_mark_recent_cell(key)
    local max_recent = math.max(1, math.floor(cfg_number(self._cfg, "recent_cells", 8)))
    self._recent_cells[#self._recent_cells + 1] = key
    while #self._recent_cells > max_recent do
        table.remove(self._recent_cells, 1)
    end
end

---@private
---@param key string
---@return boolean
function ExplorationService:_was_recently_visited(key)
    for i = #self._recent_cells, 1, -1 do
        if self._recent_cells[i] == key then
            return true
        end
    end
    return false
end

---@private
---@param now number
function ExplorationService:_prune_cells(now)
    local ttl = cfg_number(self._cfg, "cell_memory_ttl", 360.0)
    local max_entries = math.max(64, math.floor(cfg_number(self._cfg, "cell_memory_max_entries", 512)))
    local count = 0

    for key, entry in pairs(self._cells) do
        local touched = tonumber(entry and entry.last_touched_at) or 0
        if touched > 0 and (now - touched) <= ttl then
            count = count + 1
        else
            self._cells[key] = nil
        end
    end

    if count <= max_entries then
        return
    end

    -- Collect surviving entries sorted by age (oldest first) so we evict
    -- the least-recently-touched cells rather than an arbitrary pairs() order.
    local by_age = {}
    for key, entry in pairs(self._cells) do
        by_age[#by_age + 1] = { key = key, touched = tonumber(entry and entry.last_touched_at) or 0 }
    end
    table.sort(by_age, function(a, b) return a.touched < b.touched end)

    local overflow = count - max_entries
    for i = 1, #by_age do
        if overflow <= 0 then break end
        self._cells[by_age[i].key] = nil
        overflow = overflow - 1
    end
end

---@private
---@param cx number
---@param cy number
---@return table
function ExplorationService:_get_or_create_cell(cx, cy)
    local key = self:_cell_key(cx, cy)
    local cell = self._cells[key]
    if type(cell) ~= "table" then
        cell = {
            key = key,
            cx = cx,
            cy = cy,
            sighting_score = 0,
            last_seen_at = 0,
            last_visited_at = 0,
            fail_until = 0,
            failure_count = 0,
            last_touched_at = 0,
        }
        self._cells[key] = cell
    end
    return cell
end

---@private
---@param now number
---@param player_pos vec3
function ExplorationService:_record_player_cell(now, player_pos)
    local cell_size = math.max(3.0, cfg_number(self._cfg, "cell_size", 18.0))
    local cx, cy = self:_cell_index(cell_size, player_pos)
    local cell = self:_get_or_create_cell(cx, cy)
    cell.last_visited_at = now
    cell.last_touched_at = now
    self:_mark_recent_cell(cell.key)
end

---@private
---@param now number
---@param candidates table
function ExplorationService:_record_candidate_cells(now, candidates)
    if type(candidates) ~= "table" or #candidates == 0 then
        return
    end

    local cell_size = math.max(3.0, cfg_number(self._cfg, "cell_size", 18.0))
    local sighting_gain = cfg_number(self._cfg, "sighting_gain", 1.0)
    local sighting_cap = math.max(1.0, cfg_number(self._cfg, "sighting_cap", 8.0))

    -- Track per-cell candidate counts for cluster sighting detection.
    local cell_counts = {}
    for i = 1, #candidates do
        local entry = candidates[i]
        local target = entry and entry.target
        local ok_pos, pos = pcall(function() return target and target.get_position and target:get_position() end)
        if ok_pos and is_valid_position(pos) then
            local cx, cy = self:_cell_index(cell_size, pos)
            local cell = self:_get_or_create_cell(cx, cy)
            local score = tonumber(entry.score) or 0
            local normalized = Helpers.clamp((score + 1.0) * 0.5, 0.05, 1.0)
            cell.sighting_score = Helpers.clamp((tonumber(cell.sighting_score) or 0) + (sighting_gain * normalized), 0, sighting_cap)
            cell.last_seen_at = now
            cell.last_touched_at = now
            local key = cell.key
            cell_counts[key] = (cell_counts[key] or 0) + 1
        end
    end

    -- If 3+ enemies were sighted in a single cell this update, record a cluster sighting.
    for key, count in pairs(cell_counts) do
        if count >= 3 and self._cells[key] then
            local cell = self._cells[key]
            cell.cluster_sightings = (tonumber(cell.cluster_sightings) or 0) + 1
        end
    end
end

---@private
---@param now number
---@param player_pos vec3
---@param engage_radius number
---@param candidates table
---@return table|nil
function ExplorationService:_select_pursuit(now, player_pos, engage_radius, candidates)
    if type(candidates) ~= "table" or #candidates == 0 then
        return nil
    end

    local pursuit_extra = math.max(0, cfg_number(self._cfg, "pursuit_extra_radius", 30.0))
    local pursuit_min_gap = math.max(0, cfg_number(self._cfg, "pursuit_min_gap", 2.0))
    local pursuit_max = engage_radius + pursuit_extra

    local best = nil
    local best_score = -math.huge
    for i = 1, #candidates do
        local entry = candidates[i]
        local target = entry and entry.target
        local distance = tonumber(entry and entry.distance) or math.huge
        if target and distance > (engage_radius + pursuit_min_gap) and distance <= pursuit_max then
            local score = tonumber(entry.score) or 0
            local distance_penalty = distance / math.max(1.0, pursuit_max)
            local utility = score - (distance_penalty * cfg_number(self._cfg, "pursuit_distance_weight", 0.15))
            if utility > best_score then
                local ok_p, pos = pcall(function() return target.get_position and target:get_position() end)
                if ok_p and is_valid_position(pos) then
                    best_score = utility
                    best = {
                        mode = "pursuit",
                        destination = {
                            x = tonumber(pos.x) or 0,
                            y = tonumber(pos.y) or 0,
                            z = tonumber(pos.z) or 0,
                        },
                        score = utility,
                        target = target,
                        distance = distance,
                        engage_radius = engage_radius,
                        cell_key = nil,
                    }
                end
            end
        end
    end

    return best
end

---@private
---@param now number
---@param player_pos vec3
---@param anchor vec3
---@return table|nil
function ExplorationService:_select_frontier(now, player_pos, anchor)
    local cell_size = math.max(3.0, cfg_number(self._cfg, "cell_size", 18.0))
    local min_radius = math.max(6.0, cfg_number(self._cfg, "frontier_min_radius", 20.0))
    local max_radius = math.max(min_radius + 1.0, cfg_number(self._cfg, "frontier_max_radius", 65.0))
    local rings = math.max(1, math.floor(cfg_number(self._cfg, "frontier_ring_count", 3)))
    local rays = math.max(8, math.floor(cfg_number(self._cfg, "frontier_rays", 20)))
    local novelty_horizon = math.max(10.0, cfg_number(self._cfg, "novelty_horizon", 120.0))
    local seen_horizon = math.max(5.0, cfg_number(self._cfg, "seen_horizon", 90.0))

    local w_novelty = cfg_number(self._cfg, "weight_novelty", 0.55)
    local w_sighting = cfg_number(self._cfg, "weight_sighting", 0.30)
    local w_travel = cfg_number(self._cfg, "weight_travel", 0.20)
    local w_recent = cfg_number(self._cfg, "weight_recent", 0.35)
    local w_failure = cfg_number(self._cfg, "weight_failure", 0.60)

    -- Sighting score decay constants: scores decay exponentially with age.
    -- Half-life is ~10 minutes (600s); never decays below SIGHTING_DECAY_MIN.
    local SIGHTING_DECAY_MIN = 1.0
    local SIGHTING_DECAY_HALF_LIFE = 600.0

    self._last_frontier_phase = (self._last_frontier_phase + 1) % rays
    local phase_offset = (self._last_frontier_phase / rays) * (math.pi * 2)

    -- Read explore mode from active tactic (written by GrindService).
    local explore_config = self._blackboard:get("tactical.explore_config")
    local explore_mode = explore_config and explore_config.mode or "frontier"

    local best = nil
    local best_score = -math.huge

    for ring = 1, rings do
        local t = ring / rings
        local radius = min_radius + ((max_radius - min_radius) * t)
        for ray = 1, rays do
            local angle = phase_offset + ((ray / rays) * (math.pi * 2))
            local destination = {
                x = (tonumber(anchor.x) or 0) + (math.cos(angle) * radius),
                y = (tonumber(anchor.y) or 0) + (math.sin(angle) * radius),
                z = tonumber(anchor.z) or tonumber(player_pos.z) or 0,
            }

            local cx, cy = self:_cell_index(cell_size, destination)
            local cell = self:_get_or_create_cell(cx, cy)
            cell.last_touched_at = now

            local fail_until = tonumber(cell.fail_until) or 0
            if fail_until <= now then
                local dist = Helpers.distance_3d(player_pos, destination)
                local travel_term = Helpers.clamp(dist / math.max(1.0, max_radius), 0.0, 1.5)

                local last_visit = tonumber(cell.last_visited_at) or 0
                local novelty_age = (last_visit > 0) and (now - last_visit) or novelty_horizon
                local novelty = Helpers.clamp(novelty_age / novelty_horizon, 0.0, 1.0)

                local last_seen = tonumber(cell.last_seen_at) or 0
                local seen_age = (last_seen > 0) and (now - last_seen) or seen_horizon
                local seen_freshness = 1.0 - Helpers.clamp(seen_age / seen_horizon, 0.0, 1.0)
                -- Apply age-based exponential decay to sighting_score so stale
                -- high-value cells do not permanently dominate frontier selection.
                -- Decay uses last_seen_at as the "last activity" timestamp;
                -- half-life is ~10 minutes.  Never decays below SIGHTING_DECAY_MIN.
                local raw_sighting = tonumber(cell.sighting_score) or 0
                local decay_age_secs = (last_seen > 0) and (now - last_seen) or 0
                local decay_factor = math.max(0.1, math.exp(-decay_age_secs / SIGHTING_DECAY_HALF_LIFE))
                local decayed_sighting = math.max(SIGHTING_DECAY_MIN, raw_sighting * decay_factor)
                local seen_score = Helpers.clamp(decayed_sighting / math.max(1.0, cfg_number(self._cfg, "sighting_cap", 8.0)), 0.0, 1.0)
                local sighting = seen_freshness * seen_score

                local recently_visited = self:_was_recently_visited(cell.key) and 1.0 or 0.0
                local failure_count = Helpers.clamp((tonumber(cell.failure_count) or 0) / 5.0, 0.0, 1.0)

                local utility = (novelty * w_novelty)
                    + (sighting * w_sighting)
                    - (travel_term * w_travel)
                    - (recently_visited * w_recent)
                    - (failure_count * w_failure)

                -- cluster_seek mode: boost cells where enemy clusters were recently sighted.
                if explore_mode == "cluster_seek" then
                    local cs = tonumber(cell.cluster_sightings) or 0
                    if cs > 0 then
                        utility = utility + 0.4 * math.min(cs, 5) / 5
                    end
                end

                if utility > best_score then
                    best_score = utility
                    -- Jitter the destination slightly so the bot doesn't always
                    -- walk to the exact same grid-aligned frontier points.
                    local jittered_dest = self._path_entropy:jitter_position(destination)
                    best = {
                        mode = "frontier",
                        destination = jittered_dest,
                        score = utility,
                        target = nil,
                        distance = dist,
                        engage_radius = 0,
                        cell_key = cell.key,
                    }
                end
            end
        end
    end

    -- Terrain height validation: skip candidates that land on void/underwater terrain.
    -- Uses cached results from NavigationAdapter; fail-open if nav or cache unavailable.
    if best and self._nav and type(self._nav.validate_position) == "function" then
        local ok_v, valid = pcall(self._nav.validate_position, self._nav, best.destination)
        if ok_v and valid == false then
            self._log:debug("frontier candidate rejected: invalid terrain at (%.1f, %.1f, %.1f)",
                tonumber(best.destination.x) or 0,
                tonumber(best.destination.y) or 0,
                tonumber(best.destination.z) or 0)
            best = nil
        end
    end

    -- Zone boundary guard: reject frontier cells too far from the grind anchor.
    -- We can't cheaply query zone_id for an arbitrary position, so we use
    -- distance-from-anchor as a proxy for zone containment.
    if best then
        local canonical = self._blackboard:get("context.canonical")
        local anchor_zone = canonical and tonumber(canonical.zone_id) or 0
        if anchor_zone and anchor_zone > 0 then
            local anchor = self:_resolve_anchor(player_pos)
            if anchor and best.destination then
                local dx = best.destination.x - anchor.x
                local dy = best.destination.y - anchor.y
                local dist_from_anchor = math.sqrt(dx * dx + dy * dy)
                local max_radius = cfg_number(self._cfg, "max_grind_radius", 300)
                if dist_from_anchor > max_radius then
                    self._log:debug(
                        "Frontier candidate rejected: %.0fm from anchor exceeds max_grind_radius %.0fm",
                        dist_from_anchor, max_radius
                    )
                    best = nil  -- reject; caller handles nil → idle
                end
            end
        end
    end

    return best
end

---@private
---@param goal table
---@param now number
---@return boolean
function ExplorationService:_activate_goal(goal, now)
    if type(goal) ~= "table" or not is_valid_position(goal.destination) then
        return false
    end

    local active = self._active
    if active and is_valid_position(active.destination) then
        local destination_delta = Helpers.distance_3d(active.destination, goal.destination)
        local min_switch_delta = math.max(0.1, cfg_number(self._cfg, "destination_switch_distance", 1.0))
        local min_switch_cooldown = math.max(0, cfg_number(self._cfg, "destination_switch_cooldown", 0.75))
        local min_switch_gain = cfg_number(self._cfg, "destination_switch_min_gain", 0.05)

        local same_mode = tostring(active.mode or "") == tostring(goal.mode or "")
        local can_switch = true

        if active.mode == "pursuit" and goal.mode ~= "pursuit" then
            local stale_timeout = math.max(0, cfg_number(self._cfg, "pursuit_stale_timeout", 1.5))
            local last_seen_at = tonumber(active.last_target_seen_at) or tonumber(active.created_at) or now
            can_switch = (now - last_seen_at) >= stale_timeout
        elseif same_mode then
            if destination_delta <= min_switch_delta then
                can_switch = false
            end
            if (now - (tonumber(active.last_switch_at) or 0)) < min_switch_cooldown then
                can_switch = false
            end
            if (tonumber(goal.score) or 0) < ((tonumber(active.score) or 0) + min_switch_gain) then
                can_switch = false
            end
        end

        if not can_switch then
            if goal.mode == "pursuit" and goal.target then
                active.target = goal.target
                active.score = tonumber(goal.score) or active.score
                active.distance = tonumber(goal.distance) or active.distance
                active.engage_radius = tonumber(goal.engage_radius) or active.engage_radius
                active.last_target_seen_at = now
                if destination_delta > min_switch_delta then
                    active.pending_destination = goal.destination
                else
                    active.pending_destination = nil
                end
            end
            return false
        end
    end

    self._log:info("exploration goal: %s score=%.2f", tostring(goal.mode), tonumber(goal.score) or 0)
    self._active = {
        mode = goal.mode,
        destination = goal.destination,
        pending_destination = nil,
        score = tonumber(goal.score) or 0,
        target = goal.target,
        distance = tonumber(goal.distance) or 0,
        engage_radius = tonumber(goal.engage_radius) or 0,
        cell_key = goal.cell_key,
        created_at = now,
        last_switch_at = now,
        last_move_to_at = 0,
        last_soft_repath_at = 0,
        last_error = nil,
        failure_count = 0,
        command_token = 0,
        last_target_seen_at = goal.mode == "pursuit" and now or 0,
    }
    return true
end

---@private
---@param active table
---@param now number
---@param ok boolean
---@param error_code string|nil
function ExplorationService:_on_command_result(active, now, ok, error_code)
    if self._active ~= active then
        return
    end

    if ok == true then
        active.last_error = nil
        return
    end

    local err = error_code or ErrorCodes.NAV_MOVE_FAILED
    active.last_error = err
    active.failure_count = (tonumber(active.failure_count) or 0) + 1

    local fail_cooldown = cfg_number(self._cfg, "cell_failure_cooldown", 8.0)
    local failure_ttl = fail_cooldown * Helpers.clamp(active.failure_count, 1, 4)
    if active.cell_key and self._cells[active.cell_key] then
        local cell = self._cells[active.cell_key]
        cell.fail_until = now + failure_ttl
        cell.failure_count = (tonumber(cell.failure_count) or 0) + 1
        cell.last_touched_at = now
    end

    if active.mode == "pursuit" and self._targeting and type(self._targeting.mark_target_failed) == "function" and active.target then
        self._targeting:mark_target_failed(active.target, err, failure_ttl)
    end

    if active.failure_count >= math.max(1, math.floor(cfg_number(self._cfg, "max_failures_before_reset", 2))) then
        self._active = nil
        -- Track consecutive goal-level failures for global backoff.
        self._nav_fail_streak = (self._nav_fail_streak or 0) + 1
        local streak_limit = math.max(1, math.floor(cfg_number(self._cfg, "nav_fail_streak_limit", 5)))
        if self._nav_fail_streak >= streak_limit then
            local backoff = math.max(5.0, cfg_number(self._cfg, "nav_fail_backoff_secs", 30.0))
            self._nav_backoff_until = now + backoff
            self._nav_fail_streak = 0
            self._log:warn("nav_fail_streak=" .. streak_limit .. " consecutive failures; pausing frontier for " .. backoff .. "s")
        end
    end
end

---@private
---@param active table
---@param now number
function ExplorationService:_issue_navigation(active, now)
    if not self._nav then
        return
    end

    local moving = nil
    if type(self._nav.is_moving) == "function" then
        moving = self._nav:is_moving()
    end

    local destination = active.destination
    if is_valid_position(active.pending_destination) then
        destination = active.pending_destination
    end

    if moving == true and type(self._nav.soft_repath) == "function" then
        local repath_cooldown = math.max(0.05, cfg_number(self._cfg, "soft_repath_cooldown", 0.45))
        local repath_delta = math.max(0.1, cfg_number(self._cfg, "soft_repath_distance", 1.0))
        local moved_distance = Helpers.distance_3d(active.destination, destination)

        -- Force immediate soft_repath for freshly activated goals that have never
        -- been navigated.  Without this, a new goal activated while NavClient is
        -- still moving to the OLD destination enters this branch but fails the
        -- moved_distance check (destination == active.destination → 0), causing the
        -- player to drift on stale waypoints until NavClient finishes → visible stop.
        local is_first_nav = (tonumber(active.command_token) or 0) == 0

        if is_first_nav or (moved_distance >= repath_delta and (now - (tonumber(active.last_soft_repath_at) or 0)) >= repath_cooldown) then
            active.last_soft_repath_at = now
            active.destination = destination
            active.pending_destination = nil
            active.command_token = (tonumber(active.command_token) or 0) + 1
            local token = active.command_token
            self._nav:soft_repath(destination, function(ok, error_code)
                if self._active ~= active or token ~= active.command_token then
                    return
                end
                self:_on_command_result(active, get_now(), ok == true, error_code)
            end)
        end
        return
    end

    local move_to_cooldown = math.max(0.05, cfg_number(self._cfg, "move_to_cooldown", 0.85))
    if (now - (tonumber(active.last_move_to_at) or 0)) < move_to_cooldown then
        return
    end

    active.last_move_to_at = now
    active.destination = destination
    active.pending_destination = nil
    active.command_token = (tonumber(active.command_token) or 0) + 1
    local token = active.command_token
    self._nav:move_to(destination, function(ok, error_code)
        if self._active ~= active or token ~= active.command_token then
            return
        end
        self:_on_command_result(active, get_now(), ok == true, error_code)
    end)
end

---@private
---@param mode string
---@param destination vec3|nil
---@param score number|nil
---@param error_code string|nil
function ExplorationService:_write_state(mode, destination, score, error_code)
    self._blackboard:set("exploration.active", mode ~= "idle")
    self._blackboard:set("exploration.mode", mode)
    if destination then
        self._blackboard:set("exploration.destination", {
            x = tonumber(destination.x) or 0,
            y = tonumber(destination.y) or 0,
            z = tonumber(destination.z) or 0,
        })
    else
        self._blackboard:clear("exploration.destination")
    end
    if score ~= nil then
        self._blackboard:set("exploration.score", tonumber(score) or 0)
    else
        self._blackboard:clear("exploration.score")
    end
    if error_code then
        self._blackboard:set("exploration.last_error", error_code)
    else
        self._blackboard:clear("exploration.last_error")
    end
end

---@private
---@param now number
---@param active table
---@param destination vec3
---@param player_pos vec3
function ExplorationService:_tick_active_goal(now, active, destination, player_pos)
    if active.mode == "pursuit" and active.target then
        local ok_v, valid = pcall(function() return active.target.is_valid and active.target:is_valid() end)
        local ok_d, dead = pcall(function() return active.target.is_dead and active.target:is_dead() end)
        if not ok_v then valid = false end
        if not ok_d then dead = false end
        if valid == false or dead == true then
            self._active = nil
            return
        end

        -- Live-track moving targets: update pending_destination from target's
        -- current position every tick so navigation follows the mob, not where
        -- it was when we selected it.
        local ok, live_pos = pcall(function() return active.target:get_position() end)
        if ok and is_valid_position(live_pos) then
            local live = {
                x = tonumber(live_pos.x) or 0,
                y = tonumber(live_pos.y) or 0,
                z = tonumber(live_pos.z) or 0,
            }
            local moved = Helpers.distance_3d(destination, live)
            if moved and moved > 0.5 then
                active.pending_destination = live
                destination = live
            end
        end
    end

    local arrive_distance = math.max(0.5, cfg_number(self._cfg, "arrive_distance", 6.5))
    if active.mode == "pursuit" then
        local engage_radius = tonumber(active.engage_radius) or 0
        if engage_radius > 0 then
            arrive_distance = math.max(0.5, engage_radius * 0.95)
        end
    end

    local dist = Helpers.distance_3d(player_pos, destination)
    active.distance = dist
    if dist <= arrive_distance then
        if active.cell_key and self._cells[active.cell_key] then
            local cell = self._cells[active.cell_key]
            cell.last_visited_at = now
            cell.last_touched_at = now
            self:_mark_recent_cell(active.cell_key)
        end
        self._active = nil
        -- Successful arrival resets the consecutive-failure streak.
        self._nav_fail_streak = 0
        return
    end

    self:_issue_navigation(active, now)
end

---@return boolean
---@return string|nil
function ExplorationService:tick()
    local now = get_now()
    self:_prune_cells(now)

    if not self:_is_enabled() then
        self._active = nil
        self:_write_state("idle", nil, nil, nil)
        return true, nil
    end

    if self._blackboard:get("player.in_combat", false) == true or self._blackboard:get("player.is_casting", false) == true then
        self._active = nil
        self:_write_state("idle", nil, nil, nil)
        return true, nil
    end

    local player_pos = self:_get_player_position()
    if not player_pos then
        self._active = nil
        self:_write_state("idle", nil, nil, ErrorCodes.TARGET_NOT_FOUND)
        return true, ErrorCodes.TARGET_NOT_FOUND
    end

    local anchor = self:_resolve_anchor(player_pos)
    self:_record_player_cell(now, player_pos)

    local engage_radius = 0
    if self._targeting and type(self._targeting.get_adaptive_radius) == "function" then
        engage_radius = tonumber(self._targeting:get_adaptive_radius()) or 0
    end
    engage_radius = math.max(1.0, engage_radius)

    local candidates = {}
    if self._targeting and type(self._targeting.get_visible_candidates) == "function" then
        local max_distance = engage_radius + math.max(0, cfg_number(self._cfg, "pursuit_extra_radius", 30.0))
        candidates = self._targeting:get_visible_candidates({
            max_distance = max_distance,
            include_blacklisted = false,
            player_pos = player_pos,
        })
    end
    self._blackboard:set("exploration.visible_candidates", type(candidates) == "table" and #candidates or 0)
    self:_record_candidate_cells(now, candidates)

    local goal = self:_select_pursuit(now, player_pos, engage_radius, candidates)
    if not goal then
        -- Global nav-failure backoff: skip frontier selection while in cooldown to
        -- prevent spamming 422 errors when the area has no navmesh coverage.
        if now >= (self._nav_backoff_until or 0) then
            goal = self:_select_frontier(now, player_pos, anchor)
        end
    end

    if not goal then
        self._active = nil
        self:_write_state("idle", nil, nil, nil)
        return true, nil
    end

    local changed = self:_activate_goal(goal, now)
    local active = self._active
    if not active then
        self:_write_state("idle", nil, nil, nil)
        return true, nil
    end

    local destination = active.destination
    if is_valid_position(active.pending_destination) then
        destination = active.pending_destination
    end

    if changed then
        self._event_bus:emit(Events.EXPLORATION_SELECTED, {
            mode = active.mode,
            destination = destination,
            score = tonumber(active.score) or 0,
            distance = tonumber(active.distance) or 0,
        })
    end

    self:_tick_active_goal(now, active, destination, player_pos)

    -- Seamless transition: if arrival cleared the active goal, immediately select
    -- and activate the next goal in the same tick to avoid a 1-frame stall where
    -- the player stands idle waiting for the next tick's goal selection.
    if not self._active then
        local next_goal = self:_select_pursuit(now, player_pos, engage_radius, candidates)
        if not next_goal and now >= (self._nav_backoff_until or 0) then
            next_goal = self:_select_frontier(now, player_pos, anchor)
        end
        if next_goal then
            -- Guard against pseudo-arrivals: only activate if the goal is far
            -- enough that the bot actually needs to move to reach it.
            local next_pos = next_goal.destination or next_goal.position
            local next_dist = next_pos and Helpers.distance_3d(player_pos, next_pos)
            local min_move = math.max(0.5, cfg_number(self._cfg, "arrive_distance", 6.5))
            if next_dist and next_dist > min_move then
                self:_activate_goal(next_goal, now)
                if self._active then
                    local next_dest = self._active.destination
                    if is_valid_position(self._active.pending_destination) then
                        next_dest = self._active.pending_destination
                    end
                    self._event_bus:emit(Events.EXPLORATION_SELECTED, {
                        mode = self._active.mode,
                        destination = next_dest,
                        score = tonumber(self._active.score) or 0,
                        distance = tonumber(self._active.distance) or 0,
                    })
                    self:_tick_active_goal(now, self._active, next_dest, player_pos)
                end
            end
        end
    end

    if self._active then
        local final_dest = self._active.destination
        if is_valid_position(self._active.pending_destination) then
            final_dest = self._active.pending_destination
        end
        self:_write_state(self._active.mode, final_dest, self._active.score, self._active.last_error)
    else
        self:_write_state("idle", nil, nil, nil)
    end

    return true, nil
end

---@return boolean
---@return string|nil
function ExplorationService:update()
    local active = self._active
    if not active then
        self._blackboard:set("exploration.active", false)
        return true, nil
    end

    local destination = active.destination
    if is_valid_position(active.pending_destination) then
        destination = active.pending_destination
    end
    self:_write_state(active.mode, destination, active.score, active.last_error)
    return true, nil
end

function ExplorationService:reset()
    -- Stop navigation so stale exploration paths don't persist after BT preemption
    if self._nav then
        local ok_m, moving = pcall(function() return self._nav:is_moving() end)
        if ok_m and moving == true and type(self._nav.stop) == "function" then
            pcall(self._nav.stop, self._nav)
        end
    end
    self._cells = {}
    self._recent_cells = {}
    self._active = nil
    self._last_frontier_phase = 0
    self._nav_fail_streak = 0
    self._nav_backoff_until = 0
    self:_write_state("idle", nil, nil, nil)
end

--- Build BT node for exploration (used by GrindService).
---@return table BT node
function ExplorationService:build()
    local bb = self._blackboard

    return BT.ReactiveSequence:new("explore", {
        -- Gate: nothing else to do
        BT.Condition:new("idle", function()
            if bb:get("player.in_combat", false) then
                -- Clean up stale exploration navigation so combat chase
                -- takes over immediately without fighting old waypoints.
                -- Stop nav regardless of self._active — exploration may have
                -- completed its goal but nav still following the last path.
                if self._nav then
                    local ok_m, moving = pcall(function() return self._nav:is_moving() end)
                    if ok_m and moving == true and type(self._nav.stop) == "function" then
                        pcall(self._nav.stop, self._nav)
                    end
                end
                self._active = nil
                bb:set("exploration.active", false)
                bb:clear("exploration.destination")
                return false
            end
            if bb:get("player.is_dead", false) then return false end
            if bb:get("player.is_ghost", false) then return false end
            local target = bb:get("combat.target")
            if target then
                local ok, hp = pcall(function() return target:get_health() end)
                if ok and hp and hp > 0 then return false end
            end
            return true
        end),

        -- Navigate to next waypoint
        BT.Action:new("explore_waypoint", function()
            local ok = pcall(function() self:tick() end)
            if not ok then return BTStatus.FAILURE end

            local dest = bb:get("exploration.destination")
            if dest then
                return BTStatus.RUNNING
            end

            return BTStatus.FAILURE
        end),
    })
end

return ExplorationService
