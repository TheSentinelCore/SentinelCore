---
id: 8
title: "[Quest] NPCInteraction — Multi-service queue: turnin → accept → train → vendor → repair"
state: closed
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:3-execution"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: [2]
---

## Description
State machine that handles all NPC services in a single gossip frame interaction.

## Acceptance Criteria
- [ ] `build_service_queue(npc_id, blackboard, quest_engine)` → ordered services
- [ ] Order: TURNIN (all completable) → ACCEPT (all available passing filters) → TRAIN (missing spells) → VENDOR (sell/buy/repair)
- [ ] `execute_next(blackboard, nav_adapter)` — drives gossip API: select_quest → complete_quest → get_reward → select_available → accept_quest → trainer_buy → merchant_sell/buy/repair
- [ ] Retries on gossip frame close (re-opens via interact)
- [ ] Delegates VENDOR/REPAIR to existing VendorStateMachine
- [ ] Unit test: mock gossip → all services executed in order

## Blocked By
- #2 QuestGraph (knows which quests at NPC)