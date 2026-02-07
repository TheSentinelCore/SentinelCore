//! Node ID to name mappings from GatherMate2 Constants.lua
//!
//! Source: https://github.com/Nevcairiel/GatherMate2/blob/master/Constants.lua

use serde::{Deserialize, Serialize};

/// Category of gathering node
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum NodeCategory {
    Herb,
    Ore,
    Treasure,
    Fish,
    Gas,
}

/// Mapping from node ID to name and metadata
#[derive(Debug, Clone)]
pub struct NodeMapping {
    pub id: u16,
    pub name: &'static str,
    pub category: NodeCategory,
    pub skill_required: u16,
}

/// Classic herb node mappings (IDs 401-441)
pub static HERB_NODES: &[NodeMapping] = &[
    // Classic Herbs
    NodeMapping { id: 401, name: "Silverleaf", category: NodeCategory::Herb, skill_required: 1 },
    NodeMapping { id: 402, name: "Earthroot", category: NodeCategory::Herb, skill_required: 15 },
    NodeMapping { id: 403, name: "Peacebloom", category: NodeCategory::Herb, skill_required: 1 },
    NodeMapping { id: 404, name: "Mageroyal", category: NodeCategory::Herb, skill_required: 50 },
    NodeMapping { id: 405, name: "Briarthorn", category: NodeCategory::Herb, skill_required: 70 },
    NodeMapping { id: 407, name: "Stranglekelp", category: NodeCategory::Herb, skill_required: 85 },
    NodeMapping { id: 408, name: "Bruiseweed", category: NodeCategory::Herb, skill_required: 100 },
    NodeMapping { id: 409, name: "Wild Steelbloom", category: NodeCategory::Herb, skill_required: 115 },
    NodeMapping { id: 410, name: "Grave Moss", category: NodeCategory::Herb, skill_required: 120 },
    NodeMapping { id: 411, name: "Kingsblood", category: NodeCategory::Herb, skill_required: 125 },
    NodeMapping { id: 412, name: "Liferoot", category: NodeCategory::Herb, skill_required: 150 },
    NodeMapping { id: 413, name: "Fadeleaf", category: NodeCategory::Herb, skill_required: 160 },
    NodeMapping { id: 414, name: "Goldthorn", category: NodeCategory::Herb, skill_required: 170 },
    NodeMapping { id: 415, name: "Khadgar's Whisker", category: NodeCategory::Herb, skill_required: 185 },
    NodeMapping { id: 416, name: "Wintersbite", category: NodeCategory::Herb, skill_required: 195 },
    NodeMapping { id: 417, name: "Firebloom", category: NodeCategory::Herb, skill_required: 205 },
    NodeMapping { id: 418, name: "Purple Lotus", category: NodeCategory::Herb, skill_required: 210 },
    NodeMapping { id: 420, name: "Arthas' Tears", category: NodeCategory::Herb, skill_required: 220 },
    NodeMapping { id: 421, name: "Sungrass", category: NodeCategory::Herb, skill_required: 230 },
    NodeMapping { id: 422, name: "Blindweed", category: NodeCategory::Herb, skill_required: 235 },
    NodeMapping { id: 423, name: "Ghost Mushroom", category: NodeCategory::Herb, skill_required: 245 },
    NodeMapping { id: 424, name: "Gromsblood", category: NodeCategory::Herb, skill_required: 250 },
    NodeMapping { id: 425, name: "Golden Sansam", category: NodeCategory::Herb, skill_required: 260 },
    NodeMapping { id: 426, name: "Dreamfoil", category: NodeCategory::Herb, skill_required: 270 },
    NodeMapping { id: 427, name: "Mountain Silversage", category: NodeCategory::Herb, skill_required: 280 },
    NodeMapping { id: 428, name: "Plaguebloom", category: NodeCategory::Herb, skill_required: 285 },
    NodeMapping { id: 429, name: "Icecap", category: NodeCategory::Herb, skill_required: 290 },
    NodeMapping { id: 431, name: "Black Lotus", category: NodeCategory::Herb, skill_required: 300 },
    // TBC Herbs
    NodeMapping { id: 432, name: "Felweed", category: NodeCategory::Herb, skill_required: 300 },
    NodeMapping { id: 433, name: "Dreaming Glory", category: NodeCategory::Herb, skill_required: 315 },
    NodeMapping { id: 434, name: "Terocone", category: NodeCategory::Herb, skill_required: 325 },
    NodeMapping { id: 435, name: "Ancient Lichen", category: NodeCategory::Herb, skill_required: 340 },
    NodeMapping { id: 436, name: "Bloodthistle", category: NodeCategory::Herb, skill_required: 1 },
    NodeMapping { id: 437, name: "Mana Thistle", category: NodeCategory::Herb, skill_required: 375 },
    NodeMapping { id: 438, name: "Netherbloom", category: NodeCategory::Herb, skill_required: 350 },
    NodeMapping { id: 439, name: "Nightmare Vine", category: NodeCategory::Herb, skill_required: 365 },
    NodeMapping { id: 440, name: "Ragveil", category: NodeCategory::Herb, skill_required: 325 },
    NodeMapping { id: 441, name: "Flame Cap", category: NodeCategory::Herb, skill_required: 335 },
];

/// Classic ore node mappings (IDs 201-227)
pub static ORE_NODES: &[NodeMapping] = &[
    // Classic Ores
    NodeMapping { id: 201, name: "Copper Vein", category: NodeCategory::Ore, skill_required: 1 },
    NodeMapping { id: 202, name: "Tin Vein", category: NodeCategory::Ore, skill_required: 65 },
    NodeMapping { id: 203, name: "Iron Deposit", category: NodeCategory::Ore, skill_required: 125 },
    NodeMapping { id: 204, name: "Silver Vein", category: NodeCategory::Ore, skill_required: 75 },
    NodeMapping { id: 205, name: "Gold Vein", category: NodeCategory::Ore, skill_required: 155 },
    NodeMapping { id: 206, name: "Mithril Deposit", category: NodeCategory::Ore, skill_required: 175 },
    NodeMapping { id: 207, name: "Ooze Covered Mithril Deposit", category: NodeCategory::Ore, skill_required: 175 },
    NodeMapping { id: 208, name: "Truesilver Deposit", category: NodeCategory::Ore, skill_required: 230 },
    NodeMapping { id: 209, name: "Ooze Covered Silver Vein", category: NodeCategory::Ore, skill_required: 75 },
    NodeMapping { id: 210, name: "Ooze Covered Gold Vein", category: NodeCategory::Ore, skill_required: 155 },
    NodeMapping { id: 211, name: "Ooze Covered Truesilver Deposit", category: NodeCategory::Ore, skill_required: 230 },
    NodeMapping { id: 212, name: "Ooze Covered Rich Thorium Vein", category: NodeCategory::Ore, skill_required: 275 },
    NodeMapping { id: 213, name: "Ooze Covered Thorium Vein", category: NodeCategory::Ore, skill_required: 245 },
    NodeMapping { id: 214, name: "Small Thorium Vein", category: NodeCategory::Ore, skill_required: 245 },
    NodeMapping { id: 215, name: "Rich Thorium Vein", category: NodeCategory::Ore, skill_required: 275 },
    NodeMapping { id: 217, name: "Dark Iron Deposit", category: NodeCategory::Ore, skill_required: 230 },
    NodeMapping { id: 218, name: "Lesser Bloodstone Deposit", category: NodeCategory::Ore, skill_required: 75 },
    NodeMapping { id: 219, name: "Incendicite Mineral Vein", category: NodeCategory::Ore, skill_required: 65 },
    NodeMapping { id: 220, name: "Indurium Mineral Vein", category: NodeCategory::Ore, skill_required: 150 },
    // TBC Ores
    NodeMapping { id: 221, name: "Fel Iron Deposit", category: NodeCategory::Ore, skill_required: 300 },
    NodeMapping { id: 222, name: "Adamantite Deposit", category: NodeCategory::Ore, skill_required: 325 },
    NodeMapping { id: 223, name: "Rich Adamantite Deposit", category: NodeCategory::Ore, skill_required: 350 },
    NodeMapping { id: 224, name: "Khorium Vein", category: NodeCategory::Ore, skill_required: 375 },
    NodeMapping { id: 225, name: "Large Obsidian Chunk", category: NodeCategory::Ore, skill_required: 305 },
    NodeMapping { id: 226, name: "Small Obsidian Chunk", category: NodeCategory::Ore, skill_required: 305 },
    NodeMapping { id: 227, name: "Nethercite Deposit", category: NodeCategory::Ore, skill_required: 350 },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_herb_node_lookup() {
        assert_eq!(
            HERB_NODES.iter().find(|n| n.id == 403).map(|n| n.name),
            Some("Peacebloom")
        );
        assert_eq!(
            HERB_NODES.iter().find(|n| n.id == 401).map(|n| n.name),
            Some("Silverleaf")
        );
    }

    #[test]
    fn test_ore_node_lookup() {
        assert_eq!(
            ORE_NODES.iter().find(|n| n.id == 201).map(|n| n.name),
            Some("Copper Vein")
        );
        assert_eq!(
            ORE_NODES.iter().find(|n| n.id == 215).map(|n| n.name),
            Some("Rich Thorium Vein")
        );
    }
}
