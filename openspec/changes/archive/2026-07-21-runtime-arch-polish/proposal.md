# Proposal: Runtime Architecture Polish (ADR-017 Wave 4)

## Intent

Fix four architectural violations and missing features in the questing runtime: extract the embedded editor (violates ADR-500 Part 1), add hot reload for profile JSON, initialize profile variables from Runtime JSON, and complete persistence to cover all execution state.

## Scope

### In Scope
- Extract editor_ui.lua from questing module — runtime no longer loads/edits/compiles
- Add file-watcher-based hot reload for profile JSON changes
- Initialize `_variables` from `self._profile.variables` on load, map SetVariable actions
- Complete `_serialize_state()` and `_load_save()` with all missing state fields

### Out of Scope
- Rust editor binary changes (editor_ui.lua already talks to it via HTTP)
- Conditional branching in `_advance_operation` (deferred to future wave)
- UI framework integration for editor_ui.lua stubs

## Capabilities

> This is a pure architecture/implementation refactor — no spec-level behavior changes.

### New Capabilities
None

### Modified Capabilities
None

## Approach

**Ticket 15** — Remove `editor_ui.lua` require from `module.lua:_get_editor()`. Editor becomes a standalone subsystem loaded on-demand outside the questing module. Runtime never imports editor code.

**Ticket 16** — Add a file watcher in `runtime_profile.lua` that polls `self._json_path` for changes. On detected change: validate `content_hash` fingerprint, swap `self._profile`, preserve `self._variables`, continue execution. No restart.

**Ticket 17** — In `runtime_profile.lua:load()`, after `self._profile = decoded`, iterate `self._profile.variables` and initialize `self._variables[name] = current_value`. Map `SetVariable` action in `runtime_action.lua` to update `self._variables`. Persist in save state.

**Ticket 18** — Extend `_serialize_state()` and `_load_save()` in `runtime_profile.lua` to include: `current_action_idx`, `completed_quests`, `temporary_variables`, `visited_vendors`, `known_flight_paths`, `known_hearth_location`, `execution_history`.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `sentinel/modules/questing/module.lua` | Modified | Remove editor require from `_get_editor()` |
| `sentinel/modules/questing/editor_ui.lua` | Removed | No longer loaded by runtime module |
| `sentinel/modules/questing/runtime_profile.lua` | Modified | Add hot reload, variable init, full persistence |
| `sentinel/modules/questing/runtime_action.lua` | Modified | Map SetVariable to update `_variables` |
| `sentinel/modules/questing/runtime_context.lua` | Modified | Remove editor references from runtime context |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Hot reload swaps profile mid-execution with incompatible schema | Low | Validate `content_hash` fingerprint before swap; reject on mismatch |
| Editor extraction breaks existing toggle_editor callers | Low | Keep `toggle_editor()` API but load editor from separate subsystem path |
| Persistence schema change breaks existing save files | Med | Bump save version to 2; old files start fresh (fingerprint mismatch) |

## Rollback Plan

Revert each file individually: `git checkout` on `runtime_profile.lua`, `runtime_action.lua`, `module.lua`. The editor extraction is the riskiest — if callers break, restore `module.lua` and keep editor_ui.lua in place. Hot reload is opt-in by design (no restart required), so it can be disabled by removing the watcher call.

## Dependencies

- None (Wave 4 depends on Wave 3 being complete, which is confirmed)

## Success Criteria

- [ ] `module.lua` no longer requires `editor_ui.lua` — runtime loads and executes without editor code
- [ ] Profile JSON changes are detected and hot-swapped without restart, preserving `_variables`
- [ ] `self._variables[name]` initialized from `self._profile.variables` on load
- [ ] `SetVariable` actions update `_variables` correctly
- [ ] `_serialize_state()` includes all 7 missing fields
- [ ] `_load_save()` restores all 7 new fields
- [ ] Existing save files with version 1 schema still load gracefully (fingerprint mismatch → fresh start)
