local Blackboard = require("core/blackboard")
local ObjectiveTracker = require("modules/battleground/objective_tracker")
local EOTSObjectives = require("modules/battleground/data/objectives/eots")
local T = require("tests/test_util")

local M = {}

local function make_object(entry_id, pos)
    return {
        get_npc_id = function()
            return entry_id
        end,
        get_position = function()
            return pos
        end,
    }
end

local function make_named_object(name, pos)
    return {
        get_name = function()
            return name
        end,
        get_position = function()
            return pos
        end,
    }
end

function M.run()
    local bb = Blackboard:new()
    bb:set("system.now_ms", 1000)

    local old_core = _G.core
    _G.core = {
        object_manager = {
            get_visible_objects = function()
                return {
                    make_object(184381, { x = 2270.9, y = 1784.0, z = 1186.7 }),
                }
            end,
        },
    }

    local tracker = ObjectiveTracker:new(bb)
    local states = tracker:update("ALLIANCE", EOTSObjectives.all)
    T.assert_equal(states.MAGE_TOWER.owner, "FRIENDLY")
    T.assert_equal(states.MAGE_TOWER.raw_owner, "ALLIANCE")

    bb:set("system.now_ms", 2000)
    _G.core.object_manager.get_visible_objects = function()
        return {}
    end
    states = tracker:update("ALLIANCE", EOTSObjectives.all)
    T.assert_equal(states.MAGE_TOWER.owner, "FRIENDLY")

    bb:set("system.now_ms", 3000)
    _G.core.object_manager.get_visible_objects = function()
        return {
            make_named_object("Forcefield 000", { x = 2527.55, y = 1596.95, z = 1262.10 }),
        }
    end
    states, signals = tracker:update("ALLIANCE", EOTSObjectives.all, {
        bg_key = "EOTS",
        side = "ALLIANCE",
        player_pos = { x = 2523.69, y = 1596.60, z = 1269.35 },
    })
    T.assert_true(signals.visible_objects_supported)
    T.assert_true(signals.spawn_barrier_seen)
    T.assert_equal(signals.spawn_barrier_name, "Forcefield 000")
    T.assert_equal(signals.spawn_barrier_source, "name")
    T.assert_true(tonumber(signals.spawn_barrier_distance) > 0)

    _G.core = old_core
end

return M
