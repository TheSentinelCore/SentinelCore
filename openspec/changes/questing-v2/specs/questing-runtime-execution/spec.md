# Questing Runtime Execution Specification

## Purpose

The Lua questing runtime consumes a compiled `RuntimeProfile` and executes it in-game, one action
type at a time, through a recovery state machine (`running | navigating | ghost | failed |
finished`). Today it never actually runs: `ModuleRegistry` never calls
`QuestingModule:initialize`, payload field names diverge from `runtime/action.rs`, the module
allocates a fresh context every tick, saves grow unbounded, and the ghost-recovery throttle is a
no-op. This capability makes execution real and demonstrable per action type, plus a defined,
resolved policy for unknown conditions.

## Requirements

### Requirement: Payload Field Contract Alignment

Runtime action handlers MUST consume payload fields exactly as named in the shared
`runtime::action.rs` contract: `TurnInQuest.choose_reward` (not `reward_choice`); `Flight` /
`Hearth.destination` as the string type the contract defines; `Vendor.buy_items` as a `Vec<u32>` of
item IDs (not object references); and `Kill` MUST NOT read a nonexistent `destination` field.

#### Scenario: TurnInQuest reward selection

- GIVEN a compiled profile with `TurnInQuest.choose_reward = Some(5)`
- WHEN the handler executes the turn-in
- THEN it MUST read `choose_reward`, not any `reward_choice` field

#### Scenario: Kill action has no destination field

- GIVEN a compiled `Kill` action
- WHEN the handler executes it
- THEN it MUST navigate/select targets using `creature_entries`, and MUST NOT attempt to read a
  `destination` field that does not exist on `RuntimeKill`

### Requirement: ModuleRegistry Initialization Wiring

`ModuleRegistry` MUST invoke `QuestingModule:initialize(blackboard, event_bus)` as part of the
module lifecycle (LOADED → INITIALIZING → ACTIVE) so the questing module actually activates and
begins consuming a loaded profile.

#### Scenario: Registry activates questing module

- GIVEN the questing module entry in `ModuleRegistry.modules`
- WHEN `ModuleRegistry` initializes modules at boot
- THEN `QuestingModule:initialize` MUST be called and the module MUST reach `ACTIVE` state

### Requirement: Shared EventBus and Blackboard Usage

`RuntimeProfile` execution MUST publish events to and read state from the shared `EventBus`/
`Blackboard` instances wired by `SentinelApp`, not private per-instance copies.

#### Scenario: Questing log event is observable

- GIVEN a subscriber registered on the shared `EventBus` for `questing:log`
- WHEN the runtime profile emits a `questing:log` event during execution
- THEN the subscriber MUST receive the event

### Requirement: Bounded Execution Log

The execution log persisted alongside a running profile (`<profile>.save.json`) MUST be capped at
a fixed maximum length so repeated saves do not grow the file unbounded.

#### Scenario: Long-running profile save size

- GIVEN a profile that has executed more entries than the configured cap
- WHEN the profile is saved
- THEN the serialized execution log MUST NOT exceed the configured maximum entry count

### Requirement: Cached Per-Tick Execution Context

The runtime MUST build execution context once and reuse/cache it across ticks for a given action,
rather than reallocating context/closures on every tick.

#### Scenario: Repeated ticks reuse context

- GIVEN an action executing across multiple ticks
- WHEN each tick runs
- THEN the context object MUST be the same cached instance, not a freshly allocated one per tick

### Requirement: Functional Ghost-Recovery Throttle

The ghost-detection recovery timeout MUST actually gate repeated recovery attempts (no-op fixed):
recovery attempts before the timeout elapses MUST be suppressed.

#### Scenario: Rapid repeated ghost detection

- GIVEN the runtime enters `ghost` state and immediately re-detects ghosting before the configured
  timeout
- WHEN the recovery logic runs
- THEN it MUST NOT trigger a second recovery attempt until the timeout has elapsed

### Requirement: Recovery FSM Verification

The runtime profile state machine MUST correctly recover through its defined states (`running |
navigating | ghost | failed | finished`) for forced death, forced stuck, and mid-run reload.

#### Scenario: Forced death recovery

- GIVEN a profile executing an action when the character dies
- WHEN death is detected
- THEN the state machine MUST transition appropriately and resume execution after recovery

#### Scenario: Forced stuck recovery

- GIVEN the character becomes physically stuck during navigation
- WHEN stuck-detection fires
- THEN the state machine MUST enter a recovery path and resume once unstuck

#### Scenario: Mid-run reload

- GIVEN a profile with progress persisted to `<profile>.save.json`
- WHEN the game client reloads mid-run
- THEN the runtime MUST restore state from the save and resume from the correct action

### Requirement: Per-Action-Type and Chained-Sequence Verification

Every runtime action type the compiler can emit MUST have at least one demonstrated working
scenario (in-game or harness). Additionally, one chained sequence — accept → travel → kill →
collect → turnin — MUST be verified to catch action-to-action transition bugs.

#### Scenario: Action type coverage

- GIVEN the full set of `RuntimeAction` variants
- WHEN verification scenarios are run
- THEN each variant MUST have at least one passing targeted scenario

#### Scenario: Chained sequence

- GIVEN a compiled profile encoding accept → travel → kill → collect → turnin
- WHEN it executes end to end
- THEN each transition MUST complete and the final `TurnInQuest` MUST succeed

### Requirement: Round-Trippable Test Harness Mock

The offline JSON mock used by `sentinel/tests/run_offline.lua` MUST round-trip losslessly between
Rust-emitted JSON and Lua-side stringify/parse, so persistence tests reflect real save/restore
behavior rather than mock artifacts.

#### Scenario: Save then restore

- GIVEN a runtime profile save serialized to JSON by the mock
- WHEN it is parsed back by the Lua test harness
- THEN the restored state MUST equal the original state (`test_restore_state_from_save` passes)

### Requirement: Unknown Condition Fail-Open Policy

The runtime MUST treat a condition it cannot evaluate as satisfied (fail-open) rather than
blocking, so the main quest line never stalls waiting on an unresolvable or unknown condition.
This resolves the conflict between ticket 017 (fail-closed) and compliance audit L01 (fail-open):
audit L01's fail-open guidance governs, and MUST apply regardless of whether the gating action is
marked optional.

#### Scenario: Unknown condition on optional gate

- GIVEN an optional action gated by a condition the runtime cannot evaluate
- WHEN the runtime reaches that gate
- THEN it MUST treat the condition as satisfied and continue, logging a diagnostic

#### Scenario: Unknown condition on the main line

- GIVEN a non-optional action gated by an unresolvable condition
- WHEN the runtime reaches that gate
- THEN it MUST still proceed rather than stalling, logging a diagnostic for operator visibility
