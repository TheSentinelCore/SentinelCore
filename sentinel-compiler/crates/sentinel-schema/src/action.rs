//! Action types — Volume 5 §"Action", "Action Payload", and all specific actions
//! 
//! See: docs/adr/005-schema.md, docs/adr/007-operations.md

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::reference::*;
use crate::geometry::*;
use crate::condition::*;
use crate::enums::*;

/// Action — Volume 5 §"Action"
/// 
/// Every timeline item is an Action with a specific payload variant.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Action {
    pub id: Uuid,
    pub enabled: bool,
    pub name: String,
    pub notes: Option<String>,
    pub tags: Vec<String>,
    pub retry_policy: RetryPolicy,
    pub timeout_ms: u64,
    pub conditions: Vec<Condition>,
    pub payload: ActionPayload,
}

impl Action {
    pub fn new(name: impl Into<String>, payload: ActionPayload) -> Self {
        Self {
            id: Uuid::new_v4(),
            enabled: true,
            name: name.into(),
            notes: None,
            tags: Vec::new(),
            retry_policy: RetryPolicy::default(),
            timeout_ms: 30000,
            conditions: Vec::new(),
            payload,
        }
    }
    
    pub fn with_id(mut self, id: Uuid) -> Self {
        self.id = id;
        self
    }
    
    pub fn disabled(mut self) -> Self {
        self.enabled = false;
        self
    }
    
    pub fn with_retry(mut self, retries: u32, delay_ms: u64) -> Self {
        self.retry_policy = RetryPolicy::new(retries, delay_ms);
        self
    }
    
    pub fn with_timeout(mut self, timeout_ms: u64) -> Self {
        self.timeout_ms = timeout_ms;
        self
    }
    
    pub fn with_condition(mut self, condition: Condition) -> Self {
        self.conditions.push(condition);
        self
    }
}

/// Action Payload — Volume 5 §"Action Payload"
/// 
/// Exhaustive enum ensures compile-time safety.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload", rename_all = "PascalCase")]
pub enum ActionPayload {
    PickupQuest(PickupQuestAction),
    TurnInQuest(TurnInQuestAction),
    GoTo(GoToAction),
    RecordPath(RecordPathAction),
    Patrol(PatrolAction),
    Escort(EscortAction),
    GrindArea(GrindAreaAction),
    KillTarget(KillTargetAction),
    LootObject(LootObjectAction),
    TalkToNpc(TalkToNpcAction),
    Vendor(VendorAction),
    Repair(RepairAction),
    Train(TrainAction),
    FlightPath(FlightAction),
    Hearth(HearthAction),
    Mailbox(MailboxAction),
    Bank(BankAction),
    UseItem(UseItemAction),
    Wait(WaitAction),
    SetVariable(SetVariableAction),
    Branch(BranchAction),
    DungeonMarker(DungeonMarkerAction),
    DeathSkip(DeathSkipAction),
}

/// Pickup Quest — Volume 5 §"Pickup Quest"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PickupQuestAction {
    pub quest: QuestReference,
    pub npc: NpcReference,
    pub auto_complete_previous: bool,
}

/// Turn In Quest — Volume 5 §"Turn In Quest"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TurnInQuestAction {
    pub quest: QuestReference,
    pub npc: NpcReference,
}

/// Go To — Volume 5 §"Go To"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GoToAction {
    pub destination: Waypoint,
    pub arrival_radius: f32,
}

/// Record Path — Volume 5 §"Record Path"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecordPathAction {
    pub path: Path,
    pub smoothing: PathSmoothing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum PathSmoothing {
    None,
    Chaikin,
    CatmullRom,
    Bezier,
}

/// Patrol — Volume 5 §"Patrol"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PatrolAction {
    pub path: Path,
    pub wait_at_waypoints: bool,
    pub wait_duration_ms: u64,
}

/// Escort — Volume 5 §"Escort"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EscortAction {
    pub npc: NpcReference,
    pub path: Path,
    pub protect: bool,
}

/// Grind Area — Volume 5 §"Grind Area"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GrindAreaAction {
    pub polygon: Polygon,
    pub targets: Vec<CreatureReference>,
    pub stop_condition: StopCondition,
    pub loot: Vec<ItemReference>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "PascalCase")]
pub enum StopCondition {
    QuestComplete,
    ItemCount(u32, u32), // item_id, count
    KillCount(u32, u32), // creature_id, count
    TimeLimit(u64),      // milliseconds
    LevelReached(u8),
    Manual,
}

/// Kill Target — Volume 5 §"Kill Target"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct KillTargetAction {
    pub targets: Vec<CreatureReference>,
    pub amount: Option<u32>,
}

/// Loot Object — Volume 5 §"Loot Object"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LootObjectAction {
    pub objects: Vec<GameObjectReference>,
}

/// Talk To NPC — Volume 5 (for gossip, flight, etc.)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TalkToNpcAction {
    pub npc: NpcReference,
    pub gossip_option: Option<String>,
}

/// Vendor — Volume 5 §"Vendor"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VendorAction {
    pub vendor: VendorEntry,
    pub repair: bool,
    pub sell_gray: bool,
    pub sell_white: bool,
    pub buy: Vec<PurchaseRule>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PurchaseRule {
    pub item: ItemReference,
    pub max_count: u32,
    pub condition: Option<Condition>,
}

/// Repair — Volume 5 §"Repair"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RepairAction {
    pub vendor: VendorEntry,
}

/// Train — Volume 5 §"Train"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrainAction {
    pub trainer: NpcReference,
    pub class: Class,
}

/// Flight Path — Volume 5 §"Flight"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FlightAction {
    pub from: FlightNode,
    pub to: FlightNode,
}

/// Hearth — Volume 5 §"Hearth"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HearthAction {
    pub destination: HearthLocation,
}

/// Mailbox — Volume 5 §"Mailbox"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MailboxAction {
    pub mailbox: NpcReference,
}

/// Bank — Volume 5 §"Bank"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BankAction {
    pub banker: NpcReference,
}

/// Use Item — Volume 5 §"Use Item"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UseItemAction {
    pub item: ItemReference,
    pub target: Option<NpcReference>,
}

/// Wait — Volume 5 §"Wait"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WaitAction {
    pub duration_ms: u64,
}

/// Set Variable — Volume 5 §"Set Variable"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SetVariableAction {
    pub variable: String,
    pub value: VariableValue,
}

/// Branch — Volume 5 §"Branch"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BranchAction {
    pub expression: Condition,
    pub true_actions: Vec<Uuid>,
    pub false_actions: Vec<Uuid>,
}

/// Dungeon Marker — Volume 5 §"Dungeon Marker"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DungeonMarkerAction {
    pub dungeon_name: String,
    pub entrance: Waypoint,
}

/// Death Skip — Volume 5 §"Death Skip"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeathSkipAction {
    pub graveyard: Waypoint,
    pub spirit_healer: NpcReference,
}

/// Retry Policy — Volume 5 §"Retry Policy"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RetryPolicy {
    pub retries: u32,
    pub delay_ms: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self { retries: 3, delay_ms: 1000 }
    }
}

impl RetryPolicy {
    pub fn new(retries: u32, delay_ms: u64) -> Self {
        Self { retries, delay_ms }
    }
}