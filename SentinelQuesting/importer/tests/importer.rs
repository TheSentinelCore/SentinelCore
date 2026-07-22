//! Integration tests for the Wave 1 core parser.

use sentinel_importer::{parse_guide, ImportError, GuideSplitter};

const BASIC: &str = include_str!("fixtures/guide_basic.lua");
const DANGLING: &str = include_str!("fixtures/guide_dangling.lua");

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
