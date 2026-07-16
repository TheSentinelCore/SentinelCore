---
id: 3
title: "[Quest] QuestScorer — Configurable weights + heuristics"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:1-foundation"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
---

## What to build

Implement `QuestScorer` that assigns a numeric score to each available quest based on configurable weights and heuristics.

**End-to-end behavior:** `QuestScorer.score(quest, context)` returns a score. Higher = better. Used by `QuestPlanner` to pick top-K quests.

## Acceptance criteria

- [ ] Default weights from PRD (xp_per_min=0.35, travel=0.25, overlap=0.20, reward=0.10, chain=0.10)
- [ ] Profile YAML overrides weights per zone
- [ ] Heuristics:
  - XP/min: `quest.rewards.xp / estimated_completion_time_min`
  - Travel: distance from player to start_npc + start_npc to end_npc (via NavAdapter estimate)
  - Overlap: count of other available quests sharing objective spawn clusters
  - Reward: max vendor value of choices + fixed rewards
  - Chain: depth in chain (deeper = higher) * followup XP estimate
  - Death risk: heuristic from creature_template (elite, level diff, dungeon zone)
  - Difficulty: suggested_players > 1, elite mobs, cave/indoor
- [ ] `score_all(quests, context)` returns sorted array
- [ ] Pure function — no side effects, deterministic given same input
- [ ] Unit test: fixed context → deterministic scores

## Blocked by

- 002 QuestGraph (needs QuestNode structure)
