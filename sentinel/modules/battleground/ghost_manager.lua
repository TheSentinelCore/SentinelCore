local Events = require("modules/battleground/events")

local GhostManager = {}
GhostManager.__index = GhostManager

local function num(value)
    return tonumber(value) or 0
end

local function invoke_bool(owner, method, ...)
    if not owner or type(owner[method]) ~= "function" then
        return false
    end
    local fn = owner[method]
    local ok, value = pcall(fn, ...)
    if not ok then
        ok, value = pcall(fn, owner, ...)
    end
    if not ok then
        return false
    end
    return value == nil or value == true or value == 1
end

function GhostManager:new(event_bus, blackboard, nav_adapter)
    local o = setmetatable({}, GhostManager)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav_adapter = nav_adapter
    o._last_release_attempt_ms = 0
    o._ghost_started_ms = 0
    o._nav_stopped = false
    o._post_rez_until_ms = 0
    o._post_rez_published = false
    return o
end

function GhostManager:initialize()
    self:reset("initialize")
end

function GhostManager:_set(key, value)
    self._blackboard:set(key, value)
end

function GhostManager:reset(reason)
    self._last_release_attempt_ms = 0
    self._ghost_started_ms = 0
    self._nav_stopped = false
    self._post_rez_until_ms = 0
    self._post_rez_published = false
    self:_set("bg.ghost.active", false)
    self:_set("bg.ghost.mode", tostring(self._blackboard:get("module.bg.ghost_mode", "release_wait")))
    self:_set("bg.ghost.action", reason or "idle")
    self:_set("bg.ghost.release_attempted", false)
    self:_set("bg.ghost.release_attempted_at_ms", 0)
    self:_set("bg.ghost.nav_stopped", false)
    self:_set("bg.ghost.elapsed_ghost_s", 0)
    self:_set("bg.ghost.post_rez_grace", false)
end

function GhostManager:is_blocking_strategy()
    return self._blackboard:get("bg.ghost.active", false) == true
end

function GhostManager:update()
    local now_ms = num(self._blackboard:get("system.now_ms", 0))
    local is_dead = self._blackboard:get("player.is_dead", false) == true
    local is_ghost = self._blackboard:get("player.is_ghost", false) == true
    local in_bg = self._blackboard:get("bg.sensor.in_bg", false) == true

    self:_set("bg.ghost.mode", tostring(self._blackboard:get("module.bg.ghost_mode", "release_wait")))

    if is_dead and not is_ghost then
        self:_set("bg.ghost.active", true)
        self:_set("bg.ghost.action", "waiting_release")
        self:_set("bg.ghost.elapsed_ghost_s", 0)
        if (now_ms - self._last_release_attempt_ms) >= 1000 then
            local ok = invoke_bool(core and core.input, "release_spirit")
            self._last_release_attempt_ms = now_ms
            self:_set("bg.ghost.release_attempted", ok)
            self:_set("bg.ghost.release_attempted_at_ms", now_ms)
            self:_set("bg.ghost.action", ok and "release_spirit_attempt" or "release_spirit_failed")
        end
        return self:get_snapshot()
    end

    if is_ghost and in_bg then
        if self._ghost_started_ms <= 0 then
            self._ghost_started_ms = now_ms
        end
        if not self._nav_stopped then
            self._nav_adapter:stop("ghost_wait_spirit_healer")
            self._nav_stopped = true
        end
        self:_set("bg.ghost.active", true)
        self:_set("bg.ghost.action", "wait_spirit_healer")
        self:_set("bg.ghost.nav_stopped", self._nav_stopped)
        self:_set("bg.ghost.elapsed_ghost_s", math.max(0, (now_ms - self._ghost_started_ms) / 1000))
        return self:get_snapshot()
    end

    if not is_dead and not is_ghost then
        if self._ghost_started_ms > 0 then
            self._nav_adapter:stop("post_rez_reset")
            self._post_rez_until_ms = now_ms + 2000
            self._post_rez_published = false
            self._ghost_started_ms = 0
            self._nav_stopped = false
        end

        if self._post_rez_until_ms > 0 and now_ms < self._post_rez_until_ms then
            self:_set("bg.ghost.active", false)
            self:_set("bg.ghost.post_rez_grace", true)
            self:_set("bg.ghost.action", "post_rez_grace")
            if not self._post_rez_published and self._event_bus then
                self._event_bus:publish(Events.POST_REZ, {})
                self._post_rez_published = true
            end
            return self:get_snapshot()
        end

        if self._post_rez_until_ms > 0 then
            self._post_rez_until_ms = 0
            self:_set("bg.ghost.post_rez_grace", false)
        end

        if self._blackboard:get("bg.ghost.active", false) == true then
            self:reset("alive")
        end
    end

    return self:get_snapshot()
end

function GhostManager:get_snapshot()
    return {
        active = self._blackboard:get("bg.ghost.active", false),
        action = self._blackboard:get("bg.ghost.action"),
        nav_stopped = self._blackboard:get("bg.ghost.nav_stopped", false),
        elapsed_ghost_s = self._blackboard:get("bg.ghost.elapsed_ghost_s", 0),
    }
end

return GhostManager
