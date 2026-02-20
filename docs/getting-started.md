---
title: Getting Started
layout: default
nav_order: 2
---

# Getting Started
{: .no_toc }

Everything you need to start using SentinelNavClient in your plugin.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of Contents</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## Requirements

| Requirement | Details |
|:------------|:--------|
| **Sylvannas** | With plugin loader support (`header.lua` + `main.lua` pattern) |
| **SentinelNavServer** | Rust HTTP server running with Recast/Detour navmesh tiles |
| **Navmesh data** | `.mmap` and `.mmtile` files in `SentinelNavServer/mmaps/` |

SentinelNavServer must be reachable at the configured URL (default: `http://78.31.71.163:47110`). The server preloads continent map data on startup and loads dungeon/instance tiles on demand.

---

## Installation

1. **Place the `SentinelNavClient/` folder** in your Sylvannas `scripts/` directory
2. **Start SentinelNavServer** (the Rust pathfinding server)
3. **Load Sylvannas** &mdash; SentinelNavClient registers as a plugin and initializes automatically

SentinelNavClient initializes **eagerly at module load time** (not deferred to `on_update`), so the shared Client exists before any consumer plugin's `on_update` callback fires.

---

## Verifying the Connection

After loading, you can verify the SentinelNavServer connection via the Client API or the built-in debug tab:

```lua
local client = _G.SentinelNavClient.client
if client then
    client:health_check(function(ok, data)
        if ok then
            core.log(string.format(
                "[SentinelNavClient] Server v%s — %d maps loaded — uptime %ds",
                data.version, #data.loaded_maps, data.uptime_secs
            ))
        else
            core.log_error("[SentinelNavClient] Server unreachable")
        end
    end)
end
```

Or open the SentinelNavClient Settings UI (via the Sylvannas menu) and use the **Debug** tab's "Health Check" test mode.

---

## Quick Start (Consumer Plugin)

The simplest way to use SentinelNavClient from another plugin &mdash; no config, no `update()` call, no settings management:

### 1. Check availability

```lua
-- In your plugin's initialize():
if not (_G.SentinelNavClient and _G.SentinelNavClient.client) then
    core.log_error("SentinelNavClient not loaded — navigation unavailable")
    return
end

local client = _G.SentinelNavClient.client
```

### 2. Move to a destination

```lua
local dest = { x = -8900, y = 560, z = 94 }

client:move_to(dest, function(ok, reason)
    if ok then
        core.log("Arrived at destination!")
    else
        core.log_error("Navigation failed: " .. tostring(reason))
    end
end)
```

### 3. Check movement state

```lua
if client:is_moving() then
    local progress = client:get_progress()
    core.log(string.format(
        "State: %s — Waypoint %d/%d — %.0f yards remaining",
        progress.state,
        progress.path_index,
        progress.path_count,
        progress.distance_remaining
    ))
end
```

### 4. Listen for events (optional)

```lua
client:on("arrived", function()
    core.log("Destination reached!")
end)

client:on("stuck", function()
    core.log("Stuck — auto-recovery in progress...")
end)

client:on("failed", function()
    core.log_error("Movement failed after max recovery attempts")
end)

client:on("state_change", function(data)
    core.log(string.format("[Nav] %s -> %s", data.from, data.to))
end)
```

### 5. Stop movement

```lua
client:stop()
```

---

## What You Do NOT Need To Do

| Action | Why |
|:-------|:----|
| Call `client:update()` | SentinelNavClient drives this from its own `on_update` callback every frame |
| Call `client:update_config()` | SentinelNavClient's built-in UI syncs all settings automatically every render frame |
| Pass config to `create()` | The UI owns all navigation settings; config parameters are accepted but ignored |
| Create your own Client | `Client:new()` creates an isolated instance disconnected from SentinelNavClient's update loop |
| Manage the Obstacle module | The Client wires Movement and Obstacle together automatically during construction |

---

## Settings UI

SentinelNavClient includes a built-in settings window with four tabs:

| Tab | Controls |
|:----|:---------|
| **Movement** | Waypoint tolerance, stuck recovery, dynamic speed scaling, anti-detection jitter |
| **Pathfinding** | Smoothing algorithm & params, terrain cost filters, wall clearance, indoor corridor mode |
| **Obstacles** | Avoidance radius/cost, zone TTL/cap, proactive & reactive probe settings |
| **Debug** | 13 test modes, avoidance zone management, waypoint tools, visualization toggles |

Toggle the settings window via the **"SentinelNavClient"** button in the Sylvannas menu. A **"Show Advanced"** toggle above the tab bar reveals advanced settings in each tab.

All settings are persisted across sessions via `core.menu.*` elements.

---

## Next Steps

- **[Architecture](/architecture)** &mdash; Understand the four-layer design, plugin lifecycle, and module wiring
- **[Client API](/api/client)** &mdash; Full reference for the recommended entry point
- **[Consumer Integration Guide](/guides/consumer-integration)** &mdash; Patterns for integrating from your plugin
- **[Configuration Reference](/configuration)** &mdash; All 40+ settings with defaults, ranges, and descriptions
