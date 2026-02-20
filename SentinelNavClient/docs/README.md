# SentinelNavClient

SentinelNavClient is a standalone Sylvannas plugin that provides shared navigation for consumer plugins (for example SentinelGather, BgBuddy) through a single global client instance.

It owns:

- Pathfinding integration with SentinelNavServer
- Runtime movement behavior (HSM + BT)
- Obstacle probing and avoidance-zone memory
- In-game settings UI and visualization

## Requirements

- SentinelNavServer running and reachable
- Sylvannas plugin loader

## Consumer Quick Start

```lua
if not (_G.SentinelNavClient and _G.SentinelNavClient.client) then
    core.log_error("SentinelNavClient unavailable")
    return
end

local client = _G.SentinelNavClient.client

client:move_to({ x = -8900, y = 560, z = 94 }, function(ok, reason)
    if ok then
        core.log("Arrived")
    else
        core.log_error("Nav failed: " .. tostring(reason))
    end
end)
```

## Public Global API

Exported by `SentinelNavClient/main.lua`:

- `_G.SentinelNavClient.client` (live getter, shared singleton)
- `_G.SentinelNavClient.create(config?)` (returns same shared client, config ignored)
- `_G.SentinelNavClient.ui`
- `_G.SentinelNavClient.JSON`
- `_G.SentinelNavClient.Helpers`
- `_G.SentinelNavClient.VERSION`

Not exported anymore:

- `_G.SentinelNavClient.create_ui(...)`
- `_G.SentinelNavClient.Navigation`
- `_G.SentinelNavClient.Movement`
- `_G.SentinelNavClient.Obstacle`

## Architecture (Current)

```text
main.lua
  -> init.lua singleton
  -> shared Client
      -> EventBus
      -> Blackboard
      -> ConsoleLogger
      -> StateMachine
      -> Sensors
      -> Services:
         - NavigationService
         - MovementService
         - ObstacleService
         - PathValidationService
      -> Behavior Trees:
         - NavigationTree
         - StuckRecoveryTree
```

## Update and Settings Ownership

- SentinelNavClient calls `client:update()` from its own `on_update`.
- SentinelNavClient UI syncs config every render frame through `client:update_config(...)`.
- Consumers should treat SentinelNavClient as the owner of nav tuning values.

Practical guidance:

1. Do not call `client:update()` in consumer plugins.
2. Do not rely on consumer-side `client:update_config(...)` for persistent tuning.
3. Keep consumer settings domain-specific (gather logic, combat logic, routing strategy, etc.).

## Stable Consumer Surface

Primary methods consumers should use:

- `move_to`, `move_direct`, `follow_path`, `start_route`, `stop`
- `validate_destination`, `health_check`
- `get_state`, `get_full_state`, `is_moving`, `get_progress`, `get_route_progress`
- `on/off` (legacy events) or `get_event_bus()` (new event model)

State model:

- Top-level: `idle`, `navigating`, `arrived`, `failed`
- Detailed: `get_full_state()` (for example `navigating.recovering.strafing`)

## Docs Map

- `docs/API.md`: canonical API + architecture + migration guide

Read `API.md` for:

- Full Client method signatures and callback contracts
- Event list (declared vs currently emitted)
- Service-level escape-hatch APIs
- Configuration defaults
- Migration notes from pre-refactor builds
- Consumer cookbook patterns (validate-then-move, route plan + execute, event lifecycle)

## Migration Summary

If you are upgrading from older SentinelNavClient builds:

1. Remove usage of `_G.SentinelNavClient.Navigation/Movement/Obstacle`.
2. Stop calling `_G.SentinelNavClient.create_ui(...)`.
3. Update any code expecting old states (`requesting_path`, `moving`, `stuck`) to the new HSM model.
4. Use `start_route(...)` for route execution callbacks/events (`leg_complete`, `route_complete`).
5. Update any code expecting legacy `get_progress()` fields (`path_index`, `path_count`, route legs).

## Support Boundary

The recommended compatibility boundary is the `Client` API documented in `API.md`.

Direct service access (`client.nav_client`, `client.movement`, `client.obstacle`, blackboard keys) is available for advanced use, but is lower-level and may evolve faster than the stable consumer surface.
