# Tasks: Runtime Architecture Polish (ADR-017 Wave 4)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~305 |
| 400-line budget risk | Medium |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | auto-forecast |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Medium

## Phase 1: Editor Extraction (T15)

- [x] 1.1 `module.lua`: Remove `_get_editor()`, replace toggle_editor body with `event_bus:publish("questing:toggle_editor")`
- [x] 1.2 Test: Assert `editor_ui` is not loaded after calling `toggle_editor()`

## Phase 2: Variable Initialization (T17)

- [x] 2.1 `runtime_profile.lua`: In `load()`, iterate `self._profile.variables` and init `self._variables[name] = v.default_value or 0`
- [x] 2.2 Test: Load profile with variables, assert `self._variables` matches defaults

## Phase 3: Hot Reload (T16)

- [x] 3.1 `runtime_profile.lua`: Add `_check_hot_reload()` — guard on `_state`, poll mtime, read/parse JSON, validate content_hash, swap profile preserving `_variables`
- [x] 3.2 Wire `_check_hot_reload()` into the per-tick execution loop
- [x] 3.3 Test: Mock profile JSON, change mtime, verify `_variables` survive the swap

## Phase 4: Persistence (T18)

- [x] 4.1 `runtime_profile.lua`: Add 7 fields to `_serialize_state()`, bump save version to 2
- [x] 4.2 `runtime_profile.lua`: Add 7 fields to `_load_save()`, handle nil gracefully for v1 saves
- [x] 4.3 Test: v2 save/load round-trip — serialize then deserialize, assert all 7 fields match
- [x] 4.4 Test: Load v1 save file, assert fingerprint mismatch triggers fresh start

## Phase 5: Integration & Verification

- [x] 5.1 Verify `runtime_context.lua` has no editor references (already clean per design)
- [x] 5.2 Verify `runtime_action.lua` SetVariable writes to `ctx.variables` (ref to `self._variables`)
- [x] 5.3 Integration test: Execute SetVariable, save, reload, assert value restored
