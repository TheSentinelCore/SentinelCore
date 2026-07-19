//! Standard Blueprint Definitions — Volume 6 §32
//!
//! This module provides the built-in blueprint templates that ship with SentinelCore.
//! These cover the vast majority of quest automation authoring needs.
//!
//! See: docs/adr/006-blueprints.md §32

use crate::blueprint::{Blueprint, BlueprintParameter, ParameterType, ParameterValue};
use crate::enums::BlueprintCategory;
use crate::reference::VendorEntry;

// ============================================================================
// Quest Category Blueprints
// ============================================================================

/// Quest Hub — Volume 6 §5, §32
///
/// Handles complete quest hub interaction: travel, pickup quests, vendor, repair,
/// train, hearth, flight, and departure.
pub fn quest_hub_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Quest Hub", BlueprintCategory::Quest);
    bp.description = "Complete quest hub interaction: pickup, vendor, repair, train, travel".to_string();
    bp.icon = "quest_hub.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::optional(
            "QuestGiver",
            ParameterType::Npc,
            "The quest giver NPC",
            ParameterValue::Npc(crate::reference::NpcReference::default()),
        ),
        BlueprintParameter::optional(
            "Vendor",
            ParameterType::Vendor,
            "The vendor NPC for selling/repair",
            ParameterValue::Vendor(VendorEntry::default()),
        ),
        BlueprintParameter::optional(
            "Trainer",
            ParameterType::Trainer,
            "The trainer NPC for skill training",
            ParameterValue::Trainer(crate::reference::NpcReference::default()),
        ),
        BlueprintParameter::optional(
            "Repair",
            ParameterType::Boolean,
            "Enable repair",
            ParameterValue::Boolean(true),
        ),
        BlueprintParameter::optional(
            "Train",
            ParameterType::Boolean,
            "Enable training",
            ParameterValue::Boolean(true),
        ),
        BlueprintParameter::optional(
            "AcceptAll",
            ParameterType::Boolean,
            "Accept all available quests",
            ParameterValue::Boolean(true),
        ),
    ];
    // Outputs are filled during expansion with resolved parameters
    bp
}

/// Single Quest — Volume 6 §32
pub fn single_quest_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Single Quest", BlueprintCategory::Quest);
    bp.description = "Accept, complete, and turn in a single quest".to_string();
    bp.icon = "single_quest.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Quest", ParameterType::Quest, "The quest to complete"),
        BlueprintParameter::optional("Target", ParameterType::Npc, "Quest giver and turn-in NPC", ParameterValue::Npc(crate::reference::NpcReference::default())),
    ];
    bp
}

/// Quest Chain — Volume 6 §32
pub fn quest_chain_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Quest Chain", BlueprintCategory::Quest);
    bp.description = "Complete a chain of related quests".to_string();
    bp.icon = "quest_chain.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Quests", ParameterType::Quest, "The quest chain to complete"),
    ];
    bp
}

/// Turn-in Cluster — Volume 6 §32
pub fn turnin_cluster_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Turn-in Cluster", BlueprintCategory::Quest);
    bp.description = "Turn in multiple quests at one or more NPCs".to_string();
    bp.icon = "turnin_cluster.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Quests", ParameterType::Quest, "The quests to turn in"),
        BlueprintParameter::optional("NPCs", ParameterType::Npc, "NPCs to turn in at", ParameterValue::Npc(crate::reference::NpcReference::default())),
    ];
    bp
}

// ============================================================================
// Travel Category Blueprints
// ============================================================================

/// Travel Hub — Volume 6 §32
pub fn travel_hub_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Travel Hub", BlueprintCategory::Travel);
    bp.description = "Travel to a zone with optional inn-bound hearth".to_string();
    bp.icon = "travel_hub.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Destination", ParameterType::Waypoint, "Target zone/location"),
        BlueprintParameter::optional("Innkeeper", ParameterType::Npc, "Optional inn to set hearth", ParameterValue::Npc(crate::reference::NpcReference::default())),
        BlueprintParameter::optional("UseHearth", ParameterType::Boolean, "Use hearthstone if available", ParameterValue::Boolean(true)),
    ];
    bp
}

/// Flight Unlock — Volume 6 §32
pub fn flight_unlock_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Flight Unlock", BlueprintCategory::Travel);
    bp.description = "Unlock a new flight path".to_string();
    bp.icon = "flight_unlock.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("FlightMaster", ParameterType::Npc, "The flight master NPC"),
        BlueprintParameter::required("FlightPath", ParameterType::Flight, "The flight path to unlock"),
    ];
    bp
}

/// Hearth Setup — Volume 6 §32
pub fn hearth_setup_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Hearth Setup", BlueprintCategory::Travel);
    bp.description = "Set hearthstone at an inn".to_string();
    bp.icon = "hearth_setup.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Innkeeper", ParameterType::Npc, "The innkeeper NPC"),
    ];
    bp
}

// ============================================================================
// Combat Category Blueprints
// ============================================================================

/// Grind Area — Volume 6 §32
pub fn grind_area_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Grind Area", BlueprintCategory::Combat);
    bp.description = "Kill mobs in an area until stop condition".to_string();
    bp.icon = "grind_area.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Polygon", ParameterType::Polygon, "Grinding area polygon"),
        BlueprintParameter::required("Targets", ParameterType::Creature, "Creatures to kill"),
        BlueprintParameter::optional("Loot", ParameterType::Integer, "Items to loot", ParameterValue::Integer(0)),
    ];
    bp
}

/// Named Mob Hunt — Volume 6 §32
pub fn named_mob_hunt_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Named Mob Hunt", BlueprintCategory::Combat);
    bp.description = "Hunt specific named creatures".to_string();
    bp.icon = "named_mob.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Target", ParameterType::Creature, "Creature to hunt"),
        BlueprintParameter::optional("Count", ParameterType::Integer, "How many to kill", ParameterValue::Integer(1)),
    ];
    bp
}

/// Escort — Volume 6 §32
pub fn escort_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Escort", BlueprintCategory::Combat);
    bp.description = "Escort an NPC along a path".to_string();
    bp.icon = "escort.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("NPC", ParameterType::Npc, "The NPC to escort"),
        BlueprintParameter::required("Path", ParameterType::Waypoint, "Escort path waypoints"),
        BlueprintParameter::optional("Protect", ParameterType::Boolean, "Protect NPC from attacks", ParameterValue::Boolean(true)),
    ];
    bp
}

// ============================================================================
// NPC Services Category Blueprints
// ============================================================================

/// Vendor Stop — Volume 6 §32 (MVP priority)
pub fn vendor_stop_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Vendor Stop", BlueprintCategory::NpcServices);
    bp.description = "Sell junk, repair, buy food/water, restock".to_string();
    bp.icon = "vendor.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Vendor", ParameterType::Vendor, "The vendor NPC"),
        BlueprintParameter::optional("Repair", ParameterType::Boolean, "Enable repair", ParameterValue::Boolean(true)),
        BlueprintParameter::optional("SellGray", ParameterType::Boolean, "Sell gray items", ParameterValue::Boolean(true)),
        BlueprintParameter::optional("SellWhite", ParameterType::Boolean, "Sell white items", ParameterValue::Boolean(false)),
        BlueprintParameter::optional("BuyFood", ParameterType::Boolean, "Buy food", ParameterValue::Boolean(true)),
        BlueprintParameter::optional("BuyWater", ParameterType::Boolean, "Buy water", ParameterValue::Boolean(true)),
    ];
    bp
}

/// Train Stop — Volume 6 §32
pub fn train_stop_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Train Stop", BlueprintCategory::NpcServices);
    bp.description = "Train class skills at a trainer".to_string();
    bp.icon = "train.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Trainer", ParameterType::Trainer, "The trainer NPC"),
        BlueprintParameter::optional("Class", ParameterType::Enum, "Class for training", ParameterValue::Enum("Warrior".to_string())),
    ];
    bp
}

// ============================================================================
// Recovery Category Blueprints
// ============================================================================

/// Death Skip — Volume 6 §32
pub fn death_skip_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Death Skip", BlueprintCategory::Recovery);
    bp.description = "Emergency death skip to resume from graveyard".to_string();
    bp.icon = "death_skip.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Graveyard", ParameterType::Waypoint, "Target graveyard location"),
        BlueprintParameter::required("SpiritHealer", ParameterType::Npc, "The spirit healer NPC"),
    ];
    bp
}

// ============================================================================
// Utility Category Blueprints
// ============================================================================

/// Wait — Volume 6 §32
pub fn wait_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Wait", BlueprintCategory::Utility);
    bp.description = "Pause execution for a duration".to_string();
    bp.icon = "wait.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Duration", ParameterType::Integer, "Wait duration in milliseconds"),
    ];
    bp
}

/// Set Variable — Volume 6 §32
pub fn set_variable_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Set Variable", BlueprintCategory::Utility);
    bp.description = "Set a profile or operation variable".to_string();
    bp.icon = "variable.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Name", ParameterType::String, "Variable name"),
        BlueprintParameter::required("Value", ParameterType::String, "Variable value (as JSON)"),
    ];
    bp
}

/// Conditional Branch — Volume 6 §32
pub fn conditional_branch_blueprint() -> Blueprint {
    let mut bp = Blueprint::new("Conditional Branch", BlueprintCategory::Utility);
    bp.description = "Branch execution based on condition".to_string();
    bp.icon = "branch.png".to_string();
    bp.parameters = vec![
        BlueprintParameter::required("Expression", ParameterType::String, "Condition expression"),
        BlueprintParameter::optional("TrueActions", ParameterType::String, "Actions if true (UUID list)", ParameterValue::String(String::new())),
        BlueprintParameter::optional("FalseActions", ParameterType::String, "Actions if false (UUID list)", ParameterValue::String(String::new())),
    ];
    bp
}

// ============================================================================
// Collection
// ============================================================================

/// Get all standard blueprint definitions
pub fn all_standard_blueprints() -> Vec<Blueprint> {
    vec![
        quest_hub_blueprint(),
        single_quest_blueprint(),
        quest_chain_blueprint(),
        turnin_cluster_blueprint(),
        travel_hub_blueprint(),
        flight_unlock_blueprint(),
        hearth_setup_blueprint(),
        grind_area_blueprint(),
        named_mob_hunt_blueprint(),
        escort_blueprint(),
        vendor_stop_blueprint(),
        train_stop_blueprint(),
        death_skip_blueprint(),
        wait_blueprint(),
        set_variable_blueprint(),
        conditional_branch_blueprint(),
    ]
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_quest_hub_blueprint() {
        let bp = quest_hub_blueprint();
        assert_eq!(bp.name, "Quest Hub");
        assert_eq!(bp.category, BlueprintCategory::Quest);
        assert_eq!(bp.parameters.len(), 6);
        // QuestGiver should be optional
        assert!(!bp.parameters[0].required);
    }

    #[test]
    fn test_vendor_stop_blueprint() {
        let bp = vendor_stop_blueprint();
        assert_eq!(bp.name, "Vendor Stop");
        assert_eq!(bp.category, BlueprintCategory::NpcServices);
        assert_eq!(bp.parameters.len(), 6);
        // Vendor should be required
        assert!(bp.parameters[0].required);
    }

    #[test]
    fn test_all_standard_blueprints_count() {
        let blueprints = all_standard_blueprints();
        assert_eq!(blueprints.len(), 16);
        // Verify categories are present
        let categories: std::collections::HashSet<_> = blueprints.iter().map(|b| &b.category).collect();
        assert!(categories.contains(&BlueprintCategory::Quest));
        assert!(categories.contains(&BlueprintCategory::Travel));
        assert!(categories.contains(&BlueprintCategory::Combat));
        assert!(categories.contains(&BlueprintCategory::NpcServices));
        assert!(categories.contains(&BlueprintCategory::Recovery));
        assert!(categories.contains(&BlueprintCategory::Utility));
    }

    #[test]
    fn test_blueprint_serialization() {
        let bp = vendor_stop_blueprint();
        let yaml = crate::yaml_adapter::to_yaml_string(&bp).unwrap();
        let parsed: Blueprint = crate::yaml_adapter::from_yaml_string(&yaml).unwrap();
        assert_eq!(bp.name, parsed.name);
        assert_eq!(bp.category, parsed.category);
    }
}