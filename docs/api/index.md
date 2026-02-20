---
title: API Reference
layout: default
nav_order: 5
has_children: true
---

# API Reference
{: .no_toc }

Complete API reference for SentinelNavClient's four modules.
{: .fs-6 .fw-300 }

---

## Module Overview

| Module | Layer | Purpose | Access |
|:-------|:------|:--------|:-------|
| [**Client**](/api/client) | Entry point | Wires all modules, movement commands, events, state queries | `_G.SentinelNavClient.client` |
| [**Navigation**](/api/navigation) | Low-level | HTTP client for SentinelNavServer &mdash; 14 async endpoints | `client.nav_client` |
| [**Movement**](/api/movement) | High-level | Path following, stuck recovery, routes, deviation monitoring | `client.movement` |
| [**Obstacle**](/api/obstacle) | Detection | Doodad collision via ray probing, avoidance zone memory | `client.obstacle` |

---

## Where to Start

**For consumers:** Start with [**Client**](/api/client). It wraps everything and is the recommended API. You can move to a destination, plan multi-node routes, listen for events, and query state &mdash; all through the Client.

**For internals/advanced use:** See [Navigation](/api/navigation), [Movement](/api/movement), and [Obstacle](/api/obstacle) for the underlying module APIs. Access them via the [escape hatch](/api/client#escape-hatch) fields on the Client.

---

## Quick Reference

### Movement Commands (Client)

```lua
client:move_to(target, callback?, opts?)     -- Navmesh pathfinding + follow
client:move_direct(target, callback?)        -- Direct movement, no pathfinding
client:follow_path(waypoints, callback?)     -- Follow pre-computed waypoints
client:plan_route(nodes, callback?, opts?)   -- TSP-optimized multi-node route
client:replan(reason?)                       -- Replan active route from current leg
client:validate_destination(target, callback) -- Check reachability without moving
client:stop()                                -- Stop all movement, reset to idle
client:destroy()                             -- Full cleanup
```

### State Queries (Client)

```lua
client:get_state()           -- "idle"|"requesting_path"|"moving"|"stuck"|"arrived"|"failed"
client:is_moving()           -- true if "moving" or "requesting_path"
client:get_destination()     -- vec3|nil
client:get_current_path()    -- vec3[]|nil
client:get_path_index()      -- current waypoint index
client:get_progress()        -- detailed progress table
client:get_corridor_widths() -- corridor width data (indoor only)
```

### Server Queries (Client)

```lua
client:is_server_available()                   -- boolean
client:health_check(callback)                  -- server health
client:get_height(pos, callback)               -- navmesh Z at position
client:get_player_height(callback)             -- navmesh Z at player
client:get_all_heights(pos, callback, opts?)   -- multi-level heights
client:get_player_all_heights(callback, opts?) -- multi-level at player
```

### Events (Client)

```lua
client:on("state_change", function(data) end) -- data.from, data.to
client:on("arrived", function() end)
client:on("stuck", function() end)
client:on("failed", function() end)
client:off(event, callback)                   -- unsubscribe (same function ref)
```

### Navigation Endpoints (via escape hatch)

```lua
nav:find_path(start, dest, callback, opts?)
nav:find_path_corridor(start, dest, callback, opts?)
nav:find_path_avoid(start, dest, zones, callback, opts?)
nav:find_route_tsp(nodes, callback, opts?)
nav:find_route_multi(stops, callback, opts?)
nav:check_path(pos, waypoints, callback, opts?)
nav:raycast(start, dest, callback, opts?)
nav:get_height(pos, callback, opts?)
nav:get_all_heights(pos, callback, opts?)
nav:random_point(callback, opts?)
nav:flee(player_pos, threats, callback, opts?)
nav:kite(player_pos, target_pos, callback, opts?)
nav:health_check(callback)
```
