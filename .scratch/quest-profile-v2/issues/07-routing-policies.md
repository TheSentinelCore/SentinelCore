---
id: 7
title: "Routing Policies — Declarative Nav Policies + NavClient Integration"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "area:nav", "priority:high", "size:medium"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

# Routing Policies — Declarative Nav Policies + NavClient Integration

## Description

Implement the routing policy system: profiles declare policy names, `NavClient` resolves them to policy objects, calls `NavServer:plan_path(start, goal, policy)`, and follows dynamic waypoints.

## Policy Format (YAML)

```yaml
# sentinel/data/routing_policies/northshire_to_kobolds.yaml
name: "northshire_to_kobolds"
strategy: "smart"              # "smart" | "direct" | "road_only" | "offroad"
preferredPath: "road"          # "road" | "any"
avoid:
  - "elite"
  - "water"
  - "enemyTown"
dynamicReplan: true
allowShortcuts: true
opportunisticKills:
  - "Wolf"
  - "Boar"
opportunisticLoot:
  - "Chest"
  - "QuestObject"
ignore:
  - "Rare"
  - "Elite"
```

## NavClient Integration

```lua
function NavClient:followPolicy(policyName, goal)
  local policy = RoutingPolicyLoader.load(policyName)
  -- Convert policy to NavServer request format
  local request = {
    start = self:GetPlayerPosition(),
    goal = goal,
    policy = {
      strategy = policy.strategy,
      preferred_path_type = policy.preferredPath,
      avoid_zones = self:buildAvoidZones(policy.avoid),
      dynamic_replan = policy.dynamicReplan,
      allow_shortcuts = policy.allowShortcuts,
      opportunistic_kills = policy.opportunisticKills,
      opportunistic_loot = policy.opportunisticLoot,
      ignore_types = policy.ignore
    }
  }
  local path = self:callNavServer("plan_path", request)
  return self:followWaypoints(path)
end
```

## NavServer Contract (Assumed)

`POST /nav/plan_path`:
```json
{
  "start": {"x": 123.4, "y": 456.7, "z": 89.0, "map_id": 0},
  "goal": {"x": 200.0, "y": 500.0, "z": 90.0, "map_id": 0},
  "policy": {
    "strategy": "smart",
    "preferred_path_type": "road",
    "avoid_zones": [{"type": "elite", "radius": 50}],
    "dynamic_replan": true,
    "allow_shortcuts": true,
    "opportunistic_kills": ["Wolf", "Boar"],
    "opportunistic_loot": ["Chest", "QuestObject"],
    "ignore_types": ["Rare", "Elite"]
  }
}
```

Response: `{waypoints: [{"x":..., "y":..., "z":...}], policy_applied: {...}}`

## NavAdapter Events

- `NavigationStarted` — policy name, goal
- `NavigationArrived` — policy name, success
- `NavigationFailed` — policy name, reason
- `NavigationReplanned` — old waypoints, new waypoints

## Acceptance Criteria

- [ ] `RoutingPolicyLoader.load(name)` loads policy YAML, validates schema, caches
- [ ] ProfileCompiler validates policy names against policy files
- [ ] `NavClient:followPolicy(name, goal)` resolves policy → calls NavServer → follows waypoints
- [ ] `NavigationArrived` event published with `{policy="name", success=true}`
- [ ] Dynamic replan works: if blocked, requests new path, continues
- [ ] Opportunistic kills/loot work: combat filter applied during travel
- [ ] Policy avoidance zones respected (elite, water, enemy town)
- [ ] Unit tests: policy load, NavClient integration (mock NavServer), event emission

## Blocked by

- **01-profile-compiler** — needs policy loader for validation
- **03-engine-event-system** — needs `NavigationArrived` event
- NavServer must support policy object (verify API)

## Files to Create

- `sentinel/modules/quest/routing_policy_loader.lua`
- `sentinel/data/routing_policies/*.yaml` (policies for Elwynn)
- Modify `sentinel/integrations/nav_client.lua` — add `followPolicy`
- Modify `sentinel/modules/quest/engine.lua` — wire `NavigationArrived` event