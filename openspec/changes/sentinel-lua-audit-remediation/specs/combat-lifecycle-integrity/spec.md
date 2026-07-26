# Combat Lifecycle Integrity Specification

## Purpose

Defines module tick isolation/order, correct class detection, the leash
boundary, engage/disengage stability, idempotent shutdown, and spell-cast
correctness for `modules/combat/` and the shared runtime module registry.

## Requirements

### Requirement: Module Tick Isolation
A fault in one module's tick MUST NOT prevent other modules from ticking that
frame. Module tick order MUST be deterministic and documented. (B1, F2, F8)
**Verification: offline-repro**

#### Scenario: Combat still ticks when questing throws
- GIVEN questing and combat are both registered modules
- WHEN questing's tick raises an error
- THEN combat's tick MUST still execute that frame

#### Scenario: Tick order is documented and stable
- GIVEN the module registry's configured priorities
- WHEN modules are ticked
- THEN the resulting order MUST match documented priority semantics (higher
  priority ticks first) and MUST be covered by a test pinning that order

### Requirement: Class Detection Correctness
The combat rotation MUST match the player's actual class. Detection MUST NOT
permanently latch a wrong class inferred from a not-yet-ready player object.
(B2) **Verification: in-game**

#### Scenario: Detection retries until the player object is ready
- GIVEN class detection runs while `get_local_player()` is still nil
- WHEN the player object becomes available
- THEN class detection MUST re-run and select the profile matching the
  player's real class, not remain latched on a default

### Requirement: Leash Enforcement During Questing Engagement
The runaway-chase leash MUST remain enforceable while questing drives
engagement; engaging MUST NOT reset the leash center every tick. (B3)
**Verification: in-game**

#### Scenario: Leash distance grows with real displacement
- GIVEN questing publishes repeated `combat:engage_requested` while chasing a
  target
- WHEN the player moves away from the original leash center
- THEN `leash_dist` MUST reflect that real displacement, and
  `disengage("leash_exceeded")` MUST be reachable once the leash distance is
  exceeded

### Requirement: Engage/Disengage Stability Under Contested Pulls
Repeated engage requests during an outnumbered pull MUST NOT produce an
uncontrolled engage/disengage oscillation. (B6) **Verification: in-game**

#### Scenario: Outnumbered disengage does not thrash every frame
- GIVEN a solo player pulls two mobs and is disengaged as "outnumbered"
- WHEN questing continues requesting engagement
- THEN the system MUST NOT re-engage and re-disengage every single frame
  without any backoff or state change

### Requirement: Idempotent Module Shutdown
Calling a module's shutdown sequence more than once in the same shutdown pass
MUST NOT repeat state-mutating side effects. (B7) **Verification: in-game**

#### Scenario: Shutdown runs its side effects exactly once
- GIVEN combat's `shutdown()` is invoked once directly and once via
  `registry:shutdown_all()` in the same pass
- WHEN shutdown completes
- THEN disengage, nav stop, and the `DISENGAGED` publish MUST occur exactly
  once, not twice

### Requirement: Spell-Helper Call Convention
Spell-helper calls MUST use the documented colon (method-call) convention and
MUST NOT skip range or facing checks. (C1, C2) **Verification: in-game**

#### Scenario: Method call convention matches the SDK
- GIVEN a spell-castability check against the real Sylvannas API
- WHEN the helper calls the underlying spellbook function
- THEN it MUST use the colon convention as its primary call, not a
  self-shifted plain call

#### Scenario: Range and facing are checked
- GIVEN a target out of range or facing away
- WHEN castability is evaluated
- THEN the result MUST reflect the real range/facing state, not skip those
  checks

### Requirement: Spell-Helper Fail-Open Elimination
The spell helper MUST NOT report castable/in-LOS as a default for an unknown
result; unknown states MUST be distinguishable from a confirmed positive
result. (C3) **Verification: in-game**

#### Scenario: Unknown result is not silently treated as castable
- GIVEN the underlying SDK call returns an indeterminate result
- WHEN castability is evaluated
- THEN the helper MUST NOT unconditionally return true

## Out of Scope
- REFUTED items are not re-raised.
- The 34 unaudited files are out of scope for this change.
