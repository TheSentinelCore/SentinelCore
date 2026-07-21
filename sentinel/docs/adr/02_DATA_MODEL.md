Excellent. This is where we define the contract that every other subsystem relies on. I'd actually make one significant change from our earlier discussions:

> **Don't model this as a runtime state machine. Model it as an authoring project.**

The runtime profile can always be generated later, but authors should work with a clean, human-friendly data model.

---

# 02_DATA_MODEL.md

**Sentinel Questing**
**Data Model & Schema Specification**

Version: 1.0
Status: Draft

---

# 1. Purpose

This document defines the canonical data model for Sentinel Questing.

Everything in the editor is represented by these entities.

This is the **single source of truth**.

Every subsystem uses these models:

* RestedXP Importer
* Project Editor
* Validator
* Compiler
* Runtime Generator
* QueryServer

No subsystem may invent additional schema.

---

# 2. Philosophy

Unlike Honorbuddy:

```xml
<If Quest="33">
   <RunTo X="..." />
   <RunTo X="..." />
   <RunTo X="..." />
```

Sentinel stores **intent**, not execution.

Instead:

```json
{
  "type":"Travel",
  "destination":"Marshal McBride"
}
```

The compiler determines the rest.

---

# 3. Entity Relationship Diagram

```text
Project
│
├── Metadata
├── Settings
├── Variables
├── NPC Library
├── Quest Library
├── Object Library
├── Operations
│      │
│      ├── Actions
│      ├── Conditions
│      └── Notes
│
├── Validation
└── Import Metadata
```

---

# 4. Top Level Project

```rust
Project
{
    metadata
    settings

    variables

    npc_library

    quest_library

    object_library

    operations

    diagnostics

    import_metadata
}
```

The Project is the only editable artifact.

Everything else is generated.

---

# 5. Metadata

```rust
ProjectMetadata
{
    id: UUID

    name: String

    author: String

    description: String

    version: String

    schema_version: String

    game_version: "2.4.3"

    faction

    race

    class

    minimum_level

    maximum_level

    created_at

    updated_at
}
```

---

# 6. Settings

```rust
ProjectSettings
{
    autoRepair

    autoVendor

    autoTrain

    learnFlightPaths

    autoHearth

    skipOptional

    stopOnDeath

    stopOnValidationErrors

    compileOptimization

    coordinateMode
}
```

CoordinateMode

```text
WORLD
```

Only world coordinates are stored.

Map coordinates are importer-only.

---

# 7. Variables

Variables replace dozens of Honorbuddy hacks.

```rust
Variable
{
    id

    name

    type

    default_value

    current_value

    description
}
```

Supported types

```text
Bool

Int

Float

String

QuestID

NPCID
```

---

# 8. NPC Library

Instead of repeating NPCs:

```text
Quest 1

Marshal McBride

Quest 2

Marshal McBride

Quest 3

Marshal McBride
```

We reference them.

```rust
NPCReference
{
    id

    entry

    guid

    name

    faction

    roles

    position

    source

    notes
}
```

Roles

```text
QuestGiver

Vendor

Trainer

Repair

FlightMaster

Innkeeper

Mailbox

Banker

Auctioneer

Generic
```

An NPC can have multiple roles.

Example

```text
Vendor

QuestGiver

Repair
```

---

# 9. Quest Library

```rust
QuestReference
{
    id

    quest_id

    title

    level

    minimum_level

    suggested_group

    giver_npc

    finisher_npc

    chain

    prerequisites

    exclusive_with

    repeatable

    source
}
```

No objectives stored here.

Objectives belong to actions.

---

# 10. Object Library

```rust
GameObjectReference
{
    id

    entry

    name

    position

    type

    source
}
```

Examples

Chest

Mailbox

Mining Node

Quest Object

---

# 11. Operations

Operations replace giant profiles.

Example

```text
Northshire

Goldshire

Eastvale

Westfall
```

```rust
Operation
{
    id

    name

    description

    minimum_level

    maximum_level

    enabled

    conditions

    actions

    notes
}
```

---

# 12. Actions

Every operation contains actions.

```rust
Action
{
    id

    type

    enabled

    condition

    payload
}
```

Payload changes based on action type.

---

# 13. Supported Actions

Instead of XML tags we use polymorphism.

Supported actions

```text
AcceptQuest

TurnInQuest

Travel

Kill

GrindArea

LootObject

InteractNPC

Vendor

Repair

Train

LearnFlightPath

UseItem

SetHearth

Hearth

Wait

Escort

Patrol

Mailbox

Bank

Condition

SetVariable

Comment
```

---

# 14. Travel Action

```rust
TravelAction
{
    destination

    position

    tolerance

    mount

    allowFlight

    timeout
}
```

Notice

No waypoint list.

---

# 15. Accept Quest

```rust
AcceptQuest
{
    quest

    npc

    auto_complete_dialog

    optional
}
```

---

# 16. Turn In Quest

```rust
TurnInQuest
{
    quest

    npc

    choose_reward

    optional
}
```

---

# 17. Grind Area

```rust
GrindArea
{
    polygon

    targets

    loot

    timeout

    minimum_kills

    maximum_kills

    stop_condition
}
```

Polygon references a reusable area.

---

# 18. Kill Target

```rust
KillTarget
{
    creature_entries

    quantity

    loot

    ignore_elites
}
```

---

# 19. Vendor

```rust
VendorAction
{
    npc

    sell_grey

    repair

    buy_items

    minimum_free_slots
}
```

---

# 20. Trainer

```rust
TrainerAction
{
    npc

    trainer_type

    minimum_level
}
```

---

# 21. Flight Path

```rust
FlightAction
{
    npc

    destination
}
```

---

# 22. Hearth

```rust
HearthAction
{
    innkeeper

    destination
}
```

---

# 23. Conditions

Conditions replace dozens of duplicated XML rules.

```rust
Condition
{
    expression
}
```

Grammar

```text
QuestCompleted(33)

&&

Level >= 10

&&

HasItem(6948)
```

Supports

```text
AND

OR

NOT

Parentheses
```

---

# 24. Area

Reusable polygon.

```rust
Area
{
    id

    zone

    name

    points

    tags
}
```

Used by

Travel

Grind

Escort

Patrol

---

# 25. Position

```rust
Position
{
    map

    world_x

    world_y

    world_z

    orientation
}
```

World coordinates only.

---

# 26. Diagnostics

Generated.

Never edited.

```rust
Diagnostic
{
    severity

    code

    message

    entity

    action
}
```

Severity

```text
Info

Warning

Error
```

---

# 27. Import Metadata

Tracks source.

```rust
ImportMetadata
{
    importer

    imported_at

    source_file

    checksum

    guide_version
}
```

Allows re-import while preserving edits.

---

# 28. Invariants

Compiler guarantees

Every NPC exists.

Every Quest exists.

Every Action has UUID.

No duplicate IDs.

No circular references.

No missing coordinates.

No broken conditions.

---

# 29. File Layout

```text
Human_1_5/

project.json

operations/

    northshire.json

    goldshire.json

areas/

    wolf_grind.json

npc_library.json

quest_library.json

variables.json
```

Notice the project is **modular**, not a single massive JSON file. This makes source control, merging, and AI-assisted editing much easier than one monolithic profile.

---

# 30. Example Project Structure

```text
Alliance Human 1-5

├── Metadata
├── Settings
├── Variables
├── NPC Library (34 NPCs)
├── Quest Library (27 Quests)
├── Areas
│      ├── Kobold Mine
│      ├── Wolf Spawn
│      └── Goldshire Orchard
│
├── Operations
│      ├── Northshire Abbey
│      ├── Northshire Vineyards
│      ├── Goldshire
│      └── Eastvale Logging Camp
│
└── Import Metadata
```

---

# 31. Schema Versioning

Every project includes:

```json
{
    "schema_version": "1.0.0"
}
```

Versioning follows semantic versioning:

* **Major**: Breaking schema changes (requires migration).
* **Minor**: New optional fields or entities.
* **Patch**: Clarifications, defaults, or metadata additions.

The editor should include a migration pipeline that upgrades older projects to the latest schema while preserving user edits.

---

# 32. Data Model ADRs

### ADR-201 — Projects Are Modular

Projects are stored as directories containing multiple JSON files rather than a single monolithic document.

**Reason:** Easier Git diffs, merges, incremental loading, and AI-assisted editing.

---

### ADR-202 — Libraries Are Centralized

NPCs, Quests, Areas, and Objects are stored once and referenced by ID.

**Reason:** Eliminates duplication and keeps updates consistent.

---

### ADR-203 — World Coordinates Only

Compiled projects store only world-space coordinates (`world_x`, `world_y`, `world_z`).

**Reason:** RestedXP map coordinates are import-time data. The runtime should never perform coordinate conversion.

---

### ADR-204 — Intent-Based Actions

Actions describe *what* should happen, not *how* to execute it.

**Reason:** Navigation and execution remain the responsibility of SentinelNav and the runtime.

---

# 33. Acceptance Criteria

The data model is complete when:

* Every editable concept maps to a defined entity.
* No action duplicates NPC or quest metadata.
* All references are ID-based.
* Projects can be loaded incrementally.
* Validation can detect broken references without executing the project.
* The compiler can generate a deterministic runtime profile from the Project without requiring additional author input.

---

**End of Document – `02_DATA_MODEL.md`**

---

## Before we continue to `03_EDITOR_AND_IMPORTER.md`

After writing this, there are **three architectural improvements** I'd make over our original design:

1. **Replace `Quest Library` with a general `Entity Library`** (NPCs, Objects, Quests, Areas, Vendors, Trainers all become typed entities with shared metadata).
2. **Introduce reusable Blueprints** (e.g., "Standard Vendor Stop", "Learn Class Skills", "Repair + Vendor") that compile into multiple actions.
3. **Treat imported RestedXP guides as immutable source artifacts**, with user overrides stored separately. That allows re-importing updated guides without losing manual edits.

I think these changes would make the system significantly more maintainable before we lock down the editor specification in the next document.
