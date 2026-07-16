---
id: 11
title: "[Quest] ClassService — Shared class-specific data (reagents, trainer spells, mount levels)"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "phase:4-polish"]
created: "2026-07-15T22:30:00Z"
updated: "2026-07-15T22:30:00Z"
depends_on: []
---

## Description
Single source of truth for class-specific quest/reagent/trainer data. Used by InventoryAuditor, NPCInteraction, RewardSelector.

## Acceptance Criteria
- [ ] `get_quest_requirements(class)` → `{reagent_consumption{}, trainer_frequency, special_needs{}}`
- [ ] Hunter: ammo IDs, pet food IDs, stable=true
- [ ] Warlock: soul_shard IDs, summon_ritual=true
- [ ] Rogue: poison IDs
- [ ] Mage: food/water IDs, teleport/portal rune IDs
- [ ] Priest: food/water IDs
- [ ] Druid: food/water IDs
- [ ] Paladin: food/water IDs
- [ ] Shaman: food/water IDs
- [ ] Warrior: food IDs, weapon_upgrade_frequency="high"
- [ ] `get_missing_reagents(class, bb)` — uses BagScanner
- [ ] `get_trainer_spells(class, level)` — static table of spell_id per level
- [ ] Consumed by InventoryAuditor, NPCInteraction (TRAIN), RewardSelector (upgrade detection)

## Blocked by
None — can start immediately