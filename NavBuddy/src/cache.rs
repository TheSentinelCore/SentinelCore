//! Path cache with spatial quantization for fast repeated lookups.
//!
//! Caches path results keyed by (map_id, quantized_start, quantized_end)
//! so that similar start/end positions within a 5-yard grid cell hit the cache.

use dashmap::DashMap;
use detour::types::Vec3;
use std::time::{Duration, Instant};

/// Grid cell size in yards for spatial quantization.
const CELL_SIZE: f32 = 5.0;

/// Default cache TTL.
const DEFAULT_TTL: Duration = Duration::from_secs(60);

/// Default max entries per map.
const DEFAULT_MAX_ENTRIES: usize = 1000;

/// A cached path entry.
#[derive(Debug, Clone)]
pub struct CachedPath {
    pub waypoints: Vec<Vec3>,
    pub distance: f32,
    pub partial: bool,
    pub created_at: Instant,
}

/// Cache key with spatial quantization.
#[derive(Debug, Clone, Hash, Eq, PartialEq)]
struct PathCacheKey {
    map_id: u32,
    start_cell: (i32, i32, i32),
    end_cell: (i32, i32, i32),
}

/// Quantize a coordinate to a grid cell index.
fn quantize(v: f32) -> i32 {
    (v / CELL_SIZE).floor() as i32
}

/// Quantize a Vec3 to grid cell indices.
fn quantize_vec3(v: &Vec3) -> (i32, i32, i32) {
    (quantize(v.x), quantize(v.y), quantize(v.z))
}

/// Thread-safe path cache using DashMap.
pub struct PathCache {
    cache: DashMap<PathCacheKey, CachedPath>,
    ttl: Duration,
    max_entries: usize,
}

impl PathCache {
    /// Create a new path cache with default settings.
    pub fn new() -> Self {
        Self {
            cache: DashMap::new(),
            ttl: DEFAULT_TTL,
            max_entries: DEFAULT_MAX_ENTRIES,
        }
    }

    /// Look up a cached path.
    pub fn get(&self, map_id: u32, start: &Vec3, end: &Vec3) -> Option<CachedPath> {
        let key = PathCacheKey {
            map_id,
            start_cell: quantize_vec3(start),
            end_cell: quantize_vec3(end),
        };

        if let Some(entry) = self.cache.get(&key) {
            if entry.created_at.elapsed() < self.ttl {
                return Some(entry.clone());
            }
            // Expired — drop the ref before removing
            drop(entry);
            self.cache.remove(&key);
        }

        None
    }

    /// Insert a path into the cache.
    pub fn insert(&self, map_id: u32, start: &Vec3, end: &Vec3, path: CachedPath) {
        // Evict expired entries if we're at capacity
        if self.cache.len() >= self.max_entries {
            self.evict_expired();
        }

        // If still at capacity after eviction, skip insert (LRU would be better but adds complexity)
        if self.cache.len() >= self.max_entries {
            return;
        }

        let key = PathCacheKey {
            map_id,
            start_cell: quantize_vec3(start),
            end_cell: quantize_vec3(end),
        };

        self.cache.insert(key, path);
    }

    /// Remove expired entries.
    fn evict_expired(&self) {
        self.cache.retain(|_, v| v.created_at.elapsed() < self.ttl);
    }

    /// Get the number of cached entries (for health endpoint).
    pub fn len(&self) -> usize {
        self.cache.len()
    }

    /// Check if cache is empty.
    pub fn is_empty(&self) -> bool {
        self.cache.is_empty()
    }
}

impl Default for PathCache {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_quantize() {
        assert_eq!(quantize(0.0), 0);
        assert_eq!(quantize(4.9), 0);
        assert_eq!(quantize(5.0), 1);
        assert_eq!(quantize(-1.0), -1);
        assert_eq!(quantize(-5.0), -1);
        assert_eq!(quantize(-5.1), -2);
    }

    #[test]
    fn test_cache_hit_same_cell() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        cache.insert(
            0,
            &start,
            &end,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
                created_at: Instant::now(),
            },
        );

        // Same cell — should hit
        let nearby_start = Vec3::new(2.0, 3.0, 4.0);
        let nearby_end = Vec3::new(101.0, 201.0, 51.0);
        assert!(cache.get(0, &nearby_start, &nearby_end).is_some());
    }

    #[test]
    fn test_cache_miss_different_cell() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        cache.insert(
            0,
            &start,
            &end,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
                created_at: Instant::now(),
            },
        );

        // Different cell — should miss
        let far_start = Vec3::new(50.0, 50.0, 3.0);
        assert!(cache.get(0, &far_start, &end).is_none());
    }

    #[test]
    fn test_cache_miss_different_map() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        cache.insert(
            0,
            &start,
            &end,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
                created_at: Instant::now(),
            },
        );

        // Different map — should miss
        assert!(cache.get(1, &start, &end).is_none());
    }
}
