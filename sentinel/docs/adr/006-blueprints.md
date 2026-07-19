# Quest Authoring IDE
## Volume 6 — Blueprint System

Version: 1.0
Status: Canonical Specification

---

# 1. Overview

The Blueprint System is the single biggest improvement over every previous
quest profile editor (Honorbuddy, Quester, ZzukBot, RestedXP, Zygor).

Instead of forcing authors to create hundreds of primitive actions, the editor
allows them to author **Blueprints**.

Blueprints are reusable, high-level behaviors that expand into optimized
runtime actions during compilation.

Think of them as:

- Unreal Engine Blueprints
- Unity Prefabs
- VSCode Snippets

…but for quest automation.

---

# 2. Why Blueprints Exist

Without Blueprints

```
Travel

↓

Accept Quest

↓

Accept Quest

↓

Accept Quest

↓

Vendor

↓

Repair

↓

Train

↓

Talk

↓

Leave

```

Author manually creates 18 actions.

---

With Blueprints

```
Quest Hub

↓

Configure

↓

Done
```

Compiler expands automatically.

---

# 3. Authoring vs Runtime

Author edits

```
Quest Hub
```

Compiler generates

```
Travel

↓

Face NPC

↓

Talk

↓

Pickup Quest

↓

Pickup Quest

↓

Pickup Quest

↓

Vendor

↓

Repair

↓

Train

↓

Leave Hub
```

Runtime never knows a blueprint existed.

---

# 4. Blueprint Categories

```
Quest

Travel

Combat

NPC

Inventory

Economy

Utility

Recovery

Dungeon

Custom
```

---

# 5. Standard Blueprints

## Quest Hub

Handles

- Travel
- Accept quests
- Vendor
- Repair
- Train
- Hearth
- Flight
- Leave

---

## Vendor Stop

Handles

- Sell
- Repair
- Buy Food
- Buy Water
- Buy Ammo
- Restock

---

## Flight Unlock

Handles

- Travel
- Talk
- Learn Flight Path

---

## Trainer Stop

Handles

- Travel
- Train
- Learn Skills

---

## Hearth Setup

Handles

- Travel
- Talk
- Set Hearthstone

---

## Mailbox

Handles

- Open Mail
- Send Items
- Receive Gold

---

## Grind Session

Handles

- Travel

- Polygon

- Kill

- Loot

- Stop Conditions

---

## Escort

Handles

- Accept

- Follow NPC

- Defend

- Complete

---

## Patrol

Handles

Loop

Wait

Waypoint Sequence

---

## Death Skip

Handles

Death

Spirit

Corpse

Continue

---

## Dungeon Entry

Handles

Travel

Wait

Enter

Meet Group

---

# 6. Blueprint Structure

```rust
pub struct Blueprint {

    pub id: Uuid,

    pub name: String,

    pub category: BlueprintCategory,

    pub description: String,

    pub icon: String,

    pub parameters: Vec<Parameter>,

    pub outputs: Vec<Action>,

}
```

---

# 7. Parameters

Example

Quest Hub

```
Quest Giver

Vendor

Trainer

Repair

Flight

Hearth

Accept All

```

Author fills parameters.

Compiler fills everything else.

---

# 8. Blueprint Example

Quest Hub

```
Quest Hub

NPC

Marshal McBride

Vendor

Brother Danil

Trainer

Brother Sammuel

Repair

Enabled

Accept

All

```

Compiler expands.

---

# 9. Expansion Pipeline

```
Blueprint

↓

Validate

↓

Resolve References

↓

Inject Runtime Actions

↓

Optimize

↓

Execution Graph
```

---

# 10. Composite Actions

Blueprints may contain

Blueprints.

Example

Quest Hub

↓

Vendor Stop

↓

Trainer Stop

↓

Flight Unlock

↓

Quest Pickup

Nested composition.

---

# 11. Blueprint Library

```
Blueprints

Quest Hub

Vendor Stop

Repair

Flight

Escort

Mailbox

Grind Area

Death Skip

Favorites

Recent
```

Drag onto timeline.

---

# 12. Custom Blueprints

Authors can save

```
My Human Start

↓

Reusable
```

Across profiles.

---

# 13. Parameter Types

```
NPC

Quest

Waypoint

Polygon

Creature

Vendor

Trainer

Flight

Boolean

Integer

Float

String

Enum
```

---

# 14. Optional Parameters

Quest Hub

```
Repair

Optional

Vendor

Optional

Flight

Optional

```

Compiler removes unused actions.

---

# 15. Conditional Expansion

Example

```
Repair

Enabled?

↓

No

↓

Remove Repair Action
```

No runtime branching required.

---

# 16. Smart Defaults

Blueprint defaults come from QueryServer.

Example

Vendor

↓

Nearest Vendor

Trainer

↓

Nearest Trainer

Quest Giver

↓

Current Target

---

# 17. Blueprint Validation

Checks

Missing NPC

Duplicate Quest

Unknown Quest

No Polygon

Invalid Target

Missing Vendor

---

# 18. Visual Appearance

Timeline

```
▶ Quest Hub

    4 Quests

    Vendor

    Repair

    Train

```

Collapsed.

Expandable.

---

Expanded

```
Quest Hub

  Pickup

  Pickup

  Pickup

  Vendor

  Repair

  Train
```

Greyed.

Generated.

Read-only.

---

# 19. Editing

Double Click

↓

Blueprint Inspector

Change Parameters

↓

Runtime regenerates.

---

# 20. Inspector

```
Quest Hub

Quest Giver

Marshal McBride

Vendor

Brother Danil

Trainer

Brother Sammuel

Repair

☑

Train

☑

Accept All

☑
```

No primitive actions edited.

---

# 21. Generated Actions

Generated actions

Cannot be edited directly.

Instead

Edit Blueprint.

Compile again.

---

# 22. Optimization

Compiler merges adjacent actions.

Example

Vendor Stop

↓

Repair Stop

↓

Merged

↓

Vendor Stop

Repair Included

---

# 23. Reusability

One Blueprint

↓

Hundreds of Profiles

↓

Thousands of Expansions

---

# 24. Marketplace (Future)

Blueprint Packages

```
Alliance 1-10

Human Trainer Pack

Best Vendor Stops

Death Skip Library

Dungeon Starts
```

Importable.

---

# 25. Runtime Metadata

Generated actions contain

```rust
generated_from:

QuestHub_01
```

Used for debugging.

Never edited.

---

# 26. Blueprint Graph

```
Quest Hub

├── Pickup

├── Pickup

├── Vendor

├── Repair

├── Train

└── Leave
```

Compiler traverses recursively.

---

# 27. Blueprint Compiler

Pseudo-code

```rust
compile(Blueprint)

↓

Resolve Parameters

↓

Inject Defaults

↓

Resolve Database

↓

Generate Actions

↓

Optimize

↓

Return Runtime Actions
```

---

# 28. QueryServer Integration

Blueprints ask semantic questions.

Examples

```
Nearest Vendor

Nearest Trainer

Nearby Flight Master

Nearby Repair

Nearby Mailbox

Nearest Inn

Quest Chain

Shared Turn-ins

```

The editor never computes these.

---

# 29. Example

Author

```
Quest Hub

↓

Marshal McBride

↓

Accept

↓

Repair
```

Runtime Output

```
Travel

↓

Face NPC

↓

Talk

↓

Pickup Wolves

↓

Pickup Kobolds

↓

Pickup Brotherhood

↓

Vendor

↓

Repair

↓

Continue
```

Author created

1 object.

Compiler created

18 runtime actions.

---

# 30. Philosophy

Blueprints are **authoring assets**.

Actions are **execution primitives**.

The editor should encourage authors to think in Blueprints.

The runtime should never execute Blueprints.

---

# 31. Beyond Honorbuddy

Honorbuddy profiles exposed every primitive step:

```xml
<MoveTo X="..." />
<Interact />
<Wait />
<AcceptQuest />
```

This led to:
- Massive XML files
- High maintenance
- Fragile profiles
- Lots of duplicated logic

With Blueprints:

- One reusable definition replaces dozens of primitive steps.
- Common logic lives in one place.
- Compiler optimizations improve every profile automatically.
- Authors focus on intent rather than implementation.

This moves profile authoring from scripting to designing.

---

# 32. Recommended Built-in Blueprint Set (v1)

### Quest
- Quest Hub
- Single Quest
- Quest Chain
- Turn-in Cluster

### Travel
- Travel Hub
- Flight Unlock
- Hearth Setup
- Route Transition

### Combat
- Grind Area
- Named Mob Hunt
- Rare Spawn Camp
- Escort
- Patrol

### NPC Services
- Vendor Stop
- Trainer Stop
- Repair Stop
- Mailbox Stop
- Bank Stop

### Recovery
- Death Skip
- Corpse Recovery
- Stuck Recovery Marker

### Utility
- Set Variable
- Conditional Branch
- Wait
- Use Item
- Gossip Sequence

These should ship with the editor and cover the vast majority of leveling profile needs while remaining extensible.

---

End of Volume 6
