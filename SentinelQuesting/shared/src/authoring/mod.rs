//! Authoring (Project) data model — ADR `02_DATA_MODEL`.
//!
//! This is the single editable representation. The importer emits it, the editor mutates it,
//! the validator checks it, and the compiler lowers it to the runtime model. Nothing here is
//! ever executed; it describes *intent*, not *how* (ADR-204).

mod action;
mod area;
mod enums;
mod guide;
mod npc;
mod object;
mod operation;
mod position;
mod project;
mod quest;
mod variable;

pub use action::{
    AcceptQuestAction, Action, ActionPayload, BankAction, CommentAction, ConditionAction,
    ConditionRole, EscortAction, FlightAction, GrindAreaAction, HearthAction, InteractNpcAction,
    KillTargetAction, LearnFlightPathAction, LootObjectAction, MailboxAction, PatrolAction,
    RepairAction, SetHearthAction, SetVariableAction, TrainerAction, TravelAction,
    TurnInQuestAction, UseItemAction, VendorAction, WaitAction,
};
pub use area::Area;
pub use enums::{
    Class, CoordinateMode, Faction, NpcRole, Race, Severity, VariableType, VariableValue,
};
pub use guide::{CompleteWithTarget, Gated, GuideDirective, GuideGate, SourceLineNo};
pub use npc::{NPCReference, NpcRoleSet};
pub use object::GameObjectReference;
pub use operation::Operation;
pub use position::Position;
pub use project::{
    new_project, AreaIndex, Diagnostic, ImportMetadata, OperationIndex, Project, ProjectDirIndex,
    ProjectMetadata, ProjectSettings,
};
pub use quest::QuestReference;
pub use variable::Variable;
