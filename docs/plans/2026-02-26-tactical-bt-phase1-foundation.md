# Tactical BT Phase 1: Foundation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add the Tactical BT foundation layer (TacticalSelector, TacticalPlanner, PackTracker, Tactic interface) and extract current grind behavior into SingleTargetTactic with zero regression.

**Architecture:** The Tactic interface declares preconditions + utility + phases. TacticalSelector scores all available tactics each tick and activates the best one. TacticalPlanner manages phases within the active tactic. SingleTargetTactic wraps the current CombatService + PullService + ExplorationService behavior verbatim so existing Ret Paladin and Affliction Warlock grinding works identically through the new system.

**Tech Stack:** Lua 5.1 (Sylvannas runtime), BT library at `ai/BehaviorTree.lua`, tests via `tests/run_all.lua` test runner.

**Prerequisites:** The 9 bugs documented in `docs/plans/2026-02-21-sentinelcore-bug-audit.md` must be fixed first (Tasks 1-10 of that plan). Execute that plan before this one.

**Design doc:** `docs/plans/2026-02-26-tactical-bt-grind-overhaul-design.md`

---

## Task 1: Tactic Interface Base Class

**Files:**
- Create: `SentinelCore/ai/Tactic.lua`
- Create: `SentinelCore/tests/test_ai020_tactic.lua`
- Modify: `SentinelCore/tests/run_all.lua`

**Step 1: Write the test**

```lua
-- SentinelCore/tests/test_ai020_tactic.lua
local T = require("tests/TestUtil")

return { run = function()
    local Tactic = require("ai/Tactic")

    -- 1. Can create a minimal tactic
    local t = Tactic:new({
        name = "test_tactic",
        preconditions = function() return true end,
        utility = function() return 0.5 end,
        phases = {
            {
                name = "engage",
                enter_if = function() return true end,
                tick = function() return "SUCCESS" end,
                exit_if = function() return false end,
            },
        },
    })
    T.assert_true(t ~= nil, "tactic created")
    T.assert_eq(t:get_name(), "test_tactic", "name accessor")

    -- 2. preconditions delegation
    T.assert_true(t:check_preconditions({}), "preconditions pass")

    -- 3. utility delegation
    T.assert_eq(t:score_utility({}, nil), 0.5, "utility returns 0.5")

    -- 4. phases accessible
    local phases = t:get_phases()
    T.assert_eq(#phases, 1, "one phase")
    T.assert_eq(phases[1].name, "engage", "phase name")

    -- 5. config overrides default to nil (shared services use defaults)
    T.assert_eq(t:get_rest_config(), nil, "no rest config override")
    T.assert_eq(t:get_target_config(), nil, "no target config override")
    T.assert_eq(t:get_explore_config(), nil, "no explore config override")

    -- 6. Tactic with config overrides
    local t2 = Tactic:new({
        name = "custom",
        preconditions = function() return false end,
        utility = function() return 0.0 end,
        phases = {},
        rest_config = { drink_below = 0.95 },
        target_config = { prefer_clusters = true },
        explore_config = { mode = "cluster_seek" },
    })
    T.assert_eq(t2:get_rest_config().drink_below, 0.95, "rest config override")
    T.assert_eq(t2:get_target_config().prefer_clusters, true, "target config override")
    T.assert_eq(t2:get_explore_config().mode, "cluster_seek", "explore config override")

    -- 7. reset clears state
    t:reset()  -- should not error

    return { pass = true }
end }
```

**Step 2: Register test in run_all.lua**

Add to the tests list in `SentinelCore/tests/run_all.lua`:
```lua
    "tests/test_ai020_tactic",
```

**Step 3: Implement Tactic**

```lua
-- SentinelCore/ai/Tactic.lua
---@class Tactic
---@field _name string
---@field _preconditions function
---@field _utility function
---@field _phases table[]
---@field _rest_config table|nil
---@field _target_config table|nil
---@field _explore_config table|nil
local Tactic = {}
Tactic.__index = Tactic

---@param def table Tactic definition
---@return Tactic
function Tactic:new(def)
    local o = setmetatable({}, self)
    o._name = def.name or "unnamed"
    o._preconditions = def.preconditions or function() return true end
    o._utility = def.utility or function() return 0 end
    o._phases = def.phases or {}
    o._rest_config = def.rest_config or nil
    o._target_config = def.target_config or nil
    o._explore_config = def.explore_config or nil
    o._on_reset = def.on_reset or nil
    return o
end

function Tactic:get_name()
    return self._name
end

---@param ctx table Combat/world context
---@return boolean
function Tactic:check_preconditions(ctx)
    local ok, result = pcall(self._preconditions, ctx)
    return ok and result == true
end

---@param ctx table Combat/world context
---@param advisor table|nil PerformanceAdvisor
---@return number 0..1
function Tactic:score_utility(ctx, advisor)
    local ok, score = pcall(self._utility, ctx, advisor)
    if not ok or type(score) ~= "number" then return 0 end
    return math.max(0, math.min(1, score))
end

---@return table[]
function Tactic:get_phases()
    return self._phases
end

function Tactic:get_rest_config()
    return self._rest_config
end

function Tactic:get_target_config()
    return self._target_config
end

function Tactic:get_explore_config()
    return self._explore_config
end

function Tactic:reset()
    if self._on_reset then
        pcall(self._on_reset, self)
    end
end

return Tactic
```

**Step 4: Verify test passes**

Run SentinelCore tests via in-game UI button. Expected: `test_ai020_tactic` PASS.

**Step 5: Commit**

```bash
git add SentinelCore/ai/Tactic.lua SentinelCore/tests/test_ai020_tactic.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add Tactic interface base class with tests"
```

---

## Task 2: TacticalPlanner — Phase State Machine

**Files:**
- Create: `SentinelCore/ai/TacticalPlanner.lua`
- Create: `SentinelCore/tests/test_ai021_tactical_planner.lua`
- Modify: `SentinelCore/tests/run_all.lua`

**Step 1: Write the test**

```lua
-- SentinelCore/tests/test_ai021_tactical_planner.lua
local T = require("tests/TestUtil")

return { run = function()
    local TacticalPlanner = require("ai/TacticalPlanner")
    local Tactic = require("ai/Tactic")
    local BT = require("ai/BehaviorTree")

    -- Mock deps
    local deps = {}
    local phase_ticks = {}

    -- Tactic with 3 phases: gather → burst → cleanup
    local tactic = Tactic:new({
        name = "test",
        preconditions = function() return true end,
        utility = function() return 1.0 end,
        phases = {
            {
                name = "gather",
                enter_if = function(ctx) return ctx.pack_count < 3 end,
                tick = function(ctx, d)
                    phase_ticks.gather = (phase_ticks.gather or 0) + 1
                    return BT.Status.RUNNING
                end,
                exit_if = function(ctx) return ctx.pack_count >= 3 end,
            },
            {
                name = "burst",
                enter_if = function(ctx) return ctx.pack_count >= 3 and ctx.in_combat end,
                tick = function(ctx, d)
                    phase_ticks.burst = (phase_ticks.burst or 0) + 1
                    return BT.Status.RUNNING
                end,
                exit_if = function(ctx) return ctx.pack_count == 0 end,
            },
            {
                name = "cleanup",
                enter_if = function(ctx) return ctx.pack_count > 0 and ctx.pack_count < 3 end,
                tick = function(ctx, d)
                    phase_ticks.cleanup = (phase_ticks.cleanup or 0) + 1
                    return BT.Status.SUCCESS
                end,
                exit_if = function(ctx) return ctx.pack_count == 0 end,
            },
        },
    })

    local planner = TacticalPlanner:new()

    -- 1. Set tactic
    planner:set_tactic(tactic)
    T.assert_eq(planner:get_current_phase_name(), nil, "no phase before first tick")

    -- 2. Tick with pack_count=0 → should enter "gather"
    local ctx1 = { pack_count = 0, in_combat = false }
    local status1 = planner:tick(ctx1, deps)
    T.assert_eq(planner:get_current_phase_name(), "gather", "entered gather phase")
    T.assert_eq(status1, BT.Status.RUNNING, "gather returns RUNNING")
    T.assert_eq(phase_ticks.gather, 1, "gather ticked once")

    -- 3. Tick again with pack_count=3 → exit gather, enter burst
    local ctx2 = { pack_count = 3, in_combat = true }
    local status2 = planner:tick(ctx2, deps)
    T.assert_eq(planner:get_current_phase_name(), "burst", "transitioned to burst")
    T.assert_eq(phase_ticks.burst, 1, "burst ticked once")

    -- 4. Tick with pack_count=1 → exit burst (count dropped), enter cleanup
    local ctx3 = { pack_count = 1, in_combat = true }
    local status3 = planner:tick(ctx3, deps)
    T.assert_eq(planner:get_current_phase_name(), "cleanup", "transitioned to cleanup")
    T.assert_eq(status3, BT.Status.SUCCESS, "cleanup returns SUCCESS")

    -- 5. Reset clears phase
    planner:reset()
    T.assert_eq(planner:get_current_phase_name(), nil, "phase cleared after reset")

    -- 6. No eligible phase → returns FAILURE
    planner:set_tactic(tactic)
    local ctx4 = { pack_count = 0, in_combat = true }  -- gather wants pack<3 (ok), but burst wants pack>=3 (no)
    -- gather's enter_if checks pack_count < 3 → true, so gather should activate
    local status4 = planner:tick(ctx4, deps)
    T.assert_eq(planner:get_current_phase_name(), "gather", "gather re-entered")

    -- 7. Tactic with no phases → FAILURE
    local empty_tactic = Tactic:new({ name = "empty", phases = {} })
    planner:set_tactic(empty_tactic)
    local status5 = planner:tick({}, deps)
    T.assert_eq(status5, BT.Status.FAILURE, "no phases returns FAILURE")

    return { pass = true }
end }
```

**Step 2: Register test**

Add to `SentinelCore/tests/run_all.lua`:
```lua
    "tests/test_ai021_tactical_planner",
```

**Step 3: Implement TacticalPlanner**

```lua
-- SentinelCore/ai/TacticalPlanner.lua
local BT = require("ai/BehaviorTree")

---@class TacticalPlanner
---@field _tactic Tactic|nil
---@field _current_phase table|nil
---@field _current_phase_index number|nil
local TacticalPlanner = {}
TacticalPlanner.__index = TacticalPlanner

function TacticalPlanner:new()
    return setmetatable({
        _tactic = nil,
        _current_phase = nil,
        _current_phase_index = nil,
    }, self)
end

---@param tactic Tactic
function TacticalPlanner:set_tactic(tactic)
    if self._tactic ~= tactic then
        self:reset()
        self._tactic = tactic
    end
end

---@return string|nil
function TacticalPlanner:get_current_phase_name()
    return self._current_phase and self._current_phase.name or nil
end

---@param ctx table
---@param deps table
---@return number BT.Status
function TacticalPlanner:tick(ctx, deps)
    if not self._tactic then return BT.Status.FAILURE end

    local phases = self._tactic:get_phases()
    if #phases == 0 then return BT.Status.FAILURE end

    -- Check exit condition on current phase
    if self._current_phase then
        local ok_exit, should_exit = pcall(self._current_phase.exit_if, ctx)
        if ok_exit and should_exit then
            self._current_phase = nil
            self._current_phase_index = nil
        end
    end

    -- If no current phase (or just exited), find best eligible phase
    if not self._current_phase then
        for i = 1, #phases do
            local phase = phases[i]
            local ok_enter, can_enter = pcall(phase.enter_if, ctx)
            if ok_enter and can_enter then
                self._current_phase = phase
                self._current_phase_index = i
                break
            end
        end
    end

    -- No eligible phase found
    if not self._current_phase then
        return BT.Status.FAILURE
    end

    -- Tick current phase
    local ok_tick, status = pcall(self._current_phase.tick, ctx, deps)
    if not ok_tick then
        return BT.Status.FAILURE
    end

    return status or BT.Status.FAILURE
end

function TacticalPlanner:reset()
    self._current_phase = nil
    self._current_phase_index = nil
end

return TacticalPlanner
```

**Step 4: Verify test passes**

Run tests. Expected: `test_ai021_tactical_planner` PASS.

**Step 5: Commit**

```bash
git add SentinelCore/ai/TacticalPlanner.lua SentinelCore/tests/test_ai021_tactical_planner.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add TacticalPlanner phase state machine with tests"
```

---

## Task 3: PackTracker — Enemy Spatial Clustering

**Files:**
- Create: `SentinelCore/ai/PackTracker.lua`
- Create: `SentinelCore/tests/test_ai022_pack_tracker.lua`
- Modify: `SentinelCore/tests/run_all.lua`

**Step 1: Write the test**

```lua
-- SentinelCore/tests/test_ai022_pack_tracker.lua
local T = require("tests/TestUtil")

return { run = function()
    local PackTracker = require("ai/PackTracker")

    -- Mock game objects
    local function make_mob(x, y, z, in_combat, target_guid)
        return {
            get_position = function() return { x = x, y = y, z = z } end,
            is_valid = function() return true end,
            is_dead = function() return false end,
            is_in_combat = function() return in_combat or false end,
            get_target = function()
                if target_guid then
                    return { get_guid = function() return target_guid end }
                end
                return nil
            end,
            get_guid = function() return string.format("mob_%d_%d", x, z) end,
        }
    end

    local player_guid = "player_1"
    local player_pos = { x = 0, y = 0, z = 0 }

    -- 1. Empty update
    local pt = PackTracker:new()
    pt:update({}, player_pos, player_guid)
    local pack = pt:get_pack()
    T.assert_eq(pack.count, 0, "empty pack count")

    -- 2. Single mob
    local mob1 = make_mob(5, 0, 5)
    pt:update({ mob1 }, player_pos, player_guid)
    pack = pt:get_pack()
    T.assert_eq(pack.count, 1, "one mob in pack")

    -- 3. Cluster of 4 mobs within 15yd
    local mobs = {
        make_mob(10, 0, 10),
        make_mob(12, 0, 11),
        make_mob(11, 0, 13),
        make_mob(13, 0, 12),
    }
    pt:update(mobs, player_pos, player_guid)
    pack = pt:get_pack()
    T.assert_eq(pack.count, 4, "four mobs")
    T.assert_true(pack.centroid ~= nil, "centroid computed")
    T.assert_true(pack.spread < 10, "spread is small for tight cluster")

    -- 4. Gathered count: mobs targeting player
    local gathered_mobs = {
        make_mob(5, 0, 5, true, player_guid),   -- in combat, targeting player
        make_mob(6, 0, 6, true, player_guid),   -- in combat, targeting player
        make_mob(20, 0, 20, false, nil),          -- not in combat
    }
    pt:update(gathered_mobs, player_pos, player_guid)
    pack = pt:get_pack()
    T.assert_eq(pack.count, 3, "three total mobs")
    T.assert_eq(pack.gathered_count, 2, "two gathered (targeting player)")

    -- 5. Cluster detection
    local spread_mobs = {
        -- Cluster A: around (10, 0, 10)
        make_mob(10, 0, 10),
        make_mob(11, 0, 11),
        make_mob(12, 0, 10),
        -- Cluster B: around (50, 0, 50), far from A
        make_mob(50, 0, 50),
        make_mob(51, 0, 51),
    }
    local clusters = pt:find_clusters(spread_mobs, 15)
    T.assert_eq(#clusters, 2, "two clusters detected")
    -- Clusters sorted by count desc
    T.assert_eq(clusters[1].count, 3, "first cluster has 3")
    T.assert_eq(clusters[2].count, 2, "second cluster has 2")

    -- 6. Nearest distance
    local near_mobs = {
        make_mob(3, 0, 0),   -- 3yd away
        make_mob(10, 0, 0),  -- 10yd away
    }
    pt:update(near_mobs, player_pos, player_guid)
    pack = pt:get_pack()
    T.assert_true(pack.nearest_dist <= 3.1 and pack.nearest_dist >= 2.9, "nearest ~3yd")

    return { pass = true }
end }
```

**Step 2: Register test**

Add to `SentinelCore/tests/run_all.lua`:
```lua
    "tests/test_ai022_pack_tracker",
```

**Step 3: Implement PackTracker**

```lua
-- SentinelCore/ai/PackTracker.lua
local Helpers = require("lib/Helpers")

---@class PackTracker
---@field _pack table
local PackTracker = {}
PackTracker.__index = PackTracker

function PackTracker:new()
    return setmetatable({
        _pack = {
            targets = {},
            count = 0,
            centroid = { x = 0, y = 0, z = 0 },
            spread = 0,
            nearest_dist = math.huge,
            gathered_count = 0,
        },
    }, self)
end

---@return table
function PackTracker:get_pack()
    return self._pack
end

---Update pack state from visible hostile objects.
---@param hostiles table[] Array of game_object references
---@param player_pos table {x,y,z}
---@param player_guid string Player GUID for gathered detection
function PackTracker:update(hostiles, player_pos, player_guid)
    local targets = {}
    local sum_x, sum_y, sum_z = 0, 0, 0
    local nearest_dist = math.huge
    local gathered = 0

    for i = 1, #hostiles do
        local mob = hostiles[i]
        local ok, pos = pcall(function() return mob:get_position() end)
        if ok and pos then
            targets[#targets + 1] = mob
            sum_x = sum_x + (pos.x or 0)
            sum_y = sum_y + (pos.y or 0)
            sum_z = sum_z + (pos.z or 0)

            local dist = Helpers.distance_3d(player_pos, pos)
            if dist < nearest_dist then
                nearest_dist = dist
            end

            -- Check if mob is aggroed to player
            local ok_c, in_combat = pcall(function() return mob:is_in_combat() end)
            if ok_c and in_combat then
                local ok_t, mob_target = pcall(function() return mob:get_target() end)
                if ok_t and mob_target then
                    local ok_g, tguid = pcall(function() return mob_target:get_guid() end)
                    if ok_g and tguid == player_guid then
                        gathered = gathered + 1
                    end
                end
            end
        end
    end

    local count = #targets
    local centroid = { x = 0, y = 0, z = 0 }
    local spread = 0

    if count > 0 then
        centroid.x = sum_x / count
        centroid.y = sum_y / count
        centroid.z = sum_z / count

        -- Spread = max distance from centroid
        for i = 1, count do
            local ok, pos = pcall(function() return targets[i]:get_position() end)
            if ok and pos then
                local d = Helpers.distance_3d(centroid, pos)
                if d > spread then spread = d end
            end
        end
    end

    self._pack = {
        targets = targets,
        count = count,
        centroid = centroid,
        spread = spread,
        nearest_dist = count > 0 and nearest_dist or math.huge,
        gathered_count = gathered,
    }
end

---Find spatial clusters of hostiles using distance-based grouping.
---@param hostiles table[] Array of game_object references
---@param radius number Cluster radius in yards
---@return table[] Array of {centroid, count, targets} sorted by count desc
function PackTracker:find_clusters(hostiles, radius)
    local clusters = {}

    for i = 1, #hostiles do
        local mob = hostiles[i]
        local ok, pos = pcall(function() return mob:get_position() end)
        if ok and pos then
            local assigned = false
            for c = 1, #clusters do
                local cluster = clusters[c]
                if Helpers.distance_3d(cluster.centroid, pos) <= radius then
                    -- Add to existing cluster and recompute centroid
                    cluster.count = cluster.count + 1
                    cluster.targets[#cluster.targets + 1] = mob
                    cluster.centroid.x = (cluster.centroid.x * (cluster.count - 1) + pos.x) / cluster.count
                    cluster.centroid.y = (cluster.centroid.y * (cluster.count - 1) + pos.y) / cluster.count
                    cluster.centroid.z = (cluster.centroid.z * (cluster.count - 1) + pos.z) / cluster.count
                    assigned = true
                    break
                end
            end
            if not assigned then
                clusters[#clusters + 1] = {
                    centroid = { x = pos.x, y = pos.y, z = pos.z },
                    count = 1,
                    targets = { mob },
                }
            end
        end
    end

    -- Sort by count descending
    table.sort(clusters, function(a, b) return a.count > b.count end)
    return clusters
end

return PackTracker
```

**Step 4: Verify test passes**

Run tests. Expected: `test_ai022_pack_tracker` PASS.

**Step 5: Commit**

```bash
git add SentinelCore/ai/PackTracker.lua SentinelCore/tests/test_ai022_pack_tracker.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add PackTracker for enemy spatial clustering with tests"
```

---

## Task 4: TacticalSelector — Utility-Scored Tactic Selection

**Files:**
- Create: `SentinelCore/ai/TacticalSelector.lua`
- Create: `SentinelCore/tests/test_ai023_tactical_selector.lua`
- Modify: `SentinelCore/tests/run_all.lua`

**Step 1: Write the test**

```lua
-- SentinelCore/tests/test_ai023_tactical_selector.lua
local T = require("tests/TestUtil")

return { run = function()
    local TacticalSelector = require("ai/TacticalSelector")
    local Tactic = require("ai/Tactic")
    local BT = require("ai/BehaviorTree")

    -- Mock advisor (no bias)
    local advisor = {
        get_bias = function(self, name) return 1.0 end,
    }

    -- Two tactics: low utility and high utility
    local low_tactic = Tactic:new({
        name = "low",
        preconditions = function() return true end,
        utility = function() return 0.3 end,
        phases = {
            { name = "idle", enter_if = function() return true end,
              tick = function() return BT.Status.RUNNING end,
              exit_if = function() return false end },
        },
    })

    local high_tactic = Tactic:new({
        name = "high",
        preconditions = function() return true end,
        utility = function() return 0.8 end,
        phases = {
            { name = "burst", enter_if = function() return true end,
              tick = function() return BT.Status.RUNNING end,
              exit_if = function() return false end },
        },
    })

    local blocked_tactic = Tactic:new({
        name = "blocked",
        preconditions = function() return false end,  -- fails preconditions
        utility = function() return 1.0 end,
        phases = {},
    })

    -- 1. Construction
    local selector = TacticalSelector:new(advisor)
    T.assert_true(selector ~= nil, "selector created")

    -- 2. Register tactics
    selector:register(low_tactic)
    selector:register(high_tactic)
    selector:register(blocked_tactic)

    -- 3. Filter by preconditions
    local ctx = {}
    selector:refresh_available(ctx)
    T.assert_eq(selector:get_available_count(), 2, "blocked tactic filtered out")

    -- 4. Select highest utility
    local selected = selector:select(ctx)
    T.assert_eq(selected:get_name(), "high", "high utility tactic selected")

    -- 5. Active tactic persists
    T.assert_eq(selector:get_active():get_name(), "high", "active tactic is high")

    -- 6. Hysteresis: active tactic gets +0.1 bonus
    -- Make low score 0.75, high scores 0.8. With hysteresis, high (active) scores 0.9.
    -- So high stays active even though raw difference is only 0.05.
    local close_low = Tactic:new({
        name = "close_low",
        preconditions = function() return true end,
        utility = function() return 0.75 end,
        phases = low_tactic:get_phases(),
    })
    local selector2 = TacticalSelector:new(advisor)
    selector2:register(close_low)
    selector2:register(high_tactic)
    selector2:refresh_available(ctx)
    selector2:select(ctx)  -- activates "high" (0.8 > 0.75)
    T.assert_eq(selector2:get_active():get_name(), "high", "high selected first")

    -- Now high scores 0.8 + 0.1 hysteresis = 0.9 vs close_low 0.75 → high stays
    local selected2 = selector2:select(ctx)
    T.assert_eq(selected2:get_name(), "high", "hysteresis keeps high active")

    -- 7. Tactic switch when new tactic scores much higher
    local dominant = Tactic:new({
        name = "dominant",
        preconditions = function() return true end,
        utility = function() return 0.99 end,
        phases = low_tactic:get_phases(),
    })
    selector2:register(dominant)
    selector2:refresh_available(ctx)
    local selected3 = selector2:select(ctx)
    T.assert_eq(selected3:get_name(), "dominant", "dominant tactic takes over")

    -- 8. No available tactics → nil
    local empty_selector = TacticalSelector:new(advisor)
    local none = empty_selector:select(ctx)
    T.assert_eq(none, nil, "nil when no tactics available")

    return { pass = true }
end }
```

**Step 2: Register test**

Add to `SentinelCore/tests/run_all.lua`:
```lua
    "tests/test_ai023_tactical_selector",
```

**Step 3: Implement TacticalSelector**

```lua
-- SentinelCore/ai/TacticalSelector.lua
---@class TacticalSelector
---@field _all_tactics Tactic[]
---@field _available Tactic[]
---@field _active Tactic|nil
---@field _advisor table|nil
local TacticalSelector = {}
TacticalSelector.__index = TacticalSelector

local HYSTERESIS_BONUS = 0.1

---@param advisor table|nil PerformanceAdvisor (or nil for no bias)
function TacticalSelector:new(advisor)
    return setmetatable({
        _all_tactics = {},
        _available = {},
        _active = nil,
        _advisor = advisor,
    }, self)
end

---@param tactic Tactic
function TacticalSelector:register(tactic)
    self._all_tactics[#self._all_tactics + 1] = tactic
end

---Filter tactics by preconditions. Call on startup and on level-up.
---@param ctx table
function TacticalSelector:refresh_available(ctx)
    self._available = {}
    for i = 1, #self._all_tactics do
        local t = self._all_tactics[i]
        if t:check_preconditions(ctx) then
            self._available[#self._available + 1] = t
        end
    end
end

---@return number
function TacticalSelector:get_available_count()
    return #self._available
end

---@return Tactic|nil
function TacticalSelector:get_active()
    return self._active
end

---Score all available tactics and activate the best one.
---Active tactic gets a hysteresis bonus to prevent thrashing.
---@param ctx table
---@return Tactic|nil
function TacticalSelector:select(ctx)
    if #self._available == 0 then return nil end

    local best_tactic = nil
    local best_score = -1

    for i = 1, #self._available do
        local t = self._available[i]
        local raw = t:score_utility(ctx, self._advisor)

        -- Apply advisor bias
        if self._advisor and type(self._advisor.get_bias) == "function" then
            local ok, bias = pcall(self._advisor.get_bias, self._advisor, t:get_name())
            if ok and type(bias) == "number" then
                raw = raw * bias
            end
        end

        -- Hysteresis: active tactic gets bonus
        if self._active and t == self._active then
            raw = raw + HYSTERESIS_BONUS
        end

        if raw > best_score then
            best_score = raw
            best_tactic = t
        end
    end

    -- Switch tactic if changed
    if best_tactic and best_tactic ~= self._active then
        if self._active then
            self._active:reset()
        end
        self._active = best_tactic
    end

    return self._active
end

return TacticalSelector
```

**Step 4: Verify test passes**

Run tests. Expected: `test_ai023_tactical_selector` PASS.

**Step 5: Commit**

```bash
git add SentinelCore/ai/TacticalSelector.lua SentinelCore/tests/test_ai023_tactical_selector.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add TacticalSelector with utility scoring and hysteresis"
```

---

## Task 5: SingleTargetTactic — Extract Current Behavior

**Files:**
- Create: `SentinelCore/tactics/SingleTargetTactic.lua`
- Create: `SentinelCore/tests/test_ai024_single_target_tactic.lua`
- Modify: `SentinelCore/tests/run_all.lua`

This tactic wraps the existing CombatService.build_bt(), PullService.build(), and ExplorationService.build() methods. It delegates directly to them — no behavior change.

**Step 1: Write the test**

```lua
-- SentinelCore/tests/test_ai024_single_target_tactic.lua
local T = require("tests/TestUtil")

return { run = function()
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local BT = require("ai/BehaviorTree")

    -- 1. Preconditions always pass (fallback tactic)
    local tactic = SingleTargetTactic:new()
    T.assert_true(tactic:check_preconditions({}), "always available")
    T.assert_eq(tactic:get_name(), "single_target", "correct name")

    -- 2. Utility baseline
    local ctx_idle = { enemy_count = 0, player_mana_pct = 0.8 }
    local score = tactic:score_utility(ctx_idle, nil)
    T.assert_true(score >= 0.4 and score <= 1.0, "utility in valid range: " .. tostring(score))

    -- 3. Utility increases when low mana (safer to single-target)
    local ctx_low_mana = { enemy_count = 1, player_mana_pct = 0.10 }
    local score_low = tactic:score_utility(ctx_low_mana, nil)
    T.assert_true(score_low >= 0.5, "higher utility when low mana")

    -- 4. Default rest config (standard thresholds)
    local rest = tactic:get_rest_config()
    T.assert_eq(rest.drink_below, 0.30, "default drink threshold")
    T.assert_eq(rest.eat_below, 0.50, "default eat threshold")

    -- 5. Target config: no cluster preference
    local target_cfg = tactic:get_target_config()
    T.assert_eq(target_cfg.prefer_clusters, false, "no cluster preference")

    -- 6. Explore config: frontier mode
    local explore_cfg = tactic:get_explore_config()
    T.assert_eq(explore_cfg.mode, "frontier", "frontier exploration")

    -- 7. Has two phases: engage and combat
    local phases = tactic:get_phases()
    T.assert_eq(#phases, 2, "two phases")
    T.assert_eq(phases[1].name, "engage", "first phase is engage")
    T.assert_eq(phases[2].name, "combat", "second phase is combat")

    -- 8. Reset does not error
    tactic:reset()

    return { pass = true }
end }
```

**Step 2: Register test**

Add to `SentinelCore/tests/run_all.lua`:
```lua
    "tests/test_ai024_single_target_tactic",
```

**Step 3: Implement SingleTargetTactic**

This tactic delegates to existing services. The phases are thin wrappers — the real logic stays in CombatService/PullService/ExplorationService. The tactic just declares when to use them.

```lua
-- SentinelCore/tactics/SingleTargetTactic.lua
local Tactic = require("ai/Tactic")
local BT = require("ai/BehaviorTree")

local SingleTargetTactic = {}
SingleTargetTactic.__index = SingleTargetTactic
setmetatable(SingleTargetTactic, { __index = Tactic })

function SingleTargetTactic:new()
    local o = Tactic.new(self, {
        name = "single_target",

        preconditions = function(ctx)
            return true  -- always available as fallback
        end,

        utility = function(ctx, advisor)
            local base = 0.5
            local enemy_count = tonumber(ctx.enemy_count) or 0
            local mana_pct = tonumber(ctx.player_mana_pct) or 1.0

            -- Higher utility when only 1 mob or low mana (safe choice)
            if enemy_count <= 1 then base = 0.7 end
            if mana_pct < 0.20 then base = math.max(base, 0.8) end

            -- Lower utility when cluster detected and we could AoE
            local pack_count = tonumber(ctx.pack_count) or 0
            if pack_count >= 3 and mana_pct > 0.40 then
                base = base * 0.6
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
                    -- Delegates to PullService BT node via deps.pull_node
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
                name = "combat",
                enter_if = function(ctx)
                    return ctx.in_combat
                end,
                tick = function(ctx, deps)
                    -- Delegates to CombatService BT node via deps.combat_node
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
            drink_below = 0.30,
            eat_below = 0.50,
            drink_until = 0.80,
            eat_until = 0.90,
        },
        target_config = {
            prefer_clusters = false,
        },
        explore_config = {
            mode = "frontier",
        },
    })
    return o
end

return SingleTargetTactic
```

**Step 4: Verify test passes**

Run tests. Expected: `test_ai024_single_target_tactic` PASS.

**Step 5: Commit**

```bash
git add SentinelCore/tactics/SingleTargetTactic.lua SentinelCore/tests/test_ai024_single_target_tactic.lua SentinelCore/tests/run_all.lua
git commit -m "feat(tactics): add SingleTargetTactic wrapping current combat behavior"
```

---

## Task 6: Wire TacticalSelector Into GrindService

**Files:**
- Modify: `SentinelCore/services/GrindService.lua`
- Create: `SentinelCore/tests/test_ai025_grind_tactical_integration.lua`
- Modify: `SentinelCore/tests/run_all.lua`

This is the integration point. GrindService.build() gains a `tactical_selector` dep. When present, it uses the TacticalSelector to build combat/pull nodes. When absent (backward compat), it falls back to the existing direct service calls.

**Step 1: Write the integration test**

```lua
-- SentinelCore/tests/test_ai025_grind_tactical_integration.lua
local T = require("tests/TestUtil")

return { run = function()
    local TacticalSelector = require("ai/TacticalSelector")
    local TacticalPlanner = require("ai/TacticalPlanner")
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local Tactic = require("ai/Tactic")
    local BT = require("ai/BehaviorTree")

    -- 1. TacticalSelector + SingleTargetTactic integration
    local selector = TacticalSelector:new(nil)
    local st = SingleTargetTactic:new()
    selector:register(st)
    selector:refresh_available({})
    T.assert_eq(selector:get_available_count(), 1, "single target available")

    local active = selector:select({ enemy_count = 1, player_mana_pct = 0.8 })
    T.assert_eq(active:get_name(), "single_target", "single target selected")

    -- 2. TacticalPlanner ticks SingleTargetTactic phases
    local planner = TacticalPlanner:new()
    planner:set_tactic(st)

    -- Engage phase: has_target=true, not in combat
    local ctx_pull = { has_target = true, in_combat = false }
    local status = planner:tick(ctx_pull, {})
    T.assert_eq(planner:get_current_phase_name(), "engage", "engage phase active")
    -- tick returns FAILURE because deps.pull_node is nil (expected in test)
    T.assert_eq(status, BT.Status.FAILURE, "no pull_node → FAILURE")

    -- Combat phase: in_combat=true
    local ctx_combat = { has_target = true, in_combat = true, target_alive = true }
    planner:reset()
    planner:set_tactic(st)
    local status2 = planner:tick(ctx_combat, {})
    T.assert_eq(planner:get_current_phase_name(), "combat", "combat phase active")

    -- 3. Two tactics: SingleTarget + a mock AoE, selector picks correct one
    local aoe_mock = Tactic:new({
        name = "aoe_mock",
        preconditions = function() return true end,
        utility = function(ctx)
            local pack = tonumber(ctx.pack_count) or 0
            if pack >= 3 then return 0.9 end
            return 0.1
        end,
        phases = {
            { name = "gather", enter_if = function() return true end,
              tick = function() return BT.Status.RUNNING end,
              exit_if = function() return false end },
        },
    })

    local selector2 = TacticalSelector:new(nil)
    selector2:register(st)
    selector2:register(aoe_mock)
    selector2:refresh_available({})

    -- Low pack count → single target wins
    local pick1 = selector2:select({ enemy_count = 1, player_mana_pct = 0.8, pack_count = 0 })
    T.assert_eq(pick1:get_name(), "single_target", "ST wins with no pack")

    -- High pack count → AoE wins
    local pick2 = selector2:select({ enemy_count = 5, player_mana_pct = 0.8, pack_count = 5 })
    T.assert_eq(pick2:get_name(), "aoe_mock", "AoE wins with pack of 5")

    return { pass = true }
end }
```

**Step 2: Register test**

Add to `SentinelCore/tests/run_all.lua`:
```lua
    "tests/test_ai025_grind_tactical_integration",
```

**Step 3: Modify GrindService.lua**

Add TacticalSelector support. The key change: when `deps.tactical_selector` is provided, slots 4 (combat) and 12 (pull) delegate through it. When absent, existing behavior is preserved.

In `SentinelCore/services/GrindService.lua`, add after the existing requires:

```lua
local TacticalPlanner = require("ai/TacticalPlanner")
```

Then modify the `build()` function to accept `deps.tactical_selector` and `deps.pack_tracker`. When `tactical_selector` is present, create a BT action node that:
1. Calls `tactical_selector:select(ctx)` to pick the best tactic
2. Calls `planner:set_tactic(active)` to activate it
3. Calls `planner:tick(ctx, deps)` to execute the current phase

The tactical combat node replaces slot 4 (combat) in the ReactiveSelector. Create it as:

```lua
local function build_tactical_combat_node(deps)
    local selector = deps.tactical_selector
    local planner = TacticalPlanner:new()
    local bb = deps.bb

    return BT.ReactiveSequence:new("tactical_combat", {
        -- Gate: must be in combat (same as CombatService gate)
        BT.Condition:new("in_combat_or_pulling", function()
            return bb:get("player.in_combat", false)
                or bb:get("combat.has_aggro", false)
                or (bb:get("combat.target") ~= nil and not bb:get("player.is_dead", false))
        end),

        -- Select best tactic and tick its planner
        BT.Action:new("tactical_tick", function()
            local ctx = {
                in_combat = bb:get("player.in_combat", false),
                has_target = bb:get("combat.target") ~= nil,
                target_alive = false,
                enemy_count = bb:get("combat.enemy_count", 0),
                player_mana_pct = 0,
                pack_count = bb:get("pack.count", 0),
            }

            -- Check target alive
            local target = bb:get("combat.target")
            if target then
                local ok, hp = pcall(function() return target:get_health() end)
                ctx.target_alive = ok and hp and hp > 0
            end

            -- Player mana
            local mana = bb:get("player.mana") or 0
            local max_mana = bb:get("player.max_mana") or 1
            ctx.player_mana_pct = max_mana > 0 and (mana / max_mana) or 0

            local active = selector:select(ctx)
            if not active then return BT.Status.FAILURE end

            planner:set_tactic(active)
            return planner:tick(ctx, deps)
        end),
    })
end
```

In the main `build()` function, replace the combat node slot:

```lua
-- Existing line (approximately):
-- CombatService.build_bt(bb, evaluator, swing_timer, human_timing, spell_executor, navigation),
-- Replace with:
deps.tactical_selector
    and build_tactical_combat_node(deps)
    or CombatService.build_bt(bb, evaluator, swing_timer, human_timing, spell_executor, navigation),
```

This preserves backward compatibility: if no `tactical_selector` in deps, uses the old CombatService directly.

**Important:** The SingleTargetTactic's phases delegate to `deps.combat_node` and `deps.pull_node`. These must be set in deps:

```lua
-- In GrindService.build(), when tactical_selector is present:
if deps.tactical_selector then
    deps.combat_node = CombatService.build_bt(bb, evaluator, swing_timer, human_timing, spell_executor, navigation)
    deps.pull_node = PullService.build(bb, navigation, deps.rotation_engine)
end
```

This way SingleTargetTactic's phase ticks delegate directly to the existing combat/pull BT nodes — zero behavior change.

**Step 4: Verify tests pass**

Run all SentinelCore tests. Expected:
- `test_ai025_grind_tactical_integration` PASS
- All existing tests still PASS (backward compat preserved)

**Step 5: Commit**

```bash
git add SentinelCore/services/GrindService.lua SentinelCore/tests/test_ai025_grind_tactical_integration.lua SentinelCore/tests/run_all.lua
git commit -m "feat(grind): wire TacticalSelector into GrindService with backward compat"
```

---

## Task 7: Wire PackTracker and TacticalSelector in Client.lua

**Files:**
- Modify: `SentinelCore/core/Client.lua`

**Step 1: Add requires at top of Client.lua**

```lua
local TacticalSelector = require("ai/TacticalSelector")
local PackTracker = require("ai/PackTracker")
local SingleTargetTactic = require("tactics/SingleTargetTactic")
```

**Step 2: Instantiate in Client construction (near service creation)**

After the existing service instantiation block, add:

```lua
-- Tactical AI
local pack_tracker = PackTracker:new()
local tactical_selector = TacticalSelector:new(nil)  -- nil advisor for now (Phase 4)
tactical_selector:register(SingleTargetTactic:new())
tactical_selector:refresh_available({})

o._pack_tracker = pack_tracker
o._tactical_selector = tactical_selector
```

**Step 3: Pass into GrindService deps**

Where GrindService.build(deps) is called, add to the deps table:

```lua
deps.tactical_selector = o._tactical_selector
deps.pack_tracker = o._pack_tracker
```

**Step 4: Update PackTracker in the update loop**

In the update loop, after `Sensors:update()` and before the grind tree tick, add PackTracker update:

```lua
-- Update PackTracker from TargetingService's visible hostiles
if self._pack_tracker and self._services.targeting then
    local hostiles = self._services.targeting:get_visible_hostiles()
    local player_pos = self._blackboard:get("player.position")
    local player = self._blackboard:get("player.object")
    local player_guid = player and pcall(function() return player:get_guid() end) and player:get_guid() or ""
    if hostiles and player_pos then
        self._pack_tracker:update(hostiles, player_pos, player_guid)
        local pack = self._pack_tracker:get_pack()
        self._blackboard:set("pack.count", pack.count)
        self._blackboard:set("pack.centroid", pack.centroid)
        self._blackboard:set("pack.spread", pack.spread)
        self._blackboard:set("pack.gathered_count", pack.gathered_count)
        self._blackboard:set("pack.nearest_dist", pack.nearest_dist)
    end
end
```

**Note:** This requires TargetingService to expose `get_visible_hostiles()`. If that method doesn't exist, add a thin accessor that returns the already-scanned visible hostile objects from the targeting update. Check TargetingService for existing visible object data — it already scans them every tick for target scoring.

**Step 5: Refresh tactical preconditions on level-up**

Add an event listener for level changes:

```lua
o._event_bus:on(Events.ZONE_CHANGED, function()
    if o._tactical_selector then
        o._tactical_selector:refresh_available({})
    end
end)
```

**Step 6: Commit**

```bash
git add SentinelCore/core/Client.lua
git commit -m "feat(client): wire PackTracker and TacticalSelector into Client lifecycle"
```

---

## Task 8: Add get_visible_hostiles() to TargetingService

**Files:**
- Modify: `SentinelCore/services/TargetingService.lua`
- Create: `SentinelCore/tests/test_ai026_targeting_visible_hostiles.lua`
- Modify: `SentinelCore/tests/run_all.lua`

TargetingService already scans visible objects every update tick. We need a public accessor that returns the hostile subset.

**Step 1: Write the test**

```lua
-- SentinelCore/tests/test_ai026_targeting_visible_hostiles.lua
local T = require("tests/TestUtil")

return { run = function()
    -- Verify TargetingService has get_visible_hostiles method
    local TargetingService = require("services/TargetingService")

    -- Mock minimal TargetingService
    -- The method should return the last-scanned hostile objects or empty table
    T.assert_true(
        type(TargetingService.get_visible_hostiles) == "function"
        or type(TargetingService.prototype and TargetingService.prototype.get_visible_hostiles) == "function",
        "get_visible_hostiles method exists"
    )

    return { pass = true }
end }
```

**Step 2: Register test and implement**

In TargetingService, during the existing visible object scan (which already iterates all visible objects and filters hostile ones), cache the hostile subset:

```lua
-- Add field in constructor:
self._visible_hostiles = {}

-- During the existing scan in update(), after filtering hostiles:
self._visible_hostiles = hostiles  -- the filtered list already computed

-- New public method:
function TargetingService:get_visible_hostiles()
    return self._visible_hostiles or {}
end
```

**Step 3: Commit**

```bash
git add SentinelCore/services/TargetingService.lua SentinelCore/tests/test_ai026_targeting_visible_hostiles.lua SentinelCore/tests/run_all.lua
git commit -m "feat(targeting): expose get_visible_hostiles() for PackTracker consumption"
```

---

## Task 9: Full Integration Smoke Test

**Files:**
- Create: `SentinelCore/tests/test_ai027_tactical_smoke.lua`
- Modify: `SentinelCore/tests/run_all.lua`

**Step 1: Write smoke test**

This test verifies the full chain: TacticalSelector → SingleTargetTactic → TacticalPlanner → phase delegation.

```lua
-- SentinelCore/tests/test_ai027_tactical_smoke.lua
local T = require("tests/TestUtil")

return { run = function()
    local TacticalSelector = require("ai/TacticalSelector")
    local TacticalPlanner = require("ai/TacticalPlanner")
    local PackTracker = require("ai/PackTracker")
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local BT = require("ai/BehaviorTree")

    -- Full lifecycle test
    local selector = TacticalSelector:new(nil)
    local planner = TacticalPlanner:new()
    local tracker = PackTracker:new()

    -- Register SingleTarget
    selector:register(SingleTargetTactic:new())
    selector:refresh_available({})
    T.assert_eq(selector:get_available_count(), 1, "1 tactic available")

    -- Simulate: idle state (no combat, no target)
    local ctx1 = { enemy_count = 0, player_mana_pct = 1.0, pack_count = 0,
                   has_target = false, in_combat = false }
    local active1 = selector:select(ctx1)
    T.assert_eq(active1:get_name(), "single_target", "ST selected when idle")

    -- Simulate: target acquired, not yet in combat
    local ctx2 = { enemy_count = 1, player_mana_pct = 0.8, pack_count = 1,
                   has_target = true, in_combat = false }
    planner:set_tactic(active1)
    local status2 = planner:tick(ctx2, {})
    T.assert_eq(planner:get_current_phase_name(), "engage", "engage phase on target")

    -- Simulate: now in combat
    local ctx3 = { enemy_count = 1, player_mana_pct = 0.7, pack_count = 1,
                   has_target = true, in_combat = true, target_alive = true }
    local status3 = planner:tick(ctx3, {})
    T.assert_eq(planner:get_current_phase_name(), "combat", "combat phase when fighting")

    -- Simulate: combat ended
    local ctx4 = { enemy_count = 0, player_mana_pct = 0.3, pack_count = 0,
                   has_target = false, in_combat = false, target_alive = false }
    local status4 = planner:tick(ctx4, {})
    -- No phase should match (no target, no combat)
    T.assert_eq(status4, BT.Status.FAILURE, "no phase when idle — yields to loot/rest/explore")

    -- PackTracker: verify empty update
    tracker:update({}, { x = 0, y = 0, z = 0 }, "player")
    T.assert_eq(tracker:get_pack().count, 0, "empty pack")

    return { pass = true }
end }
```

**Step 2: Register test**

Add to `SentinelCore/tests/run_all.lua`:
```lua
    "tests/test_ai027_tactical_smoke",
```

**Step 3: Commit**

```bash
git add SentinelCore/tests/test_ai027_tactical_smoke.lua SentinelCore/tests/run_all.lua
git commit -m "test(tactical): add full integration smoke test for tactical BT chain"
```

---

## Task 10: Verify Zero Regression

**Step 1: Run full test suite**

Run all SentinelCore tests via in-game UI button. Expected: ALL tests pass, including all existing tests.

**Step 2: Manual verification**

Start a grind session with Ret Paladin or Affliction Warlock. Verify:
- Bot targets mobs normally
- Pull behavior unchanged
- Combat rotation works
- Looting works
- Vendor trips work (after bug fixes)
- Death recovery works
- Exploration behavior unchanged

The TacticalSelector automatically activates SingleTargetTactic, which delegates to the existing CombatService and PullService BT nodes. Behavior should be indistinguishable from pre-tactical-BT.

**Step 3: Commit any fixes found during verification**

---

## Summary

| Task | Files | Creates | Tests |
|------|-------|---------|-------|
| 1 | `ai/Tactic.lua` | Tactic interface | `test_ai020_tactic` |
| 2 | `ai/TacticalPlanner.lua` | Phase state machine | `test_ai021_tactical_planner` |
| 3 | `ai/PackTracker.lua` | Enemy clustering | `test_ai022_pack_tracker` |
| 4 | `ai/TacticalSelector.lua` | Utility scoring | `test_ai023_tactical_selector` |
| 5 | `tactics/SingleTargetTactic.lua` | Current behavior wrapper | `test_ai024_single_target_tactic` |
| 6 | `services/GrindService.lua` (mod) | Integration point | `test_ai025_grind_tactical_integration` |
| 7 | `core/Client.lua` (mod) | Lifecycle wiring | — |
| 8 | `services/TargetingService.lua` (mod) | Visible hostiles accessor | `test_ai026_targeting_visible_hostiles` |
| 9 | — | Smoke test | `test_ai027_tactical_smoke` |
| 10 | — | Manual verification | — |

**Total new LOC:** ~800 (4 new AI files + 1 tactic + 7 test files)
**Total modified:** ~100 lines across GrindService, Client, TargetingService
**Regression risk:** Zero — SingleTargetTactic delegates to existing services verbatim
