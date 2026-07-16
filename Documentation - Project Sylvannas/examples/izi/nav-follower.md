---
title: "Nav Follower"
source: "https://docs.project-sylvanas.net/dev/examples/nav-follower"
crawled: "2026-07-14"
---

# Nav Follower

## Overview

Nav Follower is an open-source quality-of-life plugin that automatically walks your character to — and keeps following — another player using [Nasrine's NavLib](https://project-sylvanas.net/panel/plugins/detail/414) pathfinding. Think of it as a smarter `/follow` command: no distance limit, no getting stuck on geometry, and it keeps re-pathing as the target moves.

Pick from three follow modes in the menu, press Start, and go make a coffee while your character catches up to your friends.

**Key Features:**
- **Three Follow Modes** — follow your current target, your focus frame, or any player by name
- **Adaptive Re-pathing** — refreshes the path faster when close, slower when far away
- **Pause & Resume** — temporarily stop moving without losing your follow target
- **No Distance Limit** — unlike `/follow`, works across entire zones
- **No Stuck Issues** — navmesh pathing navigates around obstacles and terrain
- **Clean HUD** — on-screen banner showing who you're following and how far away they are

Beyond the follow functionality, this plugin is a good reference for:
- **Object Manager Scanning** — finding players by name with a scan cooldown
- **Adaptive Tick Rates** — adjusting update frequency based on distance
- **Menu System** — comboboxes, text inputs, and dynamic button labels
- **Continuous Pathing** — re-issuing `move_to` on a loop without stop/start jitter

## How It Works

```
┌──────┐   menu Start   ┌──────────┐   target found   ┌─────────────┐
│ IDLE │ ────────────▶ │ SEARCHING │ ──────────────▶ │  FOLLOWING  │
└──────┘                └──────────┘                  └─────────────┘
   ▲                         ▲                               │
   │   menu Stop / MMB       │    target lost / died         │
   │◀─────────────────────── ◀──────────────────────────────┘
                             │                               │
                             │          menu Pause           │
                             │                        ┌──────▼──────┐
                             └────────────────────────│   PAUSED    │
                                    menu Resume       └─────────────┘
```

1. **Idle** — choose a follow mode and target in the menu. Press Start.
2. **Searching** — the plugin resolves who to follow based on your chosen mode. For custom names, it scans the object manager every 2 seconds.
3. **Following** — once the target is found, the navmesh path is computed and your character walks. The path refreshes continuously as the target moves. When you get within 3 yards, movement pauses until the target moves away again.
4. **Paused** — you can pause at any time. Your follow target is remembered so you can resume instantly.

## Follow Modes

| Mode | How It Works | Best For |
|------|-------------|----------|
| **Target** | Follows whoever you have selected (`get_target()`) | Quick follow — click someone, press Start |
| **Focus** | Follows your focus frame (`get_focus()`) | Persistent follow — focus doesn't change when you click around |
| **Custom Name** | Scans the object manager for an exact name match | Following a specific friend, even if you can't target them |

## Target Resolution with Scan Cooldown

```lua
local function resolve_target()
    local mode = menu.mode:get()
    local now = core.time()
    if mode == MODE_TARGET then
        local p = me()
        return p and p:get_target()
    elseif mode == MODE_FOCUS then
        return core.input.get_focus()
    elseif mode == MODE_NAME then
        -- Reuse cached result for 2 seconds
        if cached_name_obj
            and cached_name_obj:is_valid()
            and not cached_name_obj:is_dead() then
            if now - last_scan_t < 2.0 then
                return cached_name_obj
            end
        end
        last_scan_t = now
        local wanted = menu.name_input:get_text()
        if not wanted or wanted == "" then return nil end
        local actors = core.object_manager.get_all_objects()
        for _, obj in ipairs(actors) do
            if obj:get_name() == wanted and not obj:is_dead() then
                cached_name_obj = obj
                return obj
            end
        end
        cached_name_obj = nil
        return nil
    end
    return nil
end
```

The Custom Name mode scans the entire object manager. The **scan cooldown pattern** (reuse cached result for 2 seconds) dramatically reduces CPU overhead.

## Adaptive Re-pathing

```lua
local d = dist_to(target)
local now = core.time()

-- Adaptive interval: close = fast refresh, far = slow refresh
local interval = d < 30 and 0.2 or 1.0

-- Close enough, stop moving
if d < 3.0 then
    n:stop()
    last_path_t = now
    return
end

if now - last_path_t < interval then return end
last_path_t = now

local target_pos = target:get_position()
n:move_to(target_pos, function(ok, reason)
    if not ok then
        core.log_warning("[NavFollow] Path failed: " .. tostring(reason))
    end
end)
```

**Distance-based refresh rate:**

| Distance | Refresh Interval | Why |
|----------|-----------------|-----|
| < 30 yards | 200ms | Close to target — need to track small movements accurately |
| ≥ 30 yards | 1000ms | Far away — target position changes are relatively small, save CPU |

**Dead zone at 3 yards:** When you're within 3 yards, `n:stop()` prevents jittery "orbiting". Pathing resumes naturally when the target walks away.

## Pause & Resume

```lua
local function pause_follow()
    if not active then return end
    paused = not paused
    if paused then
        local n = get_nav()
        if n then n:stop() end
    end
    core.log("[NavFollow] " .. (paused and "Paused" or "Resumed"))
end
```

The pause button label dynamically changes between "Pause" and "Resume":

```lua
if menu.btn_pause:render(paused and "Resume" or "Pause") then
    pause_follow()
end
```

## Menu System

```lua
menu.tree:render("Nav Follower", function()
    menu.mode:render("Follow Mode", { "Target", "Focus", "Custom Name" })
    if menu.mode:get() == MODE_NAME then
        menu.name_input:render("Player Name")
    end
    if not active then
        if menu.btn_start:render("Start") then start_follow() end
    else
        if menu.btn_stop:render("Stop") then stop_follow() end
        if menu.btn_pause:render(paused and "Resume" or "Pause") then
            pause_follow()
        end
    end
end)
```

Demonstrates:
- **Combobox** — dropdown for selecting follow mode
- **Conditional rendering** — text input only appears when Custom Name mode is selected
- **Dynamic buttons** — Start when idle, Stop/Pause when active
- **Color-coded status** — blue for following, yellow for paused, grey for idle

## Controls

| Input | Context | Action |
|-------|---------|--------|
| Menu → Start | Idle | Begin following |
| Menu → Stop | Active | Stop following |
| Menu → Pause/Resume | Active | Toggle pause |
| Middle Mouse Button | Active | Stop following |

## Comparison with `/follow`

| Feature | `/follow` | Nav Follower |
|---------|----------|--------------|
| Distance limit | ~30 yards, breaks beyond that | Unlimited — works across entire zones |
| Obstacle handling | Walks into walls, gets stuck | Navmesh pathing around geometry |
| Target lost | Stops permanently | Keeps searching, auto-resumes |
| Pause/Resume | Not supported | Built-in toggle |
| Follow by name | Not supported | Type any player name |
| Follow focus | Not supported | Dedicated focus mode |
| Works while AFK | Breaks easily | Robust continuous re-pathing |

## Key Patterns to Reuse

| Pattern | Where in Code | Reuse For |
|---------|---------------|-----------|
| Object Manager scan with cooldown | `resolve_target()` NAME mode | Finding any entity by name/NPC ID efficiently |
| Adaptive tick rate | `interval = d < 30 and 0.2 or 1.0` | Any distance-dependent update frequency |
| Continuous re-pathing | `move_to` in update loop, ignore callback | Following moving targets, escort logic |
| Dead zone | `if d < 3.0 then n:stop()` | Preventing jitter when at destination |
| Conditional menu controls | `if mode == MODE_NAME then` show input | Context-sensitive UI that hides irrelevant options |
| Toggle button label | `paused and "Resume" or "Pause"` | Any on/off toggle in menu system |
| Lazy module init | `get_nav()` with cached instance | Optional dependencies that may not be loaded |

## Requirements

- **[Nasrine's NavLib](https://project-sylvanas.net/panel/plugins/detail/414)** — The navmesh pathfinding library must be loaded (`_G.NavLib` must exist)
