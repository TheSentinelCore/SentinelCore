---
id: 4
title: "[Quest] RuleEngine — Profile YAML evaluation"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:1-foundation"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
---

## What to build

`RuleEngine` evaluates profile rules against quests and player state to filter/modify scores.

**End-to-end behavior:** `RuleEngine.filter_quests(quests, profile, context)` → filtered list. `RuleEngine.should_town(profile, blackboard)` → bool + reason.

## Acceptance criteria

- [ ] Loads profile YAML from `sentinel/data/profiles/quests/{zone}.yaml`
- [ ] Hard filters: skip_elites, skip_escort, skip_dungeon_chains, skip_pvp, max_travel_yards, min_xp_per_minute
- [ ] Resource thresholds: vendor_threshold_pct, repair_threshold_pct, min_bag_slots
- [ ] Scoring weight overrides from profile.scoring
- [ ] `evaluate(quest, context)` returns {pass: bool, reason: string}
- [ ] `should_town(blackboard)` checks bag space, durability, reagents → {town_needed: bool, reason: string}
- [ ] Profile fallback to `default.yaml` if zone-specific missing
- [ ] Unit test: profile rules correctly filter synthetic quests

## Blocked by

None — can start immediately
