# ADR-0004: Event-Driven Hierarchical Statechart for Quest Profile Execution

## Context

The quest module is shifting from auto-generated quest plans to **hand-authored declarative profiles**. The user's design calls for profiles as "executable workflow specifications" with states, transitions, conditions, actions, and event handlers.

The existing engine uses a **pull-based** phase system (`Phase:tick(dt)` polling blackboard). The user explicitly requested: *"Event Driven / Data Driven architecture, all polling/tick based design should be switched to event / data driven when found."*

## Decision

Adopt a **hierarchical event-driven statechart** (SCXML-inspired, JSON-serializable) as the profile execution model.

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Statechart** | The compiled profile: a hierarchy of states with transitions, entry/exit/transition actions, and event subscriptions |
| **State** | Node in the hierarchy. Can be *atomic* (leaf) or *compound* (parent with children). Compound states may be *parallel* (orthogonal regions) or *exclusive* (single active child) |
| **Region** | An orthogonal track within a parallel state. Multiple regions are active simultaneously |
| **Transition** | `source --[event + guard]--> target` with optional `actions` |
| **Guard** | Boolean expression evaluated when event fires; `true` = transition eligible |
| **Action** | Async function (Lua coroutine) executed on entry/exit/transition; may `await` |
| **Event** | Named signal with payload, published by engine or profile |
| **History State** | Shallow/deep history for recovery (e.g., after death, resume sub-state) |

### State Hierarchy (Default Profile Template)

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

### Event Catalog

| Event | Payload | Source |
|-------|---------|--------|
| `QuestAccepted` | `{questId, title}` | Engine (quest log change) |
| `QuestCompleted` | `{questId}` | Engine |
| `QuestTurnedIn` | `{questId, rewardChoice}` | Engine |
| `QuestFailed` | `{questId, reason}` | Engine |
| `ObjectiveProgress` | `{questId, objectiveIndex, current, required}` | Engine |
| `InventoryChanged` | `{freeSlots, totalSlots}` | Engine (bag update) |
| `DurabilityChanged` | `{slot, current, max}` | Engine |
| `PlayerDied` | `{mapId, x, y, z}` | Engine |
| `PlayerResurrected` | `{mapId, x, y, z}` | Engine |
| `CombatStart` | `{targetGUID}` | Engine |
| `CombatEnd` | `{targetGUID}` | Engine |
| `LootReady` | `{targetGUID, items[]}` | Engine |
| `LevelUp` | `{newLevel}` | Engine |
| `SkillUp` | `{skill, newValue}` | Engine |
| `ReputationChanged` | `{faction, standing}` | Engine |
| `ZoneChanged` | `{newZone, newMapId}` | Engine |
| `HearthstoneReady` | `{cooldownRemaining}` | Engine |
| `FlightPathDiscovered` | `{nodeId, name}` | Engine |
| `RareSeen` | `{npcId, name, x, y, z}` | Engine |
| `EliteSeen` | `{npcId, name, x, y, z}` | Engine |
| `PlayerNearby` | `{name, distance, isGM}` | Engine |
| `Stuck` | `{x, y, z, duration}` | Engine |
| `ProfileEvent:<custom>` | `{...}` | Profile (via `publish()` action) |

### Transition Guard Language

Guards are **Lua expressions** evaluated in a sandbox with access to:
- `event` — the event payload
- `bb` — blackboard (read-only proxy)
- `profile` — profile variables (read/write)
- `state` — current state context (read-only)

Example:
```json
{
  "event": "QuestAccepted",
  "guard": "event.questId == 5441 and profile.phase == 'northshire'",
  "target": "TravelToKobolds",
  "actions": ["profile.koboldQuestAccepted = true"]
}
```

### Action Semantics

Actions are **async Lua functions** (coroutines). The executor `await`s them sequentially.

```lua
-- In profile's action registry
actions = {
  acceptQuest = function(ctx, questId)
    ctx.engine:acceptQuest(questId)
    ctx:awaitEvent("QuestAccepted", {questId = questId}, 10000)
  end,
  travelTo = function(ctx, routeName)
    ctx.engine.nav:followRoute(routeName)
    ctx:awaitEvent("NavigationArrived", {route = routeName}, 300000)
  end,
  killMobs = function(ctx, npcIds, count, area)
    ctx.engine.combat:setTargetFilter(npcIds)
    ctx:awaitEvent("ObjectiveProgress", {questId = ctx.profile.currentQuest, count = count}, 600000)
  end
}
```

### Profile Variables (Data Model)

```json
{
  "variables": {
    "playerLevel": {"type": "number", "bind": "player.level"},
    "bagSlotsFree": {"type": "number", "bind": "inventory.freeSlots"},
    "durabilityPct": {"type": "number", "bind": "equipment.lowestDurabilityPct"},
    "activeQuest": {"type": "number", "init": null},
    "koboldsKilled": {"type": "number", "init": 0},
    "phase": {"type": "string", "init": "northshire"},
    "hearthstoneBound": {"type": "boolean", "init": false}
  }
}
```

`bind` expressions are evaluated on each event tick (data-driven reactivity).

### Execution Semantics

1. **Enter** root state → enter initial child of each parallel region
2. **Event loop**: Engine publishes event → Statechart evaluates enabled transitions from *currently active leaf states* (depth-first, innermost first)
3. **Transition**: Exit source state (run `exit` actions) → run `transition` actions → enter target state (run `entry` actions)
4. **History**: On re-entry to a compound state with history, resume last active leaf
5. **Completion**: When `Questing` region reaches `Finished`, publish `ProfileComplete` and stop

### Compilation Pipeline

```
Authoring (Visual Editor / YAML DSL / JSON)
        │
        ▼
Profile Compiler (Lua)
  - Parses YAML → AST
  - Validates: schema, no unreachable states, no duplicate transitions, valid guards, valid actions
  - Resolves: route names → nav meshes, quest IDs → DB records, NPC IDs → DB records
  - Compiles: guards & action expressions → Lua bytecode (luac.loadstring)
  - Optimizes: flattens transition tables, pre-computes event→transition indices
        │
        ▼
CompiledProfile (JSON + bytecode)
        │
        ▼
StatechartExecutor (Lua runtime)
  - Event loop
  - Active state stack
  - Variable store
  - Action scheduler (coroutine pool)
```

### Profile DSL: YAML with Expression Strings

**Decision:** YAML as the authoring format. Visual editor emits YAML. Hand-authors write YAML. JSON is compilation output only.

**Expression Language:** Restricted Lua subset (arithmetic, comparison, logic, `bb.path`, `profile.var`, `event.field`, function calls to whitelisted builtins). Compiled to Lua bytecode at compile time.

Example `profile.yaml`:

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
  # Parallel root regions
  Questing:
    type: "exclusive"
    initial: "Initialize"
    states:
      Initialize:
        type: "atomic"
        onEnter: ["log('Profile starting: ' .. profile.name)"]
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
          - "nav.followRoute('northshire_to_kobolds')"
        transitions:
          - event: "NavigationArrived"
            guard: "event.route == 'northshire_to_kobolds'"
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
          - "nav.followRoute('kobolds_to_northshire')"
        transitions:
          - event: "NavigationArrived"
            guard: "event.route == 'kobolds_to_northshire'"
            target: "AcceptNorthshireQuests"  # loop for next quest
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
            onEnter: ["nav.followRoute('to_nearest_vendor')"]
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

**Why YAML over Lua DSL:**
- Visual editors serialize to YAML/JSON natively
- No sandbox needed at author-time (expressions compiled, not eval'd)
- Schema-validatable (JSON Schema / Kwalify)
- Portable — could compile to other targets (TypeScript for web visualizer)
- Comments, anchors/aliases for DRY profiles
- Clear separation: *authoring* (YAML) ≠ *runtime* (compiled bytecode)

### Objective Groups = State Hierarchy + Metadata

**Decision:** Objective groups are **not separate objects**. The state hierarchy *is* the grouping. Metadata annotations on states provide analytics/simulation data.

```yaml
CompleteObjectives:
  type: "exclusive"
  initial: "NorthFarmCluster"
  states:
    NorthFarmCluster:
      type: "compound"
      initial: "KillBoars"
      meta:
        objectiveGroup: "North Farm"
        description: "Boars, apples, and escort at North Farm"
      states:
        KillBoars:
          type: "atomic"
          meta:
            objectiveType: "kill"
            questIds: [54, 87]
            estimatedXp: 2800
            npcIds: [2956]
          onEnter: ["combat.setTargetFilter({2956})"]
          transitions:
            - event: "ObjectiveProgress"
              guard: "event.questId in {54,87} and event.current >= 12"
              target: "CollectApples"
          onExit: ["combat.clearTargetFilter()"]

        CollectApples:
          type: "atomic"
          meta:
            objectiveType: "collect"
            questIds: [91]
            estimatedXp: 1200
            itemId: 1256
          transitions:
            - event: "ObjectiveProgress"
              guard: "event.questId == 91 and event.current >= 8"
              target: "EscortFarmer"

        EscortFarmer:
          type: "atomic"
          meta:
            objectiveType: "escort"
            questIds: [54]
            npcId: 1234
          onEnter: ["escort.start(1234)"]
          transitions:
            - event: "QuestCompleted"
              guard: "event.questId == 54"
              target: "NorthFarmClusterDone"

    JasperlodeMine:
      type: "compound"
      meta:
        objectiveGroup: "Jasperlode Mine"
      # ... similar structure
```

**Benefits:**
- Single source of truth — hierarchy = execution flow = grouping
- Metadata is optional, additive, queryable by simulator/analytics
- Visual editor shows groups as collapsible state containers
- No synchronization between two representations

### Routing Policies, Not Route Waypoints

**Decision:** The nav server (`SentinelNavServer`) computes paths dynamically. Profiles declare **routing policies** (strategy, avoidance, preferences), not hardcoded waypoint lists.

```yaml
# In profile state
TravelToKoboldCamp:
  type: "atomic"
  onEnter:
    - "nav.followPolicy('northshire_to_kobolds')"
  transitions:
    - event: "NavigationArrived"
      guard: "event.policy == 'northshire_to_kobolds'"
      target: "KillKobolds"

# In routing_policies/northshire_to_kobolds.yaml
name: "northshire_to_kobolds"
strategy: "smart"
preferredPath: "road"
avoid:
  - "elite"
  - "water"
  - "enemyTown"
dynamicReplan: true
allowShortcuts: true
opportunisticKills:
  - "Wolf"
  - "Boar"
opportunisticLoot:
  - "Chest"
  - "QuestObject"
ignore:
  - "Rare"
  - "Elite"
```

**NavClient:** `nav.followPolicy(name)` → resolves policy → calls `NavServer:plan_path(start, goal, policy)` → receives dynamic waypoints → follows them.

**Benefits:**
- Nav mesh updates automatically improve all profiles
- Policies are reusable, composable, versionable
- Profile author specifies *strategy*, not *geometry*
- Visual editor edits policies (polygon avoidance zones, road preference weights) — not waypoint lists
- Compiler inlines resolved policy into compiled profile for runtime

### Action Registry: Hybrid (Core + Profile-Local)

**Decision:** Core actions = engine methods (type-safe, tested, discoverable). Profile-specific actions = inline Lua in YAML `actions:` block (compiled to bytecode).

```yaml
# Core actions (engine-provided, globally registered)
# nav.followPolicy, combat.setTargetFilter, vendor.sellJunk, consume.useFood, etc.

# Profile-local actions (inline in YAML, compiled to bytecode)
actions:
  acceptNorthshireQuests: |
    local npcId = 197
    local quests = engine:getAvailableQuestsAtNpc(npcId)
    for _, q in ipairs(quests) do
      engine:acceptQuest(q.id)
      ctx:awaitEvent("QuestAccepted", {questId = q.id}, 5000)
    end
    return true
  
  smartTurnIn: |
    local questId = profile.activeQuest
    local reward = engine:selectBestReward(questId, profile.playerClass)
    engine:turnInQuest(questId, reward)
    ctx:awaitEvent("QuestTurnedIn", {questId = questId}, 5000)
    return true
```

**Resolution at compile time:**
1. Parse all `actions:` strings as Lua chunks
2. Validate syntax, no global pollution (sandboxed env)
3. Register in profile's action table with compiled bytecode
4. At runtime, `ctx:callAction(name, args)` executes the bytecode with `ctx` (engine, profile, event helpers)

**Why hybrid:**
- Core actions = stable API, IDE support, testable in isolation
- Profile actions = custom logic without engine changes, versioned with profile
- No global registry mutation at runtime (security, determinism)

### In-Game Visual Profile Editor

**Decision:** The profile authoring tool is an **in-game addon/UI** (not Electron/web). Built with Sylvannas UI APIs, rendering to the game window.

**Architecture:**
```
In-Game Editor (Lua/Sylvannas UI)
├── Statechart Canvas (node graph: states, transitions, regions)
├── Property Panel (selected node: guards, actions, meta)
├── Map Overlay (world map with polygon drawing: patrol, avoid, vendor zones)
├── Route Policy Editor
├── Quest Browser (search Mangos DB via QueryClient → autocomplete quest/NPC/coords)
├── Dependency Graph (visual DAG of quest prerequisites from QuestRegistry)
├── Compiler Integration (on save: validate → compile → hot-reload profile)
└── (Simulator Panel — deferred)
```

**Tech stack:**
- Sylvannas UI framework (frames, textures, fonts, input handling)
- Custom node graph layout (force-directed or hierarchical) — no external deps
- Map rendering: WoW map textures + DBC data (from QueryClient) → canvas draw
- Compiler: same Lua `ProfileCompiler` module used by CLI, invoked in-editor
- (Simulator deferred)

**Data flow:**
```
Author edits graph in-game
        │
        ▼
Editor serializes to YAML AST (Lua table)
        │
        ▼
ProfileCompiler.compile(ast) → CompiledProfile + Diagnostics
        │
        ├── Diagnostics → inline errors on nodes (red squiggles)
        ├── CompiledProfile → hot-reloaded into running executor (if testing)
        └── (Simulator deferred)
```

**Benefits:**
- Author tests profile *in the actual environment* (real nav, real combat, real quest state)
- No context switching (game ↔ editor)
- Live map = real world coordinates, real spawn data
- Hot-reload: edit → save → profile continues from current state (history preserved)
- Zero external tooling dependency

**Risks:**
- Sylvannas UI capabilities must support node graph + map overlay (verify early)
- Performance: compiler must be fast enough for interactive use
- In-game editor is significant UI engineering (mitigate: start with minimal MVP)

### QuestRegistry: On-Demand Query + Caching (Not Full Preload)

**Decision:** Do **not** load all quests into memory. Use `QueryClient` (HTTP → SentinelQueryServer → Mangos DB) with **LRU cache + TTL**.

```lua
local QuestRegistry = {}
QuestRegistry.__index = QuestRegistry

function QuestRegistry.new(queryClient, maxCacheSize, ttlMs)
  return setmetatable({
    _client = queryClient,
    _cache = {},           -- [questId] = {data, timestamp}
    _searchCache = {},     -- [searchKey] = {results, timestamp}
    _maxSize = maxCacheSize or 500,
    _ttl = ttlMs or 300000, -- 5 min
  }, QuestRegistry)
end

function QuestRegistry:getQuest(questId)
  local cached = self._cache[questId]
  if cached and (now() - cached.timestamp) < self._ttl then
    return cached.data
  end
  local data = self._client:fetch_quest(questId)
  if data then
    self:_cachePut(questId, data)
  end
  return data
end

function QuestRegistry:searchQuests(criteria)
  local key = json.encode(criteria)
  local cached = self._searchCache[key]
  if cached and (now() - cached.timestamp) < self._ttl then
    return cached.results
  end
  -- QueryClient doesn't have search endpoint yet — would need to add
  -- For MVP: compiler validates only quests explicitly referenced in profile
  return {}
end

function QuestRegistry:_cachePut(questId, data)
  if self:_cacheSize() >= self._maxSize then
    self:_evictLRU()
  end
  self._cache[questId] = {data = data, timestamp = now()}
end
```

**Memory profile:** ~500 quests × ~2KB = ~1MB cache. Negligible.

**Compiler validation:** Only validates quests/NPCs **explicitly referenced** in the profile (via `getQuest(id)`, `getQuestNPCs(id)`). No full DB scan.

**Editor autocomplete:** Debounced search → `QueryClient` → server-side Mangos query → returns top 20 matches. No local full-text index needed.

**Benefits:**
- Zero startup memory spike
- Cache stays small (only touched quests)
- Server (SentinelQueryServer) does the heavy lifting
- Works for any zone/level without preloading

## Consequences

**Positive:**
- Profiles are **declarative, visualizable, simulatable, testable**
- Event-driven = no polling overhead, reacts instantly to game events
- Hierarchical = separation of concerns (questing vs survival vs logistics)
- History states = natural death/recovery/resume without custom code
- Compiler catches errors at author-time, not runtime

**Negative:**
- Significant runtime implementation effort (statechart executor)
- Learning curve for profile authors (statechart thinking vs. linear scripts)
- Debugging requires statechart visualizer (integrate with visual editor)

**Risks:**
- Lua coroutine management for async actions must be robust (timeouts, cancellation on state exit)
- Event ordering guarantees needed (e.g., `QuestAccepted` before `ObjectiveProgress`)

## Status

Accepted — proceeding to implementation phase.

## References

- SCXML (W3C) — statechart standard
- XState (JavaScript) — modern statechart library, good mental model
- Harel statecharts — hierarchical/parallel semantics