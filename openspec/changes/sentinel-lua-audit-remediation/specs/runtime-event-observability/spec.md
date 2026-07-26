# Runtime Event Observability Specification

## Purpose

Ensures the silent-failure surfaces identified in the audit (module tick
faults, profile-load failures, quest-log desync) are observable through
subscribed EventBus diagnostics rather than publishing into the void.

## Requirements

### Requirement: Module Fault Is Observable
When a module tick raises an error, a diagnostic event MUST be published and
MUST have at least one subscriber that surfaces it (log, cockpit, or both).
(C4) **Verification: offline**

#### Scenario: A questing tick fault is surfaced, not silent
- GIVEN questing's tick raises an error under the isolation guarantee
- WHEN the error is caught
- THEN a diagnostic event MUST be published and observed by a subscriber

### Requirement: Profile-Load Failure Is Observable
When a profile fails to load (e.g., because a prior write did not persist),
the resulting `questing:error` (or equivalent) event MUST have a subscriber
that makes the failure visible to the operator. (C4, A8)
**Verification: offline**

#### Scenario: Reload failure reaches the operator
- GIVEN a profile reload fails because the file was not written
- WHEN the failure event is published
- THEN at least one subscriber MUST render or log it, and the runner MUST
  NOT stay silently disabled

### Requirement: Quest-Log Sync Reflects Real State
`questing.tracked_quests` and `questing.quest_log` MUST be populated from the
real quest-log data already available via `_refresh_quest_log`, and the
runner cockpit's sync check MUST be able to report a real mismatch. (C5)
**Verification: offline**

#### Scenario: A real desync is detected, not hidden by empty defaults
- GIVEN the profile's tracked quests differ from the client's actual quest
  log
- WHEN the cockpit evaluates quest-log sync
- THEN it MUST report `ok=false` with the actual missing/mismatched quests,
  not an unconditional `ok=true` from empty defaults

### Requirement: Event Names Emitted Match Defined Severities
Every event severity/name defined for logging (e.g.
`EVENT_SEVERITY.operation_advance`) MUST correspond to at least one actual
`_log_event` call site, or MUST be removed. (E6) **Verification: offline**

#### Scenario: No orphaned severity definitions
- GIVEN the set of defined event severities
- WHEN the codebase is checked for emitters
- THEN every defined severity MUST be emitted by at least one call site

## Out of Scope
- General EventBus publish/subscribe imbalance beyond the three concrete
  silent-failure surfaces above (module fault, profile-load failure,
  quest-log desync) is not modeled as a requirement in this change; the
  remaining orphaned/unsubscribed events are architecture debt (register
  Group F) not scheduled for behavior change here.
- REFUTED items are not re-raised.
- The 34 unaudited files are out of scope for this change.
