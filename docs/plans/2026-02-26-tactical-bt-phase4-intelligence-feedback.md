# Phase 4: Intelligence + Feedback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the bot learn from session performance by adding a PerformanceAdvisor that biases tactic selection based on XP/hr and death rate, adds level-up detection, and gives Frost Mage conjure spells for self-sufficiency.

**Architecture:** PerformanceAdvisor subscribes to Telemetry events and tracks per-tactic metrics (kills/hr, deaths/hr, XP/hr). It implements the `get_bias(tactic_name)` API that TacticalSelector already accepts. Level-up detection in Sensors emits events that downstream systems can react to. Frost.lua gains conjure water/food in `precombat()` for mana/food self-sufficiency.

**Tech Stack:** Lua 5.1, EventBus pub/sub, Telemetry snapshots, forward-slash requires.

---

### Task 1: Create PerformanceAdvisor

**Files:**
- Create: `SentinelCore/ai/PerformanceAdvisor.lua`
- Test: `SentinelCore/tests/test_ai031_performance_advisor.lua`

**Context:** PerformanceAdvisor subscribes to `telemetry.flushed` events and tracks per-tactic performance windows. It provides `get_bias(tactic_name) → number` for TacticalSelector. The bias is a multiplier: >1.0 boosts a tactic, <1.0 suppresses it.

**Implementation:**

```lua
local PerformanceAdvisor = {}
PerformanceAdvisor.__index = PerformanceAdvisor

--- Window-based tracking: store last N snapshots per tactic
--- When a tactic is active, attribute current kills/deaths/xp to it

function PerformanceAdvisor:new(event_bus)
    local o = setmetatable({
        _event_bus = event_bus,
        _tactic_stats = {},  -- { [name] = { kills=0, deaths=0, xp_gained=0, active_secs=0 } }
        _active_tactic = nil,
        _last_snapshot = nil,
        _biases = {},  -- { [name] = number }
        _min_sample_secs = 120,  -- need 2min of data before biasing
    }, self)

    if event_bus then
        event_bus:on("telemetry.flushed", function(data)
            o:_on_telemetry(data)
        end, { owner = o })
    end

    return o
end

function PerformanceAdvisor:set_active_tactic(name)
    self._active_tactic = name
end

function PerformanceAdvisor:get_bias(tactic_name)
    return self._biases[tactic_name] or 1.0
end

function PerformanceAdvisor:get_stats(tactic_name)
    return self._tactic_stats[tactic_name]
end

--- Called on each telemetry flush (~1/sec)
--- Attributes delta kills/deaths/xp to active tactic
function PerformanceAdvisor:_on_telemetry(data)
    local snapshot = data and data.snapshot
    if not snapshot then return end

    local name = self._active_tactic
    if not name then
        self._last_snapshot = snapshot
        return
    end

    -- Initialize tactic stats
    if not self._tactic_stats[name] then
        self._tactic_stats[name] = { kills = 0, deaths = 0, xp_gained = 0, active_secs = 0 }
    end
    local stats = self._tactic_stats[name]

    -- Compute deltas from last snapshot
    if self._last_snapshot then
        local prev = self._last_snapshot
        local dk = (snapshot.kills or 0) - (prev.kills or 0)
        local dd = (snapshot.deaths or 0) - (prev.deaths or 0)
        local dx = (snapshot.xp_gained or 0) - (prev.xp_gained or 0)
        if dk > 0 then stats.kills = stats.kills + dk end
        if dd > 0 then stats.deaths = stats.deaths + dd end
        if dx > 0 then stats.xp_gained = stats.xp_gained + dx end
        stats.active_secs = stats.active_secs + 1
    end

    self._last_snapshot = snapshot
    self:_recompute_biases()
end

--- Recompute tactic biases based on accumulated stats
--- Tactic with better xp/hr gets boosted, worse gets suppressed
--- Deaths heavily penalize: each death = -300 xp equivalent
function PerformanceAdvisor:_recompute_biases()
    local scores = {}
    local max_score = 0
    local has_data = false

    for name, stats in pairs(self._tactic_stats) do
        if stats.active_secs >= self._min_sample_secs then
            has_data = true
            local effective_xp = stats.xp_gained - (stats.deaths * 300)
            local score = effective_xp / stats.active_secs  -- xp per second
            scores[name] = math.max(score, 0.001)
            if scores[name] > max_score then max_score = scores[name] end
        end
    end

    if not has_data or max_score <= 0 then return end

    -- Normalize: best tactic gets 1.2x, worst gets 0.8x
    for name, score in pairs(scores) do
        local ratio = score / max_score  -- 0..1
        self._biases[name] = 0.8 + 0.4 * ratio  -- 0.8..1.2
    end
end

function PerformanceAdvisor:reset()
    self._tactic_stats = {}
    self._biases = {}
    self._active_tactic = nil
    self._last_snapshot = nil
end

function PerformanceAdvisor:destroy()
    if self._event_bus then
        self._event_bus:off_owner(self)
    end
end

return PerformanceAdvisor
```

**Tests:**
1. `new` — creates with empty stats and biases
2. `get_bias` — returns 1.0 for unknown tactics
3. `set_active_tactic` + `_on_telemetry` — accumulates kills/deaths/xp to active tactic
4. `_recompute_biases` — better-performing tactic gets higher bias
5. `_min_sample_secs` — no bias applied before minimum sample period
6. `reset` — clears all stats
7. `destroy` — unsubscribes from event bus

**Commit:** `feat(ai): add PerformanceAdvisor for tactic-level feedback`

---

### Task 2: Wire PerformanceAdvisor into Client.lua + GrindService

**Files:**
- Modify: `SentinelCore/core/Client.lua`
- Modify: `SentinelCore/services/GrindService.lua`

**Context:** Client.lua creates the TacticalSelector with `nil` advisor. Replace with a PerformanceAdvisor instance. Also, the tactical_sync_node in GrindService needs to tell the advisor which tactic is currently active.

**Step 1:** In Client.lua, require PerformanceAdvisor and create it:
```lua
local PerformanceAdvisor = require("ai/PerformanceAdvisor")
-- In Client:new()
local advisor = PerformanceAdvisor:new(o._event_bus)
local tactical_selector = TacticalSelector:new(advisor)
o._performance_advisor = advisor
```

**Step 2:** In GrindService's `build_tactical_sync_node`, after selecting the active tactic, notify the advisor:
```lua
-- After: local active = selector:select(ctx)
if active and deps.performance_advisor then
    deps.performance_advisor:set_active_tactic(active:get_name())
end
```

Pass `performance_advisor` through deps in GrindService.build().

**Step 3:** In Client.lua where GrindService.build is called, add `performance_advisor` to the deps table.

**Commit:** `feat(client): wire PerformanceAdvisor into TacticalSelector`

---

### Task 3: Add level-up detection event

**Files:**
- Modify: `SentinelCore/core/Sensors.lua`
- Modify: `SentinelCore/events/Events.lua` (add event constant if pattern requires it)

**Context:** Sensors.lua reads `player.level` each frame. Add detection for level changes and emit a `player.level_up` event via EventBus.

**Step 1:** In Sensors.lua, after setting `player.level`, add level change tracking:
```lua
local current_level = safe_method(player, "get_level") or 1
bb:set("player.level", current_level)

-- Level-up detection
local prev_level = self._last_player_level or current_level
if current_level > prev_level and prev_level > 0 then
    self._event_bus:emit("player.level_up", {
        previous_level = prev_level,
        new_level = current_level,
    })
end
self._last_player_level = current_level
```

**Step 2:** Initialize `_last_player_level = nil` in Sensors constructor.

**Commit:** `feat(sensors): emit player.level_up event on level change`

---

### Task 4: Add Conjure Water/Food to Frost.lua precombat

**Files:**
- Modify: `SentinelCore/rotations/mage/Frost.lua`
- Modify: `SentinelCore/tests/test_rotation_mage_frost_regressions.lua`

**Context:** Frost.lua's `precombat()` currently returns empty. Mages should conjure water and food between pulls when their inventory is low. Use `self_spell` with the CONJURE_WATER and CONJURE_FOOD spell entries.

**Step 1:** Implement `precombat()`:
```lua
function Frost:precombat(ctx)
    if ctx.player_is_stunned or ctx.player_is_feared then
        return {}
    end

    local actions = {}
    local p = policy(ctx)

    -- Conjure Water (priority 200) — when mana > 30% and no water in bags
    local water_id = resolve_spell(ctx, SPELLS.CONJURE_WATER)
    if water_id then
        actions[#actions + 1] = self_spell(water_id, 200, {
            min_player_mana_pct = 0.30,
            intent = "sustain",
            condition = function(local_ctx)
                -- Only conjure if not in combat and haven't conjured recently
                return local_ctx.in_combat ~= true
                    and local_ctx.in_combat ~= 1
            end,
        })
    end

    -- Conjure Food (priority 195) — when mana > 30%
    local food_id = resolve_spell(ctx, SPELLS.CONJURE_FOOD)
    if food_id then
        actions[#actions + 1] = self_spell(food_id, 195, {
            min_player_mana_pct = 0.30,
            intent = "sustain",
            condition = function(local_ctx)
                return local_ctx.in_combat ~= true
                    and local_ctx.in_combat ~= 1
            end,
        })
    end

    return actions
end
```

**Step 2:** Update the test file with precombat tests:
- `precombat` returns conjure water and food actions when spells are learned
- Returns empty when stunned/feared
- Actions have correct priorities and mana conditions

**Commit:** `feat(rotations): add Conjure Water/Food to Frost Mage precombat`

---

### Task 5: Integration smoke test

**Files:**
- Create: `SentinelCore/tests/test_ai031_performance_advisor.lua` (if not done in Task 1)
- Create: `SentinelCore/tests/test_ai032_intelligence_smoke.lua`

**Context:** Smoke test verifying the full feedback loop: PerformanceAdvisor subscribes to events, tracks tactic performance, computes biases, TacticalSelector uses biases.

**Tests:**
1. Create EventBus + PerformanceAdvisor. Fire telemetry events simulating 60 kills under "single_target" tactic and 20 kills + 5 deaths under "aoe_kite". Verify single_target gets higher bias.
2. Wire advisor into TacticalSelector. Verify biased tactic selection changes outcome when base utilities are close.
3. Level-up event emission: mock Sensors with level change and verify event fires.

**Register in run_all.lua.**

**Commit:** `test(ai): add intelligence feedback smoke test`

---

### Task 6: Static verification

**Checklist:**
1. PerformanceAdvisor file exists with correct API
2. Client.lua creates advisor and passes to TacticalSelector
3. GrindService tactical_sync_node notifies advisor of active tactic
4. Sensors.lua emits player.level_up
5. Frost.lua precombat() returns conjure actions
6. All new tests registered in run_all.lua
7. No duplicate tests
8. All requires use forward slashes
