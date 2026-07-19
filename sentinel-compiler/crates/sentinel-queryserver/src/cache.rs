//! Cache layer — Volume 4 §25
//! 
//! LRU cache with 60 second TTL for NPC, Quest, Creature, Vendor, Trainer, Area queries

use moka::future::Cache;
use serde_json::Value;
use std::time::Duration;

/// Cache key prefixes for different query types
pub mod keys {
    pub const QUEST_SEARCH: &str = "quest_search";
    pub const QUEST_DETAILS: &str = "quest_details";
    pub const QUEST_NPCS: &str = "quest_npcs";
    pub const NPC_DETAILS: &str = "npc_details";
    pub const NPC_SEARCH: &str = "npc_search";
    pub const NPC_NEARBY: &str = "npc_nearby";
    pub const CREATURE_DETAILS: &str = "creature_details";
    pub const CREATURE_SPAWNS: &str = "creature_spawns";
    pub const VENDOR_DETAILS: &str = "vendor_details";
    pub const TRAINER_DETAILS: &str = "trainer_details";
    pub const FLIGHT_MASTERS: &str = "flight_masters";
    pub const MAILBOXES: &str = "mailboxes";
    pub const INNKEEPERS: &str = "innkeepers";
    pub const AREA_QUERY: &str = "area_query";
    pub const POLYGON_ANALYSIS: &str = "polygon_analysis";
    pub const ROUTE_ANALYSIS: &str = "route_analysis";
    pub const QUEST_HUB_ANALYSIS: &str = "quest_hub_analysis";
    pub const VALIDATION: &str = "validation";
    pub const SEARCH_ALL: &str = "search_all";
    pub const BLUEPRINT_SUGGEST: &str = "blueprint_suggest";
    pub const GRIND_SUGGEST: &str = "grind_suggest";
    pub const ITEM_DROPS: &str = "item_drops";
    pub const WORLD_GRAPH: &str = "world_graph";
}

/// Create the global cache with Volume 4 §25 settings
pub fn create_cache() -> Cache<String, Value> {
    Cache::builder()
        .max_capacity(10_000)
        .time_to_live(Duration::from_secs(60))  // 60 seconds TTL per Volume 4 §25
        .time_to_idle(Duration::from_secs(30))
        .build()
}

/// Cache statistics for health endpoint
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CacheStats {
    pub entries: u64,
    pub hit_rate: f64,
    pub memory_bytes: u64,
}

impl CacheStats {
    pub fn from_cache(cache: &Cache<String, Value>) -> Self {
        Self {
            entries: cache.entry_count(),
            hit_rate: 0.0, // moka doesn't expose hit_rate directly
            memory_bytes: cache.weighted_size(),
        }
    }
}