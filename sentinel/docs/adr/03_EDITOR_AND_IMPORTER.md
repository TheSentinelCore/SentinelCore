
### In-Game Editor & RestedXP Importer Specification

**Version:** 1.0  
**Status:** Draft

----------

# 1. Purpose

This document specifies the complete authoring experience for Sentinel Questing.

Unlike Honorbuddy, the user should almost never manually edit JSON.

Unlike RestedXP, the editor should be visual.

Unlike Unity, the editor should be lightweight enough to run in-game.

The editor exists for one purpose:

> Turn a leveling strategy into a validated Sentinel Project.

----------

# 2. Core Philosophy

The editor should feel like a cross between:

-   Unity Inspector
-   Visual Studio Solution Explorer
-   Rider
-   Blizzard's own Quest Log

It should **not** feel like:

-   XML editing
-   Honorbuddy Profile Editor
-   Raw JSON
-   YAML

The user should spend 95% of their time clicking.

----------

# 3. Design Goals

The editor must:

✔ Run in-game

✔ Support hot reload

✔ Support importing RestedXP

✔ Edit projects

✔ Validate continuously

✔ Compile

✔ Test

without restarting the game.

----------

# 4. Overall Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Sentinel Questing                                            Save Compile X │
├──────────────┬──────────────────────────────┬───────────────────────────────┤
│              │                              │                               │
│ Project      │      Operation Timeline      │      Inspector                │
│ Explorer     │                              │                               │
│              │                              │                               │
│              │                              │                               │
│              │                              │                               │
│              │                              │                               │
│              │                              │                               │
├──────────────┼──────────────────────────────┼───────────────────────────────┤
│ Entity       │ Validation Console           │ Query Results                 │
│ Library      │                              │                               │
└──────────────┴──────────────────────────────┴───────────────────────────────┘
```

Everything is dockable.

Everything remembers layout.

----------

# 5. Primary Panels

The editor consists of seven permanent panels.

```
Project Explorer

Timeline

Inspector

Entity Library

Validation

Query Browser

Console
```

----------

# 6. Project Explorer

Think Unity.

```
Alliance Human 1-60

▼ Operations

    Northshire

    Goldshire

    Eastvale

    Westfall

▼ Areas

▼ NPC Library

▼ Variables

▼ Import Metadata
```

Right click:

```
New Operation

Rename

Duplicate

Delete

Compile

Export
```

----------

# 7. Operation Timeline

This replaces Honorbuddy XML.

Example

```
Operation

Northshire Abbey

---------------------------------------------------

✓ Accept A Threat Within

✓ Accept Kobold Camp Cleanup

✓ Travel to Kobold Camp

✓ Kill Kobold

✓ Loot Candles

✓ Return

✓ Turn In

✓ Vendor

✓ Learn Skills

✓ Travel Goldshire
```

Each action is:

Draggable

Copyable

Disable-able

Collapsible

----------

# 8. Action Cards

Every action is a card.

```
+-------------------------------------------+

Travel

Destination

Goldshire

Distance

642m

Condition

Level >= 5

--------------------------------------------

Double Click

↓

Inspector

+-------------------------------------------+
```

----------

# 9. Inspector

The Inspector edits the selected action.

Example

Travel

```
Destination

Goldshire

NPC

Marshal Dughan

Tolerance

5 yd

Mount

Auto

Timeout

300 sec

Condition

QuestCompleted(54)
```

Changes apply immediately.

----------

# 10. Action Toolbar

Instead of XML tags:

Toolbar

```
+ Accept

+ Turn In

+ Travel

+ Grind

+ Vendor

+ Repair

+ Trainer

+ Flight

+ Hearth

+ Wait

+ Condition

+ Variable

+ Mailbox

+ Bank

+ Escort

+ Patrol

+ Comment
```

Click

↓

Creates action

↓

Inspector opens

----------

# 11. Entity Library

Instead of typing IDs.

```
NPC Library

Marshal McBride

Quest Giver

Vendor

Repair

--------------------

Innkeeper Farley

Innkeeper

--------------------

Kobold Vermin

Creature

--------------------

Wolf

Creature
```

Double click

↓

Referenced

Never copied.

----------

# 12. Search

Global search.

```
Search...

Marshal

↓

Marshal McBride

Marshal Dughan

Marshal Haggard
```

Searches

NPCs

Quests

Areas

Objects

Operations

Variables

----------

# 13. Query Browser

Backed by QueryServer.

```
Quest Search

Gold Dust Exchange

↓

Quest

NPC

Objectives

Prerequisites

Rewards

Coordinates

Chain

Accept NPC

Turn In NPC

Spawn Areas
```

One click

↓

Import

----------

# 14. Area Editor

One of the biggest improvements over Honorbuddy.

```
Record Area

↓

Walk

↓

Stop

↓

Polygon Created
```

Result

```
Wolf Area

Points

18

Creatures

Wolf

Young Wolf

Dire Wolf

Density

High
```

Compiler references polygon.

Never stores hundreds of waypoints.

----------

# 15. Travel Recorder

Travel recording.

```
Start Recording

↓

Walk

↓

Stop Recording
```

Compiler simplifies.

Stores

```
Start

End

Optional reference path
```

Not every intermediate step.

----------

# 16. Target Capture

The easiest workflow.

Target NPC

↓

Capture

↓

```
Add Quest Giver

Add Vendor

Add Trainer

Add Flight Master

Add Generic NPC
```

Captured

```
GUID

Entry

Position

Faction

Reaction

Coordinates
```

QueryServer enriches.

----------

# 17. RestedXP Import

Import

↓

Select Guide

↓

Lexer

↓

Parser

↓

AST

↓

Validation

↓

Project

Progress

```
Reading Guide...

Resolving NPCs...

Resolving Quests...

Resolving Coordinates...

Creating Operations...

Finished.
```

----------

# 18. Import Diagnostics

If importer finds issues

```
Unknown Label

Missing Quest

Unknown Directive

Unsupported Command
```

Clickable.

----------

# 19. Live Validation

Every edit triggers validation.

```
Warning

Turn In before Accept

----------

Warning

Unknown NPC

----------

Error

Circular Condition

----------

Error

Missing Quest
```

----------

# 20. Dry Run

Huge feature.

Instead of bot running

Editor simulates.

```
Start Dry Run

↓

Action 1

Accept

↓

Travel

↓

Vendor

↓

Turn In

↓

Finished
```

Movement disabled.

Combat disabled.

Perfect for testing.

----------

# 21. Compile

Compile button.

Pipeline

```
Validate

↓

Optimize

↓

Generate Runtime

↓

Write Runtime JSON

↓

Hot Reload
```

----------

# 22. Save

Project save.

```
project/

operations/

npc_library/

areas/

variables/

settings/
```

Everything modular.

----------

# 23. Undo / Redo

Every modification becomes a command.

```
Add Action

Delete Action

Move Action

Rename

Capture NPC
```

Unlimited history.

----------

# 24. Multi Select

Supports

Ctrl

Shift

Rectangle

Example

```
Travel

Vendor

Repair
```

↓

Duplicate

↓

Paste

----------

# 25. Blueprint Library (New)

This is one improvement over our previous architecture.

Instead of repeatedly creating the same sequence of actions:

```
Vendor

Repair

Buy Food

Buy Water
```

You create a reusable Blueprint:

```
Town Visit
```

Internally:

```
Town Visit

↓

Vendor

↓

Repair

↓

Restock Food

↓

Restock Water

↓

Train
```

Then future projects simply drag:

```
Town Visit
```

onto the timeline.

This drastically reduces repetitive editing.

----------

# 26. RestedXP Source Mapping (New)

Every imported action keeps a reference back to the original guide.

Example:

```
Accept Quest

↓

Imported From

Human.lua

Line 421
```

If the guide updates later:

```
Import

↓

Diff

↓

Keep User Changes

↓

Merge
```

This is much safer than replacing the project.

----------

# 27. Smart Capture (New)

Instead of:

```
Target NPC

↓

Add Vendor
```

The editor asks QueryServer:

```
Entry 197

↓

Vendor

Quest Giver

Repair

```

The UI suggests:

```
✓ Vendor

✓ Quest Giver

✓ Repair

```

One click.

All roles assigned.

----------

# 28. Keyboard Shortcuts

```
Ctrl+S Save

Ctrl+B Compile

Ctrl+Z Undo

Ctrl+Y Redo

Ctrl+F Search

Ctrl+D Duplicate

Delete Delete

F2 Rename

Space Dry Run
```

----------

# 29. Editor ADRs

## ADR-301

Projects are edited.

Never runtime profiles.

----------

## ADR-302

Every edit validates immediately.

----------

## ADR-303

Everything references IDs.

Never duplicate NPC data.

----------

## ADR-304

Blueprints compile into actions.

----------

## ADR-305

Import source mapping is preserved.

----------

## ADR-306

The editor remains in-game.

No external desktop IDE required for v1.

----------

# 30. Acceptance Criteria

The editor is considered complete when an author can:

-   Import a RestedXP guide into a project.
-   Browse and search all imported operations.
-   Add, remove, reorder, and edit actions through the timeline.
-   Capture NPCs directly in-game and automatically enrich them through the QueryServer.
-   Record travel paths and grind areas without manually entering coordinates.
-   Validate the project continuously with actionable diagnostics.
-   Perform a dry run without executing movement or combat.
-   Compile the project into a runtime profile and hot-reload it into the running bot.
-   Re-import an updated RestedXP guide while preserving manual edits through source mapping.
