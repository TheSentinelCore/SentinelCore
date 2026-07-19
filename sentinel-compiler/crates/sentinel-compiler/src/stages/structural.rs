use std::collections::{HashMap, HashSet};

use sentinel_schema::{Profile, ActionPayload};
use sentinel_schema::reference::NpcReference;
use uuid::Uuid;

use crate::diagnostics::{Diagnostic, Severity, Stage};

const EXPECTED_VERSION: &str = "1.0.0";

/// Validate the structural integrity of a Profile.
///
/// Returns `Ok(diagnostics)` if the profile passes all structural checks
/// (warnings may be present but do not cause failure), or `Err(diagnostics)`
/// if any hard errors are found. Both variants contain the full diagnostics
/// list so callers can inspect warnings even on failure.
pub fn validate(profile: &Profile) -> Result<Vec<Diagnostic>, Vec<Diagnostic>> {
    let mut diagnostics = Vec::new();

    // C-1008 — Schema version mismatch (warning)
    check_schema_version(profile, &mut diagnostics);

    // C-1001 — Duplicate Operation IDs
    check_duplicate_operation_ids(profile, &mut diagnostics);

    // C-1002 — Duplicate Action IDs within an Operation
    check_duplicate_action_ids(profile, &mut diagnostics);

    // C-1003 — Dangling Branch target references
    check_dangling_branch_targets(profile, &mut diagnostics);

    // C-1004 — Dangling NPC references
    check_dangling_npc_references(profile, &mut diagnostics);

    // C-1005 — Dangling Quest references
    check_dangling_quest_references(profile, &mut diagnostics);

    // C-1006 — TurnIn with no matching Pickup
    check_turnin_without_pickup(profile, &mut diagnostics);

    // C-1007 — Polygon with fewer than 3 vertices
    check_polygon_vertices(profile, &mut diagnostics);

    if diagnostics.iter().any(|d| d.severity == Severity::Error) {
        Err(diagnostics)
    } else {
        Ok(diagnostics)
    }
}

// ---------------------------------------------------------------------------
// C-1008 — Schema version mismatch
// ---------------------------------------------------------------------------

fn check_schema_version(profile: &Profile, diagnostics: &mut Vec<Diagnostic>) {
    if profile.schema_version != EXPECTED_VERSION {
        diagnostics.push(
            Diagnostic::warning(
                "C-1008",
                Stage::StructuralValidation,
                format!(
                    "Schema version mismatch: expected '{}', got '{}'",
                    EXPECTED_VERSION, profile.schema_version
                ),
            )
            .with_fix("Update the Profile schema_version to match the compiler's expected version"),
        );
    }
}

// ---------------------------------------------------------------------------
// C-1001 — Duplicate Operation IDs
// ---------------------------------------------------------------------------

fn check_duplicate_operation_ids(profile: &Profile, diagnostics: &mut Vec<Diagnostic>) {
    let mut seen: HashMap<Uuid, &str> = HashMap::new();
    for op in &profile.operations {
        if let Some(prev_name) = seen.get(&op.id) {
            diagnostics.push(
                Diagnostic::error(
                    "C-1001",
                    Stage::StructuralValidation,
                    format!("Duplicate Operation ID: {}", op.id),
                )
                .with_entity(format!("Operation '{}' and '{}'", prev_name, op.name)),
            );
        }
        seen.insert(op.id, &op.name);
    }
}

// ---------------------------------------------------------------------------
// C-1002 — Duplicate Action IDs within an Operation
// ---------------------------------------------------------------------------

fn check_duplicate_action_ids(profile: &Profile, diagnostics: &mut Vec<Diagnostic>) {
    for op in &profile.operations {
        let mut seen: HashMap<Uuid, &str> = HashMap::new();
        for action in &op.actions {
            if let Some(prev_name) = seen.get(&action.id) {
                diagnostics.push(
                    Diagnostic::error(
                        "C-1002",
                        Stage::StructuralValidation,
                        format!(
                            "Duplicate Action ID in Operation '{}': {}",
                            op.name, action.id
                        ),
                    )
                    .with_entity(format!("Action '{}' and '{}'", prev_name, action.name)),
                );
            }
            seen.insert(action.id, &action.name);
        }
    }
}

// ---------------------------------------------------------------------------
// C-1003 — Dangling Branch target references
// ---------------------------------------------------------------------------

fn check_dangling_branch_targets(profile: &Profile, diagnostics: &mut Vec<Diagnostic>) {
    for op in &profile.operations {
        let action_ids: HashSet<Uuid> = op.actions.iter().map(|a| a.id).collect();
        for action in &op.actions {
            if let ActionPayload::Branch(ref branch) = action.payload {
                for target_id in &branch.true_actions {
                    if !action_ids.contains(target_id) {
                        diagnostics.push(
                            Diagnostic::error(
                                "C-1003",
                                Stage::StructuralValidation,
                                format!(
                                    "Branch action '{}' references nonexistent Action ID: {}",
                                    action.name, target_id
                                ),
                            )
                            .with_entity(format!(
                                "Operation '{}' / Action '{}'",
                                op.name, action.name
                            )),
                        );
                    }
                }
                for target_id in &branch.false_actions {
                    if !action_ids.contains(target_id) {
                        diagnostics.push(
                            Diagnostic::error(
                                "C-1003",
                                Stage::StructuralValidation,
                                format!(
                                    "Branch action '{}' references nonexistent Action ID: {}",
                                    action.name, target_id
                                ),
                            )
                            .with_entity(format!(
                                "Operation '{}' / Action '{}'",
                                op.name, action.name
                            )),
                        );
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// C-1004 — Dangling NPC references
// ---------------------------------------------------------------------------

fn check_dangling_npc_references(profile: &Profile, diagnostics: &mut Vec<Diagnostic>) {
    let npc_entries: HashSet<u32> = profile.npc_library.iter().map(|n| n.entry).collect();

    for op in &profile.operations {
        for action in &op.actions {
            let npc_refs = extract_npc_references(&action.payload);
            for npc in npc_refs {
                if !npc_entries.contains(&npc.entry) {
                    diagnostics.push(
                        Diagnostic::error(
                            "C-1004",
                            Stage::StructuralValidation,
                            format!(
                                "NPC entry {} ('{}') not found in Profile NPC library",
                                npc.entry, npc.name
                            ),
                        )
                        .with_entity(format!(
                            "Operation '{}' / Action '{}'",
                            op.name, action.name
                        )),
                    );
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// C-1005 — Dangling Quest references
// ---------------------------------------------------------------------------

fn check_dangling_quest_references(profile: &Profile, diagnostics: &mut Vec<Diagnostic>) {
    let quest_ids: HashSet<u32> = profile.quest_library.iter().map(|q| q.id).collect();

    for op in &profile.operations {
        for action in &op.actions {
            let quest_refs = extract_quest_references(&action.payload);
            for quest_id in quest_refs {
                if !quest_ids.contains(&quest_id) {
                    diagnostics.push(
                        Diagnostic::error(
                            "C-1005",
                            Stage::StructuralValidation,
                            format!(
                                "Quest ID {} not found in Profile Quest library",
                                quest_id
                            ),
                        )
                        .with_entity(format!(
                            "Operation '{}' / Action '{}'",
                            op.name, action.name
                        )),
                    );
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// C-1006 — TurnIn with no matching Pickup
// ---------------------------------------------------------------------------

fn check_turnin_without_pickup(profile: &Profile, diagnostics: &mut Vec<Diagnostic>) {
    let pickup_quest_ids: HashSet<u32> = profile
        .operations
        .iter()
        .flat_map(|op| op.actions.iter())
        .filter_map(|a| match &a.payload {
            ActionPayload::PickupQuest(p) => Some(p.quest.id),
            _ => None,
        })
        .collect();

    for op in &profile.operations {
        for action in &op.actions {
            if let ActionPayload::TurnInQuest(t) = &action.payload {
                if !pickup_quest_ids.contains(&t.quest.id) {
                    diagnostics.push(
                        Diagnostic::warning(
                            "C-1006",
                            Stage::StructuralValidation,
                            format!(
                                "TurnInQuest for quest {} ('{}') has no matching PickupQuest in any reachable Operation",
                                t.quest.id, t.quest.title
                            ),
                        )
                        .with_entity(format!(
                            "Operation '{}' / Action '{}'",
                            op.name, action.name
                        ))
                        .with_fix(
                            "Add a PickupQuest action for this quest, or remove the TurnIn if the quest is picked up elsewhere",
                        ),
                    );
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// C-1007 — Polygon with fewer than 3 vertices
// ---------------------------------------------------------------------------

fn check_polygon_vertices(profile: &Profile, diagnostics: &mut Vec<Diagnostic>) {
    for op in &profile.operations {
        for action in &op.actions {
            if let ActionPayload::GrindArea(g) = &action.payload {
                if g.polygon.vertices.len() < 3 {
                    diagnostics.push(
                        Diagnostic::error(
                            "C-1007",
                            Stage::StructuralValidation,
                            format!(
                                "Polygon in GrindArea has only {} vertices (minimum 3)",
                                g.polygon.vertices.len()
                            ),
                        )
                        .with_entity(format!(
                            "Operation '{}' / Action '{}'",
                            op.name, action.name
                        )),
                    );
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers — extract references from ActionPayload variants
// ---------------------------------------------------------------------------

fn extract_npc_references(payload: &ActionPayload) -> Vec<&NpcReference> {
    match payload {
        ActionPayload::PickupQuest(a) => vec![&a.npc],
        ActionPayload::TurnInQuest(a) => vec![&a.npc],
        ActionPayload::Escort(a) => vec![&a.npc],
        ActionPayload::TalkToNpc(a) => vec![&a.npc],
        ActionPayload::Train(a) => vec![&a.trainer],
        ActionPayload::Mailbox(a) => vec![&a.mailbox],
        ActionPayload::Bank(a) => vec![&a.banker],
        ActionPayload::DeathSkip(a) => vec![&a.spirit_healer],
        ActionPayload::UseItem(a) => a.target.iter().collect(),
        ActionPayload::Vendor(a) => vec![&a.vendor.npc],
        ActionPayload::Repair(a) => vec![&a.vendor.npc],
        _ => vec![],
    }
}

fn extract_quest_references(payload: &ActionPayload) -> Vec<u32> {
    match payload {
        ActionPayload::PickupQuest(a) => vec![a.quest.id],
        ActionPayload::TurnInQuest(a) => vec![a.quest.id],
        _ => vec![],
    }
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::Operation;
    use sentinel_schema::action::*;
    use sentinel_schema::geometry::*;
    use sentinel_schema::reference::*;

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

    fn test_quest() -> QuestReference {
        QuestReference::new(1, "Wolf Kill", 197, 197)
    }

    // -- Empty profile passes ------------------------------------------------

    #[test]
    fn test_empty_profile_passes() {
        let profile = valid_profile();
        assert!(validate(&profile).is_ok());
    }

    // -- C-1001: Duplicate Operation IDs -------------------------------------

    #[test]
    fn test_duplicate_operation_ids() {
        let id = Uuid::new_v4();
        let mut op1 = Operation::new("Op1");
        op1.id = id;
        let mut op2 = Operation::new("Op2");
        op2.id = id;

        let mut profile = valid_profile();
        profile.operations = vec![op1, op2];

        let result = validate(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-1001"));
    }

    #[test]
    fn test_unique_operation_ids_pass() {
        let mut profile = valid_profile();
        profile.operations = vec![Operation::new("A"), Operation::new("B")];
        assert!(validate(&profile).is_ok());
    }

    // -- C-1002: Duplicate Action IDs within an Operation --------------------

    #[test]
    fn test_duplicate_action_ids_in_operation() {
        let id = Uuid::new_v4();
        let a1 = Action::new(
            "Wait1",
            ActionPayload::Wait(WaitAction { duration_ms: 1000 }),
        )
        .with_id(id);
        let a2 = Action::new(
            "Wait2",
            ActionPayload::Wait(WaitAction { duration_ms: 2000 }),
        )
        .with_id(id);

        let mut op = Operation::new("Op");
        op.actions = vec![a1, a2];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate(&profile);
        assert!(result.is_err());
        assert!(result.unwrap_err().iter().any(|d| d.code == "C-1002"));
    }

    #[test]
    fn test_unique_action_ids_pass() {
        let mut op = Operation::new("Op");
        op.actions = vec![
            Action::new(
                "Wait1",
                ActionPayload::Wait(WaitAction { duration_ms: 1000 }),
            ),
            Action::new(
                "Wait2",
                ActionPayload::Wait(WaitAction { duration_ms: 2000 }),
            ),
        ];
        let mut profile = valid_profile();
        profile.operations = vec![op];
        assert!(validate(&profile).is_ok());
    }

    // -- C-1003: Dangling Branch target --------------------------------------

    #[test]
    fn test_dangling_branch_target() {
        let non_existent = Uuid::new_v4();

        let mut op = Operation::new("Op");
        let branch_action = Action::new(
            "Branch",
            ActionPayload::Branch(BranchAction {
                expression: sentinel_schema::Condition::VariableTrue("flag".to_string()),
                true_actions: vec![non_existent],
                false_actions: vec![],
            }),
        );
        op.actions = vec![branch_action];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate(&profile);
        assert!(result.is_err());
        assert!(result.unwrap_err().iter().any(|d| d.code == "C-1003"));
    }

    #[test]
    fn test_branch_with_valid_targets_pass() {
        let target = Action::new(
            "Target",
            ActionPayload::Wait(WaitAction { duration_ms: 500 }),
        );
        let target_id = target.id;

        let branch_action = Action::new(
            "Branch",
            ActionPayload::Branch(BranchAction {
                expression: sentinel_schema::Condition::VariableTrue("flag".to_string()),
                true_actions: vec![target_id],
                false_actions: vec![],
            }),
        );

        let mut op = Operation::new("Op");
        op.actions = vec![branch_action, target];

        let mut profile = valid_profile();
        profile.operations = vec![op];
        assert!(validate(&profile).is_ok());
    }

    // -- C-1004: Dangling NPC reference --------------------------------------

    #[test]
    fn test_dangling_npc_reference() {
        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "Talk",
            ActionPayload::TalkToNpc(TalkToNpcAction {
                npc: NpcReference::new(
                    999,
                    "Unknown NPC",
                    "Zone",
                    Waypoint::new(0, "Zone", 0.0, 0.0, 0.0, 5.0),
                ),
                gossip_option: None,
            }),
        )];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate(&profile);
        assert!(result.is_err());
        assert!(result.unwrap_err().iter().any(|d| d.code == "C-1004"));
    }

    #[test]
    fn test_npc_reference_in_library_passes() {
        let npc = test_npc();
        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "Talk",
            ActionPayload::TalkToNpc(TalkToNpcAction {
                npc: npc.clone(),
                gossip_option: None,
            }),
        )];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.operations = vec![op];
        assert!(validate(&profile).is_ok());
    }

    // -- C-1005: Dangling Quest reference ------------------------------------

    #[test]
    fn test_dangling_quest_reference() {
        let npc = test_npc();
        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "TurnIn",
            ActionPayload::TurnInQuest(TurnInQuestAction {
                quest: QuestReference::new(999, "Nonexistent Quest", 197, 197),
                npc: npc.clone(),
            }),
        )];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.operations = vec![op];

        let result = validate(&profile);
        assert!(result.is_err());
        assert!(result.unwrap_err().iter().any(|d| d.code == "C-1005"));
    }

    #[test]
    fn test_quest_reference_in_library_passes() {
        let npc = test_npc();
        let quest = test_quest();
        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "TurnIn",
            ActionPayload::TurnInQuest(TurnInQuestAction {
                quest: quest.clone(),
                npc: npc.clone(),
            }),
        )];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.quest_library = vec![quest];
        profile.operations = vec![op];
        assert!(validate(&profile).is_ok());
    }

    // -- C-1006: TurnIn without matching Pickup (warning) --------------------

    #[test]
    fn test_turnin_without_pickup_is_warning() {
        let npc = test_npc();
        let quest = test_quest();

        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "TurnIn",
            ActionPayload::TurnInQuest(TurnInQuestAction {
                quest: quest.clone(),
                npc: npc.clone(),
            }),
        )];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.quest_library = vec![quest];
        profile.operations = vec![op];

        let result = validate(&profile);
        // Should succeed (warning only, not error)
        let diags = result.expect("expected Ok with warnings");
        assert!(diags.iter().any(|d| d.code == "C-1006"));
    }

    #[test]
    fn test_turnin_with_matching_pickup_passes() {
        let npc = test_npc();
        let quest = test_quest();

        let mut op = Operation::new("Op");
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
        assert!(validate(&profile).is_ok());
    }

    #[test]
    fn test_pickup_in_different_operation_satisfies_turnin() {
        let npc = test_npc();
        let quest = test_quest();

        let mut op1 = Operation::new("Op1");
        op1.actions = vec![Action::new(
            "Pickup",
            ActionPayload::PickupQuest(PickupQuestAction {
                quest: quest.clone(),
                npc: npc.clone(),
                auto_complete_previous: false,
            }),
        )];

        let mut op2 = Operation::new("Op2");
        op2.actions = vec![Action::new(
            "TurnIn",
            ActionPayload::TurnInQuest(TurnInQuestAction {
                quest: quest.clone(),
                npc: npc.clone(),
            }),
        )];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.quest_library = vec![quest];
        profile.operations = vec![op1, op2];
        // Should pass — pickup is in the profile (cross-operation)
        assert!(validate(&profile).is_ok());
    }

    // -- C-1007: Polygon too few vertices ------------------------------------

    #[test]
    fn test_polygon_too_few_vertices() {
        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "Grind",
            ActionPayload::GrindArea(GrindAreaAction {
                polygon: Polygon::new(vec![
                    Waypoint::new(0, "Zone", 0.0, 0.0, 0.0, 5.0),
                    Waypoint::new(0, "Zone", 1.0, 0.0, 0.0, 5.0),
                ]),
                targets: vec![CreatureReference::new(101, "Wolf")],
                stop_condition: StopCondition::KillCount(101, 10),
                loot: vec![],
            }),
        )];

        let mut profile = valid_profile();
        profile.operations = vec![op];

        let result = validate(&profile);
        assert!(result.is_err());
        assert!(result.unwrap_err().iter().any(|d| d.code == "C-1007"));
    }

    #[test]
    fn test_polygon_with_three_vertices_passes() {
        let npc = test_npc();
        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "Grind",
            ActionPayload::GrindArea(GrindAreaAction {
                polygon: Polygon::new(vec![
                    Waypoint::new(0, "Zone", 0.0, 0.0, 0.0, 5.0),
                    Waypoint::new(0, "Zone", 1.0, 0.0, 0.0, 5.0),
                    Waypoint::new(0, "Zone", 0.5, 1.0, 0.0, 5.0),
                ]),
                targets: vec![CreatureReference::new(101, "Wolf")],
                stop_condition: StopCondition::KillCount(101, 10),
                loot: vec![],
            }),
        )];

        let mut profile = valid_profile();
        profile.npc_library = vec![npc];
        profile.operations = vec![op];
        assert!(validate(&profile).is_ok());
    }

    // -- C-1008: Schema version mismatch -------------------------------------

    #[test]
    fn test_schema_version_mismatch_is_warning() {
        let mut profile = valid_profile();
        profile.schema_version = "0.9.0".to_string();

        let result = validate(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(diags.iter().any(|d| d.code == "C-1008"));
    }

    #[test]
    fn test_schema_version_correct_no_warning() {
        let profile = valid_profile();
        // Profile::new sets schema_version to "1.0.0"
        assert_eq!(profile.schema_version, "1.0.0");
        let result = validate(&profile);
        assert!(result.is_ok());
        let diags = result.unwrap();
        assert!(!diags.iter().any(|d| d.code == "C-1008"));
    }

    // -- Multiple errors at once ---------------------------------------------

    #[test]
    fn test_multiple_errors_collected() {
        let id = Uuid::new_v4();
        let mut op1 = Operation::new("Op1");
        op1.id = id;
        let mut op2 = Operation::new("Op2");
        op2.id = id;

        // Give op1 a polygon with too few vertices
        op1.actions = vec![Action::new(
            "Grind",
            ActionPayload::GrindArea(GrindAreaAction {
                polygon: Polygon::new(vec![
                    Waypoint::new(0, "Zone", 0.0, 0.0, 0.0, 5.0),
                ]),
                targets: vec![],
                stop_condition: StopCondition::Manual,
                loot: vec![],
            }),
        )];

        let mut profile = valid_profile();
        profile.operations = vec![op1, op2];

        let result = validate(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        // Should have at least C-1001 and C-1007
        assert!(diags.iter().any(|d| d.code == "C-1001"));
        assert!(diags.iter().any(|d| d.code == "C-1007"));
    }

    // -- Actions without NPC/Quest refs don't trigger C-1004/C-1005 ----------

    #[test]
    fn test_wait_actions_no_reference_errors() {
        let mut op = Operation::new("Op");
        op.actions = vec![Action::new(
            "Wait",
            ActionPayload::Wait(WaitAction { duration_ms: 5000 }),
        )];

        let mut profile = valid_profile();
        profile.operations = vec![op];
        let result = validate(&profile);
        assert!(result.is_ok());
    }
}
