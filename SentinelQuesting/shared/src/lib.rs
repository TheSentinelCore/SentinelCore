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
//!
//! A third model lives alongside those two:
//!
//! * [`kernel`] — the **kernel artifact** model ([`crate::kernel::RuntimeProfile`]) defined by ADR
//!   `07_RUNTIME_PROFILE_SCHEMA` and executed by the kernel of ADR `08_KERNEL_ARCHITECTURE`. It is
//!   a distinct, self-contained model, not a revision of [`runtime`]: both modules define a type
//!   named `RuntimeProfile`, the ADR-05 one in [`runtime`] is what `sentinel-compiler` and the Lua
//!   runtime consume today, and the two coexist deliberately. Refer to them by full path
//!   ([`crate::runtime::RuntimeProfile`] versus [`crate::kernel::RuntimeProfile`]) rather than
//!   importing both names into one scope.

pub mod authoring;
pub mod error;
pub mod kernel;
pub mod runtime;
