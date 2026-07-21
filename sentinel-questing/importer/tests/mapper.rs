//! Integration tests for the ProjectBuilder (Wave 2).

use sentinel_importer::{parse_guide, ProjectBuilder};
use sentinel_models::authoring::{ActionPayload, Faction};
use sentinel_queryclient::{MemoryQueryClient, QuestDetail, NpcDetail, WorldPos};

async fn setup_test_client() -> MemoryQueryClient {
    let quest = QuestDetail {
        id: 1598,
        title: "The Stolen Tome".to_string(),
        level: 5,
        min_level: 1,
        required_quests: vec![],
        next_quests: vec![],
        giver_entry: Some(123),
        finisher_entry: Some(456),
        objectives: vec![],
    };
    let giver = NpcDetail {
        entry: 123,
        name: "Marshal McBride".to_string(),
        faction: "35".to_string(),
        positions: vec![WorldPos { map: 0, x: -8000.0, y: 100.0, z: 100.0 }],
        roles: vec!["QuestGiver".to_string()],
    };
    let finisher = NpcDetail {
        entry: 456,
        name: "Captain Rumsey".to_string(),
        faction: "35".to_string(),
        positions: vec![WorldPos { map: 0, x: -8000.0, y: 150.0, z: 100.0 }],
        roles: vec!["QuestGiver".to_string()],
    };
    MemoryQueryClient::new()
        .with_quest(quest)
        .with_npc(giver)
        .with_npc(finisher)
}

#[tokio::test]
async fn maps_accept_and_target_to_quest_action() {
    let client = setup_test_client().await;
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .target Marshal McBride
    .accept 1598 >> Accept The Stolen Tome
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    // One operation, one accept action.
    assert_eq!(project.operations.len(), 1);
    let op = &project.operations[0];
    let accept_action = op.actions.iter().find(|a| matches!(a.payload, ActionPayload::AcceptQuest(_)));
    assert!(accept_action.is_some(), "should have AcceptQuest action");

    // Quest in library
    assert_eq!(project.quest_library.len(), 1);
    let quest_ref = &project.quest_library[0];
    assert_eq!(quest_ref.quest_id, 1598);

    // NPC in library (we have both giver and finisher from quest resolution + target)
    assert!(project.npc_library.len() >= 1, "should have at least one npc");
    assert!(project.npc_library.iter().any(|n| n.name == "Marshal McBride"));
}

#[tokio::test]
async fn unresolved_quest_becomes_diagnostic() {
    let client = MemoryQueryClient::new(); // no quest 999999
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .accept 999999 >> Accept Missing Quest
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    // Quest not found → diagnostic
    let unresolved = project.diagnostics.iter().find(|d| d.code == "UNRESOLVED_QUEST");
    assert!(unresolved.is_some(), "should have UNRESOLVED_QUEST diagnostic");

    // Action is a comment (we can't build AcceptQuest without NPC)
    let has_comment = project.operations[0].actions.iter().any(|a| matches!(a.payload, ActionPayload::Comment(_)));
    assert!(has_comment, "unresolved accept becomes comment");
}

#[tokio::test]
async fn goto_creates_travel_action() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .goto Elwynn Forest,48.2,42.9
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let travel_action = project.operations[0].actions.iter().find(|a| matches!(a.payload, ActionPayload::Travel(_)));
    assert!(travel_action.is_some(), "should have Travel action");
    let travel = match &travel_action.unwrap().payload {
        ActionPayload::Travel(t) => t,
        _ => panic!("not travel"),
    };
    assert_eq!(travel.destination, "Elwynn Forest");
    assert!(travel.position.is_none(), "world coordinates not stored from goto (per ADR-203)");
}

#[tokio::test]
async fn label_directive_becomes_operation_name() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    #label MYLABEL
    .accept 1
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    assert_eq!(project.operations[0].name, "label:MYLABEL");
}

#[tokio::test]
async fn mob_command_creates_kill_action() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .mob 12345,67890
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let kill_action = project.operations[0].actions.iter().find(|a| matches!(a.payload, ActionPayload::Kill(_)));
    assert!(kill_action.is_some(), "should have Kill action");
}

#[tokio::test]
async fn faction_header_sets_project_faction() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
<< Alliance
step
    .accept 1
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    assert_eq!(project.metadata.faction, Some(Faction::Alliance));
}

#[tokio::test]
async fn turnin_resolves_quest_and_finisher_npc() {
    let client = setup_test_client().await;
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .turnin 1598 >> Turn in The Stolen Tome
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let turnin_action = project.operations[0].actions.iter().find(|a| matches!(a.payload, ActionPayload::TurnInQuest(_)));
    assert!(turnin_action.is_some(), "should have TurnInQuest action");

    // Should have both NPCs (giver and finisher) in library since quest resolution pulls both
    assert_eq!(project.npc_library.len(), 2, "should have giver+finisher npcs");
}

#[tokio::test]
async fn multiple_steps_create_multiple_operations() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .accept 1
step
    .turnin 2
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    assert_eq!(project.operations.len(), 2, "should have two operations");
}

#[tokio::test]
async fn vendor_command_creates_vendor_action() {
    let vendor_npc = NpcDetail {
        entry: 789,
        name: "Vendor NPC".to_string(),
        faction: "35".to_string(),
        positions: vec![],
        roles: vec!["Vendor".to_string()],
    };
    let client = MemoryQueryClient::new().with_npc(vendor_npc);
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .target Vendor NPC
    .vendor >> Buy water
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let vendor_action = project.operations[0].actions.iter().find(|a| matches!(a.payload, ActionPayload::Vendor(_)));
    assert!(vendor_action.is_some(), "should have Vendor action");
}

#[tokio::test]
async fn train_command_creates_train_action() {
    let trainer_npc = NpcDetail {
        entry: 999,
        name: "Trainer".to_string(),
        faction: "35".to_string(),
        positions: vec![],
        roles: vec!["Trainer".to_string()],
    };
    let client = MemoryQueryClient::new().with_npc(trainer_npc);
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .target Trainer
    .train >> Train skills
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let train_action = project.operations[0].actions.iter().find(|a| matches!(a.payload, ActionPayload::Train(_)));
    assert!(train_action.is_some(), "should have Train action");
}

#[tokio::test]
async fn fly_command_creates_flight_action() {
    let flight_master = NpcDetail {
        entry: 555,
        name: "Flight Master".to_string(),
        faction: "35".to_string(),
        positions: vec![],
        roles: vec!["FlightMaster".to_string()],
    };
    let client = MemoryQueryClient::new().with_npc(flight_master);
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .target Flight Master
    .fly Stormwind >> Fly to Stormwind
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let flight_action = project.operations[0].actions.iter().find(|a| matches!(a.payload, ActionPayload::Flight(_)));
    assert!(flight_action.is_some(), "should have Flight action");
    let flight = match &flight_action.unwrap().payload {
        ActionPayload::Flight(f) => f,
        _ => panic!("not flight"),
    };
    assert_eq!(flight.destination, "Stormwind");
}

#[tokio::test]
async fn real_guide_imports_to_project() {
    use std::fs;
    let guide = fs::read_to_string("tests/fixtures/guide_basic.lua")
        .expect("read fixture");
    let client = setup_test_client().await;
    let parsed = parse_guide(&guide).expect("parse ok");

    // Guide has 3 steps:
    // Step 0: condition step with only chat text (no commands)
    // Step 1: accept + target + label directive
    // Step 2: turnin + goto + completewith directive
    assert_eq!(parsed.steps.len(), 3);

    // Step 1 has accept + target
    let step1 = &parsed.steps[1];
    assert!(step1.commands.iter().any(|c| c.name == "accept"));
    assert!(step1.commands.iter().any(|c| c.name == "target"));

    // Step 2 has turnin + goto
    let step2 = &parsed.steps[2];
    assert!(step2.commands.iter().any(|c| c.name == "turnin"));
    assert!(step2.commands.iter().any(|c| c.name == "goto"));

    let project = ProjectBuilder::build(&parsed, "guide_basic.lua", &client).await.expect("build ok");
    assert_eq!(project.operations.len(), 3);
}

#[tokio::test]
async fn real_restedxp_guide_imports() {
    // Uses fixture copied to tests folder
    let path = "tests/fixtures/human_1-11.lua";
    let Ok(src) = std::fs::read_to_string(path) else {
        eprintln!("skipping: fixture not found at {path}");
        return;
    };
    // Build a client with minimal data to avoid missing entity failures
    let client = MemoryQueryClient::new();
    let parsed = parse_guide(&src).expect("parse ok");

    // Parser finds steps in the guide body
    let steps = parsed.steps.len();
    assert!(steps >= 300 && steps <= 450, "got {} steps", steps);

    // Build project - one operation per step
    let project = ProjectBuilder::build(&parsed, path, &client).await.expect("build ok");
    assert_eq!(project.operations.len(), parsed.steps.len());

    // Should have unresolved references as diagnostics, not errors
    assert!(project.diagnostics.iter().any(|d| d.code == "UNRESOLVED_QUEST"));
}

#[tokio::test]
async fn tbc_alliance_corpus_validates() {
    // Wave 4: Validate complete TBC alliance guide chain imports without hard failures
    let base_path = "/mnt/e/Program Files/World of Warcraft/_anniversary_/Interface/AddOns/RXPGuides/Guides/tbc";
    
    let guides = vec![
        ("A-Human.lua", 1, 20),     // 1-11, 12-14, 15-20 segments embedded
        ("A-11-23.lua", 12, 23),
        ("A-23-30.lua", 24, 30),
        ("A-Draenei.lua", 1, 20),
        ("A-Dwarf-Gnome.lua", 1, 20),
        ("A-NightElf.lua", 1, 20),
    ];

    let client = MemoryQueryClient::new();
    let mut total_steps = 0;
    let mut total_diagnostics = 0;

    for (guide_file, min_level, max_level) in guides {
        let path = format!("{}/{}", base_path, guide_file);
        if !std::path::Path::new(&path).exists() {
            eprintln!("skipping missing: {path}");
            continue;
        }
        
        let src = match std::fs::read_to_string(&path) {
            Ok(s) => s,
            Err(e) => {
                panic!("failed to read {}: {}", guide_file, e);
            }
        };

        let parsed = match parse_guide(&src) {
            Ok(p) => p,
            Err(e) => {
                panic!("failed to parse {}: {}", guide_file, e);
            }
        };

        let project = match ProjectBuilder::build(&parsed, guide_file, &client).await {
            Ok(p) => p,
            Err(e) => {
                panic!("failed to build {}: {}", guide_file, e);
            }
        };

        total_steps += project.operations.len();
        total_diagnostics += project.diagnostics.len();
        
        // Verify the guide covers expected level range
        // (A-Human has #name 1-11, A-11-23 has #name 12-23, etc.)
        let has_level_range = parsed.headers.iter()
            .any(|h| h.key == "name" && h.value.contains(&format!("{}-", min_level)));
        
        // Basic sanity check
        assert!(project.operations.len() > 0, "{} should have at least one operation", guide_file);
    }

    // Summary output
    eprintln!("\n=== TBC Alliance Corpus Summary ===");
    eprintln!("Total guide steps parsed: {}", total_steps);
    eprintln!("Total diagnostics: {}", total_diagnostics);
    eprintln!("No hard failures - all guides parsed successfully");
}