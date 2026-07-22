---
title: "Spell Queue"
source: "https://docs.project-sylvanas.net/dev/modules/spell-queue"
crawled: "2026-07-14"
---

# Spell Queue

## Overview

The Spell Queue module provides a priority-based system for queuing spells and items. Instead of trying to cast spells directly (which may cause issues with timing, GCD, or compatibility), you queue them with a priority and the system handles execution at the optimal time.

**Key Features:**

-   **Priority System** - Enables multiple plugins to work together seamlessly
-   **Fast Variants** - Queue casts that skip GCD checks (off-GCD abilities)
-   **Multiple Cast Types** - Self-cast, target, and position-based casts
-   **Items & Spells** - Queue both spells and item uses
-   **Movement Control** - Allow or block movement during cast
-   **Queue Management** - Inspect and purge queued entries

## Why Use Spell Queue?

Using raw input functions like `core.input.cast_target_spell()` directly has several problems:

1.  **Plugin Compatibility** - If your script spams cast requests, other modules like "Universal Interrupt" or "Universal Dispel" won't be able to cast their spells when needed.

2.  **User Experience** - Spamming raw inputs prevents users from casting spells manually when they need to.

3.  **Safety** - Sending too many packets per second could potentially flag anti-cheat systems.

The Spell Queue solves all of these by implementing a priority queue that processes casts intelligently.

## Importing The Module

```lua
---@type spell_queue
local spell_queue = require("common/modules/spell_queue")
```

> **Note:** Access functions with `:` (colon), not `.` (dot).

---

## Priority System

The priority system exists primarily to enable **multiple plugins to work together**, not for prioritizing spells within your own rotation.

### The Golden Rule

> **Priority 1 for Everything in Your Plugin**
>
> **Use priority `1` for 99% of your spells.** The priority system is designed for cross-plugin compatibility, not for ordering spells within your own rotation. Your rotation logic should determine *what* to cast - the queue just handles *when*.

### Priority Levels Explained

| Priority | Reserved For | Example |
|----------|-------------|---------|
| `1` | **All normal rotation spells** | Fireball, Frostbolt, Shadow Bolt, Mortal Strike |
| `2` | Special cases only (with strong justification) | Rarely needed |
| `4-6` | Core utilities (separate plugins) | Racials, dispels, spell reflects |
| `7` | Interrupts (separate plugins) | Universal Interrupt module |
| `9` | **Manual player input only** | Player pressing a keybind |

### Why This Matters

Imagine you have three plugins running:

-   **Damage Rotation** (priority 1) - Your main DPS rotation
-   **Universal Dispel** (priority 5) - Removes dangerous debuffs
-   **Universal Interrupt** (priority 7) - Kicks important casts

When an enemy starts casting a dangerous spell:

1.  Your rotation queues Fireball at priority 1
2.  Universal Interrupt queues Counterspell at priority 7
3.  **Counterspell executes first** because it has higher priority
4.  After the interrupt, Fireball continues normally

This is the **only** correct use of the priority system.

### Common Mistakes

❌ **Wrong** - Using different priorities within your rotation:

```lua
-- DON'T DO THIS
if has_proc then
    spell_queue:queue_spell_target(PYROBLAST, target, 4, "Pyroblast")  -- Wrong!
end
spell_queue:queue_spell_target(FIREBALL, target, 2, "Fireball")  -- Wrong!
```

✅ **Correct** - Use priority 1 and let your logic decide:

```lua
-- DO THIS
if has_proc then
    spell_queue:queue_spell_target(PYROBLAST, target, 1, "Pyroblast")
    return  -- Exit early, Pyroblast is queued
end
spell_queue:queue_spell_target(FIREBALL, target, 1, "Fireball")
```

Your rotation code decides the order. The queue just executes.

---

## Spell Functions

### `queue_spell_target`

Queue a spell to cast on a target.

```lua
spell_queue:queue_spell_target(
    spell_id: number,
    target: game_object,
    priority: number,
    message?: string,
    allow_movement?: boolean
): nil
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `spell_id` | `number` | Required | The spell ID to cast |
| `target` | `game_object` | Required | Target for the spell |
| `priority` | `number` | Required | Use `1` for rotation spells |
| `message` | `string` | `nil` | Optional debug message |
| `allow_movement` | `boolean` | `false` | Allow movement during cast |

**Example:**

```lua
local spell_queue = require("common/modules/spell_queue")
local FIREBALL = 133
local target = core.object_manager.get_target()

-- Always use priority 1 for rotation spells
spell_queue:queue_spell_target(FIREBALL, target, 1, "Fireball")
```

---

### `queue_spell_target_fast`

Same as `queue_spell_target` but **skips GCD checks**. Use for off-GCD abilities.

```lua
spell_queue:queue_spell_target_fast(
    spell_id: number,
    target: game_object,
    priority: number,
    message?: string,
    allow_movement?: boolean
): nil
```

**Example:**

```lua
-- Fire Blast is off-GCD, use fast variant
local FIRE_BLAST = 108853
spell_queue:queue_spell_target_fast(FIRE_BLAST, target, 1, "Fire Blast")
```

---

### `queue_spell_position`

Queue a ground-targeted spell at a world position.

```lua
spell_queue:queue_spell_position(
    spell_id: number,
    position: vec3,
    priority: number,
    message?: string,
    allow_movement?: boolean
): nil
```

**Example:**

```lua
local BLIZZARD = 190356
local target_pos = target:get_position()
spell_queue:queue_spell_position(BLIZZARD, target_pos, 1, "Blizzard")
```

> **Note:** For AOE spells, use the [Spell Prediction](/dev/libraries/modules/spell-prediction) module to find the optimal cast position that hits the most enemies.

---

### `queue_spell_position_fast`

Position-targeted spell that skips GCD checks.

```lua
spell_queue:queue_spell_position_fast(
    spell_id: number,
    position: vec3,
    priority: number,
    message?: string,
    allow_movement?: boolean
): nil
```

---

## Item Functions

### `queue_item_self`

Queue an item for self-use (potions, food, etc.).

```lua
spell_queue:queue_item_self(item_id: number, priority: number, message?: string): nil
```

**Example:**

```lua
local HEALTH_POTION = 191380
spell_queue:queue_item_self(HEALTH_POTION, 1, "Health Potion")
```

---

### `queue_item_self_fast`

Self-use item that skips GCD checks. Most items don't have GCD, so this is commonly used.

```lua
spell_queue:queue_item_self_fast(item_id: number, priority: number, message?: string): nil
```

---

### `queue_item_target`

Queue an item to use on a target.

```lua
spell_queue:queue_item_target(
    item_id: number,
    target: game_object,
    priority: number,
    message?: string
): nil
```

---

### `queue_item_target_fast`

Target item that skips GCD checks.

```lua
spell_queue:queue_item_target_fast(
    item_id: number,
    target: game_object,
    priority: number,
    message?: string
): nil
```

---

### `queue_item_position`

Queue an item to use at a position (engineering items, etc.).

```lua
spell_queue:queue_item_position(
    item_id: number,
    position: vec3,
    priority: number,
    message?: string
): nil
```

---

### `queue_item_position_fast`

Position item that skips GCD checks.

```lua
spell_queue:queue_item_position_fast(
    item_id: number,
    position: vec3,
    priority: number,
    message?: string
): nil
```

---

## Queue Management

### `get_queue_snapshot`

Returns a shallow snapshot of the queue for debugging.

```lua
spell_queue:get_queue_snapshot(): table
```

**Returns:**

```lua
{
    [1] = {
        spell_id = number,
        spell_type = integer,
        target = game_object | nil,
        position = vec3 | nil,
        priority = number,
        timestamp = number,
        skips_global = boolean,
        is_item_exception = boolean,
        allow_movement = boolean
    },
    -- ...
}
```

**Example:**

```lua
local snapshot = spell_queue:get_queue_snapshot()
core.log("Queued entries: " .. #snapshot)
for i, entry in ipairs(snapshot) do
    core.log(string.format("  %d: spell=%d priority=%d", i, entry.spell_id, entry.priority))
end
```

---

### `purge_by_spell`

Remove specific spells from the queue.

```lua
spell_queue:purge_by_spell(spell_id: number, target?: game_object): integer
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `spell_id` | `number` | Spell ID to remove |
| `target` | `game_object` | Optional: only remove entries for this target |

**Returns:** Number of entries removed.

**Example:**

```lua
-- Remove all queued Fireballs
local removed = spell_queue:purge_by_spell(133)

-- Remove Fireballs only for a specific target
local removed = spell_queue:purge_by_spell(133, some_target)
```

---

## Complete Example

Here's a properly structured rotation using the spell queue:

```lua
---@type spell_queue
local spell_queue = require("common/modules/spell_queue")

---@type spell_helper
local spell_helper = require("common/utility/spell_helper")

local SPELLS = {
    FIREBALL = 133,
    FIRE_BLAST = 108853,
    PYROBLAST = 11366,
    COMBUSTION = 190319,
}

local last_queue_time = 0.0

local function rotation()
    local current_time = core.game_time()

    -- Throttle to avoid spamming the queue
    if current_time - last_queue_time < 0.25 then
        return
    end

    local player = core.object_manager.get_local_player()
    if not player then return end

    local target = player:get_target()
    if not target then return end

    -- Don't queue while casting
    local cast_end = player:get_active_spell_cast_end_time()
    if current_time <= cast_end then
        return
    end

    -- Priority in code determines what gets queued
    -- Queue priority is always 1

    -- Cooldowns first (in our logic, not queue priority)
    if should_use_combustion() then
        if spell_helper:is_spell_castable(SPELLS.COMBUSTION, player, player, false, false) then
            spell_queue:queue_spell_target(SPELLS.COMBUSTION, player, 1, "Combustion")
            last_queue_time = current_time
            return
        end
    end

    -- Off-GCD abilities (use _fast variant)
    if has_heating_up() then
        if spell_helper:is_spell_castable(SPELLS.FIRE_BLAST, player, target, false, false) then
            spell_queue:queue_spell_target_fast(SPELLS.FIRE_BLAST, target, 1, "Fire Blast")
            last_queue_time = current_time
            return
        end
    end

    -- Procs
    if has_hot_streak() then
        if spell_helper:is_spell_castable(SPELLS.PYROBLAST, player, target, false, false) then
            spell_queue:queue_spell_target(SPELLS.PYROBLAST, target, 1, "Pyroblast")
            last_queue_time = current_time
            return
        end
    end

    -- Filler
    if spell_helper:is_spell_castable(SPELLS.FIREBALL, player, target, false, false) then
        spell_queue:queue_spell_target(SPELLS.FIREBALL, target, 1, "Fireball")
        last_queue_time = current_time
    end
end

core.register_on_update_callback(rotation)
```

**Key Points:**

-   All spells use **priority 1**
-   Code logic determines what spell to queue (early returns)
-   `spell_helper:is_spell_castable()` checks before queuing
-   `_fast` variant for off-GCD abilities
-   Throttle to avoid queue spam

---

## Best Practices

### 1. Always Use Priority 1

Unless you're writing a utility plugin (interrupts, dispels), use priority 1.

### 2. Check Before Queuing

Always verify the spell is castable before adding it to the queue:

```lua
if spell_helper:is_spell_castable(spell_id, player, target, false, false) then
    spell_queue:queue_spell_target(spell_id, target, 1, "My Spell")
end
```

### 3. Throttle Your Queue Calls

Don't call queue functions every frame. Add a time check:

```lua
local last_queue_time = 0
local QUEUE_INTERVAL = 0.25

local function rotation()
    if core.game_time() - last_queue_time < QUEUE_INTERVAL then
        return
    end
    -- ... queue logic ...
    last_queue_time = core.game_time()
end
```

### 4. Use Fast Variants for Off-GCD

Abilities that don't trigger GCD should use `_fast` functions:

-   Fire Blast, Ice Lance procs
-   Many defensive cooldowns
-   Racial abilities
-   Most trinkets and items

### 5. Use Messages for Debugging

The message parameter helps with debugging:

```lua
spell_queue:queue_spell_target(SPELL_ID, target, 1, "Fireball - Hot Streak proc")
```

### 6. Let Code Logic Handle Priority

Your rotation code decides what to cast. Use `if/elseif` chains or early returns:

```lua
-- Good: Logic handles priority
if emergency_defensive_needed() then
    queue_defensive()
    return
end
if proc_available() then
    queue_proc_spell()
    return
end
queue_filler()
```

---

## When NOT to Use Spell Queue

For items without GCD (most items), raw functions are acceptable with proper checks:

```lua
local item_cooldown = player:get_item_cooldown(item_id)
if item_cooldown <= 0 then
    core.input.use_item(item_id)
end
```

However, **for items that trigger GCD**, use the spell queue.

---

## Related Documentation

-   [Input Functions](/dev/api/input) - Raw input functions
-   [Spell Helper](/dev/api/spell-helper) - Spell castability checks
-   [Spell Prediction](/dev/libraries/modules/spell-prediction) - Optimal AOE positioning
-   [Spell Book](/dev/api/spellbook) - Spell information queries
