local Status = require("core/bt/status")
local Node = require("core/bt/node")

local Inverter = setmetatable({}, { __index = Node })
Inverter.__index = Inverter

function Inverter:new(name, child)
    local o = Node.new(self, "inverter", name, { child })
    return o
end

function Inverter:tick(blackboard)
    local status = self.children[1]:tick(blackboard)
    if status == Status.SUCCESS then
        return Status.FAILURE
    end
    if status == Status.FAILURE then
        return Status.SUCCESS
    end
    return Status.RUNNING
end

local Cooldown = setmetatable({}, { __index = Node })
Cooldown.__index = Cooldown

function Cooldown:new(name, interval_ms, child, opts)
    local o = Node.new(self, "cooldown", name, { child })
    o.interval_ms = interval_ms or 0
    o._last_tick_at_ms = 0
    o._key = opts and opts.key or nil
    return o
end

function Cooldown:tick(blackboard)
    local now_ms = blackboard:get("system.now_ms", 0)
    local key = self._key and ("module.bt.cooldown." .. self._key) or nil
    -- Use blackboard value if key exists, otherwise fall back to instance variable
    local last_ms = self._last_tick_at_ms
    if key then
        local stored = blackboard:get(key)
        if stored ~= nil then
            last_ms = stored
        end
    end
    if now_ms - last_ms < self.interval_ms then
        return Status.FAILURE
    end
    local status = self.children[1]:tick(blackboard)
    if status ~= Status.RUNNING then
        self._last_tick_at_ms = now_ms
        if key then
            blackboard:set(key, now_ms)
        end
    end
    return status
end

local MaxAttempts = setmetatable({}, { __index = Node })
MaxAttempts.__index = MaxAttempts

function MaxAttempts:new(name, max_attempts, child, opts)
    local o = Node.new(self, "max_attempts", name, { child })
    o.max_attempts = max_attempts or 1
    o._key = opts and opts.key or name
    o._attempts = 0
    return o
end

function MaxAttempts:tick(blackboard)
    local key = "module.bt.attempts." .. tostring(self._key)
    local attempts = blackboard:get(key, self._attempts)
    if attempts >= self.max_attempts then
        return Status.FAILURE
    end
    local status = self.children[1]:tick(blackboard)
    if status == Status.FAILURE then
        attempts = attempts + 1
        self._attempts = attempts
        blackboard:set(key, attempts)
    elseif status == Status.SUCCESS then
        self._attempts = 0
        blackboard:set(key, 0)
    end
    return status
end

function MaxAttempts:reset()
    self._attempts = 0
    Node.reset(self)
end

return {
    Inverter = Inverter,
    Cooldown = Cooldown,
    MaxAttempts = MaxAttempts,
}
