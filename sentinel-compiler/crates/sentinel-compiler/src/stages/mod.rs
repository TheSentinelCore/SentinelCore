pub mod structural;
pub mod resolution;
pub mod dependency;
pub mod goal_coverage;
pub mod expansion;
pub mod optimization;
pub mod lowering;

// Re-export key intermediate types for the incremental compile wrappers.
pub use resolution::ResolvedProfile;
pub use expansion::ExpandedProfile;
pub use dependency::DependencyOrder;
pub use optimization::OptimizedProfile;

// ---------------------------------------------------------------------------
// Helper functions for incremental compilation stage skipping
// ---------------------------------------------------------------------------

/// Build a default [`ResolvedProfile`] from a bare [`Profile`] when
/// Stages 1-3 are skipped (no resolution needed).
pub fn resolved_profile_from_profile(
    profile: &sentinel_schema::Profile,
) -> ResolvedProfile {
    ResolvedProfile {
        profile: profile.clone(),
        resolved_npcs: std::collections::HashMap::new(),
        resolved_quests: std::collections::HashMap::new(),
        resolved_creatures: std::collections::HashMap::new(),
    }
}

/// Build a default [`ExpandedProfile`] from a [`ResolvedProfile`] when
/// Stages 1-3 are skipped (no expansion needed).
pub fn expanded_profile_from_resolved(
    resolved: &ResolvedProfile,
) -> ExpandedProfile {
    ExpandedProfile {
        profile: resolved.profile.clone(),
        expansion_map: std::collections::HashMap::new(),
    }
}

/// Build an empty [`DependencyOrder`] when Stage 4 is skipped.
pub fn empty_dependency_order() -> DependencyOrder {
    DependencyOrder {
        ordered: Vec::new(),
        order_map: std::collections::HashMap::new(),
    }
}

/// Build a pass-through [`OptimizedProfile`] from a bare [`Profile`] and
/// [`DependencyOrder`] when Stage 6 is skipped (no optimization needed).
pub fn optimized_profile_from_profile(
    profile: &sentinel_schema::Profile,
    _dep_order: &DependencyOrder,
) -> Result<OptimizedProfile, Vec<crate::diagnostics::Diagnostic>> {
    Ok(OptimizedProfile {
        profile: profile.clone(),
        optimizations_applied: Vec::new(),
    })
}
