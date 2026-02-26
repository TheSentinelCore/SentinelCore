---@class TacticalSelector
---@field _all_tactics Tactic[]
---@field _available Tactic[]
---@field _active Tactic|nil
---@field _advisor table|nil
local TacticalSelector = {}
TacticalSelector.__index = TacticalSelector

local HYSTERESIS_BONUS = 0.1

---@param advisor table|nil PerformanceAdvisor (or nil for no bias)
function TacticalSelector:new(advisor)
    return setmetatable({
        _all_tactics = {},
        _available = {},
        _active = nil,
        _advisor = advisor,
    }, self)
end

---@param tactic Tactic
function TacticalSelector:register(tactic)
    self._all_tactics[#self._all_tactics + 1] = tactic
end

---Filter tactics by preconditions. Call on startup and on level-up.
---@param ctx table
function TacticalSelector:refresh_available(ctx)
    self._available = {}
    for i = 1, #self._all_tactics do
        local t = self._all_tactics[i]
        if t:check_preconditions(ctx) then
            self._available[#self._available + 1] = t
        end
    end
end

---@return number
function TacticalSelector:get_available_count()
    return #self._available
end

---@return Tactic|nil
function TacticalSelector:get_active()
    return self._active
end

---Score all available tactics and activate the best one.
---Active tactic gets a hysteresis bonus to prevent thrashing.
---@param ctx table
---@return Tactic|nil
function TacticalSelector:select(ctx)
    if #self._available == 0 then return nil end

    local best_tactic = nil
    local best_score = -1

    for i = 1, #self._available do
        local t = self._available[i]
        local raw = t:score_utility(ctx, self._advisor)

        -- Apply advisor bias
        if self._advisor and type(self._advisor.get_bias) == "function" then
            local ok, bias = pcall(self._advisor.get_bias, self._advisor, t:get_name())
            if ok and type(bias) == "number" then
                raw = raw * bias
            end
        end

        -- Hysteresis: active tactic gets bonus
        if self._active and t == self._active then
            raw = raw + HYSTERESIS_BONUS
        end

        if raw > best_score then
            best_score = raw
            best_tactic = t
        end
    end

    -- Switch tactic if changed
    if best_tactic and best_tactic ~= self._active then
        if self._active then
            self._active:reset()
        end
        self._active = best_tactic
    end

    return self._active
end

return TacticalSelector
