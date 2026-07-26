//! Lowering tests for the ADR 07 kernel artifact: the interned waypoint pool, the predicate tree,
//! and the `Compiler::compile_kernel` entry point that will one day assemble them out of the two.
//!
//! **It does not assemble them yet, and section D says so out loud.** `compile_kernel` returns a
//! profile *header* — empty pool, no tasks, zero-placeholder digests — because task-graph lowering
//! is a later deliverable. The pool and predicate sections below therefore test
//! `parse_movement` / `lower_route` / `lower_predicate` directly, and section D tests the entry
//! point for the only things it currently claims: a well-formed header, and the
//! `KERNEL_PROFILE_INCOMPLETE` warning that keeps its emptiness from reading as a clean compile.
//!
//! Authority: `sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md`. Corpus:
//! `sentinel/docs/adr/restedxp guides`. Every test below quotes the verbatim guide line it lowers,
//! with its file and line number, so the expected value can be re-derived from the source rather
//! than trusted.
//!
//! # What these tests prove
//!
//! * **Coordinates normalise, they do not pass through.** RestedXP authors two coordinate systems
//!   and they are not interchangeable. `zone,x,y` carries *zone-relative percentages* (0..100);
//!   `<uiMapId>/<continentMapId>,x,y` carries *raw world* coordinates already in the server's frame.
//!   The discriminator is the `/` in field 0 and nothing else.
//! * **Prose is stripped, not parsed.** Both `>>` display text and `--` dev comments reach
//!   `parse_movement` — `SourceLine::text` is the line verbatim — and 38 corpus movement lines carry
//!   a `--`. Neither marker may reach a parsed field.
//! * **Interning is a pool operation, never a route operation.** One pool entry per distinct
//!   `(map_id, x, y, z)`; a route that re-crosses a point repeats the *index*. A route's length is
//!   the number of movement lines that produced it, before and after interning.
//! * **A malformed line is refused, never repaired.** The 67 six-argument `.goto` lines in the
//!   corpus are three different defects, and every plausible "repair" corrupts the other two.
//! * **A predicate is derived from its input, not transcribed.** `QuestObjective::need` comes from
//!   the injected metadata provider; the tests change the provider and require the output to
//!   change with it.
//! * **An incomplete artifact says so.** `compile_kernel` cannot emit an empty profile silently.
//!
//! # What these tests cannot see
//!
//! * **The zone→world transform's correctness.** The expected world coordinates are computed from
//!   the measured bounds table in `shared/src/zone.rs` (`ZONE_TABLE` — it moved there from
//!   `importer/src/project_builder.rs` so the ADR-05 and ADR-07 lowerings share one table; sampled
//!   from a live client via `core.game_ui.get_world_pos_from_map_pos` and verified against a known
//!   DB spawn to within 0.1 yd). If that table is wrong, these tests are wrong with it in exactly
//!   the same direction. They pin *that the compiler uses the measured transform*, not that the
//!   measurement is true. `assert_close`'s tolerance is 0.1 yd for the same reason.
//! * **Whether `radius: 0` means "zero yards" or "engine default".** Several of the corpus lines
//!   below authored a fourth argument of `0`; the artifact carries what was authored and this file
//!   asserts only that.
//! * **`TravelMode::Ground` / `TravelMode::Air`.** The corpus's 114 `.groundgoto` and 1 `.flygoto`
//!   lines are not exercised here; every line cited below is `.goto` or `.waypoint`, i.e.
//!   `TravelMode::Any`.
//! * **Whether the metadata provider's `need` matches `quest_template`.** The provider is a stub.
//!   These tests prove the value *travels from the provider into the predicate*; that the provider
//!   reads the right `ReqItemCount*` column is the query layer's contract, not this one's.
//! * **The route-level collapse of §2.6 / §5.7 / §8** (a source step emitting the same coordinate
//!   twice as both a 4-arg and a 5-arg line). That is a separate, later deliverable. Nothing here
//!   asserts it, and a route whose length shrank would fail
//!   `a_route_that_recrosses_a_point_repeats_the_index_and_keeps_its_length`.
//! * **Anything `compile_kernel` does not do yet** — the task graph, archetype gate resolution, the
//!   two BLAKE3 digests, and world provenance. Section D pins the *placeholders*, which is a
//!   statement about today's honesty, not about tomorrow's correctness.
//! * **`HasItem`, which is now refused by both sinks and has no test here.** An earlier revision of
//!   this file asserted that the kernel sink folded `HasItem(item)` into
//!   `ItemCount { cmp: Ge, count: 1 }`, justified as "a legal ADR-05 authoring input reachable
//!   through the editor's `/compile` endpoint". That justification was false and one grep refuted
//!   it: `compiler/src/condition.rs`'s `RuntimeConditionSink::leaf` has no `HasItem` arm, so the
//!   ADR-05 parser refuses the name; no importer emitter produces the string; and
//!   `RuntimeCondition::HasItem` is declared in `shared/src/runtime/condition.rs` and constructed
//!   nowhere. The arm was removed rather than kept, so the two sinks — which share one parser —
//!   accept exactly the same leaf vocabulary. That symmetry is pinned by
//!   `sentinel_compiler::kernel::predicate::tests::has_item_is_refused_by_both_sinks`, a unit test
//!   because only crate-internal code can reach both sinks.
//!
//! # Surface these tests require of `sentinel_compiler::kernel`
//!
//! ```ignore
//! pub struct SourceLine<'a> { pub file: &'a str, pub line: u32, pub text: &'a str }  // + Copy, Debug
//! pub struct Movement { pub point: Point, pub radius: u16, pub mode: TravelMode }    // + Debug
//! pub struct WaypointPool { /* … */ }                                               // + Default
//! impl WaypointPool { pub fn into_points(self) -> Vec<Point>; }
//!
//! pub fn parse_movement(src: SourceLine<'_>) -> Result<Movement, LoweringError>;
//! pub fn lower_route(
//!     kind: RouteKind,
//!     lines: &[SourceLine<'_>],
//!     pool: &mut WaypointPool,
//! ) -> Result<Route, LoweringError>;
//!
//! pub trait QuestMeta {
//!     /// `Some(0)` is "this objective needs no count"; `None` is "the world database could not
//!     /// answer". The two must not be collapsed — see
//!     /// `an_objective_the_provider_cannot_answer_is_a_hard_error_not_a_zero`.
//!     fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32>;
//! }
//! pub fn lower_predicate(expression: &str, meta: &dyn QuestMeta) -> Result<Predicate, LoweringError>;
//!
//! pub enum LoweringError {                                                          // + Debug
//!     MalformedArity { file: String, line: u32, text: String, found: usize },
//!     UnknownZone { file: String, line: u32, text: String, zone: String },
//!     UnknownObjective { quest: QuestId, index: u8 },
//!     UnmappablePredicate { expression: String, /* … */ },
//!     // … plus whatever the parser needs (bad number, mixed travel modes, …)
//! }
//! ```
//!
//! Section D additionally requires `Compiler::compile_kernel(&Project, &Archetype, &dyn QuestMeta)`
//! to return `(kernel::RuntimeProfile, CompileReport)`.
//!
//! `lower_predicate` must keep `compiler/src/condition.rs`'s hardened lexer/parser rather than
//! re-implement it: `MAX_CONDITION_DEPTH = 64` and `MAX_CONDITION_TOKENS = 4096` close a
//! network-reachable stack-overflow DoS on the editor's `/compile` endpoint, pinned by
//! `condition::tests::recursion_depth_is_bounded`. A rewrite that loses them reintroduces a remote
//! crash. Only the `ConditionSink` implementation — `KernelSink`'s three combinators and its `leaf`
//! mapping — is model-specific.

use sentinel_compiler::kernel::{
    lower_predicate, lower_route, parse_movement, LoweringError, Movement, QuestMeta, SourceLine,
    WaypointPool,
};
use sentinel_compiler::Compiler;
use sentinel_models::authoring::{new_project, Class, Faction, Race, Severity};
use sentinel_models::kernel::{
    Archetype, Cmp, CombatStance, Expansion, Point, Predicate, ProfileMode, QuestId, RouteKind,
    RuntimeProfile as KernelProfile, TravelMode, UnknownPolicy, MAGIC, SCHEMA_VERSION,
};

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const DARKSHORE_GUIDE: &str = "A-11-23.lua";
const TBC_GUIDE: &str = "The Burning Crusade.lua";
const DWARF_GNOME_GUIDE: &str = "A-1-11-Dwarf-Gnome.lua";
const DRAENEI_GUIDE: &str = "A-1-11-Draenei.lua";

/// Kalimdor. `.goto 1439,…` names *ui map* 1439 (Darkshore); the artifact carries the **continent**
/// the navmesh and the server use, which for Darkshore is `1`. Conflating the two is the bug this
/// discriminates against — a `Point` whose `map_id` is 1439 is a percentage that survived
/// compilation wearing a map id.
const KALIMDOR: u32 = 1;
/// Eastern Kingdoms — the continent Wetlands (ui map 1437) resolves to.
const EASTERN_KINGDOMS: u32 = 0;

/// Measured-transform tolerance, in yards. See the module header: `ZONE_TABLE` is documented as
/// accurate to 0.1 yd against a known DB spawn, so nothing tighter is meaningful.
const YARD_TOLERANCE: f32 = 0.1;

fn at(file: &'static str, line: u32, text: &'static str) -> SourceLine<'static> {
    SourceLine { file, line, text }
}

fn lowered(src: SourceLine<'static>) -> Movement {
    parse_movement(src).unwrap_or_else(|err| {
        panic!("{}:{} `{}` must lower, got: {err:?}", src.file, src.line, src.text)
    })
}

fn assert_close(actual: f32, expected: f32, what: &str) {
    assert!(
        (actual - expected).abs() <= YARD_TOLERANCE,
        "{what}: expected {expected} (±{YARD_TOLERANCE} yd, re-derived from ZONE_TABLE), \
         got: {actual:?} — a difference of {} yd",
        (actual - expected).abs()
    );
}

/// A stub `QuestMeta`. `objective_need` answers only for the pairs it was built with; everything
/// else is `None`, which the lowering must treat as a hard error rather than as `need: 0`.
struct StubMeta(Vec<((QuestId, u8), u32)>);

impl StubMeta {
    fn with(pairs: &[((QuestId, u8), u32)]) -> Self {
        StubMeta(pairs.to_vec())
    }

    /// A provider that knows nothing. Used to prove `need` is not invented when the world database
    /// cannot answer.
    fn empty() -> Self {
        StubMeta(Vec::new())
    }
}

impl QuestMeta for StubMeta {
    fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32> {
        self.0
            .iter()
            .find(|((q, i), _)| *q == quest && *i == index)
            .map(|(_, need)| *need)
    }

    /// No objective in this file is an item objective, so nothing here needs a loot rule. `None`
    /// is "not an item", never "could not answer" — see the trait's own doc comment.
    fn objective_item(&self, _quest: QuestId, _index: u8) -> Option<u32> {
        None
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// B — the waypoint pool: normalisation
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn a_zone_percentage_goto_normalises_to_measured_world_coordinates() {
    // A-11-23.lua:205 — `.goto Darkshore,40.77,78.56,40,0`
    //
    // Darkshore's measured bounds (ZONE_TABLE, continent 1):
    //   top 8333.333, left 2941.6665, bottom 3966.6665, right -3608.3333
    // and the axis convention that table documents: world X interpolates along the map's *y* axis,
    // world Y along the map's *x* axis. So
    //   world_x = 8333.333  + (78.56/100) * (3966.6665 - 8333.333)  = 4902.880
    //   world_y = 2941.6665 + (40.77/100) * (-3608.3333 - 2941.6665) =  271.231
    let movement = lowered(at(DARKSHORE_GUIDE, 205, ".goto Darkshore,40.77,78.56,40,0"));

    assert_eq!(
        movement.point.map_id, KALIMDOR,
        "the artifact carries the continent the navmesh uses, not the ui map id from field 0. \
         got: {:?}",
        movement.point
    );
    assert_close(movement.point.x, 4902.88, "A-11-23.lua:205 world X");
    assert_close(movement.point.y, 271.231, "A-11-23.lua:205 world Y");
    assert_eq!(
        movement.point.z, None,
        "§5.7 leaves Z unresolved when the compiler has no navmesh probe; `None` is the answer, \
         not a guessed 0.0. got: {:?}",
        movement.point
    );
    assert_eq!(movement.radius, 40, "got: {:?}", movement);
    assert_eq!(movement.mode, TravelMode::Any, "got: {:?}", movement);

    // The failure this guards is ADR 06 invariant 3: a percentage that survives compilation. If the
    // authored pair reached the artifact untransformed the bot travels to a meaningless point and
    // nothing fails loudly.
    assert!(
        movement.point.x != 40.77 && movement.point.y != 78.56,
        "the authored percentages reached the artifact as world coordinates. got: {:?}",
        movement.point
    );
}

#[test]
fn a_zone_name_alias_resolves_the_same_way_its_zone_id_does() {
    // Two lines from the same guide, three steps apart, both in Darkshore, authored in the two
    // spellings field 0 permits for the *same* percentage system:
    //   A-11-23.lua:127 — `.goto Darkshore,36.096,44.931`   (zone name, 35,449 corpus uses)
    //   A-11-23.lua:135 — `.goto 1439,36.767,44.285`        (zone id,   1,765 corpus uses)
    // Neither carries a `/`, so both are percentages and both resolve to continent 1.
    let by_name = lowered(at(DARKSHORE_GUIDE, 127, ".goto Darkshore,36.096,44.931"));
    let by_id = lowered(at(DARKSHORE_GUIDE, 135, ".goto 1439,36.767,44.285"));

    assert_eq!(by_name.point.map_id, KALIMDOR, "got: {:?}", by_name.point);
    assert_eq!(by_id.point.map_id, KALIMDOR, "got: {:?}", by_id.point);
    assert_close(by_name.point.x, 6371.346, "A-11-23.lua:127 world X");
    assert_close(by_name.point.y, 577.378, "A-11-23.lua:127 world Y");
    assert_close(by_id.point.x, 6399.555, "A-11-23.lua:135 world X");
    assert_close(by_id.point.y, 533.428, "A-11-23.lua:135 world Y");
}

#[test]
fn a_trailing_display_tail_is_not_a_coordinate() {
    // A-11-23.lua:40 — `.goto Wetlands,4.61,57.26,15 >> Travel to the dock for the boat to Auberdine`
    //
    // Wetlands (ui map 1437) measured bounds, continent 0:
    //   top -2147.9165, left -389.5833, bottom -4904.1665, right -4525.0
    //   world_x = -2147.9165 + (57.26/100) * (-4904.1665 - -2147.9165) = -3726.145
    //   world_y =  -389.5833 + ( 4.61/100) * (-4525.0    - -389.5833)  =  -580.226
    // The `>>` tail is prose. A lowering that comma-splits before stripping it sees a fourth and
    // fifth "argument" and lands in the malformed-arity path for a perfectly well-formed line.
    let movement = lowered(at(
        DARKSHORE_GUIDE,
        40,
        ".goto Wetlands,4.61,57.26,15 >> Travel to the dock for the boat to Auberdine",
    ));

    assert_eq!(
        movement.point.map_id, EASTERN_KINGDOMS,
        "got: {:?}",
        movement.point
    );
    assert_close(movement.point.x, -3726.145, "A-11-23.lua:40 world X");
    assert_close(movement.point.y, -580.226, "A-11-23.lua:40 world Y");
    assert_eq!(movement.radius, 15, "got: {:?}", movement);
}

#[test]
fn a_raw_world_goto_passes_its_coordinates_through_untransformed() {
    // A-11-23.lua:769 — `.goto 1439/1,579.500,5240.300`
    //
    // Field 0 is `<uiMapId>/<mapId>`: ui map 1439 (Darkshore) on continent 1 (Kalimdor). The two
    // values that follow are already in the server's frame, so the *only* correct operation is
    // none at all. Exact equality, not a tolerance: any transform applied here is a defect.
    //
    // The literals below are the shortest spellings that round-trip to the same `f32` as the
    // authored text (`5240.300` and `5240.3` are one value at this width); the verbatim line is
    // quoted above so the tie to the corpus survives the shortening.
    let movement = lowered(at(DARKSHORE_GUIDE, 769, ".goto 1439/1,579.500,5240.300"));

    assert_eq!(
        movement.point,
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
        "got: {:?}",
        movement.point
    );
}

#[test]
fn the_two_coordinate_systems_agree_about_where_the_beached_sea_creatures_are() {
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
    let percentage = lowered(at(DARKSHORE_GUIDE, 764, ".goto 1439,37.105,62.167"));
    let raw_world = lowered(at(DARKSHORE_GUIDE, 769, ".goto 1439/1,579.500,5240.300"));

    assert_close(percentage.point.x, 5618.708, "A-11-23.lua:764 world X");
    assert_close(percentage.point.y, 511.289, "A-11-23.lua:764 world Y");

    let separation = ((percentage.point.x - raw_world.point.x).powi(2)
        + (percentage.point.y - raw_world.point.y).powi(2))
    .sqrt();
    assert!(
        separation < 500.0,
        "two adjacent steps that click objects on the same beach lowered {separation} yd apart. \
         Above ~6,900 yd means the world X/Y ordering of one of the two coordinate systems is \
         reversed. got: percentage {:?}, raw world {:?}",
        percentage.point,
        raw_world.point
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// B — the waypoint pool: discrimination
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn the_slash_in_field_zero_discriminates_the_systems_not_the_coordinate_range() {
    // Field 0 spells `1439` in both of these A-11-23.lua lines. Everything about how they lower
    // differs, and the `/` is the only signal available:
    //   :215 `.goto 1439,36.051,44.757,0`     → percentages, transformed
    //   :769 `.goto 1439/1,579.500,5240.300`  → world coordinates, untouched
    let percentage = lowered(at(DARKSHORE_GUIDE, 215, ".goto 1439,36.051,44.757,0"));
    let raw_world = lowered(at(DARKSHORE_GUIDE, 769, ".goto 1439/1,579.500,5240.300"));
    assert_close(percentage.point.x, 6378.944, "A-11-23.lua:215 world X");
    assert_close(percentage.point.y, 580.326, "A-11-23.lua:215 world Y");
    assert_eq!(raw_world.point.x, 5240.3, "got: {:?}", raw_world.point);
    assert_eq!(raw_world.point.y, 579.5, "got: {:?}", raw_world.point);

    // The case a range test gets wrong. `The Burning Crusade.lua:28542` — `.goto 1944/530,4341.30029,97.1`
    // is raw world on continent 530 (Outland), and its second value, 97.1, sits squarely inside
    // 0..100. Any heuristic of the form "a coordinate in 0..100 is a percentage" reclassifies this
    // line and transforms coordinates that were already world coordinates. That reversal is how
    // ADR 07's 36,322 double-count arose; measured, the corpus has 929 raw-world lines across
    // `.goto` / `.waypoint` / `.groundgoto`, of which 15 carry an axis inside 0..100.
    let range_trap = lowered(at(TBC_GUIDE, 28542, ".goto 1944/530,4341.30029,97.1"));
    assert_eq!(
        range_trap.point,
        Point {
            map_id: 530,
            x: 97.1,
            // `4341.3003` is the shortest spelling that round-trips to the same `f32` as the
            // authored `4341.30029`, which is quoted verbatim above.
            y: 4341.3003,
            z: None,
        },
        "a value inside 0..100 is not evidence of a percentage — field 0 carries a `/`, so this \
         line is raw world and must pass through. got: {:?}",
        range_trap.point
    );

    // And the mirror: `.waypoint 1948/530,34.200,-5187.100,70,0` (The Burning Crusade.lua:113036),
    // where it is the *first* axis that looks like a percentage.
    let range_trap_first_axis = lowered(at(TBC_GUIDE, 113036, ".waypoint 1948/530,34.200,-5187.100,70,0"));
    assert_eq!(
        range_trap_first_axis.point,
        Point {
            map_id: 530,
            x: -5187.1,
            y: 34.2,
            z: None,
        },
        "got: {:?}",
        range_trap_first_axis.point
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// B — the waypoint pool: interning
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// The `#loop` circuit at `A-11-23.lua:211-237`, verbatim, in authored order.
///
/// This is the step ADR 07 §5.7 calls the decisive witness for [`RouteKind::Circuit`]: the last
/// `.waypoint` (:231) is byte-identical in its coordinates to the first `.goto` (:215), and three
/// more interior points repeat too. A navmesh asked to path from A to A returns a zero-length path
/// and cannot know the intent is to walk the loop repeatedly to farm respawns.
fn buzz_box_circuit() -> Vec<SourceLine<'static>> {
    vec![
        at(DARKSHORE_GUIDE, 215, ".goto 1439,36.051,44.757,0"),
        at(DARKSHORE_GUIDE, 216, ".goto 1439,36.280,50.071,0"),
        at(DARKSHORE_GUIDE, 217, ".goto 1439,35.275,53.464,0"),
        at(DARKSHORE_GUIDE, 218, ".waypoint 1439,36.091,51.501,60,0"),
        at(DARKSHORE_GUIDE, 219, ".waypoint 1439,37.115,52.368,60,0"),
        at(DARKSHORE_GUIDE, 220, ".waypoint 1439,37.130,53.663,60,0"),
        at(DARKSHORE_GUIDE, 221, ".waypoint 1439,36.740,55.221,60,0"),
        at(DARKSHORE_GUIDE, 222, ".waypoint 1439,35.655,55.872,60,0"),
        at(DARKSHORE_GUIDE, 223, ".waypoint 1439,35.088,55.085,60,0"),
        // :224, :225 and :226 re-cross :217, :218 and :216 respectively.
        at(DARKSHORE_GUIDE, 224, ".waypoint 1439,35.275,53.464,60,0"),
        at(DARKSHORE_GUIDE, 225, ".waypoint 1439,36.091,51.501,60,0"),
        at(DARKSHORE_GUIDE, 226, ".waypoint 1439,36.280,50.071,60,0"),
        at(DARKSHORE_GUIDE, 227, ".waypoint 1439,36.523,48.554,60,0"),
        at(DARKSHORE_GUIDE, 228, ".waypoint 1439,35.977,48.408,60,0"),
        at(DARKSHORE_GUIDE, 229, ".waypoint 1439,35.902,47.145,60,0"),
        at(DARKSHORE_GUIDE, 230, ".waypoint 1439,35.759,45.455,60,0"),
        // :231 closes the circuit onto :215.
        at(DARKSHORE_GUIDE, 231, ".waypoint 1439,36.051,44.757,60,0"),
    ]
}

#[test]
fn a_route_that_recrosses_a_point_repeats_the_index_and_keeps_its_length() {
    let lines = buzz_box_circuit();
    let mut pool = WaypointPool::default();
    let route = lower_route(RouteKind::Circuit { close: true }, &lines, &mut pool)
        .unwrap_or_else(|err| panic!("A-11-23.lua:211-237 must lower, got: {err:?}"));

    // 17 authored movement lines in, 17 route slots out. Interning is a *pool* operation; §7.1
    // annotates the pool "deduplicated" and says nothing about shortening routes. Collapsing the
    // four repeats here would delete three quarters of the loop's second half and the circuit would
    // stop being a circuit.
    assert_eq!(
        route.points.len(),
        lines.len(),
        "interning changed the route's length. got: {:?}",
        route.points
    );
    assert_eq!(
        route.radii.len(),
        lines.len(),
        "`radii` is parallel to `points` (§7.1). got: {:?}",
        route.radii
    );

    // 13 distinct coordinates for 17 slots: :224 == :217, :225 == :218, :226 == :216, :231 == :215.
    let pool = pool.into_points();
    assert_eq!(
        pool.len(),
        13,
        "17 authored points, 4 of them re-crossings, so 13 distinct entries. got: {:?}",
        pool
    );
    assert_eq!(
        route.points,
        vec![0, 1, 2, 3, 4, 5, 6, 7, 8, 2, 3, 1, 9, 10, 11, 12, 0],
        "a re-crossed point must repeat the index of its first appearance, in first-seen pool \
         order. got: {:?}",
        route.points
    );

    // The three `.goto` lines authored a fourth argument of 0; the fourteen `.waypoint` lines
    // authored 60. The artifact carries what was authored.
    let mut expected_radii = vec![0u16; 3];
    expected_radii.extend(std::iter::repeat_n(60u16, 14));
    assert_eq!(route.radii, expected_radii, "got: {:?}", route.radii);

    assert_eq!(
        route.kind,
        RouteKind::Circuit { close: true },
        "got: {:?}",
        route.kind
    );
    assert_eq!(route.mode, TravelMode::Any, "got: {:?}", route.mode);
}

#[test]
fn no_two_waypoint_pool_entries_hold_the_same_coordinate() {
    let lines = buzz_box_circuit();
    let mut pool = WaypointPool::default();
    lower_route(RouteKind::Circuit { close: true }, &lines, &mut pool)
        .unwrap_or_else(|err| panic!("A-11-23.lua:211-237 must lower, got: {err:?}"));
    let pool = pool.into_points();

    // `Point` is only `PartialEq` (it carries `f32`), so a hash/sort key would have to be invented
    // here; the pairwise scan compares the same values the invariant is stated over. This mirrors
    // `shared/tests/kernel_fixture.rs::no_two_waypoint_pool_entries_hold_the_same_coordinate`,
    // which pins the same invariant on the committed §7.3.3 fixture.
    let duplicates: Vec<String> = pool
        .iter()
        .enumerate()
        .filter_map(|(later, point)| {
            let first = pool[..later].iter().position(|earlier| earlier == point)?;
            Some(format!(
                "slots {first} and {later} both hold (map {}, {}, {}, z {:?})",
                point.map_id, point.x, point.y, point.z
            ))
        })
        .collect();

    assert!(
        duplicates.is_empty(),
        "the pool holds each distinct (map_id, x, y, z) exactly once (§6.4, §7.1). {} of the {} \
         entries lowered from A-11-23.lua:211-237 repeat an earlier entry:\n  {}",
        duplicates.len(),
        pool.len(),
        duplicates.join("\n  ")
    );
}

#[test]
fn a_point_shared_between_two_routes_is_pooled_once() {
    // Interning spans tasks, not just routes (§6.4: the pool "deduplicates shared points across
    // tasks"). `A-11-23.lua:115` and `A-11-23.lua:122` are two different steps that both send the
    // player to the byte-identical Wetlands coordinate.
    let mut pool = WaypointPool::default();
    let first = lower_route(
        RouteKind::Destination,
        &[at(DARKSHORE_GUIDE, 115, ".goto 1437,4.370,56.762")],
        &mut pool,
    )
    .unwrap_or_else(|err| panic!("A-11-23.lua:115 must lower, got: {err:?}"));
    let second = lower_route(
        RouteKind::Destination,
        &[at(DARKSHORE_GUIDE, 122, ".goto 1437,4.370,56.762")],
        &mut pool,
    )
    .unwrap_or_else(|err| panic!("A-11-23.lua:122 must lower, got: {err:?}"));

    assert_eq!(
        first.points, second.points,
        "the same coordinate authored in two steps must resolve to the same pool index. \
         got: {:?} and {:?}",
        first.points, second.points
    );
    assert_eq!(
        pool.into_points().len(),
        1,
        "two routes over one coordinate is one pool entry"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// B — the waypoint pool: malformed arity is refused, never repaired
//
// The corpus has 67 six-argument `.goto` lines and they are THREE distinct defects, not one.
// ADR 07 once described all 67 as the comma-typed-decimal case; an importer that "repairs" on that
// description silently corrupts 63 of them into wrong coordinates. Refuse, name the line, do not
// guess.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

fn refused(src: SourceLine<'static>) -> LoweringError {
    match parse_movement(src) {
        Ok(movement) => panic!(
            "{}:{} `{}` carries six comma-separated arguments and must be refused. It lowered to \
             {movement:?} instead — a repaired coordinate is indistinguishable from a correct one \
             at every later stage.",
            src.file, src.line, src.text
        ),
        Err(err) => err,
    }
}

#[test]
fn a_six_argument_goto_with_a_stray_trailing_zero_is_refused_not_repaired() {
    // The Burning Crusade.lua:67691 — `.goto Silithus,51.60,16.40,70,0,0`
    // 60 of the 67 six-argument lines are this shape: a well-formed 5-argument line with one extra
    // `0` appended. The tempting repair — drop the last field — happens to be right for these 60
    // and wrong for the other 7.
    let src = at(TBC_GUIDE, 67691, ".goto Silithus,51.60,16.40,70,0,0");
    let err = refused(src);
    let LoweringError::MalformedArity { file, line, text, found } = &err else {
        panic!(
            "the refusal must be an arity refusal, not (for instance) an unknown-zone refusal — \
             Silithus is absent from ZONE_TABLE and would fail for the wrong reason. got: {err:?}"
        )
    };
    assert_eq!(*found, 6, "got: {err:?}");
    assert_eq!(file.as_str(), TBC_GUIDE, "got: {err:?}");
    assert_eq!(*line, 67691, "got: {err:?}");
    assert_eq!(
        text.as_str(),
        ".goto Silithus,51.60,16.40,70,0,0",
        "the diagnostic must quote the line verbatim so the author can find it. got: {err:?}"
    );
}

#[test]
fn a_six_argument_goto_with_a_comma_typed_decimal_is_refused_not_repaired() {
    // The Burning Crusade.lua:23188 — `.goto Un'Goro Crater,20.6,60,4,70,0`
    // 4 of the 67 are this shape: the Y coordinate `60.4` was typed with a comma, so it split into
    // two fields. The repair that fixes the stray-trailing-zero case (drop field 5) turns this into
    // `.goto Un'Goro Crater,20.6,60,4,70`, i.e. Y = 60 instead of 60.4 — silently, and 30 yd off.
    let src = at(TBC_GUIDE, 23188, ".goto Un'Goro Crater,20.6,60,4,70,0");
    let err = refused(src);
    let LoweringError::MalformedArity { line, text, found, .. } = &err else {
        panic!("expected an arity refusal, got: {err:?}")
    };
    assert_eq!(*found, 6, "got: {err:?}");
    assert_eq!(*line, 23188, "got: {err:?}");
    assert_eq!(
        text.as_str(),
        ".goto Un'Goro Crater,20.6,60,4,70,0",
        "got: {err:?}"
    );
}

#[test]
fn a_six_argument_goto_with_a_stray_leading_zero_is_refused_not_repaired() {
    // The Burning Crusade.lua:131658 — `.goto Burning Steppes,49.6,55.4,0,60,0`
    // 3 of the 67 are this shape: an extra `0` *before* the radius, so the radius 60 and the
    // arrival flag 0 both shifted right. Dropping the trailing field here reads the radius as 0 and
    // the arrival flag as 60. Every one of the three repairs is wrong for the other two shapes,
    // which is the whole argument for refusing all three.
    let src = at(TBC_GUIDE, 131658, ".goto Burning Steppes,49.6,55.4,0,60,0");
    let err = refused(src);
    let LoweringError::MalformedArity { line, text, found, .. } = &err else {
        panic!("expected an arity refusal, got: {err:?}")
    };
    assert_eq!(*found, 6, "got: {err:?}");
    assert_eq!(*line, 131658, "got: {err:?}");
    assert_eq!(
        text.as_str(),
        ".goto Burning Steppes,49.6,55.4,0,60,0",
        "got: {err:?}"
    );
}

#[test]
fn a_refused_line_contributes_nothing_to_the_pool() {
    // Refusal must be total. A malformed line that errors *after* interning its half-parsed
    // coordinate leaves a phantom entry in the pool and shifts every index authored after it.
    let mut pool = WaypointPool::default();
    let result = lower_route(
        RouteKind::Corridor,
        &[
            at(DARKSHORE_GUIDE, 215, ".goto 1439,36.051,44.757,0"),
            at(TBC_GUIDE, 67691, ".goto Silithus,51.60,16.40,70,0,0"),
        ],
        &mut pool,
    );

    assert!(
        result.is_err(),
        "a route containing a malformed line must not lower. got: {result:?}"
    );
    assert_eq!(
        pool.into_points().len(),
        0,
        "a route that failed to lower must leave the pool as it found it"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// B — the waypoint pool: a `--` dev comment is prose, exactly like a `>>` tail
//
// 38 corpus movement lines carry a trailing `--` dev comment (`A-11-23.lua` x27,
// `A-1-11-Draenei.lua` x11). `SourceLine::text` is documented "the line itself, verbatim", so the
// comment arrives with the line and `parse_movement` has to strip it — with the *same* rule and the
// same implementation the importer's lexer applies, `sentinel_models::source::strip_inline_dev_comment`.
// Stripping `>>` here while delegating `--` upstream is the incoherent half-contract this section
// closes: both markers introduce prose, and a `SourceLine` carrying prose in field 3 is a valid
// line being refused.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

#[test]
fn a_trailing_dev_comment_is_not_an_arrival_radius() {
    // A-11-23.lua:663 — `.goto 1439,42.017,58.866,0 --NE spawn`
    //
    // Four of the 38 attach the comment directly to the radius with no space, so an unstripped line
    // parses the fourth field as `0 --NE spawn` and is refused as a malformed number. Field 0 has no
    // `/`, so these are Darkshore percentages; the expected pair is the measured transform
    // (`ZONE_TABLE`, continent 1: top 8333.333, left 2941.6665, bottom 3966.6665, right -3608.3333):
    //   world_x = 8333.333  + (58.866/100) * (3966.6665 - 8333.333)   = 5762.851
    //   world_y = 2941.6665 + (42.017/100) * (-3608.3333 - 2941.6665) =  189.553
    let movement = lowered(at(DARKSHORE_GUIDE, 663, ".goto 1439,42.017,58.866,0 --NE spawn"));

    assert_eq!(movement.point.map_id, KALIMDOR, "got: {:?}", movement.point);
    assert_close(movement.point.x, 5762.851, "A-11-23.lua:663 world X");
    assert_close(movement.point.y, 189.553, "A-11-23.lua:663 world Y");
    assert_eq!(
        movement.radius, 0,
        "the authored arrival radius is `0`; `--NE spawn` is prose about the mob camp. got: {movement:?}"
    );
}

#[test]
fn a_dev_comment_after_a_raw_world_coordinate_is_not_part_of_it() {
    // A-11-23.lua:4248 — `.goto 1414/1,-2036.9180,-796.8898 -- Nalpak`
    //
    // The three-argument shape, and the more dangerous one: the comment lands on the *second
    // coordinate*, so an unstripped line is refused with `world X '-796.8898 -- Nalpak' is not a
    // number`. Field 0 carries a `/` — ui map 1414 (the Kalimdor continent map) on continent 1 — so
    // the coordinates are already in the server's frame and pass through untransformed.
    let movement = lowered(at(
        DARKSHORE_GUIDE,
        4248,
        ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak",
    ));

    assert_eq!(
        movement.point,
        Point {
            map_id: KALIMDOR,
            x: -796.8898,
            y: -2036.918,
            z: None,
        },
        "got: {:?}",
        movement.point
    );
    assert_eq!(
        movement.radius, 0,
        "no fourth argument was authored. got: {movement:?}"
    );
}

/// Every corpus movement line carrying a `--` dev comment, verbatim and in file order.
///
/// Derived, not remembered:
/// `rg -n '^\s*\.(goto|waypoint|groundgoto|flygoto)\s.*--' *.lua` over
/// `sentinel/docs/adr/restedxp guides` returns exactly these 38 — 27 in `A-11-23.lua`, 11 in
/// `A-1-11-Draenei.lua`, none in the other five files.
const DEV_COMMENT_MOVEMENT_LINES: &[(&str, u32, &str)] = &[
    (DRAENEI_GUIDE, 3603, ".goto 1415/0,258.6045,-4078.9674,60,0 -- Wetlands to Westfall swim"),
    (DRAENEI_GUIDE, 4286, ".goto Darnassus,55.239,23.996 -- Argent Guard Manados"),
    (DRAENEI_GUIDE, 4289, ".goto Darnassus,55.360,25.024 -- Dawnwatcher Shaedlass"),
    (DRAENEI_GUIDE, 4622, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DRAENEI_GUIDE, 4624, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DRAENEI_GUIDE, 4745, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DRAENEI_GUIDE, 4747, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DRAENEI_GUIDE, 4756, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DRAENEI_GUIDE, 4764, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DRAENEI_GUIDE, 5144, ".goto Darnassus,55.239,23.996 -- Argent Guard Manados"),
    (DRAENEI_GUIDE, 5151, ".goto Darnassus,56.167,24.395 -- Dawnwatcher Selgorm"),
    (DARKSHORE_GUIDE, 663, ".goto 1439,42.017,58.866,0 --NE spawn"),
    (DARKSHORE_GUIDE, 664, ".goto 1439,43.222,59.693,0 --NE spawn"),
    (DARKSHORE_GUIDE, 665, ".goto 1439,43.069,62.448,0 --SE spawn"),
    (DARKSHORE_GUIDE, 666, ".goto 1439,42.489,60.677,0 --Middle spawn"),
    (DARKSHORE_GUIDE, 667, ".waypoint 1439,42.017,58.866,50,0 --NE spawn"),
    (DARKSHORE_GUIDE, 670, ".waypoint 1439,43.222,59.693,50,0 --NE spawn"),
    (DARKSHORE_GUIDE, 673, ".waypoint 1439,43.069,62.448,50,0 --SE spawn"),
    (DARKSHORE_GUIDE, 676, ".waypoint 1439,42.489,60.677,50,0 --Middle spawn"),
    (DARKSHORE_GUIDE, 2674, ".goto 1415/0,258.6045,-4078.9674,60,0 -- Wetlands to Westfall swim"),
    (DARKSHORE_GUIDE, 3380, ".goto Darnassus,55.239,23.996 -- Argent Guard Manados"),
    (DARKSHORE_GUIDE, 3383, ".goto Darnassus,55.360,25.024 -- Dawnwatcher Shaedlass"),
    (DARKSHORE_GUIDE, 4248, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DARKSHORE_GUIDE, 4250, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DARKSHORE_GUIDE, 4371, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DARKSHORE_GUIDE, 4373, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DARKSHORE_GUIDE, 4382, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DARKSHORE_GUIDE, 4390, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DARKSHORE_GUIDE, 4783, ".goto Darnassus,55.239,23.996 -- Argent Guard Manados"),
    (DARKSHORE_GUIDE, 4790, ".goto Darnassus,56.167,24.395 -- Dawnwatcher Selgorm"),
    (DARKSHORE_GUIDE, 5571, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DARKSHORE_GUIDE, 5573, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DARKSHORE_GUIDE, 5694, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DARKSHORE_GUIDE, 5696, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DARKSHORE_GUIDE, 5705, ".goto 1414/1,-2039.1260,-802.2871 -- Ebru"),
    (DARKSHORE_GUIDE, 5713, ".goto 1414/1,-2036.9180,-796.8898 -- Nalpak"),
    (DARKSHORE_GUIDE, 5857, ".goto Darnassus,55.239,23.996 -- Argent Guard Manados"),
    (DARKSHORE_GUIDE, 5864, ".goto Darnassus,56.167,24.395 -- Dawnwatcher Selgorm"),
];

#[test]
fn no_corpus_movement_line_is_refused_because_of_its_dev_comment() {
    assert_eq!(
        DEV_COMMENT_MOVEMENT_LINES.len(),
        38,
        "the corpus census is 38 `--`-bearing movement lines; the table must carry all of them"
    );

    let refused: Vec<String> = DEV_COMMENT_MOVEMENT_LINES
        .iter()
        .filter_map(|(file, line, text)| match parse_movement(at(file, *line, text)) {
            Ok(_) => None,
            // Kept as an accepted outcome, though nothing in this table reaches it any more:
            // `ZONE_TABLE` now covers all 68 `WorldMapArea` records, so the ten `Darnassus` lines
            // that used to be refused for an unmappable zone now lower successfully. What this
            // test is actually about is unchanged — a *lexical* refusal caused by the prose in a
            // `--` comment must never happen — and an unmappable zone is still a legitimate,
            // non-lexical reason to refuse a line, so it stays exempt.
            Err(LoweringError::UnknownZone { .. }) => None,
            Err(err) => Some(format!("{file}:{line} `{text}` -> {err:?}")),
        })
        .collect();

    assert!(
        refused.is_empty(),
        "{} of the 38 `--`-bearing corpus movement lines were refused for a reason other than an \
         unmappable zone — the dev comment leaked into a parsed field:\n  {}",
        refused.len(),
        refused.join("\n  ")
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// C — predicate lowering
//
// The input is the `02_DATA_MODEL.md` §23 DSL string the importer emits for a corpus command
// (`importer/src/project_builder.rs::gating_condition_dsl`), and each test quotes both the corpus
// line and the DSL it produces so the chain can be re-walked.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

fn predicate(expression: &str, meta: &dyn QuestMeta) -> Predicate {
    lower_predicate(expression, meta)
        .unwrap_or_else(|err| panic!("`{expression}` must lower, got: {err:?}"))
}

#[test]
fn is_on_quest_with_a_multi_id_list_lowers_to_an_or_of_quest_in_log() {
    // A-11-23.lua:1426 — `.isOnQuest 9699,9584,9643,9580,10063`
    // `quest_ids_dsl` joins one `QuestAccepted(id)` per id with ` || `; the kernel maps
    // QuestAccepted → QuestInLog, the "in the log, neither complete nor turned in" state (§5.1.1).
    let meta = StubMeta::empty();
    let lowered = predicate(
        "QuestAccepted(9699) || QuestAccepted(9584) || QuestAccepted(9643) || QuestAccepted(9580) \
         || QuestAccepted(10063)",
        &meta,
    );

    assert_eq!(
        lowered,
        Predicate::Or(vec![
            Predicate::QuestInLog { id: 9699 },
            Predicate::QuestInLog { id: 9584 },
            Predicate::QuestInLog { id: 9643 },
            Predicate::QuestInLog { id: 9580 },
            Predicate::QuestInLog { id: 10063 },
        ]),
        "got: {lowered:?}"
    );
}

#[test]
fn is_quest_complete_lowers_to_quest_complete() {
    // A-11-23.lua:473 — `.isQuestComplete 955` → DSL `QuestCompleted(955)`.
    // "Objectives met, not yet handed in" — distinct from QuestTurnedIn, and a resumed run cannot
    // tell the two apart without both (§5.1.1).
    let meta = StubMeta::empty();
    let lowered = predicate("QuestCompleted(955)", &meta);
    assert_eq!(lowered, Predicate::QuestComplete { id: 955 }, "got: {lowered:?}");
}

#[test]
fn is_quest_turned_in_lowers_to_quest_turned_in() {
    // A-11-23.lua:480 — `.isQuestTurnedIn 955` → DSL `QuestRewarded(955)`.
    let meta = StubMeta::empty();
    let lowered = predicate("QuestRewarded(955)", &meta);
    assert_eq!(lowered, Predicate::QuestTurnedIn { id: 955 }, "got: {lowered:?}");
}

#[test]
fn an_xp_level_gate_lowers_to_level_at_least() {
    // A-11-23.lua:322 — `.xp 12` → DSL `LevelAtLeast(12)` (`xp_level_dsl`).
    // §5.2 keeps this a runtime predicate rather than resolving it at compile time: player level
    // changes during play, and caching it is the RXP `applies()` bug.
    let meta = StubMeta::empty();
    let lowered = predicate("LevelAtLeast(12)", &meta);
    assert_eq!(lowered, Predicate::LevelAtLeast { level: 12 }, "got: {lowered:?}");
}

#[test]
fn item_count_with_a_less_than_operator_lowers_to_cmp_lt() {
    // A-1-11-Dwarf-Gnome.lua:631 — `.itemcount 16321,<1 --Grimoire of Blood Pact (Rank 1)`
    //
    // The §23 DSL has only an at-least primitive, so `item_count_dsl`
    // (`importer/src/project_builder.rs`) encodes `<n` as `NOT ItemCount(item,n)`. The kernel has
    // `Cmp`, so the negation folds away: NOT (count >= 1) is exactly (count < 1). Emitting
    // `Not(ItemCount { cmp: Ge, .. })` instead would be a second way to spell one thing, which
    // §5.1.1 is explicit about avoiding.
    let meta = StubMeta::empty();
    let lowered = predicate("NOT ItemCount(16321,1)", &meta);

    assert_eq!(
        lowered,
        Predicate::ItemCount {
            id: 16321,
            cmp: Cmp::Lt,
            count: 1,
        },
        "the operator authored on {DWARF_GNOME_GUIDE}:631 must survive as a `Cmp`, not as a `Not` \
         wrapper around the at-least primitive. got: {lowered:?}"
    );
}

#[test]
fn a_collect_count_lowers_to_cmp_ge() {
    // A-11-23.lua:139 — `.collect 4592,15 --Longjaw Mud Snapper` → DSL `ItemCount(4592,15)`.
    // The unoperated form is the at-least case, and it is the complement of the `<` case above.
    let meta = StubMeta::empty();
    let lowered = predicate("ItemCount(4592,15)", &meta);
    assert_eq!(
        lowered,
        Predicate::ItemCount {
            id: 4592,
            cmp: Cmp::Ge,
            count: 15,
        },
        "got: {lowered:?}"
    );
}

#[test]
fn an_objective_takes_its_need_from_the_metadata_provider() {
    // A-11-23.lua:234 — `.complete 983,1 --Crawler Leg (6)` → DSL `Objective(983,1)`.
    //
    // The DSL carries the quest and the 1-based objective index and NOTHING ELSE. `need` is baked
    // offline from `quest_template.ReqItemCount1` so the runtime never parses a localized progress
    // string (§7.3.2) — the `(6)` in the trailing dev comment is prose, stripped at lex time
    // (`lexer.rs::strip_inline_dev_comment`), and is not an input to anything.
    //
    // Two providers, one expression. If `need` were transcribed from the ADR fixture, or read off
    // the dev comment, or defaulted, the second assertion would still say 6.
    let truthful = StubMeta::with(&[((983, 1), 6)]);
    assert_eq!(
        predicate("Objective(983,1)", &truthful),
        Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 6,
        },
        "got: {:?}",
        predicate("Objective(983,1)", &truthful)
    );

    let contradicting = StubMeta::with(&[((983, 1), 99)]);
    assert_eq!(
        predicate("Objective(983,1)", &contradicting),
        Predicate::QuestObjective {
            id: 983,
            index: 1,
            need: 99,
        },
        "`need` must be read from the provider on every lowering, not from a constant that happens \
         to agree with it. got: {:?}",
        predicate("Objective(983,1)", &contradicting)
    );
}

#[test]
fn an_exploration_objective_lowers_to_need_zero() {
    // A-11-23.lua:264 — `.complete 984,1 -- Find a corrupt furbolg camp` → DSL `Objective(984,1)`.
    //
    // Quest 984 (`How Big a Threat?`) has no `Req*` columns populated at all: it is satisfied by
    // area discovery, not by a count. §7.3.2 and §8 call `need: 0` legal and load-bearing, and the
    // doc comment on `Predicate::QuestObjective::need` (`shared/src/kernel/predicate.rs`) says a
    // positive-count validation here "would make it unsatisfiable". The provider answering 0 is a
    // real answer and must survive as one.
    let meta = StubMeta::with(&[((984, 1), 0)]);
    let lowered = predicate("Objective(984,1)", &meta);
    assert_eq!(
        lowered,
        Predicate::QuestObjective {
            id: 984,
            index: 1,
            need: 0,
        },
        "got: {lowered:?}"
    );
}

#[test]
fn an_objective_the_provider_cannot_answer_is_a_hard_error_not_a_zero() {
    // The distinction the test above depends on: `Some(0)` is "this objective needs no count" and
    // `None` is "the world database could not answer". Collapsing the second into the first
    // manufactures an exploration objective out of a lookup failure, and the resulting task
    // completes the instant it is evaluated.
    let meta = StubMeta::empty();
    let result = lower_predicate("Objective(983,1)", &meta);
    assert!(
        matches!(result, Err(LoweringError::UnknownObjective { quest: 983, index: 1 })),
        "got: {result:?}"
    );
}

#[test]
fn an_unmappable_expression_is_a_hard_error_never_always_true() {
    // The ADR-05 compiler fails open here: the `ActionPayload::Condition(cond)` arm of
    // `resolve_action` (`compiler/src/lib.rs`) records an
    // `UNMAPPED_CONDITION` diagnostic and substitutes `RuntimeCondition::AlwaysTrue`
    // (`compiler/tests/compiler.rs::unmappable_condition_expression_records_diagnostic_and_fails_open`
    // pins that behaviour, and it stays pinned — `Compiler::compile` is unchanged).
    //
    // The kernel cannot do that and must not try: its 24 `Predicate` variants contain no
    // always-true, by design. Per the P3 ingest posture an expression that cannot be mapped is a
    // hard error.
    let meta = StubMeta::empty();
    let result = lower_predicate("NotARealPredicate(1)", &meta);
    let Err(LoweringError::UnmappablePredicate { expression, .. }) = &result else {
        panic!(
            "an unmappable expression must fail the compile, not gate open. got: {result:?}"
        )
    };
    assert!(
        expression.contains("NotARealPredicate"),
        "the error must name the expression it could not map. got: {result:?}"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// D — the entry point: `Compiler::compile_kernel`
//
// Everything above calls `parse_movement` / `lower_route` / `lower_predicate` directly, which says
// nothing about the function that is supposed to assemble them. What `compile_kernel` emits today
// is a **header with an empty pool and no tasks** — deliberately, because the task graph is a later
// deliverable — and the single thing that stops that emptiness reading as a clean compile is the
// `KERNEL_PROFILE_INCOMPLETE` warning. These tests exist so a later edit cannot drop the warning and
// stay green.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// A `QuestMeta` that fails the test if it is consulted.
///
/// `compile_kernel` accepts a provider it does not yet use (no task is lowered, so nothing needs a
/// baked `need`). That is a fact worth pinning rather than assuming: see
/// `the_metadata_provider_is_not_consulted_until_the_task_graph_lands`.
struct ForbiddenMeta;

impl QuestMeta for ForbiddenMeta {
    fn objective_need(&self, quest: QuestId, index: u8) -> Option<u32> {
        panic!(
            "`compile_kernel` consulted the metadata provider for quest {quest} objective {index}. \
             If task lowering now runs, this tripwire has done its job — replace it with a stub \
             that answers, and assert the baked `need` reaches the task's predicate."
        )
    }

    fn objective_item(&self, quest: QuestId, index: u8) -> Option<u32> {
        panic!(
            "`compile_kernel` consulted the metadata provider for the loot filter of quest              {quest} objective {index}. Same tripwire, same remedy."
        )
    }
}

/// The archetype under test. `compile_kernel` takes it as an **input** (C2, §5.2): faction is not
/// readable from the Sylvanas API and there is no race enum, so every static gate is resolved at
/// compile time and one artifact is emitted per archetype.
fn night_elf_druid() -> Archetype {
    Archetype {
        class: Class::Druid,
        race: Race::NightElf,
        faction: Faction::Alliance,
        expansion: Expansion::Tbc,
        allegiance: None,
        hardcore: false,
        self_found: false,
        can_fly: false,
        content_phase: None,
        mode: ProfileMode::SpeedRoute,
        // The three axes §4.2 classifies as archetype filters and `Archetype` gained with C2:
        // `#xprate` in thousandths (1_000 is blizzlike), `#hardcoreserver`, `#season`.
        xp_rate_milli: 1_000,
        hardcore_server: false,
        season: None,
    }
}

fn compiled_kernel() -> (KernelProfile, sentinel_compiler::CompileReport) {
    let project = new_project("Darkshore 11-23");
    Compiler::compile_kernel(&project, &night_elf_druid(), &ForbiddenMeta)
        .unwrap_or_else(|err| panic!("`compile_kernel` must not fail on a well-formed project, got: {err:?}"))
}

#[test]
fn compile_kernel_warns_that_the_artifact_is_incomplete() {
    let (_, report) = compiled_kernel();

    let warning = report
        .unmapped_conditions
        .iter()
        .find(|d| d.code == "KERNEL_PROFILE_INCOMPLETE")
        .unwrap_or_else(|| {
            panic!(
                "`compile_kernel` returns an empty pool and no tasks. Without a \
                 KERNEL_PROFILE_INCOMPLETE diagnostic that emptiness is indistinguishable from a \
                 clean compile of a trivial guide, and the artifact would look shippable. \
                 got: {:?}",
                report.unmapped_conditions
            )
        });

    assert_eq!(
        warning.severity,
        Severity::Warning,
        "got: {warning:?}"
    );
    assert_eq!(
        warning.entity.as_deref(),
        Some("Darkshore 11-23"),
        "the diagnostic must name the guide it refers to. got: {warning:?}"
    );
    // Naming each gap individually, so a partial implementation that closes one of them cannot keep
    // a message that still claims all three.
    for gap in ["task graph", "waypoint pool", "content_hash"] {
        assert!(
            warning.message.contains(gap),
            "the warning must name `{gap}` as a gap, so a reader knows what is missing rather than \
             only that something is. got: {:?}",
            warning.message
        );
    }
    assert_eq!(
        report.unresolved, 0,
        "nothing was resolved, so nothing failed to resolve; `unresolved` counts NPC/object \
         reference failures and must not be repurposed as an incompleteness signal. got: {report:?}"
    );
}

#[test]
fn compile_kernel_emits_zero_placeholder_digests_not_computed_ones() {
    let (profile, _) = compiled_kernel();

    // §5.4 / §5.4.1 make these BLAKE3 digests. They are not computed yet, and the placeholder is
    // all-zero *on purpose*: a wrong-but-plausible digest would pass every shape check and fail
    // only at load, on a machine with no compiler.
    assert_eq!(
        profile.schema_hash, [0u8; 32],
        "got: {:?}",
        profile.schema_hash
    );
    assert_eq!(
        profile.integrity.content_hash, [0u8; 32],
        "got: {:?}",
        profile.integrity.content_hash
    );
    assert!(
        profile.integrity.world_source.is_empty() && profile.integrity.world_build.is_empty(),
        "world provenance is not resolved either, and an invented value would be worse than an \
         empty one. got: {:?}",
        profile.integrity
    );
}

#[test]
fn compile_kernel_emits_a_well_formed_header_for_the_archetype_it_was_given() {
    let (profile, _) = compiled_kernel();

    assert_eq!(profile.magic, MAGIC, "got: {:?}", profile.magic);
    assert_eq!(profile.schema_version, SCHEMA_VERSION);
    assert_eq!(
        profile.archetype,
        night_elf_druid(),
        "the archetype is an input and must be echoed exactly — it is what every compile-time gate \
         was resolved against. got: {:?}",
        profile.archetype
    );
    assert_eq!(
        profile.meta.name, "Darkshore 11-23",
        "got: {:?}",
        profile.meta
    );

    // §5.6: `Defensive` is the profile-level default — 16,438 of 23,894 corpus tasks carry no
    // combat token at all. §5.1.2: `Defer` is the compiler's default for `complete_when`, with the
    // 60-tick budget §7.3.3 uses.
    assert_eq!(
        profile.defaults.combat.stance,
        CombatStance::Defensive,
        "got: {:?}",
        profile.defaults.combat
    );
    assert_eq!(
        profile.defaults.unknown_policy,
        UnknownPolicy::Defer { budget_ticks: 60 },
        "got: {:?}",
        profile.defaults.unknown_policy
    );

    // What it does *not* do yet, asserted so the header above stays honest.
    assert!(profile.waypoint_pool.is_empty(), "got: {:?}", profile.waypoint_pool);
    assert!(profile.tasks.is_empty(), "got: {} tasks", profile.tasks.len());
    assert!(
        profile.tags_used.is_empty(),
        "`tags_used` is every op and predicate tag the artifact references (§5.4); with no tasks \
         there are none, and a non-empty list would name tags nothing uses. got: {:?}",
        profile.tags_used
    );
}

#[test]
fn the_header_compile_kernel_emits_survives_a_serde_round_trip() {
    let (profile, _) = compiled_kernel();

    // "Well-formed as far as it goes": the model denies unknown fields and requires every one of
    // §7.2's root fields, so a header that re-reads as itself is a header no field was left out of.
    // This is a shape check and nothing more — it cannot see that the pool and tasks are empty,
    // which is what `compile_kernel_warns_that_the_artifact_is_incomplete` is for.
    let json = serde_json::to_string(&profile).expect("the emitted header must serialize");
    let reloaded: KernelProfile =
        serde_json::from_str(&json).unwrap_or_else(|err| panic!("emitted header did not re-load: {err}\n{json}"));

    assert_eq!(reloaded, profile, "round trip changed the artifact");
}

#[test]
fn the_metadata_provider_is_not_consulted_until_the_task_graph_lands() {
    // A tripwire, not a requirement. `meta` exists to bake `Predicate::QuestObjective::need` from
    // `quest_template`, and the only consumer of that is a lowered task's `complete_when` — of
    // which `compile_kernel` currently emits none. `ForbiddenMeta` panics on contact, so this test
    // fails the day the provider is genuinely wired in, which is the moment its accompanying
    // assertions should be written.
    let (profile, _) = compiled_kernel();
    assert!(
        profile.tasks.is_empty(),
        "tasks are being lowered now, so the provider must be threaded into their predicates and \
         this tripwire replaced. got: {} tasks",
        profile.tasks.len()
    );
}

#[test]
fn an_unmappable_leaf_is_never_silently_dropped_from_a_tree() {
    // The second half of the same rule, and the easier one to get wrong. Omitting an unmappable
    // leaf from an `And`/`Or` leaves a predicate that still *looks* well-formed:
    // `QuestAccepted(983) && NotARealPredicate(1)` would lower to `QuestInLog { id: 983 }` alone.
    // No gate is fail-open by another name — the dropped conjunct was the restrictive one.
    let meta = StubMeta::empty();
    let result = lower_predicate("QuestAccepted(983) && NotARealPredicate(1)", &meta);

    assert!(
        result.is_err(),
        "an unmappable leaf must fail the whole expression, not be pruned out of it. got: {result:?}"
    );
    assert_ne!(
        result.ok(),
        Some(Predicate::QuestInLog { id: 983 }),
        "the unmappable conjunct was dropped and the surviving predicate gates on less than the \
         author wrote"
    );
}
