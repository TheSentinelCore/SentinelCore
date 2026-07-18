local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local CombatZoneDetector = require("modules/combat/combat_zone_detector")
local T = require("tests/test_util")

local M = {}

local function make_player()
    local p = {}
    function p:get_guid() return "player_guid" end
    function p:get_position() return { x = 0, y = 0, z = 0 } end
    function p:is_dead() return false end
    function p:is_friend_with() return true end
    return p
end

local function make_ally(opts)
    opts = opts or {}
    local u = {}
    function u:get_guid() return opts.guid or "ally" end
    function u:get_position() return opts.position or { x = 10, y = 0, z = 0 } end
    function u:is_dead() return false end
    function u:is_in_combat() return opts.in_combat == true end
    function u:is_mounted() return opts.mounted == true end
    function u:is_friend_with() return true end
    return u
end

local function make_enemy(opts)
    opts = opts or {}
    local u = {}
    function u:get_guid() return opts.guid or "enemy" end
    function u:get_position() return opts.position or { x = 10, y = 0, z = 0 } end
    function u:is_dead() return false end
    function u:is_in_combat() return true end
    function u:get_target() return opts.target end
    function u:is_enemy_with() return true end
    return u
end

function M.run()
    core = {}

    -- 1. Tier 0 with few allies
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local detector = CombatZoneDetector:new(bus, bb)
        local player = make_player()

        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...) return { make_ally({ guid = "a1" }) } end,
            get_enemy_list_around = function(self, pos, radius, ...) return {} end,
        }

        bb:set("bg.active", true)
        bb:set("system.now_ms", 0)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        detector:update(bb)

        T.assert_false(detector:is_combat_zone(), "should not be combat zone with < 2 allies")
        T.assert_equal(detector:get_tier(), 0, "tier should be 0 with few allies")
    end

    -- 2. Tier 2 when 40%+ in combat
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local detector = CombatZoneDetector:new(bus, bb)
        local player = make_player()

        local allies = {
            make_ally({ guid = "a1", in_combat = true }),
            make_ally({ guid = "a2", in_combat = true }),
            make_ally({ guid = "a3", in_combat = true }),
            make_ally({ guid = "a4", in_combat = false }),
            make_ally({ guid = "a5", in_combat = false }),
        }

        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...) return allies end,
            get_enemy_list_around = function(self, pos, radius, ...) return {} end,
        }

        bb:set("bg.active", true)
        bb:set("system.now_ms", 1000)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        detector:update(bb)

        T.assert_true(detector:is_combat_zone(), "should be combat zone with 60% in combat")
        T.assert_equal(detector:get_tier(), 2, "tier should be 2 when 40%+ in combat")
    end

    -- 3. Not tier 2 when too many mounted
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local detector = CombatZoneDetector:new(bus, bb)
        local player = make_player()

        local allies = {
            make_ally({ guid = "a1", in_combat = true, mounted = true }),
            make_ally({ guid = "a2", in_combat = true, mounted = true }),
            make_ally({ guid = "a3", in_combat = true, mounted = true }),
            make_ally({ guid = "a4", in_combat = false, mounted = false }),
            make_ally({ guid = "a5", in_combat = false, mounted = false }),
        }

        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...) return allies end,
            get_enemy_list_around = function(self, pos, radius, ...) return {} end,
        }

        bb:set("bg.active", true)
        bb:set("system.now_ms", 2000)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        detector:update(bb)

        T.assert_false(detector:is_combat_zone(), "should not be combat zone with 60% mounted")
        T.assert_equal(detector:get_tier(), 0, "tier should be 0 when mount ratio too high")
    end

    -- 4. Tier 3 direct threat
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local detector = CombatZoneDetector:new(bus, bb)
        local player = make_player()

        local friendly_target = make_ally({ guid = "friendly1", position = { x = 5, y = 0, z = 0 } })
        friendly_target.is_friend_with = function(self, other) return true end

        local threat_enemy = make_enemy({
            guid = "threat1",
            position = { x = 10, y = 0, z = 0 },
            target = friendly_target,
        })

        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...)
                return {
                    make_ally({ guid = "a1" }),
                    make_ally({ guid = "a2" }),
                }
            end,
            get_enemy_list_around = function(self, pos, radius, ...) return { threat_enemy } end,
        }

        bb:set("bg.active", true)
        bb:set("system.now_ms", 3000)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        detector:update(bb)

        T.assert_equal(detector:get_tier(), 3, "tier should be 3 with direct threat targeting friendly")
    end

    -- 5. Event on enter
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local detector = CombatZoneDetector:new(bus, bb)
        local player = make_player()

        local events_received = {}
        bus:subscribe("bg:combat_zone_entered", function(payload)
            events_received[#events_received + 1] = payload
        end)

        local allies = {
            make_ally({ guid = "a1", in_combat = true }),
            make_ally({ guid = "a2", in_combat = true }),
            make_ally({ guid = "a3", in_combat = true }),
        }

        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...) return allies end,
            get_enemy_list_around = function(self, pos, radius, ...) return {} end,
        }

        bb:set("bg.active", true)
        bb:set("system.now_ms", 4000)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        detector:update(bb)

        T.assert_true(#events_received >= 1, "bg:combat_zone_entered event should be published")
        T.assert_equal(events_received[1].tier, 2, "event should contain tier")
    end

    -- 6. Event on leave
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local detector = CombatZoneDetector:new(bus, bb)
        local player = make_player()

        local leave_events = {}
        bus:subscribe("bg:combat_zone_left", function(payload)
            leave_events[#leave_events + 1] = payload
        end)

        local combat_allies = {
            make_ally({ guid = "a1", in_combat = true }),
            make_ally({ guid = "a2", in_combat = true }),
            make_ally({ guid = "a3", in_combat = true }),
        }

        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...) return combat_allies end,
            get_enemy_list_around = function(self, pos, radius, ...) return {} end,
        }

        bb:set("bg.active", true)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        -- Enter combat zone
        bb:set("system.now_ms", 5000)
        detector:update(bb)
        T.assert_true(detector:is_combat_zone(), "should be in combat zone")

        -- Leave combat zone (no allies)
        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...) return {} end,
            get_enemy_list_around = function(self, pos, radius, ...) return {} end,
        }
        bb:set("system.now_ms", 6000)
        detector:update(bb)

        T.assert_true(#leave_events >= 1, "bg:combat_zone_left event should be published")
        T.assert_false(detector:is_combat_zone(), "should no longer be in combat zone")
    end

    -- 7. Not in BG returns tier 0
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local detector = CombatZoneDetector:new(bus, bb)
        local player = make_player()

        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...)
                return { make_ally({ guid = "a1", in_combat = true }), make_ally({ guid = "a2", in_combat = true }) }
            end,
            get_enemy_list_around = function(self, pos, radius, ...) return {} end,
        }

        bb:set("bg.active", false)
        bb:set("system.now_ms", 7000)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        detector:update(bb)

        T.assert_equal(detector:get_tier(), 0, "tier should be 0 when bg not active")
        T.assert_false(detector:is_combat_zone(), "should not be combat zone when bg not active")
    end

    -- 8. Throttle at 500ms
    do
        local bus = EventBus:new()
        local bb = Blackboard:new()
        local detector = CombatZoneDetector:new(bus, bb)
        local player = make_player()

        local call_count = 0
        local allies = {
            make_ally({ guid = "a1", in_combat = true }),
            make_ally({ guid = "a2", in_combat = true }),
            make_ally({ guid = "a3", in_combat = true }),
        }

        detector._unit_helper = {
            get_ally_list_around = function(self, pos, radius, ...)
                call_count = call_count + 1
                return allies
            end,
            get_enemy_list_around = function(self, pos, radius, ...) return {} end,
        }

        bb:set("bg.active", true)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        -- First call
        bb:set("system.now_ms", 8000)
        detector:update(bb)
        local first_count = call_count

        -- Second call within 500ms — should use cached result
        bb:set("system.now_ms", 8200)
        detector:update(bb)

        T.assert_equal(call_count, first_count, "second call within 500ms should use cached result, not re-scan")

        -- Verify blackboard still has values from cache
        T.assert_true(bb:get("bg.combat_zone"), "cached combat_zone should still be set")
        T.assert_equal(bb:get("bg.combat_zone_tier"), 2, "cached tier should still be set")
    end
end

return M
