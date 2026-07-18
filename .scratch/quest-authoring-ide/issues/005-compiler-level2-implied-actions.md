# 005 — Compiler: Level 2 Pass - Implied Action Insertion

**What to build:** Implement the second compiler pass that inserts implied actions based on semantic analysis:
- After a Kill action: if the quest requires items, insert Loot action for those items
- After a Pickup/Accept action: if the quest auto-completes or has a turn-in step, insert TurnIn
- After a Vendor action: if average party durability < threshold, insert Repair action
- After a Travel action involving flight/zeppelin/boat: insert appropriate Wait time
- After accepting a quest that starts an escort: investigate if Escort action needed
- When looting is enabled but no loot expected: potentially add Fish or similar if appropriate
- Ensure inserted actions have proper parameter inheritance (NPC, item IDs, etc.)
- Mark inserted actions as compiler-generated in _debug fields for transparency
- Do not insert actions if user already placed them explicitly (avoid duplication)

**Blocked by:** 004 — Compiler Level 1 Pass - DB Resolution and Validation

**Status:** ready-for-agent

- [ ] Analyze quest objectives to determine required items (ReqItemId# > 0)
- [ ] After KillTarget action: if quest requires items, insert Loot action for those items
- [ ] After AcceptQuest/PickupQuest: check if quest has auto-complete or turn-in needed
- [ ] For quest turn-in: insert TurnIn action with same NPC as acceptor (or look up from DB)
- [ ] After Vendor: if equipment durability < variables.durability_threshold, insert Repair
- [ ] After Travel: if using flight path, estimate and insert Wait for flight time
- [ ] After Travel: if using zeppelin/boat, insert Wait for travel time
- [ ] When processing Collect action: if item is fished, consider adding appropriate Wait
- [ ] Ensure inherited parameters: e.g., Loot action gets quest's required items
- [ ] Tag compiler-generated actions: _debug.generated_by = "level2_implied"
- [ ] Prevent duplication: if user already placed a similar action, skip insertion
- [ ] Handle edge cases: quests with multiple item requirements, choice rewards
- [ ] Test with sample quests: "Give Gerard a Drink" (no loot needed), "Kobold Candles" (loot needed)