# Execution Prompt — Sentinel Grinder & Combat Engine

> Copy everything below the line into a new Claude Code session opened at `c:\Users\Levi\Desktop\Sylvannas\scripts`.

---

<goal>
Implement the Sentinel Grinder & Combat Engine by executing the plan at `docs/plans/2026-02-23-sentinel-grinder-combat-engine-plan.md` task by task. The plan has 19 tasks across 4 blocks. Each task follows TDD: write failing test → verify it fails → implement → verify it passes → commit. Your job is to execute every task, track progress, and deliver a fully working system with all tests passing.
</goal>

<context>
This is a Lua bot framework for World of Warcraft (TBC) built on the Sylvannas API. You are replacing the existing fixed-pipeline Client update loop with a Behavior Tree grind loop, replacing PlanComposer priority lists with a Utility AI combat engine using response curves, and implementing a TBC Retribution Paladin rotation with seal twisting and anti-detection timing.

The design doc is at `docs/plans/2026-02-23-sentinel-grinder-combat-engine-design.md`. The implementation plan is at `docs/plans/2026-02-23-sentinel-grinder-combat-engine-plan.md`. Read both files before starting any work.

Key codebase facts:
- `require()` uses forward slashes: `require("ai/ResponseCurves")` not dots
- Tests use `TestUtil.lua` with `install_core_stub()` and `mock_object()` patterns
- Tests are registered in `SentinelCore/tests/run_all.lua` and export `M.run()`
- The existing Blackboard (`core/Blackboard.lua`) and EventBus (`events/EventBus.lua`) are reused — do not replace them
- Spell IDs come from the mangos DB and are documented in the design doc Section 5.1
- The `.api/` directory contains IntelliSense stubs — reference them for API signatures but do not modify them
</context>

<instructions>

## Setup

1. Read the implementation plan fully before writing any code.
2. Create a feature branch: `git checkout -b feat/grinder-combat-engine`
3. Create `SentinelCore/progress.json` to track state:

```json
{
  "current_task": 1,
  "tasks": [
    {"id": 1, "name": "ResponseCurves", "status": "not_started"},
    {"id": 2, "name": "UtilityEvaluator", "status": "not_started"},
    {"id": 3, "name": "BehaviorTree", "status": "not_started"},
    {"id": 4, "name": "SwingTimer", "status": "not_started"},
    {"id": 5, "name": "HumanTiming", "status": "not_started"},
    {"id": 6, "name": "CombatContext", "status": "not_started"},
    {"id": 7, "name": "RetributionUtility", "status": "not_started"},
    {"id": 8, "name": "CombatSubTree", "status": "not_started"},
    {"id": 9, "name": "DeathRecoverySubTree", "status": "not_started"},
    {"id": 10, "name": "LootSubTree", "status": "not_started"},
    {"id": 11, "name": "RestMaintenanceSubTree", "status": "not_started"},
    {"id": 12, "name": "VendorSubTree", "status": "not_started"},
    {"id": 13, "name": "FleeInterruptSubTree", "status": "not_started"},
    {"id": 14, "name": "PullFindExploreSubTree", "status": "not_started"},
    {"id": 15, "name": "GrindTree", "status": "not_started"},
    {"id": 16, "name": "ClientIntegration", "status": "not_started"},
    {"id": 17, "name": "AntiDetectionWiring", "status": "not_started"},
    {"id": 18, "name": "IntegrationSmokeTests", "status": "not_started"},
    {"id": 19, "name": "FinalVerification", "status": "not_started"}
  ]
}
```

## Execution loop

For each task:

1. Update `progress.json`: set current task status to `"in_progress"`
2. Read the task from the plan file
3. Read any existing files you need to modify — never speculate about code you haven't opened
4. Write the failing test first, exactly as specified in the plan (adapt if needed to match existing patterns)
5. Run the test to confirm it fails for the expected reason
6. Write the minimal implementation to make the test pass
7. Run the test to confirm it passes
8. Run the full test suite to catch regressions: look at `SentinelCore/tests/run_all.lua` for how tests are executed
9. Commit with a descriptive message, one commit per task
10. Update `progress.json`: set task status to `"passing"`, advance `current_task`

If a test fails unexpectedly, investigate the actual error before changing code. Do not remove or weaken tests to make them pass — fix the implementation instead.

## Checkpoints

Pause and summarize progress at these points:
- After Block 1 (Tasks 1-5): "Foundation libraries complete"
- After Block 2 (Tasks 6-7): "Rotation framework complete"
- After Block 3 (Tasks 8-14): "BT subtrees complete"
- After Block 4 (Tasks 15-19): "Integration complete"

At each checkpoint, run the full test suite and report results before continuing.

## Code quality

- Keep implementations focused on what the plan specifies — do not add features, abstractions, or "improvements" beyond the task scope
- Use the existing codebase patterns: pcall for safety, `safe_method()` helpers, event emissions
- All new files go under `SentinelCore/ai/`, `SentinelCore/bt/`, or `SentinelCore/rotations/paladin/`
- All new tests go under `SentinelCore/tests/` following the `test_ai{NNN}_{name}.lua` naming
- Register every new test in `run_all.lua`
- When the plan says "see design doc Section X", read that section from the design doc file

## Adapting the plan

The plan provides complete code for Tasks 1-6. For Tasks 7-19, it provides interfaces and key algorithms with references to the design doc. When implementing these tasks:
- Read the referenced design doc section for the full specification
- Follow the existing codebase patterns (look at how similar services/modules are structured)
- Write comprehensive tests covering the key behaviors described in the plan
- If something in the plan conflicts with how the codebase actually works, trust the codebase

</instructions>

<context_management>
Your context window will be automatically compacted as it approaches its limit. Do not stop tasks early due to token concerns. Before compaction occurs, save your current state to `progress.json` and commit any work in progress. After compaction, review `progress.json` and git log to recover your position.

Use git as your primary state checkpoint: every committed task is a safe restore point. If you lose context, run `git log --oneline -10` and read `progress.json` to determine where you are.
</context_management>
