use uuid::Uuid;
use chrono::{DateTime, Utc};
use sentinel_schema::{Condition, ExitConditions, OperationGoal, RetryPolicy};
use sentinel_schema::action::ActionPayload;

/// Immutable, fully resolved execution profile — the compiler's output.
pub struct RuntimeProfile {
    pub schema_version: String,
    pub compiled_at: DateTime<Utc>,
    pub compiler_version: String,
    pub source_profile_id: Uuid,
    pub source_profile_hash: String,
    pub operations: Vec<RuntimeOperation>,
}

/// A compiled operation ready for the runtime engine.
pub struct RuntimeOperation {
    pub id: Uuid,
    pub name: String,
    pub entry_conditions: Vec<Condition>,
    pub exit_conditions: ExitConditions,
    pub goals: Vec<OperationGoal>,
    pub actions: Vec<RuntimeAction>,
}

/// A compiled action ready for the runtime engine.
pub struct RuntimeAction {
    pub id: Uuid,
    pub payload: ResolvedActionPayload,
    pub retry_policy: RetryPolicy,
    pub timeout_ms: u64,
    pub generated_from: Option<Uuid>,
}

/// ResolvedActionPayload mirrors ActionPayload but with all references
/// fully resolved. For Stage 1 scaffold, this is just a wrapper around
/// ActionPayload — reference resolution happens in Stage 2.
pub struct ResolvedActionPayload(pub ActionPayload);
