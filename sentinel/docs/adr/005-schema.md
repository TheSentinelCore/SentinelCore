# Quest Authoring IDE
## Volume 5 — Canonical Profile Schema

Version: 1.0
Status: Canonical Specification

---

# Philosophy

This is **not** the execution engine.

This is **not** a state machine.

This is **not** an XML script.

This is the canonical authoring schema.

Everything in the editor manipulates these structures.

The runtime compiler transforms this schema into an optimized execution graph.

The execution engine never edits these objects.

---

# Overall Hierarchy

```text
Workspace
│
├── Profiles
│
│   ├── Operations
│   │
│   │   ├── Actions
│   │   ├── Variables
│   │   ├── Conditions
│   │   └── Metadata
│   │
│   ├── NPC Library
│   ├── Quest Library
│   ├── Vendor Library
│   ├── Blueprint Library
│   └── Analytics
│
└── Runtime Cache
```

---

# Root Profile

```rust
pub struct Profile {

    pub schema_version: String,

    pub profile_id: Uuid,

    pub name: String,

    pub author: String,

    pub description: String,

    pub game: GameVersion,

    pub faction: Faction,

    pub race: Option<Race>,

    pub class: Option<Class>,

    pub level_range: LevelRange,

    pub tags: Vec<String>,

    pub metadata: Metadata,

    pub settings: ProfileSettings,

    pub variables: Vec<Variable>,

    pub npc_library: Vec<NpcReference>,

    pub quest_library: Vec<QuestReference>,

    pub vendor_library: Vec<VendorEntry>,

    pub blueprints: Vec<BlueprintReference>,

    pub operations: Vec<Operation>

}
```

---

# Metadata

```rust
pub struct Metadata {

    pub created_at: DateTime<Utc>,

    pub updated_at: DateTime<Utc>,

    pub editor_version: String,

    pub compiler_version: String,

    pub notes: Option<String>,

    pub source: SourceType,

}
```

---

# Profile Settings

```rust
pub struct ProfileSettings {

    pub auto_vendor: bool,

    pub auto_repair: bool,

    pub auto_train: bool,

    pub auto_loot: bool,

    pub auto_accept: bool,

    pub auto_turnin: bool,

    pub use_flight_paths: bool,

    pub allow_hearthstone: bool,

    pub use_mailbox: bool,

    pub death_skip: bool,

    pub dry_run_enabled: bool,

}
```

---

# Operation

Operations are the largest executable authoring unit.

Examples

```
Northshire

Goldshire

Westbrook

Eastvale

Redridge
```

```rust
pub struct Operation {

    pub id: Uuid,

    pub name: String,

    pub description: String,

    pub enabled: bool,

    pub level_range: LevelRange,

    pub priority: u32,

    pub tags: Vec<String>,

    pub conditions: Vec<Condition>,

    pub variables: Vec<Variable>,

    pub actions: Vec<Action>,

}
```

---

# Action

Every timeline item is an Action.

```rust
pub struct Action {

    pub id: Uuid,

    pub enabled: bool,

    pub name: String,

    pub notes: Option<String>,

    pub tags: Vec<String>,

    pub retry_policy: RetryPolicy,

    pub timeout: Duration,

    pub conditions: Vec<Condition>,

    pub payload: ActionPayload,

}
```

---

# Action Payload

```rust
pub enum ActionPayload {

    PickupQuest,

    TurnInQuest,

    GoTo,

    RecordPath,

    Patrol,

    Escort,

    GrindArea,

    KillTarget,

    LootObject,

    TalkToNpc,

    Vendor,

    Repair,

    Train,

    FlightPath,

    Hearth,

    Mailbox,

    Bank,

    UseItem,

    Wait,

    SetVariable,

    Branch,

    DungeonMarker,

    DeathSkip,

}
```

---

# Pickup Quest

```rust
pub struct PickupQuestAction {

    pub quest: QuestReference,

    pub npc: NpcReference,

    pub auto_complete_previous: bool,

}
```

---

# Turn In Quest

```rust
pub struct TurnInQuestAction {

    pub quest: QuestReference,

    pub npc: NpcReference,

}
```

---

# Go To

```rust
pub struct GoToAction {

    pub destination: Waypoint,

    pub arrival_radius: f32,

}
```

---

# Record Path

```rust
pub struct PathAction {

    pub path: Path,

    pub smoothing: PathSmoothing,

}
```

---

# Grind Area

```rust
pub struct GrindAreaAction {

    pub polygon: Polygon,

    pub targets: Vec<CreatureReference>,

    pub stop_condition: StopCondition,

    pub loot: Vec<ItemReference>,

}
```

---

# Kill Target

```rust
pub struct KillTargetAction {

    pub targets: Vec<CreatureReference>,

    pub amount: Option<u32>,

}
```

---

# Loot Object

```rust
pub struct LootObjectAction {

    pub objects: Vec<GameObjectReference>,

}
```

---

# Vendor

```rust
pub struct VendorAction {

    pub vendor: VendorEntry,

    pub repair: bool,

    pub sell_gray: bool,

    pub sell_white: bool,

    pub buy: Vec<PurchaseRule>,

}
```

---

# Repair

```rust
pub struct RepairAction {

    pub vendor: VendorEntry,

}
```

---

# Train

```rust
pub struct TrainAction {

    pub trainer: NpcReference,

    pub class: Class,

}
```

---

# Flight

```rust
pub struct FlightAction {

    pub from: FlightNode,

    pub to: FlightNode,

}
```

---

# Hearth

```rust
pub struct HearthAction {

    pub destination: HearthLocation,

}
```

---

# Mailbox

```rust
pub struct MailboxAction {

    pub mailbox: NpcReference,

}
```

---

# Bank

```rust
pub struct BankAction {

    pub banker: NpcReference,

}
```

---

# Wait

```rust
pub struct WaitAction {

    pub duration: Duration,

}
```

---

# Set Variable

```rust
pub struct SetVariableAction {

    pub variable: String,

    pub value: VariableValue,

}
```

---

# Branch

```rust
pub struct BranchAction {

    pub expression: Condition,

    pub true_actions: Vec<Uuid>,

    pub false_actions: Vec<Uuid>,

}
```

---

# NPC Reference

```rust
pub struct NpcReference {

    pub entry: u32,

    pub guid: Option<String>,

    pub name: String,

    pub zone: String,

    pub position: Waypoint,

    pub roles: Vec<NpcRole>,

}
```

Roles

```
QuestGiver

Vendor

Trainer

Innkeeper

FlightMaster

Repair

Mailbox

Bank

Auctioneer

SpiritHealer

Generic
```

Multiple roles allowed.

---

# Quest Reference

```rust
pub struct QuestReference {

    pub id: u32,

    pub title: String,

    pub giver: u32,

    pub turn_in: u32,

}
```

---

# Vendor Entry

```rust
pub struct VendorEntry {

    pub npc: NpcReference,

    pub sells: Vec<ItemReference>,

    pub repairs: bool,

}
```

---

# Waypoint

```rust
pub struct Waypoint {

    pub map: u32,

    pub zone: String,

    pub x: f32,

    pub y: f32,

    pub z: f32,

    pub radius: f32,

}
```

---

# Path

```rust
pub struct Path {

    pub points: Vec<Waypoint>,

}
```

---

# Polygon

```rust
pub struct Polygon {

    pub vertices: Vec<Waypoint>,

}
```

---

# Variables

```rust
pub struct Variable {

    pub name: String,

    pub value: VariableValue,

}
```

---

# Variable Types

```rust
pub enum VariableValue {

    Bool(bool),

    Integer(i64),

    Float(f64),

    String(String),

    Position(Waypoint),

}
```

---

# Conditions

```rust
pub enum Condition {

    QuestAccepted(u32),

    QuestCompleted(u32),

    QuestRewarded(u32),

    LevelAtLeast(u8),

    LevelBelow(u8),

    HasItem(u32),

    BagSpace(u32),

    DurabilityBelow(f32),

    GoldAbove(u32),

    VariableEquals(String),

    VariableTrue(String),

    VariableFalse(String),

}
```

---

# Retry Policy

```rust
pub struct RetryPolicy {

    pub retries: u32,

    pub delay: Duration,

}
```

---

# Blueprint Reference

```rust
pub struct BlueprintReference {

    pub id: String,

    pub version: String,

}
```

Examples

```
QuestHub

VendorStop

TrainerStop

Escort

Mailbox

DeathSkip

GrindArea

```

---

# Analytics

```rust
pub struct Analytics {

    pub average_time: Duration,

    pub average_xp: f64,

    pub average_gold: f64,

    pub deaths: u32,

}
```

---

# Design Decisions

## Why UUIDs?

Actions remain stable while being reordered.

References never break.

---

## Why Libraries?

Instead of duplicating NPCs:

```
Marshal McBride

Marshal McBride

Marshal McBride
```

Store once.

Reference everywhere.

---

## Why Operations?

Operations compile independently.

Faster validation.

Better hot reload.

---

## Why Payload Enums?

Compile-time safety.

Rust exhaustive matching.

No stringly-typed action dispatch.

---

## Why References Instead of Embedded Objects?

Single source of truth.

NPC updates propagate automatically.

Vendor changes affect every action.

---

## Schema Versioning

```text
1.0.0
```

Future migrations

```
1.0 → 1.1

Migration Script

↓

Validation

↓

Save
```

No runtime compatibility hacks.

---

# Example

```text
Profile

 ├── NPC Library

 │     Marshal McBride

 │     Brother Neals

 │     Innkeeper Farley

 │

 ├── Quest Library

 │     Wolves Across the Border

 │     Kobold Camp Cleanup

 │

 └── Operations

        Northshire

            Pickup Quest

            Pickup Quest

            Go To

            Grind Area

            Turn In

            Vendor

            Go To
```

---

# Canonical Rule

**The editor owns this schema.**

The compiler reads this schema.

The runtime never mutates this schema.

Everything else in the system exists to support these data structures.

---

End of Volume 5
