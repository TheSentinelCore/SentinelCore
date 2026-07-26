# Navigation Ownership Specification

## Purpose

Defines a single-owner protocol over the shared `SentinelNavClient` instance
so combat and questing never issue conflicting navigation commands to one
in-flight nav operation.

## Requirements

### Requirement: Exclusive Nav Client Ownership
At any given time, exactly one subsystem (questing or combat) MAY drive the
shared nav client. A subsystem MUST claim ownership before issuing movement
commands and MUST NOT issue movement commands while another subsystem holds
ownership. (B4) **Verification: in-game**

#### Scenario: Combat does not override an in-flight questing travel
- GIVEN questing has claimed nav ownership and issued a Travel move
- WHEN combat's chase controller attempts to issue `move_to`
- THEN combat MUST detect it does not own the nav client and MUST NOT issue
  the command

#### Scenario: Ownership transfers explicitly
- GIVEN questing holds nav ownership and completes or cancels its travel
- WHEN it releases ownership
- THEN combat MUST be able to claim ownership and drive the nav client
  without contention

### Requirement: Owner-Scoped Stop Authority
A subsystem MUST NOT stop nav client motion it does not own. (B4)
**Verification: in-game**

#### Scenario: Non-owner does not stop another owner's motion
- GIVEN combat does not currently own the nav client
- WHEN combat evaluates whether to call `stop()`
- THEN it MUST NOT stop navigation belonging to the current owner

## Out of Scope
- REFUTED items are not re-raised.
- The 34 unaudited files are out of scope for this change.
