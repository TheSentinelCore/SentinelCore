//! GatherBuddy profile generator
//!
//! Converts optimized routes into GatherBuddy-compatible JSON profiles.

mod profile;

pub use profile::{
    Blackspot, Profile, ProfileGenerator, ProfileMetadata, ProfileRequirements, ProfileSettings,
    SkillRequirements, Waypoint,
};
