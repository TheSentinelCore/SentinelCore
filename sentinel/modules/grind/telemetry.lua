local Telemetry = {}
Telemetry.__index = Telemetry

local DEATH_LOOP_RADIUS = 60
local DEATH_LOOP_WINDOW_MS = 300000 -- 5 minutes (tightened from 10 to reduce false positives)
local DEATH_LOOP_THRESHOLD = 3
local DEATH_BUFFER_SIZE = 10

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Telemetry:new(event_bus)
    local o = setmetatable({
        _event_bus = event_bus,
        _subscriptions = {},
        _start_ms = nil,
        _start_xp = nil,
        -- Counters
        kills = 0,
        deaths = 0,
        loot_events = 0,
        vendor_trips = 0,
        stuck_recoveries = 0,
        -- Death ring buffer for loop detection
        _death_buffer = {},
    }, self)
    return o
end

---Reset session counters and death buffer for a fresh start.
function Telemetry:reset_session()
    self._death_buffer = {}
    self.kills = 0
    self.deaths = 0
    self.loot_events = 0
    self.vendor_trips = 0
    self.stuck_recoveries = 0
    self._start_xp = nil
    self._start_ms = nil
    self._xp_accumulated = 0
    self._last_xp = nil
end

function Telemetry:initialize(now_ms)
    -- Unsubscribe any existing listeners to prevent duplicate handlers
    -- on disable/re-enable cycles (reset_session does not clear subscriptions).
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}

    self:reset_session()
    self._start_ms = now_ms

    -- Snapshot starting XP
    if core and core.object_manager then
        local ok, player = pcall(core.object_manager.get_local_player)
        if ok and player and type(player.get_xp) == "function" then
            local ok_xp, xp = pcall(player.get_xp, player)
            if ok_xp and type(xp) == "number" then
                self._start_xp = xp
            end
        end
    end

    -- Subscribe to grind events
    local subs = self._subscriptions
    subs[#subs + 1] = self._event_bus:subscribe("grind:death", function(payload)
        self.deaths = self.deaths + 1
        -- Ring buffer for death loop detection
        local buf = self._death_buffer
        buf[#buf + 1] = {
            position = payload and payload.position,
            timestamp = payload and payload.timestamp or self._start_ms,
        }
        if #buf > DEATH_BUFFER_SIZE then
            table.remove(buf, 1)
        end
    end)

    subs[#subs + 1] = self._event_bus:subscribe("grind:kill", function()
        self.kills = self.kills + 1
    end)

    subs[#subs + 1] = self._event_bus:subscribe("grind:loot", function()
        self.loot_events = self.loot_events + 1
    end)

    subs[#subs + 1] = self._event_bus:subscribe("grind:vendor_complete", function()
        self.vendor_trips = self.vendor_trips + 1
    end)

    subs[#subs + 1] = self._event_bus:subscribe("grind:stuck_recovery", function()
        self.stuck_recoveries = self.stuck_recoveries + 1
    end)
end

---Check for death loop: 3+ deaths within 60yd radius in the last 10 minutes.
---@param now_ms number Current time in milliseconds
---@return boolean
function Telemetry:is_death_loop(now_ms)
    local buf = self._death_buffer
    if #buf < DEATH_LOOP_THRESHOLD then return false end

    -- Check recent deaths within time window
    local recent = {}
    for _, entry in ipairs(buf) do
        if entry.timestamp and (now_ms - entry.timestamp) < DEATH_LOOP_WINDOW_MS then
            recent[#recent + 1] = entry
        end
    end

    if #recent < DEATH_LOOP_THRESHOLD then return false end

    -- Check if any cluster of deaths are within radius
    for i = 1, #recent do
        if recent[i].position then
            local nearby = 0
            for j = 1, #recent do
                if i ~= j and recent[j].position then
                    if distance_3d(recent[i].position, recent[j].position) <= DEATH_LOOP_RADIUS then
                        nearby = nearby + 1
                    end
                end
            end
            if nearby + 1 >= DEATH_LOOP_THRESHOLD then
                return true
            end
        end
    end

    return false
end

---Get elapsed session time in hours.
---@param now_ms number
---@return number
function Telemetry:_elapsed_hours(now_ms)
    if not self._start_ms then return 0 end
    local elapsed = (now_ms - self._start_ms) / 3600000
    return math.max(elapsed, 1 / 3600) -- minimum 1 second to avoid div/0
end

---Get kills per hour.
---@param now_ms number
---@return number
function Telemetry:get_kills_per_hour(now_ms)
    return self.kills / self:_elapsed_hours(now_ms)
end

---Get deaths per hour.
---@param now_ms number
---@return number
function Telemetry:get_deaths_per_hour(now_ms)
    return self.deaths / self:_elapsed_hours(now_ms)
end

---Get XP per hour.
---@param now_ms number
---@return number
function Telemetry:get_xp_per_hour(now_ms)
    if not self._start_xp then return 0 end
    local current_xp = 0
    if core and core.object_manager then
        local ok, player = pcall(core.object_manager.get_local_player)
        if ok and player and type(player.get_xp) == "function" then
            local ok_xp, xp = pcall(player.get_xp, player)
            if ok_xp and type(xp) == "number" then
                current_xp = xp
            end
        end
    end
    -- Track XP across level-ups: when current_xp drops below last_xp,
    -- a level-up occurred — bank the delta from last_xp to 0 and continue
    -- accumulating from the new XP value.
    if self._last_xp and current_xp < self._last_xp then
        self._xp_accumulated = (self._xp_accumulated or 0) + self._last_xp
        self._start_xp = 0
    end
    self._last_xp = current_xp
    local delta = (self._xp_accumulated or 0) + current_xp - self._start_xp
    if delta < 0 then delta = 0 end
    return delta / self:_elapsed_hours(now_ms)
end

---Write telemetry counters to blackboard for UI display.
---@param bb table Blackboard
---@param now_ms number
function Telemetry:publish_to_blackboard(bb, now_ms)
    bb:set("module.grind.telemetry.kills", self.kills)
    bb:set("module.grind.telemetry.deaths", self.deaths)
    bb:set("module.grind.telemetry.loot_events", self.loot_events)
    bb:set("module.grind.telemetry.vendor_trips", self.vendor_trips)
    bb:set("module.grind.telemetry.kills_per_hour", math.floor(self:get_kills_per_hour(now_ms)))
    bb:set("module.grind.telemetry.deaths_per_hour", math.floor(self:get_deaths_per_hour(now_ms) * 10) / 10)
    bb:set("module.grind.telemetry.xp_per_hour", math.floor(self:get_xp_per_hour(now_ms)))
end

function Telemetry:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
end

return Telemetry
