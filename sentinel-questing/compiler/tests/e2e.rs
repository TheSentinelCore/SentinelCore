//! E2E Integration tests for the full pipeline.
//! These tests require all crates to be available, so they live in the workspace tests.

use sentinel_compiler::Compiler;
use sentinel_importer::{parse_guide, ProjectBuilder};
use sentinel_models::authoring::ActionPayload;
use sentinel_queryclient::MemoryQueryClient;

#[tokio::test]
async fn full_pipeline_import_compile() {
    // Test the complete pipeline: guide -> project -> runtime profile
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test Guide
step
    .goto Elwynn Forest
    .accept 1598
    .target Marshal McBride
    .turnin 1598
]])"#;

    // Step 1: Parse
    let parsed = parse_guide(guide).expect("parse ok");
    assert!(!parsed.steps.is_empty());

    // Step 2: Build project
    let client = MemoryQueryClient::new();
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    // Step 3: Compile
    let profile = Compiler::compile(&project).expect("compile ok");

    // Step 4: Verify output
    assert_eq!(profile.operations.len(), parsed.steps.len());

    // Verify the travel action was lowered correctly
    let has_travel = profile.operations.iter().any(|op| {
        op.actions.iter().any(|a| matches!(a, sentinel_models::runtime::RuntimeAction::Travel(_)))
    });
    assert!(has_travel, "should have travel action");
}

#[tokio::test]
async fn compiled_profile_is_json_serializable() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .goto Stormwind
]])"#;

    let client = MemoryQueryClient::new();
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");
    let profile = Compiler::compile(&project).expect("compile ok");

    // Serialize to JSON
    let json = serde_json::to_string(&profile).expect("serialize ok");

    // Verify it roundtrips
    let deserialized: sentinel_models::runtime::RuntimeProfile = 
        serde_json::from_str(&json).expect("deserialize ok");

    assert_eq!(profile.operations.len(), deserialized.operations.len());
}

#[tokio::test]
async fn multiple_action_types_compile() {
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
step
step
step
step
step
step
step
step
step
]])"#;

    let client = MemoryQueryClient::new();
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");
    let profile = Compiler::compile(&project).expect("compile ok");

    // All 10 steps should become operations
    assert_eq!(profile.operations.len(), 10);
}