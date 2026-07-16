---
id: 13
title: "[Quest] Zone Profiles — YAML configs for 5+ starter zones"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:4-polish"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: [4]
---

## Description
Create profile YAMLs for initial zones. Each profile defines rules, scoring weights, and strategy.

## Acceptance Criteria
- [ ] `sentinel/data/profiles/quests/westfall.yaml` (Alliance 12-18)
- [ ] `sentinel/data/profiles/quests/redridge.yaml` (Alliance 18-22)
- [ ] `sentinel/data/profiles/quests/duskwood.yaml` (Alliance 22-26)
- [ ] `sentinel/data/profiles/quests/loch_modan.yaml` (Alliance 12-18)
- [ ] `sentinel/data/profiles/quests/darkshore.yaml` (Alliance 12-18)
- [ ] `sentinel/data/profiles/quests/default.yaml` (fallback)
- [ ] Each profile: zone, map_id, level_range, faction, rules{}, scoring{}, objective_strategy
- [ ] ProfileManager loads by zone/level/faction
- [ ] E2E test: bot clears Goldshire → Westfall hub autonomously

## Blocked by
- #4 RuleEngine (loads and evaluates profiles)