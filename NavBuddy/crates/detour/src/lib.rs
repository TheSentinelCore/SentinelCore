//! Safe Rust wrappers for Recast/Detour navigation library.
//!
//! This crate provides idiomatic, safe Rust types wrapping the raw FFI bindings.

pub mod types;
pub mod error;
pub mod mesh;
pub mod query;
pub mod filter;
pub mod pool;

pub use types::Vec3;
pub use error::DetourError;
pub use mesh::NavMesh;
pub use query::NavMeshQuery;
pub use filter::QueryFilter;
pub use pool::{QueryPool, PooledQuery};
