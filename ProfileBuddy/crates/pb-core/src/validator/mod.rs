//! Coordinate validation module for NavBuddy integration.
//!
//! This module provides coordinate validation by querying NavBuddy's
//! height endpoint to:
//! 1. Get actual terrain Z heights (instead of using zone default_z)
//! 2. Filter out nodes that aren't on the navmesh
//! 3. Detect and exclude underground/cave nodes

mod client;
mod config;

pub use client::NavBuddyClient;
pub use config::ValidatorConfig;

use log::{debug, info, warn};
use rayon::prelude::*;

use crate::error::{Error, Result};
use crate::parser::DecodedNode;

/// Result of validating a batch of nodes.
#[derive(Debug, Clone, Default)]
pub struct ValidationResult {
    /// Number of nodes successfully validated with correct Z heights.
    pub validated: usize,
    /// Number of nodes removed because they weren't on the navmesh.
    pub removed_not_on_navmesh: usize,
    /// Number of nodes removed because they were detected as underground/cave.
    pub removed_underground: usize,
    /// Number of nodes removed because they're on isolated polygons (unreachable).
    pub removed_unreachable: usize,
    /// Number of nodes that used fallback Z (when fallback_on_error is true).
    pub fallback: usize,
    /// Error messages encountered during validation.
    pub errors: Vec<String>,
}

impl ValidationResult {
    /// Total number of nodes removed.
    pub fn total_removed(&self) -> usize {
        self.removed_not_on_navmesh + self.removed_underground + self.removed_unreachable
    }

    /// Summary string for display.
    pub fn summary(&self) -> String {
        format!(
            "Validated: {}, Removed (not on navmesh): {}, Removed (underground): {}, Removed (unreachable): {}, Fallback: {}",
            self.validated,
            self.removed_not_on_navmesh,
            self.removed_underground,
            self.removed_unreachable,
            self.fallback
        )
    }
}

/// Validates node coordinates against NavBuddy's navmesh data.
pub struct HeightValidator {
    client: NavBuddyClient,
    config: ValidatorConfig,
}

impl HeightValidator {
    /// Create a new height validator.
    ///
    /// # Arguments
    /// * `config` - Validator configuration
    ///
    /// # Returns
    /// A new HeightValidator, or an error if NavBuddy is unavailable and
    /// fallback_on_error is false.
    pub fn new(config: &ValidatorConfig) -> Result<Self> {
        let client = NavBuddyClient::new(&config.navbuddy_url, config.timeout_ms)?;

        // Check if NavBuddy is available
        if !client.health_check()? {
            if !config.fallback_on_error {
                return Err(Error::NavBuddyUnavailable {
                    url: config.navbuddy_url.clone(),
                    reason: "Health check failed".to_string(),
                });
            }
            warn!(
                "NavBuddy not available at {}, will use fallback Z values",
                config.navbuddy_url
            );
        }

        Ok(Self {
            client,
            config: config.clone(),
        })
    }

    /// Check if NavBuddy is available.
    pub fn is_available(&self) -> bool {
        self.client.health_check().unwrap_or(false)
    }

    /// Validate a single node's coordinates.
    ///
    /// # Arguments
    /// * `node` - The node to validate (will be modified in place)
    /// * `map_id` - Map/continent ID for NavBuddy queries
    /// * `default_z` - Fallback Z value if validation fails
    ///
    /// # Returns
    /// - `Ok(true)` - Node validated successfully
    /// - `Ok(false)` - Node should be removed (not on navmesh or underground)
    /// - `Err(...)` - Error occurred and fallback_on_error is false
    pub fn validate_single(
        &self,
        node: &mut DecodedNode,
        map_id: u32,
        default_z: f32,
    ) -> Result<bool> {
        // Query height at the node's position
        let node_height_result = self.client.get_height(map_id, node.world_x, node.world_y, default_z);

        match node_height_result {
            Ok(height) => {
                // Check for underground/cave if enabled
                if self.config.exclude_caves {
                    // Query height from far above to find surface
                    let surface_height_result = self.client.get_height(
                        map_id,
                        node.world_x,
                        node.world_y,
                        height + 500.0, // Query from high above
                    );

                    if let Ok(surface_height) = surface_height_result {
                        let height_diff = surface_height - height;
                        if height_diff > self.config.cave_threshold {
                            debug!(
                                "Node at ({:.1}, {:.1}) detected as underground (surface={:.1}, node={:.1}, diff={:.1})",
                                node.world_x, node.world_y, surface_height, height, height_diff
                            );
                            return Ok(false); // Remove underground node
                        }
                    }
                }

                // Update node's Z coordinate with actual height
                node.world_z = height;
                Ok(true)
            }
            Err(e) => {
                if self.config.remove_invalid {
                    debug!(
                        "Node at ({:.1}, {:.1}) not on navmesh: {}",
                        node.world_x, node.world_y, e
                    );
                    Ok(false) // Remove invalid node
                } else if self.config.fallback_on_error {
                    node.world_z = default_z;
                    Ok(true) // Keep with fallback Z
                } else {
                    Err(e)
                }
            }
        }
    }

    /// Validate a batch of nodes.
    ///
    /// This modifies the input vector in place, removing invalid nodes
    /// and updating Z coordinates for valid ones.
    ///
    /// # Arguments
    /// * `map_id` - Map/continent ID for NavBuddy queries
    /// * `nodes` - Vector of nodes to validate (will be modified)
    /// * `default_z` - Fallback Z value for the zone
    ///
    /// # Returns
    /// ValidationResult with statistics about the validation.
    pub fn validate_nodes(
        &self,
        map_id: u32,
        nodes: &mut Vec<DecodedNode>,
        default_z: f32,
    ) -> ValidationResult {
        let total_nodes = nodes.len();
        info!("Validating {} nodes against NavBuddy", total_nodes);

        // Check NavBuddy availability
        if !self.is_available() {
            if self.config.fallback_on_error {
                warn!("NavBuddy not available, using fallback Z values for all nodes");
                for node in nodes.iter_mut() {
                    node.world_z = default_z;
                }
                return ValidationResult {
                    validated: 0,
                    fallback: total_nodes,
                    ..Default::default()
                };
            } else {
                return ValidationResult {
                    errors: vec![format!(
                        "NavBuddy not available at {}",
                        self.config.navbuddy_url
                    )],
                    ..Default::default()
                };
            }
        }

        // PASS 1: Height validation (parallel)
        let height_results: Vec<_> = nodes
            .par_iter()
            .map(|node| {
                // Query height at the node's position
                let height_result = self.client.get_height(map_id, node.world_x, node.world_y, default_z);

                match height_result {
                    Ok(height) => {
                        // Check for underground if enabled
                        if self.config.exclude_caves {
                            let surface_result = self.client.get_height(
                                map_id,
                                node.world_x,
                                node.world_y,
                                height + 500.0,
                            );

                            if let Ok(surface_height) = surface_result {
                                let height_diff = surface_height - height;
                                if height_diff > self.config.cave_threshold {
                                    return NodeValidation::Underground;
                                }
                            }
                        }

                        NodeValidation::Valid(height)
                    }
                    Err(_) => {
                        if self.config.remove_invalid {
                            NodeValidation::NotOnNavmesh
                        } else if self.config.fallback_on_error {
                            NodeValidation::Fallback(default_z)
                        } else {
                            NodeValidation::NotOnNavmesh
                        }
                    }
                }
            })
            .collect();

        // Update Z coordinates for valid nodes and collect indices
        let mut valid_indices: Vec<usize> = Vec::new();
        let mut fallback_indices: Vec<usize> = Vec::new();
        let mut result = ValidationResult::default();

        for (i, validation) in height_results.iter().enumerate() {
            match validation {
                NodeValidation::Valid(height) => {
                    nodes[i].world_z = *height;
                    valid_indices.push(i);
                }
                NodeValidation::Fallback(z) => {
                    nodes[i].world_z = *z;
                    fallback_indices.push(i);
                }
                NodeValidation::NotOnNavmesh => {
                    result.removed_not_on_navmesh += 1;
                }
                NodeValidation::Underground => {
                    result.removed_underground += 1;
                }
                NodeValidation::Unreachable => {
                    // Won't happen in pass 1, but handle it
                    result.removed_unreachable += 1;
                }
            }
        }

        // PASS 2: Connectivity validation (if enabled)
        let mut keep_indices: Vec<usize> = Vec::new();

        if self.config.validate_connectivity && !valid_indices.is_empty() {
            let (reference, start_check_idx) = if let Some(ref_point) = self.config.reference_point {
                info!(
                    "Validating connectivity against configured reference point ({:.1}, {:.1}, {:.1})",
                    ref_point.0, ref_point.1, ref_point.2
                );
                (ref_point, 0) // Check ALL nodes against this external point
            } else {
                // Use the first valid node as the reference point
                let ref_idx = valid_indices[0];
                let ref_node_pos = (nodes[ref_idx].world_x, nodes[ref_idx].world_y, nodes[ref_idx].world_z);

                info!(
                    "Validating connectivity against reference point ({:.1}, {:.1}, {:.1})",
                    ref_node_pos.0, ref_node_pos.1, ref_node_pos.2
                );

                // The reference node is always reachable from itself (when it IS the reference)
                keep_indices.push(ref_idx);
                result.validated += 1;
                
                (ref_node_pos, 1) // Start checking from second node
            };

            // Check connectivity for remaining valid nodes (parallel)
            let nodes_to_check: Vec<usize> = valid_indices.iter().skip(start_check_idx).copied().collect();

            let connectivity_results: Vec<(usize, bool)> = nodes_to_check
                .par_iter()
                .map(|&idx| {
                    let node = &nodes[idx];
                    let target = (node.world_x, node.world_y, node.world_z);

                    match self.client.is_reachable(map_id, reference, target) {
                        Ok(reachable) => (idx, reachable),
                        Err(e) => {
                            debug!(
                                "Connectivity check failed for ({:.1}, {:.1}): {}",
                                node.world_x, node.world_y, e
                            );
                            // On error, assume reachable if fallback is enabled
                            (idx, self.config.fallback_on_error)
                        }
                    }
                })
                .collect();

            // Process connectivity results
            for (idx, reachable) in connectivity_results {
                if reachable {
                    keep_indices.push(idx);
                    result.validated += 1;
                } else {
                    debug!(
                        "Node at ({:.1}, {:.1}, {:.1}) is unreachable (isolated polygon)",
                        nodes[idx].world_x, nodes[idx].world_y, nodes[idx].world_z
                    );
                    result.removed_unreachable += 1;
                }
            }

            // Add fallback indices (they weren't connectivity-checked)
            for idx in fallback_indices {
                keep_indices.push(idx);
                result.fallback += 1;
            }
        } else {
            // No connectivity validation - keep all height-validated nodes
            for idx in valid_indices {
                keep_indices.push(idx);
                result.validated += 1;
            }
            for idx in fallback_indices {
                keep_indices.push(idx);
                result.fallback += 1;
            }
        }

        // Remove invalid nodes by keeping only valid indices
        // We iterate in reverse to avoid index shifting issues
        let mut i = nodes.len();
        while i > 0 {
            i -= 1;
            if !keep_indices.contains(&i) {
                nodes.remove(i);
            }
        }

        info!(
            "Validation complete: {} validated, {} removed (not on navmesh), {} removed (underground), {} removed (unreachable), {} fallback",
            result.validated, result.removed_not_on_navmesh, result.removed_underground, result.removed_unreachable, result.fallback
        );

        result
    }
}

/// Internal enum for tracking node validation state.
#[derive(Debug, Clone)]
enum NodeValidation {
    /// Node is valid with this Z height.
    Valid(f32),
    /// Node is not on navmesh, should be removed.
    NotOnNavmesh,
    /// Node is underground, should be removed.
    Underground,
    /// Node is on isolated polygon (unreachable), should be removed.
    Unreachable,
    /// Node uses fallback Z.
    Fallback(f32),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validation_result_summary() {
        let result = ValidationResult {
            validated: 100,
            removed_not_on_navmesh: 5,
            removed_underground: 3,
            removed_unreachable: 2,
            fallback: 2,
            errors: vec![],
        };

        assert_eq!(result.total_removed(), 10); // 5 + 3 + 2
        assert!(result.summary().contains("100"));
        assert!(result.summary().contains("5"));
        assert!(result.summary().contains("3"));
        assert!(result.summary().contains("unreachable"));
    }

    #[test]
    fn test_config_defaults() {
        let config = ValidatorConfig::default();
        assert!(config.enabled);
        assert!(config.exclude_caves);
        assert!((config.cave_threshold - 15.0).abs() < 0.01);
    }
}
