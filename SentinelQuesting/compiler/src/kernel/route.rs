//! Coordinates: the two authored systems, the interned waypoint pool, and route lowering
//! (ADR `07_RUNTIME_PROFILE_SCHEMA` §5.7, §6.4, §7.1).

use sentinel_models::kernel::{Point, Route, RouteKind, TravelMode};
use sentinel_models::source::strip_inline_dev_comment;
use sentinel_models::zone::zone_map_for;

use super::{LoweringError, SourceLine};

/// One lowered movement line: where, how close, and by what medium.
///
/// The pool index is deliberately *not* here — interning is [`WaypointPool`]'s job, and a
/// [`Movement`] can be inspected without one.
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

/// The five coordinate-bearing commands and the medium each demands (§7.1, §5.7).
///
/// `.line` also carries coordinates but is variadic (arity 5..259) and is not a single movement;
/// lowering it is a separate deliverable.
fn travel_mode_for(command: &str) -> Option<TravelMode> {
    match command {
        ".goto" | ".waypoint" => Some(TravelMode::Any),
        ".groundgoto" => Some(TravelMode::Ground),
        ".flygoto" => Some(TravelMode::Air),
        _ => None,
    }
}

/// Lower one movement line to a world coordinate.
///
/// # The discrimination
///
/// Field 0 spells one of two coordinate systems and **the `/` is the only signal**:
///
/// | field 0 | system | operation |
/// | --- | --- | --- |
/// | `Darkshore` / `1439` | zone-relative percentages, both axes `0..100` | transform via the measured [`zone table`](sentinel_models::zone) |
/// | `1439/1` | `<uiMapId>/<mapId>`, already the server's frame | none at all |
///
/// A range test — "an axis inside 0..100 is a percentage" — is wrong and reclassifies real corpus
/// lines: `The Burning Crusade.lua:28542` is `.goto 1944/530,4341.30029,97.1`, raw world on Outland
/// with a second axis of 97.1. Measured, 15 of the corpus's 929 raw-world lines carry an axis inside
/// 0..100.
///
/// # The axis order
///
/// The first authored value is world **Y**, the second world **X**, in *both* systems. That is what
/// [`ZoneMap`](sentinel_models::zone::ZoneMap) documents and what the corpus corroborates:
/// `A-11-23.lua:764` and `:769` are consecutive steps clicking two objects on the same Darkshore
/// beach, authored one in each system, and they lower 385 yd apart under this ordering and 6,911 yd
/// apart under the reverse.
pub fn parse_movement(src: SourceLine<'_>) -> Result<Movement, LoweringError> {
    // Two markers introduce prose and neither is data: `>>` opens the display text and `--` opens a
    // dev comment. Both have to go before the comma split, or the prose is parsed as arguments —
    // `.goto Wetlands,4.61,57.26,15 >> Travel to the dock` looks like a six-argument line and lands
    // in the arity refusal, and `.goto 1439,42.017,58.866,0 --NE spawn` reads its arrival radius as
    // `0 --NE spawn`. 38 corpus movement lines carry a `--`.
    //
    // `SourceLine::text` is the line *verbatim*, so this function owns both strips; delegating one
    // of them upstream would make it total over lexed lines and partial over the input it documents
    // itself as taking. The `--` rule is `sentinel_models::source`'s, the same one the importer's
    // lexer applies — a second copy could drift. Order matches the importer: the display text is
    // split off first, then the dev comment, so a comment inside a `>>` tail never survives.
    let line = strip_inline_dev_comment(src.text.split(">>").next().unwrap_or("")).trim();

    let (command, args) = line
        .split_once(char::is_whitespace)
        .ok_or_else(|| not_a_movement(src))?;
    let mode = travel_mode_for(command).ok_or_else(|| not_a_movement(src))?;

    // Zone names contain spaces (`Un'Goro Crater`, `Burning Steppes`), so only the *first*
    // whitespace run separates the command from its arguments.
    let fields: Vec<&str> = args.trim().split(',').map(str::trim).collect();
    // Arity is checked before anything is looked up or parsed. The order matters: three of the six
    // -argument corpus lines name zones absent from the measured table, and an unknown-zone refusal
    // there would be the right answer for the wrong reason.
    if !(3..=5).contains(&fields.len()) {
        return Err(LoweringError::arity(src, fields.len()));
    }

    let first = number(src, fields[1], "first authored coordinate (world Y)")?;
    let second = number(src, fields[2], "second authored coordinate (world X)")?;

    let point = match fields[0].split_once('/') {
        // Raw world: `<uiMapId>/<mapId>`. The number *after* the slash is the continent the navmesh
        // and server use — `1944/530` is an Outland ui map on continent 530 — and the ui map id is
        // never a `Point::map_id`.
        Some((_ui_map, map)) => Point {
            map_id: integer(src, map, "map id")?,
            x: second,
            y: first,
            z: None,
        },
        // Zone-relative percentages. The artifact carries `ZoneMap::continent`, so a `Point` whose
        // `map_id` is 1439 is a percentage that survived compilation wearing a ui map id.
        None => {
            let zone = zone_map_for(fields[0]).ok_or_else(|| LoweringError::UnknownZone {
                file: src.file.to_owned(),
                line: src.line,
                text: src.text.to_owned(),
                zone: fields[0].to_owned(),
            })?;
            let (x, y) = zone.to_world(first, second);
            Point { map_id: zone.continent, x, y, z: None }
        }
    };

    // `.goto zone,x,y` authored no radius; `.goto zone,x,y,40` and `.goto zone,x,y,40,0` authored
    // 40. The fifth field is an arrival flag, not a coordinate. The artifact carries what was
    // authored — whether `0` means "zero yards" or "engine default" is the engine's question.
    let radius = match fields.get(3) {
        Some(text) => integer::<u16>(src, text, "arrival radius")?,
        None => 0,
    };

    Ok(Movement { point, radius, mode })
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

/// Lower a run of movement lines into one [`Route`], interning its points into `pool`.
///
/// **Refusal is total.** Every line is parsed before any is interned, so a route that fails leaves
/// the pool exactly as it found it. Interning a half-parsed line and *then* erroring would leave a
/// phantom entry that shifts every index authored after it — in a different task, compiled later,
/// with nothing to connect the two.
pub fn lower_route(
    kind: RouteKind,
    lines: &[SourceLine<'_>],
    pool: &mut WaypointPool,
) -> Result<Route, LoweringError> {
    let mut movements = Vec::with_capacity(lines.len());
    let mut mode: Option<TravelMode> = None;

    for src in lines {
        let movement = parse_movement(*src)?;
        match mode {
            None => mode = Some(movement.mode),
            Some(committed) if committed != movement.mode => {
                return Err(LoweringError::MixedTravelModes {
                    file: src.file.to_owned(),
                    line: src.line,
                    text: src.text.to_owned(),
                    found: movement.mode,
                    expected: committed,
                })
            }
            Some(_) => {}
        }
        movements.push(movement);
    }

    let mut points = Vec::with_capacity(movements.len());
    let mut radii = Vec::with_capacity(movements.len());
    for movement in movements {
        points.push(pool.intern(movement.point));
        radii.push(movement.radius);
    }

    Ok(Route {
        kind,
        // An empty run commits to nothing, so `Any` is the honest answer rather than a refusal:
        // whether an empty route is legal at all is the task lowering's question, not this one's.
        mode: mode.unwrap_or(TravelMode::Any),
        points,
        radii,
    })
}

fn not_a_movement(src: SourceLine<'_>) -> LoweringError {
    LoweringError::NotAMovement {
        file: src.file.to_owned(),
        line: src.line,
        text: src.text.to_owned(),
    }
}

/// Parse a coordinate. `f32` is the artifact's own width (§7.1), so parsing wider would only hide
/// the precision the model actually has.
fn number(src: SourceLine<'_>, text: &str, what: &str) -> Result<f32, LoweringError> {
    text.parse::<f32>()
        .ok()
        .filter(|value| value.is_finite())
        .ok_or_else(|| malformed_number(src, text, what))
}

fn integer<T: std::str::FromStr>(
    src: SourceLine<'_>,
    text: &str,
    what: &str,
) -> Result<T, LoweringError> {
    text.parse::<T>()
        .map_err(|_| malformed_number(src, text, what))
}

fn malformed_number(src: SourceLine<'_>, text: &str, what: &str) -> LoweringError {
    LoweringError::MalformedNumber {
        file: src.file.to_owned(),
        line: src.line,
        text: src.text.to_owned(),
        what: what.to_owned(),
        value: text.to_owned(),
    }
}
