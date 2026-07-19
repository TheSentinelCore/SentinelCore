---
id: 1
title: "ProfileCompiler — YAML DSL Parser, Validator, Bytecode Compiler"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:high", "size:large"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

# ProfileCompiler — YAML DSL Parser, Validator, Bytecode Compiler

## Description

Build the `ProfileCompiler` module that parses profile YAML, validates against schema, resolves references (quest IDs, NPC IDs, policy names), compiles guard expressions and action strings to Lua bytecode, and emits a `CompiledProfile` consumable by `StatechartExecutor`.

## Pipeline Stages

1. **Parse** — `lyaml` (or custom) → Lua table AST
2. **Schema Validate** — required fields, types, enum values, state hierarchy well-formed
3. **Semantic Validate** —
   - All referenced quest IDs exist (via `QuestRegistry`)
   - All NPC IDs exist (via `QuestRegistry:getQuestNPCs`)
   - All routing policy names exist (file in `routing_policies/`)
   - No duplicate state IDs within same parent
   - No unreachable states (all states reachable from initial)
   - No duplicate transitions (same source + event + guard)
   - Variable `bind` paths valid blackboard keys
   - Guard expressions parse as valid Lua
   - Action strings parse as valid Lua chunks
4. **Compile** —
   - Guards: `loadstring("return function(event, bb, profile, state) return " .. expr .. " end")()` → bytecode
   - Actions: `loadstring(actionStr)` → bytecode (profile actions) or resolve to core action name
   - Flatten state hierarchy → transition tables indexed by event for O(1) lookup
   - Pre-compute event → transition mapping per active leaf state
5. **Emit** — `CompiledProfile` table:
```lua
{
  profile = {id, name, levelRange, variables, ...},
  states = {  -- flattened, each with compiled transitions
    ["Questing.AcceptNorthshireQuests"] = {
      type = "atomic",
      parent = "Questing",
      onEnter = {bytecode_fn1, bytecode_fn2},
      onExit = {},
      transitions = {
        QuestAccepted = {{guard=bytecode, target="Questing.TravelToKoboldCamp", actions={bytecode}}}
      }
    },
    ...
  },
  regions = {  -- parallel region roots
    Questing = {type="exclusive", initial="Questing.Initialize"},
    Survival = {type="parallel", regions={HealthManagement=..., Combat=..., Safety=...}},
    Logistics = {type="parallel", regions={Inventory=..., Equipment=..., Travel=...}}
  },
  coreActions = {"nav.followPolicy", "combat.setTargetFilter", ...},
  profileActions = {["acceptNorthshireQuests"] = bytecode_fn, ...},
  routingPolicies = {["northshire_to_kobolds"] = {strategy="smart", avoid={...}, ...}},
  diagnostics = {errors=[], warnings=[]}
}
```

## API

```lua
local compiler = ProfileCompiler.new(questRegistry, routingPolicyLoader)
local compiled, diagnostics = compiler:compile(yamlString)
-- diagnostics: {errors=[{path, message}], warnings=[{path, message}]}
```

## Acceptance Criteria

- [ ] Parses example `alliance_human_01_10_elwynn.yaml` without errors
- [ ] Validates quest IDs against `QuestRegistry` (catches typos)
- [ ] Validates NPC IDs against quest data
- [ ] Validates routing policy names against policy files
- [ ] Compiles guard `"event.questId == 783 and profile.phase == 'kobolds'"` to callable function
- [ ] Compiles inline profile action Lua to bytecode
- [ ] Resolves core action names to engine methods
- [ ] Emits `CompiledProfile` with flattened state transition tables
- [ ] Diagnostics include file:line for errors (YAML parse errors)
- [ ] Compile time <100ms for 500-state profile
- [ ] Unit tests: valid profile compiles, invalid profiles produce diagnostics

## Blocked by

- **04-quest-registry** — needs `QuestRegistry` for validation
- **07-routing-policies** — needs policy loader

## Files to Create

- `sentinel/modules/quest/profile_compiler.lua`
- `sentinel/modules/quest/compilers/` — submodules for each stage (parse, validate, compile, emit)