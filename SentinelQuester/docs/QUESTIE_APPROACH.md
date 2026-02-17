# QuestingBuddy + Questie Approach

## Core flow
1. Load `common/utility/questie_tracker` through a guarded adapter (`pcall`).
2. On each scan tick:
   - If `questie:is_hooked()` is true, only keep objects where `questie:is_quest_object(obj)` is true.
   - If not hooked:
     - If `require_questie = true`, do nothing (safe mode).
     - If `require_questie = false`, use fallback heuristics (usable/lootable/hostile unit).
3. Score candidates (Questie match first, then distance/interaction hints).
4. Move to best candidate and interact.
5. If no progress for several seconds or target times out, blacklist it temporarily and pick another.

## Why this design
- Avoids blind behavior when Questie is unavailable.
- Keeps Questie as authoritative source when hooked.
- Prevents target lock loops with timeout + blacklist.
- Uses lightweight scan throttling to avoid heavy per-frame object processing.

## Runtime toggles (already wired)
- `qb_enabled`
- `qb_require_questie`
- `qb_fallback_hostiles`
- `qb_scan_radius`
- `qb_interact_range`
- `qb_objective_timeout`
- `qb_debug`

## Next upgrade steps
1. Add quest phase tracking (accept/turn-in/objective stage awareness).
2. Add navmesh movement backend (`NavLib`) for obstacle-safe routing.
3. Add quest profile support (zone order, quest chain constraints).
4. Add combat delegation module for kill objectives.
