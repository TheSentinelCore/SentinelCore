//! ADR 07 §7.3.3's printed listing **is** the fixture — pinned, so the two can never drift again.
//!
//! # Why this file exists
//!
//! `sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md` §7.3.3 prints a worked-example artifact, and
//! `shared/tests/fixtures/adr07_worked_example.json` is the same artifact as a loadable file. Two
//! copies of one value in two languages is a drift generator, and it drifted: this test's first run
//! reported **136 differing leaf paths** between them — eight tasks against seven, every waypoint
//! reference shifted, all 22 pool entries still carrying authored zone percentages under ui map `1439`,
//! a `#displayname` where `#name` belongs, an unsorted ten-tag census against a sorted nine-tag one,
//! and `mode: "Ground"` where `.goto` lowers to `Any`. Every one of those was the *document* being
//! wrong; the fixture is derived from the corpus and driven end to end by the real lowering
//! (`compiler/tests/kernel_worked_example.rs`).
//!
//! Hand-patching 182 values is how the 183rd appears. So §7.3.3's listing is now **generated from
//! the fixture** and this file is the guard: the ADR fence must parse, load into the model, and
//! compare equal to the fixture. Editing either side alone fails here.
//!
//! # The three claims, in the order a failure should be read
//!
//! 1. **The listing is loadable** — [`the_adr_listing_loads_into_the_kernel_model`]. §9 item 22
//!    claims §7.3.3 "was not a loadable artifact as printed — resolved", and for two revisions that
//!    claim was false in two ways at once: the two digests were printed as prose
//!    (`"<blake3-of-tagset>"`, 20 and 25 characters against §7.2's `^[0-9a-f]{64}$`), and seven
//!    `_comment` keys survived against a `deny_unknown_fields` root. Prose that says "a real
//!    artifact carries none of them" does not make a listing loadable; refusing to print them does.
//! 2. **No `_comment` key survives** — [`the_adr_listing_carries_no_comment_keys`]. Checked
//!    separately from (1) even though `deny_unknown_fields` would also catch it, because the failure
//!    message differs by an order of magnitude in usefulness: serde reports one line and column,
//!    this reports the count and the remedy (put the prose in the table above the fence).
//! 3. **It equals the fixture** — [`the_adr_listing_equals_the_worked_example_fixture`]. Field for
//!    field, by leaf path, count first.
//!
//! # What this file cannot see
//!
//! * **Whether the fixture is right.** Same blind spot as `kernel_worked_example.rs`: this pins
//!   agreement between a document and a file, not between either and the game. §7.3.2's database
//!   check and `kernel_worked_example.rs`'s end-to-end lowering are what stand behind the fixture.
//!   If both sides are wrong in the same direction this test is green.
//! * **The prose around the fence.** Task counts, pool descriptions and index claims written in
//!   English next to the listing are unchecked. A regeneration that leaves the surrounding paragraph
//!   describing eight tasks passes here.
//! * **Any other listing in the ADR.** Only §7.3.3's fence is extracted. §7.1's Rust and §7.2's JSON
//!   Schema are prose to this file.

use sentinel_models::kernel::RuntimeProfile;
use serde_json::Value;

/// Repo-relative paths, quoted in every failure message so the next reader can open both sides.
const ADR_PATH: &str = "sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md";
const FIXTURE_PATH: &str = "SentinelQuesting/shared/tests/fixtures/adr07_worked_example.json";

const ADR: &str = include_str!("../../../sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md");
const FIXTURE: &str = include_str!("fixtures/adr07_worked_example.json");

/// The section heading the listing lives under. An **anchor**, not a line number: the ADR is edited
/// constantly and `SentinelQuesting/tools/check_citation_anchors.py` refuses line-number citations
/// into living files.
const SECTION: &str = "### 7.3.3 Compiled output";

/// How the listing is fenced. The first fence of this kind after [`SECTION`] is the artifact; §7.3.3
/// contains no other.
const FENCE_OPEN: &str = "```json";
const FENCE_CLOSE: &str = "\n```";

/// The remedy, printed on every failure. One sentence, because a reader who reaches it is about to
/// choose between editing the document and editing the fixture, and only one of those is right.
const REMEDY: &str = "§7.3.3's listing is GENERATED FROM THE FIXTURE. Regenerate it from \
                      the fixture rather than editing the ADR by hand — and if the fixture is what \
                      changed, `compiler/tests/kernel_worked_example.rs` is the test that decides \
                      whether the change was legitimate.";

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Extraction
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// The raw text between §7.3.3's `json` fence markers.
///
/// Panics with the anchor it was looking for rather than returning `None`: a missing section or
/// fence means the ADR was restructured, and silently skipping the comparison is exactly the
/// outcome this file exists to prevent.
fn adr_listing() -> &'static str {
    let section = ADR.find(SECTION).unwrap_or_else(|| {
        panic!(
            "ADR 07 no longer contains the anchor {SECTION:?}.\n  \
             adr: {ADR_PATH}\n  \
             This test locates the worked-example listing by heading text, never by line number. \
             If the section was renamed, update `SECTION` here in the same commit — do not delete \
             the check.\n  {REMEDY}"
        )
    });
    let after_section = &ADR[section..];
    let open = after_section.find(FENCE_OPEN).unwrap_or_else(|| {
        panic!(
            "found {SECTION:?} but no {FENCE_OPEN:?} fence after it.\n  adr: {ADR_PATH}\n  \
             The compiled output must stay a fenced `json` block: it is the only form this test — \
             and a reader pasting it into a loader — can extract.\n  {REMEDY}"
        )
    });
    let body_start = section + open + FENCE_OPEN.len();
    let close = ADR[body_start..].find(FENCE_CLOSE).unwrap_or_else(|| {
        panic!(
            "§7.3.3's {FENCE_OPEN:?} fence is never closed.\n  adr: {ADR_PATH}\n  {REMEDY}"
        )
    });
    &ADR[body_start..body_start + close]
}

/// Parses the extracted fence, or panics with serde's position **translated into the fence's own
/// coordinates** plus the offending line.
///
/// Serde reports a position relative to the string it was handed, which here is the fence body — so
/// a bare `expected value at <line> <column>` would send the reader counting lines from the top of a
/// 2,400-line markdown file and landing in the wrong place. Saying which coordinates the numbers are
/// in, and printing the offending line, is the difference between a usable failure and a hunt.
fn parse_listing(listing: &str) -> Value {
    match serde_json::from_str::<Value>(listing) {
        Ok(value) => value,
        Err(error) => {
            let line = error.line();
            let excerpt = listing.lines().nth(line.saturating_sub(1)).unwrap_or("<past end>");
            panic!(
                "ADR 07 §7.3.3's listing is not valid JSON, so it is not an artifact anything \
                 could load.\n  \
                 adr      : {ADR_PATH}\n  \
                 position : line {line}, column {} — counted from the `{FENCE_OPEN}` line\n  \
                 that line: {excerpt}\n  \
                 serde    : {error}\n  {REMEDY}",
                error.column()
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// 1 — loadable
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// §7.3.3's listing must deserialize into [`RuntimeProfile`], not merely be valid JSON.
///
/// This is the check that makes §9 item 22's "resolved" true rather than aspirational, and it covers
/// three separate ways the listing has actually failed:
///
/// * **Prose digests.** `schema_hash` and `integrity.content_hash` are `[u8; 32]` behind a hex codec,
///   so `"<blake3-of-tagset>"` is refused here exactly as §7.2's `^[0-9a-f]{64}$` refuses it.
/// * **Unknown keys.** The root and every kernel struct are `deny_unknown_fields` per C4 (§5.4), so
///   a `_comment` — or any field the model does not declare — refuses to load.
/// * **Missing required fields.** §7.2's root `required` array is exhaustive; the listing once
///   printed neither `defaults` nor `waypoint_pool` (§9 item 22).
#[test]
fn the_adr_listing_loads_into_the_kernel_model() {
    let listing = adr_listing();
    if let Err(error) = serde_json::from_str::<RuntimeProfile>(listing) {
        // Re-parse as `Value` first: if *that* fails the message is about syntax, which is a
        // different and more basic problem than a model mismatch.
        let _ = parse_listing(listing);
        let line = error.line();
        let excerpt = listing.lines().nth(line.saturating_sub(1)).unwrap_or("<past end>");
        panic!(
            "ADR 07 §7.3.3's listing is valid JSON but does not load into \
             `sentinel_models::kernel::RuntimeProfile`, so it is not a kernel artifact.\n  \
             adr      : {ADR_PATH}\n  \
             position : line {line}, column {} — counted from the `{FENCE_OPEN}` line\n  \
             that line: {excerpt}\n  \
             serde    : {error}\n  \
             C4 (§5.4) makes every kernel struct `deny_unknown_fields` and both digests \
             `^[0-9a-f]{{64}}$`. A listing that cannot load is a specification nothing can be \
             checked against.\n  {REMEDY}",
            error.column()
        );
    }
}

/// The listing must carry no `_comment` key at all.
///
/// §7.3.3 used seven of them to annotate tasks, guarded only by a sentence saying a real artifact
/// carries none. That sentence is not a mechanism: the printed listing was the thing readers copy,
/// and it could not load. Per-task prose now lives in a table **above** the fence, where it costs
/// the artifact nothing.
#[test]
fn the_adr_listing_carries_no_comment_keys() {
    let listing = adr_listing();
    let count = listing.matches("\"_comment\"").count();
    assert_eq!(
        count, 0,
        "ADR 07 §7.3.3's listing carries {count} `_comment` key(s).\n  \
         adr: {ADR_PATH}\n  \
         `RuntimeProfile` is `#[serde(deny_unknown_fields)]` (C4, §5.4), so a listing with even one \
         of them cannot load — which makes it a worked example of nothing. Put the prose in the \
         per-task table above the fence instead.\n  {REMEDY}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// 2 — identical to the fixture
// ─────────────────────────────────────────────────────────────────────────────────────────────

/// §7.3.3's listing and the fixture must be the same artifact, field for field.
///
/// # Why by parsed `Value` and not by bytes
///
/// A byte comparison would fail on whitespace and on JSON number rendering — the fixture is
/// hand-formatted and writes `6378.9443`, which round-trips through `f32` to the same value but not
/// necessarily to the same string. Comparing parsed values pins the *artifact*, which is what a
/// loader sees, and leaves the ADR free to indent for a reader.
///
/// # Why leaf paths and not a `assert_eq!` on the two values
///
/// `assert_eq!` on two 300-line values prints both in full and leaves the reader diffing them by
/// eye. The report below names each differing path with both sides, and prints the **count first**
/// so a structural divergence (a task added or removed, which invalidates every index after it) is
/// read before the detail it invalidates.
#[test]
fn the_adr_listing_equals_the_worked_example_fixture() {
    let listing = parse_listing(adr_listing());
    let fixture: Value = serde_json::from_str(FIXTURE)
        .unwrap_or_else(|error| panic!("the fixture must be valid JSON, got: {error}"));

    let mut differences = Vec::new();
    diff_leaves(&listing, &fixture, &mut String::new(), &mut differences);
    if differences.is_empty() {
        return;
    }

    let mut report = format!(
        "ADR 07 §7.3.3's listing and the worked-example fixture disagree on \
         {} leaf path(s).\n  \
         adr    : {ADR_PATH}  (§7.3.3, anchor {SECTION:?})\n  \
         fixture: {FIXTURE_PATH}\n\n\
         The fixture is the specification: it is derived from the corpus, its ids are verified \
         against `tbcmangos.sqlite` (§7.3.2), and `compiler/tests/kernel_worked_example.rs` drives \
         the real lowering into it. The ADR listing is what moves.\n\n",
        differences.len()
    );
    // Structural divergence first: a differing array length renumbers everything after it, so every
    // path below such a difference is comparing unrelated things.
    for (path, adr_side, fixture_side) in &differences {
        if path.ends_with("[len]") {
            report.push_str(&format!(
                "  STRUCTURE {path}\n    adr    : {adr_side}\n    fixture: {fixture_side}\n"
            ));
        }
    }
    for (path, adr_side, fixture_side) in &differences {
        if !path.ends_with("[len]") {
            report.push_str(&format!(
                "  {path}\n    adr    : {adr_side}\n    fixture: {fixture_side}\n"
            ));
        }
    }
    report.push_str(&format!("\n  {REMEDY}"));
    panic!("{report}");
}

/// Absent on one side. A string, so it reads as a value in the report rather than as JSON `null` —
/// which is a real value both sides can legitimately hold.
const MISSING: &str = "<key absent>";

/// Walks both values in lockstep, recording every leaf path where they disagree.
///
/// Array length is reported as its own `[len]` pseudo-path before the elements, so a count
/// divergence is visible as a count rather than only as a wall of per-index differences.
fn diff_leaves(
    adr: &Value,
    fixture: &Value,
    path: &mut String,
    out: &mut Vec<(String, String, String)>,
) {
    match (adr, fixture) {
        (Value::Object(left), Value::Object(right)) => {
            let mut keys: Vec<&String> = left.keys().chain(right.keys()).collect();
            keys.sort();
            keys.dedup();
            for key in keys {
                let restore = path.len();
                path.push('.');
                path.push_str(key);
                match (left.get(key), right.get(key)) {
                    (Some(a), Some(b)) => diff_leaves(a, b, path, out),
                    (Some(a), None) => out.push((path.clone(), render(a), MISSING.to_string())),
                    (None, Some(b)) => out.push((path.clone(), MISSING.to_string(), render(b))),
                    (None, None) => unreachable!("key came from one of the two maps"),
                }
                path.truncate(restore);
            }
        }
        (Value::Array(left), Value::Array(right)) => {
            if left.len() != right.len() {
                out.push((
                    format!("{path}[len]"),
                    format!("{} element(s)", left.len()),
                    format!("{} element(s)", right.len()),
                ));
            }
            for index in 0..left.len().max(right.len()) {
                let restore = path.len();
                path.push_str(&format!("[{index}]"));
                match (left.get(index), right.get(index)) {
                    (Some(a), Some(b)) => diff_leaves(a, b, path, out),
                    (Some(a), None) => out.push((path.clone(), render(a), MISSING.to_string())),
                    (None, Some(b)) => out.push((path.clone(), MISSING.to_string(), render(b))),
                    (None, None) => unreachable!("index is below the longer length"),
                }
                path.truncate(restore);
            }
        }
        (left, right) if left != right => {
            out.push((path.clone(), render(left), render(right)))
        }
        _ => {}
    }
}

/// One-line rendering, truncated: a differing subtree is a pointer to where to look, not the place
/// to read the whole value.
fn render(value: &Value) -> String {
    let text = value.to_string();
    if text.chars().count() <= 90 {
        return text;
    }
    let head: String = text.chars().take(87).collect();
    format!("{head}...")
}
