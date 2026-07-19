# 008 — IDE: Explorer Pane

**What to build:** Implement the left-hand Explorer pane (~220px width) that shows:
- Project tree view: project.yaml, operations/ folder, blueprints/ folder
- Operations listed as files: northshire.operation.yaml, goldshire.operation.yaml, etc.
- Blueprints listed as files: quest_hub.blueprint.yaml, smart_grind.blueprint.yaml, etc.
- Click to select an operation or blueprint
- Right-click context menu: New Operation, New Blueprint, Delete, Rename
- Drag-and-drop reordering of operations (affects load order in manifest)
- Icons to distinguish file types (project, operation, blueprint)
- Status indicators: clean, modified, error (from compiler)
- Toolbar buttons: New Project, Open Project, Save All
- Resizable splitter between Explorer and main canvas (min/max widths)
- Keyboard navigation: arrow keys, Enter to select, Delete to remove
- Integration with file watcher to detect external changes
- Shows current project name at top
- Double-click to open/edit file in internal editor (or external if preferred)
- Context shows project path for disambiguation when multiple projects open

**Blocked by:** 001 — Source Format Specification

**Status:** ready-for-agent

- [ ] Implement Explorer pane using Sylvannas UI framework
- [ ] Implement project tree view with folders/files
- [ ] Show operation files (.operation.yaml) under operations/ folder
- [ ] Show blueprint files (.blueprint.yaml) under blueprints/ folder
- [ ] Click to select item, highlight selection
- [ ] Right-click context menu with relevant actions
- [ ] Drag-and-drop to reorder operations (updates manifest order)
- [ ] Visual indicators for file state: clean (gray), modified (blue), error (red)
- [ ] Toolbar: New Project, Open Project, Save All buttons
- [ ] Resizable splitter with collapse capability
- [ ] Keyboard shortcuts: Del (delete), F2 (rename), Ctrl+N (new), Ctrl+O (open)
- [ ] File watcher integration: update status when file changes externally
- [ ] Display current project name and path
- [ ] Double-click to open selected file (default: internal YAML editor)
- [ ] Tooltip on hover shows full path
- [ ] Support multiple projects open simultaneously (tabs or window per project)