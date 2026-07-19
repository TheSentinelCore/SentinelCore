---
id: 6
title: "Stage 2 — Reference Resolution"
state: open
labels: ["enhancement", "ready-for-agent", "size:medium"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 06 — Stage 2: Reference Resolution

**What to build:** Implement the second compiler stage — resolve every NpcReference, QuestReference, CreatureReference, and GameObjectReference against the QueryServer, embedding fully-resolved data into the intermediate representation.

**Blocked by:** #5 (compiler scaffold + Stage 1)

**Acceptance criteria:**

- [ ] Stage 2 runs after Stage 1 succeeds (no errors)
- [ ] Every `NpcReference` in the profile is resolved: name, entry_id, position, roles, faction verified against QueryServer `/api/v1/npcs/{entry_id}`
- [ ] Every `QuestReference` is resolved: title, level, objectives, giver, turnin NPC, chain dependencies via `/api/v1/quests/{quest_id}`
- [ ] Every `CreatureReference` is resolved: creature entry, spawn positions, faction via `/api/v1/creatures/{entry_id}`
- [ ] Every `GameObjectReference` is resolved: game object entry, position via appropriate endpoint
- [ ] `ResolutionCache` implemented: keyed on `(entry_id, db_version)`, avoids redundant QueryServer calls for same entity
- [ ] Resolution results stored in an intermediate IR type (e.g., `ResolvedAction` wrapping `Action` + resolved entity data)
- [ ] Error codes `C-2xxx` for: NPC not found, Quest not found, Creature not found, GameObject not found, QueryServer unreachable
- [ ] Unit tests with mock QueryClient: resolve valid references → success, resolve invalid reference → correct diagnostic
- [ ] Integration test: compile a profile with real NPC/quest references → verify resolved data contains correct positions and roles
