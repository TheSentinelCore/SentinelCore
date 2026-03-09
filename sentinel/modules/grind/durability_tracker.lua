-- Polls repair cost to detect when gear needs repair.
-- Uses core.inventory.get_total_repair_cost() (copper).
-- No per-item durability API exists, so repair cost > threshold = needs_repair.

local DurabilityTracker = {}
DurabilityTracker.__index = DurabilityTracker

local SAMPLE_INTERVAL_MS = 5000
local DEFAULT_THRESHOLD_COPPER = 5000 -- 50 silver

function DurabilityTracker:new()
    return setmetatable({
        _last_sample_ms = nil,
        _threshold_copper = DEFAULT_THRESHOLD_COPPER,
    }, self)
end

--- Set the repair cost threshold (in copper) above which needs_repair is flagged.
--- 100 copper = 1 silver, 10000 copper = 1 gold.
function DurabilityTracker:set_threshold_copper(copper)
    self._threshold_copper = copper
end

--- Poll repair cost and update blackboard.
--- Throttled to 5s intervals.
function DurabilityTracker:sample(bb, now_ms)
    if self._last_sample_ms and (now_ms - self._last_sample_ms) < SAMPLE_INTERVAL_MS then
        return
    end
    self._last_sample_ms = now_ms

    local repair_cost = 0
    if core and core.inventory and type(core.inventory.get_total_repair_cost) == "function" then
        local ok, cost = pcall(core.inventory.get_total_repair_cost)
        if ok and type(cost) == "number" then
            repair_cost = cost
        end
    end

    bb:set("module.grind.repair_cost_copper", repair_cost)
    bb:set("module.grind.needs_repair", repair_cost >= self._threshold_copper)
end

--- Force a re-sample on next call (e.g., after visiting repair vendor).
function DurabilityTracker:reset()
    self._last_sample_ms = nil
end

return DurabilityTracker
