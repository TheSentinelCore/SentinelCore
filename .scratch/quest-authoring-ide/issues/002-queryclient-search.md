# 002 — QueryClient Search Enhancement

**What to build:** Enhance the existing QueryClient to support search operations needed for IDE autocomplete and validation:
- searchQuests(criteria): returns quests matching name/level/zone/faction
- searchNPCs(criteria): returns NPCs matching name/zone
- searchItems(criteria): returns items matching name
- getQuestDetails(questId): enhanced to return prerequisites, objectives, rewards
- getNPCDetails(npcId): enhanced to return location, quests offered, services
- All methods should return Promise-like results via callback (existing async pattern)
- Results should be limited and ranked by relevance
- Cache results with TTL to prevent hammering the server

**Blocked by:** None — can start immediately (uses existing QueryClient pattern)

**Status:** ready-for-agent

- [ ] Add searchQuests method to QueryClient
- [ ] Add searchNPCs method to QueryClient
- [ ] Add searchItems method to QueryClient
- [ ] Enhance getQuestDetails to include prerequisites and objectives
- [ ] Enhance getNPCDetails to include location and services
- [ ] Implement client-side caching with TTL (5 min default)
- [ ] Add rate limiting to prevent abuse
- [ ] Return results sorted by relevance (exact match > prefix > contains)
- [ ] Limit results to 20 items per search for UI responsiveness
- [ ] Handle error cases (network failure, invalid response)
- [ ] Test with Mangos TBC database at Database/tbcmangos.sqlite