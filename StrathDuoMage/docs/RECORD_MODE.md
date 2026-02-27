# Record Mode

## Goals
- Build route profiles directly from live in-dungeon movement.
- Avoid hardcoded coordinates in code.
- Keep profile updates reversible and safe while recording.

## Implemented Features
- Session lifecycle:
  - start from default or template profile
  - stop with save or discard
- Capture operations:
  - pull points
  - gather anchor
  - lane start / lane end
- Segment operations:
  - previous segment
  - next segment (auto-creates new segment at end)
  - clear pull points
- Edit safety:
  - undo last operation
  - minimum spacing guard for pull points
  - autosave timer + explicit save
  - map consistency check (reject captures after zone/map drift)
- Metadata:
  - RFC3339 UTC timestamps on captures and save metadata
  - session/map identifiers in `record_meta`
- UI:
  - Recorder tab in SentinelUI for button-driven recording workflow

## Important Edge Cases
- Empty or missing profile file:
  - recorder creates a valid route skeleton with one default segment.
- Corrupt profile JSON:
  - load fails with explicit error status; no partial write.
- Capturing outside valid player state:
  - capture fails gracefully when player position is unavailable.
- Duplicate noisy points:
  - points below `record.min_point_spacing` are rejected.
- Wrong segment mistakes:
  - undo and clear operations are available before save.
- Wrong map/instance captures:
  - recorder locks map at session start and rejects captures if map changes.
- Save path changes:
  - parent folder creation attempted before write.

## Best-Practice Defaults
- Keep segments small and semantic (one pull train per segment).
- Use `cluster_centroid` strategy first, switch to `lane_midpoint` only for stable corridors.
- Capture 2-5 pull points per segment; too many points causes brittle routing.
- Set gather anchor only where both mages can safely alternate blink lanes.
- Save after each segment to reduce data loss from crashes/disconnects.

## Research Notes
- Deterministic state transitions are safer for recorder workflows and undo semantics.
- JSON schema and strict timestamp/ID formats help keep profiles machine-mergeable and auditable.
- Logging capture events and decisions improves reproducibility of route tuning.
