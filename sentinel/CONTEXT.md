# SentinelCore Domain Model

## Grind Module Concepts

**ConsumeManager** — manages consumable item consumption with verification. Hides the state machine for tracking eating/drinking attempts, measuring resource recovery, and handling retries when consumption stalls.

**Rest Phase** — behavior tree phase that consumes food/water until health/mana recovery thresholds are met, then signals completion.

**Vendor Phase** — behavior tree phase that delegates to VendorStateMachine for navigating to vendor, repairing gear, selling unwanted items, and purchasing consumables.

**VendorStateMachine** — encapsulates the multi-state vendor interaction lifecycle (traveling, interacting, repairing, selling, buying consumables). Owns its state internally; callers only see `tick()`, `reset()`, and `is_running()`.

**ThreatType** — a descriptor for a category of threat (DEATH, PVP_PLAYER, DANGEROUS_MOB, STUCK) with a default weight and half-life. Replaces raw string + weight pairs in ThreatMap calls.

**ThreatMap** — spatial heat map of dangerous locations, accumulating threat entries from deaths, PvP players, and stuck events.

**Flee Point** — a position computed as "away from threat center" used during safety flee behavior.

**Attack Neutral** — a grind module setting (`module.grind.attack_neutral`) that when enabled allows the bot to target and attack neutral (yellow) mobs in addition to hostile (red) mobs. Used by level 1 characters who can only auto-attack, since neutral mobs become attackable when targeted.

## Combat Module Concepts

**SpellDispatcher** — queues spells via the spell_queue system, handling target and position-based spell casting with signature deduplication.

**ActionLibrary** — factory of behavior tree leaf actions that delegate to SpellDispatcher.

**CombatZone** — state in battleground module tracking whether the player is in an active combat area (tier 2/3 detection).

## Spatial Concepts

**Distance** — 3D distance between coordinates, with nil-safe handling returning infinity for invalid inputs.

**Away From** — computes a position at a given distance "away from" a center point, used for flee behavior.