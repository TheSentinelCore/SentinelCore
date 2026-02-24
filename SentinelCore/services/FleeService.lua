local BT = require("ai/BehaviorTree")
local S = BT.Status
local get_now = require("lib/TimeHelper").get_now

local FleeService = {}

function FleeService.build(bb, navigation)
    local flee_started = false
    local flee_started_at = nil

    return BT.ReactiveSequence:new("flee", {
        -- Gate: should flee (re-evaluated every tick)
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

        -- Flee action (navigate once away from enemies)
        BT.Action:new("flee_navigate", function()
            if flee_started then
                -- Timeout: don't flee forever (12s max)
                local now = get_now()
                if flee_started_at and (now - flee_started_at) > 12 then
                    flee_started = false
                    flee_started_at = nil
                    return S.FAILURE
                end
                return S.RUNNING
            end

            local player_pos = bb:get("player.position")
            local target = bb:get("combat.target")
            if player_pos and target and navigation then
                local ok, tpos = pcall(function() return target:get_position() end)
                if ok and tpos then
                    local dx = (player_pos.x or 0) - (tpos.x or 0)
                    local dy = (player_pos.y or 0) - (tpos.y or 0)
                    local len = math.sqrt(dx*dx + dy*dy)
                    if len > 0 then
                        dx, dy = dx / len, dy / len
                    else
                        -- Player on top of enemy; pick random escape direction
                        local angle = math.random() * 2 * math.pi
                        dx, dy = math.cos(angle), math.sin(angle)
                    end
                    local flee_pos = {
                        x = (player_pos.x or 0) + dx * 30,
                        y = (player_pos.y or 0) + dy * 30,
                        z = player_pos.z or 0,
                    }
                    flee_started = true
                    flee_started_at = get_now()
                    pcall(function() navigation:move_to(flee_pos) end)
                end
            end

            return S.RUNNING
        end),
    })
end

return FleeService
