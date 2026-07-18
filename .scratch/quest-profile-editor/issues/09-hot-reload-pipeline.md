# 09 — Profile Hot-Reload Pipeline

**What to build:** The save/reload pipeline that takes edited YAML from the editor, validates and compiles it, writes to filesystem, and hot-swaps the compiled profile in the running executor while preserving execution state.

**Blocked by:** 02 — YAML Code Editor

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/hot_reload.lua`
- [ ] Save function: serialize editor state to YAML string
- [ ] Compile function: call `ProfileCompiler` to validate and compile
- [ ] Error handling: if compile fails, return diagnostics to editor
- [ ] File write: write compiled JSON to `scripts_data/quest_profiles/<id>.json`
- [ ] Hot-swap: signal `StatechartExecutor` to load new `CompiledProfile`
- [ ] State preservation: executor preserves current state stack and history
- [ ] Success notification: show "Profile saved and reloaded" message
- [ ] Ctrl+S keyboard shortcut triggers save
- [ ] Auto-save option (save on every edit with debounce)
