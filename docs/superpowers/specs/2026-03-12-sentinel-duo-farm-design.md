# SentinelDuoFarm — Design Specification

## Context

Building a duo mage dungeon farming bot for TBC Anniversary on MaNGOS core. The system must:

- Support two mages (level 58, owl gear) farming instances like Stratholme Undead
- Use Blizzard + Ice Block + Cone of Cold kiting method (no terrain exploits)
- Be generic enough to define farming profiles for any dungeon
- Run as two separate Sylvannas instances on the same machine
- Coordinate via observation (watching partner's game object), not IPC
- Maximize gold/hour through fast run times and strict cooldown alternation

---

## 1. Project Structure

New standalone project: `SentinelDuoFarm/`

```
SentinelDuoFarm/
├── main.lua                        # Entry point, _G.SentinelDuoFarm, callbacks
├── header.lua                      # Plugin metadata
├── init.lua                        # First-load initialization
├── runtime/
│   ├── app.lua                     # DuoFarmApp lifecycle (update loop, service wiring)
│   └── sensor_hub.lua              # Reads player, partner, mobs → blackboard each tick
├── core/
│   ├── blackboard.lua              # Key-value store (copy from sentinel)
│   ├── event_bus.lua               # Pub-sub events (copy from sentinel)
│   ├── error_boundary.lua          # Error handling (copy from sentinel)
│   └── bt/                         # Behavior tree library (copy from sentinel/core/bt/)
│       ├── composites.lua          # Sequence, Selector, ReactiveSequence, Parallel
│       ├── decorators.lua          # Throttle, Cooldown, Timeout, Inverter
│       ├── factory.lua             # BT.sequence(), BT.selector(), etc.
│       ├── leaves.lua              # Action, Condition
│       ├── node.lua                # Base node
│       ├── runner.lua              # BT tick runner
│       └── status.lua              # SUCCESS, FAILURE, RUNNING
├── modules/
│   ├── partner/                    # Partner observation
│   │   └── observer.lua            # Finds partner mage, tracks position/alive/ice_block
│   ├── farm/                       # Farm state machine
│   │   ├── module.lua              # FarmModule: owns the master BT, ticks it
│   │   ├── farm_tree.lua           # Master priority_selector BT
│   │   ├── state_tracker.lua       # Pull index, role, run count, timing
│   │   └── phases/                 # One BT sub-tree per phase
│   │       ├── safety.lua          # Emergency: HP critical, partner dead, wipe recovery
│   │       ├── enter_instance.lua  # Navigate to portal, zone in
│   │       ├── move_to_pull.lua    # Walk to puller_start or aoer_standby
│   │       ├── pull.lua            # Follow pull_path, tag mobs with R1 Blizzard
│   │       ├── cluster.lua         # Run to cluster_point, Ice Block
│   │       ├── aoe_kite.lua        # Kite loop + AoE rotation
│   │       ├── loot.lua            # Sweep kill zone, loot corpses
│   │       ├── rest.lua            # Eat/drink/rebuff + conjure supplies
│   │       ├── next_pull.lua       # Advance pull index, swap roles
│   │       ├── exit_instance.lua   # Walk to exit portal
│   │       └── reset_instance.lua  # Reset instances, re-enter
│   ├── combat/                     # Rotations and kiting
│   │   ├── spell_catalog.lua       # Spell ranks + runtime resolution via has_spell()
│   │   ├── aura_ids.lua            # Buff/debuff aura IDs
│   │   ├── puller_rotation.lua     # R1 Blizzard tagging + survival
│   │   ├── aoer_rotation.lua       # Blizzard/CoC/Nova + priority targets
│   │   ├── kite_engine.lua         # Centroid tracking, distance control, loop following
│   │   └── emergency.lua           # Ice Block/Cold Snap/Blink chaining
│   ├── loot/                       # Loot system
│   │   ├── corpse_scanner.lua      # Find lootable corpses in radius
│   │   └── sweep_controller.lua    # Navigate-to-loot loop
│   ├── profiles/                   # Profile system (module)
│   │   ├── profile_loader.lua      # Load from scripts_data/, validate schema
│   │   ├── profile_schema.lua      # Schema validation
│   │   └── profile_scanner.lua     # Scan scripts_data/ for available profiles
│   ├── recorder/                   # Profile recording tool
│   │   ├── recorder_module.lua     # Keybind handling, state management
│   │   ├── waypoint_marker.lua     # Waypoint buffers per pull
│   │   └── exporter.lua            # Serialize to Lua table, write to scripts_data/
│   └── ui/                         # Settings window + overlay
│       ├── window.lua              # Main UI orchestrator (TabBuilder)
│       ├── tabs/
│       │   ├── control_tab.lua     # Role, profile, start/stop, recorder toggle
│       │   ├── status_tab.lua      # Phase, pull counter, partner, mobs, timer
│       │   ├── settings_tab.lua    # Thresholds and timing sliders
│       │   └── debug_tab.lua       # Blackboard dump, BT trace, event log
│       └── overlay/
│           └── farm_overlay.lua    # 3D pull paths, kite loops, centroid, markers
├── integrations/
│   └── nav_adapter.lua             # Wrapper for _G.SentinelNavClient.client
├── shared/
│   ├── SentinelUI.lua              # Tab-based UI library (copy from SentinelGather)
│   └── queue_priorities.lua        # Spell queue priority constants
└── lib/
    ├── JSON.lua                    # JSON parser
    └── helpers.lua                 # Shared utilities
```

**Data files** (in `scripts_data/`, not in project):
```
scripts_data/
└── sentinel_duo_farm/
    ├── settings.json               # Persisted UI settings
    └── profiles/
        └── stratholme_undead.lua   # Dungeon farm profiles
```

**Conventions**:
- `require()` uses forward slashes: `require("core/bt/factory")`
- Core/BT/EventBus copied into project (Sylvannas require resolves relative to script folder)
- Global: `_G.SentinelDuoFarm = { app = app }`
- Log prefix: `[SentinelDuoFarm]`

---

## 2. Core Engine — DuoFarmApp

**File**: `runtime/app.lua`

Mirrors `sentinel/runtime/app.lua` pattern. Owns all modules and drives the update loop.

### Lifecycle

```
new(config) → start() → update() (every frame) → stop() → destroy()
```

### Update Loop (each frame)

```
1. sensor_hub:refresh(blackboard)     -- read player, partner, mob state
2. partner_observer:update(blackboard) -- derive partner readiness
3. farm_module:update(blackboard, dt)  -- tick master BT
4. ui:on_update()                      -- sync UI elements
```

### Dependencies

- `_G.SentinelNavClient.client` — resolved lazily via nav_adapter
- `core.object_manager` — for partner and mob scanning
- `core.spell_queue` — for spell casting
- `core.spell_book` — for cooldown checks

### Blackboard Schema

```
player.object           -- game_object
player.position         -- {x, y, z}
player.health_pct       -- 0..1
player.mana_pct         -- 0..1
player.is_alive         -- boolean
player.is_casting       -- boolean
player.is_channeling    -- boolean
player.class_id         -- number (8 = mage)

duo.partner.object      -- game_object | nil
duo.partner.found       -- boolean
duo.partner.position    -- {x, y, z}
duo.partner.health_pct  -- 0..1
duo.partner.is_alive    -- boolean
duo.partner.distance    -- yards
duo.partner.has_ice_block -- boolean (aura check, spell ID 45438)

farm.enabled            -- boolean (UI toggle)
farm.my_role            -- "A" | "B" (set at startup)
farm.active_role        -- "puller" | "aoer" (derived from pull_index + my_role)
farm.profile            -- loaded profile table
farm.current_pull_index -- number (1-based)
farm.dungeon_phase      -- string (current BT phase name)
farm.pulls_completed    -- number
farm.runs_completed     -- number
farm.run_start_ms       -- timestamp
farm.pull_start_ms      -- timestamp

farm.tagged_mobs        -- table of mob GUIDs
farm.tagged_mob_count   -- number
farm.alive_mob_count    -- number
farm.mob_centroid       -- {x, y, z}
farm.centroid_distance  -- yards
farm.mobs_slowed_pct   -- 0..1

farm.kite_loop_index    -- number
farm.is_looting         -- boolean
farm.loot_remaining     -- number
```

---

## 3. Partner Observation System

**File**: `modules/partner/observer.lua`

### Finding the Partner

Scans `core.object_manager.get_all_objects()` for:
- `obj:is_player()` — is a player
- GUID != self GUID — not ourselves
- `obj:is_party_member()` or proximity + faction check
- `obj:get_class() == 8` — is a mage

Caches partner GUID after first find. Subsequent ticks look up by GUID directly.

### Observed State

Each tick writes to blackboard:
- `duo.partner.position` — `partner:get_position()`
- `duo.partner.health_pct` — `partner:get_health_percentage() / 100`
- `duo.partner.is_alive` — `partner:is_alive()`
- `duo.partner.distance` — `player:distance_to(partner)`
- `duo.partner.has_ice_block` — check partner buffs for spell ID 45438

### No Phase Inference Needed

With strict alternation, each bot knows the other's role from `(pull_index % 2)`. The only hard sync is **AoEr waiting for puller's Ice Block** — detected via the `has_ice_block` aura check.

### No CD Tracking Needed

Strict alternation guarantees each mage always has Ice Block + Cold Snap ready for their pull turn. The ~3-4 minutes between a mage's consecutive pulls exceeds all relevant cooldowns (Ice Block 5min with Cold Snap reset, Icy Veins 3min).

---

## 4. Farm State Machine

**File**: `modules/farm/farm_tree.lua`

### Master BT

```lua
BT.priority_selector("duo_farm_root", {
    safety_subtree(),           -- [1] Emergency: HP/wipe/timeout
    enter_instance_subtree(),   -- [2] Zone into instance
    move_to_pull_subtree(),     -- [3] Navigate to pull/standby position
    pull_subtree(),             -- [4] Puller: follow path, tag mobs
    cluster_subtree(),          -- [5] Puller: cluster + Ice Block
    aoe_kite_subtree(),         -- [6] AoEr: kite loop + Blizzard
    loot_subtree(),             -- [7] Both: sweep and loot
    rest_subtree(),             -- [8] Both: eat/drink
    next_pull_subtree(),        -- [9] Advance pull, swap roles
    exit_instance_subtree(),    -- [10] All pulls done → exit
    reset_instance_subtree(),   -- [11] Reset + re-enter
})
```

`priority_selector` re-evaluates from the top every tick, so safety always preempts. Each subtree has entry guards (conditions) that return FAILURE when that phase isn't active, allowing the selector to fall through to the correct phase.

### StateTracker

**File**: `modules/farm/state_tracker.lua`

```lua
StateTracker = {
    my_role = "A",                -- from UI setting
    current_pull_index = 1,       -- 1-based, advances after each pull
    pulls_completed = 0,
    runs_completed = 0,
    run_start_ms = 0,
    pull_start_ms = 0,
}

function StateTracker:get_active_role()
    -- A pulls on odd, B pulls on even
    local is_odd = (self.current_pull_index % 2 == 1)
    if (self.my_role == "A") == is_odd then
        return "puller"
    else
        return "aoer"
    end
end

function StateTracker:advance_pull(profile)
    self.current_pull_index = self.current_pull_index + 1
    self.pulls_completed = self.pulls_completed + 1
    if self.current_pull_index > #profile.pulls then
        -- All pulls done, time to exit + reset
        return true -- dungeon_complete
    end
    return false
end

function StateTracker:reset_for_new_run()
    self.current_pull_index = 1
    self.runs_completed = self.runs_completed + 1
    self.run_start_ms = core.game_time()
end
```

---

## 5. Phase Details

### 5.1 Enter Instance (`phases/enter_instance.lua`)

**Guard**: Not inside instance (`core.get_map_id() ~= profile.metadata.map_id`)

**Sequence**:
1. Navigate to `profile.instance.entrance_pos` via nav_adapter
2. Face entrance and move forward (interact with portal)
3. Wait until `core.get_map_id() == profile.metadata.map_id`
4. Navigate to `profile.instance.inside_start`

### 5.2 Move To Pull (`phases/move_to_pull.lua`)

**Guard**: Inside instance, not already at position, mobs not tagged

**Behavior** (branches on role):
- **Puller**: `nav_adapter:move_to(pull.puller_start)`
- **AoEr**: `nav_adapter:move_to(pull.aoer_standby)`

Returns RUNNING until arrived, then SUCCESS.

### 5.3 Pull (`phases/pull.lua`)

**Guard**: `active_role == "puller"`, at puller_start, AoEr at standby

**Sequence**:
1. Set dungeon_phase = "PULLING"
2. Follow `pull.pull_path` waypoints via `nav_adapter:follow_path()`
3. Each tick while moving: scan for mobs matching `pull.mob_filter` within 40yd
4. Tag untagged mobs: cast Rank 1 Blizzard on clusters, or body pull (run within aggro radius ~8yd)
5. Track tagged mobs by GUID in `farm.tagged_mobs`
6. Continue until: reached last waypoint OR `tagged_mob_count >= pull.expected_mobs`
7. Check for priority targets (Eye of Naxxramas etc.) — if found, both mages focus fire immediately

**AoEr during pull phase**: Stays at `aoer_standby`, returns RUNNING (waiting).

### 5.4 Cluster (`phases/cluster.lua`)

**Guard**: `active_role == "puller"`, pull complete, mobs tagged

**Sequence**:
1. Navigate to `pull.cluster_point` at run speed (mobs chase)
2. When within 3yd of cluster_point: cast Ice Block (spell ID 45438)
3. Mobs stack on the Ice Blocked puller over ~3-5 seconds
4. Wait for Ice Block to expire (10s) or cancel after configurable delay (default 5s)
5. After Ice Block fades: Blink away from mobs toward aoer_standby

**AoEr during cluster**: Watches for `duo.partner.has_ice_block == true` → transitions to aoe_kite.

### 5.5 AoE Kite (`phases/aoe_kite.lua`)

**Guard**: `active_role == "aoer"` AND partner Ice Block detected (or faded after cluster)

**Parallel** (all run concurrently):
1. **KiteEngine**: Follow kite_loop waypoints, manage distance from centroid
2. **AoEr Rotation**: Cast Blizzard/CoC/Nova based on priority table
3. **Priority Target Scanner**: Check for priority_targets mobs, switch to single-target if found
4. **Slow Monitor**: Track mob slow %, escalate if dropping

**Puller during AoE phase**: After Ice Block + Blink, navigate to kite zone and assist with Blizzard spam as secondary DPS.

Continues until `farm.alive_mob_count == 0`.

### 5.6 Loot (`phases/loot.lua`)

**Guard**: All mobs dead (`alive_mob_count == 0`), lootable corpses exist

**Both mages** sweep the kill zone:
1. CorpseScanner finds lootable units within `pull.loot_zone.radius` of `pull.loot_zone.center`
2. Sort by distance
3. Navigate to nearest corpse → loot → repeat
4. Stop when: no lootable corpses remain OR `max_sweep_time_ms` exceeded

### 5.7 Rest (`phases/rest.lua`)

**Guard**: Looting complete, HP or mana below threshold

1. Navigate to nearest `profile.rest.safe_spots[]`
2. Sit and eat/drink (buff food + conjured water)
3. Wait until HP > 90% and mana > 80%
4. Rebuff (Frost Armor, Ice Barrier, Arcane Intellect)

### 5.8 Next Pull (`phases/next_pull.lua`)

**Guard**: Loot + rest complete

1. `state_tracker:advance_pull(profile)`
2. If dungeon complete → set flag for exit phase
3. If not → update `farm.active_role` (swapped), loop back to move_to_pull

### 5.9 Exit Instance (`phases/exit_instance.lua`)

**Guard**: All pulls done

1. Navigate to `profile.instance.exit_pos`
2. Move through portal
3. Wait until outside instance

### 5.10 Reset Instance (`phases/reset_instance.lua`)

**Guard**: Outside instance, partner also outside

1. Bot A issues reset: `core.game_ui.reset_all_instances()` (only one bot resets)
2. Wait 3 seconds
3. Both navigate back to `profile.instance.entrance_pos`
4. Enter instance
5. `state_tracker:reset_for_new_run()`

---

## 6. Kite Engine

**File**: `modules/combat/kite_engine.lua`

### State Machine

```
IDLE → APPROACH_LOOP → KITING → CLEANUP
```

### Core Loop (each tick)

```lua
function KiteEngine:update(blackboard, dt)
    -- 1. Update mob tracking
    self:update_mob_list(blackboard)
    self:update_centroid()

    -- 2. Compute distance to centroid
    local player_pos = blackboard:get("player.position")
    local dist = vec3_distance(player_pos, self._centroid)
    blackboard:set("farm.centroid_distance", dist)
    blackboard:set("farm.mob_centroid", self._centroid)

    -- 3. Distance-based behavior
    if dist < 8 then
        -- EMERGENCY: too close, Frost Nova + Blink handled by rotation
        -- Skip ahead on kite loop to gain distance
        self:skip_waypoints(3)
    elseif dist > 30 then
        -- TOO FAR: pause movement, let mobs catch up
        nav_adapter:stop()
        return
    end

    -- 4. Follow kite loop
    self:advance_loop(blackboard)
end
```

### Centroid Tracking

```lua
function KiteEngine:update_centroid()
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, mob in ipairs(self._mob_list) do
        if mob:is_alive() then
            local pos = mob:get_position()
            sx = sx + pos.x
            sy = sy + pos.y
            sz = sz + pos.z
            n = n + 1
        end
    end
    if n > 0 then
        self._centroid = { x = sx/n, y = sy/n, z = sz/n }
    end
    self._alive_count = n
end
```

### Kite Loop Following

The kite loop is a closed ring of waypoints. The engine advances through them:

```lua
function KiteEngine:advance_loop(blackboard)
    local target = self._loop[self._loop_index]
    local player_pos = blackboard:get("player.position")

    if vec3_distance(player_pos, target) < 3.0 then
        -- Reached waypoint, advance
        self._loop_index = self._loop_index + 1
        if self._loop_index > #self._loop then
            self._loop_index = 1  -- loop back
        end
        target = self._loop[self._loop_index]
    end

    nav_adapter:move_to(target)
end
```

### Slow Monitoring

Each tick, count mobs with active slow debuffs:

```lua
function KiteEngine:update_slow_status()
    local slowed = 0
    for _, mob in ipairs(self._mob_list) do
        if mob:is_alive() then
            -- Check for Blizzard chill, CoC slow, Frost Nova root
            if mob:has_debuff(AURA_IDS.BLIZZARD_CHILL)
               or mob:has_debuff(AURA_IDS.COC_SLOW)
               or mob:has_debuff(AURA_IDS.FROST_NOVA_ROOT) then
                slowed = slowed + 1
            end
        end
    end
    self._slowed_pct = self._alive_count > 0 and (slowed / self._alive_count) or 1.0
end
```

---

## 7. Combat Rotations

### 7.1 Spell Catalog (`modules/combat/spell_catalog.lua`)

Rank-aware spell resolution. At level 58, not all max ranks are available. The catalog
defines all ranks per spell and resolves the highest learned at runtime using
`core.spell_book.has_spell(spell_id)`.

Pattern: reuse `SpellbookResolver` from `sentinel/modules/combat/framework/spellbook_resolver.lua`.

```lua
-- Each spell lists ranks from highest to lowest.
-- resolve() returns the first spell_id where has_spell() returns true.
SPELL_RANKS = {
    BLIZZARD = {
        { id = 27085, rank = 7, level = 68 },  -- TBC max
        { id = 10186, rank = 5, level = 52 },  -- ← highest at 58
        { id = 10185, rank = 4, level = 44 },
        { id = 8427,  rank = 3, level = 36 },
        { id = 6141,  rank = 2, level = 28 },
        { id = 10,    rank = 1, level = 20 },
    },
    FROSTBOLT = {
        { id = 27072, rank = 13, level = 68 },
        { id = 25304, rank = 12, level = 62 },
        { id = 10181, rank = 10, level = 56 }, -- ← highest at 58
        { id = 10180, rank = 9,  level = 50 },
        { id = 10179, rank = 8,  level = 44 },
        { id = 8408,  rank = 7,  level = 38 },
        { id = 8407,  rank = 6,  level = 32 },
        { id = 8406,  rank = 5,  level = 26 },
        { id = 7322,  rank = 4,  level = 20 },
        { id = 837,   rank = 3,  level = 14 },
        { id = 205,   rank = 2,  level = 8 },
        { id = 116,   rank = 1,  level = 4 },
    },
    CONE_OF_COLD = {
        { id = 27087, rank = 6, level = 65 },
        { id = 10161, rank = 5, level = 58 }, -- ← available at 58
        { id = 10160, rank = 4, level = 50 },
        { id = 10159, rank = 3, level = 42 },
        { id = 8492,  rank = 2, level = 34 },
        { id = 120,   rank = 1, level = 26 },
    },
    FROST_NOVA = {
        { id = 27088, rank = 5, level = 65 },
        { id = 10230, rank = 4, level = 54 }, -- ← highest at 58
        { id = 6131,  rank = 3, level = 40 },
        { id = 865,   rank = 2, level = 26 },
        { id = 122,   rank = 1, level = 10 },
    },
    ARCANE_EXPLOSION = {
        { id = 27082, rank = 8, level = 67 },
        { id = 10202, rank = 6, level = 54 }, -- ← highest at 58
        { id = 10201, rank = 5, level = 46 },
        { id = 8439,  rank = 4, level = 38 },
        { id = 8438,  rank = 3, level = 30 },
        { id = 8437,  rank = 2, level = 22 },
        { id = 1449,  rank = 1, level = 14 },
    },
    FIRE_BLAST = {
        { id = 27079, rank = 9, level = 65 },
        { id = 10199, rank = 7, level = 54 }, -- ← highest at 58
        { id = 10197, rank = 6, level = 46 },
        { id = 8413,  rank = 5, level = 38 },
        { id = 8412,  rank = 4, level = 30 },
        { id = 2138,  rank = 3, level = 22 },
        { id = 2137,  rank = 2, level = 14 },
        { id = 2136,  rank = 1, level = 6 },
    },
    ICE_BARRIER = {
        { id = 33405, rank = 6, level = 69 },
        { id = 13033, rank = 4, level = 58 }, -- ← available at 58
        { id = 13032, rank = 3, level = 52 },
        { id = 13031, rank = 2, level = 46 },
        { id = 11426, rank = 1, level = 40 },
    },
    FLAMESTRIKE = {
        { id = 27086, rank = 7, level = 66 },
        { id = 10216, rank = 6, level = 56 }, -- ← highest at 58
        { id = 10215, rank = 5, level = 48 },
        { id = 8423,  rank = 4, level = 40 },
        { id = 8422,  rank = 3, level = 32 },
        { id = 2121,  rank = 2, level = 24 },
        { id = 2120,  rank = 1, level = 16 },
    },
    MANA_SHIELD = {
        { id = 27131, rank = 7, level = 66 },
        { id = 10192, rank = 5, level = 52 }, -- ← highest at 58
        { id = 10191, rank = 4, level = 44 },
        { id = 8495,  rank = 3, level = 36 },
        { id = 8494,  rank = 2, level = 28 },
        { id = 1463,  rank = 1, level = 20 },
    },
    ARCANE_INTELLECT = {
        { id = 27126, rank = 6, level = 65 },
        { id = 10157, rank = 5, level = 56 }, -- ← highest at 58
        { id = 10156, rank = 4, level = 42 },
        { id = 1461,  rank = 3, level = 28 },
        { id = 1460,  rank = 2, level = 14 },
        { id = 1459,  rank = 1, level = 1 },
    },
}

-- Fixed-rank spells (no ranks or single rank)
FIXED_SPELLS = {
    BLIZZARD_R1     = 10,       -- Rank 1 Blizzard (for tagging only)
    FROSTBOLT_R1    = 116,      -- Rank 1 Frostbolt (for tagging only)
    ICE_BLOCK       = 45438,
    COLD_SNAP       = 11958,    -- Talent
    ICY_VEINS       = 12472,    -- Talent
    BLINK           = 1953,
    COUNTERSPELL    = 2139,
    EVOCATION       = 12051,
    ICE_ARMOR       = 10219,    -- R3 (lv50), highest non-TBC rank
    CONJURE_WATER   = 27090,    -- Rank 7 (lv60, may not be available at 58)
    CONJURE_FOOD    = 33717,    -- Rank 7 (lv60, may not be available at 58)
    MANA_GEM        = 27103,    -- Mana Emerald
}

-- Runtime resolver
function SpellCatalog:resolve(spell_key)
    local ranks = SPELL_RANKS[spell_key]
    if not ranks then return FIXED_SPELLS[spell_key] end
    for _, entry in ipairs(ranks) do
        if core.spell_book.has_spell(entry.id) then
            return entry.id
        end
    end
    return nil -- spell not learned at all
end
```

### 7.1b Aura IDs (`modules/combat/aura_ids.lua`)

```lua
AURAS = {
    -- Self buffs
    ICE_BLOCK       = 45438,
    ICE_BARRIER     = 0,    -- resolved at runtime via spell_catalog
    ICY_VEINS       = 12472,
    FROST_ARMOR     = 7301,
    ICE_ARMOR       = 10219,
    ARCANE_INTELLECT = 0,   -- resolved at runtime

    -- Mob debuffs (for slow monitoring)
    BLIZZARD_CHILL  = 12486,  -- Blizzard slow effect
    COC_SLOW        = 120,    -- Cone of Cold slow (uses spell ID)
    FROST_NOVA_ROOT = 122,    -- Frost Nova root (uses base spell ID)
    FROSTBOLT_SLOW  = 116,    -- Frostbolt chill effect

    -- Priority target detection
    POLYMORPH       = 118,    -- for CC'd targets

    -- Partner detection
    PARTNER_ICE_BLOCK = 45438,
}
```

### 7.2 Puller Rotation (`modules/combat/puller_rotation.lua`)

Used during PULL phase. Priority selector:

```
1. Frost Nova        — mobs in melee (< 5yd), need escape
2. Blink             — stuck or mobs blocking path forward
3. R1 Blizzard       — 2+ untagged mobs in 40yd, cast on their cluster
4. R1 Frostbolt      — 1 untagged mob, single tag
5. (continue moving) — body pull mobs within aggro radius
```

Used during CLUSTER phase:

```
1. Ice Block          — arrived at cluster point
2. (wait for expire)
3. Blink              — away from mobs after IB fades
```

Used during AOE_KITE phase (puller assists):

```
Same as AoEr rotation but lower priority (puller is secondary DPS)
```

### 7.3 AoEr Rotation (`modules/combat/aoer_rotation.lua`)

**Off-GCD tree** (every 75ms):
```
1. Ice Barrier         — if not active
2. Icy Veins           — on pull start (once per pull)
3. Mana gem / potion   — mana < 30%
```

**GCD tree** (every 75ms, priority selector):
```
1. Priority target     — if priority_targets mob detected → Frostbolt/Fire Blast/Ice Lance
2. Ice Block           — HP < 15% emergency
3. Frost Nova          — mobs < 5yd, need distance
4. Cone of Cold        — mobs < 10yd, apply slow + damage
5. Blizzard            — on mob centroid, primary DPS + slow
6. Arcane Explosion    — mobs in melee, can't channel (movement)
7. Blink               — mobs < 4yd, can't Nova (on CD)
```

### 7.4 Emergency System (`modules/combat/emergency.lua`)

Cooldown chaining when things go wrong:

```
IF hp < 15%:
    IF Ice Block ready     → cast Ice Block
    ELIF Cold Snap ready   → Cold Snap → Ice Block
    ELIF Blink ready       → Blink away
    ELSE                   → accept death, trigger wipe recovery

IF both mages dead:
    1. Release spirit
    2. Run back to instance portal
    3. Resurrect inside
    4. Rebuff + eat/drink
    5. Resume from failed pull (do not advance pull index)
```

---

## 8. Priority Target System

Profiles define `priority_targets` per pull:

```lua
priority_targets = {
    {
        npc_id = 10411,       -- Eye of Naxxramas
        reason = "kill",      -- "kill" = focus fire, "interrupt" = kick only
        both_mages = true,    -- both switch to this target
    },
    {
        npc_id = 10399,       -- Some caster mob
        reason = "interrupt", -- interrupt casts, don't focus
        both_mages = false,   -- only nearest mage handles
    },
}
```

**Scanner** (runs each tick during pull and aoe_kite phases):
1. Check all alive mobs against `priority_targets[].npc_id`
2. If `reason == "kill"`: both mages (or designated mage) switch target, use single-target rotation (Frostbolt, Fire Blast, Ice Lance) until mob dead
3. If `reason == "interrupt"`: nearest mage uses Counterspell when mob is casting
4. After priority target resolved: resume normal AoE

---

## 9. Loot System

### CorpseScanner (`modules/loot/corpse_scanner.lua`)

```lua
function CorpseScanner:scan(center, radius)
    local corpses = {}
    for _, obj in ipairs(core.object_manager.get_all_objects()) do
        if obj:is_unit()
           and obj:is_dead()
           and (obj:can_be_looted() or obj:has_loot())
           and vec3_distance(obj:get_position(), center) <= radius then
            table.insert(corpses, obj)
        end
    end
    -- Sort by distance from player
    table.sort(corpses, function(a, b)
        return player:distance_to(a) < player:distance_to(b)
    end)
    return corpses
end
```

### SweepController (`modules/loot/sweep_controller.lua`)

State machine: `IDLE → MOVING_TO_CORPSE → LOOTING → NEXT_CORPSE → DONE`

1. Get sorted corpse list from scanner
2. Navigate to nearest
3. When within interact range (~5yd): `core.input.interact_with_object(corpse)`
4. Wait for loot window: poll `core.game_ui.get_loot_item_count() > 0`
5. Loot all items: loop `core.input.loot_item(i)` for i=1..count
6. Close loot: `core.input.close_loot()`
7. Check bags: if bags full, skip remaining corpses
8. Repeat until: no corpses left OR `max_sweep_time_ms` exceeded

---

## 10. Profile System

### Profile Format

Profiles are Lua files stored in `scripts_data/sentinel_duo_farm/profiles/` that return a table.

```lua
-- scripts_data/sentinel_duo_farm/profiles/stratholme_undead.lua
return {
    metadata = {
        name = "Stratholme Undead",
        dungeon = "Stratholme",
        map_id = 329,
        difficulty = "normal",
        min_level = 58,
        author = "Levi",
        version = 1,
    },

    instance = {
        entrance_pos  = { x = 3392.0, y = -3394.0, z = 142.0 },
        entrance_facing = 4.7,
        inside_start  = { x = 3395.0, y = -3380.0, z = 143.0 },
        exit_pos      = { x = 3395.0, y = -3380.0, z = 143.0 },
    },

    pulls = {
        {
            id = "entrance_pack",
            label = "Entrance Street — skeletons + ghouls",

            puller_start = { x = 3401.0, y = -3361.0, z = 142.0 },
            pull_path = {
                { x = 3401.0, y = -3361.0, z = 142.0 },
                { x = 3430.0, y = -3330.0, z = 142.0 },
                { x = 3460.0, y = -3305.0, z = 142.0 },
            },

            cluster_point = { x = 3475.0, y = -3275.0, z = 142.0 },

            aoer_standby = { x = 3480.0, y = -3260.0, z = 142.0 },
            kite_loop = {
                { x = 3480.0, y = -3260.0, z = 142.0 },
                { x = 3510.0, y = -3260.0, z = 142.0 },
                { x = 3510.0, y = -3300.0, z = 142.0 },
                { x = 3480.0, y = -3300.0, z = 142.0 },
            },

            loot_zone = {
                center = { x = 3495.0, y = -3280.0, z = 142.0 },
                radius = 30,
            },

            mob_filter = {
                npc_ids = { 10409, 10411, 10414, 10416 },
                max_level = 63,
            },

            expected_mobs = 30,

            priority_targets = {
                {
                    npc_id = 10411,  -- Eye of Naxxramas
                    reason = "kill",
                    both_mages = true,
                },
            },
        },
        -- ... more pulls
    },

    rest = {
        safe_spots = {
            { x = 3475.0, y = -3275.0, z = 142.0 },
        },
        health_threshold = 0.60,
        mana_threshold = 0.40,
    },

    safety = {
        max_pull_duration_ms = 120000,
        health_abort_pct = 0.10,
        immune_mob_ids = {},
    },

    loot_defaults = {
        sweep_radius = 25,
        max_sweep_time_ms = 15000,
    },
}
```

### ProfileLoader (`profiles/profile_loader.lua`)

```lua
function ProfileLoader:load(profile_name)
    local path = "sentinel_duo_farm/profiles/" .. profile_name .. ".lua"
    local ok, content = pcall(core.read_data_file, path)
    if not ok then return nil, "File not found: " .. path end

    local chunk, err = load(content, profile_name)
    if not chunk then return nil, "Lua parse error: " .. err end

    local ok2, profile = pcall(chunk)
    if not ok2 then return nil, "Lua execution error: " .. profile end

    local valid, errors = ProfileSchema:validate(profile)
    if not valid then return nil, "Schema validation: " .. table.concat(errors, ", ") end

    return profile
end
```

### ProfileSchema (`profiles/profile_schema.lua`)

Validates:
- `metadata.name` — string, required
- `metadata.map_id` — number, required
- `instance.entrance_pos` — {x,y,z}, required
- `pulls` — array, at least 1 entry
- Each pull has: `pull_path` (array of {x,y,z}), `cluster_point`, `kite_loop`, `aoer_standby`, `puller_start`
- Optional: `mob_filter`, `priority_targets`, `loot_zone`

---

## 11. Profile Recorder

**File**: `modules/recorder/recorder_module.lua`

### Activation

Toggled via UI control tab. When active, registers keybind callbacks.

### Keybinds

| Key | Action | Overlay Color |
|-----|--------|---------------|
| F1  | Add pull_path waypoint | Yellow |
| F2  | Mark cluster_point | Red |
| F3  | Add kite_loop waypoint | Cyan |
| F4  | Mark aoer_standby | Green |
| F5  | Mark puller_start | Orange |
| F6  | Mark loot_zone center | Purple |
| F7  | Finalize current pull | Flash all |
| F8  | Export to file | Save notification |

### WaypointMarker (`modules/recorder/waypoint_marker.lua`)

Buffers for current pull being recorded:

```lua
WaypointMarker = {
    _pull_path = {},
    _kite_loop = {},
    _cluster_point = nil,
    _aoer_standby = nil,
    _puller_start = nil,
    _loot_center = nil,
    _finalized_pulls = {},
    _instance_data = {
        entrance_pos = nil,
        inside_start = nil,
        exit_pos = nil,
    },
}
```

On F7 (finalize): packages current buffers into a pull table, appends to `_finalized_pulls`, clears buffers.

### Exporter (`modules/recorder/exporter.lua`)

Serializes `_finalized_pulls` + `_instance_data` into a Lua return table string. Writes to `scripts_data/sentinel_duo_farm/profiles/{name}.lua` via `core.write_data_file()`.

Generates formatted Lua:
```lua
return {
    metadata = {
        name = "recorded_profile",
        map_id = 329,
        version = 1,
    },
    instance = { ... },
    pulls = { ... },
    rest = { safe_spots = {}, health_threshold = 0.60, mana_threshold = 0.40 },
    safety = { max_pull_duration_ms = 120000, health_abort_pct = 0.10 },
}
```

### Overlay During Recording

Draws all recorded waypoints as 3D circles:
- Yellow circles + lines: pull_path
- Red circle: cluster_point
- Cyan circles + lines: kite_loop (closed loop)
- Green circle: aoer_standby
- Orange circle: puller_start
- Purple circle: loot_zone with radius ring

---

## 12. UI System

**File**: `modules/ui/window.lua`

Uses shared `rotation_settings_ui.lua` TabBuilder.

### Control Tab (`tabs/control_tab.lua`)

| Element | Type | ID | Purpose |
|---------|------|----|---------|
| Role | Dropdown | `sdf_role` | "Bot A" / "Bot B" |
| Profile | Dropdown | `sdf_profile` | Lists profiles from scripts_data/ |
| Start/Stop | Button | `sdf_toggle` | Toggles `farm.enabled` |
| Recorder | Checkbox | `sdf_recorder` | Activates recorder module |
| Reset Count | Label | — | Shows `runs_completed` |

### Status Tab (`tabs/status_tab.lua`)

Displays live state:
- Phase: "PULLING", "CLUSTERING", "AOE_KITE", "LOOTING", etc.
- Pull: "Pull 2 / 4"
- Role: "Puller" or "AoEr"
- Partner: "Found — Alive — 12yd away" or "Not found"
- Mobs: "Tagged: 28 | Alive: 15 | Dead: 13"
- Run timer: "Run 3 — 04:32"
- Pull timer: "Pull — 01:15"

### Settings Tab (`tabs/settings_tab.lua`)

| Setting | Type | ID | Default |
|---------|------|----|---------|
| Health abort % | Slider | `sdf_health_abort` | 10% |
| Mana drink threshold | Slider | `sdf_mana_drink` | 40% |
| Max pull duration | Slider | `sdf_max_pull_dur` | 120s |
| Ice Block cancel delay | Slider | `sdf_ib_delay` | 5s |
| Loot sweep time | Slider | `sdf_loot_time` | 15s |

### Debug Tab (`tabs/debug_tab.lua`)

- Blackboard dump (farm.* and duo.* keys)
- BT phase trace (last 10 phase transitions)
- Partner observation raw data
- Event log (last 20 events)

---

## 13. Diagnostics Overlay

**File**: `modules/ui/overlay/farm_overlay.lua`

Toggle: menu checkbox `"sdf_show_overlay"` (persisted).

Renders via `core.graphics.circle_3d` and `core.graphics.line_3d`:

| Element | Color | When |
|---------|-------|------|
| Pull path lines + circles | Yellow | Always (if overlay on) |
| Kite loop (closed) | Cyan | Always |
| Cluster point (5yd radius) | Red | Always |
| AoEr standby | Green | Always |
| Puller start | Orange | Always |
| Loot zone ring | Purple dashed | During loot phase |
| Mob centroid | White pulsing | During aoe_kite |
| Partner marker | Blue | Always |
| Priority target highlight | Red on mob | When priority mob alive |
| Distance ring | Dotted white | Around player at 15yd |

---

## 14. Implementation Order

### Phase 1 — Foundation (no combat)
1. Project scaffold: `main.lua`, `header.lua`, `init.lua`
2. Copy core: blackboard, event_bus, error_boundary, bt/
3. Copy integrations: nav_adapter, shared UI lib
4. `runtime/app.lua` — lifecycle + update loop
5. `runtime/sensor_hub.lua` — player + partner scanning
6. `modules/partner/observer.lua` — find + track partner
7. `profiles/profile_loader.lua` + `profile_schema.lua`
8. UI skeleton: window.lua + control_tab (role, profile, start/stop)

### Phase 2 — Movement (navigate but no combat)
1. `modules/farm/module.lua` + `farm_tree.lua` (master BT with placeholder phases)
2. `modules/farm/state_tracker.lua`
3. `phases/enter_instance.lua`
4. `phases/move_to_pull.lua`
5. `phases/exit_instance.lua` + `phases/reset_instance.lua`
6. `phases/next_pull.lua`

### Phase 3 — Pull + Cluster (combat begins)
1. `modules/combat/spell_ids.lua` + `aura_ids.lua`
2. `modules/combat/puller_rotation.lua`
3. `phases/pull.lua` — follow path, tag mobs
4. `phases/cluster.lua` — Ice Block clustering
5. Mob tracking in sensor_hub (tagged mobs, alive count)

### Phase 4 — AoE Kite
1. `modules/combat/kite_engine.lua` — centroid, distance, loop following
2. `modules/combat/aoer_rotation.lua` — Blizzard/CoC/Nova cycle
3. `phases/aoe_kite.lua` — wire kite engine + rotation into BT
4. Priority target scanning

### Phase 5 — Loot + Rest
1. `modules/loot/corpse_scanner.lua`
2. `modules/loot/sweep_controller.lua`
3. `phases/loot.lua`
4. `phases/rest.lua` — eat/drink/rebuff

### Phase 6 — Safety + Polish
1. `phases/safety.lua` — emergency, wipe recovery
2. `modules/combat/emergency.lua` — cooldown chaining
3. UI: status_tab, settings_tab, debug_tab
4. `modules/ui/overlay/farm_overlay.lua`

### Phase 7 — Recorder
1. `modules/recorder/recorder_module.lua`
2. `modules/recorder/waypoint_marker.lua`
3. `modules/recorder/exporter.lua`
4. UI: recorder_tab

---

## 15. Verification Plan

### In-Game Testing (via Sylvannas console + MCP)

1. **Foundation**: Load plugin, verify `_G.SentinelDuoFarm` exists, check partner detection
2. **Movement**: Start bot, verify it navigates to instance entrance, enters, moves to pull start
3. **Pull**: Verify puller follows path, R1 Blizzard tags mobs, mob count tracked
4. **Cluster**: Verify puller runs to cluster point, Ice Blocks, mobs stack
5. **AoE Kite**: Verify AoEr starts kite loop when partner IB detected, Blizzard spam works
6. **Loot**: Verify corpse scanning, navigate-and-loot sweep
7. **Reset**: Verify exit → reset → re-enter flow
8. **Duo sync**: Run both instances, verify alternation and Ice Block sync
9. **Recorder**: Record a simple profile, export, load, run

### Diagnostic Commands (game_eval via MCP)

```lua
-- Check partner found
_G.SentinelDuoFarm.app._blackboard:get("duo.partner.found")

-- Check current phase
_G.SentinelDuoFarm.app._blackboard:get("farm.dungeon_phase")

-- Check mob count
_G.SentinelDuoFarm.app._blackboard:get("farm.alive_mob_count")

-- Force pull advance
_G.SentinelDuoFarm.app._farm_module._state_tracker:advance_pull(profile)
```

---

## 16. API Patterns & Corrections

### Self-Cast Spells

No `queue_spell_self()` exists. Self-cast spells (Ice Block, Blink, Frost Nova, Ice Barrier, etc.)
use the player object as target:

```lua
local player = core.object_manager.get_local_player()
core.spell_queue.queue_spell_target(SPELLS.ICE_BLOCK, player, priority)
-- OR direct cast for instant off-GCD:
core.input.cast_target_spell(SPELLS.ICE_BLOCK, player)
```

### Mob Identity Tracking

No GUID API on game_object. Mob tracking strategy:

- Use `get_npc_id()` for type identification (filtering)
- Use the object reference itself as a table key within a single tick
- Rebuild mob lists each tick from `core.object_manager.get_all_objects()` filtered by:
  - `not obj:is_dead()` (alive)
  - `obj:affecting_combat()` (in combat with us)
  - `obj:is_enemy_with(player)` (hostile)
- Count-based tracking: `farm.alive_mob_count` recomputed each tick, no persistent GUID map

### Instance Reset

Use `core.input.reset_all_instances()` (will be implemented in the Sylvannas API).

```lua
core.input.reset_all_instances()
-- Wait ~3 seconds for server to process
-- Then navigate to entrance and re-enter
```

### Instance Entry

Instance portals are area triggers (walk-through), NOT interactable objects. Entry is done by
navigating to `entrance_pos` and moving forward through the portal coordinates. Detect entry
by polling `core.get_map_id()` until it matches `profile.metadata.map_id`.

### Ice Block Cancel

Use `core.input.cancel_buff(buff_ptr)`. To get the buff reference:
```lua
local buffs = player:get_buffs()
for _, buff in ipairs(buffs) do
    if buff.spell_id == SPELLS.ICE_BLOCK then
        core.input.cancel_buff(buff)
        break
    end
end
```

### Loot Interaction

```lua
-- Step 1: interact with corpse
core.input.interact_with_object(corpse)

-- Step 2: wait for loot window (poll)
-- core.game_ui.get_loot_item_count() > 0

-- Step 3: loot all items
for i = 1, core.game_ui.get_loot_item_count() do
    core.input.loot_item(i)
end

-- Step 4: close
core.input.close_loot()
```

---

## 17. Edge Cases & Recovery

### Nav Failure During Phases

Each phase handles nav failure differently:
- **During pull**: If stuck, cast Blink. If still stuck, Frost Nova + run. If nav fails completely, abort pull and skip to next.
- **During kite**: If stuck, skip to next kite loop waypoint. If still stuck, Blink. KiteEngine tracks consecutive stuck ticks.
- **During loot**: Skip current corpse, try next one.
- **During movement**: Standard nav_adapter stuck recovery (already has 6-stage escalation).

### Mob Evade/Reset During Pull

Detect via: `farm.alive_mob_count` dropping unexpectedly during pull phase (before kill phase).

If `alive_mob_count < expected * 0.5` and mobs are disappearing (not dying):
1. Stop pulling
2. If remaining mobs > 5: proceed to cluster with what we have
3. If remaining mobs < 5: skip pull, advance to next

### Single Mage Death

- **Puller dies during pull**: AoEr Ice Blocks → waits for aggro drop → runs to safe spot. Skip pull.
- **Puller dies during cluster**: AoEr Blinks away → kites what they can solo. Emergency mode.
- **AoEr dies during kite**: Puller assists with Blizzard. If can't solo, puller also dies → wipe recovery.
- **Wipe recovery**: Both release → run back → rez inside → rebuff → retry failed pull.

### Instance Lockout (5/hour)

Track `reset_timestamps` (last 5 reset times). Before attempting reset:
```lua
-- Prune resets older than 1 hour
-- If #recent_resets >= 5, wait until oldest expires
```

Display lockout countdown in status tab.

### Partner Not Found at Startup

If `duo.partner.found == false`:
1. Wait at instance entrance for up to 60 seconds
2. Display "Waiting for partner..." in status tab
3. If partner found: proceed
4. If timeout: stop bot, display error

### Conjure Supplies Phase

Added to rest phase. Between runs or before first pull:
1. If conjured water count < threshold: conjure water (highest learned rank)
2. If conjured food count < threshold: conjure food
3. If mana gem not in bags: conjure mana gem

Conjure spell ranks resolved via SpellCatalog at runtime.

---

## 18. Stratholme UD Mob Reference (from MaNGOS DB)

### Undead Side Hostile Mobs

| Entry | Name | Level | Type | Speed | Notes |
|-------|------|-------|------|-------|-------|
| 10381 | Ravaged Cadaver | 56-57 | Undead | 1.14 | Melee |
| 10382 | Mangled Cadaver | 55-56 | Undead | 1.14 | Melee |
| 10384 | Spectral Citizen | 55-56 | Undead | 1.14 | Melee |
| 10385 | Ghostly Citizen | 56-57 | Undead | 1.14 | Melee |
| 10387 | Vengeful Phantom | 56-57 | Undead | 1.14 | Melee |
| 10390 | Skeletal Guardian | 55-56 | Undead | 1.14 | Melee |
| 10391 | Skeletal Berserker | 56-57 | Undead | 1.14 | Melee |
| 10405 | Plague Ghoul | 57-58 | Undead | 1.14 | Melee, slow walk |
| 10406 | Ghoul Ravener | 58-59 | Undead | 1.14 | Melee |
| 10407 | Fleshflayer Ghoul | 59-60 | Undead | 1.14 | Melee |
| 10408 | Rockwing Gargoyle | 57-58 | Undead | **1.43** | **Fast** — kite priority |
| 10409 | Rockwing Screecher | 58-59 | Undead | 1.14 | Melee |
| 10411 | **Eye of Naxxramas** | 55-57 | Undead | 1.14 | **PRIORITY KILL** |
| 10412 | Crypt Crawler | 58-59 | Undead | 1.14 | Melee |
| 10413 | Crypt Beast | 59-60 | Undead | 1.14 | Melee |
| 10414 | Patchwork Horror | 57-58 | Undead | 1.14 | Melee |
| 10416 | Bile Spewer | 59-60 | Undead | 1.14 | Melee |
| 10417 | Venom Belcher | 60-61 | Undead | 1.14 | Melee |
| 10463 | Shrieking Banshee | 57-58 | Undead | 1.14 | **CASTER** — interrupt/LoS |
| 10464 | Wailing Banshee | 58-59 | Undead | 1.14 | **CASTER** — interrupt/LoS |

### Caster Threats (humanoid, type 7)

| Entry | Name | Level | Notes |
|-------|------|-------|-------|
| 10398 | Thuzadin Shadowcaster | 58-59 | **CASTER** — must LoS or interrupt |
| 10399 | Thuzadin Acolyte | 59-60 | **CASTER** — must LoS or interrupt |
| 10400 | Thuzadin Necromancer | 60-61 | **CASTER** — summons skeletons |

### Bosses (not typically engaged in farm runs)

| Entry | Name | Level |
|-------|------|-------|
| 10436 | Baroness Anastari | 59 |
| 10437 | Nerub'enkan | 60 |
| 10438 | Maleki the Pallid | 61 |
| 10440 | Baron Rivendare | 62 |

---

## 19. Key Dependencies

| System | Depends On | API Used |
|--------|-----------|----------|
| PartnerObserver | core.object_manager | get_all_objects(), is_player(), get_class(), is_party_member() |
| SensorHub | core.object_manager, izi_sdk | get_position(), get_health_percentage(), has_buff() |
| NavAdapter | _G.SentinelNavClient.client | move_to(), follow_path(), stop(), is_moving() |
| Pull phase | core.spell_queue | queue_spell_position() (R1 Blizzard) |
| Cluster phase | core.spell_queue | queue_spell_target(ICE_BLOCK, player) |
| AoE Kite | core.spell_queue, kite_engine | queue_spell_position() (Blizzard on centroid) |
| Loot | core.input | interact_with_object(), loot_item(), close_loot() |
| Profile Loader | core.read_data_file | Load Lua from scripts_data/ |
| Recorder | core.write_data_file | Export profile to scripts_data/ |
| SpellCatalog | core.spell_book | has_spell(), is_spell_learned() |
| UI | shared/SentinelUI | TabBuilder, widgets |
| Overlay | core.graphics | circle_3d(), line_3d() |
| IB Cancel | core.input | cancel_buff(buff_ptr) |

---

## 20. Files to Copy from Existing Projects

These files are copied per workspace convention (`require()` resolves relative to script folder):

| Source | Destination | Notes |
|--------|-------------|-------|
| `sentinel/core/blackboard.lua` | `SentinelDuoFarm/core/blackboard.lua` | Key-value store |
| `sentinel/core/event_bus.lua` | `SentinelDuoFarm/core/event_bus.lua` | Pub-sub |
| `sentinel/core/error_boundary.lua` | `SentinelDuoFarm/core/error_boundary.lua` | Error handling |
| `sentinel/core/bt/*` | `SentinelDuoFarm/core/bt/*` | Entire BT library (7 files) |
| `sentinel/integrations/nav_client/adapter.lua` | `SentinelDuoFarm/integrations/nav_adapter.lua` | Nav client wrapper |
| `SentinelGather/shared/rotation_settings_ui.lua` | `SentinelDuoFarm/shared/SentinelUI.lua` | UI library (renamed) |
| `SentinelGather/lib/JSON.lua` | `SentinelDuoFarm/lib/JSON.lua` | JSON parser |
| `sentinel/modules/combat/framework/spellbook_resolver.lua` | Pattern reference | SpellCatalog rank resolution |
