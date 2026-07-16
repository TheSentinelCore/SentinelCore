# ADR-0001: Extract ConsumeManager from Rest Phase

## Status

Accepted

## Context

The Rest phase (`modules/grind/phases/rest.lua`) contains duplicated state management for food and water consumption. Each resource has 4 state variables:
- `_eat_active` / `_drink_active` — whether consumption is in progress
- `_eat_started_ms` / `_drink_started_ms` — when consumption started
- `_eat_initial_hp` / `_drink_initial_mana` — resource level at start
- `_eat_reuse_count` / `_drink_reuse_count` — retry counter

The verification logic (CONSUME_VERIFY_MS=5000, CONSUME_MIN_GAIN=0.05) is duplicated. Understanding "resting" requires knowing 8 state variables; changes to the verification thresholds require edits in two places.

## Decision

Extract the consumable consumption logic into a dedicated `ConsumeManager` module with a deep interface:

```lua
ConsumeManager.consume(item_id, opts) -> {status, retry_count}
```

Where `opts` contains:
- `resource_type` — "health" or "mana"
- `threshold` — trigger threshold (where we decide we need to consume)
- `target_pct` — completion threshold (default 0.95)

The module holds its own state internally, exposing only the action interface to callers.

## Consequences

**Positive:**
- Locality: Verification thresholds and retry logic in one place
- Leverage: Callers get "consume with verification" without knowing the state machinery
- Testability: Can test consume_success/failure/stall scenarios without full BT context
- Reusability: Other phases (vendor buying food/water) could use same pattern

**Negative:**
- One more module to maintain
- State now lives in the module rather than phase closure (but this is actually a positive for cleanup)

**Neutral:**
- No change to user-facing behavior

## Alternatives Considered

1. **Keep in Rest phase** — Rejected. The duplication between food/water is real and the state management is complex enough to warrant encapsulation.

2. **Generic ResourceManager** — Considered but rejected as over-abstraction. Consumption has specific semantics (recovery verification, retry thresholds) that differ from other resource management.