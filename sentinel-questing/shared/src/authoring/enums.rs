//! Closed vocabulary enums shared across the authoring model.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum Faction {
    Alliance,
    Horde,
    Neutral,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum Race {
    Human,
    Orc,
    Dwarf,
    NightElf,
    Undead,
    Tauren,
    Gnome,
    Troll,
    BloodElf,
    Draenei,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum Class {
    Warrior,
    Paladin,
    Hunter,
    Rogue,
    Priest,
    Shaman,
    Mage,
    Warlock,
    Druid,
}

/// Only world coordinates are stored in compiled output (ADR-203). The authoring model records
/// the same `World` mode; map coordinates are importer-only and never persisted here.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "PascalCase")]
pub enum CoordinateMode {
    #[default]
    World,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum Severity {
    Info,
    Warning,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum NpcRole {
    QuestGiver,
    Vendor,
    Trainer,
    Repair,
    FlightMaster,
    Innkeeper,
    Mailbox,
    Banker,
    Auctioneer,
    Generic,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum VariableType {
    Bool,
    Int,
    Float,
    String,
    QuestId,
    NpcId,
}

/// A typed value for [`Variable`] (ADR `02_DATA_MODEL` §7).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum VariableValue {
    Bool(bool),
    Int(i64),
    Float(f64),
    String(String),
    QuestId(u32),
    NpcId(u32),
}
