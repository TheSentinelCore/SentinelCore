# BGBOT: Technical Overview

BGBOT is an autonomous Battleground AI implementation for World of Warcraft: The Burning Crusade (2.4.3), built upon the Project Sylvanas framework. 

Unlike legacy waypoint-following mesh bots, BGBOT utilizes a reactive, telemetry-driven pipeline. It operates as a continuous state machine that decouples perception, world-model reconciliation, strategic scoring, intent gating, and navigation actuation.

This document outlines the current architectural state, baseline capabilities, and integration requirements.

---

Alpha Release Status

BGBOT is currently in Early Alpha.
Expect rapid logic changes, unhandled BG phase states, and incomplete combat rotation modules. 

Diagnostics & Telemetry
If you encounter stuck states, thrashing, or errors, please provide the diagnostic logs.
Diagnostics and telemetry files are automatically saved to scripts_data data directory.

You can force an immediate diagnostic snapshot in-game by using the BGBOT menu:
BGBOT Menu -> Diagnostics Capture -> Snapshot Now.

---

## 1. System Architecture

BGBOT executes a synchronized tick loop (`main.lua`) routing through five core subsystems:

### 1.1 Perception (`scanner.lua`)
Reads raw state from `core.object_manager` and `core.game_ui` in expanding spatial rings.
- Mitigates API overhead by batching visible object updates (Near: every tick, Tactical: every 5 ticks) and performing a full entity reconciliation every 30 ticks.
- Features a localized aura-caching system with dynamic refresh rates based on entity combat state, distance, and flag-carrier tracking requirements.

### 1.2 World Model (`world_model.lua`)
Provides a decoupled, sanitized data contract for the decision engine.
- Filters and organizes raw entity handles into discrete lists (allies, enemies, interactables, bg_state).
- Infers match phase (`PREP` vs `ACTION`) and node ownership via confidence-gated visual heuristics (tracking banner objects rather than relying on unreliable memory reads).

### 1.3 Strategist & BG Modules (`strategist.lua`, `bg/*`)
The scoring engine. It delegates context-specific node evaluation to dynamically loaded BG Modules based on `map_id`.
- Evaluates global intents (`roam`, `fight`, `retreat`, `follow_herd`, `grab_bg_buff`, `failsafe`).
- Module implementations (WSG, AB, EotS, AV) adjust base scores using map heuristics (e.g., node priority ratios, herd center-of-mass, defensive choke-point proximity).

### 1.4 Intent Controller (`controller.lua`)
An anti-thrashing layer sitting between strategy generation and execution.
- Gated by three configurable limits: `min_commit` duration, switch `cooldown` timers, and mathematical `switch_margin` thresholds.
- Enforces execution stability unless overridden by explicit contracts (e.g., `intent:can_bypass_gates()`).

### 1.5 Actuation (`action_arbiter.lua` & Pathing)
Handles discrete interaction sequencing (facing, spellcasting interrupts, movement requests).
- Interfaces strictly with the `SentinelNavClient` backend.
- Wraps navigation failures with an objective-blacklist penalty loop. Repeated pathing failures explicitly force a re-evaluation at the Strategist layer, effectively eliminating endless "stuck" loops against unpathable terrain.

---

## 2. Current Baseline (Stages 0-5)

The repository has successfully completed Stages 0 through 5 of the architecture expansion.

**Supported Modules:**
- `wsg_module.lua` (Warsong Gulch)
- `ab_module.lua` (Arathi Basin)
- `eots_module.lua` (Eye of the Storm)
- `av_module.lua` (Alterac Valley)

**Key Operational Capabilities:**
- **Dynamic Posture Scoring:** AV module calculates `turtle_factor` (0.0 to 1.0) based on allied spatial distribution relative to defensive chokepoints, fluidly scaling deep-push versus defensive priorities.
- **Stealth Specific Assaults:** Implements conditional multipliers (e.g., Rogues/Druids receiving a 2.0x priority multiplier for attacking undefended enemy bunkers).
- **Anti-Feed Routing (`failsafe.lua`):** Detects isolation (0 nearby allies + approaching enemies) and forces an immediate nav override toward established BG safe anchors or allied cluster centroids.
- **Emergency Action Preemption (`spin_flag.lua`):** High combat-micro override to interrupt enemy node interactions.

---

## 3. Active Development Backlog

The codebase is currently shifting toward the "Industry-Standard" roadmap, focusing on deterministic testing and operations.

- **Class-Specific Micro (`COMBAT-001`):** Extending the `action_arbiter` via `core/combat_micro` to support specialized rotation modules logic per `class_id`/`spec_id`. Current combat logic relies on a generic fallback.
- **Role Allocator (`TEAM-001`):** Implementation of dynamic lane and role assignments to prevent herd overcommitment on single objectives.
- **Objective Hysteresis (`PERC-001`):** Tuning the ownership confidence state machine for banner polling to ensure network/client rendering delays do not cause logic snaps.
- **KPI Telemetry (`OBS-003`):** End-of-match NDJSON dumps mapping execution state (win rates, stick recovery times, intent thrash counts) for automated CI baseline comparisons.

---

## 4. Integration Expectations

- **Strict Namespace Isolation:** BGBOT requires the Project Sylvanas `core.*` API wrappers. Direct invocation of WoW globals (e.g., `CastSpellByName` or `JumpOrAscendStart`) bypasses the `action_arbiter` queue and will corrupt intent execution blocks.
- **Herd Dependency:** Strategic scoring heavily relies on spatial density (gathering mass coordinates of `allies`); deploying BGBOT in low-player environments or running it strictly solo will severely skew decision weighting toward purely defensive logic.
- **Warm-up Delays:** Output delays immediately after map loading or logic resets are expected. The system respects hardcoded minimum commit timers and spatial polling refresh windows before forcing actuations to maintain humanization profiles.
