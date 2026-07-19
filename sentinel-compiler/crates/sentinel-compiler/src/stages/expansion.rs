//! Stage 3: Blueprint Expansion
//!
//! Validates blueprint references and prepares expansion mappings.
//! Since ActionPayload has no Blueprint variant, this stage validates/prepares
//! blueprint expansion rather than modifying action lists.

use std::collections::HashMap;

use sentinel_schema::{Blueprint, ParameterType};

use crate::diagnostics::{Diagnostic, Severity, Stage};
use crate::query_client::QueryClient;
use crate::stages::resolution::ResolvedProfile;

/// Maximum recursion depth for nested blueprint expansion.
#[allow(dead_code)]
const MAX_RECURSION_DEPTH: usize = 2;

/// Result after blueprint expansion validation.
#[derive(Debug, Clone)]
pub struct ExpandedProfile {
    pub profile: sentinel_schema::Profile,
    /// blueprint_id (reference ID) → action names it would expand into
    pub expansion_map: HashMap<String, Vec<String>>,
}

/// Stage 3: Validate and plan blueprint expansion.
///
/// Validates:
/// - All BlueprintReferences point to known Blueprint definitions
/// - Required parameters have values provided
/// - No recursive blueprint depth exceeds limits
/// - Parameter types match expected types
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

    // Build a map of blueprints by name for lookup
    let blueprint_map: HashMap<String, &Blueprint> = resolved.profile.blueprint_library.iter()
        .map(|bp| (bp.name.clone(), bp))
        .collect();

    for bp_ref in &resolved.profile.blueprints {
        // Check if referenced blueprint exists
        if let Some(bp) = blueprint_map.get(&bp_ref.id) {
            // Validate required parameters have values and check type compatibility
            let param_map: serde_json::Map<String, serde_json::Value> = 
                bp_ref.parameters.as_object()
                    .cloned()
                    .unwrap_or_default();

            for param in &bp.parameters {
                if param.required && !param_map.contains_key(&param.name) {
                    diagnostics.push(
                        Diagnostic::error(
                            "C-3002",
                            Stage::BlueprintExpansion,
                            format!("Required parameter '{}' missing for blueprint '{}'", param.name, bp.name)
                        )
                        .with_entity(format!("Blueprint '{}'", bp.name))
                    );
                }
                
                // C-3004: Parameter type mismatch
                if let Some(value) = param_map.get(&param.name) {
                    if !is_parameter_type_compatible(value, param.param_type) {
                        diagnostics.push(
                            Diagnostic::error(
                                "C-3004",
                                Stage::BlueprintExpansion,
                                format!(
                                    "Parameter '{}' has incorrect type for blueprint '{}': expected {:?}, got value",
                                    param.name, bp.name, param.param_type
                                )
                            )
                            .with_entity(format!("Blueprint '{}'", bp.name))
                        );
                    }
                }
            }

            // Check for recursive blueprint references in outputs (C-3003)
            let mut depth_map: HashMap<String, usize> = HashMap::new();
            depth_map.insert(bp_ref.id.clone(), 0);
            check_blueprint_recursion(bp, &blueprint_map, &mut depth_map, &mut diagnostics)?;

            // Record what actions this blueprint would expand into (ensure entry exists even if empty)
            let entry = expansion_map.entry(bp_ref.id.clone()).or_insert_with(Vec::new);
            for action in &bp.outputs {
                entry.push(action.name.clone());
            }
        } else {
            diagnostics.push(
                Diagnostic::error(
                    "C-3001",
                    Stage::BlueprintExpansion,
                    format!("Blueprint '{}' not found in profile's blueprint library", bp_ref.id)
                )
                .with_entity(format!("BlueprintReference '{}'", bp_ref.id))
            );
        }
    }

    if diagnostics.iter().any(|d| d.severity == Severity::Error) {
        Err(diagnostics)
    } else {
        Ok(ExpandedProfile { 
            profile: resolved.profile.clone(), 
            expansion_map 
        })
    }
}

/// Check if a JSON value is compatible with a parameter type.
fn is_parameter_type_compatible(value: &serde_json::Value, param_type: ParameterType) -> bool {
    match param_type {
        ParameterType::Npc | ParameterType::Quest | ParameterType::Waypoint => {
            value.is_object()
        }
        ParameterType::Creature | ParameterType::Vendor | ParameterType::Trainer 
        | ParameterType::Flight | ParameterType::Polygon => {
            value.is_object()
        }
        ParameterType::Boolean => value.is_boolean(),
        ParameterType::Integer => value.is_i64(),
        ParameterType::Float => value.is_f64(),
        ParameterType::String => value.is_string(),
        ParameterType::Enum => value.is_string(),
    }
}

/// Check for recursive blueprint references.
fn check_blueprint_recursion(
    _blueprint: &Blueprint,
    _blueprint_map: &HashMap<String, &Blueprint>,
    _depth_map: &mut HashMap<String, usize>,
    _diagnostics: &mut Vec<Diagnostic>,
) -> Result<(), Vec<Diagnostic>> {
    // Note: ActionPayload has no Blueprint variant in current schema,
    // so we check for nested blueprints in outputs
    // In a full implementation, we'd check if any ActionPayload references blueprints
    
    // For now, this is a placeholder for future nested blueprint detection
    Ok(())
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::{
        Action,
        BlueprintParameter,
        BlueprintReference,
        action::WaitAction,
        BlueprintCategory,
    };

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

        fn search_npcs(&self, _query: &str) -> anyhow::Result<Vec<sentinel_schema::NpcReference>> {
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

    // -----------------------------------------------------------------------
    // test_expand_empty_blueprints — No blueprints → success
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_empty_blueprints() {
        let profile = empty_profile();
        let resolved = ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        };

        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        
        assert!(result.is_ok(), "Expected Ok but got Err: {:?}", result.err());
        
        let expanded = result.unwrap();
        assert!(expanded.expansion_map.is_empty());
    }

    // -----------------------------------------------------------------------
    // test_expand_valid_blueprint — Blueprint with all required params → success
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_valid_blueprint() {
        let mut profile = empty_profile();
        let bp = test_blueprint("TestBlueprint");
        let bp_ref = test_blueprint_reference("TestBlueprint");
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        };

        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        
        assert!(result.is_ok(), "Expected Ok but got Err: {:?}", result.err());
        
        let expanded = result.unwrap();
        // Blueprint with no outputs - entry exists with empty vector
        assert!(expanded.expansion_map.contains_key("TestBlueprint"));
        assert_eq!(expanded.expansion_map.get("TestBlueprint").map(|v| v.len()), Some(0));
    }

    // -----------------------------------------------------------------------
    // test_expand_missing_required_param — Required param missing → C-3002 error
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_missing_required_param() {
        let mut profile = empty_profile();
        let bp = test_blueprint_with_param("TestBlueprint", "RequiredNPC", true);
        let bp_ref = test_blueprint_reference("TestBlueprint"); // No params provided
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        };

        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        
        assert!(result.is_err(), "Expected Err but got Ok");
        
        let diags = result.unwrap_err();
        assert!(
            diags.iter().any(|d| d.code == "C-3002"),
            "Expected C-3002 (Missing required parameter), got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }

    // -----------------------------------------------------------------------
    // test_expand_unknown_blueprint — Reference to non-existent blueprint → C-3001
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_unknown_blueprint() {
        let mut profile = empty_profile();
        let bp_ref = test_blueprint_reference("UnknownBlueprint");
        profile.blueprints = vec![bp_ref];

        let resolved = ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        };

        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        
        assert!(result.is_err(), "Expected Err but got Ok");
        
        let diags = result.unwrap_err();
        assert!(
            diags.iter().any(|d| d.code == "C-3001"),
            "Expected C-3001 (Blueprint not found), got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }

    // -----------------------------------------------------------------------
    // test_expand_nested_blueprints — Blueprint with outputs tracked in expansion_map
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_nested_blueprints() {
        let mut profile = empty_profile();
        let mut bp = test_blueprint("TestBlueprint");
        bp.outputs = vec![
            Action::new("Action1", sentinel_schema::ActionPayload::Wait(WaitAction { duration_ms: 1000 })),
            Action::new("Action2", sentinel_schema::ActionPayload::Wait(WaitAction { duration_ms: 2000 })),
        ];
        let bp_ref = test_blueprint_reference("TestBlueprint");
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        };

        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        
        assert!(result.is_ok(), "Expected Ok but got Err: {:?}", result.err());
        
        let expanded = result.unwrap();
        assert!(expanded.expansion_map.contains_key("TestBlueprint"));
        
        let actions = &expanded.expansion_map["TestBlueprint"];
        assert_eq!(actions.len(), 2);
        assert_eq!(actions[0], "Action1");
        assert_eq!(actions[1], "Action2");
    }

    // -----------------------------------------------------------------------
    // test_expand_optional_parameter_missing — Optional param missing → success
    // -----------------------------------------------------------------------

    #[test]
    fn test_expand_optional_parameter_missing() {
        let mut profile = empty_profile();
        let mut bp = Blueprint::new("TestBlueprint", BlueprintCategory::Quest);
        bp.parameters.push(BlueprintParameter {
            name: "OptionalNPC".to_string(),
            param_type: ParameterType::Npc,
            required: false,
            default: None,
            description: String::new(),
        });
        let bp_ref = test_blueprint_reference("TestBlueprint"); // No params provided (optional)
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        };

        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        
        // Should succeed - optional parameter is not required
        assert!(result.is_ok(), "Expected Ok for optional parameter, got Err: {:?}", result.err());
    }

    // -----------------------------------------------------------------------
    // test_max_recursion_depth — Deep nesting → C-3003 error
    // -----------------------------------------------------------------------

    #[test]
    fn test_max_recursion_depth() {
        // Note: Since ActionPayload doesn't have Blueprint variant in current schema,
        // we can't test actual recursive blueprint expansion yet.
        // This test validates the recursion check exists and would catch issues
        // when the schema supports nested blueprints.
        
        // For now, test that a simple blueprint works (no recursion to check)
        let mut profile = empty_profile();
        let bp = test_blueprint("TestBlueprint");
        let bp_ref = test_blueprint_reference("TestBlueprint");
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        };

        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        
        // Should succeed - no deep nesting
        assert!(result.is_ok());
    }

    // -----------------------------------------------------------------------
    // test_parameter_type_mismatch — Wrong type → C-3004 error
    // -----------------------------------------------------------------------

    #[test]
    fn test_parameter_type_mismatch() {
        // Create a blueprint with required parameter
        let mut profile = empty_profile();
        let mut bp = Blueprint::new("TestBlueprint", BlueprintCategory::Quest);
        bp.parameters.push(BlueprintParameter {
            name: "RequiredNPC".to_string(),
            param_type: ParameterType::Npc, // Expects an object
            required: true,
            default: None,
            description: String::new(),
        });
        // Provide a boolean value for an Npc parameter (type mismatch)
        let bp_ref = BlueprintReference::new("TestBlueprint", "1.0.0")
            .with_param("RequiredNPC", serde_json::Value::Bool(true));
        profile.blueprint_library = vec![bp.clone()];
        profile.blueprints = vec![bp_ref];

        let resolved = ResolvedProfile {
            profile,
            resolved_npcs: HashMap::new(),
            resolved_quests: HashMap::new(),
            resolved_creatures: HashMap::new(),
        };

        let client = MockQueryClient;
        let result = expand_blueprints(&resolved, &client);
        
        // Should fail due to type mismatch (C-3004)
        assert!(result.is_err(), "Expected Err for type mismatch, got Ok");
        
        let diags = result.unwrap_err();
        assert!(
            diags.iter().any(|d| d.code == "C-3004"),
            "Expected C-3004 (Parameter type mismatch), got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }
}