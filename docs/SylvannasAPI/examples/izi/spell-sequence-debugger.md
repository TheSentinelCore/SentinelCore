---
title: "Spell Sequence Debugger"
source: "https://docs.project-sylvanas.net/dev/examples/tbc-warlock-affliction"
crawled: "2026-07-14"
---

# Spell Sequence Debugger

## Overview

This open-source example implements a complete **TBC Affliction Warlock rotation** using the IZI SDK's spell system. But the rotation itself isn't the main event — this plugin is a showcase for a powerful development workflow that combines **callback-based spell priorities** with **Nova's SpellDebugger**, enabling an AI-assisted feedback loop that makes building and debugging rotations dramatically faster.

The idea is simple: structure your rotation as a table of named callbacks, wire them into the SpellDebugger with a single line, and you get both a real-time in-game debug UI and an exportable report that you can hand to an AI agent. The agent reads the report, sees exactly which spells passed or failed and why, and fixes the rotation for you.

**Key Features:**
- **Callback-Based Rotation** — each spell is a named function that returns true/false, tried in priority order
- **SpellDebugger Integration** — real-time in-game UI showing every decision the rotation makes
- **Exportable Debug Reports** — structured Lua tables an AI agent can read and reason about
- **AI Feedback Loop** — describe what you want in natural language, test, export, let the AI iterate
- **Auto Rank Detection** — scans the spellbook to always use the highest rank of each spell
- **Reactive Procs** — Nightfall (Shadow Trance) triggers instant Shadow Bolt at highest priority
- **Full Menu System** — per-spell toggles, keybind toggle, control panel integration

## Requirements

- **[FBR - The Node](https://project-sylvanas.net/panel/plugins/detail/401)** by Nova — provides the SpellDebugger system. The rotation works without it, but you lose the debug UI and export capability.

## The AI Feedback Loop

```
┌─────────────────┐     natural language      ┌──────────────┐
│    Developer    │ ──────────────────────▶  |   AI Agent    │
│ (or vibe-coder) │                           │              │
└────────┬────────┘                           └──────┬───────┘
         │                                           │
         │  test in-game                             │  generates/fixes
         │  for a few seconds                        │  rotation code
         ▼                                           ▼
┌─────────────────┐                           ┌──────────────┐
│  SpellDebugger  │     export report         │   AI reads   │
│  records every  │ ──────────────────────▶  │   the report  │
│  decision       │     (Lua table)           │   and fixes  │
└─────────────────┘                           └──────────────┘
         ▲                                           │
         │              updated code                 │
         └───────────────────────────────────────────┘
```

1. **Describe** what you want: *"Affliction warlock, keep DoTs up, Life Tap when low mana, Shadow Bolt on Nightfall procs, Drain Life as filler"*
2. The AI **generates** the callback-based rotation
3. **Test** in-game for a few seconds against a training dummy
4. **Export** the SpellDebugger report (press the export button in the debug UI)
5. **Send the report** back to the AI — it sees every tick, every condition check, every cast
6. The AI **diagnoses** issues and produces a fix
7. **Repeat** until the rotation is clean

## Full Source Code

```lua
-- TBC Warlock Sequence Test
-- Affliction Rotation (IZI SDK)
-- SpellDebugger-integrated: callback-based priority loop + reactive Nightfall / Life Tap
-- Press END key in-game to toggle the SpellDebugger UI
local izi = require("common/izi_sdk")
local key_helper = require("common/utility/key_helper")
local control_panel_helper = require("common/utility/control_panel_helper")

-- FBR/SpellDebugger integration (optional - rotation works without it)
---@diagnostic disable-next-line: undefined-field
local FBR = _G.NODE_LIBRARY_INSTANCE
local PREFIX = "tbc_warlock_aff"
local function uid(k) return PREFIX .. "_" .. k end

-- Toggle: false = use cast() instead of cast_safe() for debugging
local use_safe_cast = true
local function try_cast(spell, target, label)
    if use_safe_cast then
        return spell:cast_safe(target, label)
    else
        return spell:cast(target, label)
    end
end

--------------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------------
local m = core.menu
local menu = {
    MAIN_TREE     = m.tree_node(),
    ROTATION_TREE = m.tree_node(),
    enabled  = m.checkbox(true, uid("enabled")),
    toggle   = m.keybind(999, false, uid("toggle")),
    shadow_bolt = m.checkbox(true, uid("shadowbolt")),
    life_tap    = m.checkbox(true, uid("lifetap")),
    corruption  = m.checkbox(true, uid("corruption")),
    agony       = m.checkbox(true, uid("agony")),
    siphon      = m.checkbox(true, uid("siphon")),
    ua          = m.checkbox(true, uid("ua")),
    immolate    = m.checkbox(true, uid("immolate")),
    drain       = m.checkbox(true, uid("drain")),
}

function menu:on()
    return self.enabled:get_state() and self.toggle:get_toggle_state()
end

core.register_on_render_menu_callback(function()
    menu.MAIN_TREE:render("TBC Warlock Sequence", function()
        core.menu.header():render("Affliction Rotation", izi.color.yellow(200))
        menu.enabled:render("Enabled", "Master toggle")
        if not menu.enabled:get_state() then return end
        menu.ROTATION_TREE:render("Spells", function()
            menu.toggle:render("Rotation Toggle",
                "Keybind to enable/disable rotation")
            menu.shadow_bolt:render("Shadow Bolt (Nightfall)")
            menu.life_tap:render("Life Tap")
            menu.corruption:render("Corruption")
            menu.agony:render("Curse of Agony")
            menu.siphon:render("Siphon Life")
            menu.ua:render("Unstable Affliction")
            menu.immolate:render("Immolate")
            menu.drain:render("Drain Life (filler)")
        end)
    end)
end)

core.register_on_render_control_panel_callback(function()
    local el = {}
    if not menu.enabled:get_state() then return el end
    control_panel_helper:insert_toggle(el, {
        name = string.format("[Warlock] Rotation (%s)",
            key_helper:get_key_name(menu.toggle:get_key_code())),
        keybind = menu.toggle
    })
    return el
end)

--------------------------------------------------------------------------------
-- Spells
--------------------------------------------------------------------------------
local SHADOW_TRANCE = 17941
local DEFS = {
    CORRUPTION = 172,
    AGONY      = 980,
    SIPHON     = 18265,
    UA         = 30108,
    IMMOLATE   = 348,
    BOLT       = 686,
    DRAIN      = 689,
    TAP        = 1454,
}

local spells    ={}
local spell_ids ={}
local all_ranks ={}
for k, id in pairs(DEFS) do
    spells[k]    = izi.spell(id)
    spell_ids[k] = id
    all_ranks[k] = { id }
end

-- SPELLS table for SpellDebugger (maps callback names to spell objects)
local SPELLS = {
    LIFE_TAP    = spells.TAP,
    SHADOW_BOLT = spells.BOLT,
    CORRUPTION  = spells.CORRUPTION,
    AGONY       = spells.AGONY,
    SIPHON      = spells.SIPHON,
    UA          = spells.UA,
    IMMOLATE    = spells.IMMOLATE,
    DRAIN_LIFE  = spells.DRAIN,
    DRAIN       = spells.DRAIN,
}

--------------------------------------------------------------------------------
-- Spellbook scanner
--------------------------------------------------------------------------------
local resolved   ={}
local name_cache ={}
local last_scan  = -999

local function spell_name(id)
    if name_cache[id] then return name_cache[id] end
    local s = izi.spell(id)
    if not s then return nil end
    local n = s:name()
    if n and n ~ = "" then name_cache[id] = n; return n end
    return nil
end

local function scan()
    local now = core.time()
    if now - last_scan < 2 then return end
    last_scan = now
    for k, id in pairs(DEFS) do
        if not resolved[k] then
            local n = spell_name(id)
            if n then resolved[k] = n end
        end
    end
    local known = core.spell_book.get_spells()
    if not known then return end
    local ids ={}
    for k, v in pairs(known) do
        if type(k) == "number" then ids[k] = true end
        if type(v) == "number" then ids[v] = true end
    end
    local best, ranks ={},{}
    for sid in pairs(ids) do
        local n = spell_name(sid)
        if n then
            for def_k in pairs(DEFS) do
                if resolved[def_k] and n == resolved[def_k] then
                    ranks[def_k] = ranks[def_k] or{}
                    table.insert(ranks[def_k], sid)
                    if not best[def_k] or sid > best[def_k] then
                        best[def_k] = sid
                    end
                end
            end
        end
    end
    for k, id in pairs(best) do
        if spell_ids[k] ~ = id then
            spell_ids[k] = id
            spells[k] = izi.spell(id)
        end
        if ranks[k] then all_ranks[k] = ranks[k] end
    end
    -- Refresh SPELLS so callbacks and SpellDebugger use current spell ranks
    SPELLS.LIFE_TAP    = spells.TAP
    SPELLS.SHADOW_BOLT = spells.BOLT
    SPELLS.CORRUPTION  = spells.CORRUPTION
    SPELLS.AGONY       = spells.AGONY
    SPELLS.SIPHON      = spells.SIPHON
    SPELLS.UA          = spells.UA
    SPELLS.IMMOLATE    = spells.IMMOLATE
    SPELLS.DRAIN_LIFE  = spells.DRAIN
    SPELLS.DRAIN       = spells.DRAIN
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function debuff_missing(target, key)
    local r = all_ranks[key]
    if not r or #r == 0 then return true end
    return not target:debuff_up(r)
end

--------------------------------------------------------------------------------
-- SPELL CALLBACKS (SpellDebugger-integrated)
-- Each callback returns true if it cast, false otherwise.
-- Callbacks are tried in priority order each frame.
--------------------------------------------------------------------------------
local spellCallbacks ={}

spellCallbacks.lifeTap = function()
    local me = izi.me()
    if not me then return false end
    if not menu.life_tap:get_state() then return false end
    if not SPELLS.LIFE_TAP
        or not SPELLS.LIFE_TAP:is_learned()
        or not SPELLS.LIFE_TAP:cooldown_up() then
        return false
    end
    local cond = (me:mana_pct() < 25 and me:get_health_percentage() > 75)
              or (me:mana_pct() < 50 and me:get_health_percentage() > 99)
    if not cond then return false end
    return try_cast(SPELLS.LIFE_TAP, me, "Life Tap")
end

spellCallbacks.shadowBolt = function(condition)
    local me = izi.me()
    local target = me and me:get_target()
    if not me or not target
        or not target:is_valid()
        or not target:is_valid_enemy() then
        return false
    end
    if not menu.shadow_bolt:get_state() then return false end
    if not SPELLS.SHADOW_BOLT
        or not SPELLS.SHADOW_BOLT:is_learned() then
        return false
    end
    if condition == "nightfall" or me:buff_up(SHADOW_TRANCE) then
        return try_cast(SPELLS.SHADOW_BOLT, target,
            "Shadow Bolt (Nightfall)")
    end
    return false
end

spellCallbacks.corruption = function()
    local me = izi.me()
    local target = me and me:get_target()
    if not me or not target
        or not target:is_valid()
        or not target:is_valid_enemy() then
        return false
    end
    if not menu.corruption:get_state() then return false end
    if not SPELLS.CORRUPTION
        or not SPELLS.CORRUPTION:is_learned()
        or not SPELLS.CORRUPTION:cooldown_up() then
        return false
    end
    if not debuff_missing(target, "CORRUPTION") then return false end
    return try_cast(SPELLS.CORRUPTION, target, "Corruption")
end

spellCallbacks.agony = function()
    local me = izi.me()
    local target = me and me:get_target()
    if not me or not target
        or not target:is_valid()
        or not target:is_valid_enemy() then
        return false
    end
    if not menu.agony:get_state() then return false end
    if not SPELLS.AGONY
        or not SPELLS.AGONY:is_learned()
        or not SPELLS.AGONY:cooldown_up() then
        return false
    end
    if not debuff_missing(target, "AGONY") then return false end
    return try_cast(SPELLS.AGONY, target, "Curse of Agony")
end

spellCallbacks.siphon = function()
    local me = izi.me()
    local target = me and me:get_target()
    if not me or not target
        or not target:is_valid()
        or not target:is_valid_enemy() then
        return false
    end
    if not menu.siphon:get_state() then return false end
    if not SPELLS.SIPHON
        or not SPELLS.SIPHON:is_learned()
        or not SPELLS.SIPHON:cooldown_up() then
        return false
    end
    if not debuff_missing(target, "SIPHON") then return false end
    return try_cast(SPELLS.SIPHON, target, "Siphon Life")
end

spellCallbacks.ua = function()
    local me = izi.me()
    local target = me and me:get_target()
    if not me or not target
        or not target:is_valid()
        or not target:is_valid_enemy() then
        return false
    end
    if not menu.ua:get_state() then return false end
    if not SPELLS.UA
        or not SPELLS.UA:is_learned()
        or not SPELLS.UA:cooldown_up() then
        return false
    end
    if not debuff_missing(target, "UA") then return false end
    return try_cast(SPELLS.UA, target, "Unstable Affliction")
end

spellCallbacks.immolate = function()
    local me = izi.me()
    local target = me and me:get_target()
    if not me or not target
        or not target:is_valid()
        or not target:is_valid_enemy() then
        return false
    end
    if not menu.immolate:get_state() then return false end
    if not SPELLS.IMMOLATE
        or not SPELLS.IMMOLATE:is_learned()
        or not SPELLS.IMMOLATE:cooldown_up() then
        return false
    end
    if not debuff_missing(target, "IMMOLATE") then return false end
    return try_cast(SPELLS.IMMOLATE, target, "Immolate")
end

spellCallbacks.drain = function()
    local me = izi.me()
    local target = me and me:get_target()
    if not me or not target
        or not target:is_valid()
        or not target:is_valid_enemy() then
        return false
    end
    if not menu.drain:get_state() then return false end
    if not SPELLS.DRAIN_LIFE
        or not SPELLS.DRAIN_LIFE:is_learned()
        or not SPELLS.DRAIN_LIFE:cooldown_up() then
        return false
    end
    return try_cast(SPELLS.DRAIN_LIFE, target, "Drain Life (filler)")
end

-- ONE LINE to enable the SpellDebugger
if FBR and FBR.SpellDebugger then
    FBR.SpellDebugger.register_callbacks(spellCallbacks, SPELLS)
end

--------------------------------------------------------------------------------
-- Action list (priority order)
--------------------------------------------------------------------------------
local actionList ={}
actionList.core = function()
    if spellCallbacks.lifeTap()    then return true end
    if spellCallbacks.corruption() then return true end
    if spellCallbacks.agony()      then return true end
    if spellCallbacks.siphon()     then return true end
    if spellCallbacks.ua()         then return true end
    if spellCallbacks.immolate()   then return true end
    if spellCallbacks.drain()      then return true end
    return false
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------
core.register_on_update_callback(function()
    scan()
    if not menu:on() then return end
    local me = izi.me()
    if not me or not me:is_alive() then return end
    local target = me:get_target()
    if not target or not target:is_valid() then return end
    if not target:is_valid_enemy() then return end
    if not me:can_attack(target) then return end

    local SD = FBR and FBR.SpellDebugger
    -- Nightfall: force cast Shadow Bolt (highest priority)
    if menu.shadow_bolt:get_state() and me:buff_up(SHADOW_TRANCE) then
        if SD then SD.set_action_list("nightfall") end
        spellCallbacks.shadowBolt("nightfall")
        return
    end
    -- Core rotation (Life Tap, DoTs, Drain filler)
    if SD then SD.set_action_list("core") end
    actionList.core()
end)

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------
core.register_on_render_callback(function()
    if not menu.enabled:get_state() then return end
    if FBR and FBR.SpellDebugger then
        local txt = "[TBC Warlock Aff] SpellDebugger: Press END to toggle"
        core.graphics.text_2d(
            txt, izi.vec2(20, 50), 16, izi.color.yellow(200), false
        )
    end
end)
```

## Code Walkthrough

### The Callback Pattern

The core idea that makes everything work — both the rotation and the SpellDebugger — is structuring every spell as a **named callback** in a table:

```lua
local spellCallbacks ={}
spellCallbacks.lifeTap = function()
    -- check conditions
    -- return true if cast succeeded, false otherwise
end
spellCallbacks.corruption = function()
    -- ...
end
```

Each callback follows the same contract: check all conditions, attempt the cast if everything passes, return `true` if the spell was cast and `false` otherwise. The name of the function (`lifeTap`, `corruption`, etc.) becomes the label in the debug UI and the exported report.

The action list then tries them in priority order:

```lua
actionList.core = function()
    if spellCallbacks.lifeTap()    then return true end
    if spellCallbacks.corruption() then return true end
    if spellCallbacks.agony()      then return true end
    if spellCallbacks.siphon()     then return true end
    if spellCallbacks.ua()         then return true end
    if spellCallbacks.immolate()   then return true end
    if spellCallbacks.drain()      then return true end
    return false
end
```

The first callback to return `true` wins, and the rest are skipped for that tick.

### SpellDebugger Integration

The entire integration is **one line**:

```lua
if FBR and FBR.SpellDebugger then
    FBR.SpellDebugger.register_callbacks(spellCallbacks, SPELLS)
end
```

You pass your callbacks table and your spells table, and the SpellDebugger hooks into every callback to record what happened.

### Reading the Export

When you export a debug session, you get a structured Lua table. Key sections:

**`tick_snapshots`** — What happened each tick:

```lua
tick_snapshots = {
    {
        time = 0.48,
        winner = "corruption",
        invocations = {
            { spell_id = 1454, result = false, name = "lifeTap" },
            { spell_id = 172,  result = true,  name = "corruption" },
        }
    },
}
```

**`cast_events`** — What actually happened in the game (shows highest-rank spell IDs).

**`failed_casts`** — Why a spell didn't fire, with pass/fail status for every condition.

**`skipped_available`** — Spells that could have cast but lost priority.

### Spellbook Scanner (Auto-Ranking)

TBC has multiple ranks of each spell. The scanner automatically finds the highest rank:

```lua
local function scan()
    local now = core.time()
    if now - last_scan < 2 then return end
    last_scan = now
    -- Resolve base spell names from DEFS
    for k, id in pairs(DEFS) do
        if not resolved[k] then
            local n = spell_name(id)
            if n then resolved[k] = n end
        end
    end
    -- Scan spellbook for all known spells, find highest rank by name match
    local known = core.spell_book.get_spells()
    -- ...
    for k, id in pairs(best) do
        if spell_ids[k] ~ = id then
            spell_ids[k] = id
            spells[k] = izi.spell(id)
        end
    end
end
```

### Reactive Proc Handling

Nightfall (Shadow Trance) is handled as a high-priority interrupt that bypasses the normal action list:

```lua
if menu.shadow_bolt:get_state() and me:buff_up(SHADOW_TRANCE) then
    if SD then SD.set_action_list("nightfall") end
    spellCallbacks.shadowBolt("nightfall")
    return
end
```

### `cast` vs `cast_safe`

```lua
local use_safe_cast = true
local function try_cast(spell, target, label)
    if use_safe_cast then
        return spell:cast_safe(target, label)
    else
        return spell:cast(target, label)
    end
end
```

`cast_safe` includes additional checks (GCD, casting state, facing, range) before attempting the cast — this is what generates the detailed `conditions` list in the SpellDebugger export. `cast` skips these and sends the cast command directly.

## Rotation Priority

| Priority | Spell | Condition |
|----------|-------|-----------|
| **0** (reactive) | Shadow Bolt | Nightfall (Shadow Trance) proc active |
| **1** | Life Tap | Mana < 25% and HP > 75%, or Mana < 50% and HP > 99% |
| **2** | Corruption | Missing from target |
| **3** | Curse of Agony | Missing from target |
| **4** | Siphon Life | Missing from target |
| **5** | Unstable Affliction | Missing from target |
| **6** | Immolate | Missing from target |
| **7** | Drain Life | Filler (always available) |

## Key Patterns to Reuse

| Pattern | Where in Code | Reuse For |
|---------|---------------|-----------|
| Callback-based rotation | `spellCallbacks` table | Any class rotation — structure spells as named functions |
| SpellDebugger integration | `register_callbacks` one-liner | Debugging any callback-based rotation |
| Action list tags | `SD.set_action_list("core")` | Labeling different priority groups in the debugger |
| Auto rank detection | `scan()` spellbook scanner | TBC/Classic rotations where spells have multiple ranks |
| Multi-rank debuff check | `debuff_missing` with `all_ranks` | Checking if any rank of a DoT is active |
| Reactive proc bypass | Nightfall check before action list | Art of War, Clearcasting, Missile Barrage, etc. |
| `cast` vs `cast_safe` toggle | `try_cast` wrapper | Switching between debug and production casting |
| Control panel integration | `register_on_render_control_panel_callback` | Adding keybind toggles to the floating panel |

## Requirements

- **[FBR - The Node](https://project-sylvanas.net/panel/plugins/detail/401)** by Nova — provides the SpellDebugger. The rotation runs without it, but you lose the debug UI and export capability.
