---
id: 8
title: "Stages 4+5 — Dependency Graph + Goal Coverage"
state: open
labels: ["enhancement", "ready-for-agent", "size:medium"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 08 — Stages 4+5: Dependency Graph + Goal Coverage

**What to build:** Implement the fourth and fifth compiler stages — build and validate the Operation dependency graph, then verify that declared OperationGoals are covered by actions.

**Blocked by:** #5 (compiler scaffold — can run in parallel with #6/#7 since it operates on the authoring Profile, not the resolved IR)

**Acceptance criteria:**

**Stage 4 — Dependency Resolution:**
- [ ] `DependencyGraph` type: nodes are Operations, edges are Requires/UnlocksAfter/ExcludesWith
- [ ] Cycle detection on Requires/UnlocksAfter → hard error with cycle path in diagnostic
- [ ] ExcludesWith conflict detection: two Operations with ExcludesWith that both have matching entry_conditions → hard error
- [ ] Topological sort: Operations ordered by Requires/UnlocksAfter, respecting SoftPrefers tie-breaking, then priority, then declaration order
- [ ] Error codes `C-4xxx` for: cycle detected, ExcludesWith conflict, unreachable Operation (requires an Operation that doesn't exist)

**Stage 5 — Goal Coverage:**
- [ ] For each required `OperationGoal`:
  - `CompleteQuest(id)`: verify PickupQuest + TurnInQuest actions exist in the Operation's action list (or in sub_operations)
  - `CompleteQuestChain(ids)`: verify all quest IDs in the chain are covered
  - `UnlockFlightPath(id)`: verify FlightPath or TalkToNpc action exists that resolves to a flight master
  - `ReachLevel(n)`, `GainXp(n)`, `ReachZone(id)`, `ReachWaypoint(pos)`: informational, pass through or check for matching GoTo
- [ ] Optional goals without actions → warning (not error)
- [ ] Error codes `C-5xxx` for: quest not covered, chain incomplete, flight path not unlocked
- [ ] Unit tests for each goal type: covered → pass, missing → correct diagnostic
- [ ] Test with a 3-Operation profile with dependencies, conflicts, and goals → verify correct ordering and coverage
