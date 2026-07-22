//! Integration tests for the full Sentinel Questing pipeline.
//! Tests import → validate → compile end-to-end using fixture data.

//! Integration tests for the full Sentinel Questing pipeline.
//! Tests validate → compile → serialize round-trip end-to-end using fixture data.

#[cfg(test)]
mod tests {
    use sentinel_models::authoring::Project;

    fn load_sample_project() -> Project {
        let json = include_str!("../fixtures/sample_project.json");
        serde_json::from_str(json).expect("Failed to parse sample_project.json fixture")
    }

    // ==================================================================
    // W8.4: Full pipeline E2E tests
    // ==================================================================

    #[test]
    fn pipeline_validate_passes_clean_project() {
    let project = load_sample_project();
    let diags = sentinel_validator::Validator::validate(&project);

    // The sample project should pass without diagnostics
    // (no duplicate NPCs, no broken references, no circular conditions)
    let errors: Vec<_> = diags.iter().filter(|d| {
        matches!(d.severity, sentinel_models::authoring::Severity::Error)
    }).collect();
    assert!(
        errors.is_empty(),
        "Expected no validation errors, got: {:?}",
        errors
    );
}

#[test]
fn pipeline_compiles_to_valid_profile() {
    let project = load_sample_project();
    let profile = sentinel_compiler::Compiler::compile(&project)
        .expect("Compiler should succeed for valid project");

    // Verify profile structure
    assert!(!profile.name.is_empty(), "Profile must have a name");
    assert_eq!(profile.operations.len(), 2, "Expected 2 operations");

    // Verify operation 1
    let op1 = &profile.operations[0];
    assert_eq!(op1.name, "Northshire Start");
    assert_eq!(op1.actions.len(), 3, "Northshire Start should have 3 actions");

    // Verify action types in op1
    assert!(matches!(op1.actions[0], sentinel_models::runtime::RuntimeAction::AcceptQuest(_)));
    assert!(matches!(op1.actions[1], sentinel_models::runtime::RuntimeAction::Kill(_)));
    assert!(matches!(op1.actions[2], sentinel_models::runtime::RuntimeAction::SetVariable(_)));

    // Verify operation 2
    let op2 = &profile.operations[1];
    assert_eq!(op2.name, "Goldshire Delivery");
    assert_eq!(op2.actions.len(), 3, "Goldshire Delivery should have 3 actions");

    // Verify action types in op2
    assert!(matches!(op2.actions[0], sentinel_models::runtime::RuntimeAction::Travel(_)));
    assert!(matches!(op2.actions[1], sentinel_models::runtime::RuntimeAction::TurnInQuest(_)));
    assert!(matches!(op2.actions[2], sentinel_models::runtime::RuntimeAction::SetVariable(_)));

    // Verify NPC references resolved to entries
    if let sentinel_models::runtime::RuntimeAction::AcceptQuest(a) = &op1.actions[0] {
        assert_eq!(a.npc_entry, 197, "Marshal McBride should resolve to entry 197");
        assert_eq!(a.quest_id, 33);
    } else {
        panic!("First action should be AcceptQuest");
    }

    // Verify content hash is set
    assert!(!profile.content_hash.is_empty(), "Content hash must be computed");
}

#[test]
fn pipeline_validate_detects_duplicate_npc() {
    let mut project = load_sample_project();
    // Add a duplicate NPC entry
    project.npc_library.push(sentinel_models::authoring::NPCReference {
        id: uuid::Uuid::new_v4(),
        entry: Some(197),
        guid: None,
        name: "Duplicate McBride".to_string(),
        faction: None,
        roles: vec![],
        position: None,
        source: None,
        notes: None,
    });
    let diags = sentinel_validator::Validator::validate(&project);
    assert!(
        diags.iter().any(|d| d.code == "DUPLICATE_NPC"),
        "Expected DUPLICATE_NPC diagnostic"
    );
}

#[test]
fn pipeline_serialize_roundtrip() {
    let project = load_sample_project();
    let profile = sentinel_compiler::Compiler::compile(&project)
        .expect("Compile should succeed");

    // Serialize to JSON and back
    let json = serde_json::to_string(&profile).expect("Serialize profile");
    let deserialized: sentinel_models::runtime::RuntimeProfile =
        serde_json::from_str(&json).expect("Deserialize profile");

    assert_eq!(profile.name, deserialized.name);
    assert_eq!(profile.operations.len(), deserialized.operations.len());
    assert_eq!(profile.content_hash, deserialized.content_hash);
}

#[test]
fn pipeline_validate_detects_broken_npc_ref() {
    let mut project = load_sample_project();
    // Add an operation with a reference to a non-existent NPC
    let bad_npc_id = uuid::Uuid::new_v4();
    project.operations.push(sentinel_models::authoring::Operation {
        id: uuid::Uuid::new_v4(),
        name: "Bad Ref".to_string(),
        description: None,
        minimum_level: None,
        maximum_level: None,
        enabled: true,
        conditions: vec![],
        sticky: false,
        looping: false,
        actions: vec![sentinel_models::authoring::Action {
            id: uuid::Uuid::new_v4(),
            enabled: true,
            condition: None,
            note: None,
            payload: sentinel_models::authoring::ActionPayload::Vendor(
                sentinel_models::authoring::VendorAction {
                    npc: bad_npc_id,
                    sell_grey: false,
                    repair: false,
                    buy_items: vec![],
                    minimum_free_slots: None,
                },
            ),
        }],
        notes: None,
    });
    let diags = sentinel_validator::Validator::validate(&project);
    assert!(
        diags.iter().any(|d| d.code == "BROKEN_NPC_REFERENCE"),
        "Expected BROKEN_NPC_REFERENCE diagnostic, got: {:?}",
        diags
    );
}

#[test]
fn pipeline_compile_fails_with_unresolved_npc() {
    let mut project = load_sample_project();
    // Add a Vendor action referencing an NPC not in the library
    let missing_npc_id = uuid::Uuid::new_v4();
    project.operations.push(sentinel_models::authoring::Operation {
        id: uuid::Uuid::new_v4(),
        name: "Missing NPC".to_string(),
        description: None,
        minimum_level: None,
        maximum_level: None,
        enabled: true,
        conditions: vec![],
        sticky: false,
        looping: false,
        actions: vec![sentinel_models::authoring::Action {
            id: uuid::Uuid::new_v4(),
            enabled: true,
            condition: None,
            note: None,
            payload: sentinel_models::authoring::ActionPayload::Vendor(
                sentinel_models::authoring::VendorAction {
                    npc: missing_npc_id,
                    sell_grey: false,
                    repair: false,
                    buy_items: vec![],
                    minimum_free_slots: None,
                },
            ),
        }],
        notes: None,
    });
    let result = sentinel_compiler::Compiler::compile(&project);
    assert!(
        result.is_err(),
        "Compiler should fail with unresolved NPC reference"
    );
}

#[test]
fn pipeline_end_to_end_success() {
    // Full pipeline: validate → compile → serialize → deserialize
    // Then verify all data integrity
    let project = load_sample_project();

    // 1. Validate (allow warnings/info — only errors block the pipeline)
    let diags = sentinel_validator::Validator::validate(&project);
    let errors: Vec<_> = diags.iter().filter(|d| {
        matches!(d.severity, sentinel_models::authoring::Severity::Error)
    }).collect();
    assert!(
        errors.is_empty(),
        "Expected no validation errors, got: {:?}",
        errors
    );

    // 2. Compile
    let profile = sentinel_compiler::Compiler::compile(&project)
        .expect("Compilation should succeed");

    // 3. Serialize
    let json = serde_json::to_string_pretty(&profile)
        .expect("Serialization should succeed");

    // 4. Verify JSON contains expected data
    assert!(json.contains("Northshire Start"));
    assert!(json.contains("Goldshire Delivery"));
    assert!(json.contains("content_hash"));

    // 5. Deserialize and verify content_hash stability
    let deserialized: sentinel_models::runtime::RuntimeProfile =
        serde_json::from_str(&json).expect("Deserialization should succeed");
    assert_eq!(profile.content_hash, deserialized.content_hash);

    // 6. Verify the content hash is deterministic
    let profile2 = sentinel_compiler::Compiler::compile(&project)
        .expect("Second compilation should succeed");
    assert_eq!(
        profile.content_hash, profile2.content_hash,
        "Content hash must be deterministic across compilations"
    );
}
}
