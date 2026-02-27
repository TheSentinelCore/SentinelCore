# Phase 3: AoE Tactical System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an AoE kiting tactic that gathers enemy clusters, roots them, and blizzards — so a Frost Mage dynamically switches between single-target (1 mob) and AoE kite (3+ cluster).

**Architecture:** The AoE system layers on Phase 1's tactic framework. A new `AoEKiteTactic` registers alongside `SingleTargetTactic` in the `TacticalSelector`. `PositioningService` computes kite vectors and AoE center points. `CombatContext` gains pack fields from `PackTracker`. `ExplorationService` gains a `cluster_seek` mode that biases frontier selection toward dense spawn areas. `TargetingService` gains cluster scoring so the bot prefers pulling near groups. Frost.lua's `aoe()` method gains Blizzard as a `position_spell` action.

**Tech Stack:** Lua 5.1 (Sylvannas runtime), forward-slash requires, setmetatable OOP, ActionBuilder framework, NavigationAdapter async movement.

---

### Task 1: Add pack fields to CombatContext

**Files:**
- Modify: `SentinelCore/ai/CombatContext.lua` (lines 83-249)
- Test: `SentinelCore/tests/test_ai006_combat_context.lua`

**Context:** CombatContext currently builds a flat numeric table from Blackboard + game objects. It already has `enemy_count` and `nearest_enemy_distance`. We need to add pack-awareness fields that downstream consumers (tactics, rotations, positioning) can use.

**Step 1: Add pack fields to CombatContext.build()**

Add after the `enemy_count` / `nearest_enemy_distance` computation block (around line 173), before the `local ctx = {` table construction (line 179):

```lua
-- Pack data (from blackboard, populated by PackTracker in Client.lua)
local pack_count = bb:get("pack.count", 0)
local pack_spread = bb:get("pack.spread", 0)
local pack_centroid_x = 0
local pack_centroid_y = 0
local pack_centroid_z = 0
local pack_centroid = bb:get("pack.centroid")
if pack_centroid then
    pack_centroid_x = pack_centroid.x or 0
    pack_centroid_y = pack_centroid.y or 0
    pack_centroid_z = pack_centroid.z or 0
end
local pack_gathered_count = bb:get("pack.gathered_count", 0)
```

Then add these keys to the `local ctx = {` table, after the `nearest_enemy_distance` line:

```lua
-- Pack (from PackTracker)
pack_count = pack_count,
pack_spread = pack_spread,
pack_centroid_x = pack_centroid_x,
pack_centroid_y = pack_centroid_y,
pack_centroid_z = pack_centroid_z,
pack_gathered_count = pack_gathered_count,
```

**Step 2: Verify PackTracker writes these blackboard keys**

Read `SentinelCore/core/Client.lua` to confirm the PackTracker update block writes `pack.count`, `pack.spread`, `pack.centroid`, `pack.gathered_count` to the blackboard. If it doesn't, add the missing writes.

**Step 3: Add test for pack fields**

In `test_ai006_combat_context.lua`, add a test that creates a mock blackboard with pack keys set and verifies the built context contains the pack fields.

**Step 4: Commit**

```bash
git add SentinelCore/ai/CombatContext.lua SentinelCore/tests/test_ai006_combat_context.lua
git commit -m "feat(context): add pack fields to CombatContext"
```

---

### Task 2: Create PositioningService

**Files:**
- Create: `SentinelCore/services/PositioningService.lua`
- Test: `SentinelCore/tests/test_sc031_positioning_service.lua`

**Context:** PositioningService is a stateless utility that computes two things: (1) safe kite direction away from enemies, and (2) optimal AoE center point for a group of enemies. It does NOT handle movement — it returns positions that other systems consume.

**Step 1: Create PositioningService module**

```lua
local PositioningService = {}

--- Compute the centroid (average position) of a list of positions.
---@param positions table[] Array of {x, y, z} tables
---@return table {x, y, z} or nil if empty
function PositioningService.centroid(positions)
    if not positions or #positions == 0 then return nil end
    local sx, sy, sz = 0, 0, 0
    for i = 1, #positions do
        local p = positions[i]
        sx = sx + (p.x or 0)
        sy = sy + (p.y or 0)
        sz = sz + (p.z or 0)
    end
    local n = #positions
    return { x = sx / n, y = sy / n, z = sz / n }
end

--- Compute kite direction: unit vector pointing AWAY from threat centroid.
--- Returns a position `distance` yards from `from_pos` in the opposite direction.
---@param from_pos table {x, y, z} Player position
---@param threat_centroid table {x, y, z} Center of enemies
---@param distance number How far to kite (yards)
---@return table {x, y, z} Target kite position
function PositioningService.kite_position(from_pos, threat_centroid, distance)
    if not from_pos or not threat_centroid then return from_pos end
    local dx = (from_pos.x or 0) - (threat_centroid.x or 0)
    local dy = (from_pos.y or 0) - (threat_centroid.y or 0)
    local dz = (from_pos.z or 0) - (threat_centroid.z or 0)
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then
        -- Enemies on top of us, pick arbitrary direction (+x)
        return { x = (from_pos.x or 0) + distance, y = from_pos.y or 0, z = from_pos.z or 0 }
    end
    local nx, ny, nz = dx / len, dy / len, dz / len
    return {
        x = (from_pos.x or 0) + nx * distance,
        y = (from_pos.y or 0) + ny * distance,
        z = (from_pos.z or 0) + nz * distance,
    }
end

--- Compute optimal AoE placement center: the centroid of enemies clamped to
--- `max_range` yards from the player (Blizzard has 30yd range).
---@param player_pos table {x, y, z}
---@param enemy_positions table[] Array of {x, y, z}
---@param max_range number Maximum cast range (e.g. 30.0 for Blizzard)
---@return table {x, y, z} AoE center or nil
function PositioningService.aoe_center(player_pos, enemy_positions, max_range)
    local center = PositioningService.centroid(enemy_positions)
    if not center or not player_pos then return center end

    -- Clamp to max_range from player
    local dx = (center.x or 0) - (player_pos.x or 0)
    local dy = (center.y or 0) - (player_pos.y or 0)
    local dz = (center.z or 0) - (player_pos.z or 0)
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist <= max_range then return center end

    -- Scale toward player
    local scale = max_range / dist
    return {
        x = (player_pos.x or 0) + dx * scale,
        y = (player_pos.y or 0) + dy * scale,
        z = (player_pos.z or 0) + dz * scale,
    }
end

--- Check if a position is within a given distance from reference.
---@param pos table {x, y, z}
---@param ref table {x, y, z}
---@param range number
---@return boolean
function PositioningService.in_range(pos, ref, range)
    if not pos or not ref then return false end
    local dx = (pos.x or 0) - (ref.x or 0)
    local dy = (pos.y or 0) - (ref.y or 0)
    local dz = (pos.z or 0) - (ref.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= range
end

return PositioningService
```

**Step 2: Write tests**

Test file `test_sc031_positioning_service.lua` with the standard `T = require("tests/TestUtil")` pattern. Tests:

1. `centroid` — averages 3 positions correctly, returns nil for empty
2. `kite_position` — returns position in opposite direction at correct distance
3. `kite_position` — handles zero-distance (enemies on top of player)
4. `aoe_center` — returns enemy centroid when within range
5. `aoe_center` — clamps centroid to max_range when too far
6. `in_range` — returns true/false correctly at boundary

**Step 3: Register test in run_all.lua**

Add `"tests/test_sc031_positioning_service"` to the tests array.

**Step 4: Commit**

```bash
git add SentinelCore/services/PositioningService.lua SentinelCore/tests/test_sc031_positioning_service.lua SentinelCore/tests/run_all.lua
git commit -m "feat(services): add PositioningService for kite vectors and AoE placement"
```

---

### Task 3: Create AoEKiteTactic

**Files:**
- Create: `SentinelCore/tactics/AoEKiteTactic.lua`
- Test: `SentinelCore/tests/test_ai029_aoe_kite_tactic.lua`

**Context:** AoEKiteTactic is the second tactic registered with TacticalSelector. It mirrors SingleTargetTactic's structure (extends Tactic base class, 2 phases) but with AoE-specific preconditions, utility scoring, and config. The tactic phases delegate to the same `deps.combat_node` and `deps.pull_node` — the rotation engine handles AoE spell selection via the `aoe()` method when `enemy_count >= aoe_threshold`.

**Step 1: Create AoEKiteTactic**

File: `SentinelCore/tactics/AoEKiteTactic.lua`

```lua
local Tactic = require("ai/Tactic")
local BT = require("ai/BehaviorTree")

local AoEKiteTactic = {}
AoEKiteTactic.__index = AoEKiteTactic
setmetatable(AoEKiteTactic, { __index = Tactic })

function AoEKiteTactic:new()
    local o = Tactic.new(self, {
        name = "aoe_kite",

        preconditions = function(ctx)
            -- Only available when 3+ enemies detected in a cluster
            local pack_count = tonumber(ctx.pack_count) or 0
            local mana_pct = tonumber(ctx.player_mana_pct) or 0
            return pack_count >= 3 and mana_pct > 0.25
        end,

        utility = function(ctx, advisor)
            local base = 0.4
            local pack_count = tonumber(ctx.pack_count) or 0
            local mana_pct = tonumber(ctx.player_mana_pct) or 1.0

            -- Scale with pack density
            if pack_count >= 5 then
                base = 0.85
            elseif pack_count >= 4 then
                base = 0.75
            elseif pack_count >= 3 then
                base = 0.65
            end

            -- Penalize at low mana (AoE is expensive)
            if mana_pct < 0.35 then
                base = base * 0.5
            elseif mana_pct < 0.50 then
                base = base * 0.75
            end

            return base
        end,

        phases = {
            {
                name = "engage",
                enter_if = function(ctx)
                    return ctx.has_target and not ctx.in_combat
                end,
                tick = function(ctx, deps)
                    if deps.pull_node then
                        return deps.pull_node:tick()
                    end
                    return BT.Status.FAILURE
                end,
                exit_if = function(ctx)
                    return ctx.in_combat
                end,
            },
            {
                name = "aoe_combat",
                enter_if = function(ctx)
                    return ctx.in_combat
                end,
                tick = function(ctx, deps)
                    if deps.combat_node then
                        return deps.combat_node:tick()
                    end
                    return BT.Status.FAILURE
                end,
                exit_if = function(ctx)
                    return not ctx.in_combat and not ctx.target_alive
                end,
            },
        },

        rest_config = {
            drink_below = 0.40,   -- AoE is mana-intensive, drink sooner
            eat_below = 0.60,
            drink_until = 0.90,   -- Drink to higher mana for AoE
            eat_until = 0.90,
        },
        target_config = {
            prefer_clusters = true,
        },
        explore_config = {
            mode = "cluster_seek",
        },
    })
    return o
end

return AoEKiteTactic
```

**Step 2: Write tests**

Test file `test_ai029_aoe_kite_tactic.lua`:

1. **preconditions**: true when pack_count >= 3 and mana > 25%, false otherwise
2. **utility scoring**: higher for larger packs, lower at low mana
3. **utility vs SingleTarget**: AoE scores higher than ST for 3+ packs with sufficient mana
4. **phases**: engage enters on has_target+not_in_combat, combat enters on in_combat
5. **rest_config**: drink_below=0.40, eat_below=0.60
6. **target_config**: prefer_clusters=true
7. **explore_config**: mode="cluster_seek"

**Step 3: Register test**

Add `"tests/test_ai029_aoe_kite_tactic"` to run_all.lua.

**Step 4: Commit**

```bash
git add SentinelCore/tactics/AoEKiteTactic.lua SentinelCore/tests/test_ai029_aoe_kite_tactic.lua SentinelCore/tests/run_all.lua
git commit -m "feat(tactics): add AoEKiteTactic for multi-target kite grinding"
```

---

### Task 4: Register AoEKiteTactic in Client.lua

**Files:**
- Modify: `SentinelCore/core/Client.lua`

**Context:** Client.lua creates the TacticalSelector and registers tactics. Currently only SingleTargetTactic is registered. We need to add AoEKiteTactic.

**Step 1: Add require and registration**

Near the top of Client.lua where SingleTargetTactic is required, add:
```lua
local AoEKiteTactic = require("tactics/AoEKiteTactic")
```

In the tactical selector setup section, after `selector:register(SingleTargetTactic:new())`, add:
```lua
selector:register(AoEKiteTactic:new())
```

**Step 2: Commit**

```bash
git add SentinelCore/core/Client.lua
git commit -m "feat(client): register AoEKiteTactic in TacticalSelector"
```

---

### Task 5: Add cluster scoring bias to TargetingService

**Files:**
- Modify: `SentinelCore/services/TargetingService.lua`
- Test: `SentinelCore/tests/test_sc007_targeting_service.lua`

**Context:** TargetingService scores enemy candidates for target selection. When the active tactic has `target_config.prefer_clusters = true`, candidates near clusters should score higher. The tactic's `target_config` is accessible via `blackboard.get("tactical.target_config")`.

**Step 1: Read TargetingService scoring logic**

Read the full scoring section of TargetingService to understand where to inject cluster bias. Look for the candidate scoring loop and the score calculation.

**Step 2: Add cluster proximity bonus**

In the scoring loop, after the base score calculation, add:

```lua
-- Cluster bonus: boost score for targets near other enemies (AoE opportunity)
local target_config = self._bb:get("tactical.target_config")
if target_config and target_config.prefer_clusters then
    local nearby = 0
    for j = 1, #candidates do
        if j ~= i then
            local other_pos = candidates[j].position
            if other_pos and candidate_pos then
                local d = distance_3d(candidate_pos, other_pos)
                if d <= 15.0 then  -- within AoE clump range
                    nearby = nearby + 1
                end
            end
        end
    end
    score = score + nearby * 0.15  -- +15% per nearby enemy
end
```

**Step 3: Wire tactic target_config to blackboard**

In the `build_tactical_combat_node` function in `GrindService.lua`, after tactic selection, write the tactic's target_config to the blackboard:

```lua
local active = selector:select(ctx)
if active then
    bb:set("tactical.target_config", active:get_target_config())
end
```

**Step 4: Add test**

Add a test to `test_sc007_targeting_service.lua` that verifies cluster proximity bonus is applied when `tactical.target_config.prefer_clusters` is set on the blackboard.

**Step 5: Commit**

```bash
git add SentinelCore/services/TargetingService.lua SentinelCore/services/GrindService.lua SentinelCore/tests/test_sc007_targeting_service.lua
git commit -m "feat(targeting): add cluster scoring bias for AoE tactic"
```

---

### Task 6: Add cluster_seek mode to ExplorationService

**Files:**
- Modify: `SentinelCore/services/ExplorationService.lua`
- Test: `SentinelCore/tests/test_sc020_exploration_service.lua`

**Context:** ExplorationService has a `frontier` mode and a `pursuit` mode. We need a `cluster_seek` mode that biases frontier candidate scoring toward cells where enemy clusters have been recently sighted. The active tactic's `explore_config.mode` is written to the blackboard by the tactical system.

**Step 1: Read ExplorationService cell scoring**

Read the frontier candidate scoring section to understand the weight system (`weight_novelty`, `weight_sighting`, `weight_travel`, etc.).

**Step 2: Add cluster_seek mode**

In the frontier candidate scoring, add a cluster sighting weight. When `mode == "cluster_seek"`:
- Cells where multiple enemies were sighted together get a `weight_cluster` bonus (default 0.4)
- Track `cell.cluster_sightings` (number of times 3+ enemies were seen in this cell)

In the `update()` method where enemies are scanned, if 3+ enemies are within a cell's area, increment that cell's `cluster_sightings` counter.

In the scoring function, add:
```lua
if mode == "cluster_seek" and cell.cluster_sightings and cell.cluster_sightings > 0 then
    score = score + weights.weight_cluster * math.min(cell.cluster_sightings, 5) / 5
end
```

**Step 3: Wire tactic explore_config to blackboard**

In `GrindService.lua`'s `build_tactical_combat_node`, write the explore config:
```lua
bb:set("tactical.explore_config", active:get_explore_config())
```

In ExplorationService, read the mode from blackboard:
```lua
local explore_config = self._bb:get("tactical.explore_config")
local mode = explore_config and explore_config.mode or "frontier"
```

**Step 4: Add test**

Test that cluster_seek mode produces higher scores for cells with cluster sightings.

**Step 5: Commit**

```bash
git add SentinelCore/services/ExplorationService.lua SentinelCore/services/GrindService.lua SentinelCore/tests/test_sc020_exploration_service.lua
git commit -m "feat(exploration): add cluster_seek mode for AoE tactic"
```

---

### Task 7: Wire rest threshold overrides from active tactic

**Files:**
- Modify: `SentinelCore/services/GrindService.lua`

**Context:** Each tactic defines a `rest_config` with drink/eat thresholds. The RestService needs to use these thresholds instead of hardcoded defaults. Currently RestService reads from the blackboard. We need GrindService to write the active tactic's rest_config to the blackboard.

**Step 1: Write rest_config to blackboard in tactical_tick**

In `build_tactical_combat_node`, after tactic selection, add:
```lua
bb:set("tactical.rest_config", active:get_rest_config())
```

**Step 2: Read rest_config in RestService**

Read `SentinelCore/services/RestService.lua` to understand how rest thresholds are configured. Modify the threshold resolution to check `bb:get("tactical.rest_config")` first, falling back to the existing defaults.

**Step 3: Commit**

```bash
git add SentinelCore/services/GrindService.lua SentinelCore/services/RestService.lua
git commit -m "feat(rest): wire tactic rest_config overrides into RestService"
```

---

### Task 8: Enhance Frost.lua aoe() with Blizzard position_spell

**Files:**
- Modify: `SentinelCore/rotations/mage/Frost.lua`
- Modify: `SentinelCore/tests/test_rotation_mage_frost_regressions.lua`

**Context:** Frost.lua's `aoe()` method currently has Cone of Cold, Arcane Explosion, and Frostbolt fallback. For AoE kiting, Blizzard is the key spell — a channeled AoE cast at a world position. We use `ActionBuilder.position_spell()` which requires a `position` field in opts. The position will be resolved dynamically from pack centroid data in the context.

**Step 1: Add Blizzard to aoe()**

Add Blizzard between Cone of Cold and Arcane Explosion. It's a channeled spell, so use `channel_spell` with a position resolver:

Actually, Blizzard in TBC requires ground targeting — `position_spell` is the right action type. But we also need `channel_duration` since it channels for 8 seconds.

```lua
-- Blizzard (550) — channeled AoE at pack centroid, 3+ enemies, sufficient mana
position_spell(SPELLS.BLIZZARD, 550, {
    allow_movement = false,
    intent = { "burst", "sustain" },
    combat_modes = { "burst", "sustain" },
    min_player_mana_pct = 0.25,
    condition = function(local_ctx)
        local enemies = tonumber(local_ctx.nearby_enemy_count or local_ctx.aoe_target_count or local_ctx.enemy_count) or 0
        if enemies < 3 then return false end
        -- Resolve AoE position from pack centroid
        local cx = tonumber(local_ctx.pack_centroid_x)
        local cy = tonumber(local_ctx.pack_centroid_y)
        local cz = tonumber(local_ctx.pack_centroid_z)
        if not cx or not cy or not cz then return false end
        if cx == 0 and cy == 0 and cz == 0 then return false end
        return true
    end,
    resolve_position = function(local_ctx)
        return {
            x = tonumber(local_ctx.pack_centroid_x) or 0,
            y = tonumber(local_ctx.pack_centroid_y) or 0,
            z = tonumber(local_ctx.pack_centroid_z) or 0,
        }
    end,
}),
```

Note: `resolve_position` is a new convention. The action executor in RotationEngine/PlanComposer must call it before spell queue submission. If the executor doesn't support this yet, add the resolver call in the position_spell execution path.

**Step 2: Add BLIZZARD_RANGE constant**

```lua
local BLIZZARD_RANGE = 30.0
```

**Step 3: Update test**

Add test for Blizzard action in the aoe test section: verify position_spell type, priority 550, min_mana_pct condition, and position resolution.

**Step 4: Commit**

```bash
git add SentinelCore/rotations/mage/Frost.lua SentinelCore/tests/test_rotation_mage_frost_regressions.lua
git commit -m "feat(rotations): add Blizzard position_spell to Frost AoE rotation"
```

---

### Task 9: Wire tactical configs in GrindService build_tactical_combat_node

**Files:**
- Modify: `SentinelCore/services/GrindService.lua`

**Context:** Tasks 5-7 each added individual blackboard writes for tactical configs. This task consolidates them into a clean block in `build_tactical_combat_node`. If they were already added incrementally, this task verifies they're all present and in the right order.

**Step 1: Verify all tactical config writes exist**

In `build_tactical_combat_node`, after `selector:select(ctx)`, verify these blackboard writes:
```lua
local active = selector:select(ctx)
if not active then return BT.Status.FAILURE end

-- Publish tactic configs so downstream services can read them
bb:set("tactical.target_config", active:get_target_config())
bb:set("tactical.explore_config", active:get_explore_config())
bb:set("tactical.rest_config", active:get_rest_config())
```

**Step 2: Commit** (if any changes needed)

```bash
git add SentinelCore/services/GrindService.lua
git commit -m "feat(grind): consolidate tactical config blackboard writes"
```

---

### Task 10: Integration smoke test

**Files:**
- Create: `SentinelCore/tests/test_ai030_aoe_tactical_smoke.lua`

**Context:** End-to-end smoke test that verifies:
1. TacticalSelector picks AoEKiteTactic when pack_count >= 3 and mana > 25%
2. TacticalSelector falls back to SingleTargetTactic when pack < 3 or low mana
3. AoEKiteTactic phases work (engage → combat transitions)
4. PositioningService integrates (kite_position returns valid positions)
5. CombatContext includes pack fields

**Step 1: Create smoke test**

Use mock blackboard, mock game objects, mock PackTracker data. Wire up TacticalSelector with both tactics. Verify tactic selection switches based on pack_count changes.

**Step 2: Register in run_all.lua**

Add `"tests/test_ai030_aoe_tactical_smoke"` to the tests array.

**Step 3: Commit**

```bash
git add SentinelCore/tests/test_ai030_aoe_tactical_smoke.lua SentinelCore/tests/run_all.lua
git commit -m "test(tactical): add AoE tactical system smoke test"
```

---

### Task 11: Static verification

**Verification checklist:**
1. All new files exist and have proper module returns
2. All new tests registered in run_all.lua
3. No duplicate test entries
4. All requires use forward slashes
5. AoEKiteTactic registered in Client.lua
6. CombatContext pack fields present
7. TargetingService has cluster bias code
8. ExplorationService has cluster_seek mode
9. RestService reads tactical rest_config
10. Frost.lua aoe() includes Blizzard
11. GrindService writes all 3 tactical configs to blackboard
