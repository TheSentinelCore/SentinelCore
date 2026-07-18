//! Sentinel Compiler — 7-stage compilation pipeline
//!
//! Compiles authored [`sentinel_schema::Profile`]s into immutable
//! [`RuntimeProfile`]s suitable for the runtime execution engine.
//!
//! See: docs/adr/008-compilation-pipeline.md

use sentinel_schema::Profile;

pub mod diagnostics;
pub mod query_client;
pub mod runtime_profile;
pub mod stages;

use diagnostics::Diagnostic;
use query_client::QueryClient;
use runtime_profile::RuntimeProfile;

/// Compile an authored Profile into an immutable Runtime Execution Profile.
///
/// Runs the 7-stage pipeline. Returns `Ok(RuntimeProfile)` on success,
/// or `Err(Vec<Diagnostic>)` if any stage produces hard errors.
pub fn compile(_profile: Profile, _query_client: &dyn QueryClient) -> Result<RuntimeProfile, Vec<Diagnostic>> {
    // Stage 1: Structural Validation
    let _structural_warnings = stages::structural::validate(&_profile)?;

    // Stage 2: Reference Resolution (not yet implemented — another ticket)
    // stages::resolution::resolve(&_profile, query_client)?;

    // Stage 3: Blueprint Expansion (not yet implemented — another ticket)

    // Stage 4: Dependency Resolution
    let _dep_order = stages::dependency::resolve_dependencies(&_profile)?;

    // Stage 5: Goal Coverage
    let _goal_diagnostics = stages::goal_coverage::validate_goals(&_profile)?;

    // Stages 6-7: not yet implemented
    todo!("Stages 2, 3, 6, 7 not yet implemented")
}
