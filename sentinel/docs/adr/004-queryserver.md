# Quest Authoring IDE
## Volume 4 — QueryServer Architecture

Version: 1.0
Status: Draft

---

# 1. Overview

The QueryServer is a lightweight Rust/Axum HTTP service responsible for
enriching authoring data using the Mangos TBC SQLite database.

It exists for one purpose:

> Turn IDs into knowledge.

The editor should never query SQLite directly.

```
+---------------------------+
| In-Game Editor            |
+-------------+-------------+
              |
          HTTP/JSON
              |
+-------------v-------------+
| QueryServer (Rust/Axum)   |
+-------------+-------------+
              |
         SQLite Queries
              |
+-------------v-------------+
| Mangos TBC Database        |
+---------------------------+
```

---

# 2. Design Goals

The QueryServer should:

- Be stateless
- Be cacheable
- Be deterministic
- Return semantic objects
- Hide database schema
- Support future databases

The editor should never know table names.

---

# 3. Responsibilities

The QueryServer provides:

✓ Quest Search

✓ NPC Lookup

✓ Object Lookup

✓ Creature Lookup

✓ Vendor Lookup

✓ Trainer Lookup

✓ Flight Masters

✓ Innkeepers

✓ Quest Chains

✓ Spawn Locations

✓ Spawn Density

✓ Loot Tables

✓ Drop Chances

✓ Area Queries

✓ Path Analysis

✓ Validation

✓ World Graph

---

# 4. World Graph

Instead of exposing SQL tables...

```
creature_template

creature

npc_vendor

quest_template

```

...the server exposes a semantic graph.

```
Quest

↓

Quest Giver

↓

NPC

↓

Spawn

↓

Zone

↓

Subzone

↓

Nearby Vendors

↓

Nearby Trainers

↓

Nearby Flight Master

↓

Nearby Mailbox

↓

Nearby Bank

↓

Nearby Quests
```

The editor consumes semantic objects.

Not SQL rows.

---

# 5. API Design Principles

REST

JSON

Stable

Versioned

Read-only

No editor state.

No profile state.

No runtime state.

---

# 6. API Versioning

```
/api/v1/
```

Future

```
/api/v2/
```

No breaking changes inside versions.

---

# 7. Quest Endpoints

## Search

```
GET /api/v1/quests/search
```

Parameters

```
query

zone

min_level

max_level

faction

limit
```

Response

```json
[
  {
    "id":33,
    "title":"Wolves Across the Border",
    "level":2,
    "min_level":1,
    "zone":"Elwynn Forest",
    "giver":197
  }
]
```

---

## Quest Details

```
GET /api/v1/quests/{id}
```

Returns

- objectives
- rewards
- chain
- prerequisites
- followups
- exclusive quests
- required items
- required kills

---

## Quest Chain

```
GET /api/v1/quests/{id}/chain
```

Response

```
Accept

↓

Quest

↓

Followups

↓

Branches

↓

End
```

---

## Nearby Quests

```
GET /api/v1/quests/near
```

Parameters

```
zone

x

y

radius
```

Returns every quest inside radius.

---

# 8. NPC Endpoints

## Lookup

```
GET /api/v1/npcs/{entry}
```

Returns

```json
{
  "entry":197,
  "name":"Marshal McBride",
  "roles":[
      "QuestGiver"
  ],
  "zone":"Northshire Abbey"
}
```

---

## Search

```
GET /api/v1/npcs/search
```

Supports

Name

Entry

Role

Faction

Zone

---

## Nearby NPCs

```
GET /api/v1/npcs/near
```

Parameters

```
x

y

radius

zone
```

Returns

Quest Givers

Vendors

Trainers

Innkeepers

Repair

Mailbox

Flight Master

---

# 9. Creature Endpoints

```
GET /api/v1/creatures/search
```

Filters

Name

Family

Faction

Zone

Level

Elite

---

## Spawn Locations

```
GET /api/v1/creatures/{entry}/spawns
```

Returns

```
Spawn Points

Respawn

Density

Average Count
```

---

# 10. Vendor Endpoints

```
GET /api/v1/vendors/{entry}
```

Returns

Items

Prices

Limited Supply

Repair

Ammo

Food

Drink

---

# 11. Trainer Endpoints

```
GET /api/v1/trainers/{entry}
```

Returns

Class

Spells

Level Requirements

Costs

---

# 12. Flight Master

```
GET /api/v1/flightmasters
```

Returns

Node

Faction

Connected Routes

---

# 13. Mailboxes

```
GET /api/v1/mailboxes
```

---

# 14. Inns

```
GET /api/v1/innkeepers
```

Returns

Rest Area

Hearth

---

# 15. Area Queries

This is one of the most important APIs.

```
POST /api/v1/areas/query
```

Request

```json
{
  "zone":"Elwynn",

  "polygon":[

    [12,44],

    [20,45],

    [25,50]
  ]
}
```

Returns

NPCs

Objects

Creatures

Spawn Density

Loot Sources

Quest Objectives

---

# 16. Polygon Analysis

Given a polygon...

Determine

Average mob density

Respawn

Unique creatures

Quest overlap

Elite mobs

Aggro risk

Average travel

---

# 17. Route Analysis

```
POST /api/v1/routes/analyze
```

Request

Waypoints

Response

Distance

Travel Time

Elevation

Zone Crossings

Suggested Split

---

# 18. Quest Hub Analysis

```
GET /api/v1/hubs/{entry}
```

Returns

Available Quests

Nearby Vendor

Nearby Trainer

Nearby Mailbox

Nearby Flight

Nearby Repair

Nearby Inn

Nearby Bank

---

# 19. Validation API

```
POST /api/v1/validate
```

Request

Profile Fragment

Returns

Warnings

Errors

Suggestions

Database Issues

---

# 20. Search Everywhere

```
GET /api/v1/search
```

Returns

NPCs

Quests

Items

Objects

Zones

Creatures

Vendors

Trainers

One endpoint.

Entire database.

---

# 21. Blueprint Suggestions

```
POST /api/v1/blueprints/suggest
```

Example

Send

```
NPC

Quest

Vendor
```

Returns

```
Quest Hub Blueprint
```

---

# 22. Grind Suggestions

```
POST /api/v1/grind/suggest
```

Input

Polygon

Returns

Best Creatures

Drop Rates

XP/hour

Suggested Loot

Quest Overlap

---

# 23. Loot Lookup

```
GET /api/v1/items/{id}/drops
```

Returns

Creature

Drop %

Average Count

Spawn Area

---

# 24. World Graph

```
GET /api/v1/worldgraph/node/{id}
```

Returns connected graph

Quest

↓

NPC

↓

Vendor

↓

Trainer

↓

Flight

↓

Zone

↓

Objects

↓

Loot

This powers intelligent suggestions.

---

# 25. Caching

Recommended

Memory Cache

60 seconds

NPC

Quest

Creature

Vendor

Trainer

Area Queries

LRU eviction.

---

# 26. Performance Targets

NPC Lookup

<5ms

Quest Search

<10ms

Polygon Query

<40ms

Spawn Density

<20ms

Route Analysis

<20ms

---

# 27. Internal Modules

```
queryserver

├── api
├── services
├── graph
├── sqlite
├── cache
├── validation
├── analytics
└── models
```

---

# 28. SQLite Layer

Never exposed.

Responsible for

Prepared Statements

Indexes

Transactions

Caching

Migration

---

# 29. Future Providers

QueryServer is provider-based.

```
trait WorldProvider {

    fn quest();

    fn npc();

    fn creature();

    fn vendor();

}
```

Future implementations

Classic

Wrath

Cata

Custom Servers

Retail

---

# 30. Why QueryServer Exists

Without QueryServer

```
Editor

↓

SQLite

↓

Tables

↓

Joins

↓

Complex SQL
```

With QueryServer

```
Editor

↓

QuestHub

↓

Semantic API

↓

Knowledge

```

The editor asks:

> "What's near this quest?"

Not

> "SELECT * FROM creature..."

This separation keeps the editor simple, the database abstracted, and allows the semantic layer to evolve independently of the underlying Mangos schema.

---

# 31. Design Improvement: World Knowledge Engine

Rather than treating QueryServer as a thin REST wrapper over SQLite, I would evolve it into a **World Knowledge Engine**. Besides exposing raw entities, it should answer higher-level questions that directly support authoring:

- "What quest hubs are within 500 yards?"
- "Which quests share the same travel route?"
- "Which vendor minimizes travel after this operation?"
- "Which grind area overlaps the most active objectives?"
- "If I record this polygon, what creatures and quest objectives does it naturally support?"

This keeps optimization logic out of the editor while making the editor feel intelligent.

---

End of Volume 4
