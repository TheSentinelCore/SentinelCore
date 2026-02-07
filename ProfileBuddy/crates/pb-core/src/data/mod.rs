//! Static data for ProfileBuddy
//!
//! Contains zone boundaries, node ID mappings, and other reference data.

mod nodes;
mod zones;

pub use nodes::{NodeCategory, NodeMapping, HERB_NODES, ORE_NODES};
pub use zones::{ExclusionZone, GameVersion, ZoneBounds, ZONE_DATABASE};

/// Get node name from node ID
pub fn get_node_name(node_id: u16, category: NodeCategory) -> Option<&'static str> {
    match category {
        NodeCategory::Herb => HERB_NODES.iter().find(|n| n.id == node_id).map(|n| n.name),
        NodeCategory::Ore => ORE_NODES.iter().find(|n| n.id == node_id).map(|n| n.name),
        _ => None,
    }
}

/// Get zone bounds by UiMapID
pub fn get_zone_bounds(ui_map_id: u32) -> Option<&'static ZoneBounds> {
    ZONE_DATABASE.iter().find(|z| z.ui_map_id == ui_map_id)
}

/// Get zone bounds by zone name (case-insensitive)
pub fn get_zone_bounds_by_name(name: &str) -> Option<&'static ZoneBounds> {
    let name_lower = name.to_lowercase();
    ZONE_DATABASE
        .iter()
        .find(|z| z.name.to_lowercase() == name_lower)
}
