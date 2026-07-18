# 006 — Compiler: Dead Code Elimination Pass

**What to build:** Implement a compiler pass that removes quests made obsolete by higher-level alternatives in the same operation:
- For each quest in the operation, check if there exists another quest in the same operation:
  - Same quest giver (or logical equivalent)
  - Same or similar objectives
  - Higher level/reward
  - Given at same or earlier point in the progression
- If found, mark the lower quest as skippable (do not generate acceptance/actions for it)
- Preserve quests that are prerequisites for others (even if obsolete)
- Handle quest chains: if quest A is obsolete but quest B requires A, keep A
- Make decision based purely on DB data (deterministic, no heuristics)
- Ensure removed quests don't break logic for subsequent quests
- Report skipped quests in compilation stats for transparency
- Only remove if the higher quest is actually accepted in the flow (control flow aware)

**Blocked by:** 005 — Compiler Level 2 Pass - Implied Action Insertion

**Status:** ready-for-agent

- [ ] For each quest, find all other quests with same quest giver NPC
- [ ] Compare objectives: same item kills, collections, similar counts
- [ ] Check level comparison: candidate quest level > current quest level
- [ ] Verify reward superiority: better xp, money, items (simple heuristic)
- [ ] Confirm quest giver is encountered earlier or same point in current flow
- [ ] Build prerequisite map from QuestTemplate.PrevQuestId/NextQuestId
- [ ] If quest X is prerequisite for any kept quest, do not mark X as skippable
- [ ] If quest X has unique objective not covered by others, keep it
- [ ] Skip quest by not generating acceptance actions for it
- [ ] Still validate its existence (for DB integrity) but don't emit states for it
- [ ] Add to compilation report: "Skipped 3 obsolete quests: [list]"
- [ ] Make decision purely deterministic based on DB - no randomness
- [ ] Test case: Wool Cloth quests where higher level version makes lower obsolete
- [ ] Test case: quest chains where you must keep prerequisites