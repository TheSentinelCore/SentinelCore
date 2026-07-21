//! Runtime (execution) model — ADR `05_RUNTIME_AND_EXECUTION_MODEL`.
//!
//! This is the deterministic, fully-resolved artifact the compiler emits and the Lua executor
//! consumes. Invariants from ADR-500 Part 2 apply: every ID already resolved, no references, no
//! compiler/editor metadata, no comments, no diagnostics — pure execution.

mod action;
mod area;
mod condition;
mod npc;
mod operation;
mod profile;
mod quest;
mod variable;
mod waypoint;

pub use action::{
    RuntimeAcceptQuest, RuntimeAction, RuntimeBank, RuntimeComment, RuntimeConditionAction,
    RuntimeEscort, RuntimeFlight, RuntimeGrind, RuntimeHearth, RuntimeInteractNpc, RuntimeKill,
    RuntimeLearnFlightPath, RuntimeLoot, RuntimeMailbox, RuntimePatrol, RuntimeRepair,
    RuntimeSetVariable, RuntimeTrain, RuntimeTravel, RuntimeTurnInQuest, RuntimeUseItem,
    RuntimeVendor, RuntimeWait,
};
pub use area::RuntimeArea;
pub use condition::RuntimeCondition;
pub use npc::RuntimeNpc;
pub use operation::RuntimeOperation;
pub use profile::RuntimeProfile;
pub use quest::RuntimeQuest;
pub use variable::RuntimeVariable;
pub use waypoint::RuntimeWaypoint;
