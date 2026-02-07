# GatherBuddy - Testing Strategy

**Version:** 1.0  
**Date:** January 31, 2025  

---

## 1. Overview

This document outlines the testing approach for GatherBuddy. Due to the nature of game automation, traditional unit testing is limited. We employ a combination of:

1. **Manual Unit Tests** - Inline test functions that verify module behavior
2. **Integration Tests** - Test modules working together
3. **Simulation Tests** - Mock game state for controlled testing
4. **Live Tests** - Real game testing with specific scenarios
5. **Regression Tests** - Ensure fixes don't break existing functionality

---

## 2. Test Categories

### 2.1 Unit Tests

Each module should include a `_test()` function that can be called manually.

```lua
-- Example: EventBus test
function EventBus:_test()
    local results = {}
    
    -- Test 1: Basic subscribe/publish
    local received = nil
    local id = self:subscribe("test:event", function(data)
        received = data.value
    end)
    self:publish("test:event", { value = 42 })
    results.basic_pubsub = (received == 42)
    
    -- Test 2: Unsubscribe
    self:unsubscribe(id)
    received = nil
    self:publish("test:event", { value = 99 })
    results.unsubscribe = (received == nil)
    
    -- Test 3: Priority ordering
    local order = {}
    self:subscribe("test:priority", function() table.insert(order, "B") end, 200)
    self:subscribe("test:priority", function() table.insert(order, "A") end, 100)
    self:publish("test:priority", {})
    results.priority = (order[1] == "A" and order[2] == "B")
    
    -- Test 4: Once
    local once_count = 0
    self:once("test:once", function() once_count = once_count + 1 end)
    self:publish("test:once", {})
    self:publish("test:once", {})
    results.once = (once_count == 1)
    
    -- Report
    for name, passed in pairs(results) do
        core.log("[TEST] EventBus." .. name .. ": " .. (passed and "PASS" or "FAIL"))
    end
    
    return results
end
```

### 2.2 Module Test Functions

#### JSON Tests

```lua
function JSON:_test()
    local results = {}
    
    -- Test encode/decode roundtrip
    local original = {
        name = "test",
        value = 123.456,
        enabled = true,
        items = {1, 2, 3},
        nested = { a = 1, b = "two" }
    }
    local encoded = JSON.encode(original)
    local decoded = JSON.decode(encoded)
    
    results.roundtrip_string = (decoded.name == "test")
    results.roundtrip_number = (math.abs(decoded.value - 123.456) < 0.001)
    results.roundtrip_boolean = (decoded.enabled == true)
    results.roundtrip_array = (#decoded.items == 3)
    results.roundtrip_nested = (decoded.nested.a == 1)
    
    -- Test escape sequences
    local with_escapes = { text = "line1\nline2\ttab\"quote" }
    local escaped = JSON.encode(with_escapes)
    local unescaped = JSON.decode(escaped)
    results.escapes = (unescaped.text:find("\n") ~= nil)
    
    -- Test null
    local with_null = '{"value": null}'
    local parsed_null = JSON.decode(with_null)
    results.null = (parsed_null.value == nil)
    
    return results
end
```

#### Helpers Tests

```lua
function Helpers:_test()
    local results = {}
    
    -- Test gaussian_random distribution
    local samples = {}
    for i = 1, 1000 do
        samples[i] = Helpers.gaussian_random(0, 100)
    end
    
    local sum = 0
    local min, max = 100, 0
    for _, v in ipairs(samples) do
        sum = sum + v
        min = math.min(min, v)
        max = math.max(max, v)
    end
    local mean = sum / #samples
    
    results.gaussian_mean = (mean > 40 and mean < 60)
    results.gaussian_bounds = (min >= 0 and max <= 100)
    
    -- Test distance calculations
    local p1 = { x = 0, y = 0, z = 0 }
    local p2 = { x = 3, y = 4, z = 0 }
    results.distance_3d = (math.abs(Helpers.distance_3d(p1, p2) - 5) < 0.001)
    results.distance_2d = (math.abs(Helpers.distance_2d(p1, p2) - 3) < 0.001)
    
    -- Test clamp
    results.clamp_below = (Helpers.clamp(-5, 0, 10) == 0)
    results.clamp_above = (Helpers.clamp(15, 0, 10) == 10)
    results.clamp_within = (Helpers.clamp(5, 0, 10) == 5)
    
    -- Test lerp
    results.lerp = (math.abs(Helpers.lerp(0, 10, 0.5) - 5) < 0.001)
    
    return results
end
```

#### StateMachine Tests

```lua
function StateMachine:_test()
    local results = {}
    local mock_bus = { publish = function() end }
    
    local sm = StateMachine:new(mock_bus, STATES.IDLE)
    
    -- Test initial state
    results.initial = (sm:get_state() == STATES.IDLE)
    
    -- Test valid transition
    results.valid_transition = sm:transition(STATES.LOADING)
    results.after_transition = (sm:get_state() == STATES.LOADING)
    
    -- Test invalid transition
    results.invalid_transition = not sm:transition(STATES.GATHERING)
    results.state_unchanged = (sm:get_state() == STATES.LOADING)
    
    -- Test can_transition
    results.can_transition_valid = sm:can_transition(STATES.TRAVELING)
    results.can_transition_invalid = not sm:can_transition(STATES.CORPSE_RUN)
    
    -- Test context
    sm:transition(STATES.TRAVELING, { waypoint = 1 })
    local ctx = sm:get_context()
    results.context_data = (ctx.data.waypoint == 1)
    results.context_previous = (ctx.previous_state == STATES.LOADING)
    
    return results
end
```

#### ProfileManager Tests

```lua
function ProfileManager:_test()
    local results = {}
    
    -- Test validation - valid profile
    local valid_profile = {
        version = "1.0",
        metadata = { name = "Test" },
        requirements = { map_id = 37 },
        settings = { loop = true },
        waypoints = {
            { id = 1, x = 0, y = 0, z = 0, type = "path" },
            { id = 2, x = 10, y = 0, z = 10, type = "hotspot", radius = 30 }
        }
    }
    local valid, errors = self:validate_profile(valid_profile)
    results.valid_profile = (valid == true and #errors == 0)
    
    -- Test validation - missing required fields
    local invalid_profile = {
        version = "1.0",
        waypoints = {}
    }
    valid, errors = self:validate_profile(invalid_profile)
    results.invalid_missing_fields = (valid == false and #errors > 0)
    
    -- Test validation - invalid waypoint
    local bad_waypoint_profile = {
        version = "1.0",
        metadata = { name = "Test" },
        requirements = { map_id = 37 },
        settings = {},
        waypoints = {
            { id = 1, type = "path" }  -- Missing coordinates
        }
    }
    valid, errors = self:validate_profile(bad_waypoint_profile)
    results.invalid_waypoint = (valid == false)
    
    -- Test blackspot check
    self._current_profile = {
        blackspots = {
            { x = 100, y = 50, z = 100, radius = 20 }
        }
    }
    results.in_blackspot = self:is_in_blackspot({ x = 105, y = 50, z = 105 })
    results.outside_blackspot = not self:is_in_blackspot({ x = 200, y = 50, z = 200 })
    
    return results
end
```

### 2.3 Integration Tests

#### Movement + Navigation Integration

```lua
function Test_Movement_Navigation()
    local results = {}
    
    -- Setup
    local event_bus = EventBus:new()
    local nav_client = NavigationClient:new(event_bus)
    local movement = MovementModule:new(event_bus, nav_client)
    
    -- Test: Path request triggers nav client
    local path_requested = false
    event_bus:subscribe(EVENTS.PATH_REQUEST, function()
        path_requested = true
    end)
    
    movement:move_to(vec3.new(100, 50, 100), true)
    results.path_request_sent = path_requested
    
    -- Simulate path received
    event_bus:publish(EVENTS.PATH_RECEIVED, {
        path = {
            vec3.new(50, 50, 50),
            vec3.new(75, 50, 75),
            vec3.new(100, 50, 100)
        }
    })
    
    results.movement_started = movement:is_moving()
    
    return results
end
```

#### Gathering Flow Integration

```lua
function Test_Gathering_Flow()
    local results = {}
    
    -- Setup
    local event_bus = EventBus:new()
    local scanner = NodeScanner:new(event_bus)
    local gather = GatherModule:new(event_bus, scanner)
    
    -- Track events
    local events_received = {}
    event_bus:subscribe(EVENTS.GATHER_START, function() 
        events_received.start = true 
    end)
    event_bus:subscribe(EVENTS.GATHER_SUCCESS, function() 
        events_received.success = true 
    end)
    
    -- Mock node
    local mock_node = {
        is_valid = function() return true end,
        get_name = function() return "Copper Vein" end,
        get_position = function() return vec3.new(50, 50, 50) end
    }
    
    -- Start gather
    gather:start_gather(mock_node)
    results.gather_started = gather:is_gathering()
    results.start_event = events_received.start == true
    
    return results
end
```

---

## 3. Test Scenarios

### 3.1 Happy Path Scenarios

| ID | Scenario | Steps | Expected Result |
|----|----------|-------|-----------------|
| HP-01 | Basic gathering loop | Load profile → Start → Travel → Detect node → Gather → Loot → Continue | Node gathered, route continues |
| HP-02 | Hotspot behavior | Reach hotspot waypoint → Linger → Scan → Find node → Gather | Bot waits at hotspot, gathers nearby nodes |
| HP-03 | Route completion | Complete all waypoints with loop=true | Route restarts from beginning |
| HP-04 | Mount usage | Travel 50+ yards | Bot mounts, travels, dismounts at destination |

### 3.2 Error Scenarios

| ID | Scenario | Steps | Expected Result |
|----|----------|-------|-----------------|
| ER-01 | Node despawns during approach | Node detected → Start approaching → Node despawns | Bot blacklists, returns to route |
| ER-02 | Gather interrupted | Start gathering → Enter combat | Gather cancelled, combat handled |
| ER-03 | Stuck during movement | Travel to point blocked by geometry | Stuck detected, recovery attempted |
| ER-04 | Navigation service down | Request path → Service unavailable | Retry logic, fallback to direct movement |
| ER-05 | Invalid profile | Load malformed JSON | Error shown, bot stays idle |

### 3.3 Edge Cases

| ID | Scenario | Steps | Expected Result |
|----|----------|-------|-----------------|
| EC-01 | Node at exact same position | Waypoint and node at same coords | Still detects and gathers |
| EC-02 | Multiple nodes in range | 3 nodes visible simultaneously | Picks best candidate with randomization |
| EC-03 | Death at waypoint | Die at exact waypoint position | Resurrect, continue from same waypoint |
| EC-04 | Empty loot window | Gather succeeds but no loot | Treat as success, continue |
| EC-05 | Combat during loot | Looting when attacked | Close loot, handle combat |

---

## 4. Test Execution

### 4.1 Running Unit Tests

```lua
-- In game console or init.lua for testing
local function run_all_tests()
    core.log("=== GatherBuddy Test Suite ===")
    
    local modules = {
        { name = "JSON", instance = require("utils/JSON") },
        { name = "Helpers", instance = require("utils/Helpers") },
        { name = "EventBus", instance = EventBus:new() },
        -- Add other modules...
    }
    
    local total_pass = 0
    local total_fail = 0
    
    for _, mod in ipairs(modules) do
        if mod.instance._test then
            core.log("\n--- Testing " .. mod.name .. " ---")
            local results = mod.instance:_test()
            
            for test_name, passed in pairs(results) do
                if passed then
                    total_pass = total_pass + 1
                    core.log("  ✓ " .. test_name)
                else
                    total_fail = total_fail + 1
                    core.log("  ✗ " .. test_name)
                end
            end
        end
    end
    
    core.log("\n=== Results ===")
    core.log("Passed: " .. total_pass)
    core.log("Failed: " .. total_fail)
    
    return total_fail == 0
end

-- Call: run_all_tests()
```

### 4.2 Live Testing Checklist

Before each release, manually verify:

#### Basic Functionality
- [ ] Profile loads successfully
- [ ] Bot starts and enters TRAVELING state
- [ ] Waypoints are followed in order
- [ ] Hotspots trigger scanning
- [ ] Nodes are detected within radius
- [ ] Gathering animation plays
- [ ] Loot is collected
- [ ] Route loops correctly

#### Movement
- [ ] Mount triggers at correct distance
- [ ] Dismount occurs before gathering
- [ ] Stuck detection activates when blocked
- [ ] Unstuck strategies work
- [ ] Path deviation is visible (not straight lines)

#### Safety
- [ ] Enemy detection radius is accurate
- [ ] Combat state is detected
- [ ] Death triggers spirit release
- [ ] Corpse run navigates correctly
- [ ] Resurrection works

#### Anti-Detection
- [ ] Random pauses occur
- [ ] Timing varies (not robotic)
- [ ] Gathering order isn't always nearest
- [ ] Jumps occur during travel

### 4.3 Regression Test Cases

Run after any code changes:

| ID | Test | Verify |
|----|------|--------|
| REG-01 | Profile loading | Load existing valid profile |
| REG-02 | State transitions | Start → Stop → Start cycle |
| REG-03 | Event delivery | Events reach all subscribers |
| REG-04 | Node filtering | Blackspots respected |
| REG-05 | Timing functions | Delays are in expected range |

---

## 5. Mocking

### 5.1 Mock Game Objects

```lua
---@class MockGameObject
local MockGameObject = {}

function MockGameObject:new(config)
    local obj = {
        _valid = config.valid ~= false,
        _name = config.name or "Mock Object",
        _position = config.position or vec3.new(0, 0, 0),
        _can_loot = config.can_loot or false,
        _can_use = config.can_use or false,
        _dead = config.dead or false,
        _ghost = config.ghost or false,
        _combat = config.combat or false,
        _mounted = config.mounted or false,
        _casting = config.casting or false,
        _health = config.health or 100,
        _max_health = config.max_health or 100,
    }
    
    function obj:is_valid() return self._valid end
    function obj:get_name() return self._name end
    function obj:get_position() return self._position end
    function obj:can_be_looted() return self._can_loot end
    function obj:can_be_used() return self._can_use end
    function obj:is_dead() return self._dead end
    function obj:is_ghost() return self._ghost end
    function obj:is_in_combat() return self._combat end
    function obj:is_mounted() return self._mounted end
    function obj:is_casting_spell() return self._casting end
    function obj:get_health() return self._health end
    function obj:get_max_health() return self._max_health end
    
    return obj
end

return MockGameObject
```

### 5.2 Mock Core APIs

```lua
-- Mock core.object_manager for testing
local MockObjectManager = {
    _local_player = nil,
    _objects = {},
    
    set_local_player = function(self, player)
        self._local_player = player
    end,
    
    set_objects = function(self, objects)
        self._objects = objects
    end,
    
    get_local_player = function(self)
        return self._local_player
    end,
    
    get_all_objects = function(self)
        return self._objects
    end
}
```

---

## 6. Continuous Testing

### 6.1 Pre-Commit Checks

Before committing code:

1. Run unit tests for modified modules
2. Verify no syntax errors (Lua linter)
3. Check for forbidden API calls:
   ```bash
   grep -r "GetSpellInfo\|UnitHealth\|C_Map\|C_Timer" *.lua
   ```
4. Verify all `get_local_player()` calls are nil-checked
5. Verify all game_object usage includes `is_valid()` check

### 6.2 Daily Testing

During active development:

- Run full test suite
- Execute HP-01 (basic gathering loop) manually
- Check for memory leaks (monitor Lua heap)
- Verify logging output is appropriate

### 6.3 Release Testing

Before each release:

1. Complete test suite passes
2. All regression tests pass
3. 30-minute live gathering session
4. Test on both Classic and Retail (if applicable)
5. Test profile creation and loading
6. Test all error recovery scenarios

---

## 7. Known Limitations

Testing is limited by:

1. **No automated game interaction** - Cannot fully automate game state
2. **Timing sensitivity** - Some tests depend on frame timing
3. **Server variability** - Node spawns vary by server
4. **API mocking complexity** - Full Sylvannas API mock is impractical

Mitigations:
- Focus unit tests on pure logic (no game API)
- Use event-driven design for testability
- Document manual testing procedures
- Maintain detailed test logs

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-31 | Alex | Initial draft |
