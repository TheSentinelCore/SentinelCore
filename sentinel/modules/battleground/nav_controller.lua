local NavController = {}
NavController.__index = NavController

function NavController:new(event_bus, blackboard, nav_adapter)
    local o = setmetatable({}, NavController)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav_adapter = nav_adapter
    o._active = nil
    o._last_poll_at_ms = 0
    o._poll_interval_ms = 250
    o._idle_recovery_grace_ms = 750
    o._stuck_polls = 0
    return o
end

function NavController:reset()
    self._active = nil
    self._last_poll_at_ms = 0
    self._stuck_polls = 0
    self._blackboard:set("nav.owner", nil)
    self._blackboard:set("nav.command", nil)
    self._blackboard:set("nav.destination", nil)
    self._blackboard:set("nav.state", "idle")
    self._blackboard:set("bg.nav_objective_id", nil)
    self._blackboard:set("bg.nav_route_id", nil)
end

function NavController:_activate(command, destination, meta)
    meta = meta or {}
    self._active = {
        command = command,
        destination = destination,
        objective_id = meta.objective_id,
        route_id = meta.route_id,
        source = meta.source or "bg",
        failure_count = 0,
        started_published = false,
        issued_at_ms = tonumber(self._blackboard:get("system.now_ms", 0)) or 0,
    }
    self._blackboard:set("nav.owner", "bg")
    self._blackboard:set("nav.command", command)
    self._blackboard:set("nav.destination", destination)
    self._blackboard:set("nav.failure_count", 0)
    self._blackboard:set("nav.last_failure_count", 0)
    self._blackboard:set("bg.nav_objective_id", meta.objective_id)
    self._blackboard:set("bg.nav_route_id", meta.route_id)
    self._event_bus:publish("nav:command_requested", {
        command = command,
        source = meta.source or "bg",
        target = command == "move_to" and destination or nil,
        nodes = (command == "plan_route" or command == "follow_path") and meta.nodes or nil,
        opts = meta.opts or {},
        objective_id = meta.objective_id,
        route_id = meta.route_id,
    })
end

function NavController:issue_move_to(target, meta)
    self:_activate("move_to", target, meta)
    self._nav_adapter:move_to(target, meta and meta.opts or nil)
end

function NavController:issue_plan_route(nodes, meta)
    local destination = nodes and nodes[#nodes] or nil
    meta = meta or {}
    meta.nodes = nodes
    self:_activate("plan_route", destination, meta)
    self._nav_adapter:plan_route(nodes, meta.opts)
end

function NavController:issue_follow_path(nodes, meta)
    local destination = nodes and nodes[#nodes] or nil
    meta = meta or {}
    meta.nodes = nodes
    self:_activate("follow_path", destination, meta)
    self._nav_adapter:follow_path(nodes, meta.opts)
end

function NavController:stop(reason, source)
    self._nav_adapter:stop(reason)
    if self._active then
        self._event_bus:publish("nav:stopped", {
            reason = reason or "stop",
            source = source or self._active.source,
        })
    end
    self:reset()
end

function NavController:update(blackboard)
    local now_ms = blackboard:get("system.now_ms", 0)
    if (now_ms - self._last_poll_at_ms) < self._poll_interval_ms then
        return
    end
    self._last_poll_at_ms = now_ms

    local state, progress = self._nav_adapter:poll()
    blackboard:set("nav.state", state)
    if progress then
        blackboard:set("nav.progress", progress)
    end

    if not self._active then
        return
    end

    if state == "idle" then
        local issued_at_ms = tonumber(self._active.issued_at_ms or 0) or 0
        local elapsed_ms = now_ms - issued_at_ms
        if not self._active.started_published and elapsed_ms >= self._idle_recovery_grace_ms then
            blackboard:set("nav.last_idle_abort_reason", "movement_idle_before_start")
            self:reset()
            return
        end

        if self._active.started_published then
            self._active.failure_count = self._active.failure_count + 1
            blackboard:set("nav.failure_count", self._active.failure_count)
            blackboard:set("nav.last_failure_count", self._active.failure_count)
            blackboard:set("bg.nav_result", "failed")
            self._event_bus:publish("nav:failed", {
                command = self._active.command,
                reason = "movement_idle_after_start",
                failure_count = self._active.failure_count,
                destination = self._active.destination,
                objective_id = self._active.objective_id,
            })
            self:reset()
        end
        return
    end

    if (state == "requesting_path" or state == "moving" or state == "stuck") and not self._active.started_published then
        self._active.started_published = true
        self._event_bus:publish("nav:started", {
            command = self._active.command,
            source = self._active.source,
            destination = self._active.destination,
            node_count = progress and progress.path_count or nil,
            objective_id = self._active.objective_id,
        })
    end

    if state == "requesting_path" or state == "moving" or state == "stuck" then
        self._event_bus:publish("nav:progress", progress or {
            state = state,
            destination = self._active.destination,
        })
        if state == "stuck" then
            self._stuck_polls = self._stuck_polls + 1
            if self._stuck_polls > 2 then
                self._event_bus:publish("nav:reroute_requested", {
                    reason = "stuck_poll_threshold",
                    fallback_id = self._active.objective_id,
                    source = self._active.source,
                    objective_id = self._active.objective_id,
                })
            end
        else
            self._stuck_polls = 0
        end
        return
    end

    if state == "arrived" then
        blackboard:set("bg.nav_result", "arrived")
        self._event_bus:publish("nav:arrived", {
            command = self._active.command,
            destination = self._active.destination,
            objective_id = self._active.objective_id,
        })
        self:reset()
        return
    end

    if state == "failed" then
        self._active.failure_count = self._active.failure_count + 1
        blackboard:set("nav.failure_count", self._active.failure_count)
        blackboard:set("nav.last_failure_count", self._active.failure_count)
        blackboard:set("bg.nav_result", "failed")
        self._event_bus:publish("nav:failed", {
            command = self._active.command,
            reason = "movement_failed",
            failure_count = self._active.failure_count,
            destination = self._active.destination,
            objective_id = self._active.objective_id,
        })
        self:reset()
        return
    end
end

return NavController
