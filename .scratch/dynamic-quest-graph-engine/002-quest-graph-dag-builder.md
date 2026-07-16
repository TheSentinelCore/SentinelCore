---
id: 2
title: "[Quest] QuestGraph — DAG builder from Mangos DB"
state: closed
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:1-foundation"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: []
---

## Description
Build the QuestGraph DAG from Mangos TBC database via QueryClient. Nodes = quests, edges = prerequisites/follows/breadcrumbs/exclusives.

## Acceptance Criteria
- [ ] `QuestGraph.build_from_db(zone, level_range)` returns populated graph
- [ ] Nodes contain: id, title, level, zone, start_npc, end_npc, objectives[], rewards, suggested_players, prev/next/in_chain/breadcrumb/exclusive_group
- [ ] Edges: `requires` (PrevQuestId), `follows` (NextQuestId), `continues` (NextQuestInChain), `breadcrumbs` (BreadcrumbForQuestId), `excludes` (ExclusiveGroup > 0)
- [ ] Filter by race/class/level at build time using `RequiredClasses`, `RequiredRaces`, `MinLevel`, `MaxLevel`, `QuestLevel`
- [ ] Track completed quests via `core.quests.is_quest_flagged_completed(quest_id)` on session start
- [ ] Unit test: synthetic DB rows → assert DAG topology (diamond, chain, breadcrumb, exclusive)

## Files to Create
- `sentinel/modules/quest/quest_graph.lua`

## Dependencies
- `modules/quest/query_client.lua` (existing)
- `modules/quest/engine.lua` (existing — add `get_quest_graph()`)