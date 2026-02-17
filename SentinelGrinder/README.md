# GrindBuddy

Lightweight grinding module scaffold for SentinelCore.

## Author

- Laidbak

## Current Version

- Defined in `GrindBuddy/version.lua`.
- Format: `major.minor.patch-rrevision`

## Controls

- Sylvanas menu button: `GrindBuddy: Start` / `GrindBuddy: Stop`
- Sylvanas menu button: `GrindBuddy UI` to open Astro settings window.
- `Grind` tab now includes live sliders:
- `Scan Radius`, `Pull Range`, `Chase Stop`
- `Min/Max Level Delta` (default max set to `+2`)
- `Ignore Player Targets` enabled by default.
- Patrol now expands automatically when no enemies are found (search radius growth over time).
- UI init/load was hardened so it can open without requiring a manual `F6` reload.

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

## Versioning Workflow

Use the helper script for every code change:

```powershell
powershell -ExecutionPolicy Bypass -File .\GrindBuddy\tools\bump_version.ps1 -Level revision -Message "Describe the change"
```

Levels: `revision`, `patch`, `minor`, `major`.
