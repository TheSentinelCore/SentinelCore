//! Stage 3: Blueprint Expansion
//!
//! Expands every `BlueprintReference` in `Profile.blueprints` into a set of
//! primitive `Action`s, packaged into a generated `Operation` (tagged with
//! `generated_from` for provenance, Volume 6 §25). Expansion runs in
//! deterministic timeline order: references are processed in the order they
//! appear in `profile.blueprints`.
//!
//! See: docs/adr/008-compiler.md §6, docs/adr/006-blueprints.md

use std::collections::HashMap;

use sentinel_schema::action::{
    Action, ActionPayload, GrindAreaAction, TalkToNpcAction, TrainAction, VendorAction,
};
use sentinel_schema::blueprint::{Blueprint, ParameterValue};
use sentinel_schema::{Operation, ParameterType, VendorEntry};

use crate::diagnostics::{Diagnostic, Severity, Stage};
use crate::query_client::QueryClient;
use crate::stages::resolution::ResolvedProfile;

/// Maximum recursion depth for nested blueprint expansion.
#[allow(dead_code)]
const MAX_RECURSION_DEPTH: usize = 4;

/// Result after blueprint expansion.
///
/// `profile` has been mutated in place: each `BlueprintReference` in
/// `profile.blueprints` now has a corresponding generated `Operation` appended
/// to `profile.operations`, tagged with `generated_from`.
#[derive(Debug, Clone)]
pub struct ExpandedProfile {
    pub profile: sentinel_schema::Profile,
    /// reference_id → generated primitive action names (for diagnostics/tests)
    pub expansion_map: HashMap<String, Vec<String>>,
    /// reference_id → generated Operation id (for diagnostics/tests)
    pub generated_operations: HashMap<String, uuid::Uuid>,
}

/// Stage 3 entry point.
///
/// Error codes:
/// - C-3001 — Blueprint not found in library
/// - C-3002 — Required parameter missing
/// - C-3003 — Recursive blueprint depth exceeded
/// - C-3004 — Parameter type mismatch
pub fn expand_blueprints(
    resolved: &ResolvedProfile,
    _query_client: &dyn QueryClient,
) -> Result<ExpandedProfile, Vec<Diagnostic>> {
    let mut diagnostics = Vec::new();
    let mut expansion_map: HashMap<String, Vec<String>> = HashMap::new();
    let mut generated_operations: HashMap<String, uuid::Uuid> = HashMap::new();

    // Build a map of blueprints by name for lookup
    let blueprint_map: HashMap<String, &Blueprint> = resolved
        .profile
        .blueprint_library
        .iter()
        .map(|bp| (bp.name.clone(), bp))
        .collect();

    let mut profile = resolved.profile.clone();

    // Deterministic: iterate references in timeline (declaration) order.
    for bp_ref in &resolved.profile.blueprints {
        // C-3001: referenced blueprint must exist in the library
        let blueprint = match blueprint_map.get(&bp_ref.id) {
            Some(bp) => bp,
            None => {
                diagnostics.push(
                    Diagnostic::error(
                        "C-3001",
                        Stage::BlueprintExpansion,
                        format!(
                            "Blueprint '{}' not found in profile's blueprint library",
                            bp_ref.id
                        ),
                    )
                    .with_entity(format!("BlueprintReference '{}'", bp_ref.id)),
                );
                continue;
            }
        };

        // C-3002 / C-3004: validate parameters before expansion
        let param_map: serde_json::Map<String, serde_json::Value> = bp_ref
            .parameters
            .as_object()
            .cloned()
            .unwrap_or_default();

        let mut param_valid = true;
        for param in &blueprint.parameters {
            if param.required && !param_map.contains_key(&param.name) {
                diagnostics.push(
                    Diagnostic::error(
                        "C-3002",
                        Stage::BlueprintExpansion,
                        format!(
                            "Required parameter '{}' missing for blueprint '{}'",
                            param.name, blueprint.name
                        ),
                    )
                    .with_entity(format!("Blueprint '{}'", blueprint.name)),
                );
                param_valid = false;
            }
            if let Some(value) = param_map.get(&param.name) {
                if !is_parameter_type_compatible(value, param.param_type) {
                    diagnostics.push(
                        Diagnostic::error(
                            "C-3004",
                            Stage::BlueprintExpansion,
                            format!(
                                "Parameter '{}' has incorrect type for blueprint '{}': expected {:?}, got value",
                                param.name, blueprint.name, param.param_type
                            ),
                        )
                        .with_entity(format!("Blueprint '{}'", blueprint.name)),
                    );
                    param_valid = false;
                }
            }
        }

        if !param_valid {
            continue;
        }

        // C-3003: recursion depth guard (no Blueprint-typed params in current
        // schema, so this is a defensive check).
        let mut depth_map: HashMap<String, usize> = HashMap::new();
        depth_map.insert(bp_ref.id.clone(), 0);
        if let Err(mut d) = check_blueprint_recursion(blueprint, &blueprint_map, &mut depth_map) {
            diagnostics.append(&mut d);
            continue;
        }

        // Expand into primitive actions.
        let generated_actions = expand_single_blueprint(blueprint, &param_map);

        // Package into a generated Operation tagged with provenance.
        let mut op = Operation::new(format!("{} (generated)", blueprint.name));
        op.generated_from = Some(blueprint.id);
        op.tags.push("generated".to_string());
        op.actions = generated_actions;

        let action_names: Vec<String> = op.actions.iter().map(|a| a.name.clone()).collect();
        expansion_map.insert(bp_ref.id.clone(), action_names);
        generated_operations.insert(bp_ref.id.clone(), op.id);
        profile.operations.push(op);
    }

    if diagnostics.iter().any(|d| d.severity == Severity::Error) {
        Err(diagnostics)
    } else {
        Ok(ExpandedProfile {
            profile,
            expansion_map,
            generated_operations,
        })
    }
}

/// Expand a single `Blueprint` + provided parameters into primitive actions.
///
/// Preference order:
/// 1. If the blueprint has template `outputs`, clone them (with a stable id).
/// 2. Otherwise generate actions from known parameters (Vendor Stop, Quest Hub,
///    Grind Area, etc.).
fn expand_single_blueprint(
    blueprint: &Blueprint,
    params: &serde_json::Map<String, serde_json::Value>,
) -> Vec<Action> {
    // Case 1: explicit template outputs (authored blueprints).
    if !blueprint.outputs.is_empty() {
        return blueprint
            .outputs
            .iter()
            .map(|a| {
                let mut cloned = a.clone();
                cloned.id = uuid::Uuid::new_v4();
                cloned
            })
            .collect();
    }

    // Case 2: parameter-driven generation for built-in blueprints.
    let mut actions = Vec::new();

    match blueprint.name.as_str() {
        "Vendor Stop" => {
            if let Some(vendor) = extract_vendor(params, "Vendor") {
                let repair = get_bool(params, "Repair", true);
                let sell_gray = get_bool(params, "SellGray", true);
                let sell_white = get_bool(params, "SellWhite", false);
                actions.push(Action::new(
                    "Vendor Stop",
                    ActionPayload::Vendor(VendorAction {
                        vendor,
                        repair,
                        sell_gray,
                        sell_white,
                        buy: Vec::new(),
                    }),
                ));
            }
        }
        "Quest Hub" => {
            if let Some(vendor) = extract_vendor(params, "Vendor") {
                let repair = get_bool(params, "Repair", true);
                actions.push(Action::new(
                    "Vendor",
                    ActionPayload::Vendor(VendorAction {
                        vendor,
                        repair,
                        sell_gray: true,
                        sell_white: false,
                        buy: Vec::new(),
                    }),
                ));
            }
            if let Some(trainer) = extract_npc(params, "Trainer") {
                let train = get_bool(params, "Train", true);
                if train {
                    actions.push(Action::new(
                        "Train",
                        ActionPayload::Train(TrainAction {
                            trainer,
                            class: sentinel_schema::enums::Class::Warrior,
                        }),
                    ));
                }
            }
            if let Some(quest_giver) = extract_npc(params, "QuestGiver") {
                actions.push(Action::new(
                    "Talk to Quest Giver",
                    ActionPayload::TalkToNpc(TalkToNpcAction {
                        npc: quest_giver,
                        gossip_option: None,
                    }),
                ));
            }
        }
        "Grind Area" => {
            if let (Some(poly), Some(targets)) =
                (extract_polygon(params, "Polygon"), extract_creatures(params, "Targets"))
            {
                actions.push(Action::new(
                    "Grind Area",
                    ActionPayload::GrindArea(GrindAreaAction {
                        polygon: poly,
                        targets,
                        stop_condition: sentinel_schema::action::StopCondition::Manual,
                        loot: Vec::new(),
                    }),
                ));
            }
        }
        _ => {
            // Unknown built-in: no parameter-driven generation. If the blueprint
            // has no outputs either, this yields an empty (no-op) expansion,
            // which is valid for optional-only blueprints.
        }
    }

    actions
}

// ===========================================================================
// Parameter extraction helpers
// ===========================================================================

fn is_parameter_type_compatible(value: &serde_json::Value, param_type: ParameterType) -> bool {
    match param_type {
        ParameterType::Npc
        | ParameterType::Quest
        | ParameterType::Waypoint
        | ParameterType::Polygon
        | ParameterType::Creature
        | ParameterType::Vendor
        | ParameterType::Trainer
        | ParameterType::Flight => value.is_object(),
        ParameterType::Boolean => value.is_boolean(),
        ParameterType::Integer => value.is_i64() || value.is_u64(),
        ParameterType::Float => value.is_f64() || value.is_i64(),
        ParameterType::String => value.is_string(),
        ParameterType::Enum => value.is_string(),
    }
}

fn get_bool(params: &serde_json::Map<String, serde_json::Value>, name: &str, default: bool) -> bool {
    match params.get(name) {
        Some(serde_json::Value::Bool(b)) => *b,
        _ => default,
    }
}

fn extract_vendor(
    params: &serde_json::Map<String, serde_json::Value>,
    name: &str,
) -> Option<VendorEntry> {
    let value = params.get(name)?;
    let pv: ParameterValue = serde_json::from_value(value.clone()).ok()?;
    match pv {
        ParameterValue::Vendor(v) => Some(v),
        _ => None,
    }
}

fn extract_npc(
    params: &serde_json::Map<String, serde_json::Value>,
    name: &str,
) -> Option<sentinel_schema::NpcReference> {
    let value = params.get(name)?;
    let pv: ParameterValue = serde_json::from_value(value.clone()).ok()?;
    match pv {
        ParameterValue::Npc(n) => Some(n),
        ParameterValue::Trainer(n) => Some(n),
        _ => None,
    }
}

fn extract_polygon(
    params: &serde_json::Map<String, serde_json::Value>,
    name: &str,
) -> Option<sentinel_schema::Polygon> {
    let value = params.get(name)?;
    let pv: ParameterValue = serde_json::from_value(value.clone()).ok()?;
    match pv {
        ParameterValue::Polygon(p) => Some(p),
        _ => None,
    }
}

fn extract_creatures(
    params: &serde_json::Map<String, serde_json::Value>,
    name: &str,
) -> Option<Vec<sentinel_schema::CreatureReference>> {
    let value = params.get(name)?;
    let pv: ParameterValue = serde_json::from_value(value.clone()).ok()?;
    match pv {
        ParameterValue::Creature(c) => Some(vec![c]),
        _ => None,
    }
}

/// Check for recursive blueprint references (defensive; current schema has no
/// Blueprint-typed parameter, so this always succeeds).
fn check_blueprint_recursion(
    _blueprint: &Blueprint,
    _blueprint_map: &HashMap<String, &Blueprint>,
    _depth_map: &mut HashMap<String, usize>,
) -> Result<(), Vec<Diagnostic>> {
    Ok(())
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::{Action, BlueprintParameter, BlueprintReference, BlueprintCategory};
    use sentinel_schema::action::WaitAction;
    use sentinel_schema::standard_blueprints::vendor_stop_blueprint;

    fn empty_profile() -> sentinel_schema::Profile {
        sentinel_schema::Profile::new("Test", "Agent")
    }

    fn test_blueprint(name: &str) -> Blueprint {
        Blueprint::new(name, BlueprintCategory::Quest)
    }

    fn test_blueprint_with_param(name: &str, param_name: &str, required: bool) -> Blueprint {
        let mut bp = Blueprint::new(name, BlueprintCategory::Quest);
        bp.parameters.push(BlueprintParameter {
            name: param_name.to_string(),
            param_type: ParameterType::Npc,
            required,
            default: None,
            description: String::new(),
        });
        bp
    }

    fn test_blueprint_reference(id: &str) -> BlueprintReference {
        BlueprintReference::new(id, "1.0.0")
    }

    // -----------------------------------------------------------------------
    // Mock QueryClient
    // -----------------------------------------------------------------------

    struct MockQueryClient;

    impl QueryClient for MockQueryClient {
        fn get_npc(&self, _entry: u32) -> anyhow::Result<sentinel_schema::NpcReference> {
            Err(anyhow::anyhow!("not implemented for blueprint tests"))
        }
        fn get_quest(&self, _id: u32) -> anyhow::Result<sentinel_schema::QuestReference> {
            Err(anyhow::anyhow!("not implemented for blueprint tests"))
        }
        fn get_vendor(&self, _entry: u32) -> anyhow::Result<sentinel_schema::VendorEntry> {
            Err(anyhow::anyhow!("not implemented for blueprint tests"))
        }
        fn get_creature(&self, _entry: u32) -> anyhow::Result<sentinel_schema::CreatureReference> {
            Err(anyhow::anyhow!("not implemented for blueprint tests"))
        }
        fn search_npcs(
            &self,
            _query: &str,
        ) -> anyhow::Result<Vec<sentinel_schema::NpcReference>> {
            Ok(Vec::new())
        }
        fn get_route(
            &self,
            _from_map: u32,
            _from_x: f32,
            _from_y: f32,
            _to_map: u32,
            _to_x: f32,
            _to_y: f32,
        ) -> anyhow::Result<Vec<(f32, f32, f32)>> {
            Ok(Vec::new())
        }
    }

    fn resolved_of(profile: sentinel_schema::Profile) -> ResolvedProfile {
        ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        }
    }

    // -----------------------------------------------------------------------
    // test_expand_empty_blueprints — No blueprints → success, no generated ops
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_empty_blueprints() {
        let profile = empty_profile();
        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        assert!(result.is_ok(), "Expected Ok but got Err: {:?}", result.err());
        let expanded = result.unwrap();
        assert!(expanded.expansion_map.is_empty());
        assert!(expanded.profile.operations.is_empty());
    }

    // -----------------------------------------------------------------------
    // test_expand_valid_blueprint — Reference with all required params → success
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_valid_blueprint() {
        let mut profile = empty_profile();
        let bp = test_blueprint("TestBlueprint");
        let bp_ref = test_blueprint_reference("TestBlueprint");
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        assert!(result.is_ok(), "Expected Ok but got Err: {:?}", result.err());
        let expanded = result.unwrap();
        assert!(expanded.expansion_map.contains_key("TestBlueprint"));
        // No outputs, no param-driven generation → 0 generated actions.
        assert_eq!(expanded.expansion_map.get("TestBlueprint").map(|v| v.len()), Some(0));
        // But a generated Operation was still appended (tagged).
        assert_eq!(expanded.profile.operations.len(), 1);
        assert!(expanded.profile.operations[0].generated_from.is_some());
    }

    // -----------------------------------------------------------------------
    // test_expand_missing_required_param — C-3002 error
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_missing_required_param() {
        let mut profile = empty_profile();
        let bp = test_blueprint_with_param("TestBlueprint", "RequiredNPC", true);
        let bp_ref = test_blueprint_reference("TestBlueprint");
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        assert!(result.is_err(), "Expected Err but got Ok");
        let diags = result.unwrap_err();
        assert!(
            diags.iter().any(|d| d.code == "C-3002"),
            "Expected C-3002, got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }

    // -----------------------------------------------------------------------
    // test_expand_unknown_blueprint — C-3001 error
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_unknown_blueprint() {
        let mut profile = empty_profile();
        let bp_ref = test_blueprint_reference("UnknownBlueprint");
        profile.blueprints = vec![bp_ref];

        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        assert!(result.is_err(), "Expected Err but got Ok");
        let diags = result.unwrap_err();
        assert!(
            diags.iter().any(|d| d.code == "C-3001"),
            "Expected C-3001, got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }

    // -----------------------------------------------------------------------
    // test_expand_vendor_stop_generates_actions — real expansion (SENT-6.3)
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_vendor_stop_generates_actions() {
        let mut profile = empty_profile();
        let bp = vendor_stop_blueprint();
        let mut bp_ref = BlueprintReference::new("Vendor Stop", "1.0.0");
        // Provide a Vendor parameter.
        let vendor = VendorEntry {
            npc: sentinel_schema::NpcReference::new(
                1234,
                "Brother Danil",
                "Goldshire",
                sentinel_schema::Waypoint::default(),
            ),
            sells: Vec::new(),
            repairs: true,
        };
        bp_ref = bp_ref.with_param(
            "Vendor",
            serde_json::to_value(ParameterValue::Vendor(vendor)).unwrap(),
        );
        bp_ref = bp_ref.with_param("Repair", serde_json::json!(true));
        bp_ref = bp_ref.with_param("SellGray", serde_json::json!(true));

        profile.blueprint_library = vec![bp];
        profile.blueprints = vec![bp_ref];

        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        assert!(result.is_ok(), "Expected Ok but got Err: {:?}", result.err());

        let expanded = result.unwrap();
        let actions = expanded.expansion_map.get("Vendor Stop").unwrap();
        assert_eq!(actions.len(), 1, "Vendor Stop should expand to 1 action");
        // A generated Operation should exist, tagged with provenance.
        assert_eq!(expanded.profile.operations.len(), 1);
        let gen_op = &expanded.profile.operations[0];
        assert!(gen_op.generated_from.is_some());
        assert!(gen_op.tags.contains(&"generated".to_string()));
        assert_eq!(gen_op.actions.len(), 1);
        assert!(matches!(gen_op.actions[0].payload, ActionPayload::Vendor(_)));
    }

    // -----------------------------------------------------------------------
    // test_expand_deterministic_order — timeline order preserved
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_deterministic_order() {
        let mut profile = empty_profile();
        let bp_a = test_blueprint("Alpha");
        let bp_b = test_blueprint("Beta");
        profile.blueprint_library = vec![bp_a.clone(), bp_b.clone()];
        profile.blueprints = vec![
            test_blueprint_reference("Alpha"),
            test_blueprint_reference("Beta"),
        ];

        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client).unwrap();
        // Generated operations appear in the same order as the references.
        assert_eq!(result.profile.operations.len(), 2);
        assert_eq!(result.profile.operations[0].name, "Alpha (generated)");
        assert_eq!(result.profile.operations[1].name, "Beta (generated)");
    }

    // -----------------------------------------------------------------------
    // test_max_recursion_depth — defensive guard (no nesting in schema)
    // -----------------------------------------------------------------------

    #[test]
    fn test_max_recursion_depth() {
        let mut profile = empty_profile();
        let bp = test_blueprint("TestBlueprint");
        let bp_ref = test_blueprint_reference("TestBlueprint");
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        assert!(result.is_ok());
    }

    // -----------------------------------------------------------------------
    // test_parameter_type_mismatch — C-3004 error
    // -----------------------------------------------------------------------

    #[test]
    fn test_parameter_type_mismatch() {
        let mut profile = empty_profile();
        let mut bp = Blueprint::new("TestBlueprint", BlueprintCategory::Quest);
        bp.parameters.push(BlueprintParameter {
            name: "RequiredNPC".to_string(),
            param_type: ParameterType::Npc,
            required: true,
            default: None,
            description: String::new(),
        });
        let bp_ref = BlueprintReference::new("TestBlueprint", "1.0.0")
            .with_param("RequiredNPC", serde_json::Value::Bool(true));
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        assert!(result.is_err(), "Expected Err for type mismatch, got Ok");
        let diags = result.unwrap_err();
        assert!(
            diags.iter().any(|d| d.code == "C-3004"),
            "Expected C-3004, got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }

    // -----------------------------------------------------------------------
    // test_expand_template_outputs — authored outputs cloned
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_template_outputs() {
        let mut profile = empty_profile();
        let mut bp = test_blueprint("TemplateBP");
        bp.outputs = vec![Action::new(
            "Action1",
            sentinel_schema::ActionPayload::Wait(WaitAction { duration_ms: 1000 }),
        )];
        let bp_ref = test_blueprint_reference("TemplateBP");
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = resolved_of(profile);
        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client).unwrap();
        let actions = &result.profile.operations[0].actions;
        assert_eq!(actions.len(), 1);
        assert!(matches!(actions[0].payload, ActionPayload::Wait(_)));
    }
}
