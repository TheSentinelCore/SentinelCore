//! Retry Policy — Volume 5 §"Retry Policy"
//! 
//! See: docs/adr/005-schema.md

use serde::{Deserialize, Serialize};

/// Retry Policy — Volume 5 §"Retry Policy"
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RetryPolicy {
    pub retries: u32,
    pub delay_ms: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self { retries: 3, delay_ms: 1000 }
    }
}

impl RetryPolicy {
    pub fn new(retries: u32, delay_ms: u64) -> Self {
        Self { retries, delay_ms }
    }
    
    pub fn none() -> Self {
        Self { retries: 0, delay_ms: 0 }
    }
    
    pub fn aggressive() -> Self {
        Self { retries: 5, delay_ms: 500 }
    }
    
    pub fn conservative() -> Self {
        Self { retries: 2, delay_ms: 5000 }
    }
}