---
id: 10
title: "[Quest] InventoryAuditor — Pre-departure audit + RETURN_TO_TOWN phase injection"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:4-polish"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: [7, 12]
---

## Description
Checks bags/consumables/reagents before leaving town. Injects town return phase if critical.

## Acceptance Criteria
- [ ] `audit(blackboard, quest_plan)` → report with warnings/critical flag
- [ ] Checks: bag slots, food/water/potion stacks, durability %, class reagents
- [ ] Class reagents: Hunter ammo+pet_food, Warlock shards, Rogue poisons, Mage food/water/runes
- [ ] Quest plan lookahead: upcoming COLLECT objectives → verify bag space for required items
- [ ] `inject_town_phase(plan, report)` → prepends RETURN_TO_TOWN with services={VENDOR,REPAIR,MAIL,TRAIN}
- [ ] Called by QuestPlanner before finalizing plan
- [ ] Uses existing BagScanner, ConsumableIds, DurabilityTracker, ClassService

## Blocked By
- #7 QuestPhases (RETURN_TO_TOWN phase type)
- #12 ClassService (reagent lists)