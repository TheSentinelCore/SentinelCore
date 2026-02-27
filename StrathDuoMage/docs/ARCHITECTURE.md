# Architecture

## Core
- `core/Config.lua`: default plugin config and profile loader
- `core/Blackboard.lua`: shared runtime state
- `core/EventBus.lua`: local pub/sub
- `core/Logger.lua`: prefixed logging
- `core/StateMachine.lua`: idle/running/paused/failed transitions
- `core/Bot.lua`: orchestrates service update pipeline
- `ui/window.lua`: SentinelUI window + tab registration
- `ui/tabs/dashboard_tab.lua`: runtime controls and metrics
- `ui/tabs/recorder_tab.lua`: route recorder workflow controls

## Services
- `services/SensorService.lua`: player/target sampling
- `services/DuoSyncService.lua`: leader/follower heartbeat sync via file
- `services/RouteService.lua`: multi-pack pull route state + dynamic blizzard anchors
- `services/RecordService.lua`: profile recording/editing with undo and autosave
- `services/TargetService.lua`: hostile scan and target selection
- `services/MovementService.lua`: navigation wrappers
- `services/CombatService.lua`: frost combat decisions
- `services/LootService.lua`: corpse looting attempts
- `services/VendorService.lua`: vendor trigger placeholder
- `services/TelemetryService.lua`: session metrics and GPH estimate
- `services/FarmService.lua`: high-level farm phase controller

## Route Profile Model
- `route.segments[]`: ordered pull segments in one dungeon loop
- `segment.pull_points[]`: sequence of points used to gather multiple packs before AoE
- `segment.gather_anchor`: fallback blizzard anchor when no live cluster exists
- `segment.blizzard.strategy`:
  - `cluster_centroid`: cast on live hostile centroid (default)
  - `lane_midpoint`: cast at configured lane midpoint
- `segment.blizzard.lane_start/lane_end`: optional lane clamp for consistent kiting corridor

## Runtime Data Flow
- `RouteService` publishes:
  - `route.pull_point`
  - `route.target_focus_position`
  - `route.target_focus_radius`
  - `route.collecting` / `route.collect_complete`
  - `combat.blizzard_anchor`
- `TargetService` uses route focus to avoid grabbing wrong packs.
- `FarmService` drives pull-point progression and segment advancement.
- `CombatService` uses dynamic `combat.blizzard_anchor` instead of fixed coordinates.

## Record Mode
- Start from default/template profile path.
- Capture operations:
  - `pull_point`
  - `gather_anchor`
  - `blizzard.lane_start`
  - `blizzard.lane_end`
- Editing operations:
  - `next/new segment`, `prev segment`
  - `toggle blizzard strategy`
  - `undo last action`
  - `clear pull points`
- Persistence:
  - autosave while active
  - explicit save
  - stop with save or discard
