-- PerformanceAdvisor.lua
-- Tracks per-tactic telemetry (kills, deaths, XP) and computes performance biases
-- that TacticalSelector uses to favour better-performing tactics.

local PerformanceAdvisor = {}
PerformanceAdvisor.__index = PerformanceAdvisor

function PerformanceAdvisor:new(event_bus)
    local o = setmetatable({
        _event_bus = event_bus,
        _tactic_stats = {},
        _active_tactic = nil,
        _last_snapshot = nil,
        _biases = {},
        _min_sample_secs = 120,
    }, self)

    if event_bus then
        event_bus:on("telemetry.flushed", function(data)
            o:_on_telemetry(data)
        end, { owner = o })
    end

    return o
end

function PerformanceAdvisor:set_active_tactic(name)
    self._active_tactic = name
end

function PerformanceAdvisor:get_bias(tactic_name)
    return self._biases[tactic_name] or 1.0
end

function PerformanceAdvisor:get_stats(tactic_name)
    return self._tactic_stats[tactic_name]
end

function PerformanceAdvisor:_on_telemetry(data)
    local snapshot = data and data.snapshot
    if not snapshot then return end

    local name = self._active_tactic
    if not name then
        self._last_snapshot = snapshot
        return
    end

    if not self._tactic_stats[name] then
        self._tactic_stats[name] = { kills = 0, deaths = 0, xp_gained = 0, active_secs = 0 }
    end
    local stats = self._tactic_stats[name]

    if self._last_snapshot then
        local prev = self._last_snapshot
        local dk = (snapshot.kills or 0) - (prev.kills or 0)
        local dd = (snapshot.deaths or 0) - (prev.deaths or 0)
        local dx = (snapshot.xp_gained or 0) - (prev.xp_gained or 0)
        if dk > 0 then stats.kills = stats.kills + dk end
        if dd > 0 then stats.deaths = stats.deaths + dd end
        if dx > 0 then stats.xp_gained = stats.xp_gained + dx end
        stats.active_secs = stats.active_secs + 1
    end

    self._last_snapshot = snapshot
    self:_recompute_biases()
end

function PerformanceAdvisor:_recompute_biases()
    local scores = {}
    local max_score = 0
    local has_data = false

    for name, stats in pairs(self._tactic_stats) do
        if stats.active_secs >= self._min_sample_secs then
            has_data = true
            local effective_xp = stats.xp_gained - (stats.deaths * 300)
            local score = effective_xp / stats.active_secs
            scores[name] = math.max(score, 0.001)
            if scores[name] > max_score then max_score = scores[name] end
        end
    end

    if not has_data or max_score <= 0 then return end

    for name, score in pairs(scores) do
        local ratio = score / max_score
        self._biases[name] = 0.8 + 0.4 * ratio
    end
end

function PerformanceAdvisor:reset()
    self._tactic_stats = {}
    self._biases = {}
    self._active_tactic = nil
    self._last_snapshot = nil
end

function PerformanceAdvisor:destroy()
    if self._event_bus then
        self._event_bus:off_owner(self)
    end
end

return PerformanceAdvisor
