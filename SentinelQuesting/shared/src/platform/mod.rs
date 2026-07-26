//! Platform (behavior authoring) model — ADR `09_BEHAVIOR_AUTHORING_PLATFORM` + `09a` §1.
//!
//! A fourth model alongside [`crate::authoring`], [`crate::runtime`] and [`crate::kernel`]. It
//! describes a **Campaign**: a set of graphs whose nodes carry authored `intent` and derived
//! `resolved` state. `sentinel-resolver` lowers a Campaign into an [`ExecutionPlan`], which is the
//! only shape that reaches the runtime.
//!
//! Two rules from ADR 09a are load-bearing here:
//!
//! * `intent` is the source of truth; `resolved` is derived and re-resolvable at any time. The
//!   types make that explicit — [`Resolved`] is an `Option` on [`Node`], and it carries the
//!   `db_fingerprint` + `resolver_version` it was produced against so staleness is detectable.
//! * A task lowers only to the **existing** [`crate::runtime::RuntimeAction`] vocabulary. That
//!   vocabulary is a frozen contract in this phase; a task needing a new action is a runtime
//!   change with its own review, not an editor feature.

mod campaign;
mod entity_ref;
mod graph;
mod plan;

pub use campaign::{
    Campaign, CampaignImport, ConditionDef, NodeOverride, Variable, VariableType, VariableValue,
};
pub use entity_ref::{EntityKind, EntityRef, EntityRefError};
pub use graph::{Edge, Graph, Intent, IntentValue, Node, Resolved};
pub use plan::{compute_content_hash, ExecutionPlan, PlanOperation, PlanTransition};

/// Schema version stamped on every [`Campaign`] and [`ExecutionPlan`] (ADR 09a §1.3, §1.4).
pub const PLATFORM_SCHEMA_VERSION: u32 = 3;

fn default_schema_version() -> u32 {
    PLATFORM_SCHEMA_VERSION
}
