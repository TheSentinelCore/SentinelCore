//! Sentinel Compiler — 7-stage compilation pipeline
//!
//! Compiles authored [`sentinel_schema::Profile`]s into immutable
//! [`RuntimeProfile`]s suitable for the runtime execution engine.
//!
//! See: docs/adr/008-compilation-pipeline.md

use sentinel_schema::Profile;

pub mod diagnostics;
pub mod dirty;
pub mod incremental;
pub mod query_client;
pub mod runtime_profile;
pub mod stages;

pub use dirty::{DirtyState, DirtyTracker, StageFlags};
pub use incremental::{compile_incremental, update_tracker};

use diagnostics::Diagnostic;
use query_client::QueryClient;
use runtime_profile::RuntimeProfile;

/// Compile an authored Profile into an immutable Runtime Execution Profile.
///
/// Runs the 7-stage pipeline. Returns `Ok(RuntimeProfile)` on success,
/// or `Err(Vec<Diagnostic>)` if any stage produces hard errors.
pub fn compile(profile: Profile, query_client: &dyn QueryClient) -> Result<RuntimeProfile, Vec<Diagnostic>> {
    // Stage 1: Structural Validation
    let _warnings = stages::structural::validate(&profile)?;

    // Stage 2: Reference Resolution
    let _resolved = stages::resolution::resolve(&profile, query_client)?;

    // Stage 3: Blueprint Expansion
    let _expanded = stages::expansion::expand_blueprints(&_resolved, query_client)?;

    // Stage 4: Dependency Resolution
    let dep_order = stages::dependency::resolve_dependencies(&profile)?;

    // Stage 5: Goal Coverage
    let _goal_diagnostics = stages::goal_coverage::validate_goals(&profile)?;

    // Stage 6: Cross-Operation Optimization
    let optimized = stages::optimization::optimize(&profile, &dep_order)?;

    // Stage 7: Lowering
    let result = stages::lowering::lower(&optimized, profile.profile_id);

    Ok(result.runtime_profile)
}