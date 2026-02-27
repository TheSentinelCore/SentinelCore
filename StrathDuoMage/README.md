# StrathDuoMage

Standalone plugin rewrite targeted only at duo-mage Stratholme farming.

## Scope
- Independent runtime (no `SentinelCore` imports)
- Leader/follower duo coordination via shared sync file
- Mage frost combat baseline with AoE-first behavior
- Route-driven farm loop focused on multi-pack pull -> gather -> AoE -> loot -> vendor
- SentinelUI-backed control panel (Dashboard + Recorder tabs)

## Status
This is a clean-room foundation. It runs as a separate plugin and now supports:
- Multi-point pull segments
- Route-aware target focus
- Dynamic blizzard anchors (cluster centroid or lane midpoint)
- Built-in route recorder with undo/autosave/segment controls

Profile files:
- `profiles/strath_duo_default.json`: safe baseline (route segments intentionally empty)
- `profiles/strath_duo_anniversary_template.json`: editable multi-pack template
- Runtime helper: `_G.StrathDuoMage.capture_point("label")` prints JSON-ready coordinates in logs.

UI:
- `lib/SentinelUI.lua` is copied from SentinelCore `AstroUI.lua` and used as the plugin UI framework.

Recorder design notes:
- `docs/RECORD_MODE.md`

## Entry Points
- `StrathDuoMage/header.lua`
- `StrathDuoMage/init.lua`
- `StrathDuoMage/main.lua`

## Next Work
- Flesh out route execution for exact Strath pull lanes
- Tighten spell timing for pack-size breakpoints
- Add full anti-stuck and corpse-walk recovery
- Add robust gold accounting from loot/sell/repair deltas
