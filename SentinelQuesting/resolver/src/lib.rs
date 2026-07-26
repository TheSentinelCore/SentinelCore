//! Sentinel resolver — lowers authored intent into a runtime execution plan.
//!
//! This is a LIBRARY, not a service (ADR 09 §5). QueryServer, a CLI, CI, and batch generation all
//! call it; HTTP is one transport among several, never the home of the logic.
//!
//! Resolution is PURE: the same intent plus the same `db_fingerprint` must produce byte-identical
//! output. That is what makes bulk re-resolution diffable and the whole pipeline testable with no
//! game client.
//!
//! ```text
//! Campaign ──flatten imports/overrides──▶ Graph ──topological order──▶ ExecutionPlan
//!                                          │
//!                                          └─ per node: TaskRegistry ──lower──▶ [RuntimeAction]
//! ```
//!
//! Three boundaries are load-bearing:
//!
//! * [`TaskRegistry`] is the platform seam — the core registers no task types, and the IDE's
//!   Properties panel renders from [`Field`] rather than from hand-written per-task code.
//! * [`ResolverDb`] is the only way in to game data. No connection is opened here and no request
//!   is issued, so the crate resolves a campaign with no sqlite file and no server.
//! * The [`sentinel_models::runtime::RuntimeAction`] vocabulary is frozen. A task that needs a new
//!   action is a runtime change with its own review.

mod db;
mod diagnostic;
mod registry;
mod resolve;
mod tasks;

pub use db::{InMemoryDb, ResolverDb, Spawn};
pub use diagnostic::{Diagnostic, Severity};
pub use registry::{
    Field, FieldKind, LowerFn, RegistryError, TaskRegistry, TaskType, ValidateFn, ValidationRule,
};
pub use resolve::{resolve, CampaignLibrary, NoImports, Resolver};
pub use tasks::questing_task_types;

/// Stamped into [`sentinel_models::platform::Resolved::resolver_version`] by callers that persist
/// resolution back onto a campaign, so a node resolved by an older resolver is detectable.
pub const RESOLVER_VERSION: &str = env!("CARGO_PKG_VERSION");
