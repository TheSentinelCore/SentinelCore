# Quest Authoring IDE
## Volume 3 — In-Game UI Architecture

Version: 1.0
Status: Draft

---

# 1. Philosophy

The editor is **not** a file editor.

It is **not** a JSON editor.

It is **not** a state machine editor.

It is a **world editor**.

The author is walking through Azeroth while designing a quest profile.

The UI should always answer one question:

> "What should happen here?"

NOT

> "What JSON should I write?"

---

# 2. UI Design Goals

The UI must satisfy the following principles:

✓ Capture > Typing

✓ Click > Configuration

✓ Drag > Enter Coordinates

✓ Live Feedback

✓ Always Visible

✓ Zero Modal Dialogs

✓ Immediate Validation

✓ Undo Everything

---

# 3. Layout

Default layout

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Toolbar                                                                    │
├───────────────┬──────────────────────────────────────┬─────────────────────┤
│ Explorer      │             World Map                │ Inspector           │
│               │                                      │                     │
│ Operations    │                                      │ Selected Action     │
│ NPC Library   │                                      │ Properties          │
│ Variables     │                                      │ Conditions          │
│ Validation    │                                      │ Runtime Preview     │
│ Assets        │                                      │                     │
│               │                                      │                     │
├───────────────┴──────────────────────────────────────┴─────────────────────┤
│ Timeline / Action Sequence                                                │
├────────────────────────────────────────────────────────────────────────────┤
│ Console / Validation / Dry Run                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

Every panel is dockable.

Every panel can be hidden.

Layout persists.

---

# 4. Toolbar

```
┌─────────────────────────────────────────────────────────────────────────┐
│ File  Edit  View  Capture  Tools  Test  Help                           │
│                                                                         │
│ Save Compile Validate DryRun Start Stop Undo Redo                      │
└─────────────────────────────────────────────────────────────────────────┘
```

Buttons

Save

Compile

Validate

Run Dry Run

Capture NPC

Capture Path

Capture Area

Undo

Redo

Search

Settings

---

# 5. Explorer

Explorer is the project tree.

```
Alliance Human

▼ Elwynn

    ▼ Northshire

        Northshire Abbey

        Echo Ridge

        Vineyards

    ▼ Goldshire

        Quest Hub

        Jasperlode

        Eastvale

NPC Library

Variables

Blueprints

Validation

Analytics
```

Operations are reordered with drag/drop.

---

# 6. World Map

The World Map is the primary editing surface.

```
+------------------------------------------------------+

              ELWYNN FOREST

          ○ NPC

                 ▲ Player

     ███████████

     Grind Area

                ◎ Vendor

                          ✈ Flight Master

---------------- Road --------------------

                Quest Target

+------------------------------------------------------+
```

Icons

○ NPC

◎ Vendor

✈ Flight Master

🏠 Innkeeper

📦 Mailbox

⚒ Repair

⭐ Quest

🔺 Waypoint

🟩 Polygon

🟦 Route

---

# 7. Map Interaction

Left Click

Select

Double Click

Open Inspector

Right Click

Context Menu

Shift Click

Multi Select

Ctrl Drag

Move Marker

Alt Drag

Duplicate

Mouse Wheel

Zoom

Middle Mouse

Pan

---

# 8. Target Capture Panel

```
Current Target

Marshal McBride

NPC Entry:
197

GUID:
0xF13000197...

Faction:
Alliance

Reaction:
Friendly

Position:
48.2 42.7

──────────────────────────

[ Add NPC ]

[ Quest Giver ]

[ Vendor ]

[ Trainer ]

[ Flight Master ]

[ Innkeeper ]

[ Mailbox ]

[ Banker ]

[ Repair ]

──────────────────────────

Already Exists ✓
```

Workflow

Target NPC

↓

Click

Vendor

↓

Query QueryServer

↓

Merge Roles

↓

Update Library

↓

Validate

---

# 9. NPC Library

```
NPC Library

Search

___________________

☑ Marshal McBride

☑ Brother Neals

☑ General Store

☑ Gryphon Master

☑ Innkeeper

☑ Trainer

```

Selecting NPC

↓

Highlights on Map

↓

Shows all Operations using NPC

↓

Inspector updates

---

# 10. Quest Browser

```
Search

_____________________

Gold Dust

Results

Gold Dust Exchange

Goldtooth

Kobold Camp Cleanup

Wolves Across the Border

```

Selecting Quest

Shows

Objectives

Prerequisites

Followups

Rewards

XP

Turn In NPC

Nearby Quests

Accept NPC

Buttons

```
Add Pickup

Add Turn In

Add Both

Preview Chain
```

---

# 11. Timeline

```
Northshire Abbey

1 Pickup Quest

2 Pickup Quest

3 Go To

4 Grind Area

5 Vendor

6 Turn In

7 Go To

```

Supports

Drag

Drop

Duplicate

Delete

Collapse

Expand

Color Coding

---

# 12. Action Palette

```
Movement

 Go To

 Patrol

 Escort

 Hearth

 Flight

Combat

 Kill Target

 Grind Area

 Loot

 Quest

 Pickup

 Turn In

 NPC

 Vendor

 Repair

 Trainer

 Gossip

 Utility

 Variable

 Branch

 Wait

 Mailbox

 Bank

 Death Skip

 Dungeon

```

Drag onto timeline.

---

# 13. Inspector

```
Selected Action

Grind Area

Name

Kobold Camp

Radius

Automatic

Polygon

8 Vertices

Targets

Kobold Laborer

Kobold Worker

Kobold Miner

Loot

Gold Dust

Linen Cloth

Stop

Quest Complete

```

Inspector changes update live.

---

# 14. Property Editors

Every Action has

Common

Name

Enabled

Notes

Conditions

Retry

Timeout

Tags

Specific

Depends on action type.

---

# 15. Variables Panel

```
Variables

Food

20

Water

20

RepairNeeded

False

HasFlight

True

Deaths

0
```

Supports

Create

Delete

Rename

Watch

---

# 16. Validation Panel

```
ERROR

Turn In

before

Pickup

WARNING

Duplicate Vendor

INFO

Unused Variable

SUCCESS

Compiled
```

Clicking message

↓

Selects offending object.

---

# 17. Console

```
Compile Started

Compiling...

Validation...

Generated

127 Runtime Actions

Success

```

Separate tabs

Editor

Compiler

Runtime

---

# 18. Dry Run

```
Current Action

Pickup Quest

Success

↓

Go To

Simulated

↓

Vendor

Skipped

↓

Turn In

Success

```

Controls

Play

Pause

Step

Reset

---

# 19. Path Recorder

```
Capture Path

● Recording

Distance

52m

Points

14

Time

00:18

[ Stop ]

```

Stop

↓

Simplify

↓

Smooth

↓

Save

↓

Generate Waypoint Action

---

# 20. Polygon Recorder

```
Record Area

● Recording

Vertices

12

Area

328m²

NPC Density

High

```

Stop

↓

Query QueryServer

↓

Creatures

↓

Suggest Targets

↓

Create Grind Action

---

# 21. Context Menu

Right Clicking Map

```
Create Waypoint

Create Polygon

Create Operation

Paste

Center Player

```

Right Clicking NPC

```
Capture NPC

Vendor

Trainer

Quest Giver

Delete

```

---

# 22. Blueprint Library

```
Quest Hub

Vendor Stop

Trainer Stop

Death Skip

Escort

Mailbox

Dungeon

```

Drag

↓

Timeline

↓

Expand During Compile

---

# 23. Multi Select

Ctrl Click

↓

Multiple Actions

Inspector

↓

Bulk Edit

Examples

Enable

Disable

Delete

Tag

Retry Count

---

# 24. Undo / Redo

Every change

↓

Command Stack

```
Capture NPC

↓

Undo

↓

NPC Removed

↓

Redo

↓

NPC Restored
```

Unlimited history until save.

---

# 25. Search Everywhere

Ctrl+P

```
Search

Marshal

Gold Dust

Vendor

Waypoint

Variable

Operation

```

Returns every matching entity.

---

# 26. Hotkeys

Ctrl+S

Save

Ctrl+Shift+S

Compile

Ctrl+Z

Undo

Ctrl+Y

Redo

Delete

Delete Selection

Ctrl+D

Duplicate

Space

Center Player

F

Focus Selection

---

# 27. Workflow Example

Target Marshal McBride

↓

Click

Quest Giver

↓

NPC Added

↓

Click

Add Quest

↓

Quest Browser Opens

↓

Select

"Wolves Across the Border"

↓

Pickup Action Created

↓

Turn In Created

↓

Move to Desired Operation

↓

Compile

↓

Validation Passes

↓

Profile Ready

No JSON edited.

No coordinates typed.

---

# 28. Design Goals Achieved

✔ Map-first authoring

✔ Capture-based workflow

✔ Live validation

✔ Immediate feedback

✔ Reusable blueprints

✔ Database-assisted authoring

✔ Runtime remains hidden

✔ Minimal typing

✔ No modal workflow

✔ One-click capture

---

End of Volume 3
