# ADR-0005: Quest Authoring IDE Architecture

## Context
The original quest profile architecture (ADR-0004) exposed the runtime statechart execution model directly to profile authors through a visual statechart editor and YAML DSL. This forced authors to think in terms of states, transitions, guards, and actions — implementation details that belong to the executor, not the design layer.

After researching Honorbuddy's architecture and analyzing modern visual programming systems (Unreal Blueprints, Unity Visual Scripting), it became clear that authors think in terms of **intent** ("Go accept these quests", "Kill kobolds here", "Turn them in") not execution mechanics. The profile had become the execution engine rather than a declaration of intent.

Furthermore, the file-per-profile approach did not scale to full-zone authoring. Authors need project-level organization, reusable templates, and database-driven assistance — capabilities that a traditional profile editor cannot provide.

## Decision
We replace the profile editor with a **Quest Authoring IDE** that separates concerns into four layers:

```
Authoring Layer (Intent)
          │
          ▼
Compiler (Semantic Transformation)
          │
          ▼
Compiled Profile (Optimized Executor Input)
          │
          ▼
StatechartExecutor (Runtime Engine)
          │
          ▼
Game Engine (Sylvannas)
```

### Layer 1: Authoring (Quest Authoring IDE)
- **Project-based organization** (not file-based): Open "Elwynn Forest" like a Unity project
- **Directory source format**: YAML files with semantic extensions (.operation.yaml, .blueprint.yaml)
- **Four-pane UI**: Explorer (left), Map (center), Timeline (bottom), Properties (right)
- **Action Palette**: Draggable intent nodes (Pickup Quest, Kill Target, Travel, etc.)
- **Blueprints**: Reusable parameterized templates (QuestHub, SmartGrind, Escort)
- **Database Integration**: Autocomplete and validation via Mangos TBC database
- **No in-game editing**: External IDE (Rust/TanStack Start) with thin in-game debugger only

### Layer 2: Compiler
- **Input**: Authoring YAML files (operations, blueprints, project config)
- **Output**: StatechartExecutor-compatible JSON profile (one file per operation)
- **Passes**:
  - Level 1: Resolve IDs from DB, inject coordinates
  - Level 2: Insert implied actions (loot, interact, turn-in)
  - Dead Code Elimination: Skip obsoleted quests (deterministic)
  - Level 3/4: Interface-only in v1 (reordering, approvals)
- **Artifacts**: 
  - `compiled/manifest.json` (operation order, project variables)
  - `compiled/<operation>.profile.json` (executor input)
  - Embedded `_debug` fields for source mapping (no separate execution.graph file)
- **No persisted IR**: Compiler stages are in-memory only for v1

### Layer 3: Compiled Profile
- **Format**: Exact StatechartExecutor input specification (from ADR-0004)
- **Structure**:
  - `.regions` (Questing, Survival, Logistics parallel regions)
  - `.states` (all states keyed by ID)
  - `.variables` (profile variables with bindings)
  - States contain `.type`, `.transitions`, `.onEnter`, `.onExit`, `.actions`
- **Invariants**:
  - Zero Mangos field names (all resolved to semantic fields)
  - Fully resolved, ordered list of Actions with inferred steps inlined
  - Source mapping metadata in `_debug` fields on each action

### Layer 4: Runtime
- **Executor**: Unchanged StatechartExecutor (from ADR-0004)
- **Wrapper**: ProfileExecutor provides context (engine services, blackboard, event helpers)
- **Contract**: Consumes compiled profile JSON, executes actions via engine services
- **No authoring concerns**: Executor never sees operations, actions, or blueprints

## Consequences

### Positive
- **Authoring matches intent**: Authors think in missions, not statecharts
- **Database-driven**: Autocomplete, validation, and semantic resolution reduce errors
- **Reusable templates**: Blueprints eliminate repetition (like Unreal prefabs)
- **Project scaling**: Directory-based source enables git diffs, incremental recompilation
- **Clean separation**: Authoring layer isolated from executor; executor unchanged
- **Runtime simplicity**: Executor receives pre-validated, optimized profile
- **Incremental compilation**: Only changed operations recompile (one file per operation)
- **Debuggability**: `_debug` fields link compiled actions back to source YAML

### Negative
- **Increased upfront complexity**: Compiler and IDE must be built before any profile runs
- **IDE dependency**: Profiles require the external IDE for authoring (no in-game editing)
- **Compiler correctness critical**: Bugs in inference/resolution affect all generated profiles
- **Learning curve**: Authors must learn the new intent-based model (mitigated by familiarity with visual scripting tools)

### Risks
- **Compiler/executor contract mismatch**: Mitigated by targeting existing StatechartExecutor format
- **IDE scope creep**: Limited to v1 features (Level 1-2 + dead code elimination)
- **Database performance**: Solved by LRU caching in QuestRegistry (proven in ADR-0004)
- **Author adoption**: Addressed by making intent modeling obvious and database-driven

## Status
Accepted — proceeding with Quest Authoring IDE v1 implementation.

## References
- ADR-0004: Event-Driven Hierarchical Statechart for Quest Profile Execution
- Honorbuddy Quest Behaviors research (BosslandGmbH/Honorbuddy-Quest-Behaviors)
- Mangos TBC database schema (Database/tbcmangos.sqlite)
- Unreal Engine Blueprints (visual scripting paradigm)
- Unity Visual Scripting (node-based authoring)
- SentinelCore StatechartExecutor (existing runtime engine)