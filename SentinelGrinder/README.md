# GrindBuddy

Lightweight grinding module scaffold for SentinelCore.

## Author

- Laidbak

## Current Version

- Defined in `SentinelGrinder/version.lua`.
- Format: `major.minor.patch-rrevision`

## Controls

- Sylvanas menu button: `GrindBuddy: Start` / `GrindBuddy: Stop`
- Sylvanas menu button: `GrindBuddy UI` to open Astro settings window.
- `Grind` tab now includes live sliders:
- `Scan Radius`, `Pull Range`, `Chase Stop`
- `Min/Max Level Delta` (default max set to `+2`)
- `Ignore Player Targets` enabled by default.
- `Route Mode`: `Circle (Legacy)` or `Profile Route`.
- `Auto Route Profile` + `Route Profile` selector (map/level-aware profile auto-pick).
- Patrol now expands automatically when no enemies are found (search radius growth over time).
- UI init/load was hardened so it can open without requiring a manual `F6` reload.

## Route Profiles

- Route profiles are stored in `scripts_data/grindbuddy/profiles/`.
- Index file: `scripts_data/grindbuddy/profiles/index.json`.
- On first load, GrindBuddy seeds Honorbuddy-based Classic/TBC routes converted from the provided profile pack:
- `hb_classic_horde_durotar_5_12.json`
- `hb_classic_alliance_ek_5_12.json`
- `hb_classic_horde_kalimdor_40_45.json`
- `hb_classic_ungoro_48_55.json`
- `hb_classic_silithus_55_60.json`
- `hb_tbc_sporeggar_60_63.json`
- `hb_tbc_kurenai_64_66.json`
- `hb_tbc_netherwing_67_70.json`
- If the Honorbuddy seed catalog is unavailable, GrindBuddy falls back to generated circle test routes.
- Existing `index.json` entries are preserved; missing seeded entries are appended automatically.
- Profile route supports:
- map filter (`map_id`),
- level range (`min_level`, `max_level`),
- route style (`there_and_back` or loop),
- closest-waypoint resume on start.
- If no valid route profile is available, GrindBuddy falls back to the legacy circle patrol.

Example `index.json` entry:

```json
{
  "profiles": [
    {
      "id": "example_auto",
      "label": "Example Auto Route",
      "file": "grindbuddy/profiles/example_auto.json",
      "enabled": true,
      "min_level": 1,
      "max_level": 80,
      "map_id": 0,
      "there_and_back": false
    }
  ]
}
```

Example route profile file:

```json
{
  "name": "Example Auto Route",
  "map_id": 0,
  "min_level": 1,
  "max_level": 80,
  "there_and_back": false,
  "points": [
    { "x": 1234.0, "y": 567.0, "z": 45.0 },
    { "x": 1240.0, "y": 590.0, "z": 45.0 }
  ]
}
```

## Basic Rotation (TBC/Sylvanas)

- Imported from MaxDps `Specialization/TBC` mini-rotations.
- Includes 25 selectable TBC profiles across classes/specs (from the provided MaxDps packs).
- In Astro UI, users can:
- Enable auto profile selection by class.
- Or manually choose the exact profile to run.
- Warlock profiles include extra self-buff handling:
- `Demon Armor (11735)`, `Detect Invisibility (132)`, `Soul Link (19028)`.

## Blackspot Learning

- Persistent blackspots are saved in `scripts_data/grindbuddy/blackspots.csv`.
- On repeated movement timeout, GrindBuddy adds a blackspot automatically at the stuck location.
- Patrol waypoints and candidate targets inside blackspots are skipped on the same map.

## Movement Recovery (Unstuck v2)

- Move requests now use tokens so stale nav callbacks are ignored.
- Stuck detection now checks both hard timeout and no-progress stall windows.
- Recovery attempts run staged movement actions (jump, strafe, backward, turn) when low-level input is available.
- Each recovery step retries the same move target automatically.
- Route/profile changes, mount/dismount flow, and stop now use one cancel path for inflight moves.

## Versioning Workflow

Use the helper script for every code change:

```powershell
powershell -ExecutionPolicy Bypass -File .\SentinelGrinder\tools\bump_version.ps1 -Level revision -Message "Describe the change"
```

Levels: `revision`, `patch`, `minor`, `major`.
