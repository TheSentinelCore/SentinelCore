//! Stage 5: Goal Coverage Validation
//!
//! Validates that declared OperationGoals are covered by appropriate actions
//! within the Operation or its sub_operations.
//!
//! See: docs/adr/008-compilation-pipeline.md §8

use sentinel_schema::enums::GoalType;
use sentinel_schema::{ActionPayload, Profile};
use uuid::Uuid;

use crate::diagnostics::{Diagnostic, Severity, Stage};

/// Stage 5: Validate that declared goals are covered by actions.
///
/// Returns `Ok(diagnostics)` (possibly with warnings) on success, or
/// `Err(diagnostics)` if any hard errors are found.
pub fn validate_goals(profile: &Profile) -> Result<Vec<Diagnostic>, Vec<Diagnostic>> {
    let mut diagnostics: Vec<Diagnostic> = Vec::new();

    // Build an operation lookup for sub_operation resolution.
    let op_map: std::collections::HashMap<Uuid, &sentinel_schema::Operation> = profile
        .operations
        .iter()
        .map(|op| (op.id, op))
        .collect();

    for op in &profile.operations {
        for goal in &op.goals {
            match &goal.goal_type {
                GoalType::CompleteQuest(quest_id) => {
                    let covered =
                        check_quest_covered(profile, op, &op_map, *quest_id);
                    if !covered && goal.required {
                        diagnostics.push(
                            Diagnostic::error(
                                "C-5001",
                                Stage::GoalCoverage,
                                format!(
                                    "Required goal '{}' — quest {} not covered by any action",
                                    goal.description, quest_id
                                ),
                            )
                            .with_entity(format!("Operation '{}'", op.name)),
                        );
                    } else if !covered && !goal.required {
                        diagnostics.push(
                            Diagnostic::warning(
                                "C-5001",
                                Stage::GoalCoverage,
                                format!(
                                    "Optional goal '{}' — quest {} not covered by any action",
                                    goal.description, quest_id
                                ),
                            )
                            .with_entity(format!("Operation '{}'", op.name)),
                        );
                    }
                }
                GoalType::CompleteQuestChain(ids) => {
                    for quest_id in ids {
                        let covered =
                            check_quest_covered(profile, op, &op_map, *quest_id);
                        if !covered && goal.required {
                            diagnostics.push(
                                Diagnostic::error(
                                    "C-5002",
                                    Stage::GoalCoverage,
                                    format!(
                                        "Required goal '{}' — quest {} in chain not covered",
                                        goal.description, quest_id
                                    ),
                                )
                                .with_entity(format!("Operation '{}'", op.name)),
                            );
                        } else if !covered && !goal.required {
                            diagnostics.push(
                                Diagnostic::warning(
                                    "C-5002",
                                    Stage::GoalCoverage,
                                    format!(
                                        "Optional goal '{}' — quest {} in chain not covered",
                                        goal.description, quest_id
                                    ),
                                )
                                .with_entity(format!("Operation '{}'", op.name)),
                            );
                        }
                    }
                }
                GoalType::UnlockFlightPath(node_id) => {
                    let covered =
                        check_flight_covered(profile, op, &op_map, *node_id);
                    if !covered && goal.required {
                        diagnostics.push(
                            Diagnostic::error(
                                "C-5003",
                                Stage::GoalCoverage,
                                format!(
                                    "Required goal '{}' — flight path {} not unlocked by any action",
                                    goal.description, node_id
                                ),
                            )
                            .with_entity(format!("Operation '{}'", op.name)),
                        );
                    } else if !covered && !goal.required {
                        diagnostics.push(
                            Diagnostic::warning(
                                "C-5004",
                                Stage::GoalCoverage,
                                format!(
                                    "Optional goal '{}' — flight path {} not unlocked by any action",
                                    goal.description, node_id
                                ),
                            )
                            .with_entity(format!("Operation '{}'", op.name)),
                        );
                    }
                }
                GoalType::ReachLevel(_)
                | GoalType::GainXp(_)
                | GoalType::ReachZone(_)
                | GoalType::ReachWaypoint(_)
                | GoalType::AcquireItem(_, _)
                | GoalType::KillCount(_, _)
                | GoalType::LearnSpell(_)
                | GoalType::Custom(_) => {
                    // Informational — cannot be statically verified.
                }
            }
        }
    }

    if diagnostics
        .iter()
        .any(|d| d.severity == Severity::Error)
    {
        Err(diagnostics)
    } else {
        Ok(diagnostics)
    }
}

// =========================================================================
// Goal coverage helpers
// =========================================================================

/// Collect all action payloads from an operation, including those in
/// sub_operations (resolved transitively).
fn collect_all_actions<'a>(
    profile: &'a Profile,
    op: &'a sentinel_schema::Operation,
    op_map: &std::collections::HashMap<Uuid, &'a sentinel_schema::Operation>,
) -> Vec<&'a ActionPayload> {
    let mut actions: Vec<&ActionPayload> = Vec::new();

    // Direct actions.
    for action in &op.actions {
        actions.push(&action.payload);
    }

    // Sub-operation actions (one level deep — sub_operations reference other Operations).
    let mut visited = std::collections::HashSet::new();
    collect_sub_op_actions(profile, op, op_map, &mut actions, &mut visited);

    actions
}

/// Recursively collect actions from sub_operations.
fn collect_sub_op_actions<'a>(
    profile: &'a Profile,
    op: &'a sentinel_schema::Operation,
    op_map: &std::collections::HashMap<Uuid, &'a sentinel_schema::Operation>,
    actions: &mut Vec<&'a ActionPayload>,
    visited: &mut std::collections::HashSet<Uuid>,
) {
    if !visited.insert(op.id) {
        return; // prevent infinite recursion
    }

    for sub_id in &op.sub_operations {
        if let Some(sub_op) = op_map.get(sub_id) {
            for action in &sub_op.actions {
                actions.push(&action.payload);
            }
            // Go one more level.
            collect_sub_op_actions(profile, sub_op, op_map, actions, visited);
        }
    }
}

/// Check if a quest (by ID) has both PickupQuest and TurnInQuest actions
/// in the operation or its sub_operations.
fn check_quest_covered(
    profile: &Profile,
    op: &sentinel_schema::Operation,
    op_map: &std::collections::HashMap<Uuid, &sentinel_schema::Operation>,
    quest_id: u32,
) -> bool {
    let actions = collect_all_actions(profile, op, op_map);
    let has_pickup = actions.iter().any(|p| matches!(p, ActionPayload::PickupQuest(a) if a.quest.id == quest_id));
    let has_turnin = actions.iter().any(|p| matches!(p, ActionPayload::TurnInQuest(a) if a.quest.id == quest_id));
    has_pickup && has_turnin
}

/// Check if a flight path (by node ID) has a FlightPath action or a
/// TalkToNpc action that could serve as a flight master interaction.
fn check_flight_covered(
    profile: &Profile,
    op: &sentinel_schema::Operation,
    op_map: &std::collections::HashMap<Uuid, &sentinel_schema::Operation>,
    node_id: u32,
) -> bool {
    let actions = collect_all_actions(profile, op, op_map);
    // Check for FlightPath action where either from or to has the matching node ID.
    let has_flight = actions.iter().any(|p| {
        matches!(p, ActionPayload::FlightPath(f)
            if f.from.id == node_id || f.to.id == node_id)
    });
    if has_flight {
        return true;
    }

    // Check for TalkToNpc where the NPC has the FlightMaster role.
    let has_flight_master_talk = actions.iter().any(|p| {
        matches!(p, ActionPayload::TalkToNpc(a)
            if a.npc.has_role(sentinel_schema::enums::NpcRole::FlightMaster))
    });
    has_flight_master_talk
}

// =========================================================================
// Tests
// =========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::action::*;
    use sentinel_schema::condition::OperationGoal;
    use sentinel_schema::enums::{GoalType, NpcRole};
    use sentinel_schema::geometry::Waypoint;
    use sentinel_schema::reference::*;
    use sentinel_schema::Operation;
    use sentinel_schema::Profile;

    fn valid_profile() -> Profile {
        Profile::new("Test", "Agent")
    }

    fn test_npc() -> NpcReference {
        NpcReference::new(
            197,
            "Marshal McBride",
            "Northshire",
            Waypoint::new(0, "Northshire", 0.0, 0.0, 0.0, 5.0),
        )
    }

    fn flight_master_npc() -> NpcReference {
        NpcReference::new(
            1,
            "Flight Master",
            "Northshire",
            Waypoint::new(0, "Northshire", 0.0, 0.0, 0.0, 5.0),
        )
        .with_roles(vec![NpcRole::FlightMaster])
    }

    fn test_quest() -> QuestReference {
        QuestReference::new(1, "Wolf Kill", 197, 197)
    }

    fn flight_action(from_id: u32, to_id: u32) -> ActionPayload {
        ActionPayload::FlightPath(FlightAction {
            from: FlightNode::new(from_id, "From"),
            to: FlightNode::new(to_id, "To"),
        })
    }

    // -- Quest goal covered ------------------------------------------------

    #[test]
    fn test_quest_goal_covered() {
        let npc = test_npc();
        let quest = test_quest();

        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::required(
            "Complete Wolf Kill",
            GoalType::CompleteQuest(1),
            1.0,
        )];
        op.actions = vec![
            Action::new(
                "Pickup",
                ActionPayload::PickupQuest(PickupQuestAction {
                    quest: quest.clone(),
                    npc: npc.clone(),
                    auto_complete_previous: false,
                }),
            ),
            Action::new(
                "TurnIn",
                ActionPayload::TurnInQuest(TurnInQuestAction {
                    quest: quest.clone(),
                    npc: npc.clone(),
                }),
            ),
        ];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.quest_library = vec![quest];
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(!diags.iter().any(|d| d.code == "C-5001"));
    }

    // -- Quest goal missing ------------------------------------------------

    #[test]
    fn test_quest_goal_missing() {
        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::required(
            "Complete Wolf Kill",
            GoalType::CompleteQuest(1),
            1.0,
        )];
        // No quest actions.

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-5001"));
    }

    // -- Optional quest goal warning ---------------------------------------

    #[test]
    fn test_optional_quest_goal_warning() {
        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::optional(
            "Complete Wolf Kill",
            GoalType::CompleteQuest(1),
            0.5,
        )];
        // No quest actions.

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(diags.iter().any(|d| d.code == "C-5001"));
        assert!(diags
            .iter()
            .any(|d| d.severity == Severity::Warning && d.code == "C-5001"));
    }

    // -- Quest chain covered -----------------------------------------------

    #[test]
    fn test_quest_chain_covered() {
        let npc = test_npc();
        let quest1 = QuestReference::new(1, "Wolf Kill", 197, 197);
        let quest2 = QuestReference::new(2, "Rabbit Kill", 197, 197);

        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::required(
            "Complete chain",
            GoalType::CompleteQuestChain(vec![1, 2]),
            1.0,
        )];
        op.actions = vec![
            Action::new(
                "Pickup1",
                ActionPayload::PickupQuest(PickupQuestAction {
                    quest: quest1.clone(),
                    npc: npc.clone(),
                    auto_complete_previous: false,
                }),
            ),
            Action::new(
                "TurnIn1",
                ActionPayload::TurnInQuest(TurnInQuestAction {
                    quest: quest1.clone(),
                    npc: npc.clone(),
                }),
            ),
            Action::new(
                "Pickup2",
                ActionPayload::PickupQuest(PickupQuestAction {
                    quest: quest2.clone(),
                    npc: npc.clone(),
                    auto_complete_previous: false,
                }),
            ),
            Action::new(
                "TurnIn2",
                ActionPayload::TurnInQuest(TurnInQuestAction {
                    quest: quest2.clone(),
                    npc: npc.clone(),
                }),
            ),
        ];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.quest_library = vec![quest1, quest2];
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(!diags.iter().any(|d| d.code == "C-5002"));
    }

    // -- Quest chain incomplete --------------------------------------------

    #[test]
    fn test_quest_chain_incomplete() {
        let npc = test_npc();
        let quest1 = QuestReference::new(1, "Wolf Kill", 197, 197);
        let quest2 = QuestReference::new(2, "Rabbit Kill", 197, 197);

        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::required(
            "Complete chain",
            GoalType::CompleteQuestChain(vec![1, 2]),
            1.0,
        )];
        // Only quest 1 is covered.
        op.actions = vec![
            Action::new(
                "Pickup1",
                ActionPayload::PickupQuest(PickupQuestAction {
                    quest: quest1.clone(),
                    npc: npc.clone(),
                    auto_complete_previous: false,
                }),
            ),
            Action::new(
                "TurnIn1",
                ActionPayload::TurnInQuest(TurnInQuestAction {
                    quest: quest1.clone(),
                    npc: npc.clone(),
                }),
            ),
        ];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.quest_library = vec![quest1, quest2];
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-5002"));
    }

    // -- Flight goal covered -----------------------------------------------

    #[test]
    fn test_flight_goal_covered() {
        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::required(
            "Unlock Stormwind flight",
            GoalType::UnlockFlightPath(100),
            1.0,
        )];
        op.actions = vec![Action::new("Fly", flight_action(50, 100))];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(!diags.iter().any(|d| d.code == "C-5003"));
    }

    // -- Flight goal missing -----------------------------------------------

    #[test]
    fn test_flight_goal_missing() {
        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::required(
            "Unlock Stormwind flight",
            GoalType::UnlockFlightPath(100),
            1.0,
        )];
        // No flight actions.

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-5003"));
    }

    // -- Informational goals pass ------------------------------------------

    #[test]
    fn test_informational_goals_pass() {
        use sentinel_schema::geometry::Waypoint;

        let mut op = Operation::new("Op");
        op.goals = vec![
            OperationGoal::required("Reach level 10", GoalType::ReachLevel(10), 1.0),
            OperationGoal::required("Gain XP", GoalType::GainXp(5000), 1.0),
            OperationGoal::required(
                "Reach zone",
                GoalType::ReachZone("Elwynn".to_string()),
                1.0,
            ),
            OperationGoal::required(
                "Reach waypoint",
                GoalType::ReachWaypoint(Waypoint::new(0, "Elwynn", 0.0, 0.0, 0.0, 5.0)),
                1.0,
            ),
        ];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(diags.is_empty());
    }

    // -- Sub-operations checked --------------------------------------------

    #[test]
    fn test_sub_operations_checked() {
        let npc = test_npc();
        let quest = test_quest();

        let id_sub = Uuid::new_v4();

        // Sub-operation has the quest actions.
        let mut sub_op = Operation::new("SubOp");
        sub_op.id = id_sub;
        sub_op.actions = vec![
            Action::new(
                "Pickup",
                ActionPayload::PickupQuest(PickupQuestAction {
                    quest: quest.clone(),
                    npc: npc.clone(),
                    auto_complete_previous: false,
                }),
            ),
            Action::new(
                "TurnIn",
                ActionPayload::TurnInQuest(TurnInQuestAction {
                    quest: quest.clone(),
                    npc: npc.clone(),
                }),
            ),
        ];

        // Parent operation has the goal but no direct quest actions.
        let mut parent_op = Operation::new("ParentOp");
        parent_op.goals = vec![OperationGoal::required(
            "Complete Wolf Kill",
            GoalType::CompleteQuest(1),
            1.0,
        )];
        parent_op.sub_operations = vec![id_sub];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.quest_library = vec![quest];
        profile.operations = vec![parent_op, sub_op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(!diags.iter().any(|d| d.code == "C-5001"));
    }

    // -- Flight via TalkToNpc with FlightMaster role ------------------------

    #[test]
    fn test_flight_goal_via_talk_to_flight_master() {
        let fm = flight_master_npc();

        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::required(
            "Unlock flight",
            GoalType::UnlockFlightPath(100),
            1.0,
        )];
        op.actions = vec![Action::new(
            "Talk to FM",
            ActionPayload::TalkToNpc(TalkToNpcAction {
                npc: fm.clone(),
                gossip_option: None,
            }),
        )];

        let mut profile = valid_profile();
        profile.npc_library = vec![fm];
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(!diags.iter().any(|d| d.code == "C-5003"));
    }

    // -- No goals → no diagnostics -----------------------------------------

    #[test]
    fn test_no_goals_no_diagnostics() {
        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "Wait",
            ActionPayload::Wait(WaitAction { duration_ms: 1000 }),
        )];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(diags.is_empty());
    }

    // -- Quest goal missing only pickup (no turnin) → not covered ----------

    #[test]
    fn test_quest_goal_only_pickup_not_covered() {
        let npc = test_npc();
        let quest = test_quest();

        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::required(
            "Complete Wolf Kill",
            GoalType::CompleteQuest(1),
            1.0,
        )];
        op.actions = vec![Action::new(
            "Pickup",
            ActionPayload::PickupQuest(PickupQuestAction {
                quest: quest.clone(),
                npc: npc.clone(),
                auto_complete_previous: false,
            }),
        )];
        // No TurnInQuest action.

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.quest_library = vec![quest];
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-5001"));
    }

    // -- Quest chain: optional incomplete → warning -------------------------

    #[test]
    fn test_quest_chain_optional_incomplete_warning() {
        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::optional(
            "Complete chain",
            GoalType::CompleteQuestChain(vec![1, 2]),
            0.5,
        )];
        // No quest actions at all.

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(diags
            .iter()
            .filter(|d| d.code == "C-5002")
            .count()
            >= 1);
        assert!(diags
            .iter()
            .any(|d| d.severity == Severity::Warning && d.code == "C-5002"));
    }

    // -- Optional flight goal missing → warning C-5004 ---------------------

    #[test]
    fn test_optional_flight_goal_warning() {
        let mut op = Operation::new("Op");
        op.goals = vec![OperationGoal::optional(
            "Unlock Stormwind flight",
            GoalType::UnlockFlightPath(100),
            0.5,
        )];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(diags
            .iter()
            .any(|d| d.severity == Severity::Warning && d.code == "C-5004"));
    }

    // -- Custom / LearnSpell / KillCount / AcquireItem pass silently -------

    #[test]
    fn test_other_goal_types_pass() {
        let mut op = Operation::new("Op");
        op.goals = vec![
            OperationGoal::required("Custom goal", GoalType::Custom("test".to_string()), 1.0),
            OperationGoal::required("Learn spell", GoalType::LearnSpell(123), 1.0),
            OperationGoal::required("Kill count", GoalType::KillCount(101, 5), 1.0),
            OperationGoal::required("Acquire item", GoalType::AcquireItem(500, 3), 1.0),
        ];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate_goals(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(diags.is_empty());
    }
}
