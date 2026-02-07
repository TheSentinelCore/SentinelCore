//! QueryFilter wrapper for controlling pathfinding behavior.

use std::ptr::NonNull;

use crate::error::DetourError;

/// Query filter for controlling pathfinding behavior.
///
/// QueryFilter controls which polygons are considered during pathfinding
/// based on flags and area costs.
///
/// # Thread Safety
///
/// QueryFilter is `Send + Sync` because it's immutable after construction.
/// Use the builder methods to configure before passing to NavMeshQuery.
pub struct QueryFilter {
    ptr: NonNull<detour_sys::dtQueryFilter>,
}

impl QueryFilter {
    /// Create a new filter with default settings.
    ///
    /// Default: include_flags = 0xFFFF, exclude_flags = 0, all area costs = 1.0
    pub fn new() -> Result<Self, DetourError> {
        let ptr = unsafe { detour_sys::wrapper_dtAllocQueryFilter() };
        NonNull::new(ptr)
            .map(|ptr| Self { ptr })
            .ok_or(DetourError::AllocationFailed)
    }

    /// Set flags that must be present on polygons for them to be included.
    pub fn set_include_flags(&mut self, flags: u16) {
        unsafe {
            detour_sys::wrapper_dtQueryFilter_setIncludeFlags(
                self.ptr.as_ptr(),
                flags,
            );
        }
    }

    /// Get the current include flags.
    pub fn include_flags(&self) -> u16 {
        unsafe {
            detour_sys::wrapper_dtQueryFilter_getIncludeFlags(self.ptr.as_ptr())
        }
    }

    /// Set flags that must NOT be present on polygons for them to be included.
    pub fn set_exclude_flags(&mut self, flags: u16) {
        unsafe {
            detour_sys::wrapper_dtQueryFilter_setExcludeFlags(
                self.ptr.as_ptr(),
                flags,
            );
        }
    }

    /// Get the current exclude flags.
    pub fn exclude_flags(&self) -> u16 {
        unsafe {
            detour_sys::wrapper_dtQueryFilter_getExcludeFlags(self.ptr.as_ptr())
        }
    }

    /// Set the cost multiplier for an area type.
    ///
    /// # Arguments
    /// * `area` - Area index (0-63)
    /// * `cost` - Cost multiplier (higher = more expensive to traverse)
    pub fn set_area_cost(&mut self, area: u8, cost: f32) {
        if area < 64 {
            unsafe {
                detour_sys::wrapper_dtQueryFilter_setAreaCost(
                    self.ptr.as_ptr(),
                    area as i32,
                    cost,
                );
            }
        }
    }

    /// Get the cost multiplier for an area type.
    pub fn area_cost(&self, area: u8) -> f32 {
        if area < 64 {
            unsafe {
                detour_sys::wrapper_dtQueryFilter_getAreaCost(
                    self.ptr.as_ptr(),
                    area as i32,
                )
            }
        } else {
            1.0
        }
    }

    /// Get raw pointer for FFI calls.
    pub(crate) fn as_ptr(&self) -> *const detour_sys::dtQueryFilter {
        self.ptr.as_ptr()
    }
}

impl Default for QueryFilter {
    fn default() -> Self {
        let mut filter = Self::new().expect("Failed to allocate QueryFilter");
        // Set WoW-appropriate default area costs
        filter.set_area_cost(0, 1.0);    // Ground
        filter.set_area_cost(1, 1.0);    // Road
        filter.set_area_cost(2, 10.0);   // Water (expensive)
        filter.set_area_cost(3, 100.0);  // Lava (very expensive)
        filter
    }
}

impl Drop for QueryFilter {
    fn drop(&mut self) {
        unsafe {
            detour_sys::wrapper_dtFreeQueryFilter(self.ptr.as_ptr());
        }
    }
}

// SAFETY: QueryFilter is thread-safe because:
// - The underlying dtQueryFilter only stores flags and area costs
// - These are read-only during pathfinding queries
// - Modifications should be done before sharing
unsafe impl Send for QueryFilter {}
unsafe impl Sync for QueryFilter {}

/// Builder for QueryFilter with fluent API.
pub struct QueryFilterBuilder {
    include_flags: u16,
    exclude_flags: u16,
    area_costs: [f32; 64],
}

impl QueryFilterBuilder {
    /// Create a new builder with default values.
    pub fn new() -> Self {
        let mut area_costs = [1.0f32; 64];
        // WoW defaults
        area_costs[2] = 10.0;   // Water
        area_costs[3] = 100.0;  // Lava

        Self {
            include_flags: 0xFFFF,
            exclude_flags: 0,
            area_costs,
        }
    }

    /// Set include flags.
    pub fn include_flags(mut self, flags: u16) -> Self {
        self.include_flags = flags;
        self
    }

    /// Set exclude flags.
    pub fn exclude_flags(mut self, flags: u16) -> Self {
        self.exclude_flags = flags;
        self
    }

    /// Set the cost for an area type.
    pub fn area_cost(mut self, area: u8, cost: f32) -> Self {
        if (area as usize) < self.area_costs.len() {
            self.area_costs[area as usize] = cost;
        }
        self
    }

    /// Build the QueryFilter.
    pub fn build(self) -> Result<QueryFilter, DetourError> {
        let mut filter = QueryFilter::new()?;
        filter.set_include_flags(self.include_flags);
        filter.set_exclude_flags(self.exclude_flags);
        for (i, &cost) in self.area_costs.iter().enumerate() {
            filter.set_area_cost(i as u8, cost);
        }
        Ok(filter)
    }
}

impl Default for QueryFilterBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_filter_allocate_free() {
        let filter = QueryFilter::new().unwrap();
        drop(filter);
    }

    #[test]
    fn test_filter_default_values() {
        let filter = QueryFilter::new().unwrap();
        assert_eq!(filter.include_flags(), 0xFFFF);
        assert_eq!(filter.exclude_flags(), 0);
        assert_eq!(filter.area_cost(0), 1.0);
    }

    #[test]
    fn test_filter_set_flags() {
        let mut filter = QueryFilter::new().unwrap();
        filter.set_include_flags(0x0F);
        filter.set_exclude_flags(0xF0);
        assert_eq!(filter.include_flags(), 0x0F);
        assert_eq!(filter.exclude_flags(), 0xF0);
    }

    #[test]
    fn test_filter_set_area_cost() {
        let mut filter = QueryFilter::new().unwrap();
        filter.set_area_cost(5, 2.5);
        assert_eq!(filter.area_cost(5), 2.5);
    }

    #[test]
    fn test_filter_builder() {
        let filter = QueryFilterBuilder::new()
            .include_flags(0x0F)
            .exclude_flags(0xF0)
            .area_cost(10, 5.0)
            .build()
            .unwrap();

        assert_eq!(filter.include_flags(), 0x0F);
        assert_eq!(filter.exclude_flags(), 0xF0);
        assert_eq!(filter.area_cost(10), 5.0);
    }

    #[test]
    fn test_filter_send_sync() {
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}

        assert_send::<QueryFilter>();
        assert_sync::<QueryFilter>();
    }
}
