local MountController = require("modules/grind/mount_controller")
local T = require("tests/test_util")

local M = {}

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function make_bb(overrides)
    local data = {
        ["combat.source"]    = nil,
        ["player.is_outdoors"] = true,
        ["player.is_dead"]   = false,
        ["player.is_ghost"]  = false,
    }
    if overrides then
        for k, v in pairs(overrides) do data[k] = v end
    end
    return {
        get = function(_, key, default)
            local v = data[key]
            if v == nil then return default end
            return v
        end,
        set = function(_, key, value)
            data[key] = value
        end,
    }
end

local function mock_player(opts)
    opts = opts or {}
    return {
        get_position = function()
            return { x = opts.x or 0, y = opts.y or 0, z = opts.z or 0 }
        end,
        is_mounted = function() return opts.mounted or false end,
        is_alive   = function() return opts.alive ~= false end,
        is_enemy_with = function(_, target) return true end,
    }
end

local function mock_hostile(opts)
    opts = opts or {}
    return {
        get_position = function()
            return { x = opts.x or 0, y = opts.y or 0, z = opts.z or 0 }
        end,
        get_target = function() return opts.target end,
        is_alive   = function() return opts.alive ~= false end,
    }
end

-- ---------------------------------------------------------------------------
-- tests
-- ---------------------------------------------------------------------------

function M.run()
    -- -----------------------------------------------------------------------
    -- should_mount: true when all conditions met
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0 })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        local dest = { x = 100, y = 0, z = 0 }  -- 100yd away
        T.assert_true(ctrl:should_mount(bb, dest),
            "should_mount true when all conditions met (long distance, outdoor, no combat)")
    end

    -- -----------------------------------------------------------------------
    -- should_mount: false when distance < threshold
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0 })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        local dest = { x = 10, y = 0, z = 0 }  -- 10yd < 40yd threshold
        T.assert_false(ctrl:should_mount(bb, dest),
            "should_mount false when distance < threshold")
    end

    -- -----------------------------------------------------------------------
    -- should_mount: false when in combat
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb({ ["combat.source"] = "some_mob" })
        local player = mock_player({ x = 0, y = 0, z = 0 })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        local dest = { x = 100, y = 0, z = 0 }
        T.assert_false(ctrl:should_mount(bb, dest),
            "should_mount false when in combat")
    end

    -- -----------------------------------------------------------------------
    -- should_mount: false when indoors
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb({ ["player.is_outdoors"] = false })
        local player = mock_player({ x = 0, y = 0, z = 0 })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        local dest = { x = 100, y = 0, z = 0 }
        T.assert_false(ctrl:should_mount(bb, dest),
            "should_mount false when indoors")
    end

    -- -----------------------------------------------------------------------
    -- should_mount: false when already mounted
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ mounted = true })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        local dest = { x = 100, y = 0, z = 0 }
        T.assert_false(ctrl:should_mount(bb, dest),
            "should_mount false when already mounted")
    end

    -- -----------------------------------------------------------------------
    -- should_mount: false when dead
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb({ ["player.is_dead"] = true })
        local player = mock_player({ alive = false })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        local dest = { x = 100, y = 0, z = 0 }
        T.assert_false(ctrl:should_mount(bb, dest),
            "should_mount false when dead")
    end

    -- -----------------------------------------------------------------------
    -- should_mount: false when ghost
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb({ ["player.is_ghost"] = true })
        local player = mock_player()
        bb:set("player.object", player)
        local ctrl = MountController:new()
        local dest = { x = 100, y = 0, z = 0 }
        T.assert_false(ctrl:should_mount(bb, dest),
            "should_mount false when ghost")
    end

    -- -----------------------------------------------------------------------
    -- should_dismount: true when near destination
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0, mounted = true })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        ctrl._destination = { x = 20, y = 0, z = 0 }  -- 20yd < 30yd threshold
        T.assert_true(ctrl:should_dismount(bb),
            "should_dismount true when near destination")
    end

    -- -----------------------------------------------------------------------
    -- should_dismount: true when combat starts
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb({ ["combat.source"] = "aggro_mob" })
        local player = mock_player({ x = 0, y = 0, z = 0, mounted = true })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        ctrl._destination = { x = 100, y = 0, z = 0 }  -- far from dest
        T.assert_true(ctrl:should_dismount(bb),
            "should_dismount true when combat starts")
    end

    -- -----------------------------------------------------------------------
    -- should_dismount: false when far from dest and no combat
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0, mounted = true })
        bb:set("player.object", player)
        local ctrl = MountController:new()
        ctrl._destination = { x = 100, y = 0, z = 0 }
        T.assert_false(ctrl:should_dismount(bb),
            "should_dismount false when far from destination and no combat")
    end

    -- -----------------------------------------------------------------------
    -- should_smart_dismount: true when hostile targets player
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0, mounted = true })
        bb:set("player.object", player)

        local hostile = mock_hostile({ x = 20, y = 0, z = 0, target = player })
        local ctrl = MountController:new()
        T.assert_true(ctrl:should_smart_dismount(bb, { hostile }),
            "should_smart_dismount true when hostile targets player")
    end

    -- -----------------------------------------------------------------------
    -- should_smart_dismount: false when no hostile targets player
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0, mounted = true })
        bb:set("player.object", player)

        local other_target = mock_player({ x = 50, y = 50, z = 0 })
        local hostile = mock_hostile({ x = 20, y = 0, z = 0, target = other_target })
        local ctrl = MountController:new()
        T.assert_false(ctrl:should_smart_dismount(bb, { hostile }),
            "should_smart_dismount false when hostile targets someone else")
    end

    -- -----------------------------------------------------------------------
    -- should_smart_dismount: false when hostile is too far
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0, mounted = true })
        bb:set("player.object", player)

        local hostile = mock_hostile({ x = 100, y = 0, z = 0, target = player })
        local ctrl = MountController:new()
        T.assert_false(ctrl:should_smart_dismount(bb, { hostile }),
            "should_smart_dismount false when hostile is outside scan radius")
    end

    -- -----------------------------------------------------------------------
    -- should_smart_dismount: false when not mounted
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0, mounted = false })
        bb:set("player.object", player)

        local hostile = mock_hostile({ x = 20, y = 0, z = 0, target = player })
        local ctrl = MountController:new()
        T.assert_false(ctrl:should_smart_dismount(bb, { hostile }),
            "should_smart_dismount false when not mounted")
    end

    -- -----------------------------------------------------------------------
    -- begin_travel stores destination and sets mounting state
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        -- Stub core globals for begin_travel
        local old_core = _G.core
        _G.core = {
            spell_book = {
                get_mount_count = function() return 1 end,
                get_mount_info  = function(i)
                    return {
                        mount_name = "Test Horse",
                        spell_id   = 12345,
                        mount_id   = 1,
                        is_active  = false,
                        is_usable  = true,
                        mount_type = 1,
                    }
                end,
            },
            input = {
                mount = function(idx) return true end,
            },
        }

        local ctrl = MountController:new()
        local dest = { x = 100, y = 0, z = 0 }
        ctrl:begin_travel(bb, dest)
        T.assert_true(ctrl:is_mounting(), "is_mounting true after begin_travel")
        T.assert_equal(ctrl._destination.x, 100, "destination stored after begin_travel")

        _G.core = old_core
    end

    -- -----------------------------------------------------------------------
    -- begin_travel does not mount when should_mount is false
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb({ ["combat.source"] = "mob" })
        local player = mock_player({ x = 0, y = 0, z = 0 })
        bb:set("player.object", player)

        local ctrl = MountController:new()
        local dest = { x = 100, y = 0, z = 0 }
        ctrl:begin_travel(bb, dest)
        T.assert_false(ctrl:is_mounting(), "is_mounting false when conditions not met")
    end

    -- -----------------------------------------------------------------------
    -- clear resets state
    -- -----------------------------------------------------------------------
    do
        local ctrl = MountController:new()
        ctrl._mounting = true
        ctrl._destination = { x = 50, y = 0, z = 0 }
        ctrl:clear()
        T.assert_false(ctrl:is_mounting(), "is_mounting false after clear")
        T.assert_true(ctrl._destination == nil, "destination nil after clear")
    end

    -- -----------------------------------------------------------------------
    -- update triggers dismount when should_dismount is true
    -- -----------------------------------------------------------------------
    do
        local bb = make_bb()
        local player = mock_player({ x = 0, y = 0, z = 0, mounted = true })
        bb:set("player.object", player)

        local dismount_called = false
        local old_core = _G.core
        _G.core = {
            input = {
                dismount = function() dismount_called = true; return true end,
            },
        }

        local ctrl = MountController:new()
        ctrl._destination = { x = 10, y = 0, z = 0 }  -- 10yd < 30yd
        ctrl._mounting = true
        ctrl:update(bb)
        T.assert_true(dismount_called, "dismount called when near destination")
        T.assert_false(ctrl:is_mounting(), "is_mounting false after dismount")

        _G.core = old_core
    end
end

return M
