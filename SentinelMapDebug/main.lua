local PREFIX = "[MapDebug] "
local last_log_time = 0
local LOG_INTERVAL = 2.0

-------------------------------------------------------------------------------
-- MDT coordinate transform verification
--
-- MDT stores enemy positions as pixel offsets on an 840x555 canvas.
-- Hypothesis: normalized = { x = mdt_x / 840, y = (-mdt_y) / 555 }
-- Then core.game_ui.get_world_pos_from_map_pos(uiMapId, normalized) -> world XY.
--
-- Multi-floor: try ALL zone UiMapIDs for each point, log which gives closest.
-------------------------------------------------------------------------------
local MDT_CANVAS_W = 840
local MDT_CANVAS_H = 555

-- Windrunner Spire: instance_id=2805, zones={ 2492, 2493, 2494, 2496, 2497, 2498, 2499 }
local WS_ZONES = { 2492, 2493, 2494, 2496, 2497, 2498, 2499 }
local WS_ZONE_SET = {}
for _, z in ipairs(WS_ZONES) do WS_ZONE_SET[z] = true end

local WS_POINTS = {
    { name = "Emberdawn (Boss)",      mdt_x = 651.167, mdt_y = -146.649 },
    { name = "Kalis (Boss)",          mdt_x = 285.656, mdt_y = -507.041 },
    { name = "Latch (Boss)",          mdt_x = 321.035, mdt_y = -506.544 },
    { name = "Restless Heart (Boss)", mdt_x = 680.894, mdt_y = -304.656 },
    { name = "Restless Steward",      mdt_x = 86.933,  mdt_y = -154.120 },
}

--- Convert a single MDT coordinate to world position.
local function mdt_to_world(ui_map_id, mdt_x, mdt_y)
    local normalized = { x = mdt_x / MDT_CANVAS_W, y = (-mdt_y) / MDT_CANVAS_H }
    local ok, result = pcall(core.game_ui.get_world_pos_from_map_pos, ui_map_id, normalized)
    if ok and result then
        return result
    end
    return nil
end

--- Convert the player's current world pos BACK to MDT coords for comparison.
local function world_to_mdt(world_pos)
    local ok, norm = pcall(core.game_ui.world_pos_to_map_pos_normalized, world_pos)
    if ok and norm then
        return norm.x * MDT_CANVAS_W, -(norm.y * MDT_CANVAS_H)
    end
    return nil, nil
end

local mdt_log_time = 0
local MDT_LOG_INTERVAL = 5.0

local function run_mdt_verification()
    local ui_map_id = core.get_map_id()
    if not WS_ZONE_SET[ui_map_id] then return end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end
    local player_pos = player:get_position()

    local now = core.time()
    if now - mdt_log_time < MDT_LOG_INTERVAL then return end
    mdt_log_time = now

    -- Log player's position in MDT coords
    local pmx, pmy = world_to_mdt(player_pos)
    if pmx then
        core.log(string.format("%sUiMap=%d | Player MDT=(%.1f, %.1f) World=(%.1f, %.1f, %.1f)",
            PREFIX, ui_map_id, pmx, pmy, player_pos.x, player_pos.y, player_pos.z))
    end

    -- For each test point, try ALL zone UiMapIDs and report best match
    for _, pt in ipairs(WS_POINTS) do
        local best_zone, best_dist, best_wx, best_wy = nil, math.huge, 0, 0
        local results = {}
        for _, zone_id in ipairs(WS_ZONES) do
            local world_xy = mdt_to_world(zone_id, pt.mdt_x, pt.mdt_y)
            if world_xy then
                local dx = world_xy.x - player_pos.x
                local dy = world_xy.y - player_pos.y
                local dist = math.sqrt(dx * dx + dy * dy)
                results[#results + 1] = string.format("%d:(%.0f,%.0f)=%.0f", zone_id, world_xy.x, world_xy.y, dist)
                if dist < best_dist then
                    best_zone, best_dist, best_wx, best_wy = zone_id, dist, world_xy.x, world_xy.y
                end
            end
        end
        -- Log best match + all zone results
        core.log(string.format("%s  %s: BEST zone=%d dist=%.1f World=(%.1f,%.1f) | %s",
            PREFIX, pt.name, best_zone or 0, best_dist, best_wx, best_wy,
            table.concat(results, " ")))
    end
end

-------------------------------------------------------------------------------
-- Main update loop
-------------------------------------------------------------------------------
core.register_on_update_callback(function()
    local now = core.time()

    local ok, err = pcall(run_mdt_verification)
    if not ok and err then
        core.log(PREFIX .. "MDT verify error: " .. tostring(err))
    end

    if now - last_log_time < LOG_INTERVAL then return end
    last_log_time = now

    local instance_id = core.get_instance_id()
    local map_id = core.get_map_id()
    local map_name = core.get_map_name()

    local player = core.object_manager.get_local_player()
    local pos_str = ""
    if player and player:is_valid() then
        local pos = player:get_position()
        pos_str = string.format("  pos=(%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z)
    end

    local msg = string.format("instance_id=%s  map_id=%s  name=%s%s",
        tostring(instance_id), tostring(map_id), tostring(map_name), pos_str)

    core.log(PREFIX .. msg)
end)
