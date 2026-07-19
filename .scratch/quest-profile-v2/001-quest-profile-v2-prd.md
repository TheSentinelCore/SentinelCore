---
id: 1
title: "Quest Profile v2 — Hand-Authored Declarative Profiles with Event-Driven Statechart Executor"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:high", "size:large"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

# PRD: Quest Profile v2 — Hand-Authored Declarative Profiles

## Context

The current quest module auto-generates leveling plans using `QuestPlanner`, `QuestScorer`, `RuleEngine`, and `ObjectivePlanner` — querying the Mangos database and Questie for available quests, scoring them, and building waypoint-based execution plans. This approach cannot capture the strategic optimizations that make commercial guides (Zygor, RestedXP) superior:

- "Accept this quest now but don't do it until later"
- "Kill wolves while traveling because you'll need hides later"
- "Skip this cave until level 14 because of respawns"
- "Die intentionally to spirit rez"
- "Don't pick up this breadcrumb because it clutters the log"
- "Leave one objective unfinished until another quest overlaps"

These are **strategic decisions**, not pathfinding outputs.

## Decision

**Big Bang migration** to **hand-authored declarative profiles** executed by an **event-driven hierarchical statechart** (SCXML-inspired). Profiles describe *intent* (objective groups, conditions, routing policies); the execution engine handles low-level details via Sylvannas APIs.

This replaces the entire planning layer (`QuestPlanner`, `ObjectivePlanner`, `QuestScorer`, `RuleEngine`, `QuestProfileManager`, `QuestGraph` graph-building) in one cutover. Infrastructure that survives: `NavAdapter`, `QueryClient`, `QuestieAdapter`, `Tracker`, `Heatmap`, `FlightOptimizer`, `RewardSelector`.

**Architecture documented in:** `sentinel/docs/adr/0004-event-driven-profile-statechart.md`  
**Domain glossary updated in:** `sentinel/CONTEXT.md` (see "Quest Profile Concepts")

---

## Scope

### In Scope

1. **Profile DSL** — YAML authoring format with expression guards/actions
2. **Profile Compiler** — Parses YAML → validates → compiles guards/actions to Lua bytecode → emits `CompiledProfile`
3. **StatechartExecutor** — Runtime that loads `CompiledProfile`, manages active state stack, evaluates guards on events, schedules async actions
4. **Event System** — Engine publishes 20+ game events (`QuestAccepted`, `InventoryChanged`, `PlayerDied`, etc.); profiles subscribe via transitions
5. **Routing Policies** — Declarative nav policies (not waypoints); resolved at runtime via `SentinelNavServer`
6. **Action Registry** — Hybrid: core actions = engine methods; profile actions = inline Lua compiled per-profile
7. **QuestRegistry** — On-demand query + LRU cache (no full DB preload)
8. **In-Game Editor MVP** — YAML editor + validator + hot-reload (graph editor deferred)
9. **First Profile** — Alliance Human 1-10 Elwynn Forest (`alliance_human_01_10_elwynn.yaml`)

### Out of Scope (Deferred)

- Visual node-graph editor (Tier 2+)
- Map overlay with polygon drawing (Tier 3+)
- Quest browser / dependency graph visualizer (Tier 2+)
- Simulator / Monte Carlo optimizer
- Route policy visual editor
- Horde profiles, other zones, other expansions

---

## Technical Design

### Profile Structure (YAML)

```yaml
schemaVersion: "2.0"
profile:
  id: "alliance_human_01_10_elwynn"
  name: "Human 1-10 Elwynn Forest"
  author: "Sentinel"
  expansion: "TBC"
  faction: "Alliance"
  race: ["Human"]
  class: ["*"]
  levelRange: {min: 1, max: 10}

variables:
  playerLevel: {type: "number", bind: "player.level"}
  bagSlotsFree: {type: "number", bind: "inventory.freeSlots"}
  durabilityPct: {type: "number", bind: "equipment.lowestDurabilityPct"}
  activeQuest: {type: "number", init: null}
  phase: {type: "string", init: "northshire"}
  hearthstoneBound: {type: "boolean", init: false}

states:
  Questing:
    type: "exclusive"
    initial: "Initialize"
    states:
      Initialize:
        type: "atomic"
        onEnter: ["log('Profile starting')"]
        transitions:
          - event: "ProfileStart"
            target: "AcceptNorthshireQuests"

      AcceptNorthshireQuests:
        type: "atomic"
        onEnter:
          - "acceptAllAvailableQuests(npcId=197)"
          - "profile.activeQuest = 783"
        transitions:
          - event: "QuestAccepted"
            guard: "event.questId == 783"
            target: "TravelToKoboldCamp"
            actions: ["profile.phase = 'kobolds'"]

      TravelToKoboldCamp:
        type: "atomic"
        onEnter:
          - "nav.followPolicy('northshire_to_kobolds')"
        transitions:
          - event: "NavigationArrived"
            guard: "event.policy == 'northshire_to_kobolds'"
            target: "KillKobolds"

      KillKobolds:
        type: "atomic"
        onEnter:
          - "combat.setTargetFilter({80, 257})"
        transitions:
          - event: "ObjectiveProgress"
            guard: "event.questId == 783 and event.current >= 10"
            target: "TurnInNorthshire"
        onExit:
          - "combat.clearTargetFilter()"

      TurnInNorthshire:
        type: "atomic"
        onEnter:
          - "nav.followPolicy('kobolds_to_northshire')"
        transitions:
          - event: "NavigationArrived"
            guard: "event.policy == 'kobolds_to_northshire'"
            target: "AcceptNorthshireQuests"
            actions: ["turnInQuest(questId=783)"]

      Finished:
        type: "final"
        onEnter: ["log('Profile complete')"]

  Survival:
    type: "parallel"
    regions:
      HealthManagement:
        type: "exclusive"
        initial: "Healthy"
        states:
          Healthy:
            transitions:
              - event: "HealthChanged"
                guard: "event.pct < 40"
                target: "Eating"
          Eating:
            onEnter: ["consume.useFood()"]
            transitions:
              - event: "HealthChanged"
                guard: "event.pct >= 85"
                target: "Healthy"
            onExit: ["consume.stop()"]
      Combat:
        type: "exclusive"
        initial: "Idle"
        states:
          Idle:
            transitions:
              - event: "CombatStart"
                target: "Fighting"
          Fighting:
            onEnter: ["combat.engage()"]
            transitions:
              - event: "CombatEnd"
                target: "Looting"
          Looting:
            onEnter: ["loot.lootAll()"]
            transitions:
              - event: "LootComplete"
                target: "Idle"

  Logistics:
    type: "parallel"
    regions:
      Inventory:
        type: "exclusive"
        initial: "Normal"
        states:
          Normal:
            transitions:
              - event: "InventoryChanged"
                guard: "event.freeSlots <= 4"
                target: "Vending"
          Vending:
            onEnter: ["nav.followPolicy('to_nearest_vendor')"]
            transitions:
              - event: "NavigationArrived"
                target: "Selling"
              - event: "InventoryChanged"
                guard: "event.freeSlots > 10"
                target: "Normal"
          Selling:
            onEnter: ["vendor.sellJunk()"]
            transitions:
              - event: "VendorDone"
                target: "Normal"

actions:
  acceptAllAvailableQuests: "engine:acceptAllQuestsAtNpc(npcId)"
  turnInQuest: "engine:turnInQuest(questId)"
  log: "core:log(msg)"
```

### State Hierarchy

```
QuestProfile (parallel)
├── Questing (exclusive)           -- Main quest flow
│   ├── Initialize
│   ├── AcceptQuests
│   ├── TravelToObjective
│   ├── CompleteObjectives
│   ├── TurnInQuests
│   └── Finished
├── Survival (parallel)            -- Always active
│   ├── HealthManagement (exclusive)
│   │   ├── Healthy
│   │   ├── Eating
│   │   ├── Drinking
│   │   └── Bandaging
│   ├── Combat (exclusive)
│   │   ├── Idle
│   │   ├── Pulling
│   │   ├── Fighting
│   │   └── Looting
│   └── Safety (exclusive)
│       ├── Safe
│       ├── Fleeing
│       └── CorpseRecovery
└── Logistics (parallel)           -- Always active
    ├── Inventory (exclusive)
    │   ├── Normal
    │   ├── Vending
    │   └── Mailing
    ├── Equipment (exclusive)
    │   ├── Good
    │   └── Repairing
    └── Travel (exclusive)
        ├── Mounted
        ├── Walking
        └── Flying
```

### Event Catalog (Engine → Profile)

| Event | Payload |
|-------|---------|
| `QuestAccepted` | `{questId, title}` |
| `QuestCompleted` | `{questId}` |
| `QuestTurnedIn` | `{questId, rewardChoice}` |
| `QuestFailed` | `{questId, reason}` |
| `ObjectiveProgress` | `{questId, objectiveIndex, current, required}` |
| `InventoryChanged` | `{freeSlots, totalSlots}` |
| `DurabilityChanged` | `{slot, current, max}` |
| `PlayerDied` | `{mapId, x, y, z}` |
| `PlayerResurrected` | `{mapId, x, y, z}` |
| `CombatStart` | `{targetGUID}` |
| `CombatEnd` | `{targetGUID}` |
| `LootReady` | `{targetGUID, items[]}` |
| `LevelUp` | `{newLevel}` |
| `SkillUp` | `{skill, newValue}` |
| `ReputationChanged` | `{faction, standing}` |
| `ZoneChanged` | `{newZone, newMapId}` |
| `HearthstoneReady` | `{cooldownRemaining}` |
| `FlightPathDiscovered` | `{nodeId, name}` |
| `RareSeen` | `{npcId, name, x, y, z}` |
| `EliteSeen` | `{npcId, name, x, y, z}` |
| `PlayerNearby` | `{name, distance, isGM}` |
| `Stuck` | `{x, y, z, duration}` |
| `ProfileEvent:<custom>` | `{...}` |

### Routing Policies (Referenced by Name)

```yaml
# routing_policies/northshire_to_kobolds.yaml
name: "northshire_to_kobolds"
strategy: "smart"
preferredPath: "road"
avoid: ["elite", "water", "enemyTown"]
dynamicReplan: true
allowShortcuts: true
opportunisticKills: ["Wolf", "Boar"]
opportunisticLoot: ["Chest", "QuestObject"]
ignore: ["Rare", "Elite"]
```

Profile: `nav.followPolicy('northshire_to_kobolds')` → `NavClient` resolves policy → calls `NavServer:plan_path(start, goal, policy)` → follows dynamic waypoints.

### Action Registry

**Core actions** (engine methods, globally registered):
- `nav.followPolicy(name)`
- `combat.setTargetFilter(npcIds)`
- `combat.clearTargetFilter()`
- `combat.engage()`
- `consume.useFood()`
- `consume.stop()`
- `vendor.sellJunk()`
- `loot.lootAll()`
- `engine:acceptAllQuestsAtNpc(npcId)`
- `engine:turnInQuest(questId)`
- `engine:selectBestReward(questId, class)`

**Profile actions** (inline Lua in YAML, compiled to bytecode per-profile):
```yaml
actions:
  acceptNorthshireQuests: |
    local npcId = 197
    local quests = engine:getAvailableQuestsAtNpc(npcId)
    for _, q in ipairs(quests) do
      engine:acceptQuest(q.id)
      ctx:awaitEvent("QuestAccepted", {questId = q.id}, 5000)
    end
    return true
```

---

## Implementation Plan

### Phase 1: Core Runtime (Foundation)

| Task | Description | Module |
|------|-------------|--------|
| 1.1 | `ProfileCompiler` module — YAML parsing, schema validation, guard/action compilation to bytecode | `sentinel/modules/quest/profile_compiler.lua` |
| 1.2 | `StatechartExecutor` — active state stack, event loop, guard evaluation, transition execution, history states | `sentinel/modules/quest/statechart_executor.lua` |
| 1.3 | `ProfileExecutionContext` — provides `engine`, `nav`, `combat`, `consume`, `vendor`, `loot`, `profile`, `bb`, `ctx:awaitEvent()`, `ctx:callAction()` | `sentinel/modules/quest/profile_context.lua` |
| 1.4 | Event publishing in engine — hook quest log, inventory, combat, health, death, zone events → publish to executor | Modify `sentinel/modules/quest/engine.lua` |
| 1.5 | `QuestRegistry` — on-demand `QueryClient` cache with LRU + TTL | `sentinel/modules/quest/quest_registry.lua` |

### Phase 2: Engine Integration

| Task | Description |
|------|-------------|
| 2.1 | Replace `QuestProfileManager` with `ProfileLoader` (loads compiled profiles) |
| 2.2 | Replace `QuestPlanner` + `ObjectivePlanner` with `ProfileExecutor` (wraps `StatechartExecutor`) |
| 2.3 | Wire `PhaseRunner` → `StepExecutors` for core actions (travel, kill, collect, interact, vendor, repair, train, fly, grind, recover) |
| 2.4 | Remove deleted modules: `QuestPlanner`, `ObjectivePlanner`, `QuestScorer`, `RuleEngine`, `QuestProfileManager`, `QuestGraph` (graph-building logic) |
| 2.5 | Repurpose `Engine` → `PhaseRunner` (executes steps, no planning) |
| 2.6 | Repurpose `QuestPhases` → `StepExecutors` (one per step type) |

### Phase 3: First Profile & Validation

| Task | Description |
|------|-------------|
| 3.1 | Write `alliance_human_01_10_elwynn.yaml` (Northshire → Goldshire → Eastvale → Jasperlode) |
| 3.2 | Write routing policies for each travel segment |
| 3.3 | Compiler validation pass — no unresolved refs, valid guards, valid actions |
| 3.4 | In-game YAML editor MVP (syntax highlight, validate on save, show diagnostics) |
| 3.5 | Hot-reload: save profile → recompile → executor hot-swaps `CompiledProfile` preserving history |
| 3.6 | Test run: fresh Human 1-10, verify quest acceptance, travel, combat, turn-in, vendor, repair |

### Phase 4: Polish

| Task | Description |
|------|-------------|
| 4.1 | Death recovery: `Safety.CorpseRecovery` state with smart corpse run + re-equip + eat |
| 4.2 | Stuck detection + navigation recovery |
| 4.3 | Rare/elite detection → `RareSeen`/`EliteSeen` events → profile can react |
| 4.4 | GM detection → pause profile |
| 4.5 | Performance: compiler <100ms, executor overhead <1ms/tick |

---

## Acceptance Criteria

### Functional

- [ ] Profile YAML compiles without errors (all quest IDs, NPC IDs, policy names resolve)
- [ ] `StatechartExecutor` enters `Questing.Initialize` on profile load
- [ ] `QuestAccepted` event transitions `AcceptNorthshireQuests` → `TravelToKoboldCamp`
- [ ] `NavigationArrived` with correct policy triggers objective state
- [ ] `ObjectiveProgress` with count ≥ required transitions to turn-in
- [ ] `InventoryChanged` ≤4 slots triggers `Logistics.Inventory.Vending`
- [ ] `HealthChanged` <40% triggers `Survival.HealthManagement.Eating`
- [ ] `CombatStart`/`CombatEnd` drives `Survival.Combat` sub-state machine
- [ ] `PlayerDied` → `Safety.CorpseRecovery` → corpse run → resurrect → resume previous `Questing` state (history)
- [ ] Profile completes Human 1-10 Elwynn without human intervention

### Non-Functional

- [ ] Profile compiler validates + compiles in <100ms for 500-state profile
- [ ] `StatechartExecutor` event processing <1ms per event
- [ ] Memory: `QuestRegistry` cache <2MB, `CompiledProfile` <500KB
- [ ] Hot-reload preserves `Questing` region history (resumes from current sub-state)
- [ ] No polling loops in executor (pure event-driven)

---

## Migration Notes

**Deleted modules (Big Bang):**
- `quest_planner.lua` → replaced by hand-authored profile
- `objective_planner.lua` → replaced by profile's `CompleteObjectives` hierarchy
- `quest_scorer.lua` → no scoring; profile declares priority
- `rule_engine.lua` → profile embeds conditions/rules/overrides
- `quest_profile_manager.lua` → replaced by `ProfileLoader`
- `quest_graph.lua` (graph-building) → replaced by `QuestRegistry` (on-demand query)

**Repurposed modules:**
- `engine.lua` → `phase_runner.lua` (executes steps, no planning)
- `quest_phases.lua` → `step_executors/*.lua` (TravelExecutor, KillExecutor, CollectExecutor, InteractExecutor, VendorExecutor, RepairExecutor, TrainExecutor, FlyExecutor, GrindExecutor, RecoverExecutor)

**Surviving modules (minimal changes):**
- `nav_adapter.lua`, `query_client.lua`, `questie_adapter.lua`, `tracker.lua`, `heatmap.lua`, `flight_optimizer.lua`, `reward_selector.lua`

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Sylvannas UI can't support node graph + map overlay | Start with YAML text editor MVP; verify UI capabilities early |
| Compiler too slow for interactive use | ProfileCompiler is pure Lua; benchmark early; cache AST |
| Event ordering bugs (QuestAccepted before ObjectiveProgress) | Define event sequence contracts in engine; integration tests |
| Coroutine leaks on state exit | `StatechartExecutor` cancels all running actions on state exit; timeout guards |
| Profile authoring learning curve | In-game editor with snippets, validation, live diagnostics; example profile as template |
| NavServer policy support incomplete | Verify `NavServer:plan_path(start, goal, policy)` accepts policy object early |

---

## References

- ADR-0004: `sentinel/docs/adr/0004-event-driven-profile-statechart.md`
- Domain Glossary: `sentinel/CONTEXT.md` (Quest Profile Concepts section)
- Current quest module: `sentinel/modules/quest/`
- Sylvannas API: `Documentation - Project Sylvannas/dev/api/`