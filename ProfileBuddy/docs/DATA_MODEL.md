# ProfileBuddy - Data Model

## Input Data Structures

### GatherMate2 Raw Format

```lua
-- GatherMateData2HerbDB structure
GatherMateData2HerbDB = {
    [zone_id] = {
        [packed_coord] = node_id,
        -- packed_coord: XXXXYYYY00 format (10 digits)
        -- node_id: herb/ore type identifier
    }
}
```

### Parsed Node

```rust
/// Raw node data directly from GatherMate2
#[derive(Debug, Clone)]
pub struct RawNode {
    pub zone_id: u32,
    pub packed_coord: u64,
    pub node_id: u16,
    pub category: NodeCategory,
}

/// Node category
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeCategory {
    Herb,
    Ore,
    Treasure,
    Fish,
    Gas,
}
```

### Decoded Node

```rust
/// Node with decoded coordinates
#[derive(Debug, Clone)]
pub struct DecodedNode {
    pub id: u64,
    pub zone_id: u32,
    pub zone_name: String,
    pub map_x: f32,         // 0.0-1.0 normalized
    pub map_y: f32,         // 0.0-1.0 normalized
    pub world_x: f32,       // WoW world coordinate
    pub world_y: f32,       // WoW world coordinate
    pub world_z: f32,       // Estimated ground level
    pub category: NodeCategory,
    pub node_id: u16,
    pub node_name: String,
}
```

## Static Data Structures

### Zone Boundaries

```rust
/// Zone boundary information for coordinate conversion
#[derive(Debug, Clone)]
pub struct ZoneBounds {
    pub ui_map_id: u32,        // Modern UiMapID (GatherMate2 Era/TBC)
    pub name: &'static str,
    pub continent_id: u32,      // 0=EK, 1=Kalimdor, 530=Outland
    pub map_id: u32,            // For GatherBuddy profile
    pub loc_top: f32,           // North boundary (X)
    pub loc_bottom: f32,        // South boundary (X)
    pub loc_left: f32,          // West boundary (Y)
    pub loc_right: f32,         // East boundary (Y)
    pub default_z: f32,         // Default ground height
    pub game_version: GameVersion,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum GameVersion {
    #[default]
    Era,    // Classic Anniversary
    Tbc,    // The Burning Crusade
}
```

### Node ID Mappings

```rust
/// Mapping from GatherMate2 node IDs to names
#[derive(Debug, Clone)]
pub struct NodeMapping {
    pub id: u16,
    pub name: &'static str,
    pub skill_required: u16,
}

// Example mappings
pub const HERB_NODES: &[NodeMapping] = &[
    NodeMapping { id: 401, name: "Silverleaf", skill_required: 1 },
    NodeMapping { id: 402, name: "Earthroot", skill_required: 15 },
    NodeMapping { id: 403, name: "Peacebloom", skill_required: 1 },
    // ... more mappings
];

pub const ORE_NODES: &[NodeMapping] = &[
    NodeMapping { id: 201, name: "Copper Vein", skill_required: 1 },
    NodeMapping { id: 202, name: "Tin Vein", skill_required: 65 },
    // ... more mappings
];
```

## Intermediate Data Structures

### Route Optimization

```rust
/// Configuration for route optimization
#[derive(Debug, Clone)]
pub struct OptimizerConfig {
    pub algorithm: Algorithm,
    pub randomization: RandomStrategy,
    pub max_iterations: u32,
    pub node_subset_ratio: f32,   // 0.7-1.0 for subset selection
    pub jitter_range: f32,        // Coordinate jitter in yards
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Algorithm {
    #[default]
    Tsp,
    Cluster,
    Density,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RandomStrategy {
    None,
    #[default]
    RouteVariation,
    NodeSubset,
    Both,
}

/// Optimized route
#[derive(Debug, Clone)]
pub struct Route {
    pub waypoints: Vec<RouteWaypoint>,
    pub total_distance: f32,
    pub hotspots: Vec<NodeCluster>,
    pub algorithm: Algorithm,
    pub randomized: bool,
    pub source_nodes: Vec<DecodedNode>,
}

#[derive(Debug, Clone)]
pub struct RouteWaypoint {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub waypoint_type: WaypointType,
    pub source_node_id: Option<u16>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WaypointType {
    Path,
    Hotspot { radius: u32 },
}

#[derive(Debug, Clone)]
pub struct NodeCluster {
    pub center_x: f32,
    pub center_y: f32,
    pub center_z: f32,
    pub radius: f32,
    pub node_count: usize,
    pub node_ids: Vec<u16>,
}
```

## Output Data Structures

### GatherBuddy Profile (JSON)

```rust
/// Complete GatherBuddy profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub version: String,
    pub metadata: ProfileMetadata,
    pub requirements: ProfileRequirements,
    pub settings: ProfileSettings,
    pub waypoints: Vec<Waypoint>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub blackspots: Vec<Blackspot>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileMetadata {
    pub name: String,
    pub author: String,
    pub description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub estimated_time_minutes: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileRequirements {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub min_skill: Option<SkillRequirements>,
    pub zone: String,
    pub map_id: u32,
    pub continent_id: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub requires_flying: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillRequirements {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mining: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub herbalism: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileSettings {
    #[serde(rename = "loop")]
    pub loop_route: bool,
    pub node_search_radius: f32,
    pub waypoint_tolerance: f32,
    pub mount_threshold_distance: f32,
    pub skip_if_enemies_near: bool,
    pub enemy_detection_radius: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Waypoint {
    pub id: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    #[serde(rename = "type")]
    pub waypoint_type: String, // "path" or "hotspot"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub radius: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub linger_time: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Blackspot {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub radius: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}
```

## Database Schema (In-Memory)

```rust
/// Main database holding all parsed data
#[derive(Debug, Default)]
pub struct NodeDatabase {
    pub game_version: GameVersion,
    pub zones: HashMap<u32, ZoneData>,
    pub total_herb_count: usize,
    pub total_ore_count: usize,
}

#[derive(Debug, Clone, Default)]
pub struct ZoneData {
    pub zone_id: u32,
    pub name: String,
    pub bounds: Option<ZoneBounds>,
    pub herbs: Vec<DecodedNode>,
    pub ores: Vec<DecodedNode>,
}
```

## Coordinate Systems Reference

| System | X | Y | Z |
|--------|---|---|---|
| GatherMate2 (normalized) | 0.0-1.0 (map %) | 0.0-1.0 (map %) | N/A |
| WoW World | North-South | West-East | Height |
| GatherBuddy Profile | North-South | West-East | Height |

### Conversion Formula

```rust
/// Decode GatherMate2 packed coordinate
fn decode_coord(packed: u64) -> (f32, f32) {
    let x = (packed / 1_000_000) as f32 / 10000.0;
    let y = ((packed % 1_000_000) / 100) as f32 / 10000.0;
    (x, y)
}

/// Convert normalized map coords to world coords
fn to_world_coords(map_x: f32, map_y: f32, bounds: &ZoneBounds) -> (f32, f32, f32) {
    let world_x = bounds.loc_top + (bounds.loc_bottom - bounds.loc_top) * map_x;
    let world_y = bounds.loc_left + (bounds.loc_right - bounds.loc_left) * map_y;
    let world_z = bounds.default_z;
    (world_x, world_y, world_z)
}
```
