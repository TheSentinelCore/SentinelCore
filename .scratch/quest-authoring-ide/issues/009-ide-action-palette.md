# 009 — IDE: Action Palette

**What to build:** Implement the Action Palette - a panel containing draggable action items that users can drop onto the Timeline:
- Categorized list of actions: Movement, Quest, Economy, Utility, etc.
- Each action shows: icon, name, brief description
- Dragging creates a "ghost" that follows cursor, showing where it will insert
- Dropping onto Timeline inserts the action at that point
- Dropping between two actions shows insertion line
- Dropping on an action replaces it (with confirmation)
- Right-click on action shows context menu: "Add New Above/Below", "Add Instance"
- Search/filter box to find actions by name
- Recently used section at top
- Ability to mark favorites for quick access
- Tooltips show full description and parameter requirements
- Keyboard navigation: arrow keys to browse, Enter to add at cursor
- Integration with Blueprint system: shows blueprints alongside atomic actions
- Blueprint items visually distinct (e.g., with a overlay icon or label)
- When dragging a blueprint, shows what it expands to on hover (optional preview)
- Persistent state: last open category, scroll position, favorites
- Compact and dense display modes (toggle via settings)
- Minimal width: 200px, ideal width: 280px
- Can be detached as floating window or docked to left/right edges
- Initially docked above Timeline or in left pane below Explorer (user configurable)

**Actions to include in v1**:
Movement:
  - Marker (set start position)
  - Go To (Travel to NPC/position/area)
  - Wait (fixed time or until condition)

Quest:
  - Pickup Quest
  - Turn In Quest
  - Accept Available Quests (at NPC)
  - AcceptAll, atSpecific)
  - Abandon Quest

Economy:
  - Vendor (sell junk, repair, restock)
  - Repair (armor/weapons)
  - Train (learn skills/spells)
  - Mail (send/check mail)
  - Bank (deposit/withdraw)
  - Auction House (browse/buy/sell)

Utility:
  - Hearthstone (set/recall)
  - Flight Path (take flight route)
  - Zeppelin/Boat (take transport)
  - Summon Pet
  - Dismiss Pet

Combat:
  - Kill Target (specific NPC, with count/radius/health filters)
  - Assist Ally (help friendly NPC)
  - Defend Location (area)
  - Patrol Route (loop between points)

Collection:
  - Loot Object (specific item ID)
  - Loot Quest Items (for current quest)
  - Gather Node (herb, mine, etc.) - simple placeholder

**Blocked by:** 001 — Source Format Specification

**Status:** ready-for-agent

- [ ] Create Action Palette component with categorized tabs/lists
- [ ] Implement drag source for each action item
- [ ] Define drag payload: action type, default parameters, category
- [ ] Create visual representation: icon + name + description
- [ ] Implement drop target logic for Timeline component
- [ ] Show insertion indicator (line) when dragging between items
- [ ] Handle drop-on-replace with confirmation dialog
- [ ] Right-click context menu on palette items
- [ ] Search/filter functionality (real-time as user types)
- [ ] Recently used and favorites sections
- [ ] Tooltips with detailed description and parameter help
- [ ] Keyboard navigation support
- [ ] Blueprint integration: show alongside atomic actions
- [ ] Visual distinction for blueprints (e.g., small "stack" icon overlay)
- [ ] Optional: blueprint hover preview showing expanded actions
- [ ] Persist UI state: selected tab, scroll position, favorites
- [ ] Compact/comfortable density toggle
- [ ] Make pane detachable as floating window or dockable to edges
- [ ] Initial position: docked above Timeline or in left column
- [ ] Define the initial set of actions for v1 (list above)