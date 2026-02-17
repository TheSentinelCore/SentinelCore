# GrindBuddy Update (r15)

This update hardens movement recovery with a full Unstuck v2 pipeline and safer inflight move cancellation.

## What was improved

- Added progress-based stuck detection:
  - hard move timeout (`_move_timeout`)
  - no-progress stall timeout (`_move_stall_timeout`)
- Added staged unstuck recovery flow:
  - jump
  - strafe left
  - strafe right
  - backward move + jump
  - short turn-left
- Added move request tokening to ignore stale nav callbacks after cancels/retries.
- Added automatic retry toward the original move target after each unstuck action.
- Unified inflight cancel handling for:
  - mount/dismount transitions
  - stop flow
  - route mode / route profile / auto-select changes

## Result

GrindBuddy now recovers from blocked navigation more reliably and avoids desynced movement state during route and travel transitions.
