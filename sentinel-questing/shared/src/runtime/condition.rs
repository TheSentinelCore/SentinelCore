//! Typed, executable condition (ADR `05` Part 4 + `02_DATA_MODEL` §23 grammar).
//!
//! The authoring model stores conditions as free-form expression strings. The compiler parses
//! those into this typed tree so the Lua runtime can evaluate deterministically with no string
//! parsing at execution time. `Not`/`All`/`Any` realize the AND/OR/NOT/Parens grammar.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum RuntimeCondition {
    AlwaysTrue,
    QuestAccepted(u32),
    QuestCompleted(u32),
    QuestRewarded(u32),
    ObjectiveComplete(u32, u8),
    LevelAtLeast(u8),
    LevelBelow(u8),
    HasItem(u32),
    ItemCountAtLeast(u32, u32),
    GoldAtLeast(u64),
    ProfessionSkillAtLeast(String, u32),
    ItemCooldownReady(u32),
    ReputationAtLeast(String, i32),
    RaceIs(String),
    ClassIs(String),
    FactionIs(String),
    Not(Box<RuntimeCondition>),
    All(Vec<RuntimeCondition>),
    Any(Vec<RuntimeCondition>),
}