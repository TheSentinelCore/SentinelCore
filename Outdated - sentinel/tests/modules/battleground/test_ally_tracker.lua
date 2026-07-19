local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local AllyTracker = require("modules/battleground/ally_tracker")
local T = require("tests/test_util")

local M = {}

local function make_ally(opts)
    opts = opts or {}
    local u = {}
    function u:get_guid() return opts.guid or "ally" end
    function u:get_position() return opts.position or { x = 10, y = 0, z = 0 } end
    function u:is_dead() return opts.dead == true end
    function u:is_friend_with() return true end
    function u:get_group_role() return opts.role or 0 end
    function u:is_player() return true end
    function u:is_in_combat() return opts.in_combat == true end
    function u:is_mounted() return false end
    return u
end

local function make_player()
    local p = {}
    function p:get_guid() return "player_guid" end
    function p:get_position() return { x = 0, y = 0, z = 0 } end
    function p:is_dead() return false end
    function p:is_friend_with() return true end
    function p:get_group_role() return 0 end
    function p:is_player() return true end
    return p
end

function M.run()
    core = { time = function() return 0 end }

    -- 1. Healer scored higher
    do
        local bb = Blackboard:new()
        local bus = EventBus:new()
        local mock_humanization = {
            jitter_point = function(self, pos, amount) return pos end,
            is_ready = function() return true end,
        }
        local tracker = AllyTracker:new(bus, bb, mock_humanization)
        local player = make_player()

        local healer = make_ally({ guid = "healer1", position = { x = 10, y = 0, z = 0 }, role = 1 })
        local dps = make_ally({ guid = "dps1", position = { x = 10, y = 0, z = 0 }, role = 0 })

        tracker._scan_allies = function() return { healer, dps } end
        tracker._scan_enemies = function() return {} end

        bb:set("bg.active", true)
        bb:set("system.now_ms", 0)
        bb:set("player.object", player)
        bb:set("player.position", { x = 0, y = 0, z = 0 })

        tracker:update(bb)

        T.assert_equal(bb:get("bg.follow_target_guid"), "healer1", "healer should be selected as follow target")
    end

    -- 2. Closer ally preferred when equal role
    do
        local bb = Blackboard:new()
        local bus = EventBus:new()
        local mock_humanization = {
            jitter_point = function(self, pos, amount) return pos end,
            is_ready = function() return true end,
        }
        local tracker = AllyTracker:new(bus, bb, mock_humanization)
        local player = make_player()

        local close_dps = make_ally({ guid = "close_dps", position = { x = 10, y = 0, z = 0 }, role = 0 })
        local far_dps = make_ally({ guid = "far_dps", position = { x = 40, y = 0, z = 0 }, role = 0 })

        tracker._scan_allies = function() return { close_dps, far_dps } end
        tracker._scan_enemies = function() return {} end

        bb:set("bg.active", true)
        bb:set("system.now_ms", 0)
        bb:set("player.object", player)
        bb:set("player.position", { x = 0, y = 0, z = 0 })

        tracker:update(bb)

        T.assert_equal(bb:get("bg.follow_target_guid"), "close_dps", "closer ally should be preferred")
    end

    -- 3. Idle blacklist after 7s
    do
        local bb = Blackboard:new()
        local bus = EventBus:new()
        local mock_humanization = {
            jitter_point = function(self, pos, amount) return pos end,
            is_ready = function() return true end,
        }
        local tracker = AllyTracker:new(bus, bb, mock_humanization)
        local player = make_player()

        local idle_ally = make_ally({ guid = "idle1", position = { x = 10, y = 0, z = 0 } })

        tracker._scan_allies = function() return { idle_ally } end
        tracker._scan_enemies = function() return {} end

        bb:set("bg.active", true)
        bb:set("player.object", player)
        bb:set("player.position", { x = 0, y = 0, z = 0 })

        -- First update at time 0 — records position, selects ally
        bb:set("system.now_ms", 0)
        tracker:update(bb)
        T.assert_equal(bb:get("bg.follow_target_guid"), "idle1", "ally should be selected initially")

        -- Second update at time 1000 — same position, starts idle tracking
        -- Need to expire cache first (cache_duration_ms = 4000)
        bb:set("system.now_ms", 5000)
        tracker:update(bb)

        -- Third update at time 8000 — idle for >7000ms, should be blacklisted
        -- The idle entry was created at the second update (5000ms), so we need 5000+7000=12000
        bb:set("system.now_ms", 13000)
        tracker:update(bb)

        T.assert_equal(bb:get("bg.follow_target_guid"), nil, "idle ally should be blacklisted after 7s")
    end

    -- 4. Blacklist removal on movement
    do
        local bb = Blackboard:new()
        local bus = EventBus:new()
        local mock_humanization = {
            jitter_point = function(self, pos, amount) return pos end,
            is_ready = function() return true end,
        }
        local tracker = AllyTracker:new(bus, bb, mock_humanization)
        local player = make_player()

        local moving_pos = { x = 10, y = 0, z = 0 }
        local moving_ally = {
            get_guid = function() return "mover1" end,
            get_position = function() return moving_pos end,
            is_dead = function() return false end,
            is_friend_with = function() return true end,
            get_group_role = function() return 0 end,
            is_player = function() return true end,
            is_in_combat = function() return false end,
            is_mounted = function() return false end,
        }

        tracker._scan_allies = function() return { moving_ally } end
        tracker._scan_enemies = function() return {} end

        bb:set("bg.active", true)
        bb:set("player.object", player)
        bb:set("player.position", { x = 0, y = 0, z = 0 })

        -- Record initial position
        bb:set("system.now_ms", 0)
        tracker:update(bb)

        -- Same position — starts idle tracking
        bb:set("system.now_ms", 5000)
        tracker:update(bb)

        -- Still same position, past idle threshold
        bb:set("system.now_ms", 13000)
        tracker:update(bb)
        T.assert_equal(bb:get("bg.follow_target_guid"), nil, "should be blacklisted")

        -- Move to new position — should clear blacklist
        moving_pos = { x = 20, y = 0, z = 0 }
        bb:set("system.now_ms", 18000)
        tracker:update(bb)
        T.assert_equal(bb:get("bg.follow_target_guid"), "mover1", "blacklist should clear on movement")
    end

    -- 5. Cache persists for 4s
    do
        local bb = Blackboard:new()
        local bus = EventBus:new()
        local mock_humanization = {
            jitter_point = function(self, pos, amount) return pos end,
            is_ready = function() return true end,
        }
        local tracker = AllyTracker:new(bus, bb, mock_humanization)
        local player = make_player()

        local ally_a = make_ally({ guid = "ally_a", position = { x = 20, y = 0, z = 0 }, role = 0 })
        local ally_b = make_ally({ guid = "ally_b", position = { x = 5, y = 0, z = 0 }, role = 1 })

        -- Start with only ally_a
        tracker._scan_allies = function() return { ally_a } end
        tracker._scan_enemies = function() return {} end

        bb:set("bg.active", true)
        bb:set("player.object", player)
        bb:set("player.position", { x = 0, y = 0, z = 0 })

        bb:set("system.now_ms", 0)
        tracker:update(bb)
        T.assert_equal(bb:get("bg.follow_target_guid"), "ally_a", "should select ally_a initially")

        -- Add better ally_b, but within cache window (2000ms < 4000ms cache)
        tracker._scan_allies = function() return { ally_a, ally_b } end
        bb:set("system.now_ms", 2000)
        tracker:update(bb)
        T.assert_equal(bb:get("bg.follow_target_guid"), "ally_a", "cache should keep ally_a for 4s")
    end

    -- 6. Cache expires after 4s
    do
        local bb = Blackboard:new()
        local bus = EventBus:new()
        local mock_humanization = {
            jitter_point = function(self, pos, amount) return pos end,
            is_ready = function() return true end,
        }
        local tracker = AllyTracker:new(bus, bb, mock_humanization)
        local player = make_player()

        local ally_a = make_ally({ guid = "ally_a2", position = { x = 20, y = 0, z = 0 }, role = 0 })
        local ally_b = make_ally({ guid = "ally_b2", position = { x = 5, y = 0, z = 0 }, role = 1 })

        tracker._scan_allies = function() return { ally_a } end
        tracker._scan_enemies = function() return {} end

        bb:set("bg.active", true)
        bb:set("player.object", player)
        bb:set("player.position", { x = 0, y = 0, z = 0 })

        bb:set("system.now_ms", 0)
        tracker:update(bb)
        T.assert_equal(bb:get("bg.follow_target_guid"), "ally_a2", "should select ally_a initially")

        -- After cache expires, better ally_b should be selected
        tracker._scan_allies = function() return { ally_a, ally_b } end
        bb:set("system.now_ms", 5000)
        tracker:update(bb)
        T.assert_equal(bb:get("bg.follow_target_guid"), "ally_b2", "healer ally_b should be selected after cache expires")
    end

    -- 7. No allies returns nil
    do
        local bb = Blackboard:new()
        local bus = EventBus:new()
        local mock_humanization = {
            jitter_point = function(self, pos, amount) return pos end,
            is_ready = function() return true end,
        }
        local tracker = AllyTracker:new(bus, bb, mock_humanization)
        local player = make_player()

        tracker._scan_allies = function() return {} end
        tracker._scan_enemies = function() return {} end

        bb:set("bg.active", true)
        bb:set("system.now_ms", 0)
        bb:set("player.object", player)
        bb:set("player.position", { x = 0, y = 0, z = 0 })

        tracker:update(bb)
        T.assert_equal(bb:get("bg.follow_target_guid"), nil, "no allies should yield nil follow target")
        T.assert_equal(bb:get("bg.follow_target"), nil, "no allies should yield nil follow target object")
    end

    -- 8. Event published on target change
    do
        local bb = Blackboard:new()
        local bus = EventBus:new()
        local mock_humanization = {
            jitter_point = function(self, pos, amount) return pos end,
            is_ready = function() return true end,
        }
        local tracker = AllyTracker:new(bus, bb, mock_humanization)
        local player = make_player()

        local events_received = {}
        bus:subscribe("bg:follow_target_changed", function(payload)
            events_received[#events_received + 1] = payload
        end)

        local ally_a = make_ally({ guid = "evt_a", position = { x = 10, y = 0, z = 0 } })
        local ally_b = make_ally({ guid = "evt_b", position = { x = 10, y = 0, z = 0 } })

        tracker._scan_allies = function() return { ally_a } end
        tracker._scan_enemies = function() return {} end

        bb:set("bg.active", true)
        bb:set("player.object", player)
        bb:set("player.position", { x = 0, y = 0, z = 0 })

        -- Select ally_a
        bb:set("system.now_ms", 0)
        tracker:update(bb)
        T.assert_true(#events_received >= 1, "event should be published on initial target selection")
        T.assert_equal(events_received[#events_received].new_guid, "evt_a", "event should contain new guid")

        -- Switch to ally_b after cache expires
        tracker._scan_allies = function() return { ally_b } end
        bb:set("system.now_ms", 5000)
        tracker:update(bb)
        T.assert_true(#events_received >= 2, "event should be published on target change")
        T.assert_equal(events_received[#events_received].new_guid, "evt_b", "event should contain new guid after change")
    end
end

return M
