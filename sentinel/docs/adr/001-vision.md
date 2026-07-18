# Quest Authoring IDE
## Volume 1 — Vision, Philosophy & Architecture

Version: 1.0
Status: Draft
Target Runtime: Project Sylvanas (WoW TBC 2.4.3)
Target Language: Rust
Target UI: In-game Overlay (ImGui-style assumed until Sylvanas Addons API confirms otherwise)

---

# 1. Executive Summary

The Quest Authoring IDE is an in-game development environment for creating,
editing, validating and testing questing profiles directly while playing World
of Warcraft.

Unlike historical systems such as Honorbuddy profiles, the author never edits
execution logic directly.

Instead, the author describes intent.

The editor assists the author by capturing live game information,
cross-referencing a Mangos database, validating the profile, and generating
a deterministic runtime profile consumed by the existing Project Sylvanas
execution engine.

The runtime remains intentionally simple.

The editor remains intelligent.

The compiler sits between them.

---

# 2. Goals

The project has six primary goals.

## Goal 1

Create quest profiles without leaving the game.

The author should never need to:

- Alt-tab
- Edit XML
- Edit JSON
- Copy coordinates manually
- Look up NPC IDs
- Search Wowhead

Everything should be capturable directly from gameplay.

---

## Goal 2

Profiles describe intent.

Not implementation.

Good

```
Pickup Quest

↓

Travel

↓

Kill Wolves

↓

Turn In
```

Bad

```
Waypoint 123

Waypoint 124

Waypoint 125

Turn 15°

Interact

Delay

Interact Again

Verify

Continue
```

The runtime decides *how* to accomplish the task.

The author decides *what* should happen.

---

## Goal 3

Minimize duplicated information.

Everything already stored in Mangos should remain in Mangos.

Examples:

- NPC names
- Quest names
- Spawn locations
- Flight masters
- Vendors
- Trainers
- Quest chains
- Drop tables
- Objects

Profiles should reference IDs rather than duplicating metadata.

---

## Goal 4

Profiles must remain readable.

An operation should read like documentation.

Example

```
Northshire Cleanup

• Accept Wolves Across the Border
• Accept Kobold Camp Cleanup
• Kill Wolves
• Loot Meat
• Turn In
• Repair
• Continue
```

Not

```
NPC 197

Quest 783

Waypoint 441

Interact 2

Condition

Variable

Branch

```

---

## Goal 5

Support live editing.

Authors should be able to

- capture NPCs
- edit actions
- reorder operations
- validate
- dry run
- save
- reload

without restarting the client.

---

## Goal 6

Runtime simplicity.

Every complex decision belongs in authoring.

Not runtime.

---

# 3. Non-Goals

The editor is NOT responsible for

- Combat logic
- Navigation
- Pathfinding
- Mesh generation
- Object detection
- Bot state machines
- Memory reading
- Packet manipulation

Those already exist elsewhere.

The editor produces profiles.

Nothing more.

---

# 4. Core Philosophy

Every historical questing framework has made the same mistake.

They expose implementation.

Honorbuddy XML

RestedXP

Older Zygor guides

all expose runtime behavior.

Eventually profiles become impossible to maintain.

Instead:

Author

↓

Intent

↓

Compiler

↓

Runtime

The runtime should never need to infer author intent.

The compiler already did that.

---

# 5. Design Principles

Every future decision should follow these principles.

## Principle 1

Intent over implementation.

Never expose runtime details unless debugging.

---

## Principle 2

Capture, don't type.

Prefer

Target NPC

↓

Capture

over

```
NPC ID:
________
```

---

## Principle 3

Everything references the database.

No duplicated names.

No duplicated coordinates.

No duplicated quest chains.

---

## Principle 4

Author once.

Reuse everywhere.

Operations.

Blueprints.

Variables.

Templates.

Everything reusable.

---

## Principle 5

Profiles remain deterministic.

Runtime execution should produce identical behavior given identical world state.

No hidden randomness.

---

## Principle 6

Validation should happen immediately.

Every edit produces diagnostics.

Never wait until runtime.

---

## Principle 7

Author visually.

Maps.

Pins.

Recorded paths.

Polygons.

NPC capture.

Minimal typing.

---

# 6. Architecture

```
                  In-Game Editor

                Capture / Edit

                        │

                        ▼

                 Authoring Profile

                        │

             Compile + Validate

                        │

                        ▼

             Runtime Quest Profile

                        │

                        ▼

          Existing Quest Execution Engine

                        │

                        ▼

                Navigation Layer

                        │

                        ▼

                     Game
```

---

# 7. Why A Compile Step Exists

Even though editing occurs in-game,
the runtime profile should never be edited directly.

Instead:

```
Author

↓

Validate

↓

Resolve Database References

↓

Expand Templates

↓

Generate Runtime Actions

↓

Executor
```

Benefits

- Version migrations
- Better validation
- Runtime optimization
- Stable execution format
- Future desktop IDE compatibility

---

# 8. Terminology

## Workspace

Entire project.

Example

Alliance Questing

---

## Campaign

A complete leveling route.

Example

Alliance Human 1–60

---

## Chapter

A zone or logical progression.

Examples

Northshire

Goldshire

Westfall

Redridge

---

## Operation

A reusable sequence of actions.

Example

Northshire Abbey Quest Hub

---

## Action

Single executable instruction.

Examples

Pickup Quest

Vendor

Repair

Travel

Kill

Escort

Wait

---

## Blueprint

Reusable authoring template.

Examples

Quest Hub

Vendor Stop

Flight Master

Innkeeper

Dungeon Entrance

Death Skip

---

## Runtime Profile

Compiled executable representation.

Never edited manually.

---

# 9. Why Operations Instead of One Huge Timeline

Operations provide

- reuse
- testing
- independent validation
- modularity

Instead of

```
Human 1-60

5000 actions
```

Use

```
Northshire

Goldshire

Eastvale

Westfall

Redridge
```

Each operation remains understandable.

---

# 10. Why Blueprints Exist

Quest hubs repeat.

Rather than manually author

Accept

Vendor

Repair

Mailbox

Trainer

Flight Master

Turn In

Accept Followups

Every time...

Capture once.

Save as Blueprint.

Reuse forever.

---

# 11. Database First

The Mangos database is treated as the authoritative world model.

The editor should never ask the author for information that already exists.

Examples

Typing

```
Quest ID

NPC ID

Coordinates

```

is considered a UX failure.

---

# 12. Validation Philosophy

Validation is continuous.

Every modification immediately checks

- Missing NPCs
- Duplicate quests
- Broken quest chains
- Invalid references
- Missing coordinates
- Circular branches
- Unreachable actions

Errors prevent compilation.

Warnings do not.

---

# 13. Dry Run

Dry Run executes the profile logically.

No combat.

No movement.

No interaction.

Instead:

```
Action 1

✓

Action 2

✓

Action 3

⚠ Missing NPC

Action 4

Skipped
```

---

# 14. Versioning

Every profile begins with

```
schema_version
```

Future migrations never modify runtime behavior directly.

Instead

Old Version

↓

Migration

↓

Latest Authoring Format

↓

Compile

↓

Runtime

---

# 15. Success Criteria

The project succeeds when an experienced player can:

• Walk through Elwynn Forest.
• Target quest givers.
• Capture vendors.
• Record travel paths.
• Draw grind polygons.
• Search quests.
• Validate.
• Dry run.
• Save.

…without ever editing JSON or XML manually.

If an author needs to open a text editor to create a normal quest profile,
the Quest Authoring IDE has failed its primary objective.

---

End of Volume 1
