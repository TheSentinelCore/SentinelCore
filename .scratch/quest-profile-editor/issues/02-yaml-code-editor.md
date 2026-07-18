# 02 — YAML Code Editor

**What to build:** A text editor component that displays the profile YAML with line numbers and basic syntax highlighting. The editor shows the raw YAML of the loaded profile, highlights keywords/strings/numbers, and displays compile errors as inline diagnostics. Users can edit the YAML directly.

**Blocked by:** 01 — Editor Window Shell

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/yaml_editor.lua`
- [ ] Display YAML with line numbers (left gutter)
- [ ] Basic syntax highlighting: keywords (type, event, target), strings (quoted), numbers, comments (#)
- [ ] Show compile errors as red highlights on affected lines
- [ ] Scroll vertically through long files
- [ ] Track cursor position (line, column) for diagnostics
- [ ] Integrate with `ProfileEditorController` — load/save YAML content
- [ ] Wire "Save" button to serialize YAML and trigger hot-reload pipeline
