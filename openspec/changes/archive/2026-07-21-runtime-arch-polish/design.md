# Design: Runtime Architecture Polish (ADR-017 Wave 4)

## Technical Approach

Pure internal refactor across 4 tickets in the questing runtime. Editor extraction severs the module -> editor_ui require; hot reload uses polling+content_hash; variable initialization wires profile defaults into runtime; persistence extends v1 schema with 7 missing fields. Zero observable behavioral changes.

## Architecture Decisions

| Decision | Choice | Alternatives | Rationale |
|----------|--------|-------------|-----------|
| Editor extraction strategy | Remove require from `module.lua`; `toggle_editor()` publishes event; editor loads as standalone subsystem | Keep editor but guard with flag | ADR-500 Part 1: runtime must NEVER load/edit/compile Lua. Event bus decouples without breaking external callers |
| Hot reload trigger | Per-tick polling of `mtime` on profile JSON | fsnotify lib, explicit `/reload` command | Lua has no native filesystem notifications; polling is the only portable option. mtime check is cheap (stat call) |
| Variable initialization | Copy defaults from `self._profile.variables` in `load()` after profile decode | Lazy init on first variable read | Early init ensures `SetVariable` sees defaults before any action executes; matches SetVariable's existing write-to-context pattern |
| Persistence schema migration | Bump to v2; v1 saves get fingerprint mismatch -> fresh start | In-place migration from v1->v2 | v1 saves have so few fields that migration adds complexity for zero gain; fingerprint validation already rejects mismatches cleanly |

## Data Flow

```
T15 -- Editor Extraction (before -> after)

  Before:                         After:
  module:toggle_editor()          module:toggle_editor()
    -> _get_editor()                 -> event_bus:publish("questing:toggle_editor")
    -> require("editor_ui")          -> (no editor code loaded)
    -> QuestingEditor:toggle()    
                                     EditorSubsystem (separate):
                                       -> subscribe("questing:toggle_editor")
                                       -> lazy-require editor_ui
                                       -> QuestingEditor:toggle()

T16 -- Hot Reload (per-tick)

  Profile JSON mtime changed? --no--> skip
    | yes
    v
  Read file -> parse JSON -> validate content_hash
    | hash mismatch? --yes--> skip (emit log warning)
    v no
  hash same as last? --yes--> update mtime cache only, skip
    v different
  Swap self._profile, preserve self._variables values,
  reset init defaults for new variables
    -> _log_event("hot_reload")
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `sentinel/modules/questing/module.lua` | Modify | Remove `_get_editor()`; `toggle_editor()` publishes event; keep `load_compiled_profile()` |
| `sentinel/modules/questing/runtime_profile.lua` | Modify | Add `_hot_reload_check()`, variable init in `load()`, 7 new fields in `_serialize_state()`/`_load_save()`, bump to v2 |
| `sentinel/modules/questing/runtime_action.lua` | Modify | No structural changes -- SetVariable already writes to `ctx.variables` (which is `self._variables` by reference) |
| `sentinel/modules/questing/runtime_context.lua` | None | Already clean -- no editor references found |
| `sentinel/modules/questing/editor_ui.lua` | Keep (move to editor subsystem) | Not deleted -- moved out of questing module's require path |

## Interfaces / Contracts

**Hot reload guard -- only when state == "running":**
```lua
function RuntimeProfile:_check_hot_reload()
    if self._state ~= "running" then return end
    -- mtime poll -> read -> content_hash validate -> swap
end
```

**Variable init in load():**
```lua
self._variables = {}
if self._profile.variables then
    for _, v in ipairs(self._profile.variables) do
        self._variables[v.name] = v.default_value or 0
    end
end
```

**v2 save schema additions:**
```lua
-- _serialize_state() additions (beyond v1 fields):
version = 2,
current_action_idx = self._current_action_idx,
completed_quests = self._completed_quests or {},
temporary_variables = self._temporary_variables or {},
visited_vendors = self._visited_vendors or {},
known_flight_paths = self._known_flight_paths or {},
known_hearth_location = self._known_hearth_location,
execution_history = self._execution_log or {},
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | Editor not loaded after `toggle_editor()` | Assert `require` not called for `editor_ui` |
| Unit | Hot reload swaps profile preserves variables | Mock profile JSON, change mtime, verify `_variables` survive |
| Unit | Variable init from profile defaults | Load profile with known variables, assert `self._variables` matches |
| Unit | v2 save/load round-trip (all 7 fields) | Serialize -> deserialize -> assert equal |
| Unit | v1 save file -> fresh start | Load v1-format save, assert fingerprint mismatch path |
| Integration | SetVariable -> persisting in save | Execute SetVariable, save, reload, assert value restored |

## Threat Matrix

N/A -- no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary. Pure Lua runtime refactoring.

## Migration / Rollout

No migration required. v1 save files get fingerprint mismatch on next load (no profile hash match) -> start fresh. Existing execution continues uninterrupted. Hot reload is opt-in (triggered by `_check_hot_reload` in tick); disable by removing the one call.

## Open Questions

- [ ] Where should `editor_ui.lua` physically live after extraction? New `sentinel/editor/` directory, or stay in `questing/` but never required by module? (Proposal: keep file in place, remove require path -- simplest rollback)
