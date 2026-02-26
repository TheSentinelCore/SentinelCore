# Tactical BT Grind Overhaul — Design Document

> **Date:** 2026-02-26
> **Scope:** Full grind strategy overhaul + Frost Mage AoE grinding
> **Architecture:** Hybrid BT + Utility + Lightweight Planning ("Tactical BT")

---

## 1. Problem Statement

SentinelCore's current grind loop is single-target only: find one mob → pull → fight → loot → rest → repeat. This has four problems:

1. **Combat is rigid** — hardcoded BT subtrees per service, no situational adaptation
2. **No AoE grinding** — Frost Mage AoE kite grinding (gather 5-8 mobs → Frost Nova → Blizzard) is impossible with current architecture
3. **No spatial awareness** — TargetingService tracks one target and a raw enemy_count, no pack/cluster concept
4. **No performance feedback** — the bot can't learn that AoE grinding produces better XP/hr than single-target

Additionally, 9 known bugs (documented in `2026-02-21-sentinelcore-bug-audit.md`) must be fixed as prerequisites, including the critical inventory free-slot bug that causes permanent vendor loops.

## 2. Architecture: Five-Layer Tactical BT

Inspired by the [GOBT framework](https://www.jmis.org/archive/view_article?pid=jmis-10-4-321) which integrates goal-oriented planning and utility scoring within behavior trees.

### Layer Overview

```
Layer 1: ReactiveSelector           [KEEP — already great]
  Death > Combat > Loot > Rest > Vendor > Explore
  Handles priority preemption (death interrupts anything)

Layer 2: TacticalSelector           [NEW — replaces hardcoded combat node]
  Scores available Tactics each tick using utility functions
  Activates highest-scoring Tactic dynamically
  Mid-combat tactic switching when situation changes

Layer 3: TacticalPlanner            [NEW — within each Tactic]
  Phase-based planner for multi-step sequences
  AoE cycle: GATHER → NOVA → DISTANCE → BLIZZARD → CLEANUP
  Re-evaluates phase transitions each tick (not pre-committed)

Layer 4: ActionScorer               [ENHANCE existing UtilityEvaluator]
  Within a phase, score individual spells using ResponseCurves
  Already exists — wire into Tactic system

Layer 5: PerformanceAdvisor         [NEW — feedback loop]
  Tracks XP/hr, deaths/hr, mana efficiency per Tactic
  Biases utility scores over 5-minute sliding windows
```

### Integration With Existing ReactiveSelector

The shared ReactiveSelector stays intact. Only slots 4 (combat), 12 (pull), and 14 (explore) delegate to TacticalSelector instead of directly to CombatService/PullService/ExplorationService:

```
ReactiveSelector "grind_root" {
  1.  fatigue_sync            [shared — unchanged]
  2.  death_recovery          [shared — unchanged]
  3.  combat_interrupt        [shared — unchanged]
  4.  TACTICAL:combat         [TacticalSelector — active tactic's combat phase]
  5.  flee                    [shared — unchanged]
  6.  idle_pause              [shared — unchanged]
  7.  loot                    [shared — unchanged, already handles multi-corpse]
  8.  rest                    [shared — thresholds from active tactic]
  9.  vendor                  [shared — unchanged]
  10. maintenance             [shared — tactic can override]
  11. mount                   [shared — unchanged]
  12. TACTICAL:pull           [TacticalSelector — active tactic's pull phase]
  13. targeting               [shared — scoring config from active tactic]
  14. TACTICAL:explore        [TacticalSelector — active tactic's explore phase]
}
```

## 3. Component Designs

### 3.1 Tactic Interface

Each Tactic is a self-contained object declaring when it's useful and what it does.

```lua
Tactic = {
    -- Identity
    name = "aoe_kite",

    -- Can this tactic run at all? (class/level/spell gates)
    -- Checked once at startup and on level-up events.
    preconditions(ctx) → bool

    -- How good is this tactic right now? (0..1, evaluated every tick)
    -- PerformanceAdvisor applies a bias multiplier to the raw score.
    utility(ctx, advisor) → number

    -- Phases for the TacticalPlanner (ordered list, but planner
    -- evaluates enter_if/exit_if dynamically — not a fixed sequence).
    phases = {
        {
            name = "gather",
            enter_if = function(ctx) ... end,   -- precondition to enter
            tick     = function(ctx, deps) ... end,  -- returns BT status
            exit_if  = function(ctx) ... end,   -- condition to leave
        },
        -- ...more phases
    }

    -- Config overrides for shared services
    get_rest_config()    → { drink_below, eat_below, drink_until, eat_until }
    get_target_config()  → { prefer_clusters, cluster_radius, min_pack, max_pack }
    get_explore_config() → { mode, scan_radius }

    -- Cleanup when tactic is preempted or completed
    reset()
}
```

**Registration:** Tactics live in `SentinelCore/tactics/`. TacticalSelector loads all files in the directory at startup. Adding a new tactic = dropping a file, no wiring.

**Utility scoring examples:**

| Tactic | High utility | Low utility |
|--------|-------------|-------------|
| SingleTarget | 1 mob in range, or low mana, or no AoE spells | cluster detected, full mana, AoE ready |
| AoEGather | cluster detected, mana>40%, Blizzard off CD, not in combat | already in combat, low mana |
| AoEBurst | pack gathered, count>=3, Nova ready | pack scattered, Nova on CD |
| KiteReposition | in combat, mobs too close, Nova on CD | mobs rooted, safe distance |
| Emergency | HP<15%, multiple mobs, Ice Block ready | healthy |

### 3.2 TacticalSelector

Replaces the hardcoded combat/pull/explore nodes in GrindService.

```lua
TacticalSelector = {
    -- Startup: load all Tactic files from tactics/ directory
    -- Filter by preconditions (class, level, known spells)
    _available_tactics = {},  -- tactics that pass preconditions
    _active_tactic = nil,     -- currently executing tactic
    _advisor = nil,           -- PerformanceAdvisor reference

    -- Called every tick. Scores all available tactics, activates best.
    -- If active tactic changes, resets the old one and starts new.
    -- Hysteresis: active tactic gets +0.1 utility bonus to prevent thrashing.
    select(ctx) → Tactic

    -- Build BT nodes that delegate to active tactic's phases
    build_combat(deps)  → BT node
    build_pull(deps)    → BT node
    build_explore(deps) → BT node

    -- Event listener: re-evaluate preconditions on LEVEL_UP
    on_level_up(new_level)
}
```

**Hysteresis:** The currently active tactic gets a +0.1 utility bonus to prevent rapid switching. A new tactic must score meaningfully higher to preempt.

**Tactic switching mid-combat:** Allowed. If AoE burst tactic's utility drops (mobs dying, only 1-2 left), SingleTargetTactic can take over for cleanup. The old tactic's `reset()` is called, new tactic starts from its best-matching phase.

### 3.3 TacticalPlanner

Manages phases within the active tactic. Not a full GOAP planner — a utility-scored state machine that re-evaluates transitions every tick.

```lua
TacticalPlanner = {
    _tactic = nil,        -- active Tactic reference
    _current_phase = nil, -- active phase table
    _phase_started_at = 0,

    -- Every tick: check exit_if on current phase, then check enter_if
    -- on all phases (including current). Transition to best eligible phase.
    tick(ctx, deps) → BT.Status

    -- Reset on tactic switch or preemption
    reset()
}
```

**Phase transition rules:**
1. If current phase's `exit_if(ctx)` returns true, phase ends
2. Scan all phases: collect those where `enter_if(ctx)` returns true
3. Pick the first eligible phase in the phases list (priority order)
4. If no phase is eligible, tactic yields (returns BT.FAILURE)

**Example: AoEKiteTactic phases and transitions:**

```
GATHER ──(pack.gathered_count >= target_pack_size)──→ NOVA
GATHER ──(player.health_pct < 0.30)─────────────────→ (tactic yields to flee)
NOVA ──(frost_nova_cast_success)─────────────────────→ DISTANCE
NOVA ──(frost_nova_on_cd OR resisted)────────────────→ KITE
DISTANCE ──(distance_to_centroid > 15yd)─────────────→ BLIZZARD
BLIZZARD ──(pack.count == 0)─────────────────────────→ (tactic complete)
BLIZZARD ──(mobs_unfrozen AND close)─────────────────→ KITE
KITE ──(frost_nova_ready)────────────────────────────→ NOVA
KITE ──(pack.count <= 2)─────────────────────────────→ CLEANUP
CLEANUP ──(all_dead)─────────────────────────────────→ (tactic complete)
```

### 3.4 PackTracker

Gives the system spatial awareness of enemy groups. Updated every tick from visible hostile objects.

```lua
PackTracker = {
    -- Per-tick update from visible objects
    update(visible_hostiles, player_pos) → void

    -- Pack state (written to blackboard under pack.* keys)
    pack = {
        targets = {},        -- game_object references in the pack
        count = 0,           -- number of hostiles in pack
        centroid = vec3,     -- average position of pack
        spread = 0,          -- max distance from centroid (groupedness)
        nearest_dist = 0,    -- closest mob to player
        gathered_count = 0,  -- mobs currently aggroed/chasing player
    }

    -- Cluster detection for exploration (find groups to pull)
    find_clusters(visible_hostiles, radius) → {
        { centroid=vec3, count=N, targets={}, avg_level=N },
        ...
    }

    -- Blackboard keys written:
    --   pack.count, pack.centroid, pack.spread
    --   pack.gathered_count, pack.nearest_dist
    --   pack.clusters (array of detected clusters)
}
```

**Clustering algorithm:** Simple distance-based. For each hostile, check if within `cluster_radius` (default 15yd) of any existing cluster centroid. If yes, add to cluster and recompute centroid. If no, start new cluster. O(n*k) where n=hostiles, k=clusters — fast enough for <50 mobs.

**Gathered detection:** A mob is "gathered" (aggroed to player) if `mob:is_in_combat()` AND `mob:get_target() == player` (or mob is targeting player's pet). This distinguishes mobs we've pulled from ambient mobs.

### 3.5 PositioningService

Handles where to stand during combat. Critical for kiting and AoE placement.

```lua
PositioningService = {
    -- Kiting: position away from pack centroid at desired distance
    get_kite_position(player_pos, pack_centroid, desired_dist) → vec3

    -- AoE placement: best position to cast Blizzard/Flamestrike
    get_aoe_target(pack) → vec3  -- usually pack centroid

    -- Safe distance check: am I far enough from the pack?
    is_safe_distance(player_pos, pack, min_dist) → bool

    -- Blink target: position along kite vector at blink range
    get_blink_target(player_pos, pack_centroid, blink_range) → vec3

    -- Gather waypoint: next un-aggroed mob to run through
    get_next_gather_target(player_pos, pack, ungathered_mobs) → game_object

    -- All methods use NavigationAdapter for navmesh-aware positioning.
    -- Falls back to vector math if nav unavailable.
}
```

**Kite vector calculation:**
1. Compute direction: `player_pos - pack_centroid` (away from mobs)
2. Normalize and scale to `desired_dist`
3. Validate via `nav:validate_position()` (don't kite into wall/cliff)
4. If invalid, rotate vector ±30° and retry (up to 4 attempts)
5. Fall back to FleeService's vector math if all fail

**Gather pathing:** During GATHER phase, the bot needs to run through un-aggroed mobs to body-pull them. PositioningService finds the nearest un-gathered mob and provides a waypoint that passes through/near it.

### 3.6 PerformanceAdvisor

Closes the feedback loop. The bot improves its tactic choices over the session.

```lua
PerformanceAdvisor = {
    -- Sliding windows per tactic (5 minutes, updated per tick)
    _windows = {
        ["single_target"] = {
            kills = 0, deaths = 0, xp_gained = 0,
            time_active_secs = 0, mana_consumed = 0,
            window_start = 0,
        },
        ["aoe_kite"] = { ... },
    }

    -- Record events
    on_kill(tactic_name)
    on_death(tactic_name)
    on_xp(tactic_name, amount)

    -- Compute bias multiplier for a tactic's utility score
    -- Returns 0.5..1.5 based on relative efficiency
    get_bias(tactic_name) → number

    -- Internal: efficiency = (kills / time_active) * death_penalty
    -- death_penalty = max(0.5, 1.0 - (deaths * 0.15))
    -- Normalized against best-performing tactic in session
}
```

**Bias range:** 0.5 to 1.5. Applied as multiplier on raw utility: `final_utility = tactic.utility(ctx) * advisor.get_bias(tactic.name)`.

**Death penalty:** Each death within the window reduces the tactic's bias by 0.15. Two deaths in 5 minutes = bias drops to 0.7. This naturally suppresses risky AoE pulls when the bot keeps dying.

**Reinforcement:** If AoE consistently produces 2x the kills/min of single-target with low deaths, its bias climbs to 1.3-1.5, making the TacticalSelector strongly prefer it when conditions allow.

## 4. Frost Mage Rotation Provider

### 4.1 SpellCatalog Additions

```lua
SpellCatalog.MAGE = {}
SpellCatalog.MAGE.FROST = {
    -- Primary nukes
    FROSTBOLT       = { name = "frostbolt",       ids = { 27072, 25304, 12506, 12505, 10181, 10180, 10179, 8408, 8407, 7322, 837, 205, 116 } },
    FIRE_BLAST      = { name = "fire blast",      ids = { 27079, 10199, 10197, 8413, 8412, 2138, 2136, 1953, 2137 } },
    ICE_LANCE       = { name = "ice lance",       ids = { 30455 } },

    -- AoE
    BLIZZARD        = { name = "blizzard",        ids = { 27085, 10187, 10186, 10185, 6141, 10, 8427 } },
    CONE_OF_COLD    = { name = "cone of cold",    ids = { 27087, 10161, 10160, 10159, 8492, 120 } },
    ARCANE_EXPLOSION = { name = "arcane explosion", ids = { 27082, 10202, 10201, 8437, 8439, 1449 } },
    FLAMESTRIKE     = { name = "flamestrike",     ids = { 27086, 10216, 10215, 8423, 8422, 2121, 2120 } },

    -- Defensive
    FROST_NOVA      = { name = "frost nova",      ids = { 27088, 10230, 6131, 122, 865 } },
    ICE_BARRIER     = { name = "ice barrier",     ids = { 33405, 13033, 13032, 13031, 11426 } },
    ICE_BLOCK       = { name = "ice block",       ids = { 45438 } },
    BLINK           = { name = "blink",           ids = { 1953 } },
    MANA_SHIELD     = { name = "mana shield",     ids = { 27131, 10193, 10192, 10191, 8494, 1463 } },
    COLD_SNAP       = { name = "cold snap",       ids = { 11958 } },
    COUNTERSPELL    = { name = "counterspell",    ids = { 2139 } },

    -- Utility
    EVOCATION       = { name = "evocation",       ids = { 12051 } },
    ARCANE_INTELLECT = { name = "arcane intellect", ids = { 27126, 10157, 10156, 1461, 1459, 1008 } },
    FROST_ARMOR     = { name = "frost armor",     ids = { 7301, 7300, 168, 7302 } },
    ICE_ARMOR       = { name = "ice armor",       ids = { 27124, 10220, 10219, 7320 } },
    CONJURE_WATER   = { name = "conjure water",   ids = { 27090, 10140, 10139, 10138, 6127, 5506, 5505, 5504 } },
    CONJURE_FOOD    = { name = "conjure food",    ids = { 33717, 28612, 10145, 10144, 6129, 990, 597, 587 } },
    MANA_GEM        = { name = "conjure mana gem", ids = { 27101, 10054, 10053, 3552, 759 } },
}
```

### 4.2 Rotation Provider Structure

`SentinelCore/rotations/mage/Frost.lua` follows the established provider contract:

- `combat(ctx)` — Single-target: Frostbolt spam, Fire Blast weave, Ice Lance on Fingers of Frost
- `aoe(ctx)` — Blizzard (channeled at position), Cone of Cold (melee AoE), Arcane Explosion (emergency melee AoE)
- `defensive(ctx)` — Ice Barrier (preemptive shield), Frost Nova (root escape), Blink (reposition), Ice Block (<15% HP emergency), Cold Snap (reset frost CDs), Mana Shield (fallback)
- `interrupt(ctx)` — Counterspell
- `utility(ctx)` — Evocation (mana recovery), Arcane Intellect, Frost/Ice Armor, Conjure Water/Food, Mana Gem
- `maintenance(ctx)` — Buff refresh (AI, armor), conjure water/food when stacks low
- `get_pull_profile(ctx)` — Frostbolt pull at 30yd, or body pull for AoE gather

**Mana mode state machine** (like Retribution):
- `burst` — Full DPS, Blizzard spam, mana > 40%
- `sustain` — Frostbolt only, conserve mana, 15-40%
- `recovery` — Evocation priority, wand if available, < 15%

### 4.3 Level-Aware Spell Availability

The rotation uses `RankPolicy.select_max_rank()` which returns nil for unlearned spells. Key level gates:

| Level | Unlocks | Impact |
|-------|---------|--------|
| 1-3 | Frostbolt R1 | Single-target only |
| 4 | Frost Nova R1 | Can root and run |
| 8 | Frost Armor | Passive defense |
| 14 | Cone of Cold R1 | Short-range AoE |
| 20 | Blizzard R1, Blink | **AoE kite grinding becomes possible** |
| 22 | Frost Nova R2 | More reliable roots |
| 30 | Ice Barrier (talented) | Preemptive shield for AoE pulls |
| 40 | Ice Block (Cold Snap talent) | Emergency survival |

AoEKiteTactic's `preconditions(ctx)` requires Blizzard + Frost Nova → activates at level 20+.
Below level 20, only SingleTargetTactic is available for Mage.

## 5. Existing Service Modifications

### 5.1 GrindService.lua

Minimal change. Wire TacticalSelector into the ReactiveSelector where CombatService/PullService/ExplorationService currently sit:

```lua
-- build() now accepts tactical_selector in deps
local tac = deps.tactical_selector

return BT.ReactiveSelector:new("grind_root", {
    -- ...unchanged shared nodes 1-3...
    tac:build_combat(deps),     -- slot 4: was CombatService.build_bt()
    -- ...unchanged shared nodes 5-11...
    tac:build_pull(deps),       -- slot 12: was PullService.build()
    -- ...unchanged shared node 13 (targeting)...
    tac:build_explore(deps),    -- slot 14: was ExplorationService.build()
})
```

### 5.2 TargetingService.lua

Add PackTracker integration:
- Call `pack_tracker:update(visible_hostiles, player_pos)` during target scan
- When active tactic sets `prefer_clusters=true`, bias target scoring toward mobs near other mobs (adds cluster_bonus to score)
- Expose `find_clusters()` for exploration use

### 5.3 ExplorationService.lua

Add `cluster_seek` exploration mode:
- When active tactic's `get_explore_config().mode == "cluster_seek"`, prefer navigating toward detected clusters instead of random frontier cells
- Cluster data comes from PackTracker via blackboard `pack.clusters`
- Falls back to normal frontier exploration if no clusters detected

### 5.4 RestService.lua

Read rest thresholds from active tactic's `get_rest_config()`:
- Default (SingleTarget): `drink_below=0.30, eat_below=0.50, drink_until=0.80, eat_until=0.90`
- Frost Mage AoE: `drink_below=0.95, eat_below=0.50, drink_until=0.95, eat_until=0.90`
  (Mage drinks after every AoE pull — near-complete mana dump)

### 5.5 CombatContext.lua

Add pack fields readable by all tactics and rotation providers:

```lua
-- New fields in context table:
pack_count = 0,           -- from PackTracker
pack_centroid = vec3,     -- from PackTracker
pack_spread = 0,          -- from PackTracker
pack_gathered_count = 0,  -- from PackTracker
pack_nearest_dist = 0,    -- from PackTracker
```

### 5.6 Client.lua

- Instantiate TacticalSelector, PackTracker, PositioningService, PerformanceAdvisor
- Pass TacticalSelector into GrindService.build(deps)
- Wire PerformanceAdvisor to Telemetry kill/death/xp events

## 6. Concrete Tactic Implementations

### 6.1 SingleTargetTactic

Extracted from current CombatService + PullService behavior. Zero regression.

```lua
SingleTargetTactic = {
    name = "single_target",

    preconditions = function(ctx)
        return true  -- always available as fallback
    end,

    utility = function(ctx, advisor)
        local base = 0.5  -- moderate baseline
        if ctx.enemy_count <= 1 then base = 0.8 end
        if ctx.player_mana_pct < 0.20 then base = 0.9 end  -- safe when low mana
        return base * advisor:get_bias("single_target")
    end,

    phases = {
        {
            name = "engage",
            enter_if = function(ctx) return ctx.has_target and not ctx.in_combat end,
            tick = function(ctx, deps)
                -- Navigate to pull range, cast pull spell, start auto-attack
                -- (extracted from PullService logic)
            end,
            exit_if = function(ctx) return ctx.in_combat end,
        },
        {
            name = "combat",
            enter_if = function(ctx) return ctx.in_combat and ctx.target_alive end,
            tick = function(ctx, deps)
                -- Chase to melee range, execute rotation
                -- (extracted from CombatService logic)
            end,
            exit_if = function(ctx) return not ctx.target_alive end,
        },
    },

    get_rest_config = function()
        return { drink_below = 0.30, eat_below = 0.50, drink_until = 0.80, eat_until = 0.90 }
    end,
    get_target_config = function()
        return { prefer_clusters = false }
    end,
    get_explore_config = function()
        return { mode = "frontier" }
    end,
}
```

### 6.2 AoEKiteTactic

The Frost Mage AoE grinding cycle.

```lua
AoEKiteTactic = {
    name = "aoe_kite",

    preconditions = function(ctx)
        return ctx.class_id == 8                         -- Mage
            and ctx.has_spell("blizzard")                -- level 20+
            and ctx.has_spell("frost_nova")              -- level 4+
    end,

    utility = function(ctx, advisor)
        local base = 0.0
        local clusters = ctx.pack_clusters or {}
        local best_cluster = clusters[1]  -- sorted by count desc

        if best_cluster and best_cluster.count >= 3 then
            base = 0.4 + (best_cluster.count * 0.08)    -- 3 mobs=0.64, 5=0.80, 8=1.04→capped
        end

        -- Suppress if low mana (can't sustain AoE)
        if ctx.player_mana_pct < 0.35 then base = base * 0.3 end

        -- Suppress if Ice Barrier + Frost Nova both on CD (too risky)
        if ctx.spell_on_cd("frost_nova") and ctx.spell_on_cd("ice_barrier") then
            base = base * 0.5
        end

        return math.min(base, 1.0) * advisor:get_bias("aoe_kite")
    end,

    phases = {
        {
            name = "gather",
            enter_if = function(ctx)
                return not ctx.in_combat or ctx.pack_gathered_count < 3
            end,
            tick = function(ctx, deps)
                -- Pre-cast Ice Barrier if available
                -- Navigate through mob cluster to body-pull
                -- Track gathered count via PackTracker
                -- Use PositioningService.get_next_gather_target()
            end,
            exit_if = function(ctx)
                return ctx.pack_gathered_count >= ctx.tactic_cfg.target_pack_size
                    or ctx.player_health_pct < 0.30
            end,
        },
        {
            name = "nova",
            enter_if = function(ctx)
                return ctx.in_combat
                    and ctx.pack_gathered_count >= 3
                    and not ctx.spell_on_cd("frost_nova")
                    and ctx.pack_nearest_dist < 10
            end,
            tick = function(ctx, deps)
                -- Cast Frost Nova (instant, roots all nearby)
                -- Cone of Cold if in melee range (bonus damage)
            end,
            exit_if = function(ctx)
                return ctx.frost_nova_just_cast or ctx.spell_on_cd("frost_nova")
            end,
        },
        {
            name = "distance",
            enter_if = function(ctx)
                return ctx.in_combat
                    and ctx.pack_nearest_dist < 15
                    and ctx.pack_count >= 3
            end,
            tick = function(ctx, deps)
                -- Blink away if available
                -- Otherwise run away using PositioningService.get_kite_position()
                -- Target: 18-22yd from pack centroid
            end,
            exit_if = function(ctx)
                return ctx.pack_nearest_dist >= 15
                    or not deps.positioning:is_safe_distance(ctx.player_pos, ctx.pack, 15)
            end,
        },
        {
            name = "blizzard",
            enter_if = function(ctx)
                return ctx.in_combat
                    and ctx.pack_count >= 3
                    and ctx.pack_nearest_dist >= 12
                    and not ctx.spell_on_cd("blizzard")
                    and ctx.player_mana_pct > 0.10
            end,
            tick = function(ctx, deps)
                -- Cast Blizzard at pack centroid (channeled 8s)
                -- If mobs break free and close distance, exit to kite
            end,
            exit_if = function(ctx)
                return ctx.pack_nearest_dist < 8
                    or ctx.pack_count < 2
                    or ctx.player_health_pct < 0.20
            end,
        },
        {
            name = "kite",
            enter_if = function(ctx)
                return ctx.in_combat
                    and ctx.pack_nearest_dist < 12
                    and ctx.pack_count >= 2
                    and ctx.spell_on_cd("frost_nova")
            end,
            tick = function(ctx, deps)
                -- Run away from pack centroid using PositioningService
                -- Fire Blast / Ice Lance while kiting (instants only)
                -- Wait for Frost Nova CD
            end,
            exit_if = function(ctx)
                return not ctx.spell_on_cd("frost_nova")
                    or ctx.pack_count < 2
            end,
        },
        {
            name = "cleanup",
            enter_if = function(ctx)
                return ctx.in_combat and ctx.pack_count <= 2 and ctx.pack_count > 0
            end,
            tick = function(ctx, deps)
                -- Switch to single-target: Frostbolt the remaining mobs
                -- Use rotation_engine:tick_combat_once(1) -- ST mode
            end,
            exit_if = function(ctx)
                return ctx.pack_count == 0
            end,
        },
    },

    get_rest_config = function()
        return { drink_below = 0.95, eat_below = 0.50, drink_until = 0.95, eat_until = 0.90 }
    end,
    get_target_config = function()
        return { prefer_clusters = true, cluster_radius = 15, min_pack = 3, max_pack = 8 }
    end,
    get_explore_config = function()
        return { mode = "cluster_seek", scan_radius = 60 }
    end,
}
```

### 6.3 Future: PetTankTactic

For Hunter Beast Mastery (future implementation):

- Pet engages mob, player DPS from 20yd range
- Pet health monitoring (mend pet when low)
- Multi-mob: pet holds aggro on 2-3 mobs, player kills one at a time
- Utility high when pet alive and healthy, low when pet dead

## 7. Bug Fixes (Prerequisites)

All 9 bugs from `2026-02-21-sentinelcore-bug-audit.md` must be fixed before tactical work begins:

| # | Bug | Severity | Impact on Tactical BT |
|---|-----|----------|----------------------|
| B1 | Inventory always reads 0 free slots | CRITICAL | Permanent vendor loops break grind cycle |
| B2 | NavigationAdapter wrong error codes | HIGH | Misleading error reporting |
| B3 | WorldDataAdapter dead retry code | LOW | Dead code cleanup |
| B4 | Helpers.distance_2d wrong axes | HIGH | All distance calculations wrong |
| B5 | BT Throttle returns SUCCESS not RUNNING | HIGH | Throttled nodes signal completion incorrectly |
| B6 | Mode tick() returns string not BT constant | HIGH | Type mismatch in BT evaluation |
| B7 | FactionResolver duplicate 469 | LOW | Alliance mobs treated as neutral |
| B8 | Inventory test masks real issue | MEDIUM | Tests pass for wrong reasons |

## 8. Phased Implementation Plan

### Phase 1: Foundation (~3K LOC)
1. Fix all 9 bugs from audit
2. Add `ai/PackTracker.lua` — enemy clustering
3. Add `ai/Tactic.lua` — tactic interface
4. Add `ai/TacticalSelector.lua` — utility-scored tactic selection
5. Add `ai/TacticalPlanner.lua` — phase-based planner
6. Extract current CombatService+PullService behavior into `tactics/SingleTargetTactic.lua`
7. Wire TacticalSelector into GrindService
8. **Verification: existing Ret Paladin and Affliction Lock grind identically via SingleTargetTactic**

### Phase 2: Frost Mage Core (~1.5K LOC)
1. Add `SpellCatalog.MAGE.FROST` entries
2. Add `AuraCatalog.MAGE.FROST` entries
3. Create `rotations/mage/Frost.lua` rotation provider
4. Create `rotations/mage/FrostUtility.lua` utility actions
5. Register in Providers.lua + RotationRegistry.lua
6. **Verification: Frost Mage grinds in single-target mode via SingleTargetTactic**

### Phase 3: AoE Tactical System (~2K LOC)
1. Add `services/PositioningService.lua` — kite vectors, AoE placement
2. Create `tactics/AoEKiteTactic.lua` — gather/nova/blizzard/kite/cleanup phases
3. Add pack fields to CombatContext
4. Add `cluster_seek` mode to ExplorationService
5. Add cluster scoring bias to TargetingService
6. Wire rest threshold overrides from active tactic
7. **Verification: Frost Mage dynamically switches between ST (1 mob) and AoE (3+ cluster)**

### Phase 4: Intelligence + Feedback (~1K LOC)
1. Add `ai/PerformanceAdvisor.lua` — per-tactic XP/hr tracking
2. Wire to Telemetry kill/death/xp events
3. Add utility bias feedback from advisor to TacticalSelector
4. Consumable auto-purchase from vendors (buy water/food/reagents)
5. Trainer visit automation (detect level-up, navigate to trainer, learn spells)
6. Mage-specific: Conjure Water/Food between pulls
7. **Verification: bot adapts tactic choice based on session performance**

### Phase 5: Polish (~1K LOC)
1. Anti-detection for AoE patterns (vary pack size, kite path, pull timing)
2. Level-aware tactic switching (ST below 20, AoE above for Mage)
3. Additional rotations (Hunter BM framework for PetTankTactic)
4. Threat management improvements (add awareness during gather)
5. PathEntropy integration for kite path variation
6. **Verification: extended multi-hour grinding sessions stable**

## 9. File Manifest

### New Files

| File | Purpose | Est. LOC |
|------|---------|---------|
| `SentinelCore/ai/TacticalSelector.lua` | Utility-scored tactic selection | 200 |
| `SentinelCore/ai/TacticalPlanner.lua` | Phase-based planner | 300 |
| `SentinelCore/ai/Tactic.lua` | Tactic interface/base class | 100 |
| `SentinelCore/ai/PackTracker.lua` | Spatial enemy clustering | 200 |
| `SentinelCore/ai/PerformanceAdvisor.lua` | Feedback loop | 250 |
| `SentinelCore/services/PositioningService.lua` | Kite/AoE positioning | 300 |
| `SentinelCore/tactics/SingleTargetTactic.lua` | Extracted current behavior | 400 |
| `SentinelCore/tactics/AoEKiteTactic.lua` | Frost Mage AoE cycle | 500 |
| `SentinelCore/rotations/mage/Frost.lua` | Frost Mage rotation | 1200 |
| `SentinelCore/rotations/mage/FrostUtility.lua` | Frost utility actions | 400 |
| **Total new** | | **~3850** |

### Modified Files

| File | Change | Est. Diff |
|------|--------|----------|
| `SentinelCore/services/GrindService.lua` | Wire TacticalSelector | +30 |
| `SentinelCore/services/TargetingService.lua` | PackTracker integration, cluster scoring | +80 |
| `SentinelCore/services/ExplorationService.lua` | cluster_seek mode | +60 |
| `SentinelCore/services/RestService.lua` | Tactic threshold overrides | +20 |
| `SentinelCore/ai/CombatContext.lua` | Pack fields | +30 |
| `SentinelCore/rotations/framework/SpellCatalog.lua` | Mage spells | +60 |
| `SentinelCore/rotations/framework/AuraCatalog.lua` | Mage auras | +20 |
| `SentinelCore/rotations/Providers.lua` | Register Mage | +5 |
| `SentinelCore/core/Client.lua` | Instantiate new components | +40 |
| `SentinelCore/core/Telemetry.lua` | Per-tactic metrics | +30 |
| + 14 files from bug audit | Bug fixes | +200 |
| **Total modified** | | **~575** |

## 10. References

- [GOBT: Goal-Oriented Behavior Trees (JMIS 2023)](https://www.jmis.org/archive/view_article?pid=jmis-10-4-321)
- [Choosing Between BT and GOAP — Davide Aversa](https://www.davideaversa.it/blog/choosing-behavior-tree-goap-planning/)
- [Game AI Planning: GOAP, Utility, and BTs](https://tonogameconsultants.com/game-ai-planning/)
- [Utility-Based AI + BT Control System (IEEE 2021)](https://ieeexplore.ieee.org/document/9632040/)
- [SentinelCore Bug Audit](../plans/2026-02-21-sentinelcore-bug-audit.md)
- [SentinelCore Architecture](../../SentinelCore/docs/ARCHITECTURE.md)
