//! Sentinel Questing — canonical data models.
//!
//! This crate is the single source of truth for the two data models defined by the ADRs:
//!
//! * [`authoring`] — the **Project** model ([`crate::authoring::Project`]), the editable
//!   representation authored in the editor and emitted by the importer (ADR `02_DATA_MODEL`).
//! * [`runtime`] — the **Runtime Profile** model ([`crate::runtime::RuntimeProfile`]), the
//!   deterministic, fully-resolved execution artifact produced by the compiler and consumed by
//!   the Lua executor (ADR `05_RUNTIME_AND_EXECUTION_MODEL`).
//!
//! The Rust compiler (`sentinel-compiler`) lowers `authoring` → `runtime`. The Lua runtime
//! never sees the authoring model. Only the runtime JSON crosses the execution boundary
//! (ADR-500, Part 1).

pub mod authoring;
pub mod error;
pub mod runtime;
