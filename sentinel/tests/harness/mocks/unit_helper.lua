-- sentinel/tests/harness/mocks/unit_helper.lua
-- Offline mock for `common/utility/unit_helper`, an injector-provided module
-- (Sylvannas/Sylvannas-adjacent) that does not exist on disk and is therefore
-- absent in every offline test run (see audit finding D4). Without this mock,
-- `pcall(require, "common/utility/unit_helper")` fails everywhere it is
-- attempted, so every proximity-dependent branch (combat outnumbered checks,
-- target selection scoring, healer detection, sensor health lookups) takes
-- its "no unit_helper" fallback path and is structurally untestable offline.
--
-- This module is NOT wired into package.path/package.loaded automatically —
-- doing so requires a change to sentinel/tests/run_offline.lua, which is out
-- of scope for the lane that authored this mock. See the coordination note
-- in that file's owning lane for the exact registration line needed:
--
--   package.loaded["common/utility/unit_helper"] = require("tests/harness/mocks/unit_helper")
--
-- placed after package.path is configured and before test_modules run.
--
-- Test usage once registered:
--   local UnitHelper = require("common/utility/unit_helper")
--   UnitHelper.set_enemies({ mob1, mob2 })
--   UnitHelper.set_allies({ ally1 })
--   UnitHelper.set_healers({ [healer_unit] = true })
--   -- ... exercise code under test ...
--   UnitHelper.reset() -- call between tests to avoid cross-test bleed

local M = {}

local _enemies = {}
local _allies = {}
local _healers = {}
local _health_pct = {}

--- Test configuration -------------------------------------------------------

function M.set_enemies(list)
    _enemies = list or {}
end

function M.set_allies(list)
    _allies = list or {}
end

--- Mark a unit as a healer. `map` is either a set-style table (`{[unit]=true}`)
--- or an array of units, both accepted for caller convenience.
function M.set_healers(map)
    _healers = {}
    if type(map) ~= "table" then return end
    for k, v in pairs(map) do
        if type(k) == "number" and type(v) ~= "boolean" then
            _healers[v] = true
        else
            _healers[k] = v and true or nil
        end
    end
end

--- Set a fixed health percentage for a given unit (0-100 scale, matching the
--- production `get_health_percentage` callers' expectations).
function M.set_health_percentage(unit, pct)
    _health_pct[unit] = pct
end

function M.reset()
    _enemies = {}
    _allies = {}
    _healers = {}
    _health_pct = {}
end

--- Mocked unit_helper surface -----------------------------------------------
-- Signatures mirror production call sites (self-call convention, matching
-- `pcall(self._unit_helper.get_enemy_list_around, self._unit_helper, ...)`).

function M.get_enemy_list_around(_self, _position, _radius, ...)
    return _enemies
end

function M.get_ally_list_around(_self, _position, _radius, ...)
    return _allies
end

function M.is_healer(_self, unit)
    return _healers[unit] == true
end

function M.get_health_percentage(_self, unit)
    local pct = _health_pct[unit]
    if pct ~= nil then return pct end
    if unit and type(unit.get_health_percentage) == "function" then
        local ok, value = pcall(unit.get_health_percentage, unit)
        if ok and value then return value * 100 end
    end
    return 100
end

return M
