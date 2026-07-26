//! Domain task plugins.
//!
//! Questing is the first domain, registered through the same [`crate::TaskRegistry::register`]
//! any other would use (ADR 09 §4). It is not privileged and it is not baked into the core — a
//! later domain adds a sibling module here and touches nothing else.

pub mod questing;

pub use questing::questing_task_types;
