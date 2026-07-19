# 012 — IDE: Properties Pane

**What to build:** Implement the right-hand Properties pane (~320px width) that shows:
- Context-sensitive form for editing selected action/blueprint invocation
- Field layout adapts to selected action type (dynamic form generation)
- Real-time validation with inline error messages
- Auto-completion for database fields (NPC names, quest names, item names)
- Number sliders for ranges (count, radius, health %, etc.)
- Checkboxes for boolean flags (loot, vendor, repair, train, flight, etc.)
- Dropdowns for enumerated values (loot filters, travel policies, etc.)
- Color pickers for visual elements (if applicable)
- Multi-line text editors for descriptions/comments
- Object pickers: clicking field icon allows selecting object in game world
- Field grouping: Position, Combat, Loot, Timing, Conditions, etc.
- Help tooltips for each field explaining purpose and valid values
- Default value restoration (right-click or double-click to reset)
- Copy/paste functionality for individual fields or entire action
- Inherited value indication (shows when value comes from blueprint parameter)
- Override indicator (shows when blueprint parameter is overridden)
- Parameter binding display (shows $param references)
- Undo/redo stack for property changes
- Integration with Validation panel: shows related warnings/errors
- Resizable splitter between Properties and adjacent panes
- Scrollable content for long forms
- Printable view option (for documentation)
- Ability to collapse/expand sections
- Search within properties for large forms
- Preset buttons for common configurations (e.g., "Standard Vendor Setup")
- Integration with Blueprint system: shows which values come from blueprint
- Real-time preview of how action will appear in compiled output (optional)

**Field Types to Support**:
- Text: single line input (names, descriptions)
- Number: spinners/sliders with min/max/step
- Boolean: checkboxes/toggles
- Dropdown: enumerated options (loot filter, travel policy, etc.)
- Color: RGB/HSV picker with alpha
- Object Picker: button that opens world selector for NPC/item/gameobject
- Multi-line Text: resizable textarea for descriptions
- Date/Time: for scheduled events (if applicable)
- File Picker: for importing/exporting related data
- Array/List: for multiple values (waypoints, item lists, etc.)
- Reference: links to other actions/operations in same project

**Blocked by:** 001 — Source Format Specification

**Status:** ready-for-agent

- [ ] Create Properties component with dynamic form generation
- [ ] Implement form field factory that creates appropriate input based on action type
- [ ] Add real-time validation with visual feedback (red/green borders)
- [ ] Integrate with enhanced QueryClient for autocomplete (NPC, quest, item search)
- [ ] Add number inputs with slider alternative for ranges
- [ ] Implement boolean controls as toggles/checkboxes
- [ ] Add dropdowns for enumerated values with search capability
- [ ] Include color picker for visual customization fields
- [ ] Create multi-line text editor for descriptions/notes
- [ ] Implement object picker: button that triggers world selection mode
- [ ] Group related fields logically (Combat, Movement, Loot, etc.)
- [ ] Add help tooltips that explain each field's purpose and constraints
- [ ] Implement default value restoration (right-click or context menu)
- [ ] Add copy/paste functionality for individual field values
- [ ] Indicate when values come from blueprint parameters (italic/gray)
- [ ] Show override status when blueprint parameter is changed locally
- [ ] Display parameter bindings ($param) clearly in field labels
- [ ] Implement undo/redo stack for property changes (Ctrl+Z/Y)
- [ ] Connect to Validation panel to show related warnings/errors
- [ ] Add resizable splitter between Properties and Map/Timeline panes
- [ ] Ensure content is scrollable when form exceeds pane height
- [ ] Add print-friendly stylesheet for generating documentation
- [ ] Implement collapsible sections with animated transitions
- [ ] Add search/filter functionality for large property sets
- [ ] Include preset buttons for common configurations (e.g., "Quest Giver Setup")
- [ ] Show blueprint inheritance: which values are from blueprint vs overridden
- [ ] Display parameter resolution: how $param evaluates to actual value
- [ ] Add preview pane showing how action will compile to JSON (optional)
- [ ] Ensure WCAG 2.1 AA accessibility compliance
- [ ] Performance target: responsive updates with <50ms delay