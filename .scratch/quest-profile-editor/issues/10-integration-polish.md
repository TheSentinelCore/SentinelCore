# 10 — Integration, Keyboard Shortcuts & Polish

**What to build:** Final integration of all components, keyboard shortcuts, window persistence, and testing with real profiles.

**Blocked by:** 05 — Statechart Canvas: Editing, 07 — Dependency Graph, 08 — Map Overlay, 09 — Hot-Reload Pipeline

**Status:** ready-for-agent

- [ ] Wire statechart canvas edits to YAML editor (bidirectional sync)
- [ ] Wire quest browser drag-and-drop to statechart canvas
- [ ] Wire dependency graph click to quest browser selection
- [ ] Keyboard shortcuts: Ctrl+S (save), Ctrl+Z (undo), Delete (remove selected), Escape (deselect)
- [ ] Window persistence: remember position, size, active tab across sessions
- [ ] Tab state: remember zoom/pan positions per tab
- [ ] Test with `alliance_human_01_10_elwynn.yaml` profile
- [ ] Test with `westfall.yaml` profile
- [ ] Verify hot-reload preserves execution state
- [ ] Performance: ensure 60fps with 100+ state nodes
- [ ] Add help tooltip explaining editor controls
- [ ] Wire "New Profile" button to create blank profile template
