---
id: 1
title: "[PRD] Dynamic Quest Graph Engine"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest"]
created: "2026-07-15T22:00:00Z"
updated: "2026-07-15T22:00:00Z"
---

# PRD: Dynamic Quest Graph Engine

**Status:** Ready for implementation  
**Labels:** `enhancement`, `ready-for-agent`, `area:quest`  
**Related:** Phase A.2 of Implementation Plan

---

## 1. Problem Statement

The current `sentinel/modules/quest/` module provides basic quest tracking (quest log scanning, gossip interaction, Questie adapter, QueryClient for DB) but **no autonomous quest planning or execution**. It passively tracks state; it doesn't decide *which* quests to do, *in what order*, or *how to optimize travel*.

We need a **graph-driven quest planner** that:
- Builds a DAG from Mangos TBC database (prereqs, chains, breadcrumbs, exclusives)
- Scores available quests dynamically (XP/min, travel, overlap, rewards, risk)
- Clusters objectives spatially to minimize travel
- Generates `QuestPlan` → `QuestPhase[]` executed by BT
- Integrates with existing `NavAdapter`, `VendorStateMachine`, `InventoryAuditor`, `ClassService`

---

## 2. User Stories

| ID | Story | Acceptance |
|----|-------|------------|
| US-1 | As a bot, I want to accept all available quests at a hub, complete their objectives in optimal order, and turn them in — without manual profile scripting. | Bot clears a quest hub (e.g., Goldshire) autonomously. |
| US-2 | As a bot, I want to skip dungeon/elite quests unless in a group, but still complete their lead-up chain. | RFC lead-up quests done; RFC dungeon quest skipped. |
| US-3 | As a bot, I want to cluster "Kill 10 Raptors + Collect 8 Eggs + Escort Hunter" in one area into a single travel loop. | Single trip to raptor area completes all 3 objectives. |
| US-4 | As a bot, I want to auto-select quest rewards by vendor value (default) or upgrade detection (weapons/armor). | No manual reward selection needed. |
| US-5 | As a bot, I want to return to town *before* bags are full / gear broken / reagents empty. | `InventoryAuditor` injects `RETURN_TO_TOWN` phase proactively. |
| US-6 | As a bot, I want to use flight paths and hearthstone optimally. | Travel time minimized via `FlightPathOptimizer` + `HearthstoneOptimizer`. |

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        QuestEngine (Module)                      │
├─────────────────────────────────────────────────────────────────┤
│  QuestGraph       │  QuestScorer      │  ObjectivePlanner       │
│  (DAG from DB)    │  (weights + heur) │  (clustering + seq)     │
├─────────────────────────────────────────────────────────────────┤
│  QuestPlanner → QuestPlan → QuestPhaseExecutor (BT subtree)     │
├─────────────────────────────────────────────────────────────────┤
│  Integrations: NavAdapter, VendorSM, InventoryAuditor, ClassSvc │
└─────────────────────────────────────────────────────────────────┘
```

### New Files

```
sentinel/modules/quest/
├── quest_graph.lua         # DAG builder + traversal
├── quest_scorer.lua        # Scoring weights + heuristics
├── objective_planner.lua   # Spatial clustering + sequencing
├── quest_planner.lua       # Main entry: builds QuestPlan
├── quest_phases.lua        # BT leaf nodes for each phase type
├── npc_interaction.lua     # Multi-service NPC handler
├── reward_selector.lua     # Vendor value + upgrade logic
├── inventory_auditor.lua   # Pre-departure checks + phase injection
├── class_service.lua       # Shared class-specific data
├── rule_engine.lua         # Profile rule evaluation
├── heatmap.lua             # Dynamic spawn density maps
└── flight_optimizer.lua    # Taxi + hearthstone routing
```

### Existing Files Modified

| File | Change |
|------|--------|
| `module.lua` | Initialize new subsystems, wire into update loop |
| `engine.lua` | Add `build_plan()`, `get_active_plan()` |
| `tracker.lua` | Emit `quest:objective_complete` events for planner reactivity |
| `interactions.lua` | Delegate to `npc_interaction.lua` for multi-service |

---

## 4. Core Data Structures

### QuestGraph (DAG)
```lua
QuestGraph = {
  nodes = { [quest_id] = QuestNode },
  edges = { [quest_id] = { requires={}, follows={}, breadcrumbs={}, excludes={} } },
  available = {},  -- filtered by level/race/class/completion
  completed = {},  -- from core.quests.is_quest_flagged_completed()
}

QuestNode = {
  id = 1234,
  title = "Westfall Stew",
  level = 12,
  zone = "Westfall",
  start_npc = {id=234, pos={x,y,z}},
  end_npc = {id=235, pos={x,y,z}},
  objectives = {
    {type="KILL", target_id=123, count=10, spawn_clusters={...}},
    {type="COLLECT", item_id=456, count=8, source_ids={789,790}},
    {type="ESCORT", npc_id=345, waypoints={...}},
  },
  rewards = {xp=1200, money=5000, choices={{item=123, count=1},...}, fixed={...}},
  suggested_players = 1,
  is_elite = false,
  is_dungeon = false,
  prev_quest_id = 1233,
  next_quest_id = 1235,
  next_in_chain = 1235,
  breadcrumb_for = 1236,
  exclusive_group = 0,
}
```

### QuestPlan
```lua
QuestPlan = {
  quest_id = 1234,
  phases = {
    {type="TRAVEL_TO_GIVER", target={x,y,z}, waypoints={...}, constraints={avoid_elites=true}},
    {type="INTERACT_ACCEPT", npc_id=234, quest_id=1234},
    {type="OBJECTIVE_KILL", targets={123}, area={center={x,y,z}, radius=80}, waypoints={...}},
    {type="OBJECTIVE_COLLECT", item_id=456, count=8, sources={789,790}, area={...}},
    {type="TRAVEL_TO_TURNIN", target={x,y,z}, waypoints={...}},
    {type="INTERACT_TURNIN", npc_id=235, quest_id=1234, reward_choice=2},
  },
  current_phase = 1,
  score = 94.5,
  estimated_time_min = 12,
  overlaps = {1235, 1236},  -- other quests sharing objectives
}
```

---

## 5. Seams & Test Points

| Seam | Type | Test Strategy |
|------|------|---------------|
| `QuestGraph.build_from_db()` | Pure function | Unit: feed synthetic DB rows → assert DAG topology |
| `QuestScorer.score(quest, context)` | Pure function | Unit: fixed context → deterministic score |
| `ObjectivePlanner.cluster(objectives)` | Pure function | Unit: synthetic spawn points → clusters match expectation |
| `QuestPlanner.plan(context)` | Integration | Integration: mock QueryClient + NavAdapter → valid QuestPlan |
| `QuestPhaseExecutor.tick(blackboard)` | BT leaf | BT test harness: blackboard in → status out |
| `NPCInteraction.execute_service_queue()` | State machine | Unit: mock gossip API → all services executed in order |
| `RewardSelector.choose(rewards, class)` | Pure function | Unit: fixed rewards → expected choice |
| `InventoryAuditor.audit(plan)` | Pure function | Unit: mock bags → warnings + phase injection |
| `FlightOptimizer.route(origin, dest)` | Integration | Integration: mock NavServer → waypoints valid |

**Highest seam:** `QuestPlanner.plan()` — end-to-end with mocked DB/Nav.

---

## 6. Implementation Phases

### Phase 1: Foundation (Week 1-2)
- [ ] `quest_graph.lua` — DAG builder from QueryClient responses
- [ ] `quest_scorer.lua` — Configurable weights, heuristics (death risk, difficulty)
- [ ] `rule_engine.lua` — Profile YAML → filter/score modifiers
- [ ] Unit tests for graph topology + scoring

### Phase 2: Planning (Week 2-3)
- [ ] `objective_planner.lua` — DBSCAN clustering (eps=50yd, minPts=3)
- [ ] `quest_planner.lua` — Top-K quests → QuestPlan with phases
- [ ] `heatmap.lua` — Dynamic density map from `creature` + `gameobject` spawns
- [ ] Integration test: planner produces valid plan for Westfall

### Phase 3: Execution (Week 3-4)
- [ ] `quest_phases.lua` — BT leaves: `TRAVEL`, `INTERACT`, `OBJECTIVE_KILL`, `OBJECTIVE_COLLECT`, `OBJECTIVE_ESCORT`
- [ ] `npc_interaction.lua` — Service queue: turnin → accept → train → vendor → repair
- [ ] `reward_selector.lua` — Vendor value default + ilvl upgrade for weapons/armor
- [ ] Wire into `module.lua` update loop; emit `quest:plan_ready` event

### Phase 4: Polish (Week 4-5)
- [ ] `inventory_auditor.lua` — Pre-departure audit → inject `RETURN_TO_TOWN`
- [ ] `class_service.lua` — Hunter ammo, Warlock shards, Rogue poisons, Mage food/water
- [ ] `flight_optimizer.lua` — Taxi graph + hearthstone logic
- [ ] Profile YAMLs for 5+ zones (Westfall, Redridge, Duskwood, Loch Modan, Darkshore)
- [ ] E2E test: bot clears Goldshire → Westfall hub autonomously

---

## 7. Configuration (Profile YAML)

```yaml
# sentinel/data/profiles/quests/westfall.yaml
zone: "Westfall"
map_id: 0
level_range: { min: 12, max: 18 }
faction: "Alliance"

rules:
  skip_elites: true
  skip_escort: false
  skip_dungeon_chains: true
  skip_pvp: true
  max_travel_yards: 1800
  min_xp_per_minute: 500
  vendor_threshold_pct: 80
  repair_threshold_pct: 40
  min_bag_slots: 4

scoring:
  xp_per_minute: 0.35
  travel_efficiency: 0.25
  objective_overlap: 0.20
  reward_value: 0.10
  chain_priority: 0.10

objective_strategy: "cluster"
```

---

## 8. Acceptance Criteria (Definition of Done)

1. **Autonomous hub clearing**: Bot enters Goldshire, accepts all available quests, completes objectives in clustered order, turns in all, exits with ≥80% bag space.
2. **Dungeon chain handling**: Lead-up quests for RFC completed; RFC quest skipped; chain continues post-dungeon.
3. **Objective clustering**: "Kill Raptors + Collect Eggs + Escort" in same area → single travel loop.
4. **Reward selection**: Auto-picks highest vendor value; picks weapon/armor upgrade if >5 ilvl.
5. **Inventory awareness**: Returns to town when bags <4 slots, durability <40%, or reagents missing — *before* critical.
6. **Flight/hearth usage**: Uses taxi network when >500yd travel; hearths when >10min walk to bind.
7. **No regressions**: Existing grind/combat/vendor phases unchanged; all existing tests pass.
8. **Profile-driven**: New zone = new YAML only; no Lua changes.

---

## 9. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Quest DB schema mismatch | Medium | High | QueryClient already handles; add integration test |
| NavAdapter pathfinding fails in caves | Medium | Medium | `avoid_elites`/`avoid_water` opts; fallback to direct move |
| Gossip frame timing (race conditions) | Medium | Medium | `npc_interaction` uses state machine with retries |
| Performance: planner runs too often | Low | Medium | Throttle to 5s; only replan on quest log change |
| Mangos DB missing spawn data | Low | High | Heatmap falls back to Questie coordinates |

---

## 10. Rollout Plan

1. **Feature flag**: `module.quest.enabled` (already exists) — default `false`
2. **Canary**: Enable for 1 tester on Westfall profile
3. **Gradual**: Add profiles zone-by-zone
4. **Default on**: Once 10+ zones validated

---

*Generated from grilled design decisions. See `sentinel/docs/adr/0004-dynamic-quest-graph-engine.md` for ADR.*