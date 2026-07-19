local GrindStateManager = {}
GrindStateManager.__index = GrindStateManager

---Manage grind-level state transitions on disable, death, and ghost.
---Extracted from SentinelGrind:update() to give state-reset logic its own locality.
function GrindStateManager:new()
    return setmetatable({
        _telemetry_initialized = false,
        _death_loop_responding = false,
    }, self)
end

---Tick: clean up stale state when grind is disabled or player is dead/ghost.
---@param bb table Blackboard
---@param enabled boolean Whether grind module is currently enabled
---@return boolean should_skip_update True if the caller should skip the rest of update()
function GrindStateManager:tick(bb, enabled)
    if not enabled then
        -- Reset telemetry session so death loop can recover on re-enable
        if self._telemetry_initialized then
            self._telemetry_initialized = false
        end
        self._death_loop_responding = false
        self._pending_kill_targets = nil

        -- Clear phase flags so Safety/Combat aren't blocked on re-enable
        if bb:get("module.grind.is_resting") then
            bb:set("module.grind.is_resting", false)
        end
        if bb:get("module.grind.is_looting") then
            bb:set("module.grind.is_looting", false)
        end
        return true
    end

    -- Clear death-related state when player is alive
    local is_dead = bb:get("player.is_dead") == true
    local is_ghost = bb:get("player.is_ghost") == true
    if not is_dead and not is_ghost then
        if bb:get("module.grind.death_started_ms") then
            bb:clear("module.grind.death_started_ms")
            bb:clear("module.grind.last_release_ms")
            bb:clear("module.grind.last_resurrect_ms")
            bb:clear("module.grind.corpse_position")
        end
    end

    -- Clear grind target and loot flag on death/ghost
    if is_dead or is_ghost then
        if bb:get("module.grind.current_target") then
            bb:set("module.grind.current_target", nil)
        end
        if bb:get("module.grind.is_looting") then
            bb:set("module.grind.is_looting", false)
        end
    end

    return false
end

function GrindStateManager:get_telemetry_initialized()
    return self._telemetry_initialized
end

function GrindStateManager:set_telemetry_initialized(val)
    self._telemetry_initialized = val
end

function GrindStateManager:get_death_loop_responding()
    return self._death_loop_responding
end

function GrindStateManager:set_death_loop_responding(val)
    self._death_loop_responding = val
end

---Track kill targets and detect deaths.
---Uses GUID comparison to avoid recycled userdata pointer issues.
---@param bb table Blackboard
---@param event_bus table EventBus
function GrindStateManager:track_kills(bb, event_bus)
    if not self._pending_kill_targets then
        self._pending_kill_targets = {}
    end

    local grind_target = bb:get("module.grind.current_target")
    if grind_target then
        local ok_guid, guid = pcall(grind_target.get_guid, grind_target)
        local key = ok_guid and guid and tostring(guid) or nil
        if key and not self._pending_kill_targets[key] then
            self._pending_kill_targets[key] = grind_target
        end
    end

    local to_remove = {}
    for guid, target in pairs(self._pending_kill_targets) do
        local ok_alive, alive = pcall(target.is_alive, target)
        if not ok_alive or not alive then
            to_remove[#to_remove + 1] = guid
            event_bus:publish("grind:kill", { target = target })
            local cur = bb:get("module.grind.current_target")
            if cur then
                local ok_cg, cur_guid = pcall(cur.get_guid, cur)
                if ok_cg and tostring(cur_guid) == guid then
                    bb:clear("module.grind.current_target")
                end
            end
        end
    end
    for _, guid in ipairs(to_remove) do
        self._pending_kill_targets[guid] = nil
    end
end

return GrindStateManager
