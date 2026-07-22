//! Integration tests for the ProjectBuilder (Wave 2).

use sentinel_importer::{parse_guide, ProjectBuilder};
use sentinel_models::authoring::{ActionPayload, Faction};
use sentinel_queryclient::{MemoryQueryClient, QuestDetail, NpcDetail, WorldPos};

/// Look up a `Condition` action's expression string, if the payload is that variant.
fn condition_expression(payload: &ActionPayload) -> Option<&str> {
    match payload {
        ActionPayload::Condition(c) => Some(c.expression.as_str()),
        _ => None,
    }
}

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
    assert!(!project.npc_library.is_empty(), "should have at least one npc");
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
async fn goto_with_coordinates_populates_position() {
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
    let position = travel.position.expect("goto with numeric coords must populate position (IF1)");
    assert_eq!(position.world_x, 48.2);
    assert_eq!(position.world_y, 42.9);
}

#[tokio::test]
async fn goto_with_zone_name_only_leaves_position_none() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .goto Elwynn Forest
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let travel_action = project.operations[0].actions.iter().find(|a| matches!(a.payload, ActionPayload::Travel(_)));
    let travel = match &travel_action.expect("should have Travel action").payload {
        ActionPayload::Travel(t) => t,
        _ => panic!("not travel"),
    };
    assert_eq!(travel.destination, "Elwynn Forest");
    assert!(travel.position.is_none(), "zone-only goto has no numeric coords to populate position from");
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
    assert!((300..=450).contains(&steps), "got {} steps", steps);

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

    for (guide_file, min_level, _max_level) in guides {
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
        let _has_level_range = parsed.headers.iter()
            .any(|h| h.key == "name" && h.value.contains(&format!("{}-", min_level)));
        
        // Basic sanity check
        assert!(!project.operations.is_empty(), "{} should have at least one operation", guide_file);
    }

    // Summary output
    eprintln!("\n=== TBC Alliance Corpus Summary ===");
    eprintln!("Total guide steps parsed: {}", total_steps);
    eprintln!("Total diagnostics: {}", total_diagnostics);
    eprintln!("No hard failures - all guides parsed successfully");
}

#[tokio::test]
async fn well_formed_gating_commands_lower_to_typed_conditions() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .complete 1234,1
step
    .collect 159,10
step
    .itemcount 2139,1
step
    .isOnQuest 5624
step
    .isQuestComplete 1234
step
    .isQuestTurnedIn 5624
step
    .isQuestAvailable 42
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let expr = |op_idx: usize| {
        condition_expression(&project.operations[op_idx].actions[0].payload)
            .unwrap_or_else(|| panic!("operation {op_idx} should have a Condition action, not Comment"))
    };

    assert_eq!(expr(0), "Objective(1234,1)");
    assert_eq!(expr(1), "ItemCount(159,10)");
    assert_eq!(expr(2), "ItemCount(2139,1)");
    assert_eq!(expr(3), "QuestAccepted(5624)");
    assert_eq!(expr(4), "QuestCompleted(1234)");
    assert_eq!(expr(5), "QuestRewarded(5624)");
    assert_eq!(expr(6), "NOT QuestRewarded(42)");
}

#[tokio::test]
async fn itemcount_and_collect_support_comparison_operators_and_omitted_count() {
    // REL-1 fix: corpus-proven patterns the plain-u32 parse misclassified as malformed.
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .itemcount 2449,<5 --Earthroot (<5)
step
    .collect 19003
step
    .itemcount 100,>=3
step
    .itemcount 21377,>5
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let expr = |op_idx: usize| {
        condition_expression(&project.operations[op_idx].actions[0].payload)
            .unwrap_or_else(|| panic!("operation {op_idx} should have a Condition action, not Comment"))
    };

    // `.itemcount 2449,<5` (A-1-11-NightElf.lua:501) — count < 5 is NOT at-least-5.
    assert_eq!(expr(0), "NOT ItemCount(2449,5)");
    // `.collect 19003` (The Burning Crusade.lua:93674) — omitted count defaults to 1.
    assert_eq!(expr(1), "ItemCount(19003,1)");
    // Explicit `>=` form (generic RestedXP operator, not corpus-cited but same grammar).
    assert_eq!(expr(2), "ItemCount(100,3)");
    // `.itemcount 21377,>5` (The Burning Crusade.lua:23825) — count > 5 is at-least-6.
    assert_eq!(expr(3), "ItemCount(21377,6)");
}

#[tokio::test]
async fn gating_commands_tolerate_trailing_inline_dev_comments() {
    // REL-1: RestedXP lines commonly carry trailing `--` dev comments the lexer does not
    // strip (corpus-proven: 843/1391 `.complete <id>,<idx>` lines across six guides).
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .complete 1598,1 --Collect Powers of the Void (x1)
step
    .isQuestTurnedIn 418 -- Thelsamar Blood Sausages
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let expr = |op_idx: usize| {
        condition_expression(&project.operations[op_idx].actions[0].payload)
            .unwrap_or_else(|| panic!("operation {op_idx} should have a Condition action, not Comment"))
    };
    assert_eq!(expr(0), "Objective(1598,1)");
    assert_eq!(expr(1), "QuestRewarded(418)");
    assert!(
        !project.diagnostics.iter().any(|d| d.code == "MALFORMED_GATING_ARGS"),
        "trailing dev comments must not trigger a malformed diagnostic"
    );
}

#[tokio::test]
async fn goto_tolerates_trailing_inline_dev_comment() {
    // REL-2: same root cause hitting `.goto` coordinate parsing (IF1 MUST-populate clause).
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .goto Darnassus,55.239,23.996 -- Argent Guard Manados
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let travel = match &project.operations[0].actions[0].payload {
        ActionPayload::Travel(t) => t,
        _ => panic!("not travel"),
    };
    let position = travel.position.expect("goto with a trailing dev comment must still populate position");
    assert_eq!(position.world_x, 55.239);
    assert_eq!(position.world_y, 23.996);
}

#[tokio::test]
async fn multi_id_quest_gates_lower_to_any_of_the_predicates() {
    // Round-3 finding: RestedXP quest-gating commands commonly list multiple quest IDs read
    // as "any of these" — narrowing to only the first ID silently drops an OR-across-N gate.
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .isOnQuest 9699,9584,9643,9580,10063
step
    .isQuestTurnedIn 3789,3790,10520,3763
step
    .isQuestAvailable 9717,9719,9738
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let expr = |op_idx: usize| {
        condition_expression(&project.operations[op_idx].actions[0].payload)
            .unwrap_or_else(|| panic!("operation {op_idx} should have a Condition action, not Comment"))
    };

    // `.isOnQuest 9699,9584,9643,9580,10063` (A-11-23.lua:1426)
    assert_eq!(expr(0), "QuestAccepted(9699) || QuestAccepted(9584) || QuestAccepted(9643) || QuestAccepted(9580) || QuestAccepted(10063)");
    // `.isQuestTurnedIn 3789,3790,10520,3763` (The Burning Crusade.lua:22371)
    assert_eq!(expr(1), "QuestRewarded(3789) || QuestRewarded(3790) || QuestRewarded(10520) || QuestRewarded(3763)");
    // `.isQuestAvailable 9717,9719,9738` (The Burning Crusade.lua:6434)
    assert_eq!(expr(2), "NOT QuestRewarded(9717) || NOT QuestRewarded(9719) || NOT QuestRewarded(9738)");
}

#[tokio::test]
async fn itemcount_overflow_falls_back_to_malformed_diagnostic() {
    // REL-3: `>`/`<=` add 1 to the parsed count; must not panic at u32::MAX.
    let client = MemoryQueryClient::new();
    let guide = format!("\nRXPGuides.RegisterGuide([[\n#version 7\n#name Test\nstep\n    .itemcount 100,>{}\n]])", u32::MAX);
    let parsed = parse_guide(&guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    let action = &project.operations[0].actions[0];
    assert!(matches!(action.payload, ActionPayload::Comment(_)), "overflow falls back to inert Comment");
    assert!(
        project.diagnostics.iter().any(|d| d.code == "MALFORMED_GATING_ARGS"),
        "count overflow must carry a diagnostic, never a bare Comment"
    );
}

#[tokio::test]
async fn malformed_gating_command_becomes_typed_inert_action_with_diagnostic() {
    let client = MemoryQueryClient::new();
    let guide = r#"
RXPGuides.RegisterGuide([[
#version 7
#name Test
step
    .isQuestComplete notanumber
]])"#;
    let parsed = parse_guide(guide).expect("parse ok");
    let project = ProjectBuilder::build(&parsed, "test.lua", &client).await.expect("build ok");

    // Never a bare Comment with no diagnostic trail (IF2 malformed scenario).
    let action = &project.operations[0].actions[0];
    assert!(matches!(action.payload, ActionPayload::Comment(_)), "malformed args fall back to inert Comment");
    assert!(
        project.diagnostics.iter().any(|d| d.code == "MALFORMED_GATING_ARGS"),
        "malformed gating args must carry a diagnostic, never a bare Comment"
    );
}