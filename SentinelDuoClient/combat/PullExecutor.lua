-- PullExecutor.lua — Manages the pull running phase for the puller.
-- Per design doc §7.2.

local helpers     = require("lib/helpers")
local unit_helper = require("common/izi_sdk")

---@class PullExecutor
local PullExecutor = {}
PullExecutor.__index = PullExecutor

local AGGRO_RADIUS     = 40.0  -- yards to scan for enemies while running
local TAG_RANGE        = 30.0  -- yards — cast tag spell within
local MIN_CAST_GAP_MS  = 200

---@param duo_nav      table  DuoNav
---@param spell_catalog table SpellCatalog
---@param blackboard   table  Blackboard
---@return PullExecutor
function PullExecutor:new(duo_nav, spell_catalog, blackboard)
    return setmetatable({
        _nav    = duo_nav,
        _sc     = spell_catalog,
        _bb     = blackboard,
        _pull   = nil,
        _wp_idx = 1,
        _last_cast_ms = 0,
        _mob_count    = 0,
    }, PullExecutor)
end

---@param pull_def table  pull definition from profile
function PullExecutor:start(pull_def)
    self._pull      = pull_def
    self._wp_idx    = 1
    self._mob_count = 0
    self._bb:set("duo.mob_count_in_pack", 0)

    -- Navigate to first waypoint
    if type(pull_def.pull_path) == "table" and #pull_def.pull_path > 0 then
        self._nav:move_to(pull_def.pull_path[1])
    end
end

local function get_enemies_around(pos, radius)
    local ok, list = pcall(unit_helper.get_enemy_list_around, unit_helper, pos, radius, false, false)
    if ok and type(list) == "table" then return list end
    return {}
end

local function nearest_enemy(enemies, player_pos)
    local best, best_dist = nil, math.huge
    for _, e in ipairs(enemies) do
        local ok, ep = pcall(e.get_position, e)
        if ok and ep then
            local dx = (ep.x or 0) - (player_pos.x or 0)
            local dy = (ep.y or 0) - (player_pos.y or 0)
            local dz = (ep.z or 0) - (player_pos.z or 0)
            local d  = math.sqrt(dx*dx + dy*dy + dz*dz)
            if d < best_dist then best, best_dist = e, d end
        end
    end
    return best, best_dist
end

--- Returns "running" | "ib_time" | "abort" | "error"
---@param player       table   game_object
---@param game_time_ms number
---@return string
function PullExecutor:tick(player, game_time_ms)
    if not self._pull then return "error" end
    if not player then return "error" end

    local pull      = self._pull
    local path      = pull.pull_path or {}
    local timing    = pull.timing or {}
    local avoid_ids = pull.mob_ids_avoid or {}

    -- Get player position
    local ok_pos, player_pos = pcall(player.get_position, player)
    if not ok_pos or not player_pos then return "running" end

    -- Advance waypoint on arrival
    local current_wp = path[self._wp_idx]
    if current_wp and self._nav:is_arrived(5.0) then
        self._wp_idx = self._wp_idx + 1
        local next_wp = path[self._wp_idx]
        if next_wp then
            self._nav:move_to(next_wp)
        end
    end

    -- Scan enemies
    local enemies   = get_enemies_around(player_pos, AGGRO_RADIUS)
    local filtered  = {}
    local avoid_set = {}
    for _, id in ipairs(avoid_ids) do avoid_set[id] = true end

    for _, e in ipairs(enemies) do
        local ok_id, npc_id = pcall(e.get_npc_id, e)
        if not (ok_id and avoid_set[npc_id]) then
            table.insert(filtered, e)
        end
    end

    self._mob_count = #filtered
    self._bb:set("duo.mob_count_in_pack", self._mob_count)

    -- Tag nearest mob — skip if already casting (Frostbolt is 3.5s; re-casting
    -- every 200ms would interrupt the in-progress cast before it completes).
    local is_casting = self._bb:get("player.is_casting", false)
    if game_time_ms - self._last_cast_ms >= MIN_CAST_GAP_MS and #filtered > 0 and not is_casting then
        local target, dist = nearest_enemy(filtered, player_pos)
        if target and dist <= TAG_RANGE then
            local tag_id = self._sc:resolve("Frostbolt", player)
            if tag_id then
                -- Target the enemy
                pcall(core.input.set_target, target)
                pcall(core.input.cast_target_spell, tag_id, target)
                self._last_cast_ms = game_time_ms
            end
        end
    end

    -- Check transition conditions
    local pull_to_ib_count = timing.pull_to_ib_mob_count or 3
    if self._mob_count >= pull_to_ib_count then
        helpers.log("[Pull] mob count " .. self._mob_count .. " >= " .. pull_to_ib_count .. " → ib_time")
        return "ib_time"
    end

    -- At end of path with too few mobs
    if self._wp_idx > #path then
        local min_expected = pull.expected_mob_count_min or 2
        if self._mob_count < min_expected then
            helpers.log_warn("[Pull] end of path with only " .. self._mob_count .. " mobs → abort")
            return "abort"
        end
        return "ib_time"
    end

    return "running"
end

return PullExecutor
