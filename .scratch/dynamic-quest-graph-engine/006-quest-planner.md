---
id: 6
title: "[Quest] QuestPlanner — Top-K selection → QuestPlan"
state: closed
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:2-planning"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
---

## What to build

`QuestPlanner` ties graph, scorer, and objective planner together to produce a `QuestPlan` with phases.

**End-to-end behavior:** `QuestPlanner.plan(context)` returns `QuestPlan` ready for BT execution. Replans on quest log change.

## Acceptance criteria

- [ ] `plan(context)` — gets available quests from QuestGraph, scores via QuestScorer, filters via RuleEngine
- [ ] Selects top-K (configurable, default 5) by score
- [ ] For each quest, builds phases via ObjectivePlanner
- [ ] Merges overlapping phases across quests (shared travel)
- [ ] Outputs `QuestPlan` with phases array, current_phase index, total score, estimated_time
- [ ] Emits `quest:plan_ready` event on blackboard
- [ ] Throttles replanning to 5s; only replans on `QUEST_LOG_UPDATE`
- [ ] Integration test: Westfall profile → valid plan for Goldshire hub

## Blocked by

- 002 QuestGraph
- 003 QuestScorer
- 004 RuleEngine
- 005 ObjectivePlanner
