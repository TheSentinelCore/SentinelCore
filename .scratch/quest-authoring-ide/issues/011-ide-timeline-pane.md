# 011 — IDE: Timeline Pane

**What to build:** Implement the bottom Timeline pane (~180px height) that shows:
- Horizontal strip of operations as expandable cards (Northshire → Goldshire → Eastvale → etc.)
- Each operation card shows: name, icon, progress indicator, expand/collapse toggle
- Expanding an operation reveals its action sequence as horizontal flow
- Actions displayed as labeled chips with icons (color-coded by type)
- Drag-and-drop reordering of actions within an operation
- Drag-and-drop from Action Palette onto timeline to insert new actions
- Clicking an action selects it and updates Properties pane
- Right-click on action shows context menu: Cut/Copy/Paste/Delete/Duplicate
- Keyboard shortcuts: Del (delete), Ctrl+C/X/V (copy/cut/paste), Ctrl+Z/Y (undo/redo)
- Visual indicators for action status: unsaved changes, validation errors
- Inline editing of action labels (double-click to edit name)
- Ability to collapse/expand individual actions to show/hide parameters
- Timeline scrolls horizontally with smooth animation
- Jump to operation buttons (for large numbers of operations)
- Integration with Map: selecting an action highlights its markers/polys on map
- Integration with Explorer: selecting operation in Explorer highlights it in timeline
- Timeline ruler showing estimated time/distance progression
- Ability to insert comments/dividers between action groups
- Performance: virtual scrolling for operations with hundreds of actions
- Tooltip on action hover showing full details and source location
- Context menu for timeline background: Add Operation, Paste, etc.
- Drag timeline to scroll vertically (if multiple timelines supported)
- Timeline can be detached as separate panel or floated

**Blocked by:** 001 — Source Format Specification

**Status:** ready-for-agent

- [ ] Create Timeline component using virtual scrolling for performance
- [ ] Implement operation cards with expand/collapse animation
- [ ] Design action chip component with icon, label, color coding
- [ ] Implement drag-and-drop for actions within and between operations
- [ ] Integrate with Action Palette for inserting new actions
- [ ] Add selection system: clicking action highlights it, updates Properties
- [ ] Implement context menus for actions and timeline background
- [ ] Add keyboard shortcut support (delete, copy/paste, undo/redo)
- [ ] Implement inline editing for action labels and parameters
- [ ] Add visual indicators for validation errors/warnings
- [ ] Create smooth scrolling and animation for expand/collapse
- [ ] Add timeline ruler with distance/time markers (optional)
- [ ] Implement integration with Map component (selection synchronization)
- [ ] Integrate with Explorer component (selection synchronization)
- [ ] Add ability to group actions with comments/dividers
- [ ] Implement virtual rendering for large action lists (>100 actions)
- [ ] Add tooltips showing full action details on hover
- [ ] Implement context menu for timeline background (add operation, paste, etc.)
- [ ] Ensure accessibility compliance (keyboard navigation, screen readers)
- [ ] Performance target: smooth 60fps interaction with 500+ actions