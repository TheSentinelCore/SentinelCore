---
id: 3
title: "[Quest] QuestScorer — Configurable weights + heuristics"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:1-foundation"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: [2]
---

## Description
Score available quests dynamically using configurable weights and heuristics for death risk, difficulty, travel cost.

## Acceptance Criteria
- [ ] `QuestScorer.score(quest_node, context)` returns numeric score
- [ ] Configurable weights from profile YAML (xp_per_min, travel_efficiency, objective_overlap, reward_value, chain_priority)
- [ ] Heuristic death probability from DB: level_diff, elite_flag, dungeon_zone, cave_indoor, mob_count, class_squishiness
- [ ] Heuristic difficulty score from same factors
- [ ] Travel distance estimated via NavAdapter (cached)
- [ ] Objective overlap bonus computed from shared spawn clusters
- [ ] Follow-up chain value: sum of estimated XP of chained quests
- [ ] Reward value: vendor sell price of choices + fixed reward money
- [ ] Pure function — deterministic given same inputs
- [ ] Unit test: fixed context → deterministic scores for known quest set

## Files to Create
- `sentinel/modules/quest/quest_scorer.lua`

## Dependencies
- #2 QuestGraph (provides QuestNode)
- Profile YAML loading (ProfileManager)