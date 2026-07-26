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
//!
//! Three further modules carry reference data and shared source rules rather than a model. All
//! exist because the importer's ADR-05 lowering and the compiler's ADR-07 lowering need the same
//! fact, and a second copy of it could drift from the first:
//!
//! * [`zone`] — the measured zone→world coordinate transform, so there is one measured table, not
//!   two.
//! * [`movement`] — the decision *built on* that table: which of the two authored coordinate systems
//!   a movement line is written in, and what a malformed one does. This is the module that used to
//!   be two, and the copy every compile ran was the incomplete one.
//! * [`source`] — the lexical rules of RestedXP guide source (the `--` dev-comment marker), so both
//!   ingests strip prose the same way.

pub mod authoring;
pub mod error;
pub mod kernel;
pub mod movement;
pub mod runtime;
pub mod source;
pub mod zone;
