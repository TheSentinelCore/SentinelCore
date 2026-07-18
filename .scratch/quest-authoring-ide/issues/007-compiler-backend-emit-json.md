# 007 — Compiler: Backend - Emit StatechartExecutor JSON

**What to build:** Implement the compiler backend that transforms the IR into StatechartExecutor-compatible JSON:
- Convert processed operations into States and Transitions
- Generate the standard region structure: Questing (exclusive), Survival (parallel), Logistics (parallel)
- Map actions to states with appropriate onEnter/onExit/transitions
- Handle control flow: sequencing, branching (basic conditionals from variables)
- Generate profile variables section with bind expressions
- Create action registry mapping names to either native engine functions or bytecode
- Include source mapping (_debug fields) on all states and actions
- Validate final output against StatechartExecutor expectations
- Write one .profile.json per operation to compiled/ directory
- Generate manifest.json listing all operations and project info
- Ensure zero Mangos field names appear in output (semantic fields only)
- Optimize transition lookup (precompute event→state maps for efficiency)
- Test that output loads successfully in ProfileExecutor + StatechartExecutor

**Blocked by:** 006 — Compiler Dead Code Elimination Pass

**Status:** ready-for-agent

- [ ] Map each operation to a sequence of states in the Questing region
- [ ] Generate standard Survival and Logistics region structures (from ADR-0004)
- [ ] For each action: create state(s) with appropriate onEnter actions
- [ ] Sequence: State N → on Complete → State N+1 transition
- [ ] Handle branching: if/else conditions based on profile variables
- [ ] Generate variables section: bind expressions for player.*, inventory.*, etc.
- [ ] Create action registry:
  - Native actions: map to engine service calls (e.g., "engine:acceptQuest" → QuestExecutor::acceptQuest)
  - Bytecode actions: compile YAML action strings to Lua bytecode
- [ ] Embed source mapping: all states/actions get _debug with file/line/expanded_from
- [ ] Validate output: ensure all states have types, transitions reference valid states
- [ ] Write individual operation profile.json files
- [ ] Write manifest.json with operation load order and project variables
- [ ] Confirm output contains no raw Mangos field names (audit sample)
- [ ] Precompute event→transition mappings for fast lookup in executor
- [ ] Test end-to-end: compile sample operation → load in executor → verify no errors