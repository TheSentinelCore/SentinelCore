//! Integration tests for the Wave 1 core parser.

use sentinel_importer::{parse_guide, parse_guide_bundle, ImportError, GuideSplitter};
use sentinel_queryclient::MemoryQueryClient;

const BASIC: &str = include_str!("fixtures/guide_basic.lua");
const DANGLING: &str = include_str!("fixtures/guide_dangling.lua");
const BUNDLE_SLICE: &str = include_str!("fixtures/guide_bundle_tbc_slice.lua");

#[test]
fn extracts_body_and_splits_headers_from_steps() {
    let split = GuideSplitter::split(BASIC).expect("split ok");
    // Headers: #version, #group, << Alliance, #name, #defaultfor  (5 lines before first step)
    assert_eq!(split.headers.len(), 5);
    // Body lines begin at the first `step` marker.
    assert!(split.body_lines.iter().any(|l| l.text.trim_start().starts_with("step")));
    // Source mapping: the body's first line is the line after `RegisterGuide([[`.
    assert!(split.body_lines[0].line_no >= 3);
}

#[test]
fn parses_basic_guide_structure() {
    let guide = parse_guide(BASIC).expect("parse ok");

    // Headers
    let name = guide.headers.iter().find(|h| h.key == "name").expect("name header");
    assert_eq!(name.value, "1-5 Test Zone");
    let faction = guide.headers.iter().find(|h| h.key == "faction").expect("faction header");
    assert_eq!(faction.value, "Alliance");

    // 3 steps
    assert_eq!(guide.steps.len(), 3);

    // Step 0: condition !Human, only text
    assert_eq!(guide.steps[0].conditions, vec!["!Human".to_string()]);
    assert!(guide.steps[0].text.iter().any(|t| t.contains("meant for Humans")));
    assert!(guide.steps[0].commands.is_empty());

    // Step 1: .accept 1598 with note, .target, #label TOME
    let accept = guide.steps[1]
        .commands
        .iter()
        .find(|c| c.name == "accept")
        .expect("accept command");
    assert_eq!(accept.args, vec!["1598".to_string()]);
    assert!(accept.note.as_ref().unwrap().contains("Accept The Stolen Tome"));
    let target = guide.steps[1]
        .commands
        .iter()
        .find(|c| c.name == "target")
        .expect("target command");
    assert_eq!(target.args, vec!["Dane Winslow".to_string()]);
    let label = guide.steps[1]
        .directives
        .iter()
        .find(|d| d.name == "label")
        .expect("label directive");
    assert_eq!(label.value.as_deref(), Some("TOME"));

    // Step 2: condition Warlock, #completewith TOME, .goto with comma args
    assert_eq!(guide.steps[2].conditions, vec!["Warlock".to_string()]);
    let cw = guide.steps[2]
        .directives
        .iter()
        .find(|d| d.name == "completewith")
        .expect("completewith directive");
    assert_eq!(cw.value.as_deref(), Some("TOME"));
    let goto = guide.steps[2]
        .commands
        .iter()
        .find(|c| c.name == "goto")
        .expect("goto command");
    assert_eq!(
        goto.args,
        vec!["Elwynn Forest".to_string(), "48.2".to_string(), "42.9".to_string()]
    );

    // Label graph: TOME defined and referenced, nothing unresolved.
    assert_eq!(guide.labels.definitions.get("TOME"), Some(&1));
    assert_eq!(guide.labels.references.len(), 1);
    assert!(guide.labels.unresolved.is_empty());
}

#[test]
fn resolves_class_list_conditions() {
    let src = "RXPGuides.RegisterGuide([[\n#name x\nstep << Priest/Mage/Warlock\n.accept 1\n]])";
    let guide = parse_guide(src).expect("parse ok");
    assert_eq!(
        guide.steps[0].conditions,
        vec!["Priest".to_string(), "Mage".to_string(), "Warlock".to_string()]
    );
}

#[test]
fn surfaces_unresolved_label_as_diagnostic_not_error() {
    let guide = parse_guide(DANGLING).expect("parse does not hard-fail on dangling label");
    assert_eq!(guide.steps.len(), 1);
    assert_eq!(guide.labels.unresolved.len(), 1);
    assert_eq!(guide.labels.unresolved[0].label, "NOPE");
}

#[test]
fn reports_extraction_errors() {
    assert_eq!(parse_guide("no guide here"), Err(ImportError::NoGuideBlock));
    assert_eq!(
        parse_guide("RXPGuides.RegisterGuide([[unterminated"),
        Err(ImportError::UnterminatedGuideBlock)
    );
}

#[test]
fn reserved_next_keyword_is_not_a_label() {
    let src = "RXPGuides.RegisterGuide([[\n#name x\nstep\n.completewith next\n.accept 1\n]])";
    let guide = parse_guide(src).expect("parse ok");
    assert!(guide.labels.references.is_empty(), "next must be skipped");
}

#[test]
fn command_line_class_suffix_is_parsed_into_class_restriction() {
    // IF3: `.collect 7972,1 << Warrior` (corpus-proven form, no note).
    let src = "RXPGuides.RegisterGuide([[\n#name x\nstep\n.collect 7972,1 << Warrior\n]])";
    let guide = parse_guide(src).expect("parse ok");
    let collect = guide.steps[0].commands.iter().find(|c| c.name == "collect").expect("collect");
    assert_eq!(collect.args, vec!["7972".to_string(), "1".to_string()]);
    assert_eq!(collect.class_restriction.as_deref(), Some("Warrior"));
}

#[tokio::test]
async fn multi_registerguide_bundle_yields_one_project_per_guide() {
    // IF6 end-to-end: real 2-block excerpt from The Burning Crusade.lua (253 blocks in the full
    // file) must split into N `ParsedGuide`s AND, once fed through `ProjectBuilder` (PR1b-iii
    // wiring), N `Project`s — one per guide, not one per file.
    let results = parse_guide_bundle(BUNDLE_SLICE);
    assert_eq!(results.len(), 2, "bundle has 2 RegisterGuide blocks");
    let guides: Vec<_> = results.into_iter().map(|r| r.expect("each block parses")).collect();
    let name_of = |g: &sentinel_importer::ParsedGuide| {
        g.headers.iter().find(|h| h.key == "name").map(|h| h.value.clone())
    };
    assert_eq!(name_of(&guides[0]), Some("Prep-Silithus Start".to_string()));
    assert_eq!(name_of(&guides[1]), Some("DM East".to_string()));
    assert!(guides[0].steps.iter().any(|s| s.commands.iter().any(|c| c.name == "fp")));
    assert!(guides[1].steps.iter().any(|s| s.commands.iter().any(|c| c.name == "collect")));

    let client = MemoryQueryClient::new();
    let mut projects = Vec::new();
    for guide in &guides {
        projects.push(
            sentinel_importer::ProjectBuilder::build(guide, "bundle.lua", &client)
                .await
                .expect("builds"),
        );
    }
    assert_eq!(projects.len(), 2, "one Project per guide, not one per file (IF6)");
    assert_eq!(projects[0].metadata.name, "Prep-Silithus Start");
    assert_eq!(projects[1].metadata.name, "DM East");
}

#[tokio::test]
async fn fp_without_target_resolves_flight_master_from_step_name_hints() {
    // Corpus measurement of The Burning Crusade.lua (253 guides, 86,073 commands) showed `.fp`
    // producing 135 unresolved actions — 26% of ALL 514 unresolved commands — because, unlike its
    // siblings `.vendor`/`.train`, it only consulted a preceding `.target` and had no
    // `resolve_npc_with_hints` fallback to the step's |cRXP_FRIENDLY_...|r name hints.
    const GUIDE: &str = r#"RXPGuides.RegisterGuide([[
#version 1
#name FP Hint Test
step
    .fp >> Get the flight path from |cRXP_FRIENDLY_Thalia Amberhide|r
]])"#;

    let guide = parse_guide(GUIDE).expect("parses");
    let client = MemoryQueryClient::new().with_npc(sentinel_queryclient::NpcDetail {
        entry: 4321,
        name: "Thalia Amberhide".to_string(),
        faction: "Alliance".to_string(),
        positions: vec![],
        roles: vec![],
    });
    let project = sentinel_importer::ProjectBuilder::build(&guide, "fp.lua", &client)
        .await
        .expect("builds");

    let typed_fp = project
        .operations
        .iter()
        .flat_map(|o| &o.actions)
        .any(|a| matches!(a.payload, sentinel_models::authoring::ActionPayload::LearnFlightPath(_)));
    assert!(
        typed_fp,
        ".fp must resolve its flight master from the step's NPC name hints when no .target precedes it"
    );
}

#[tokio::test]
async fn train_preserves_the_spell_ids_from_its_args() {
    // `.train <spell_id>[,rank]` names the SPELL to train, not an NPC — only 1 of the 1,383
    // `.train` lines in The Burning Crusade.lua carries an NPC hint. The importer was discarding
    // `cmd.args` entirely, so every `.train` (including the 1,157 that resolved an NPC and counted
    // as "typed") lost what to actually train. Preserve the spell IDs.
    const GUIDE: &str = r#"RXPGuides.RegisterGuide([[
#version 1
#name Train Spell Test
step
    .target Rogo Waterspout
    .train 48792,1 >> Train the spell
]])"#;

    let guide = parse_guide(GUIDE).expect("parses");
    let client = MemoryQueryClient::new().with_npc(sentinel_queryclient::NpcDetail {
        entry: 777,
        name: "Rogo Waterspout".to_string(),
        faction: "Alliance".to_string(),
        positions: vec![],
        roles: vec![],
    });
    let project = sentinel_importer::ProjectBuilder::build(&guide, "train.lua", &client)
        .await
        .expect("builds");

    let spells: Vec<u32> = project
        .operations
        .iter()
        .flat_map(|o| &o.actions)
        .filter_map(|a| match &a.payload {
            sentinel_models::authoring::ActionPayload::Train(t) => Some(t.spells.clone()),
            _ => None,
        })
        .flatten()
        .collect();
    assert_eq!(
        spells,
        vec![48792],
        ".train must preserve its spell id (rank suffix is not a second spell)"
    );
}

#[tokio::test]
async fn mob_resolves_creature_names_to_entries() {
    // `.mob` is name-based in 6,585 of its corpus uses (e.g. `.mob Young Wolf`). The importer only
    // parsed numeric args, so EVERY name-based .mob produced an empty creature_entries list and a
    // Kill action the runtime could never satisfy — measured 53 of 53 empty in the Elwynn profile.
    const GUIDE: &str = r#"RXPGuides.RegisterGuide([[
#version 1
#name Mob Name Test
step
    .mob Young Wolf
    .mob 69
]])"#;

    let guide = parse_guide(GUIDE).expect("parses");
    let client = MemoryQueryClient::new().with_npc(sentinel_queryclient::NpcDetail {
        entry: 299,
        name: "Young Wolf".to_string(),
        faction: "Beast".to_string(),
        positions: vec![],
        roles: vec![],
    });
    let project = sentinel_importer::ProjectBuilder::build(&guide, "mob.lua", &client)
        .await
        .expect("builds");

    let kills: Vec<Vec<u32>> = project
        .operations
        .iter()
        .flat_map(|o| &o.actions)
        .filter_map(|a| match &a.payload {
            sentinel_models::authoring::ActionPayload::Kill(k) => Some(k.creature_entries.clone()),
            _ => None,
        })
        .collect();

    assert_eq!(kills.len(), 2, "both .mob commands lower to Kill actions");
    assert_eq!(kills[0], vec![299], "a named .mob must resolve to its creature entry");
    assert_eq!(kills[1], vec![69], "a numeric .mob keeps working unchanged");
}

#[test]
fn standalone_and_bundled_parse_are_invariant_modulo_line_offset() {
    // The same guide text, parsed standalone vs. embedded as the second block of a bundle, must
    // produce identical structure — only line numbers should differ by a constant, non-zero
    // offset once bundled (PR1b-iii line-offset fix).
    let guide_src = "RXPGuides.RegisterGuide([[\n#name Solo\nstep\n.accept 42\n]]);";
    let standalone = parse_guide(guide_src).expect("standalone parses");

    let bundle_src = format!(
        "-- leading comment\nRXPGuides.RegisterGuide([[\n#name Leader\nstep\n.accept 1\n]]);\n{guide_src}"
    );
    let bundled = parse_guide_bundle(&bundle_src);
    assert_eq!(bundled.len(), 2);
    let second = bundled[1].as_ref().expect("second block parses");

    assert_eq!(
        second.headers.iter().find(|h| h.key == "name").map(|h| &h.value),
        standalone.headers.iter().find(|h| h.key == "name").map(|h| &h.value),
    );
    assert_eq!(second.steps.len(), standalone.steps.len());
    assert_eq!(second.steps[0].commands[0].name, standalone.steps[0].commands[0].name);

    let solo_accept_line = standalone.steps[0].commands[0].line;
    let bundled_accept_line = second.steps[0].commands[0].line;
    assert!(
        bundled_accept_line > solo_accept_line,
        "bundled block's lines must be file-absolute (shifted), not restarted at the block's own line 1"
    );
}

#[test]
fn parses_real_restedxp_guide_when_present() {
    // Path relative to this crate root (sentinel-questing/importer).
    let path = "../../../sentinel/docs/adr/restedxp guides/A-1-11-Human.lua";
    let Ok(src) = std::fs::read_to_string(path) else {
        eprintln!("skipping real-guide test: fixture not found at {path}");
        return;
    };
    let guide = parse_guide(&src).expect("real guide parses");
    // The guide has 421 `step` markers.
    assert_eq!(guide.steps.len(), 421);
    // A known label is defined.
    assert!(guide.labels.definitions.contains_key("ATW"));
    // `next` is reserved and must not appear as an unresolved reference.
    assert!(!guide.labels.unresolved.iter().any(|u| u.label == "next"));
    // `TheBinding` is a genuine dangling reference in this guide.
    assert!(guide.labels.unresolved.iter().any(|u| u.label == "TheBinding"));
}
