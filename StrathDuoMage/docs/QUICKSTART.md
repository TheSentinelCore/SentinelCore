# Quick Start

## Start the plugin
Use the menu button `Strath Duo Mage` and press `Start/Stop`.

## Open Sentinel UI
Use `Open/Close UI` in the plugin menu. UI is backed by `lib/SentinelUI.lua`.

## Switch role
Use `Switch Leader/Follower` from the menu.
In UI this is `Switch Role`; it toggles `leader` vs `follower` in duo sync metadata.

## Optional profile load
From script console:

```lua
local bot = _G.StrathDuoMage and _G.StrathDuoMage.create and _G.StrathDuoMage.create()
if bot then
    bot:load_profile("StrathDuoMage/profiles/strath_duo_default.json")
end
```

## Duo sync
Both clients share `StrathDuoMage/state/duo_sync.v1.json`.

## Route calibration (TBC Anniversary)
`profiles/strath_duo_default.json` now supports multi-pack pulls through `route.segments`.
`profiles/strath_duo_anniversary_template.json` contains an editable segment template. Treat those coordinates as placeholders and replace all of them.

Recorder workflow (UI -> `Recorder` tab):
1. `Start Template` or `Start Default`.
2. Move through pull path and click `Pull Point` at each route anchor.
3. Capture `Gather`, `Lane Start`, and `Lane End`.
4. Use `Next/New Seg` for next pack train.
5. `Stop+Save` (or `Save`) to persist profile.

Tip: hover any button in Dashboard/Recorder for tooltip details (what it does and why).

Coordinate capture workflow:
1. Walk each pull location in dungeon order.
2. At each spot, run:

```lua
_G.StrathDuoMage.capture_point("segment_01_pull_01")
```

3. Paste those into `segment.pull_points`.
4. Add one `gather_anchor` and optional `blizzard.lane_start/lane_end` for each segment.
5. Tune `min_enemy_count_for_aoe` and `collect_timeout_secs` for Anniversary mob behavior/hotfixes.

## Notes
- This rewrite is fully separate from SentinelCore modules.
- Navigation integration expects `SentinelNavClient` to be loaded.
