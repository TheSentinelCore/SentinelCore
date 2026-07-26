//! Coordinate normalisation, **through the pipeline that actually compiles a guide**
//! (ADR `07_RUNTIME_PROFILE_SCHEMA` §2.6, §5.7, §6.4, §7.1).
//!
//! # Why this file exists at all
//!
//! These tests were written against `kernel::parse_movement`, a second, complete implementation of
//! the coordinate transform that **no compile ever called**. The live path is
//! `sentinel_importer::ProjectBuilder` → `project_builder.rs::build_travel_position` →
//! `TravelAction::position` → `kernel::task_graph::flush_route`, and `build_travel_position`
//! implemented none of the `/` discrimination: it handed field 0 straight to
//! `zone::zone_map_for`, so every `1439/1` line matched nothing, was dropped with an
//! `UNMAPPED_GOTO_ZONE` diagnostic, and **929 corpus lines never reached an artifact**. Twelve
//! tests passed the whole time, over a function nothing ran.
//!
//! There is now one transform — `sentinel_models::movement::resolve_coordinate` — and one caller of
//! it. Every test below drives `parse_guide` → `ProjectBuilder::build` → `Compiler::compile_kernel`
//! and asserts on the artifact, so a transform that stops being called stops being tested.
//!
//! Every test quotes the verbatim guide line it lowers, with its file and line number, so the
//! expected value can be re-derived from the corpus rather than trusted.
//!
//! # What these tests prove
//!
//! * **Coordinates normalise, they do not pass through.** RestedXP authors two coordinate systems
//!   and they are not interchangeable. `zone,x,y` carries *zone-relative percentages* (0..100);
//!   `<uiMapId>/<continentMapId>,x,y` carries *raw world* coordinates already in the server's frame.
//!   The discriminator is the `/` in field 0 and nothing else.
//! * **Prose is stripped, not parsed.** Both `>>` display text and `--` dev comments reach the
//!   lexer, and 38 corpus movement lines carry a `--`. Neither marker may reach a parsed field.
//! * **A malformed line is refused, never repaired.** The 67 six-argument `.goto` lines in the
//!   corpus are three different defects, and every plausible "repair" corrupts the other two.
//!
//! # What these tests cannot see
//!
//! * **The zone→world transform's correctness.** The expected world coordinates are computed from
//!   the measured bounds table in `shared/src/zone.rs` (`ZONE_TABLE` — sampled from a live client
//!   via `core.game_ui.get_world_pos_from_map_pos` and verified against a known DB spawn to within
//!   0.1 yd). If that table is wrong, these tests are wrong with it in exactly the same direction.
//!   They pin *that the compiler uses the measured transform*, not that the measurement is true.
//!   `assert_close`'s tolerance is 0.1 yd for the same reason.
//! * **Whether `radius: 0` means "zero yards" or "engine default".** Several of the corpus lines
//!   below authored a fourth argument of `0`; the artifact carries what was authored and this file
//!   asserts only that.
//! * **`TravelMode::Ground` / `TravelMode::Air` reaching an artifact.** Almost every line cited
//!   below is `.goto` or `.waypoint`, i.e. `TravelMode::Any`. The media are owned by
//!   `kernel_route_aggregation.rs` and `importer/tests/movement_fidelity_and_provenance.rs`.
//! * **The route-level collapse of §2.6 / §5.7 / §8** (a source step emitting the same coordinate
//!   twice as both a 4-arg and a 5-arg line). That is a separate, later deliverable.
//! * **Whether a whole guide survives a malformed line.** The arity refusal below is a *line*
//!   refusal: the coordinate is dropped and named, the step and the guide live on. Measured, 5 of
//!   the corpus's 277 guide blocks carry one of the 67 six-argument lines, and refusing the block
//!   would delete 5 whole guides to punish 67 lines.

use sentinel_compiler::kernel::QuestMeta;
use sentinel_compiler::{CompileReport, Compiler};
use sentinel_models::authoring::{ActionPayload, Class, Faction, Project, Race, Severity};
use sentinel_models::kernel::{
    Archetype, Expansion, Op, Point, ProfileMode, QuestId, Route, RuntimeProfile as KernelProfile,
    TravelMode,
};
use sentinel_queryclient::MemoryQueryClient;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Harness — the same three calls a real compile makes
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Kalimdor. `.goto 1439,…` names *ui map* 1439 (Darkshore); the artifact carries the **continent**
/// the navmesh and the server use, which for Darkshore is `1`. Conflating the two is the bug this
/// discriminates against — a `Point` whose `map_id` is 1439 is a percentage that survived
/// compilation wearing a map id.
const KALIMDOR: u32 = 1;
/// Eastern Kingdoms — the continent Wetlands (ui map 1437) resolves to.
const EASTERN_KINGDOMS: u32 = 0;
/// Outland — the continent `1944/530` and `1948/530` name directly.
const OUTLAND: u32 = 530;

/// Measured-transform tolerance, in yards. See the module header: `ZONE_TABLE` is documented as
/// accurate to 0.1 yd against a known DB spawn, so nothing tighter is meaningful.
const YARD_TOLERANCE: f32 = 0.1;

struct AnswersOne;

impl QuestMeta for AnswersOne {
    fn objective_need(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        Some(1)
    }

    /// No fragment here works an item objective, so no task needs a loot rule. `None` is "not an
    /// item", never "could not answer" — see the trait's own doc comment.
    fn objective_item(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        None
    }
}

/// The Night Elf Hunter of §7.3.3, spelled out in full: every field is a gate axis and a defaulted
/// one is a gate nobody chose.
fn night_elf_hunter() -> Archetype {
    Archetype {
        class: Class::Hunter,
        race: Race::NightElf,
        faction: Faction::Alliance,
        expansion: Expansion::Tbc,
        allegiance: None,
        hardcore: false,
        self_found: false,
        can_fly: false,
        content_phase: None,
        mode: ProfileMode::SpeedRoute,
        xp_rate_milli: 1_000,
        hardcore_server: false,
        season: None,
    }
}

/// Wrap movement lines in the smallest guide that carries them: one step per line, each closed by
/// the same completion predicate so the step survives task elision.
fn guide(steps: &[&str]) -> String {
    let mut out = String::from("RXPGuides.RegisterGuide([[\n#name 10-14 Darkshore\n");
    for step in steps {
        out.push_str("step\n");
        out.push_str("    ");
        out.push_str(step);
        out.push('\n');
        out.push_str("    .complete 983,1\n");
    }
    out.push_str("]])");
    out
}

async fn import(source: &str) -> Project {
    let parsed = sentinel_importer::parse_guide(source)
        .unwrap_or_else(|err| panic!("the fragment must parse, got: {err:?}"));
    sentinel_importer::ProjectBuilder::build(&parsed, "A-11-23.lua", &MemoryQueryClient::new())
        .await
        .unwrap_or_else(|err| panic!("the fragment must build into a Project, got: {err:?}"))
}

async fn lower(source: &str) -> (KernelProfile, CompileReport) {
    let project = import(source).await;
    Compiler::compile_kernel(&project, &night_elf_hunter(), &AnswersOne)
        .unwrap_or_else(|err| panic!("`compile_kernel` must not refuse the fragment, got: {err:?}"))
}

/// Compile one movement line and return the single point and the single route it produced.
async fn lowered(line: &str) -> (Point, Route) {
    let (profile, _report) = lower(&guide(&[line])).await;
    let routes: Vec<&Route> = profile
        .tasks
        .iter()
        .flat_map(|task| &task.ops)
        .filter_map(|op| match op {
            Op::Travel { route } => Some(route),
            _ => None,
        })
        .collect();
    let [route] = routes.as_slice() else {
        panic!("`{line}` must lower to exactly one `Op::Travel`, got {routes:?}")
    };
    let [point] = profile.waypoint_pool.as_slice() else {
        panic!(
            "`{line}` must intern exactly one waypoint, got {:?}",
            profile.waypoint_pool
        )
    };
    (*point, (*route).clone())
}

fn assert_close(actual: f32, expected: f32, what: &str) {
    assert!(
        (actual - expected).abs() <= YARD_TOLERANCE,
        "{what}: expected {expected} (±{YARD_TOLERANCE} yd, re-derived from ZONE_TABLE), \
         got: {actual:?} — a difference of {} yd",
        (actual - expected).abs()
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The waypoint pool: normalisation
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn a_zone_percentage_goto_normalises_to_measured_world_coordinates() {
    // A-11-23.lua:205 — `.goto Darkshore,40.77,78.56,40,0`
    //
    // Darkshore's measured bounds (ZONE_TABLE, continent 1):
    //   top 8333.333, left 2941.6665, bottom 3966.6665, right -3608.3333
    // and the axis convention that table documents: world X interpolates along the map's *y* axis,
    // world Y along the map's *x* axis. So
    //   world_x = 8333.333  + (78.56/100) * (3966.6665 - 8333.333)  = 4902.880
    //   world_y = 2941.6665 + (40.77/100) * (-3608.3333 - 2941.6665) =  271.231
    let (point, route) = lowered(".goto Darkshore,40.77,78.56,40,0").await;

    assert_eq!(
        point.map_id, KALIMDOR,
        "the artifact carries the continent the navmesh uses, not the ui map id from field 0. \
         got: {point:?}"
    );
    assert_close(point.x, 4902.88, "A-11-23.lua:205 world X");
    assert_close(point.y, 271.231, "A-11-23.lua:205 world Y");
    assert_eq!(
        point.z, None,
        "§5.7 leaves Z unresolved when the compiler has no navmesh probe; `None` is the answer, \
         not a guessed 0.0. got: {point:?}"
    );
    assert_eq!(route.radii, vec![40], "got: {route:?}");
    assert_eq!(route.mode, TravelMode::Any, "got: {route:?}");

    // The failure this guards is ADR 06 invariant 3: a percentage that survives compilation. If the
    // authored pair reached the artifact untransformed the bot travels to a meaningless point and
    // nothing fails loudly.
    assert!(
        point.x != 40.77 && point.y != 78.56,
        "the authored percentages reached the artifact as world coordinates. got: {point:?}"
    );
}

#[tokio::test]
async fn a_zone_name_alias_resolves_the_same_way_its_zone_id_does() {
    // Two lines from the same guide, three steps apart, both in Darkshore, authored in the two
    // spellings field 0 permits for the *same* percentage system:
    //   A-11-23.lua:127 — `.goto Darkshore,36.096,44.931`   (zone name, 35,449 corpus uses)
    //   A-11-23.lua:135 — `.goto 1439,36.767,44.285`        (zone id,   1,765 corpus uses)
    // Neither carries a `/`, so both are percentages and both resolve to continent 1.
    let (by_name, _) = lowered(".goto Darkshore,36.096,44.931").await;
    let (by_id, _) = lowered(".goto 1439,36.767,44.285").await;

    assert_eq!(by_name.map_id, KALIMDOR, "got: {by_name:?}");
    assert_eq!(by_id.map_id, KALIMDOR, "got: {by_id:?}");
    assert_close(by_name.x, 6371.346, "A-11-23.lua:127 world X");
    assert_close(by_name.y, 577.378, "A-11-23.lua:127 world Y");
    assert_close(by_id.x, 6399.555, "A-11-23.lua:135 world X");
    assert_close(by_id.y, 533.428, "A-11-23.lua:135 world Y");
}

#[tokio::test]
async fn a_trailing_display_tail_is_not_a_coordinate() {
    // A-11-23.lua:40 — `.goto Wetlands,4.61,57.26,15 >> Travel to the dock for the boat to Auberdine`
    //
    // Wetlands (ui map 1437) measured bounds, continent 0:
    //   top -2147.9165, left -389.5833, bottom -4904.1665, right -4525.0
    //   world_x = -2147.9165 + (57.26/100) * (-4904.1665 - -2147.9165) = -3726.145
    //   world_y =  -389.5833 + ( 4.61/100) * (-4525.0    - -389.5833)  =  -580.226
    // The `>>` tail is prose. A lowering that comma-splits before stripping it sees a fourth and
    // fifth "argument" and lands in the malformed-arity path for a perfectly well-formed line.
    let (point, route) = lowered(
        ".goto Wetlands,4.61,57.26,15 >> Travel to the dock for the boat to Auberdine",
    )
    .await;

    assert_eq!(point.map_id, EASTERN_KINGDOMS, "got: {point:?}");
    assert_close(point.x, -3726.145, "A-11-23.lua:40 world X");
    assert_close(point.y, -580.226, "A-11-23.lua:40 world Y");
    assert_eq!(route.radii, vec![15], "got: {route:?}");
}

#[tokio::test]
async fn a_raw_world_goto_passes_its_coordinates_through_untransformed() {
    // A-11-23.lua:769 — `.goto 1439/1,579.500,5240.300`
    //
    // Field 0 is `<uiMapId>/<mapId>`: ui map 1439 (Darkshore) on continent 1 (Kalimdor). The two
    // values that follow are already in the server's frame, so the *only* correct operation is
    // none at all. Exact equality, not a tolerance: any transform applied here is a defect.
    //
    // The literals below are the shortest spellings that round-trip to the same `f32` as the
    // authored text (`5240.300` and `5240.3` are one value at this width); the verbatim line is
    // quoted above so the tie to the corpus survives the shortening.
    //
    // Before the transform was unified this line produced no coordinate at all: field 0 went
    // straight to the zone table, `1439/1` matched nothing, and the action arrived carrying
    // `position: None`. 929 corpus lines are this shape.
    let (point, _) = lowered(".goto 1439/1,579.500,5240.300").await;

    assert_eq!(
        point,
        Point {
            map_id: KALIMDOR,
            // The authoring convention is the one ZONE_TABLE documents: the first authored value
            // is world **Y**, the second world **X**. See
            // `the_two_coordinate_systems_agree_about_where_the_beached_sea_creatures_are` for the
            // corpus corroboration of that ordering.
            x: 5240.3,
            y: 579.5,
            z: None,
        },
        "got: {point:?}"
    );
}

#[tokio::test]
async fn the_two_coordinate_systems_agree_about_where_the_beached_sea_creatures_are() {
    // The axis-order corroboration, from two consecutive steps of the same guide:
    //   A-11-23.lua:764 — `.goto 1439,37.105,62.167`      then `.accept 4722` (Beached Sea Turtle)
    //   A-11-23.lua:769 — `.goto 1439/1,579.500,5240.300` then `.accept 4728` (Beached Sea Creature)
    // Two clickable objects on the same Darkshore beach, authored one in each coordinate system.
    //
    // Under the ZONE_TABLE convention (first value → world Y, second → world X) A-11-23.lua:764
    // lowers to
    // (5618.708, 511.289) and the two points are 385 yd apart — the same beach.
    // Under the reversed reading they are 6,911 yd apart, which is most of the zone. That gap is
    // what makes this a test rather than a restatement: only one of the two orderings is survivable.
    let (percentage, _) = lowered(".goto 1439,37.105,62.167").await;
    let (raw_world, _) = lowered(".goto 1439/1,579.500,5240.300").await;

    assert_close(percentage.x, 5618.708, "A-11-23.lua:764 world X");
    assert_close(percentage.y, 511.289, "A-11-23.lua:764 world Y");

    let separation =
        ((percentage.x - raw_world.x).powi(2) + (percentage.y - raw_world.y).powi(2)).sqrt();
    assert!(
        separation < 500.0,
        "two adjacent steps that click objects on the same beach lowered {separation} yd apart. \
         Above ~6,900 yd means the world X/Y ordering of one of the two coordinate systems is \
         reversed. got: percentage {percentage:?}, raw world {raw_world:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The waypoint pool: discrimination
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn the_slash_in_field_zero_discriminates_the_systems_not_the_coordinate_range() {
    // Field 0 spells `1439` in both of these A-11-23.lua lines. Everything about how they lower
    // differs, and the `/` is the only signal available:
    //   :215 `.goto 1439,36.051,44.757,0`     → percentages, transformed
    //   :769 `.goto 1439/1,579.500,5240.300`  → world coordinates, untouched
    let (percentage, _) = lowered(".goto 1439,36.051,44.757,0").await;
    let (raw_world, _) = lowered(".goto 1439/1,579.500,5240.300").await;
    assert_close(percentage.x, 6378.944, "A-11-23.lua:215 world X");
    assert_close(percentage.y, 580.326, "A-11-23.lua:215 world Y");
    assert_eq!(raw_world.x, 5240.3, "got: {raw_world:?}");
    assert_eq!(raw_world.y, 579.5, "got: {raw_world:?}");

    // The case a range test gets wrong. `The Burning Crusade.lua:28542` — `.goto 1944/530,4341.30029,97.1`
    // is raw world on continent 530 (Outland), and its second value, 97.1, sits squarely inside
    // 0..100. Any heuristic of the form "a coordinate in 0..100 is a percentage" reclassifies this
    // line and transforms coordinates that were already world coordinates. That reversal is how
    // ADR 07's 36,322 double-count arose; measured, the corpus has 929 raw-world lines across
    // `.goto` / `.waypoint` / `.groundgoto`, of which 15 carry an axis inside 0..100.
    let (range_trap, _) = lowered(".goto 1944/530,4341.30029,97.1").await;
    assert_eq!(
        range_trap,
        Point {
            map_id: OUTLAND,
            x: 97.1,
            // `4341.3003` is the shortest spelling that round-trips to the same `f32` as the
            // authored `4341.30029`, which is quoted verbatim above.
            y: 4341.3003,
            z: None,
        },
        "a value inside 0..100 is not evidence of a percentage — field 0 carries a `/`, so this \
         line is raw world and must pass through. got: {range_trap:?}"
    );

    // And the mirror: `.waypoint 1948/530,34.200,-5187.100,70,0` (The Burning Crusade.lua:113036),
    // where it is the *first* axis that looks like a percentage.
    let (range_trap_first_axis, _) = lowered(".waypoint 1948/530,34.200,-5187.100,70,0").await;
    assert_eq!(
        range_trap_first_axis,
        Point {
            map_id: OUTLAND,
            x: -5187.1,
            y: 34.2,
            z: None,
        },
        "got: {range_trap_first_axis:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Malformed arity is refused, never repaired
//
// The corpus has 67 six-argument `.goto` lines and they are THREE distinct defects, not one.
// ADR 07 once described all 67 as the comma-typed-decimal case; an importer that "repairs" on that
// description silently corrupts 63 of them into wrong coordinates. Refuse, name the line, do not
// guess.
//
// The refusal is scoped to the **line**, not the guide: the coordinate is dropped and a diagnostic
// quotes it, and the surrounding step still compiles. That is the same posture the unknown-zone
// refusal already had (`build_travel_position`: "A zone we cannot convert yields NO position rather
// than a bogus one"), and it is the only one that survives contact with the corpus — 5 of the 277
// guide blocks carry one of these 67 lines.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// Compile a movement line that must be refused, and return the diagnostic that named it.
async fn refused(line: &str) -> sentinel_models::authoring::Diagnostic {
    let project = import(&guide(&[line])).await;

    let positioned: Vec<_> = project
        .operations
        .iter()
        .flat_map(|op| &op.actions)
        .filter_map(|action| match &action.payload {
            ActionPayload::Travel(travel) => travel.position,
            _ => None,
        })
        .collect();
    assert!(
        positioned.is_empty(),
        "`{line}` carries six comma-separated arguments and must be refused. It lowered to \
         {positioned:?} instead — a repaired coordinate is indistinguishable from a correct one at \
         every later stage."
    );

    let arity: Vec<_> = project
        .diagnostics
        .iter()
        .filter(|d| d.code == "MALFORMED_MOVEMENT_ARITY")
        .collect();
    let [diagnostic] = arity.as_slice() else {
        panic!(
            "the refusal must be an arity refusal, not (for instance) an unknown-zone refusal — \
             `Silithus` and `Burning Steppes` are both in ZONE_TABLE and would lower to a wrong \
             coordinate rather than fail. got: {:?}",
            project.diagnostics
        )
    };
    assert_eq!(
        diagnostic.severity,
        Severity::Warning,
        "a dropped coordinate is a warning, not an error that stops the import: 5 of 277 guide \
         blocks carry one of these lines and refusing the block deletes the other ~500 coordinates \
         in it. got: {diagnostic:?}"
    );
    (*diagnostic).clone()
}

#[tokio::test]
async fn a_six_argument_goto_with_a_stray_trailing_zero_is_refused_not_repaired() {
    // The Burning Crusade.lua:67691 — `.goto Silithus,51.60,16.40,70,0,0`
    // 60 of the 67 six-argument lines are this shape: a well-formed 5-argument line with one extra
    // `0` appended. The tempting repair — drop the last field — happens to be right for these 60
    // and wrong for the other 7.
    let diagnostic = refused(".goto Silithus,51.60,16.40,70,0,0").await;

    assert!(
        diagnostic.message.contains("6"),
        "the diagnostic must say how many fields were found, so the reader can tell the three \
         defects apart. got: {diagnostic:?}"
    );
    assert!(
        diagnostic.message.contains(".goto Silithus,51.60,16.40,70,0,0"),
        "the diagnostic must quote the line verbatim so the author can find it. got: {diagnostic:?}"
    );
}

#[tokio::test]
async fn a_six_argument_goto_with_a_comma_typed_decimal_is_refused_not_repaired() {
    // The Burning Crusade.lua:23188 — `.goto Un'Goro Crater,20.6,60,4,70,0`
    // 4 of the 67 are this shape: the Y coordinate `60.4` was typed with a comma, so it split into
    // two fields. The repair that fixes the stray-trailing-zero case (drop field 5) turns this into
    // `.goto Un'Goro Crater,20.6,60,4,70`, i.e. Y = 60 instead of 60.4 — silently, and 30 yd off.
    //
    // Un'Goro Crater IS in ZONE_TABLE, so before the arity check reached the live path this line
    // lowered to that wrong coordinate and nothing said so.
    let diagnostic = refused(".goto Un'Goro Crater,20.6,60,4,70,0").await;

    assert!(
        diagnostic.message.contains("6")
            && diagnostic.message.contains(".goto Un'Goro Crater,20.6,60,4,70,0"),
        "got: {diagnostic:?}"
    );
}

#[tokio::test]
async fn a_six_argument_goto_with_a_stray_leading_zero_is_refused_not_repaired() {
    // The Burning Crusade.lua:131658 — `.goto Burning Steppes,49.6,55.4,0,60,0`
    // 3 of the 67 are this shape: an extra `0` *before* the radius, so the radius 60 and the
    // arrival flag 0 both shifted right. Dropping the trailing field here reads the radius as 0 and
    // the arrival flag as 60. Every one of the three repairs is wrong for the other two shapes,
    // which is the whole argument for refusing all three.
    let diagnostic = refused(".goto Burning Steppes,49.6,55.4,0,60,0").await;

    assert!(
        diagnostic.message.contains("6")
            && diagnostic.message.contains(".goto Burning Steppes,49.6,55.4,0,60,0"),
        "got: {diagnostic:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A `--` dev comment is prose, exactly like a `>>` tail
//
// 38 corpus movement lines carry a trailing `--` dev comment (`A-11-23.lua` x27,
// `A-1-11-Draenei.lua` x11). The importer's lexer strips it
// (`sentinel_models::source::strip_inline_dev_comment`) before the args are split, and this section
// pins that the stripped line reaches the artifact whole: both markers introduce prose, and a
// movement line carrying prose in field 3 is a valid line being refused.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[tokio::test]
async fn a_trailing_dev_comment_is_not_an_arrival_radius() {
    // A-11-23.lua:663 — `.goto 1439,42.017,58.866,0 --NE spawn`
    //
    // Four of the 38 attach the comment directly to the radius with no space, so an unstripped line
    // parses the fourth field as `0 --NE spawn` and is refused as a malformed number. Field 0 has no
    // `/`, so these are Darkshore percentages; the expected pair is the measured transform
    // (`ZONE_TABLE`, continent 1: top 8333.333, left 2941.6665, bottom 3966.6665, right -3608.3333):
    //   world_x = 8333.333  + (58.866/100) * (3966.6665 - 8333.333)   = 5762.851
    //   world_y = 2941.6665 + (42.017/100) * (-3608.3333 - 2941.6665) =  189.553
    let (point, route) = lowered(".goto 1439,42.017,58.866,0 --NE spawn").await;

    assert_eq!(point.map_id, KALIMDOR, "got: {point:?}");
    assert_close(point.x, 5762.851, "A-11-23.lua:663 world X");
    assert_close(point.y, 189.553, "A-11-23.lua:663 world Y");
    assert_eq!(
        route.radii,
        vec![0],
        "the authored arrival radius is `0`; `--NE spawn` is prose about the mob camp. got: {route:?}"
    );
}

#[tokio::test]
async fn a_dev_comment_after_a_raw_world_coordinate_is_not_part_of_it() {
    // A-11-23.lua:4248 — `.goto 1414/1,-2036.9180,-796.8898 -- Nalpak`
    //
    // The three-argument shape, and the more dangerous one: the comment lands on the *second
    // coordinate*, so an unstripped line is refused with `world X '-796.8898 -- Nalpak' is not a
    // number`. Field 0 carries a `/` — ui map 1414 (the Kalimdor continent map) on continent 1 — so
    // the coordinates are already in the server's frame and pass through untransformed.
    let (point, route) = lowered(".goto 1414/1,-2036.9180,-796.8898 -- Nalpak").await;

    assert_eq!(
        point,
        Point {
            map_id: KALIMDOR,
            x: -796.8898,
            y: -2036.918,
            z: None,
        },
        "got: {point:?}"
    );
    assert_eq!(
        route.radii,
        vec![5],
        "no fourth argument was authored, so the importer's 5-yard reach default stands. \
         got: {route:?}"
    );
}

/// Every corpus movement line carrying a `--` dev comment, verbatim and in file order.
///
/// Derived, not remembered:
/// `rg -n '^\s*\.(goto|waypoint|groundgoto|flygoto)\s.*--' *.lua` over
/// `sentinel/docs/adr/restedxp guides` returns exactly these 38 — 27 in `A-11-23.lua`, 11 in
/// `A-1-11-Draenei.lua`, none in the other five files.
const DEV_COMMENT_MOVEMENT_LINES: &[&str] = &[
    // A-1-11-Draenei.lua:3603
    ".goto 1415/0,258.6045,-4078.9674,60,0 -- Wetlands to Westfall swim",
    // A-1-11-Draenei.lua:4286
    ".goto Darnassus,55.239,23.996 -- Argent Guard Manados",
    // A-1-11-Draenei.lua:4289
    ".goto Darnassus,55.360,25.024 -- Dawnwatcher Shaedlass",
    // A-1-11-Draenei.lua:4622
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-1-11-Draenei.lua:4624
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-1-11-Draenei.lua:4745
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-1-11-Draenei.lua:4747
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-1-11-Draenei.lua:4756
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-1-11-Draenei.lua:4764
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-1-11-Draenei.lua:5144
    ".goto Darnassus,55.239,23.996 -- Argent Guard Manados",
    // A-1-11-Draenei.lua:5151
    ".goto Darnassus,56.167,24.395 -- Dawnwatcher Selgorm",
    // A-11-23.lua:663
    ".goto 1439,42.017,58.866,0 --NE spawn",
    // A-11-23.lua:664
    ".goto 1439,43.222,59.693,0 --NE spawn",
    // A-11-23.lua:665
    ".goto 1439,43.069,62.448,0 --SE spawn",
    // A-11-23.lua:666
    ".goto 1439,42.489,60.677,0 --Middle spawn",
    // A-11-23.lua:667
    ".waypoint 1439,42.017,58.866,50,0 --NE spawn",
    // A-11-23.lua:670
    ".waypoint 1439,43.222,59.693,50,0 --NE spawn",
    // A-11-23.lua:673
    ".waypoint 1439,43.069,62.448,50,0 --SE spawn",
    // A-11-23.lua:676
    ".waypoint 1439,42.489,60.677,50,0 --Middle spawn",
    // A-11-23.lua:2674
    ".goto 1415/0,258.6045,-4078.9674,60,0 -- Wetlands to Westfall swim",
    // A-11-23.lua:3380
    ".goto Darnassus,55.239,23.996 -- Argent Guard Manados",
    // A-11-23.lua:3383
    ".goto Darnassus,55.360,25.024 -- Dawnwatcher Shaedlass",
    // A-11-23.lua:4248
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-11-23.lua:4250
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-11-23.lua:4371
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-11-23.lua:4373
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-11-23.lua:4382
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-11-23.lua:4390
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-11-23.lua:4783
    ".goto Darnassus,55.239,23.996 -- Argent Guard Manados",
    // A-11-23.lua:4790
    ".goto Darnassus,56.167,24.395 -- Dawnwatcher Selgorm",
    // A-11-23.lua:5571
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-11-23.lua:5573
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-11-23.lua:5694
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-11-23.lua:5696
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-11-23.lua:5705
    ".goto 1414/1,-2039.1260,-802.2871 -- Ebru",
    // A-11-23.lua:5713
    ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    // A-11-23.lua:5857
    ".goto Darnassus,55.239,23.996 -- Argent Guard Manados",
    // A-11-23.lua:5864
    ".goto Darnassus,56.167,24.395 -- Dawnwatcher Selgorm",
];

#[tokio::test]
async fn no_corpus_movement_line_is_refused_because_of_its_dev_comment() {
    assert_eq!(
        DEV_COMMENT_MOVEMENT_LINES.len(),
        38,
        "the corpus census is 38 `--`-bearing movement lines; the table must carry all of them"
    );

    let project = import(&guide(DEV_COMMENT_MOVEMENT_LINES)).await;

    let travels: Vec<&sentinel_models::authoring::TravelAction> = project
        .operations
        .iter()
        .flat_map(|op| &op.actions)
        .filter_map(|action| match &action.payload {
            ActionPayload::Travel(travel) => Some(travel),
            _ => None,
        })
        .collect();
    assert_eq!(
        travels.len(),
        38,
        "each of the 38 lines is a movement command and must reach the authoring model as one. \
         got: {travels:?}"
    );

    let unresolved: Vec<&str> = travels
        .iter()
        .zip(DEV_COMMENT_MOVEMENT_LINES)
        .filter(|(travel, _)| travel.position.is_none())
        .map(|(_, line)| *line)
        .collect();
    assert!(
        unresolved.is_empty(),
        "{} of the 38 `--`-bearing corpus movement lines resolved to no coordinate — the dev \
         comment leaked into a parsed field:\n  {}",
        unresolved.len(),
        unresolved.join("\n  ")
    );
}
