//! GatherMate2 Lua parser implementation
//!
//! Uses regex to parse Lua table structures without a full Lua VM.

use crate::data::{get_node_name, get_zone_bounds, GameVersion, NodeCategory, ZoneBounds};
use crate::error::Result;
use regex::Regex;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// Raw node data directly from GatherMate2
#[derive(Debug, Clone)]
pub struct RawNode {
    pub zone_id: u32,
    pub packed_coord: u64,
    pub node_id: u16,
    pub category: NodeCategory,
}

/// Node with decoded coordinates
#[derive(Debug, Clone)]
pub struct DecodedNode {
    /// Unique identifier (packed_coord can serve as ID)
    pub id: u64,
    /// Zone UiMapID
    pub zone_id: u32,
    /// Zone name (if known)
    pub zone_name: String,
    /// Normalized map X coordinate (0.0-1.0)
    pub map_x: f32,
    /// Normalized map Y coordinate (0.0-1.0)
    pub map_y: f32,
    /// World X coordinate (North-South)
    pub world_x: f32,
    /// World Y coordinate (West-East)
    pub world_y: f32,
    /// World Z coordinate (Height)
    pub world_z: f32,
    /// Node category (Herb, Ore, etc.)
    pub category: NodeCategory,
    /// GatherMate2 node ID
    pub node_id: u16,
    /// Node name (e.g., "Peacebloom", "Copper Vein")
    pub node_name: String,
}

/// Data for a single zone
#[derive(Debug, Clone, Default)]
pub struct ZoneData {
    pub zone_id: u32,
    pub name: String,
    pub bounds: Option<ZoneBounds>,
    pub herbs: Vec<DecodedNode>,
    pub ores: Vec<DecodedNode>,
}

impl ZoneData {
    /// Get all nodes (herbs + ores)
    pub fn all_nodes(&self) -> impl Iterator<Item = &DecodedNode> {
        self.herbs.iter().chain(self.ores.iter())
    }

    /// Total node count
    pub fn node_count(&self) -> usize {
        self.herbs.len() + self.ores.len()
    }
}

/// Database of all parsed nodes
#[derive(Debug, Default)]
pub struct NodeDatabase {
    pub game_version: GameVersion,
    pub zones: HashMap<u32, ZoneData>,
    pub total_herb_count: usize,
    pub total_ore_count: usize,
}

impl NodeDatabase {
    /// Get zone data by UiMapID
    pub fn get_zone(&self, zone_id: u32) -> Option<&ZoneData> {
        self.zones.get(&zone_id)
    }

    /// Get all zones sorted by name
    pub fn zones_sorted(&self) -> Vec<&ZoneData> {
        let mut zones: Vec<_> = self.zones.values().collect();
        zones.sort_by(|a, b| a.name.cmp(&b.name));
        zones
    }

    /// Get unique herb types across all zones
    pub fn unique_herbs(&self) -> Vec<(u16, &str)> {
        let mut herbs: HashMap<u16, &str> = HashMap::new();
        for zone in self.zones.values() {
            for node in &zone.herbs {
                herbs.entry(node.node_id).or_insert(&node.node_name);
            }
        }
        let mut result: Vec<_> = herbs.into_iter().collect();
        result.sort_by(|a, b| a.1.cmp(b.1));
        result
    }

    /// Get unique ore types across all zones
    pub fn unique_ores(&self) -> Vec<(u16, &str)> {
        let mut ores: HashMap<u16, &str> = HashMap::new();
        for zone in self.zones.values() {
            for node in &zone.ores {
                ores.entry(node.node_id).or_insert(&node.node_name);
            }
        }
        let mut result: Vec<_> = ores.into_iter().collect();
        result.sort_by(|a, b| a.1.cmp(b.1));
        result
    }
}

/// GatherMate2 data parser
pub struct Parser {
    game_version: GameVersion,
    zone_pattern: Regex,
    node_pattern: Regex,
}

impl Parser {
    /// Create a new parser for the specified game version
    pub fn new(game_version: GameVersion) -> Self {
        Self {
            game_version,
            // Pattern to match zone blocks: [zone_id] = {
            zone_pattern: Regex::new(r"\[(\d+)\]\s*=\s*\{").unwrap(),
            // Pattern to match node entries: [packed_coord] = node_id,
            node_pattern: Regex::new(r"\[(\d+)\]\s*=\s*(\d+)").unwrap(),
        }
    }

    /// Parse all data files in a GatherMate2_Data directory
    pub fn parse_all<P: AsRef<Path>>(&self, data_dir: P) -> Result<NodeDatabase> {
        let data_dir = data_dir.as_ref();
        let mut db = NodeDatabase {
            game_version: self.game_version,
            ..Default::default()
        };

        // Parse herbalism data
        let herb_path = data_dir.join("HerbalismData.lua");
        if herb_path.exists() {
            let herbs = self.parse_file(&herb_path, NodeCategory::Herb)?;
            for node in herbs {
                self.add_node_to_db(&mut db, node);
            }
        }

        // Parse mining data
        let mine_path = data_dir.join("MiningData.lua");
        if mine_path.exists() {
            let ores = self.parse_file(&mine_path, NodeCategory::Ore)?;
            for node in ores {
                self.add_node_to_db(&mut db, node);
            }
        }

        Ok(db)
    }

    /// Parse a single GatherMate2 data file
    pub fn parse_file<P: AsRef<Path>>(
        &self,
        path: P,
        category: NodeCategory,
    ) -> Result<Vec<RawNode>> {
        let content = fs::read_to_string(path.as_ref())?;
        self.parse_content(&content, category)
    }

    /// Parse GatherMate2 Lua content
    pub fn parse_content(&self, content: &str, category: NodeCategory) -> Result<Vec<RawNode>> {
        let mut nodes = Vec::new();
        let mut current_zone_id: Option<u32> = None;
        let mut brace_depth = 0;

        for line in content.lines() {
            let trimmed = line.trim();

            // Track brace depth to know when we exit a zone block
            brace_depth += trimmed.matches('{').count();
            brace_depth = brace_depth.saturating_sub(trimmed.matches('}').count());

            // Check for zone start
            if let Some(caps) = self.zone_pattern.captures(trimmed) {
                if let Ok(zone_id) = caps[1].parse::<u32>() {
                    current_zone_id = Some(zone_id);
                }
                continue;
            }

            // If we're at depth 0 and see }, we've exited the zone
            if brace_depth == 0 && trimmed.contains('}') {
                current_zone_id = None;
                continue;
            }

            // Parse node entries within a zone
            if let Some(zone_id) = current_zone_id {
                if let Some(caps) = self.node_pattern.captures(trimmed) {
                    if let (Ok(packed_coord), Ok(node_id)) =
                        (caps[1].parse::<u64>(), caps[2].parse::<u16>())
                    {
                        nodes.push(RawNode {
                            zone_id,
                            packed_coord,
                            node_id,
                            category,
                        });
                    }
                }
            }
        }

        Ok(nodes)
    }

    /// Add a raw node to the database, decoding coordinates
    fn add_node_to_db(&self, db: &mut NodeDatabase, raw: RawNode) {
        // Decode packed coordinate to normalized map coords
        let (map_x, map_y) = decode_coord(raw.packed_coord);

        // Get zone bounds and convert to world coords
        let (zone_name, world_x, world_y, world_z, bounds) =
            if let Some(bounds) = get_zone_bounds(raw.zone_id) {
                let (wx, wy, wz) = bounds.to_world_coords(map_x, map_y);
                (bounds.name.to_string(), wx, wy, wz, Some(bounds.clone()))
            } else {
                // Unknown zone - keep normalized coords
                (format!("Zone {}", raw.zone_id), 0.0, 0.0, 0.0, None)
            };

        // Get node name
        let node_name = get_node_name(raw.node_id, raw.category)
            .unwrap_or("Unknown")
            .to_string();

        let decoded = DecodedNode {
            id: raw.packed_coord,
            zone_id: raw.zone_id,
            zone_name: zone_name.clone(),
            map_x,
            map_y,
            world_x,
            world_y,
            world_z,
            category: raw.category,
            node_id: raw.node_id,
            node_name,
        };

        // Get or create zone data
        let zone_data = db.zones.entry(raw.zone_id).or_insert_with(|| ZoneData {
            zone_id: raw.zone_id,
            name: zone_name,
            bounds,
            herbs: Vec::new(),
            ores: Vec::new(),
        });

        // Add to appropriate list
        match raw.category {
            NodeCategory::Herb => {
                zone_data.herbs.push(decoded);
                db.total_herb_count += 1;
            }
            NodeCategory::Ore => {
                zone_data.ores.push(decoded);
                db.total_ore_count += 1;
            }
            _ => {}
        }
    }
}

/// Decode GatherMate2 packed coordinate to normalized map coordinates (0.0-1.0)
///
/// Format: XXXXYYYY00 (10 digits)
/// - Digits 1-4: X coordinate * 10000
/// - Digits 5-8: Y coordinate * 10000
/// - Digits 9-10: Padding (always 00)
pub fn decode_coord(packed: u64) -> (f32, f32) {
    let x = (packed / 1_000_000) as f32 / 10000.0;
    let y = ((packed % 1_000_000) / 100) as f32 / 10000.0;
    (x, y)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decode_coord() {
        // Test known coordinate: 6430598000 should decode to (0.643, 0.598)
        let (x, y) = decode_coord(6430598000);
        assert!((x - 0.643).abs() < 0.0001, "x was {}", x);
        assert!((y - 0.598).abs() < 0.0001, "y was {}", y);

        // Test another coordinate
        let (x, y) = decode_coord(3560343000);
        assert!((x - 0.356).abs() < 0.0001, "x was {}", x);
        assert!((y - 0.343).abs() < 0.0001, "y was {}", y);
    }

    #[test]
    fn test_parse_content() {
        let content = r#"
GatherMateData2HerbDB = {
	[1411] = {
		[3570284000] = 401,
		[3610296000] = 403,
	},
	[1429] = {
		[4560382000] = 403,
		[5120445000] = 401,
	},
}
"#;

        let parser = Parser::new(GameVersion::Era);
        let nodes = parser.parse_content(content, NodeCategory::Herb).unwrap();

        assert_eq!(nodes.len(), 4);

        // Check first node
        assert_eq!(nodes[0].zone_id, 1411);
        assert_eq!(nodes[0].packed_coord, 3570284000);
        assert_eq!(nodes[0].node_id, 401);

        // Check zone separation
        assert_eq!(nodes[2].zone_id, 1429);
    }

    #[test]
    fn test_parser_creates_db() {
        let content = r#"
GatherMateData2HerbDB = {
	[1429] = {
		[4560382000] = 403,
		[5120445000] = 401,
	},
}
"#;

        let parser = Parser::new(GameVersion::Era);
        let nodes = parser.parse_content(content, NodeCategory::Herb).unwrap();

        let mut db = NodeDatabase::default();
        for node in nodes {
            parser.add_node_to_db(&mut db, node);
        }

        assert_eq!(db.zones.len(), 1);
        assert!(db.zones.contains_key(&1429));

        let zone = db.get_zone(1429).unwrap();
        assert_eq!(zone.herbs.len(), 2);
        assert_eq!(zone.name, "Elwynn Forest");
    }
}
