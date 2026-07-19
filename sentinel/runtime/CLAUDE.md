# Runtime Module — Agent Reference

The `runtime/` directory is the Lua runtime + storage engine. Under ADR 014
(one-tier model) the authored profile IS the executable profile — there is no
separate compile tier. `ProfileManager:prepare(profile)` runs validation +
cross-Operation merge and returns the same profile (flat `action_type` +
top-level params). The RuntimeAction consumed by `runtime_action_executor`
is exactly what the editor authors.

## Prepare pipeline (entry: `compile_pipeline.lua`, canonical call `ProfileManager:prepare`)

Stages run in order over the flat profile. Each stage takes a profile + ordered
op ids and returns a modified profile + diagnostics. A failed stage
short-circuits the pipeline. `compile` is a deprecated alias for `prepare`.

 1. `stage_reference_resolution` — resolve references (NPC/Quest/Vendor/…) to concrete ids.
 2. `stage_blueprint_expansion` — expand blueprint templates eagerly into flat RuntimeActions.
    (ADR 014: this is the "editor macro" expansion; it runs at prepare time until the
    editor wires direct insertion. Output is already executable — no later lowering.)
 3. `stage_dependency_resolution` — order operations by `dependencies` (topological).
 4. `stage_goal_coverage` — validate every goal is reachable (gate).
 5. `stage_optimization` — cross-operation optimization: Vendor+Repair collapse,
    redundant-GoTo removal, and in-operation reordering (`reorder_actions`).
 6. `stage_lowering` — **pass-through under ADR 014.** `RuntimeTypes.new_runtime_action`
    is a no-op pass-through (flat actions are already executable), so this stage only
    stamps identity/metadata. **Per-instance `ProfileCache` keyed by
    `RuntimeTypes._compute_content_hash`** (recursive table-walk hash). Same content +
    different `profile.name` yields a stable cache hit with re-stamped `profile_id`.

## Storage (`storage_manager.lua`) — deep module

**Interface (inject `file_io` adapter; defaults to Sylvannas `_G.core` globals):**

- `save_tier2(profile)` — writes an authoring profile as a manifest
  (`sentinel/profiles/authoring/<id>.json`) plus one file per operation
  (`.../<id>/ops/<op_id>.json`). Keeps per-op edits from rewriting the whole profile.
- `load_tier2(profile_id)` — reassembles manifest + operation files, running schema
  migration on each.
- `save_tier1(runtime_profile)` — writes the prepared profile (single file). Under
  ADR 014 this is the same flat shape as Tier2 (no separate compiled form); kept for
  back-compat / caching the prepared artifact.
- `load_tier1(profile_id, compiler_fn?)` — reads the prepared copy; if absent, resolves
  from Tier2 via `compiler_fn` and **persists** the result. Without a compiler it returns
  the Tier2 profile tagged `tier = "tier1"` as a best-effort fallback.

**Atomicity:** `_atomic_write` writes a `.tmp` sibling, then renames over the target via
the adapter's `rename`. In-game adapter falls back to a direct overwrite if
`core.rename_data_file` is unavailable.

**Migration:** every load runs `MigrationRegistry:migrate` (chain-walks semver; built-in
`0.0.0 → 1.0.0` advances `schema_version` to `"1.0.0"`).

**Anti-pattern:** do NOT key anything on `JSON:encode(profile)` — `lib/JSON` silently
drops non-string keys (e.g. `params` numeric keys). Use `RuntimeTypes._compute_content_hash`
for content-stable keys.

## Determinism note (SENT-6.11)

`RuntimeTypes._compute_content_hash(value, seen)` is a cycle-guarded recursive walk that
captures every field including `params` and numeric keys. It is the source of truth for
lowering cache keys and `metadata.source_hash`. Editing any action `params` yields a
distinct hash → no stale cache hit.
