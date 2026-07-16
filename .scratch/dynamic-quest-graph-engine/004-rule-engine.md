---
id: 4
title: "[Quest] RuleEngine — Profile YAML filter/score modifiers"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:1-foundation"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: [2]
---

## Description
Evaluate zone profile rules (skip_elites, max_travel, min_xp_per_min) against quest nodes. Apply scoring modifiers.

## Acceptance Criteria
- [ ] `RuleEngine.evaluate(profile, quest_node, context)` → `{pass: bool, reason: string?}`
- [ ] Hard filters: skip_elites, skip_escort, skip_dungeon_chains, skip_pvp, max_travel_yards, min_xp_per_minute
- [ ] Travel distance uses NavAdapter estimate (cached)
- [ ] XP/min estimate from QuestScorer internals
- [ ] Scoring modifiers: profile.scoring weights applied to QuestScorer
- [ ] `RuleEngine.should_return_to_town(profile, blackboard)` → `{should: bool, reason: string?}`
- [ ] Checks: bag space, durability, reagent thresholds from profile
- [ ] Profile YAML schema validation on load
- [ ] Unit test: profile with skip_elites=true → elite quests rejected

## Files to Create
- `sentinel/modules/quest/rule_engine.lua`

## Dependencies
- #2 QuestGraph
- #3 QuestScorer (for XP/min estimate)
- `modules/grind/profile_manager.lua` (existing — loads quest profiles)