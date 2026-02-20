---
title: Consumer Integration
layout: default
parent: Guides
nav_order: 1
---

# Consumer Integration Guide
{: .no_toc }

How to use SentinelNavClient from your own Sylvannas plugin.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Load Order

SentinelNavClient must initialize before consumers. This happens **automatically** because:

1. SentinelNavClient's `main.lua` calls `on_load()` eagerly (at module load time, not deferred to `on_update`)
2. By the time any consumer's `on_update` callback fires, `_G.SentinelNavClient.client` is ready

No special load order configuration is needed.

---

## Basic Integration Pattern

```lua
-- In your plugin's initialize():

-- 1. Check SentinelNavClient availability
if not (_G.SentinelNavClient and _G.SentinelNavClient.client) then
    core.log_error("SentinelNavClient not loaded — navigation unavailable")
    return
end

local client = _G.SentinelNavClient.client

-- 2. Store reference for later use
self._nav_client = client

-- 3. Issue movement commands
client:move_to(target, function(ok, reason)
    if ok then
        core.log("Arrived!")
    else
        core.log_error("Failed: " .. tostring(reason))
    end
end)

-- 4. Query state
if client:is_moving() then
    local progress = client:get_progress()
    core.log(string.format("Waypoint %d/%d", progress.path_index, progress.path_count))
end
```

---

## Storing Module References

If your plugin needs frequent access to specific modules, store references at initialization:

```lua
function MyPlugin:initialize()
    if _G.SentinelNavClient and _G.SentinelNavClient.client then
        self._client = _G.SentinelNavClient.client

        -- Store module references if needed for direct access
        self._modules = {
            Navigation = self._client.nav_client,
            Movement   = self._client.movement,
            Obstacle   = self._client.obstacle,
        }

        self._nav_available = true
    else
        self._nav_available = false
        self._nav_error = "SentinelNavClient plugin not loaded."
    end
end
```

---

## Event Handling

Subscribe to events for state change notifications. Events are optional but useful for reactive behavior:

```lua
-- Subscribe to events
client:on("arrived", function()
    -- Trigger next action in your plugin's workflow
    self:on_destination_reached()
end)

client:on("stuck", function()
    -- Log or take plugin-specific action
    core.log("[MyPlugin] Navigation stuck, recovery in progress...")
end)

client:on("failed", function()
    -- Handle navigation failure
    core.log_error("[MyPlugin] Navigation failed")
    self:handle_nav_failure()
end)

client:on("state_change", function(data)
    -- General state tracking
    self._last_nav_state = data.to
end)
```

{: .warning }
Event callbacks are wrapped in `pcall`. If your handler throws an error, it is caught and logged but does not affect SentinelNavClient or other handlers. However, **do not perform expensive operations in event handlers** &mdash; they run on the main thread.

### Unsubscribing

To unsubscribe, pass the **same function reference** used when subscribing:

```lua
local function on_arrived()
    core.log("Done!")
end

client:on("arrived", on_arrived)

-- Later:
client:off("arrived", on_arrived)
```

---

## What NOT to Do

### Don't create your own Client

```lua
-- WRONG: Creates an isolated instance disconnected from SentinelNavClient
local my_client = Client:new(config)

-- RIGHT: Use the shared singleton
local client = _G.SentinelNavClient.client
```

### Don't call update() yourself

```lua
-- UNNECESSARY: SentinelNavClient handles this every frame
client:update()

-- This is harmless (Movement rate-limits internally) but unnecessary
```

### Don't push settings

```lua
-- OVERWRITTEN: SentinelNavClient's sync_to_client() runs every render frame
client:update_config({ movement = { waypoint_tolerance = 5.0 } })

-- Use the SentinelNavClient Settings UI instead
```

### Don't manage Obstacle wiring

```lua
-- UNNECESSARY: Client wires Obstacle into Movement at construction
movement:set_obstacle_module(my_obstacle)

-- The shared Client already handles this
```

---

## Multi-Node Routes

For plugins that need to visit multiple locations (e.g., gathering routes):

```lua
local herb_spots = {
    { x = -9100, y = 400, z = 93 },
    { x = -9200, y = 500, z = 91 },
    { x = -8900, y = 600, z = 95 },
    { x = -8800, y = 650, z = 92 },
}

client:plan_route(herb_spots, function(ok, data)
    if ok then
        if data.type == "leg_complete" then
            core.log(string.format("Leg %d/%d complete", data.leg, data.total))
            -- Perform action at this node (e.g., gather herb)
            self:gather_at_node(data.leg)
        elseif data.type == "route_complete" then
            core.log("Route finished!")
            self:on_route_complete()
        end
    else
        core.log_error("Route failed: " .. data.error)
    end
end, {
    return_to_start = true,  -- Return to first node after visiting all
})
```

### Replanning Mid-Route

If conditions change during a route (e.g., a node becomes unavailable), replan from the current leg:

```lua
client:replan("Node unavailable")
```

This collects remaining unvisited nodes and re-requests a TSP-optimized route from SentinelNavServer.

---

## Destination Validation

Before committing to a destination, validate it's reachable:

```lua
client:validate_destination(target, function(reachable, reason, distance)
    if reachable then
        core.log(string.format("Target reachable, %.0f yards", distance))
        client:move_to(target, on_arrival)
    else
        core.log_error("Unreachable: " .. tostring(reason))
        -- Handle: choose alternative target, wait, etc.
    end
end)
```

---

## Checking Server Health

Before starting navigation-critical operations:

```lua
function MyPlugin:ensure_nav_ready(callback)
    if not self._nav_available then
        callback(false, "SentinelNavClient not loaded")
        return
    end

    self._client:health_check(function(ok, data)
        if ok then
            callback(true)
        else
            callback(false, "SentinelNavServer unreachable")
        end
    end)
end
```

---

## Real-World Examples

### SentinelGather

SentinelGather's `BotManager:initialize()` accesses the shared Client and stores module references:

```lua
if _G.SentinelNavClient and _G.SentinelNavClient.client then
    self._nav_client = _G.SentinelNavClient.client
    self._modules.Navigation = self._nav_client.nav_client
    self._modules.Movement   = self._nav_client.movement
    self._modules.Obstacle   = self._nav_client.obstacle
    self._nav_client_available = true
else
    self._nav_client_available = false
    self._nav_client_error = "SentinelNavClient plugin not loaded."
end
```

SentinelGather's `_update_modules()` only updates its **own** modules (Safety, NodeScanner, Gather, Mount, etc.). SentinelNavClient modules update themselves via SentinelNavClient's own `on_update` callback.

### BgBuddy

BgBuddy's `QueueManager` uses the backward-compatible `create()` API:

```lua
function QueueManager:_ensure_nav()
    if self._nav then return true end
    if not _G.SentinelNavClient or not _G.SentinelNavClient.create then
        return false
    end
    self._nav = _G.SentinelNavClient.create({})  -- Config ignored, returns shared Client
    return self._nav ~= nil
end
```

---

## Tips

1. **Check availability early.** Validate `_G.SentinelNavClient.client` in your plugin's `initialize()`, not on every frame.

2. **Store the client reference.** Avoid repeated global lookups &mdash; store `_G.SentinelNavClient.client` in a local field.

3. **Use callbacks for flow control.** Navigation is asynchronous. Chain actions via callbacks rather than polling.

4. **Don't fight the settings.** All navigation tuning is owned by SentinelNavClient's UI. Your plugin should only manage its own domain-specific settings.

5. **Handle unavailability gracefully.** SentinelNavClient may not be loaded. Always have a fallback or clear error message.
