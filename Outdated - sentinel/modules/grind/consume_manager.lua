local ConsumeManager = {}
ConsumeManager.__index = ConsumeManager

local CONSUME_VERIFY_MS = 5000  -- Check if consuming actually started after 5s
local CONSUME_MIN_GAIN = 0.05    -- Expect at least 5% gain if consuming
local MAX_REUSE_ATTEMPTS = 5

---Create a new ConsumeManager instance.
---@return table
function ConsumeManager:new()
    return setmetatable({
        _active = false,
        _started_ms = 0,
        _initial_resource = 0,
        _reuse_count = 0,
    }, self)
end

---Consume an item and verify it worked.
---@param item_id number Item ID to consume
---@param opts table Options
---          resource_type "health" or "mana"
---          threshold number Trigger threshold (where we decide to consume)
---          target_pct number Completion threshold (default 0.95)
---@param blackboard table Blackboard instance
---@return table {status = "success"|"running"|"retry"|"failed", retry_count = number}
function ConsumeManager:consume(item_id, opts, blackboard)
    opts = opts or {}
    local resource_type = opts.resource_type or "health"
    local target_pct = opts.target_pct or 0.95
    
    -- Get current resource percentage
    local resource_key = resource_type == "mana" and "player.mana_pct" or "player.health_pct"
    local current_resource = blackboard:get(resource_key, 1)
    
    -- Check if we've completed (above target threshold)
    if current_resource >= target_pct then
        self._active = false
        self._reuse_count = 0
        return { status = "success", retry_count = 0 }
    end
    
    local now = blackboard:get("system.now_ms", 0)
    
    -- Not started yet — initiate consumption
    if not self._active then
        if core and core.input and core.input.use_item then
            local ok_use, err = pcall(core.input.use_item, item_id)
            if core and core.log then
                pcall(core.log, string.format("[Consume] consume(%d) %s ok=%s err=%s resource=%.2f",
                    item_id, resource_type, tostring(ok_use), tostring(err), current_resource))
            end
        end
        self._active = true
        self._started_ms = now
        self._initial_resource = current_resource
        self._reuse_count = self._reuse_count + 1
        return { status = "running", retry_count = self._reuse_count }
    end
    
    -- Check if we've been consuming long enough to verify
    if now - self._started_ms >= CONSUME_VERIFY_MS then
        local gain = current_resource - self._initial_resource
        
        -- Reset for next verification window
        self._started_ms = now
        self._initial_resource = current_resource
        
        if gain < CONSUME_MIN_GAIN then
            -- Passive regen only — consuming didn't start or stalled
            if core and core.log then
                pcall(core.log, string.format("[Consume] stall: gain=%.3f < %.3f, retry #%d",
                    gain, CONSUME_MIN_GAIN, self._reuse_count))
            end
            if self._reuse_count >= MAX_REUSE_ATTEMPTS then
                self._active = false
                self._reuse_count = 0
                return { status = "failed", retry_count = self._reuse_count }
            end
            return { status = "retry", retry_count = self._reuse_count }
        end
        
        -- Real consumption confirmed — reset timer for next window
        self._started_ms = now
        self._initial_resource = current_resource
    end
    
    return { status = "running", retry_count = self._reuse_count }
end

---Reset consumption state (e.g., on interrupt).
function ConsumeManager:reset()
    self._active = false
    self._reuse_count = 0
end

return ConsumeManager