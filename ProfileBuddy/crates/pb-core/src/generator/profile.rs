//! GatherBuddy profile generation
//!
//! Converts optimized routes into GatherBuddy-compatible JSON profiles.

use crate::data::{get_zone_bounds, NodeCategory, ZoneBounds};
use crate::error::{Error, Result};
use crate::optimizer::{Route, WaypointType};
use serde::{Deserialize, Serialize};

/// Complete GatherBuddy profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub version: String,
    pub metadata: ProfileMetadata,
    pub requirements: ProfileRequirements,
    pub settings: ProfileSettings,
    pub waypoints: Vec<Waypoint>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub blackspots: Vec<Blackspot>,
}

/// Profile metadata
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

/// Profile requirements
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

/// Skill requirements for gathering
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillRequirements {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mining: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub herbalism: Option<u16>,
}

/// Profile settings
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

impl Default for ProfileSettings {
    fn default() -> Self {
        Self {
            loop_route: true,
            node_search_radius: 80.0,
            waypoint_tolerance: 3.0,
            mount_threshold_distance: 40.0,
            skip_if_enemies_near: true,
            enemy_detection_radius: 25.0,
        }
    }
}

/// A waypoint in the profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Waypoint {
    pub id: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    #[serde(rename = "type")]
    pub waypoint_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub radius: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub linger_time: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

/// A blackspot (area to avoid)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Blackspot {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub radius: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// Profile generator configuration
#[derive(Debug, Clone)]
pub struct GeneratorConfig {
    /// Profile author name
    pub author: String,
    /// Custom profile name (auto-generated if None)
    pub name: Option<String>,
    /// Custom description
    pub description: Option<String>,
    /// Game version string
    pub game_version: Option<String>,
    /// Override default settings
    pub settings: Option<ProfileSettings>,
    /// Blackspots to include
    pub blackspots: Vec<Blackspot>,
}

impl Default for GeneratorConfig {
    fn default() -> Self {
        Self {
            author: "ProfileBuddy".to_string(),
            name: None,
            description: None,
            game_version: None,
            settings: None,
            blackspots: Vec::new(),
        }
    }
}

/// Generates GatherBuddy-compatible profiles from optimized routes
pub struct ProfileGenerator {
    config: GeneratorConfig,
}

impl ProfileGenerator {
    /// Create a new profile generator with default config
    pub fn new() -> Self {
        Self {
            config: GeneratorConfig::default(),
        }
    }

    /// Create a new profile generator with custom config
    pub fn with_config(config: GeneratorConfig) -> Self {
        Self { config }
    }

    /// Generate a profile from an optimized route
    pub fn generate(&self, route: &Route, zone_name: &str) -> Result<Profile> {
        if route.waypoints.is_empty() {
            return Err(Error::ProfileGenerationError(
                "Route has no waypoints".to_string(),
            ));
        }

        // Get zone bounds for coordinate conversion
        let bounds = get_zone_bounds_for_route(route)?;

        // Build waypoints
        let waypoints = self.build_waypoints(route, bounds);

        // Calculate skill requirements
        let min_skill = self.calculate_skill_requirements(route);

        // Generate profile name
        let name = self.config.name.clone().unwrap_or_else(|| {
            let node_types = self.get_node_type_string(route);
            format!("{} - {}", zone_name, node_types)
        });

        // Generate description
        let description = self.config.description.clone().unwrap_or_else(|| {
            format!(
                "Auto-generated gathering route with {} waypoints",
                waypoints.len()
            )
        });

        Ok(Profile {
            version: "1.0".to_string(),
            metadata: ProfileMetadata {
                name,
                author: self.config.author.clone(),
                description,
                game_version: self.config.game_version.clone(),
                estimated_time_minutes: Some(self.estimate_route_time(route)),
            },
            requirements: ProfileRequirements {
                min_skill,
                zone: zone_name.to_string(),
                map_id: bounds.map_id,
                continent_id: bounds.continent_id,
                requires_flying: Some(false),
            },
            settings: self.config.settings.clone().unwrap_or_default(),
            waypoints,
            blackspots: self.config.blackspots.clone(),
        })
    }

    /// Build waypoints from route
    fn build_waypoints(&self, route: &Route, bounds: &ZoneBounds) -> Vec<Waypoint> {
        let mut waypoints = Vec::new();
        let mut id = 1u32;

        // Add waypoints from the route (which already include hotspots as WaypointType::Hotspot)
        for wp in &route.waypoints {
            // The waypoints already have world coords from the optimizer
            // (DecodedNode.world_x/y/z -> RouteWaypoint.x/y/z)
            let world_x = wp.x;
            let world_y = wp.y;
            let world_z = if wp.z > 0.0 { wp.z } else { bounds.default_z };

            match wp.waypoint_type {
                WaypointType::Path => {
                    waypoints.push(Waypoint {
                        id,
                        x: world_x,
                        y: world_y,
                        z: world_z,
                        waypoint_type: "path".to_string(),
                        radius: None,
                        linger_time: None,
                        note: wp.note.clone(),
                    });
                }
                WaypointType::Hotspot { radius } => {
                    waypoints.push(Waypoint {
                        id,
                        x: world_x,
                        y: world_y,
                        z: world_z,
                        waypoint_type: "hotspot".to_string(),
                        radius: Some(radius as f32),
                        linger_time: Some(5), // 5 seconds default linger
                        note: wp.note.clone(),
                    });
                }
            }
            id += 1;
        }

        waypoints
    }

    /// Calculate minimum skill requirements based on nodes in route
    fn calculate_skill_requirements(&self, route: &Route) -> Option<SkillRequirements> {
        let mut min_mining: Option<u16> = None;
        let mut min_herbalism: Option<u16> = None;

        for node in &route.source_nodes {
            match node.category {
                NodeCategory::Ore => {
                    let skill = get_skill_for_node(node.node_id, NodeCategory::Ore);
                    min_mining = Some(min_mining.map_or(skill, |m| m.max(skill)));
                }
                NodeCategory::Herb => {
                    let skill = get_skill_for_node(node.node_id, NodeCategory::Herb);
                    min_herbalism = Some(min_herbalism.map_or(skill, |m| m.max(skill)));
                }
                _ => {}
            }
        }

        if min_mining.is_some() || min_herbalism.is_some() {
            Some(SkillRequirements {
                mining: min_mining,
                herbalism: min_herbalism,
            })
        } else {
            None
        }
    }

    /// Get a string describing node types in the route
    fn get_node_type_string(&self, route: &Route) -> String {
        let mut node_names: Vec<&str> = route
            .source_nodes
            .iter()
            .map(|n| n.node_name.as_str())
            .collect();
        node_names.sort();
        node_names.dedup();

        if node_names.len() <= 3 {
            node_names.join(", ")
        } else {
            let has_herbs = route
                .source_nodes
                .iter()
                .any(|n| n.category == NodeCategory::Herb);
            let has_ores = route
                .source_nodes
                .iter()
                .any(|n| n.category == NodeCategory::Ore);

            match (has_herbs, has_ores) {
                (true, true) => "Herbs & Ores".to_string(),
                (true, false) => "Herbs".to_string(),
                (false, true) => "Ores".to_string(),
                (false, false) => "Nodes".to_string(),
            }
        }
    }

    /// Estimate route completion time in minutes
    fn estimate_route_time(&self, route: &Route) -> u32 {
        // Rough estimate:
        // - Average mount speed: ~100% = 14 yards/sec (ground mount)
        // - Gathering time per node: ~3 seconds average
        // - Route distance is in normalized units, need to convert

        let waypoint_count = route.waypoints.len();
        let hotspot_count = route.hotspots.len();

        // Base estimate: 30 seconds per waypoint, 60 seconds per hotspot
        let travel_time = (waypoint_count as f32 * 0.5 + hotspot_count as f32 * 1.0) as u32;

        // Minimum 5 minutes, maximum 60 minutes
        travel_time.max(5).min(60)
    }

    /// Serialize profile to JSON string
    pub fn to_json(&self, profile: &Profile) -> Result<String> {
        serde_json::to_string_pretty(profile).map_err(Error::from)
    }

    /// Serialize profile to JSON and write to file
    pub fn write_to_file(&self, profile: &Profile, path: &std::path::Path) -> Result<()> {
        let json = self.to_json(profile)?;
        std::fs::write(path, json)?;
        Ok(())
    }
}

impl Default for ProfileGenerator {
    fn default() -> Self {
        Self::new()
    }
}

/// Get zone bounds from the first node in a route
fn get_zone_bounds_for_route(route: &Route) -> Result<&'static ZoneBounds> {
    let first_node = route.source_nodes.first().ok_or_else(|| {
        Error::ProfileGenerationError("Route has no source nodes".to_string())
    })?;

    get_zone_bounds(first_node.zone_id).ok_or_else(|| {
        Error::ZoneNotFound {
            zone_id: first_node.zone_id,
            zone_name: first_node.zone_name.clone(),
        }
    })
}

/// Get skill requirement for a node ID
fn get_skill_for_node(node_id: u16, category: NodeCategory) -> u16 {
    use crate::data::{HERB_NODES, ORE_NODES};

    match category {
        NodeCategory::Herb => HERB_NODES
            .iter()
            .find(|n| n.id == node_id)
            .map(|n| n.skill_required)
            .unwrap_or(1),
        NodeCategory::Ore => ORE_NODES
            .iter()
            .find(|n| n.id == node_id)
            .map(|n| n.skill_required)
            .unwrap_or(1),
        _ => 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::optimizer::{Algorithm, NodeCluster, RouteWaypoint, WaypointType};
    use crate::parser::DecodedNode;

    fn create_test_route() -> Route {
        Route {
            waypoints: vec![
                RouteWaypoint {
                    x: 0.5,
                    y: 0.5,
                    z: 56.0,
                    waypoint_type: WaypointType::Path,
                    source_node_id: None,
                    note: None,
                },
                RouteWaypoint {
                    x: 0.6,
                    y: 0.5,
                    z: 57.0,
                    waypoint_type: WaypointType::Path,
                    source_node_id: None,
                    note: None,
                },
                RouteWaypoint {
                    x: 0.6,
                    y: 0.6,
                    z: 58.0,
                    waypoint_type: WaypointType::Hotspot { radius: 30 },
                    source_node_id: None,
                    note: Some("Dense node area".to_string()),
                },
            ],
            total_distance: 150.0,
            hotspots: vec![NodeCluster {
                center_x: 0.55,
                center_y: 0.55,
                center_z: 57.0,
                radius: 30.0,
                node_count: 5,
                node_ids: vec![403, 403, 403, 201, 201],
            }],
            algorithm: Algorithm::Tsp,
            randomized: false,
            source_nodes: vec![DecodedNode {
                id: 1,
                zone_id: 1429, // Elwynn Forest
                zone_name: "Elwynn Forest".to_string(),
                map_x: 0.5,
                map_y: 0.5,
                world_x: 0.0,
                world_y: 0.0,
                world_z: 0.0,
                category: NodeCategory::Herb,
                node_id: 403, // Peacebloom
                node_name: "Peacebloom".to_string(),
            }],
        }
    }

    #[test]
    fn test_profile_generation() {
        let route = create_test_route();
        let generator = ProfileGenerator::new();
        let profile = generator.generate(&route, "Elwynn Forest").unwrap();

        assert_eq!(profile.version, "1.0");
        assert_eq!(profile.requirements.zone, "Elwynn Forest");
        assert!(!profile.waypoints.is_empty());
    }

    #[test]
    fn test_profile_serialization() {
        let route = create_test_route();
        let generator = ProfileGenerator::new();
        let profile = generator.generate(&route, "Elwynn Forest").unwrap();

        let json = generator.to_json(&profile).unwrap();
        assert!(json.contains("\"version\""));
        assert!(json.contains("\"waypoints\""));
        assert!(json.contains("Elwynn Forest"));
    }

    #[test]
    fn test_empty_route_error() {
        let route = Route {
            waypoints: vec![],
            total_distance: 0.0,
            hotspots: vec![],
            algorithm: Algorithm::Tsp,
            randomized: false,
            source_nodes: vec![],
        };
        let generator = ProfileGenerator::new();
        let result = generator.generate(&route, "Test Zone");

        assert!(result.is_err());
    }
}
