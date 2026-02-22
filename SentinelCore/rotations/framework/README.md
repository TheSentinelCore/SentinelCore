# Rotation Framework

Shared primitives for class/spec combat routines.

## Core Modules

- `ActionBuilder.lua`: action object builders.
- `CombatContext.lua`: normalized runtime combat context builder (`0..1` percentages).
- `PlanComposer.lua`: deterministic phase composition and stable priority ordering.
- `RankPolicy.lua`: reusable spell rank/downrank policy helpers.
- `SpellCatalog.lua`: shared spell metadata catalog.
- `AuraCatalog.lua`: shared aura group catalog.
- `SpellbookResolver.lua`: learned-rank lookup adapter.
- `ConsumableCatalog.lua`: item-id catalogs for food/water consumables.

## Action Schema

Use `ActionBuilder` to emit normalized action tables:

- `target_spell(spell_id, priority, opts?)`
- `self_spell(spell_id, priority, opts?)`
- `position_spell(spell_id, priority, opts?)`
- `item_self(item_id|item_ids, priority, opts?)`
- `best_health_potion(priority, opts?)`
- `best_mana_potion(priority, opts?)`

`spell_id` can be a number or a resolver function `(ctx, action) -> spell_id`.

Supported guard fields:

- `min_target_health_pct`, `max_target_health_pct`
- `min_player_health_pct`, `max_player_health_pct`
- `min_player_mana_pct`
- `max_player_mana_pct`
- `min_target_distance`, `max_target_distance`
- `target_must_be_casting`
- `condition(ctx, action)`
- `requires_castable_check` (default `true`)

Item action metadata:

- `item_kind`: optional semantic selector for `use_item_self` (`food`, `water`, `food_or_water`) resolved from current consumables when available.
- `rest_lock_secs`: optional post-consume lock window to prevent repeated item spam while rest auras settle.

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
- `get_movement_profile(ctx)` (optional, combat chase tuning; fallback derives from pull profile)
- `maintenance(ctx)` (optional, out-of-combat upkeep)

Register providers in `rotations/Providers.lua`.

`RotationEngine` loads providers via that catalog, registers by metadata, and evaluates action guards before executing queue/input casts.

## Combat Context Notes

`CombatContext` now exposes target typing helpers for legality-gated spells:

- `target_is_player`
- `target_creature_type_id`
- `target_creature_type_name`
- `target_is_demon`
- `target_is_undead`
- `target_is_undead_or_demon`
- `target_is_creature_type(name)`

It also exposes out-of-combat rest context:

- `eating_or_drinking` (aura-derived with rest-lock fallback)
- `rest_lock_until`

Use these when a spell has strict target-family rules (for example, Exorcism/Holy Wrath in TBC).
