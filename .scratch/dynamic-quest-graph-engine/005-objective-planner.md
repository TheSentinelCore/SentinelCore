---
id: 5
title: "[Quest] ObjectivePlanner — DBSCAN spatial clustering"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:2-planning"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
---

## What to build

`ObjectivePlanner` clusters quest objectives by spawn location using DBSCAN, then sequences clusters for minimal travel.

**End-to-end behavior:** Given active quests with objectives, returns ordered clusters → each cluster has waypoints covering all objectives in that area.

## Acceptance criteria

- [ ] `cluster_objectives(objectives, eps=50, min_pts=3)` — DBSCAN on spawn positions from Mangos `creature` + `gameobject` tables
- [ ] Each cluster: {center, radius, objectives[], spawn_ids[], waypoints[]}
- [ ] `sequence_clusters(clusters, start_pos)` — nearest-neighbor or TSP approximation
- [ ] `plan_routes(clusters, nav_adapter)` — calls NavAdapter.plan_route for inter-cluster travel
- [ ] Strategy modes: "cluster" (default), "minimize_travel", "maximize_overlap"
- [ ] Falls back to Questie coordinates if Mangos spawn data missing
- [ ] Unit test: synthetic spawn points → correct clusters + sequence

## Blocked by

- 002 QuestGraph (needs objectives with spawn data)
- 003 QuestScorer (needs scored quests to plan)
