# SentinelCore Domain Model

## Grind Module Concepts

**ConsumeManager** — manages consumable item consumption with verification. Hides the state machine for tracking eating/drinking attempts, measuring resource recovery, and handling retries when consumption stalls.

**Rest Phase** — behavior tree phase that consumes food/water until health/mana recovery thresholds are met, then signals completion.

**Vendor Phase** — multi-step phase for navigating to vendor, repairing gear, selling unwanted items, and purchasing consumables.

**ThreatMap** — spatial heat map of dangerous locations, accumulating threat entries from deaths, PvP players, and stuck events.

**Flee Point** — a position computed as "away from threat center" used during safety flee behavior.

## Combat Module Concepts

**SpellDispatcher** — queues spells via the spell_queue system, handling target and position-based spell casting with signature deduplication.

**ActionLibrary** — factory of behavior tree leaf actions that delegate to SpellDispatcher.

**CombatZone** — state in battleground module tracking whether the player is in an active combat area (tier 2/3 detection).

## Spatial Concepts

**Distance** — 3D distance between coordinates, with nil-safe handling returning infinity for invalid inputs.

**Away From** — computes a position at a given distance "away from" a center point, used for flee behavior.