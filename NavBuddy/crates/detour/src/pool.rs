//! Thread-safe query pool for NavMeshQuery instances.

use crate::error::DetourError;
use crate::filter::QueryFilter;
use crate::mesh::NavMesh;
use crate::query::NavMeshQuery;
use parking_lot::Mutex;
use std::ops::Deref;
use std::sync::Arc;

/// Default maximum pool size.
pub const DEFAULT_MAX_POOL_SIZE: usize = 32;

/// Thread-safe pool of NavMeshQuery instances.
///
/// Since NavMeshQuery is not thread-safe (it has internal mutable state),
/// we use a pool pattern where each thread acquires exclusive access to
/// a query instance.
///
/// # Thread Safety
///
/// QueryPool is `Send + Sync`. The pool uses a mutex to protect the
/// vector of available queries, and each acquired query is exclusively
/// owned by the acquiring thread until returned.
///
/// # Example
///
/// ```ignore
/// let mesh = Arc::new(NavMesh::new()?);
/// let pool = QueryPool::new(mesh, 4, 2048)?;
///
/// // Acquire a query from the pool
/// let query = pool.acquire()?;
/// let (poly_ref, nearest_pt) = query.find_nearest_poly(
///     center,
///     half_extents,
///     pool.filter(),
/// )?;
/// // Query automatically returned to pool when `query` is dropped
/// ```
pub struct QueryPool {
    mesh: Arc<NavMesh>,
    pool: Mutex<Vec<NavMeshQuery>>,
    filter: Arc<QueryFilter>,
    max_nodes: u32,
    max_size: usize,
}

impl QueryPool {
    /// Create a new query pool.
    ///
    /// # Arguments
    /// * `mesh` - The navmesh to query
    /// * `initial_size` - Number of queries to pre-allocate
    /// * `max_nodes` - Maximum nodes per query (affects memory usage)
    ///
    /// # Returns
    /// A new QueryPool with default filter and max size.
    pub fn new(mesh: Arc<NavMesh>, initial_size: usize, max_nodes: u32) -> Result<Self, DetourError> {
        Self::with_config(mesh, initial_size, max_nodes, DEFAULT_MAX_POOL_SIZE, None)
    }

    /// Create a new query pool with full configuration.
    ///
    /// # Arguments
    /// * `mesh` - The navmesh to query
    /// * `initial_size` - Number of queries to pre-allocate
    /// * `max_nodes` - Maximum nodes per query (affects memory usage)
    /// * `max_size` - Maximum number of queries in the pool
    /// * `filter` - Optional custom QueryFilter (default filter used if None)
    pub fn with_config(
        mesh: Arc<NavMesh>,
        initial_size: usize,
        max_nodes: u32,
        max_size: usize,
        filter: Option<QueryFilter>,
    ) -> Result<Self, DetourError> {
        let filter = Arc::new(filter.unwrap_or_default());

        // Pre-allocate queries up to initial_size
        let pool: Vec<NavMeshQuery> = (0..initial_size.min(max_size))
            .filter_map(|_| NavMeshQuery::new(mesh.clone(), max_nodes).ok())
            .collect();

        Ok(Self {
            mesh,
            pool: Mutex::new(pool),
            filter,
            max_nodes,
            max_size,
        })
    }

    /// Get the shared query filter.
    ///
    /// This filter is used by all queries in the pool. Use this when
    /// calling query methods that require a filter.
    pub fn filter(&self) -> &QueryFilter {
        &self.filter
    }

    /// Acquire a query from the pool.
    ///
    /// Returns a RAII guard that automatically returns the query
    /// to the pool when dropped. If the pool is empty, a new query
    /// is allocated.
    ///
    /// # Returns
    /// A `PooledQuery` guard that dereferences to `NavMeshQuery`.
    pub fn acquire(&self) -> Result<PooledQuery<'_>, DetourError> {
        let query = {
            let mut pool = self.pool.lock();
            pool.pop()
        };

        let query = match query {
            Some(q) => q,
            None => NavMeshQuery::new(self.mesh.clone(), self.max_nodes)?,
        };

        Ok(PooledQuery {
            query: Some(query),
            pool: self,
        })
    }

    /// Return a query to the pool.
    ///
    /// If the pool has reached max_size, the query is dropped instead
    /// of being returned to the pool.
    fn return_query(&self, query: NavMeshQuery) {
        let mut pool = self.pool.lock();
        if pool.len() < self.max_size {
            pool.push(query);
        }
        // If at max capacity, query is dropped here
    }

    /// Get current number of queries in the pool.
    pub fn size(&self) -> usize {
        self.pool.lock().len()
    }

    /// Get the maximum pool size.
    pub fn max_size(&self) -> usize {
        self.max_size
    }

    /// Get the mesh reference.
    pub fn mesh(&self) -> &Arc<NavMesh> {
        &self.mesh
    }
}

// SAFETY: QueryPool is thread-safe because:
// - The pool vector is protected by a Mutex
// - Each acquired NavMeshQuery is exclusively owned by one thread
// - The filter is immutable and wrapped in Arc
unsafe impl Send for QueryPool {}
unsafe impl Sync for QueryPool {}

/// RAII guard for a pooled query.
///
/// Automatically returns the query to the pool when dropped.
/// Dereferences to `NavMeshQuery` for convenient method access.
pub struct PooledQuery<'a> {
    query: Option<NavMeshQuery>,
    pool: &'a QueryPool,
}

impl<'a> PooledQuery<'a> {
    /// Get a reference to the underlying query.
    pub fn query(&self) -> &NavMeshQuery {
        self.query.as_ref().expect("Query already returned to pool")
    }
}

impl<'a> Deref for PooledQuery<'a> {
    type Target = NavMeshQuery;

    fn deref(&self) -> &Self::Target {
        self.query()
    }
}

impl<'a> Drop for PooledQuery<'a> {
    fn drop(&mut self) {
        if let Some(query) = self.query.take() {
            self.pool.return_query(query);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mesh::NavMeshParams;

    fn create_test_mesh() -> Arc<NavMesh> {
        let mut mesh = NavMesh::new().unwrap();
        let params = NavMeshParams {
            orig: [0.0, 0.0, 0.0],
            tile_width: 533.33333,
            tile_height: 533.33333,
            max_tiles: 1024,
            max_polys: 1024,
        };
        mesh.init(&params).unwrap();
        Arc::new(mesh)
    }

    #[test]
    fn test_pool_create() {
        let mesh = create_test_mesh();
        let pool = QueryPool::new(mesh, 4, 2048).unwrap();
        assert_eq!(pool.size(), 4);
    }

    #[test]
    fn test_pool_acquire_return() {
        let mesh = create_test_mesh();
        let pool = QueryPool::new(mesh, 2, 2048).unwrap();
        assert_eq!(pool.size(), 2);

        {
            let _query = pool.acquire().unwrap();
            assert_eq!(pool.size(), 1);
        }
        // Query returned to pool when dropped
        assert_eq!(pool.size(), 2);
    }

    #[test]
    fn test_pool_max_size_respected() {
        let mesh = create_test_mesh();
        let pool = QueryPool::with_config(mesh, 2, 2048, 2, None).unwrap();
        assert_eq!(pool.size(), 2);
        assert_eq!(pool.max_size(), 2);

        // Acquire all queries
        let q1 = pool.acquire().unwrap();
        let q2 = pool.acquire().unwrap();
        // Force allocation of a third
        let q3 = pool.acquire().unwrap();

        assert_eq!(pool.size(), 0);

        // Drop all three
        drop(q1);
        drop(q2);
        drop(q3);

        // Pool should only have 2 (max_size), third was discarded
        assert_eq!(pool.size(), 2);
    }

    #[test]
    fn test_pool_filter_access() {
        let mesh = create_test_mesh();
        let pool = QueryPool::new(mesh, 1, 2048).unwrap();

        // Check we can access the filter
        assert_eq!(pool.filter().include_flags(), 0xFFFF);
    }

    #[test]
    fn test_pool_send_sync() {
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}

        assert_send::<QueryPool>();
        assert_sync::<QueryPool>();
    }
}
