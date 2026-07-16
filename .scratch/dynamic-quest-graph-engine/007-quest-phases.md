---
id: 7
title: "[Quest] QuestPhases — BT leaves for TRAVEL, INTERACT, OBJECTIVE_KILL, OBJECTIVE_COLLECT, OBJECTIVE_ESCORT"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:3-execution"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: [2, 5, 6]
---

## Description
BT leaf nodes that execute each QuestPlan phase type. Wired into GrindTree as new priority branches.

## Acceptance Criteria
- [ ] `TRAVEL_TO_GIVER/TO_TURNIN` — calls NavAdapter.move_to(waypoints), succeeds on arrival
- [ ] `INTERACT_ACCEPT/TURNIN` — delegates to NPCInteraction service queue
- [ ] `OBJECTIVE_KILL` — sets target filter for quest mobs, integrates with Acquire/Combat phases
- [ ] `OBJECTIVE_COLLECT` — tracks item count, navigates to spawn clusters from ObjectivePlanner
- [ ] `OBJECTIVE_ESCORT` — follows escort NPC via waypoints, handles combat during escort
- [ ] Each phase: success → advances QuestPlan.current_phase; failure → retry or replan
- [ ] Emits `quest:phase_complete` event for telemetry
- [ ] Unit test: mock blackboard → phase returns SUCCESS/FAILURE/RUNNING correctly

## Blocked By
- #2 QuestGraph (phase data structures)
- #5 ObjectivePlanner (waypoints/clusters)
- #6 QuestPlan (phase sequence)