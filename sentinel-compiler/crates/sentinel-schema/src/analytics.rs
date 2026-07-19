//! Analytics — Volume 5 §"Analytics"
//! 
//! See: docs/adr/005-schema.md

use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Analytics — Volume 5 §"Analytics"
/// 
/// Profile-level aggregate metrics.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Analytics {
    pub average_time: Duration,
    pub average_xp: f64,
    pub average_gold: f64,
    pub deaths: u32,
}