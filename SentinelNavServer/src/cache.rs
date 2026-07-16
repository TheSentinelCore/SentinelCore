//! Path cache with spatial quantization for fast repeated lookups.
//!
//! Uses moka's concurrent LRU cache keyed by (map_id, quantized_start, quantized_end)
//! so that similar start/end positions within a 5-yard grid cell hit the cache.

use detour::types::Vec3;
use moka::sync::Cache;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

/// Grid cell size in yards for spatial quantization.
const CELL_SIZE: f32 = 5.0;

/// Default cache TTL.
const DEFAULT_TTL: Duration = Duration::from_secs(60);

/// Default max entries.
const DEFAULT_MAX_ENTRIES: u64 = 1000;

/// A cached path entry.
#[derive(Debug, Clone)]
pub struct CachedPath {
    pub waypoints: Vec<Vec3>,
    pub distance: f32,
    pub partial: bool,
}

/// Cache key with spatial quantization and options hash.
#[derive(Debug, Clone, Hash, Eq, PartialEq)]
struct PathCacheKey {
    map_id: u32,
    start_cell: (i32, i32, i32),
    end_cell: (i32, i32, i32),
    options_hash: u64,
}

/// Quantize a coordinate to a grid cell index.
fn quantize(v: f32) -> i32 {
    (v / CELL_SIZE).floor() as i32
}

/// Quantize a Vec3 to grid cell indices.
fn quantize_vec3(v: &Vec3) -> (i32, i32, i32) {
    (quantize(v.x), quantize(v.y), quantize(v.z))
}

/// Thread-safe path cache using moka LRU.
pub struct PathCache {
    cache: Cache<PathCacheKey, CachedPath>,
    hits: AtomicU64,
    misses: AtomicU64,
}

impl PathCache {
    /// Create a new path cache with default settings.
    pub fn new() -> Self {
        Self {
            cache: Cache::builder()
                .max_capacity(DEFAULT_MAX_ENTRIES)
                .time_to_live(DEFAULT_TTL)
                .build(),
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
        }
    }

    /// Look up a cached path.
    pub fn get(&self, map_id: u32, start: &Vec3, end: &Vec3, options_hash: u64) -> Option<CachedPath> {
        let key = PathCacheKey {
            map_id,
            start_cell: quantize_vec3(start),
            end_cell: quantize_vec3(end),
            options_hash,
        };

        match self.cache.get(&key) {
            Some(entry) => {
                self.hits.fetch_add(1, Ordering::Relaxed);
                Some(entry)
            }
            None => {
                self.misses.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }

    /// Insert a path into the cache.
    pub fn insert(&self, map_id: u32, start: &Vec3, end: &Vec3, options_hash: u64, path: CachedPath) {
        let key = PathCacheKey {
            map_id,
            start_cell: quantize_vec3(start),
            end_cell: quantize_vec3(end),
            options_hash,
        };
        self.cache.insert(key, path);
    }

    /// Get the number of cached entries (for health endpoint).
    pub fn len(&self) -> usize {
        self.cache.entry_count() as usize
    }

    /// Check if cache is empty.
    pub fn is_empty(&self) -> bool {
        self.cache.entry_count() == 0
    }

    /// Get cache hit count.
    pub fn hit_count(&self) -> u64 {
        self.hits.load(Ordering::Relaxed)
    }

    /// Get cache miss count.
    pub fn miss_count(&self) -> u64 {
        self.misses.load(Ordering::Relaxed)
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
            0,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
            },
        );

        // Same cell, same options — should hit
        let nearby_start = Vec3::new(2.0, 3.0, 4.0);
        let nearby_end = Vec3::new(101.0, 201.0, 51.0);
        assert!(cache.get(0, &nearby_start, &nearby_end, 0).is_some());
        assert_eq!(cache.hit_count(), 1);
        assert_eq!(cache.miss_count(), 0);
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
            0,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
            },
        );

        // Different cell — should miss
        let far_start = Vec3::new(50.0, 50.0, 3.0);
        assert!(cache.get(0, &far_start, &end, 0).is_none());
        assert_eq!(cache.miss_count(), 1);
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
            0,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
            },
        );

        // Different map — should miss
        assert!(cache.get(1, &start, &end, 0).is_none());
    }

    #[test]
    fn test_cache_miss_different_options() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        cache.insert(
            0,
            &start,
            &end,
            42,
            CachedPath {
                waypoints: vec![start, end],
                distance: 100.0,
                partial: false,
            },
        );

        // Same cell, different options hash — should miss
        assert!(cache.get(0, &start, &end, 99).is_none());
        assert_eq!(cache.miss_count(), 1);

        // Same options hash — should hit
        assert!(cache.get(0, &start, &end, 42).is_some());
        assert_eq!(cache.hit_count(), 1);
    }

    #[test]
    fn test_cache_metrics() {
        let cache = PathCache::new();
        let start = Vec3::new(1.0, 2.0, 3.0);
        let end = Vec3::new(100.0, 200.0, 50.0);

        // Miss
        cache.get(0, &start, &end, 0);
        assert_eq!(cache.hit_count(), 0);
        assert_eq!(cache.miss_count(), 1);

        // Insert + hit
        cache.insert(0, &start, &end, 0, CachedPath {
            waypoints: vec![start, end],
            distance: 100.0,
            partial: false,
        });
        cache.get(0, &start, &end, 0);
        assert_eq!(cache.hit_count(), 1);
        assert_eq!(cache.miss_count(), 1);
    }
}
