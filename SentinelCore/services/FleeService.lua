local BT = require("ai/BehaviorTree")
local S = BT.Status
local get_now = require("lib/TimeHelper").get_now

local FleeService = {}

--- Returns positions of all visible units that can attack the player.
--- Used to compute the flee direction centroid so the bot moves away from
--- ALL nearby threats rather than just the primary combat target.
---@param player any game_object
---@return table[] list of vec3 positions
local function get_threat_positions(player)
    local positions = {}
    if not player or not core or not core.object_manager
        or not core.object_manager.get_visible_objects then
        return positions
    end
    local ok, objects = pcall(core.object_manager.get_visible_objects)
    if not ok or type(objects) ~= "table" then return positions end
    for i = 1, #objects do
        local unit = objects[i]
        if unit then
            local ok_v, valid   = pcall(function() return unit:is_valid() end)
            local ok_d, dead    = pcall(function() return unit:is_dead() end)
            local ok_a, can_atk = pcall(function() return unit:can_attack(player) end)
            if ok_v and valid and (not ok_d or not dead) and ok_a and can_atk then
                local ok_p, upos = pcall(function() return unit:get_position() end)
                if ok_p and upos then
                    positions[#positions + 1] = upos
                end
            end
        end
    end
    return positions
end

---@private
---@param player_pos vec3
---@param threats table[]
---@return vec3  A vector-based flee destination 30 yards away from threat centroid.
local function _compute_vector_flee_pos(player_pos, threats)
    local dx, dy = 0, 0
    if #threats > 0 then
        for i = 1, #threats do
            dx = dx + ((player_pos.x or 0) - (threats[i].x or 0))
            dy = dy + ((player_pos.y or 0) - (threats[i].y or 0))
        end
        dx = dx / #threats
        dy = dy / #threats
    end

    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then
        local angle = math.random() * 2 * math.pi
        dx, dy = math.cos(angle), math.sin(angle)
    else
        dx, dy = dx / len, dy / len
    end

    return {
        x = (player_pos.x or 0) + dx * 30,
        y = (player_pos.y or 0) + dy * 30,
        z = player_pos.z or 0,
    }
end

function FleeService.build(bb, navigation)
    local flee_started = false
    local flee_started_at = nil

    return BT.ReactiveSequence:new("flee", {
        -- Gate: should flee (re-evaluated every tick).
        -- combat.enemy_count is kept live by TargetingService:update() each frame,
        -- so this accurately reflects the current number of attackers.
        BT.Condition:new("should_flee", function()
            if not bb:get("player.in_combat", false) then
                flee_started = false
                flee_started_at = nil
                return false
            end
            local hp = bb:get("player.health", 0)
            local max_hp = bb:get("player.max_health", 1)
            local hp_pct = max_hp > 0 and (hp / max_hp) or 1
            local enemies = bb:get("combat.enemy_count", 0)
            return hp_pct < 0.20 and enemies >= 2
        end),

        -- Flee action: navigate away from centroid of all visible threats.
        -- D5: If navigation.get_flee_position is available, use the NavServer
        -- tactical flee endpoint for navmesh-aware escape paths. Falls back to
        -- the vector-based calculation if the server is unavailable or returns nil.
        BT.Action:new("flee_navigate", function()
            if flee_started then
                -- Timeout: don't flee forever (12s max).
                local now = get_now()
                if flee_started_at and (now - flee_started_at) > 12 then
                    flee_started = false
                    flee_started_at = nil
                    return S.FAILURE
                end
                return S.RUNNING
            end

            local player_pos = bb:get("player.position")
            if not player_pos or not navigation then
                return S.RUNNING
            end

            -- Collect threat positions.
            local player = bb:get("player.object")
            local threats = get_threat_positions(player)

            -- If no threats from object scan, fall back to primary combat target.
            if #threats == 0 then
                local target = bb:get("combat.target")
                if target then
                    local ok, tpos = pcall(function() return target:get_position() end)
                    if ok and tpos then
                        threats = { tpos }
                    end
                end
            end

            -- D5: Try NavServer tactical flee endpoint first.
            if type(navigation.get_flee_position) == "function" and #threats > 0 then
                navigation:get_flee_position(player_pos, threats, function(flee_pos)
                    if flee_pos and flee_pos.x ~= nil then
                        -- NavServer returned a navmesh-snapped flee path destination.
                        navigation:move_to(flee_pos, function(ok)
                            if not ok then
                                flee_started = false
                                flee_started_at = nil
                            end
                        end)
                    else
                        -- NavServer unavailable or no path: fall back to vector flee.
                        local fallback_pos = _compute_vector_flee_pos(player_pos, threats)
                        navigation:move_to(fallback_pos, function(ok)
                            if not ok then
                                flee_started = false
                                flee_started_at = nil
                            end
                        end)
                    end
                end)
                flee_started = true
                flee_started_at = get_now()
                return S.RUNNING
            end

            -- Fallback (no get_flee_position available): vector-based flee.
            local flee_pos
            if #threats > 0 then
                flee_pos = _compute_vector_flee_pos(player_pos, threats)
            else
                -- No threats at all: pick a random direction.
                local angle = math.random() * 2 * math.pi
                flee_pos = {
                    x = (player_pos.x or 0) + math.cos(angle) * 30,
                    y = (player_pos.y or 0) + math.sin(angle) * 30,
                    z = player_pos.z or 0,
                }
            end

            -- Issue navigation with a callback so a nav failure cancels the flee
            -- state immediately rather than waiting out the full 12s timeout.
            navigation:move_to(flee_pos, function(ok)
                if not ok then
                    flee_started = false
                    flee_started_at = nil
                end
            end)
            flee_started = true
            flee_started_at = get_now()

            return S.RUNNING
        end),
    })
end

return FleeService
