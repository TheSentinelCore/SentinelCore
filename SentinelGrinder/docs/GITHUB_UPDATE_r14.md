# GrindBuddy Update (r14)

This update introduces profile-driven patrol routes while keeping full backward compatibility with the legacy circle patrol.

## What was improved

- Added route profile manager:
  - Reads profile index from `scripts_data/grindbuddy/profiles/index.json`.
  - Reads profile route files from `scripts_data/grindbuddy/profiles/*.json`.
  - Supports map filtering (`map_id`) and level range filtering (`min_level`/`max_level`).
- Added patrol route modes:
  - `Circle (Legacy)` (existing behavior).
  - `Profile Route` (new profile-based behavior).
- Added route profile selection controls in UI:
  - `Route Mode`
  - `Auto Route Profile`
  - `Route Profile` (manual when auto is disabled)
- Added profile patrol behavior upgrades:
  - closest-waypoint resume on start,
  - loop or there-and-back route traversal,
  - automatic fallback to legacy circle when no valid profile is available.
- Added first-run profile bootstrap:
  - auto-generates `index.json` and `example_auto.json` if missing.

## Result

GrindBuddy can now patrol explicit route profiles by map/level while still safely falling back to the original circle patrol if profiles are not configured.
