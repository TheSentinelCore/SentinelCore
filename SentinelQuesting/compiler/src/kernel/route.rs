//! The interned waypoint pool and route lowering (ADR `07_RUNTIME_PROFILE_SCHEMA` §5.7, §6.4,
//! §7.1).
//!
//! # The coordinate transform is not here
//!
//! It is [`sentinel_models::movement::resolve_coordinate`], and this module has no copy of it. It
//! used to: `parse_movement` lowered a whole guide line — the `/` raw-world discrimination, the
//! `3..=5` arity refusal, the `>>`/`--` prose strip, the axis order — and **no compile ever called
//! it**. The pipeline reaches routes through the importer, whose own transform implemented none of
//! the `/` handling, so 929 corpus lines were dropped while twelve tests over the dead
//! implementation stayed green. Coordinates now arrive here already resolved, on
//! [`TravelAction::position`](sentinel_models::authoring::TravelAction::position).
//!
//! # There are no unit tests in this file, deliberately
//!
//! There were two, and both were about the *mixed-medium refusal*: that it named the offending line,
//! and that a route which failed left the pool as it found it. A refusal aborts the whole compile, so
//! no artifact survives it to be inspected — that was the one property a compile could not observe,
//! and it was the only justification for testing this module directly rather than through one.
//! [`lower_route`] no longer refuses anything: a run that changes medium **splits**. Everything it
//! decides is now visible in an artifact, and it is pinned in
//! `compiler/tests/kernel_route_aggregation.rs`, driven the way a compile drives it. A unit test
//! here would be a second caller, which is what this whole module's history argues against.

use sentinel_models::authoring::TravelMedium;
use sentinel_models::kernel::{Point, Route, RouteKind, TravelMode};

/// One lowered movement: where, how close, and by what medium.
///
/// The pool index is deliberately *not* here — interning is [`WaypointPool`]'s job, and a
/// [`Movement`] can be inspected without one.
///
/// This is the currency [`lower_route`] takes, and the task-graph adapter is its only producer: it
/// lowers a [`TravelAction`](sentinel_models::authoring::TravelAction) the importer already
/// resolved. One producer, one route builder — which is what stops the pipeline growing a second
/// route implementation with its own answer about media.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Movement {
    /// World coordinate. `z` is `None`: the compiler has no navmesh probe, and §5.7 says an
    /// unresolved height is `None` so the engine ground-snaps — never a guessed `0.0`, which buries
    /// waypoints inside terrain.
    pub point: Point,
    /// Arrival radius in yards, exactly as authored. A line that authored none carries `0`.
    pub radius: u16,
    /// Required travel medium.
    pub mode: TravelMode,
}

/// The artifact's spelling of an authoring [`TravelMedium`] (§7.1).
///
/// The one place the two vocabularies meet. The command→medium table itself lives on
/// [`TravelMedium::for_command`] in the authoring model, shared with the importer so a command
/// cannot be recognised by one side and dropped by the other — which is exactly what happened to
/// `.groundgoto`'s 114 lines.
pub(crate) fn travel_mode(medium: TravelMedium) -> TravelMode {
    match medium {
        TravelMedium::Any => TravelMode::Any,
        TravelMedium::Ground => TravelMode::Ground,
        TravelMedium::Air => TravelMode::Air,
    }
}

/// The profile's shared coordinate pool (§6.4, §7.1), holding each distinct `(map_id, x, y, z)`
/// exactly once.
///
/// Interning is a **pool** operation and never a route operation: a route that re-crosses a point
/// repeats the *index*, so a route's length is always the number of movement lines that produced
/// it. Collapsing repeats would delete the second half of every `#loop` circuit, and a circuit whose
/// last point no longer returns to its first has stopped being a circuit.
///
/// (The separate route-level collapse §2.6 and §8 call for — one source step emitting the same
/// coordinate twice, as both a 4-argument and a 5-argument line — is a later deliverable. Nothing
/// here does it.)
#[derive(Debug, Clone, Default)]
pub struct WaypointPool {
    points: Vec<Point>,
}

impl WaypointPool {
    /// Index of `point` in the pool, appending it if this is its first appearance.
    ///
    /// Identity is [`Point`]'s own `PartialEq`, because that is the relation the invariant is stated
    /// over and the relation `no_two_waypoint_pool_entries_hold_the_same_coordinate` checks. A hash
    /// key over `f32::to_bits` would disagree with it about `+0.0` versus `-0.0`. The scan is linear
    /// in the pool — measured, the whole corpus interns to 4,190 distinct points, so this is a few
    /// hundred million `f32` comparisons across a full offline compile and never runs in-game.
    pub fn intern(&mut self, point: Point) -> u32 {
        if let Some(index) = self.points.iter().position(|held| *held == point) {
            return index as u32;
        }
        self.points.push(point);
        (self.points.len() - 1) as u32
    }

    /// The pooled points, in first-seen order. Route indices are positions in this slice.
    pub fn points(&self) -> &[Point] {
        &self.points
    }

    /// Consume the pool, yielding
    /// [`RuntimeProfile::waypoint_pool`](sentinel_models::kernel::RuntimeProfile::waypoint_pool).
    pub fn into_points(self) -> Vec<Point> {
        self.points
    }
}

/// Lower one run of movements into its [`Route`]s, interning their points into `pool`.
///
/// **This is the compiler's only route builder.** Everything a route is — its
/// [`kind`](Route::kind), its [`mode`](Route::mode), its indices, its radii, and where one route
/// ends and the next begins — is decided here and nowhere else. `task_graph::flush_route` used to
/// decide two of those itself, with a hardcoded `mode: TravelMode::Any`, while this function's
/// medium logic sat behind an entry point no compile ever reached.
///
/// # Zero routes, one, or several
///
/// **Zero** is a run that resolved to no point at all, and it is not an error. The importer emits a
/// travel action with `position: None` for a coordinate it refused — an unmappable zone, a malformed
/// arity — so a run can survive gate resolution and still name nowhere to go. An `Op::Travel` over an
/// empty route is not a smaller instruction, it is an unsatisfiable one: the runner has nothing to
/// walk to, the task cannot complete, and `Travel` enters the §5.4 tag census for a task that never
/// travels. §7.3.3's tasks 4 and 5 print `ops: []` for exactly this shape.
///
/// **Several** is a run that changes travel medium partway. [`Route`] carries a single
/// [`mode`](Route::mode), and the three ways to lower `.groundgoto` immediately followed by `.goto`
/// are: flatten to one medium (drops the `.groundgoto`'s whole reason for existing — it *overrides*
/// the engine's preferred line where that line threads mountain paths, caves and stairs, §5.7),
/// refuse (measured: 9 of the corpus's 277 guide blocks then produced no artifact at all, ~1,675
/// Travel ops lost, to yield `ground=3, air=0` corpus-wide), or **split**. A medium change is a run
/// boundary exactly as an intervening op already is: `The Burning Crusade.lua:8158-8159` is
/// `.groundgoto Terokkar Forest,43.46,22.31,20,0` then `.goto Terokkar Forest,43.40,22.10`, which
/// says "climb the tower on the ground, then travel to there" — two routes, not a contradiction.
/// All 27 mixed runs in the corpus are in that file and every one of them splits, so there is no
/// unsplittable case left and no `MixedTravelModes` error to raise.
///
/// # The kind
///
/// §5.7 draws it from the step and the segment, not from geometry:
///
/// * `#loop` ⇒ [`Circuit { close: true }`](RouteKind::Circuit) (1,661 uses, §4.3). `close` states
///   the *cycling intent* rather than a geometric property: §7.3.3 prints `close: true` for both of
///   its circuits and only one returns to its first point — `A-11-23.lua:231` closes onto `:215`,
///   `:254` ends elsewhere. A geometric test would disagree with the specification on the second and
///   silently reclassify any circuit whose author left the last hop to the engine. A `#loop` step
///   whose run splits yields one `Circuit` per segment: the cycling intent is the *step's*, and each
///   medium-homogeneous leg of it is still walked repeatedly.
/// * a single point ⇒ [`Destination`](RouteKind::Destination) — the 16,231 three-argument `.goto`
///   lines where the coordinate is just where the NPC stands and the navmesh paths there better than
///   a 2004-era waypoint chain.
/// * anything longer ⇒ [`Corridor`](RouteKind::Corridor) — ordered points the engine *may* smooth
///   between, which is exactly what a `Circuit` may not do.
///
/// The kind is decided per **segment**, not per run: the one-line tail of a split run is a
/// `Destination`, because that is what it is once the medium boundary has been drawn.
pub fn lower_route(
    looping: bool,
    movements: &[Movement],
    pool: &mut WaypointPool,
) -> Vec<Route> {
    let mut routes = Vec::new();
    // Points are interned in authored order, segment by segment, so a pool index still reflects the
    // order the guide wrote its coordinates in and a split never reorders the pool.
    let mut segment_start = 0usize;
    while segment_start < movements.len() {
        let mode = movements[segment_start].mode;
        let segment_end = movements[segment_start..]
            .iter()
            .position(|movement| movement.mode != mode)
            .map(|offset| segment_start + offset)
            .unwrap_or(movements.len());
        let segment = &movements[segment_start..segment_end];

        let mut points = Vec::with_capacity(segment.len());
        let mut radii = Vec::with_capacity(segment.len());
        for movement in segment {
            points.push(pool.intern(movement.point));
            radii.push(movement.radius);
        }

        let kind = if looping {
            RouteKind::Circuit { close: true }
        } else if points.len() <= 1 {
            RouteKind::Destination
        } else {
            RouteKind::Corridor
        };

        routes.push(Route { kind, mode, points, radii });
        segment_start = segment_end;
    }
    routes
}
