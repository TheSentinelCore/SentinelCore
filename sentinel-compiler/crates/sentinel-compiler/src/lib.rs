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
    // stages::structural::validate(&_profile)?;

    // Stages 2-7 will be implemented in later tickets.
    // For now, only Stage 1 is wired up.
    todo!("Stages 2-7 not yet implemented")
}
