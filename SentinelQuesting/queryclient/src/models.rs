//! Data transfer objects for QueryServer endpoints (ADR `01_ARCHITECTURE` §10).
//!
//! These are defined once in `sentinel-query-types` and re-exported here so existing
//! `use sentinel_queryclient::models::*` imports keep working. See that crate for docs.

pub use sentinel_query_types::*;
