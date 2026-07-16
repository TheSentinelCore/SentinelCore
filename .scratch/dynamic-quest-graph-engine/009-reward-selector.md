---
id: 9
title: "[Quest] RewardSelector — Vendor value default + ilvl upgrade for weapons/armor"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:3-execution"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: [2]
---

## Description
Chooses quest reward automatically based on configurable policy.

## Acceptance Criteria
- [ ] Default policy: max vendor sell price (copper)
- [ ] Upgrade policy for Weapon/Armor: if reward ilvl > equipped ilvl + 5 → pick upgrade
- [ ] Policy per item class configurable in profile: `vendor_value` | `upgrade` | `keep`
- [ ] `choose(rewards, class, blackboard)` → reward_index
- [ ] Uses `core.quests.get_quest_item_link("choice", index)` for item data
- [ ] Never auto-picks Quest items (keeps for turnin)
- [ ] Unit test: fixed rewards → expected choice

## Blocked By
- #2 QuestGraph (reward data structure)