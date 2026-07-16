---
id: 12
title: "[Quest] FlightOptimizer — Taxi graph + hearthstone routing"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:4-polish"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: [6]
---

## Description
Computes optimal travel: walk → taxi → walk. Uses hearthstone when bind point closer than walk.

## Acceptance Criteria
- [ ] `route(origin_pos, dest_pos, bb)` → `{mode: "walk"|"taxi"|"hearth", waypoints[], estimated_time_min}`
- [ ] Taxi graph: nodes = taxi master NPCs (from Mangos `creature_template` NPCFlags), edges = known taxi paths
- [ ] Uses NavAdapter for walk segments to/from taxi nodes
- [ ] Hearthstone: if `walk_time(origin, bind_location) > 10min` and hearth off CD → mode="hearth"
- [ ] Integrates with QuestPlanner travel phases
- [ ] Profile config: `use_flight_paths: true`, `hearthstone_threshold_minutes: 5`
- [ ] Falls back to direct walk if taxi unavailable

## Blocked by
- #6 QuestPlanner (consumes route for TRAVEL phases)