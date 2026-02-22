# Mode Objective Queues

SentinelCore now exposes a shared objective layer on top of the combat kernel.

All modes (`grind`, `quest`, `gather`, `bg`) can consume waypoint objective queues:

- `objective.<mode>.queue`
- `objective.<mode>.queue_index`
- `objective.<mode>.loop`

## Client API

Use the client helpers to configure queues at runtime:

```lua
local client = _G.SentinelCore and _G.SentinelCore.get_client and _G.SentinelCore:get_client()
if client then
    client:set_mode_objective_queue("quest", {
        { x = -2550.2, y = 6978.4, z = -0.8, label = "Quest Hub" },
        { x = -2528.0, y = 7012.1, z = -1.0, label = "Kill Zone A" },
    }, { loop = false })
end
```

Read/clear queue state:

```lua
local queue, meta = client:get_mode_objective_queue("quest")
client:clear_mode_objective_queue("quest")
```

`meta` includes:

- `index`: next waypoint index
- `loop`: whether queue loops after last waypoint

## Behavior

- Objective branch is shared across all modes through `CombatKernelTree`.
- Active combat always takes priority over objective execution.
- Objectives run only out of combat.
- Waypoint objectives use navigation reissue + timeout guards and emit objective events.

## Event Stream

- `objective.selected`
- `objective.progress`
- `objective.completed`
- `objective.failed`

These feed runtime logs/telemetry and are visible in the Runtime tab.
