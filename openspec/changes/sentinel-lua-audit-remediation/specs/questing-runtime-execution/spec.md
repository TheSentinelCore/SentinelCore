# Questing Runtime Execution Specification

## Purpose

Correct action-handler contracts, retry accounting, and completion gating for
`modules/questing/`. Replaces silent-success returns and cross-action retry
leakage found in the audit register.

## Requirements

### Requirement: Per-Action Retry Isolation
The executor MUST track retry counts independently per action index.
Exhausting one action's retry budget MUST NOT reduce or carry into the next
action's budget. (A1) **Verification: offline-repro**

#### Scenario: One flaky action does not fail the operation
- GIVEN an operation with four actions each retrying up to their own budget
- WHEN action 1 exhausts its retries and the executor advances to action 2
- THEN action 2 MUST start with its own full retry budget

### Requirement: Bag Content Accuracy
Bag item counts feeding `HasItem`/`ItemCountAtLeast` MUST reflect actual bag
contents. (A2) **Verification: offline**

#### Scenario: Item count matches real bag contents
- GIVEN a bag holding a tracked quest item
- WHEN the executor evaluates `HasItem`
- THEN the reported count MUST match the item's real quantity, not zero

### Requirement: Loot Targets a Resolved Object
The loot handler MUST target a resolved game object, not a raw entry id, and
MUST NOT report success when no loot target was engaged. (A3)
**Verification: in-game**

#### Scenario: Loot succeeds only on a real target
- GIVEN a lootable corpse resolved to a game object
- WHEN the executor executes the loot action
- THEN it MUST loot the resolved object and MUST NOT return success if
  nothing was targeted

### Requirement: Kill Action Honors Loot and Elite Flags
The kill action MUST honor `RuntimeKill.loot` and `RuntimeKill.ignore_elites`.
(A4) **Verification: in-game**

#### Scenario: Elites skipped when ignore_elites is set
- GIVEN `ignore_elites=true` and an elite is the nearest candidate
- WHEN a kill target is selected
- THEN the elite MUST NOT become the sticky target

#### Scenario: Loot flag controls post-kill looting
- GIVEN `loot=false`
- WHEN a target dies
- THEN the executor MUST NOT attempt to loot the corpse

### Requirement: No False Success Without Observable Effect
Questing handlers MUST NOT return "success" on a path that produced no
observable game-state effect. (A5, A6, A8) **Verification: in-game**

#### Scenario: Grind/escort/patrol require real progress
- GIVEN a Grind, Escort, or Patrol action with real targets/polygon/kill goals
- WHEN the handler executes
- THEN it MUST NOT return success until the objective work actually occurred

#### Scenario: Vendor sell reports failure when nothing sold
- GIVEN a sell-greys call where no sell API call succeeded
- WHEN the handler evaluates its result
- THEN it MUST NOT set `attempted`/success outside the actual success guard

#### Scenario: Profile reload fails loudly on a missing write
- GIVEN a profile write that did not persist to disk
- WHEN `initialize()` loads that path
- THEN the load MUST fail with a diagnosable error, not silently disable the
  runner

### Requirement: Flight Destination Resolution
Taxi actions MUST use a documented Sylvannas API and MUST resolve
`RuntimeFlight.destination` (a string) to the matching flight node without
relying on undefined indexing. (A7) **Verification: in-game**

#### Scenario: Correct flight node selected
- GIVEN a destination string naming a specific flight node
- WHEN the executor resolves it
- THEN it MUST select that node, not a default/fallback index

### Requirement: No Unreachable Navigation Branch on Kill
The kill action MUST NOT contain a navigate-to-spawn-area branch gated on a
payload field `RuntimeKill` never populates. (A9) **Verification: offline**

#### Scenario: No dead conditional on a nonexistent field
- GIVEN a compiled `RuntimeKill` action (no `destination` field)
- WHEN the executor evaluates its navigation branches
- THEN every reachable branch MUST correspond to a field `RuntimeKill` sets

### Requirement: NPC Proximity Detection Accuracy
`is_at_npc` MUST NOT report "at NPC" when the player's own position could not
be read. (A10) **Verification: offline**

#### Scenario: Unreadable position routes to navigation
- GIVEN an NPC found via scan but the player position is unreadable
- WHEN `is_at_npc` is checked
- THEN it MUST return false, not true

### Requirement: Hot-Reload Detects File Changes In-Game
Hot-reload change detection MUST use a mechanism that can produce a non-nil
result inside the Sylvannas sandbox. (A11) **Verification: offline**

#### Scenario: Hot reload is not silently dead in-game
- GIVEN a profile file whose mtime changed
- WHEN `_check_hot_reload` runs
- THEN the mtime comparison MUST be able to return non-nil in-game

### Requirement: Nav Arrival Requires Position Confirmation
The executor MUST NOT treat the shared nav client's "idle" state as arrival
without confirming the player is at the destination. (B5)
**Verification: offline**

#### Scenario: Idle without position match is not arrival
- GIVEN the client is "idle" because something else called `stop()`, and the
  player is not at the destination
- WHEN `_execute_navigating` evaluates arrival
- THEN it MUST NOT treat this as arrival; it MUST re-navigate or time out via
  `NAV_TIMEOUT`

## Out of Scope
- REFUTED register items (lines 117-129) are not re-raised.
- The 34 unaudited files (register lines 133-147) are out of scope for this
  change; any future edit there needs its own read-first audit step.
- A12 (dead `is_at_destination_2d`), B8 (duplicate class-id maps), B9
  (proximity sensor frame-skip) are acknowledged but not scheduled by any PR
  in this change; deferred.
