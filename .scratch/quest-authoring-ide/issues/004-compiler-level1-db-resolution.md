# 004 — Compiler: Level 1 Pass - DB Resolution and Validation

**What to build:** Implement the first compiler pass that resolves IDs from the Mangos database and validates references:
- Resolve NPC names → NPC IDs and validate they exist in the correct zone
- Resolve quest names → Quest IDs and validate existence, level/race/class requirements
- Resolve item names → Item IDs and validate existence
- Inject coordinates (x,y,z) for NPCs, items, game objects from creature/gameobject tables
- Validate that referenced entities are appropriate for the project's zone/faction/level
- Add semantic metadata to AST nodes (resolved IDs, coordinates, validation status)
- Handle missing references gracefully with clear error messages
- Optional: fetch quest objectives, prerequisites, rewards for later use

**Blocked by:** 003 — Compiler Parser and AST

**Status:** ready-for-agent

- [ ] Implement NPC lookup: name → creature.id + validation (zone, faction, level)
- [ ] Implement Quest lookup: name → quest_template.entry + validation (level, race, class)
- [ ] Implement Item lookup: name → item.template.entry + validation
- [ ] For NPCs: fetch position_x, position_y, position_z from creature table
- [ ] For GameObjects: fetch position from gameobject table if needed
- [ ] Validate that NPC is in project's zone (creature.zoneId or via spawn lookup)
- [ ] Validate that quest is appropriate for faction/race/class/level range
- [ ] Attach resolved data to AST: npc_id, quest_id, item_id, position_x/y/z
- [ ] Fetch and cache quest objectives (ReqItemId#, ReqCreatureOrGoId#) for Level 2 pass
- [ ] Fetch and cache quest chain info (PrevQuestId, NextQuestId) for dead code elimination
- [ ] Error handling: unknown name, wrong zone, incompatible level/race/class
- [ ] Performance: batch queries where possible, use QueryClient caching
- [ ] Test with sample data from Elwynn Forest (zone 12)