# Rotation Framework

Shared primitives for class/spec combat routines.

## Action Schema

Use `ActionBuilder` to emit normalized action tables:

- `target_spell(spell_id, priority, opts?)`
- `self_spell(spell_id, priority, opts?)`

Supported guard fields:

- `min_target_health_pct`, `max_target_health_pct`
- `min_player_health_pct`, `max_player_health_pct`
- `min_player_mana_pct`
- `min_target_distance`, `max_target_distance`
- `target_must_be_casting`
- `condition(ctx, action)`
- `requires_castable_check` (default `true`)

## Provider Contract

Providers should implement:

- `class_id()` or `CLASS_ID`
- `spec_id()` or `SPEC_ID` (use `0` for TBC fallback)
- `can_run(ctx)`
- `defensive(ctx)`
- `interrupt(ctx)`
- `utility(ctx)`
- `combat(ctx)`
- `aoe(ctx)`
- `get_pull_profile(ctx)`

Register providers in `rotations/Providers.lua`.

`RotationEngine` loads providers via that catalog, registers by metadata, and evaluates action guards before executing queue/input casts.
