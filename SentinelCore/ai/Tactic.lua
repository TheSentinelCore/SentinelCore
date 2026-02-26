---@class Tactic
---@field _name string
---@field _preconditions function
---@field _utility function
---@field _phases table[]
---@field _rest_config table|nil
---@field _target_config table|nil
---@field _explore_config table|nil
---@field _on_reset function|nil
local Tactic = {}
Tactic.__index = Tactic

---@param def table Tactic definition
---@return Tactic
function Tactic:new(def)
    local o = setmetatable({}, self)
    o._name = def.name or "unnamed"
    o._preconditions = def.preconditions or function() return true end
    o._utility = def.utility or function() return 0 end
    o._phases = def.phases or {}
    o._rest_config = def.rest_config
    o._target_config = def.target_config
    o._explore_config = def.explore_config
    o._on_reset = def.on_reset
    return o
end

function Tactic:get_name()
    return self._name
end

---@param ctx table Combat/world context
---@return boolean
function Tactic:check_preconditions(ctx)
    local ok, result = pcall(self._preconditions, ctx)
    return ok and result == true
end

---@param ctx table Combat/world context
---@param advisor table|nil PerformanceAdvisor
---@return number 0..1
function Tactic:score_utility(ctx, advisor)
    local ok, score = pcall(self._utility, ctx, advisor)
    if not ok or type(score) ~= "number" then return 0 end
    return math.max(0, math.min(1, score))
end

---@return table[]
function Tactic:get_phases()
    return self._phases
end

function Tactic:get_rest_config()
    return self._rest_config
end

function Tactic:get_target_config()
    return self._target_config
end

function Tactic:get_explore_config()
    return self._explore_config
end

function Tactic:reset()
    if self._on_reset then
        pcall(self._on_reset, self)
    end
end

return Tactic
