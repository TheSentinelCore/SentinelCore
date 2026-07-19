//! Reference types — Volume 5 §"NPC Reference", "Quest Reference", "Vendor Entry"
//! 
//! See: docs/adr/005-schema.md, docs/adr/007-operations.md

use serde::{Deserialize, Serialize};

use crate::enums::NpcRole;
use crate::geometry::Waypoint;

/// NPC Reference — Volume 5 §"NPC Reference"
/// 
/// Single source of truth for NPC data. Referenced by actions, not embedded.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct NpcReference {
    pub entry: u32,
    pub guid: Option<String>,
    pub name: String,
    pub zone: String,
    pub position: Waypoint,
    pub roles: Vec<NpcRole>,
}

impl NpcReference {
    pub fn new(entry: u32, name: impl Into<String>, zone: impl Into<String>, position: Waypoint) -> Self {
        Self {
            entry,
            guid: None,
            name: name.into(),
            zone: zone.into(),
            position,
            roles: Vec::new(),
        }
    }
    
    pub fn with_guid(mut self, guid: impl Into<String>) -> Self {
        self.guid = Some(guid.into());
        self
    }
    
    pub fn with_roles(mut self, roles: Vec<NpcRole>) -> Self {
        self.roles = roles;
        self
    }
    
    pub fn has_role(&self, role: NpcRole) -> bool {
        self.roles.contains(&role)
    }
}

/// Quest Reference — Volume 5 §"Quest Reference"
/// 
/// Minimal quest identifier. Full details resolved via QueryServer at compile time.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuestReference {
    pub id: u32,
    pub title: String,
    pub giver: u32,
    pub turn_in: u32,
}

impl QuestReference {
    pub fn new(id: u32, title: impl Into<String>, giver: u32, turn_in: u32) -> Self {
        Self { id, title: title.into(), giver, turn_in }
    }
}

/// Vendor Entry — Volume 5 §"Vendor Entry"
/// 
/// Vendor with items and repair capability.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct VendorEntry {
    pub npc: NpcReference,
    pub sells: Vec<ItemReference>,
    pub repairs: bool,
}

/// Item Reference — Volume 5 §"ItemReference" (referenced by VendorEntry, GrindAreaAction)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemReference {
    pub id: u32,
    pub name: String,
    pub count: u32,
}

impl ItemReference {
    pub fn new(id: u32, name: impl Into<String>, count: u32) -> Self {
        Self { id, name: name.into(), count }
    }
}

/// Creature Reference — Volume 5 §"CreatureReference" (for GrindAreaAction targets)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct CreatureReference {
    pub entry: u32,
    pub name: String,
}

impl CreatureReference {
    pub fn new(entry: u32, name: impl Into<String>) -> Self {
        Self { entry, name: name.into() }
    }
}

/// Game Object Reference — Volume 5 §"GameObjectReference" (for LootObjectAction)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GameObjectReference {
    pub entry: u32,
    pub name: String,
}

impl GameObjectReference {
    pub fn new(entry: u32, name: impl Into<String>) -> Self {
        Self { entry, name: name.into() }
    }
}

/// Flight Node — Volume 5 §"FlightAction"
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct FlightNode {
    pub id: u32,
    pub name: String,
}

impl FlightNode {
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self { id, name: name.into() }
    }
}

/// Hearth Location — Volume 5 §"HearthAction"
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct HearthLocation {
    pub zone: String,
    pub innkeeper: u32,
}

impl HearthLocation {
    pub fn new(zone: impl Into<String>, innkeeper: u32) -> Self {
        Self { zone: zone.into(), innkeeper }
    }
}