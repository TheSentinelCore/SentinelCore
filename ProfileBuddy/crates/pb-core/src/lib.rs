//! ProfileBuddy Core Library
//!
//! This crate provides the core functionality for ProfileBuddy:
//! - GatherMate2 Lua file parsing
//! - Route optimization algorithms (TSP, Cluster, Density)
//! - GatherBuddy profile generation
//!
//! # Example
//!
//! ```no_run
//! use pb_core::{Parser, ProfileGenerator, GameVersion, Algorithm, OptimizerConfig, create_optimizer};
//!
//! // Parse GatherMate2 data
//! let parser = Parser::new(GameVersion::Era);
//! let db = parser.parse_all("path/to/GatherMate2_Data/Era").unwrap();
//!
//! // Filter by zone
//! let zone = db.get_zone(1429).unwrap(); // Elwynn Forest
//! let nodes: Vec<_> = zone.all_nodes().cloned().collect();
//!
//! // Optimize route
//! let optimizer = create_optimizer(Algorithm::Tsp);
//! let config = OptimizerConfig::default();
//! let route = optimizer.optimize(&nodes, &config);
//!
//! // Generate profile
//! let generator = ProfileGenerator::new();
//! let profile = generator.generate(&route, "Elwynn Forest").unwrap();
//! ```

pub mod data;
pub mod error;
pub mod generator;
pub mod optimizer;
pub mod parser;
pub mod validator;

// Re-export main types
pub use data::{GameVersion, NodeCategory, ZoneBounds, ZONE_DATABASE};
pub use error::{Error, Result};
pub use generator::{Profile, ProfileGenerator};
pub use optimizer::{Algorithm, OptimizerConfig, RandomStrategy, Route, RouteOptimizer, create_optimizer};
pub use parser::{DecodedNode, NodeDatabase, Parser, RawNode};
pub use validator::{HeightValidator, NavBuddyClient, ValidationResult, ValidatorConfig};
