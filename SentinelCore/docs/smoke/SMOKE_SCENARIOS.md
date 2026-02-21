# SentinelCore Smoke Scenarios (P0 -> P1.5)

This document tracks the locked-scope smoke checks mapped to `SC-014`.

## Scenarios
1. Start Here grind loop runs for N minutes without hard failure.
2. Kill -> loot cycle completes repeatedly.
3. Inventory threshold triggers vendor flow.
4. Nearest same-map reachable vendor selected and interacted with.
5. Vendor unavailable path exhausts and fails closed.
6. Dependency outage triggers pause -> auto-restart -> hard-stop escalation.
7. Stop/pause/resume idempotency under active movement/combat.
8. Restart after failure restores persisted runtime state safely.

## Harness
- Scripted smoke harness entrypoint: `SentinelCore/tests/smoke_suite.lua`
- Full ticket suite entrypoint: `SentinelCore/tests/run_all.lua`

## Execution Model
- Each scenario runs in an isolated core-stubbed environment.
- Scenarios are deterministic and use scripted adapters/mocks to avoid flaky in-game dependencies.
- Failures are fail-closed: a scenario throws and is reported as `false` in the result map.
