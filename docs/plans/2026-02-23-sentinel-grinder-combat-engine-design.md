# Sentinel Grinder & Combat Engine — Design Document

**Date**: 2026-02-23
**Branch**: TBD (new feature branch from master)
**Scope**: Behavior Tree grind loop, Utility AI combat engine, rotation framework, TBC Retribution Paladin rotation, anti-detection layer

## 1. Overview

Replace the fixed 7-step Client update pipeline and PlanComposer priority-list rotation with:

1. **Behavior Tree (BT)** — governs the grind loop (death → combat → loot → rest → vendor → pull → explore)
2. **Utility AI** — governs combat decisions using response curve evaluation instead of static priorities
3. **Rotation Framework** — provider interface for class/spec rotations using utility curves
4. **Retribution Paladin Rotation** — full TBC rotation with seal twisting
5. **Human-Like Timing Layer** — anti-detection across all systems

Architecture: **Big Bang Replacement** — all systems designed together, implemented as a unified replacement of the existing pipeline.

## 2. Behavior Tree — Grind Loop

The BT replaces Client's fixed service update order. Every frame, the tree ticks from root; the first satisfied branch executes.

### 2.1 Tree Structure

```
Root (Selector — first success wins)
│
├── [1] DeathRecovery (Sequence)
│   ├── Condition: is_dead OR is_ghost
│   ├── Action: release_spirit (delay + jitter)
│   ├── Action: corpse_run (nav to corpse)
│   ├── Action: resurrect
│   └── Action: post_res_check (res sickness → wait or play conservative)
│
├── [2] EmergencyDefense (Selector)
│   ├── Condition: health < 10% AND in_combat AND has_cooldown_available
│   └── Action: pop_defensive (DS > LoH > pot)
│
├── [3] CombatInterrupt (Sequence)
│   ├── Condition: in_combat AND (was_resting OR was_looting)
│   └── Action: cancel_current_action (stand up, stop channel)
│
├── [4] Combat (Sequence)
│   ├── Condition: in_combat OR has_aggro_threat
│   ├── Decorator: timeout(45s, on_timeout → blacklist + disengage)
│   ├── SubTree: UtilityAI.evaluate()
│   ├── Action: execute (with human timing)
│   └── Repeat until: threats_dead OR fled
│
├── [5] Flee (Sequence)
│   ├── Condition: should_flee (enemy_count > threshold, HP low, no CDs)
│   ├── Action: freedom_if_available
│   ├── Action: navigate_away (opposite direction of enemies)
│   └── WaitUntil: out_of_combat
│
├── [6] Loot (Sequence)
│   ├── Condition: lootable_nearby AND NOT in_combat
│   ├── Decorator: timeout(8s) + stuck_detect
│   └── Action: navigate_and_loot
│
├── [7] Rest (Sequence)
│   ├── Condition: NOT in_combat AND needs_recovery
│   ├── Action: find_safe_spot (away from patrol paths + spawns)
│   ├── Action: eat_drink
│   └── WaitUntil: recovered OR threat_approaching
│
├── [8] Vendor (Sequence)
│   ├── Condition: bags_near_full OR durability_low
│   ├── Decorator: timeout(120s) + stuck_detect
│   └── SubTree: vendor_trip (nav, sell, repair, nav_back)
│
├── [9] Maintenance (Sequence)
│   ├── Condition: NOT in_combat
│   ├── Action: ensure_aura (Sanctity default)
│   ├── Action: ensure_blessing (Might solo / Kings group)
│   └── Action: ensure_seal (Blood default)
│
├── [10] Pull (Sequence)
│   ├── Condition: has_valid_target AND ready_to_pull
│   ├── Decorator: timeout(12s) + stuck_detect
│   ├── Action: navigate_to_range
│   └── Action: pull (auto-attack or Judgement)
│
├── [11] FindTarget (Sequence)
│   ├── Condition: NOT has_valid_target
│   └── Action: scan_score_select
│       Filter: not_blacklisted, not_tagged, not_elite, in_level_range
│       Score: distance * level_diff_penalty * mob_type_bonus * path_safety
│
└── [12] Explore (Sequence)
    ├── Condition: nothing_else_to_do
    ├── Action: navigate_to_next_waypoint
    └── Decorator: path_entropy + idle_variance (anti-detection)
```

### 2.2 Node Types

| Type | Behavior |
|------|----------|
| `Selector` | Tries children left-to-right, returns on first SUCCESS |
| `Sequence` | Runs children in order, fails on first FAILURE |
| `Condition` | Reads blackboard, returns SUCCESS/FAILURE |
| `Action` | Executes game action, returns RUNNING/SUCCESS/FAILURE |
| `Decorator` | Wraps child: repeat, invert, timeout, cooldown, stuck_detect |
| `SubTree` | Delegates to another tree (e.g., Utility AI, vendor trip) |

### 2.3 Blackboard

Shared state store replacing the current event-driven KV:

```lua
bb = {
  player = { pos, health_pct, mana_pct, is_dead, is_ghost, in_combat, is_moving,
             is_casting, is_cc, equipped_weapon_speed, buffs = {} },
  target = { obj, health_pct, distance, is_casting, cast_progress, mob_type,
             time_to_die, is_fleeing, is_tagged, level },
  combat = { enemy_count, nearest_enemy_dist, time_in_combat, was_resting, was_looting },
  inventory = { free_slots, durability_pct, has_food, has_drink },
  navigation = { current_path, stuck_timer, last_waypoint },
  grind = { current_waypoint_index, kills_this_session, deaths_this_session },
  timing = { last_action_time, session_start, fatigue_factor },
  swing = { last_swing_time, weapon_speed, haste_modifier, time_until_swing,
            in_prep_window, in_twist_window },
}
```

### 2.4 Edge Cases Handled

| Edge Case | How BT Handles It |
|-----------|-------------------|
| Multi-aggro during pull | Combat [4] activates; UtilityAI sees enemy_count > 1, AoE scores rise |
| Attacked while resting | CombatInterrupt [3] cancels eat/drink; Combat [4] takes over |
| Attacked while looting | Same as above — CombatInterrupt detects `was_looting` |
| Navigation stuck | Timeout + stuck_detect decorators on all nav actions |
| Target evades/resets | Combat timeout → blacklist + disengage |
| Mob fleeing at low HP | UtilityAI scores Hammer of Wrath high on fleeing targets |
| Player CC'd | All actions fail can_act gate; tree naturally waits |
| Mob tagged by other | `not_tagged` filter in FindTarget scoring |
| Resurrection sickness | post_res_check detects debuff, waits or plays conservative |
| Bags fill mid-grind | Vendor [8] condition triggers on bags_near_full |
| Combat flag stuck | 45s combat timeout forces disengage and state reset |
| Buff expired | Maintenance [9] refreshes aura/blessing/seal before pull |

## 3. Utility AI — Combat Engine

Replaces PlanComposer's intent-weighted priority sorting with response curve evaluation.

### 3.1 Core Concept

Every combat action defines **considerations** — response curves mapping game state to [0,1] utility. Final utility = `weight * geometric_mean(all_scores)`.

```lua
-- Example action definition
{
  action_type = "cast_spell_target",
  spell_id = 27180,  -- Hammer of Wrath
  weight = 2.2,
  considerations = {
    { input = "target_health_pct", curve = "step_below", params = { threshold = 0.20 } },
    { input = "target_health_pct", curve = "inverse_linear", params = { min = 0, max = 0.20 } },
    { input = "player_mana_pct", curve = "linear", params = { min = 0.05, max = 0.50 } },
    { input = "target_distance", curve = "inverse_linear", params = { min = 5, max = 30 } },
    { input = "spell_cooldown_remaining", curve = "step_below", params = { threshold = 0.1 } },
  },
}
```

### 3.2 Response Curve Types

| Curve | Formula | Use Case |
|-------|---------|----------|
| `linear` | `clamp((x-min)/(max-min), 0, 1)` | Gradual scaling (mana, distance) |
| `inverse_linear` | `1 - linear(x)` | Inverse scaling (closer = better) |
| `quadratic` | `linear(x)^2` | Slow start, fast finish |
| `inverse_quadratic` | `1 - (1-linear(x))^2` | Fast start, slow finish |
| `logistic` | `1 / (1 + e^(-k*(x-m)))` | S-curve with configurable steepness |
| `step_above` | `x >= threshold ? 1 : 0` | Hard gate (must be above) |
| `step_below` | `x < threshold ? 1 : 0` | Hard gate (must be below) |
| `bell` | `e^(-((x-center)^2)/(2*width^2))` | Peak at specific value |
| `constant` | `value` | Fixed score |

### 3.3 Evaluation Pipeline

```
Every frame (during Combat subtree):

  1. UPDATE CONTEXT (from Blackboard)
     - Player: health%, mana%, position, buffs, movement, casting
     - Target: health%, distance, casting, mob_type, time_to_die
     - Combat: enemy_count, nearest_enemy_dist, time_in_combat
     - Swing: time_until_swing, prep_window, twist_window

  2. EVALUATE ALL ACTIONS
     For each registered action:
       a. Hard gates: can_cast? on_cooldown? in_range? has_mana?
          → Skip if any gate fails
       b. Evaluate each consideration:
          input_value = context[consideration.input]
          score = curve(input_value, params)
       c. Final utility = weight * geometric_mean(all_scores)

  3. STOCHASTIC SELECTION (anti-detection)
     - Top K=3 actions by utility
     - Add Gaussian noise: noisy = score + N(0, score * 0.05)
     - Select highest noisy_score
     - ~5% of the time, 2nd-best wins → human-like variation

  4. EXECUTE
     - Pass through HumanTiming delay layer
     - On failure: mark action on backoff (0.12-2.0s)
     - On success: record for telemetry
```

### 3.4 Seal Twisting

Special swing-timer-driven actions for dual-seal procs:

**SwingTimer module** tracks auto-attack cycle:
- `time_until_swing`: seconds until next melee auto
- `in_prep_window`: true when >0.80s remaining (apply SoC R1)
- `in_twist_window`: true when ≤0.40s remaining (switch to SoB)

**Twist sequence**:
1. Early in swing → SoC R1 (65 mana) applied, utility weight 2.5
2. Last 0.4s → SoB applied, utility weight 3.0 (overrides everything)
3. On swing → both SoC and SoB proc → massive burst damage
4. After swing → SoB remains active for Judgement/autos

**Fallback**: When not seal twisting (disabled or OOM), just maintain SoB.

**Fumble rate**: 5% of twists intentionally "miss" the window for anti-detection.

### 3.5 Context Inputs

```lua
context_inputs = {
  -- Player
  "player_health_pct",        -- [0,1]
  "player_mana_pct",          -- [0,1]
  "player_is_moving",         -- 0 or 1
  "player_is_casting",        -- 0 or 1
  "player_is_cc",             -- 0 or 1

  -- Target
  "target_health_pct",        -- [0,1]
  "target_distance",          -- yards
  "target_is_casting",        -- 0 or 1
  "target_cast_progress",     -- [0,1]
  "target_time_to_die",       -- seconds
  "target_is_fleeing",        -- 0 or 1
  "target_is_undead_demon",   -- 0 or 1

  -- Combat
  "enemy_count",              -- integer
  "time_in_combat",           -- seconds
  "nearest_enemy_distance",   -- yards

  -- Spell
  "spell_cooldown_remaining", -- seconds (per-action)
  "gcd_remaining",            -- seconds

  -- Swing timer
  "swing_time_remaining",     -- seconds
  "swing_in_prep_window",     -- 0 or 1
  "swing_in_twist_window",    -- 0 or 1

  -- Buffs
  "has_seal_of_blood",        -- 0 or 1
  "has_seal_of_command",      -- 0 or 1
  "has_avenging_wrath",       -- 0 or 1
  "has_blessing_of_might",    -- 0 or 1
  "vengeance_stacks",         -- 0-5

  -- Config
  "seal_twist_enabled",       -- 0 or 1
  "aoe_threshold",            -- integer
}
```

## 4. Rotation Framework

### 4.1 Provider Interface

```lua
RotationProvider = {
  class_id = number,
  spec_name = string,

  can_run(context) → bool,

  -- Profiles for BT
  get_pull_profile() → { max_range, pull_spell_id, ... },
  get_movement_profile() → { combat_chase_range, kite_range, ... },

  -- Core: register all actions with utility curves
  register_actions(evaluator) → void,

  -- Per-frame hook (update swing timer, track procs)
  on_tick(context) → void,

  -- Cleanup
  on_combat_end() → void,
}
```

### 4.2 Evaluator API

```lua
evaluator:register({
  action_type = string,       -- "cast_spell_target" | "cast_spell_self" | "use_item" | "auto_attack"
  spell_id = number | nil,
  item_id = number | nil,
  weight = number,            -- base importance multiplier
  bypasses_gcd = bool,        -- e.g., Judgement is off-GCD
  considerations = { ... },   -- response curve definitions
})

evaluator:evaluate(context) → { action, utility_score }
evaluator:clear()             -- remove all registered actions
```

## 5. Retribution Paladin — Full Action Set

### 5.1 Key Spell IDs (from mangos DB)

```lua
-- Seals
SEAL_OF_BLOOD         = 31892   -- Horde, 210 mana
SEAL_OF_COMMAND_R1    = 20375   -- 65 mana (for twisting)
SEAL_OF_COMMAND_R6    = 27170   -- 280 mana
SEAL_OF_VENGEANCE     = 31801   -- Alliance, 250 mana
SEAL_OF_WISDOM_R4     = 27166   -- 270 mana
SEAL_OF_LIGHT_R5      = 27160   -- 280 mana

-- Core Rotation
JUDGEMENT             = 20271   -- 5% base mana, 10s CD (8s talented), OFF GCD
CRUSADER_STRIKE       = 35395   -- 8% base mana, 6s CD
HAMMER_OF_WRATH_R4    = 27180   -- 440 mana, 6s CD, <20% HP execute
EXORCISM_R7           = 27138   -- 340 mana, 15s CD, undead/demon only
CONSECRATION_R6       = 27173   -- 660 mana, 8s CD
HOLY_WRATH_R3         = 27139   -- 825 mana, 60s CD, undead/demon AoE

-- Cooldowns
AVENGING_WRATH        = 31884   -- 3min CD, +30% dmg 20s
DIVINE_SHIELD_R2      = 1020    -- 5min CD, immunity
LAY_ON_HANDS_R4       = 27154   -- 60min CD, full heal

-- CC / Utility
HAMMER_OF_JUSTICE_R4  = 10308   -- 60s CD, 6s stun
REPENTANCE            = 20066   -- 60s CD
BLESSING_OF_FREEDOM   = 1044    -- 25s CD

-- Blessings / Auras
BLESSING_OF_MIGHT_R8  = 27140   -- +220 AP
BLESSING_OF_KINGS     = 20217   -- +10% stats
SANCTITY_AURA         = 20218   -- +10% Holy dmg

-- Heals
FLASH_OF_LIGHT_R7     = 27137   -- 180 mana, 1.5s cast
HOLY_LIGHT_R11        = 27136   -- 840 mana, 2.5s cast
```

### 5.2 Cooldown Reference

| Ability | CD (ms) | GCD (ms) | Notes |
|---------|---------|----------|-------|
| Crusader Strike | 6,000 | 1,500 | Core rotational |
| Judgement | 10,000 (8,000 talented) | 0 (OFF GCD) | Improved Judgement 2/2 |
| Consecration | 8,000 | 1,500 | AoE, mana-expensive |
| Exorcism | 15,000 | 1,500 | Undead/Demon only |
| Hammer of Wrath | 6,000 | 500 | Execute (<20% HP) |
| Hammer of Justice | 60,000 | 1,500 | Stun interrupt |
| Repentance | 60,000 | 1,500 | CC |
| Avenging Wrath | 180,000 | — | +30% dmg, triggers Forbearance |
| Divine Shield | 300,000 | 1,500 | Immunity, triggers Forbearance |
| Lay on Hands | 3,600,000 | 1,500 | Full heal, drains all mana |
| Holy Wrath | 60,000 | 1,500 | AoE, undead/demon only |

### 5.3 Action Definitions

#### Defensives

```lua
-- Divine Shield (panic button)
{ spell_id = 1020, type = "cast_spell_self", weight = 5.0,
  considerations = {
    { input = "player_health_pct", curve = "inverse_quadratic", params = { min = 0, max = 0.25 } },
    { input = "enemy_count", curve = "linear", params = { min = 1, max = 5 } },
  }}

-- Lay on Hands (absolute last resort)
{ spell_id = 27154, type = "cast_spell_self", weight = 4.0,
  considerations = {
    { input = "player_health_pct", curve = "step_below", params = { threshold = 0.12 } },
  }}

-- Holy Light (big self-heal)
{ spell_id = 27136, type = "cast_spell_self", weight = 1.8,
  considerations = {
    { input = "player_health_pct", curve = "inverse_linear", params = { min = 0.30, max = 0.65 } },
    { input = "player_mana_pct", curve = "linear", params = { min = 0.22, max = 0.60 } },
    { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
  }}

-- Flash of Light (quick heal)
{ spell_id = 27137, type = "cast_spell_self", weight = 2.0,
  considerations = {
    { input = "player_health_pct", curve = "inverse_linear", params = { min = 0.25, max = 0.55 } },
    { input = "player_mana_pct", curve = "linear", params = { min = 0.10, max = 0.40 } },
    { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
  }}

-- Health Potion
{ type = "use_item", item_category = "health_potion", weight = 3.0,
  considerations = {
    { input = "player_health_pct", curve = "step_below", params = { threshold = 0.30 } },
  }}
```

#### Interrupts

```lua
-- Hammer of Justice (stun interrupt)
{ spell_id = 10308, type = "cast_spell_target", weight = 3.5,
  considerations = {
    { input = "target_is_casting", curve = "step_above", params = { threshold = 0.5 } },
    { input = "target_cast_progress", curve = "linear", params = { min = 0.50, max = 0.85 } },
    { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 10 } },
  }}

-- Repentance (CC interrupt backup)
{ spell_id = 20066, type = "cast_spell_target", weight = 2.5,
  considerations = {
    { input = "target_is_casting", curve = "step_above", params = { threshold = 0.5 } },
    { input = "target_cast_progress", curve = "linear", params = { min = 0.55, max = 0.90 } },
    { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 20 } },
  }}
```

#### Seal Twisting

```lua
-- SoC R1 prep (early in swing cycle)
{ spell_id = 20375, type = "cast_spell_self", weight = 2.5,
  considerations = {
    { input = "swing_in_prep_window", curve = "step_above", params = { threshold = 0.5 } },
    { input = "has_seal_of_command", curve = "step_below", params = { threshold = 0.5 } },
    { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.08 } },
    { input = "seal_twist_enabled", curve = "step_above", params = { threshold = 0.5 } },
  }}

-- SoB twist (last 0.4s before swing)
{ spell_id = 31892, type = "cast_spell_self", weight = 3.0,
  considerations = {
    { input = "swing_in_twist_window", curve = "step_above", params = { threshold = 0.5 } },
    { input = "has_seal_of_command", curve = "step_above", params = { threshold = 0.5 } },
    { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.08 } },
    { input = "seal_twist_enabled", curve = "step_above", params = { threshold = 0.5 } },
  }}

-- Fallback: maintain SoB when not twisting
{ spell_id = 31892, type = "cast_spell_self", weight = 1.0,
  considerations = {
    { input = "has_seal_of_blood", curve = "step_below", params = { threshold = 0.5 } },
    { input = "seal_twist_enabled", curve = "step_below", params = { threshold = 0.5 } },
  }}
```

#### Cooldowns

```lua
-- Avenging Wrath (+30% dmg)
{ spell_id = 31884, type = "cast_spell_self", weight = 1.5,
  considerations = {
    { input = "target_health_pct", curve = "linear", params = { min = 0.40, max = 1.0 } },
    { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.30 } },
    { input = "enemy_count", curve = "linear", params = { min = 1, max = 4 } },
  }}
```

#### Core Rotation

```lua
-- Judgement (off-GCD, 8s CD with talent)
{ spell_id = 20271, type = "cast_spell_target", weight = 1.8, bypasses_gcd = true,
  considerations = {
    { input = "has_seal_of_blood", curve = "step_above", params = { threshold = 0.5 } },
    { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 10 } },
    { input = "player_mana_pct", curve = "linear", params = { min = 0.05, max = 0.25 } },
  }}

-- Crusader Strike (6s CD, core filler)
{ spell_id = 35395, type = "cast_spell_target", weight = 1.5,
  considerations = {
    { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 5.5 } },
    { input = "player_mana_pct", curve = "linear", params = { min = 0.08, max = 0.35 } },
  }}

-- Hammer of Wrath (execute <20% HP)
{ spell_id = 27180, type = "cast_spell_target", weight = 2.2,
  considerations = {
    { input = "target_health_pct", curve = "step_below", params = { threshold = 0.20 } },
    { input = "target_health_pct", curve = "inverse_linear", params = { min = 0, max = 0.20 } },
    { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 30 } },
    { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.06 } },
  }}

-- Exorcism (undead/demon, 15s CD)
{ spell_id = 27138, type = "cast_spell_target", weight = 1.3,
  considerations = {
    { input = "target_is_undead_demon", curve = "step_above", params = { threshold = 0.5 } },
    { input = "player_mana_pct", curve = "linear", params = { min = 0.15, max = 0.55 } },
    { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
    { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 30 } },
  }}

-- Consecration (AoE, expensive)
{ spell_id = 27173, type = "cast_spell_self", weight = 1.1,
  considerations = {
    { input = "enemy_count", curve = "linear", params = { min = 2, max = 5 } },
    { input = "player_mana_pct", curve = "linear", params = { min = 0.25, max = 0.70 } },
    { input = "nearest_enemy_distance", curve = "inverse_linear", params = { min = 0, max = 8 } },
  }}

-- Holy Wrath (AoE, undead/demon, 60s CD)
{ spell_id = 27139, type = "cast_spell_self", weight = 1.0,
  considerations = {
    { input = "target_is_undead_demon", curve = "step_above", params = { threshold = 0.5 } },
    { input = "enemy_count", curve = "linear", params = { min = 2, max = 6 } },
    { input = "player_mana_pct", curve = "step_above", params = { threshold = 0.35 } },
    { input = "player_is_moving", curve = "step_below", params = { threshold = 0.5 } },
  }}

-- Auto-attack (always available filler)
{ type = "auto_attack", weight = 0.3,
  considerations = {
    { input = "target_distance", curve = "inverse_linear", params = { min = 0, max = 5.5 } },
  }}
```

### 5.4 Emergent Mana Management

No explicit "modes" — response curves create natural behavior:

| Mana Level | Actions That Score Well | Emergent Behavior |
|------------|------------------------|-------------------|
| >50% | CS, Judgement, Consecration, Exorcism, Holy Wrath | Burst mode |
| 20-50% | CS, Judgement | Sustain mode |
| <20% | Judgement (5% base mana), auto-attack | Recovery mode |
| <10% | Consider SoW swap (if configured) | Deep recovery |

### 5.5 Target Scoring (for BT FindTarget)

```lua
target_score = (
  distance_score         -- inverse_linear(0, 40) — closer is better
  * level_diff_score     -- bell(0, 3) — same level peaks, ±5 drops to 0.1
  * mob_type_bonus       -- undead/demon = 1.3 (Exorcism usable)
  * not_elite_gate       -- elite = 0.0
  * not_tagged_gate      -- tagged by other = 0.0
  * health_pct_score     -- linear(0.8, 1.0) — prefer full HP targets
  * path_safety          -- estimated by patrol density near mob
)
```

## 6. Anti-Detection — Human-Like Behavior Layer

### 6.1 Detection Vector: Action Timing Regularity

```lua
HumanTiming = {
  base_reaction_ms = 180,     -- skilled player baseline
  reaction_stddev_ms = 60,    -- Gaussian variance
  gcd_jitter_ms = 40,         -- ±40ms around GCD end

  -- Fatigue: reaction degrades over session
  fatigue_factor = 0.0,       -- +0.002 per combat minute
  fatigue_max = 0.35,         -- cap at 35% slower after ~2.5 hours

  -- Action type multipliers
  type_multipliers = {
    interrupt = 1.4,   -- reactive, slower
    defensive = 1.2,   -- panic slightly slower
    rotation = 0.9,    -- practiced, faster
    seal_twist = 0.7,  -- muscle memory
  },
}
```

### 6.2 Detection Vector: Path Self-Similarity

```lua
PathEntropy = {
  waypoint_jitter_radius = 3.0,    -- yards, validated against navmesh
  suboptimal_path_chance = 0.08,   -- 8% pick 2nd-best waypoint
  micro_pause_chance = 0.03,       -- 3% brief pause per waypoint
  micro_pause_duration = { 0.5, 1.5 },
  approach_angle_jitter = 15,      -- ±15° off direct line to mob
}
```

### 6.3 Detection Vector: Session Pattern Regularity

```lua
SessionBehavior = {
  idle_check_interval = { 180, 420 },   -- 3-7 min between "checks"
  idle_check_duration = { 2, 8 },       -- 2-8s pause
  afk_chance_per_hour = 0.15,           -- ~1 per 6-7 hours
  afk_duration = { 30, 120 },           -- 30s-2min
  post_rest_delay = { 0.5, 3.0 },       -- don't pull instantly after rest
}
```

### 6.4 Detection Vector: Combat Decision Consistency

- **Stochastic selection**: Top-3 utility scores + N(0, 5%) Gaussian noise
- **Seal twist fumble**: 5% intentional miss rate
- **Interrupt timing**: Cast progress curve 0.50-0.85 (not instant)

### 6.5 Detection Vector: Targeting Consistency

```lua
TargetHumanization = {
  target_switch_delay = { 0.3, 1.2 },     -- delay acquiring new target
  target_loyalty_factor = 0.7,             -- 70% stick to current
  add_notice_delay = { 0.5, 2.0 },        -- delay before retarget add
}
```

### 6.6 Integration

```
Action execution:  UtilityAI → HumanTiming delay → Execute
Movement:          BT navigate → PathEntropy jitter → Execute
Session:           SessionBehavior overlay on entire BT root
```

## 7. File Structure (Proposed)

```
SentinelCore/
├── ai/
│   ├── BehaviorTree.lua          -- BT node types (Selector, Sequence, etc.)
│   ├── Blackboard.lua            -- Shared state store
│   ├── UtilityEvaluator.lua      -- Response curve evaluation engine
│   ├── ResponseCurves.lua        -- Curve type implementations
│   ├── SwingTimer.lua            -- Auto-attack swing tracking
│   └── HumanTiming.lua           -- Anti-detection timing layer
├── bt/
│   ├── GrindTree.lua             -- Root BT for grind loop
│   ├── CombatSubTree.lua         -- Combat subtree (wraps UtilityAI)
│   ├── VendorSubTree.lua         -- Vendor trip subtree
│   ├── DeathRecoverySubTree.lua  -- Death handling subtree
│   └── decorators/
│       ├── Timeout.lua
│       ├── StuckDetect.lua
│       ├── PathEntropy.lua
│       └── SessionBehavior.lua
├── rotations/
│   ├── RotationProvider.lua      -- Provider interface
│   └── paladin/
│       └── Retribution.lua       -- Ret rotation (utility curves)
├── services/                     -- Existing services (refactored as BT leaves)
│   ├── TargetingService.lua
│   ├── CombatService.lua         -- Simplified: chase/face only, no rotation logic
│   ├── LootService.lua
│   ├── VendorService.lua
│   └── InventoryService.lua
└── core/
    ├── Client.lua                -- Simplified: init BT, tick BT
    └── Sensors.lua               -- Populates Blackboard
```

## 8. Research References

### Academic Literature

- **Three-layer hybrid** (Lifecycle FSM/HTN → Tactical BT → Combat Utility AI) is the consensus for MMO bot architecture
- **Utility AI** (IAUS-style, Dave Mark GDC talks) consistently outperforms priority lists for combat due to handling continuous gradients
- **Detection literature**: Timing interval regularity, path self-similarity, and session pattern consistency are primary detection vectors
- **Countermeasures**: Gaussian timing jitter, path entropy injection, stochastic action selection within utility thresholds

### TBC Retribution Paladin

- **Seal Twisting**: SoC R1 → SoB in last 0.4s = ~13% DPS increase
- **Judgement off-GCD**: Critical for rotation optimization
- **Spiritual Attunement**: SoB self-damage → heals → mana return (mana engine)
- **Improved Judgement 2/2**: 10s → 8s CD
- **Vengeance talent**: On crit → +5% damage for 30s (stacking refresh)
- **Fanaticism**: +15% Judgement crit, -32% threat

### Key Mangos DB Findings

- Seal of Blood proc: 35% weapon damage as Holy on every hit (spell 31893)
- Judgement of Blood: 294 base Holy damage (spell 31898)
- Crusader Strike: 110% normalized weapon damage, refreshes Judgement debuffs
- Hammer of Wrath: 500ms GCD (shorter than normal 1500ms)
- Consecration: 63 damage/tick × 8 ticks = 504 base for 660 mana (expensive)
