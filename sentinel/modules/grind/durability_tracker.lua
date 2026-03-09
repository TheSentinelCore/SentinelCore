local DurabilityTracker = {}
DurabilityTracker.__index = DurabilityTracker

local SAMPLE_INTERVAL_MS = 5000
local DEFAULT_THRESHOLD = 0.25

---Create a new DurabilityTracker instance.
---@return table tracker
function DurabilityTracker:new()
    local o = {
        _last_sample_ms = nil,
        _threshold = DEFAULT_THRESHOLD,
    }
    setmetatable(o, self)
    return o
end

---Set the durability threshold below which needs_repair is flagged.
---@param pct number Threshold as a fraction (0-1), e.g. 0.25 = 25%
function DurabilityTracker:set_threshold(pct)
    self._threshold = pct
end

---Poll equipped item durability and write results to the blackboard.
---Throttled to SAMPLE_INTERVAL_MS (5s) between samples.
---@param bb table Blackboard
---@param now_ms number Current time in milliseconds
function DurabilityTracker:sample(bb, now_ms)
    if self._last_sample_ms and (now_ms - self._last_sample_ms) < SAMPLE_INTERVAL_MS then
        return
    end
    self._last_sample_ms = now_ms

    local lowest_pct = 1.0

    local player = bb:get("player.object")
    if player then
        local ok_items, items = pcall(player.get_equipped_items, player)
        if ok_items and type(items) == "table" then
            for _, slot in ipairs(items) do
                local obj = slot.object
                if obj then
                    local ok_dur, dur = pcall(obj.get_durability, obj)
                    local ok_max, max_dur = pcall(obj.get_max_durability, obj)
                    if ok_dur and ok_max and type(dur) == "number" and type(max_dur) == "number" and max_dur > 0 then
                        local pct = dur / max_dur
                        if pct < lowest_pct then
                            lowest_pct = pct
                        end
                    end
                end
            end
        end
    end

    bb:set("module.grind.durability_pct", lowest_pct)
    bb:set("module.grind.needs_repair", lowest_pct < self._threshold)
end

return DurabilityTracker
