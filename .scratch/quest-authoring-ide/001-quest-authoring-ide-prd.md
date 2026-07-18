# Quest Authoring IDE v1 - Product Requirements Document

## Stakeholders
- **Primary**: Quest/profile authors (game designers, content creators)
- **Secondary**: Players (who experience the authored content via the bot)
- **Tertiary**: Developers (maintaining the compiler, IDE, executor)

## Goals
1. Enable authors to create questing content by expressing **intent** rather than execution mechanics
2. Leverage the Mangos TBC database for autocomplete, validation, and semantic resolution
3. Provide reusable templates (Blueprints) to eliminate repetition
4. Generate optimized, validated profiles consumable by the existing StatechartExecutor
5. Support project-based authoring for full zones (not just individual profiles)
6. Provide fast iteration via hot-reloading and immediate feedback
7. Ensure generated profiles are debuggable through source mapping

## Non-Goals (v1)
- In-game editing (external IDE only)
- Level 3/4 compiler optimizations (reordering, approval-based suggestions)
- Multi-faction or multi-class variant projects (single faction/class per project)
- General semantic queries (nearest vendor, rare spawns) - limited to validation/Level 1-2 needs
- Advanced debugging (breakpoints, stepping, graph visualization)
- Plugin architecture for custom actions (core + profile-local actions only)

## System Overview

The Quest Authoring IDE is an in-game Sylvannas UI module that resides within the SentinelCore addon structure (e.g., `sentinel/ui/quest_authoring/`). It separates concerns into four layers that interact with the SentinelCore quest system:

```
Authoring Layer (Intent)  <-- Quest Authoring IDE (In-Game Sylvannas UI)
           │
           ▼
Compiler (Semantic Transformation)  <-- Part of SentinelCore (library/binary)
           │
           ▼
Compiled Profile (Executor Input)   <-- JSON files consumed by SentinelCore
           │
           ▼
StatechartExecutor (Runtime Engine) <-- Existing SentinelCore component
           │
           ▼
Game Engine (Sylvannas)
```

### Layer 1: Authoring (Quest Authoring IDE - In-Game Sylvannas UI)
The Quest Authoring IDE (located at `sentinel/ui/quest_authoring/`) presents:
- **Project Explorer**: Tree view of operations and blueprints
- **Action Palette**: Draggable intent nodes (Pickup Quest, Kill Target, Travel, etc.)
- **Four-Pane Canvas**:
  - **Left**: Explorer (~220px) - list of operations/blueprints
  - **Center**: Map (primary) - shows markers/polygons for selected operation
  - **Right**: Properties (~320px) - form for editing selected action/blueprint instance
  - **Bottom**: Timeline (~180px) - horizontal strip of operations, expandable to show/edit action sequences
- **Database Integration**: Autocomplete and validation via Mangos TBC database (Quest/NPC/Item search)
- **Blueprints**: Reusable parameterized templates (e.g., QuestHub expands to Travel+Accept+Vendor+Repair+Train+Hearth+TurnIn+AcceptFollowUps)

### Workflow 1: Creating a New Operation
1. Author opens the Quest Authoring IDE in-game (accessible via chat command or menu)
2. Author creates project directory: `sentinel/data/profiles/quests/elwynn/` (or uses existing)
3. Creates `sentinel/data/profiles/quests/elwynn/project.yaml` with name, zone_id, filiation
4. Opens Quest Authoring IDE → sees empty project in Explorer
5. Clicks "New Operation" → names it "northshire"
6. Quest Authoring IDE creates `sentinel/data/profiles/quests/elwynn/operations/northshire.operation.yaml` with template
7. Author drags actions from Action Palette onto Timeline:
   - Marker (sets start position)
   - QuestHub (Marshal McBride, no flight, with train)
   - KillTarget (Kobold Miner, 8, radius=35)
   - Collect (Wolf Meat, 8)
   - TurnIn (Marshal McBride)
   - Vendor (auto when bags full)
   - Repair (auto when low durability)
8. As they drag, Quest Authoring IDE shows tooltips with action descriptions
9. Author clicks on actions in Timeline/Map to edit properties in Properties pane
10. Author presses Ctrl+S → Quest Authoring IDE saves file → triggers compile
11. Quest Authoring IDE shows errors if any (e.g., unknown NPC ID)
12. On success: Quest Authoring IDE shows "Compiled successfully" and notifies the SentinelCore executor
13. SentinelCore executor hot-swaps new profile and continues from current state

### Workflow 2: Editing an Existing Operation
1. Author selects operation in Quest Authoring IDE Explorer
2. Timeline shows operation's actions as expandable card
3. Author expands card → sees action sequence
4. Author drags new Action Palette item into sequence
5. Author clicks existing action to edit its properties
6. Author presses Ctrl+S → same compile/hot-reload flow
7. If outside Elwynn zone in-game, Quest Authoring IDE debugger shows "Position: (-8900, -160, 82) - Outside operation bounds"

### Workflow 3: Using Blueprints
1. Author opens Quest Authoring IDE Blueprint Explorer (tab in Explorer pane)
2. Sees "QuestHub", "SmartGrind", "Escort" blueprints
3. Drags "QuestHub" onto Timeline
4. In Properties pane, fills in:
   - NPC: "Marshal McBride" (autocomplete suggests from DB)
   - Flight: [ ] 
   - Train: [x]
5. Blueprint shows as single item in Timeline with expand/collapse toggle
6. Clicking expands to show the 8 actions it contains (grayed out, not directly editable)
7. To edit blueprint itself: open in Quest Authoring IDE Blueprint Editor → modify → all instances update

### Workflow 4: Database-Assisted Authoring
1. Author types "Gold Dust Exchange" in Quest action's NPC field in Quest Authoring IDE
2. Quest Authoring IDE shows dropdown: 
   - Gold Dust Exchange (Quest 47) - NPC 773, Reward: 10 silver
   - (Other matches...)
3. Author selects correct one → Quest Authoring IDE auto-fills:
   - NPC ID: 773
   - Quest ID: 47
   - Suggests turn-in NPC: 2061 (Innkeeper Allison) 
   - Suggests objectives based on quest template
4. Author can accept suggestions or override manually

### Workflow 5: Testing and Iteration
1. Author makes change → Ctrl+S in Quest Authoring IDE
2. Quest Authoring IDE compiles → shows any errors/warnings in bottom panel
3. If clean: Quest Authoring IDE notifies SentinelCore executor via local IPC
4. SentinelCore executor hot-swaps new profile (preserves current state/variables)
5. Author sees change take effect immediately in-game:
   - New route appears on minimap (via Quest Authoring IDE debugger)
   - New behavior executes on next relevant event
6. If error: Quest Authoring IDE shows inline red squiggles with error message
7. Author fixes → saves → repeats