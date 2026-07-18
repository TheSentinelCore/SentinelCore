local T = require("tests/test_util")
local ObjectiveInteractor = require("modules/battleground/objective_interactor")

local M = {}

local function make_blackboard(overrides)
    local data = overrides or {}
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

local function make_event_bus()
    local published = {}
    return {
        publish = function(_, event, payload)
            published[#published + 1] = { event = event, payload = payload }
        end,
        published = published,
    }
end

local function make_humanization(ready)
    return {
        is_ready = function() return ready ~= false end,
    }
end

local function make_objective(id, obj_type, x, y, z, owner_map)
    return {
        id = id,
        type = obj_type,
        x = x or 100,
        y = y or 200,
        z = z or 50,
        owner_map = owner_map or {},
    }
end

local function make_game_object(entry_id, pos, usable)
    return {
        get_entry = function() return entry_id end,
        get_position = function() return pos end,
        can_be_used = function() return usable ~= false end,
        get_type = function() return "gameobject" end,
    }
end

local function setup_core(objects)
    _G.core = {
        object_manager = {
            get_visible_objects = function() return objects or {} end,
        },
        input = {
            use_object = function() return nil end,
        },
    }
end

function M.run()
    -- 1. Returns idle for non-interactable type
    do
        local bb = make_blackboard({ ["bg.key"] = "AB" })
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization())
        local result = interactor:update(make_objective("MID", "MID"), { x = 100, y = 200, z = 50 }, 1000)
        T.assert_equal(result, "idle", "non-interactable type should return idle")
    end

    -- 2. Returns approaching when out of range
    do
        local bb = make_blackboard({ ["bg.key"] = "AB" })
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization())
        local obj = make_objective("STABLES", "NODE", 100, 200, 50, { [180087] = "NEUTRAL" })
        local result = interactor:update(obj, { x = 200, y = 200, z = 50 }, 1000)
        T.assert_equal(result, "approaching", "out of range should return approaching")
    end

    -- 3. Returns cooldown when interact too recent
    do
        local bb = make_blackboard({ ["bg.key"] = "AB" })
        setup_core({})
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization())
        interactor._last_interact_ms = 500
        local obj = make_objective("STABLES", "NODE", 100, 200, 50, { [180087] = "NEUTRAL" })
        local result = interactor:update(obj, { x = 100, y = 200, z = 50 }, 1000)
        T.assert_equal(result, "cooldown", "recent interact should return cooldown")
    end

    -- 4. Returns proximity for EOTS NODE type
    do
        local bb = make_blackboard({ ["bg.key"] = "EOTS" })
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization())
        local obj = make_objective("FEL_REAVER", "NODE", 100, 200, 50, { [184381] = "ALLIANCE" })
        local result = interactor:update(obj, { x = 100, y = 200, z = 50 }, 5000)
        T.assert_equal(result, "proximity", "EOTS NODE should return proximity")
    end

    -- 5. Interacts when in range and object found
    do
        local bb = make_blackboard({ ["bg.key"] = "AB" })
        setup_core({ make_game_object(180087, { x = 100, y = 200, z = 50 }, true) })
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization())
        local obj = make_objective("STABLES", "NODE", 100, 200, 50, { [180087] = "NEUTRAL" })
        local result = interactor:update(obj, { x = 101, y = 200, z = 50 }, 5000)
        T.assert_equal(result, "interacted", "should interact when in range with matching object")
    end

    -- 6. Publishes event on interaction
    do
        local bb = make_blackboard({ ["bg.key"] = "AB" })
        local eb = make_event_bus()
        setup_core({ make_game_object(180087, { x = 100, y = 200, z = 50 }, true) })
        local interactor = ObjectiveInteractor:new(eb, bb, make_humanization())
        local obj = make_objective("STABLES", "NODE", 100, 200, 50, { [180087] = "NEUTRAL" })
        interactor:update(obj, { x = 101, y = 200, z = 50 }, 5000)
        local found = false
        for _, pub in ipairs(eb.published) do
            if pub.event == "bg:objective_interacted" then
                found = true
                T.assert_equal(pub.payload.objective_id, "STABLES", "event should have objective_id")
                T.assert_equal(pub.payload.entry_id, 180087, "event should have entry_id")
            end
        end
        T.assert_true(found, "bg:objective_interacted event should be published")
    end

    -- 7. Returns no_object when no matching game object
    do
        local bb = make_blackboard({ ["bg.key"] = "AB" })
        setup_core({})
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization())
        local obj = make_objective("STABLES", "NODE", 100, 200, 50, { [180087] = "NEUTRAL" })
        local result = interactor:update(obj, { x = 100, y = 200, z = 50 }, 5000)
        T.assert_equal(result, "no_object", "should return no_object when nothing found")
    end

    -- 8. Returns waiting when humanization not ready
    do
        local bb = make_blackboard({ ["bg.key"] = "AB" })
        setup_core({ make_game_object(180087, { x = 100, y = 200, z = 50 }, true) })
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization(false))
        local obj = make_objective("STABLES", "NODE", 100, 200, 50, { [180087] = "NEUTRAL" })
        local result = interactor:update(obj, { x = 100, y = 200, z = 50 }, 5000)
        T.assert_equal(result, "waiting", "should return waiting when humanization not ready")
    end

    -- 9. Matches object by position proximity
    do
        local bb = make_blackboard({ ["bg.key"] = "AB" })
        setup_core({ make_game_object(999999, { x = 101, y = 201, z = 50 }, true) })
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization())
        local obj = make_objective("STABLES", "NODE", 100, 200, 50, { [180087] = "NEUTRAL" })
        local result = interactor:update(obj, { x = 100, y = 200, z = 50 }, 5000)
        T.assert_equal(result, "interacted", "should match by position proximity")
    end

    -- 10. Handles FLAG type (WSG)
    do
        local bb = make_blackboard({ ["bg.key"] = "WSG" })
        setup_core({ make_game_object(179831, { x = 916, y = 1433, z = 346 }, true) })
        local interactor = ObjectiveInteractor:new(make_event_bus(), bb, make_humanization())
        local obj = make_objective("HORDE_FLAG", "FLAG", 916, 1433, 346, { [179831] = "HORDE" })
        local result = interactor:update(obj, { x = 917, y = 1433, z = 346 }, 5000)
        T.assert_equal(result, "interacted", "should interact with WSG flag")
    end

    _G.core = nil
end

return M
