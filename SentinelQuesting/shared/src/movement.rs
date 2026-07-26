//! The **one** coordinate transform: the comma-separated fields of a RestedXP movement line in,
//! a world coordinate out (ADR `07_RUNTIME_PROFILE_SCHEMA` §2.6, §5.7, §7.1).
//!
//! # Why this is a module and not a function on either side
//!
//! It used to be two implementations. `sentinel-importer` had
//! `project_builder::build_travel_position`, which every compile ran, and `sentinel-compiler` had
//! `kernel::route::parse_movement`, which **nothing** ran — a complete second lowering with the `/`
//! discrimination, the arity refusal and the raw-world pass-through that the live one lacked
//! entirely. The live one handed field 0 straight to [`zone_map_for`], so all 929 raw-world corpus
//! lines matched no zone and were dropped, while twelve tests over the dead one stayed green.
//!
//! Both call this now, and neither owns a copy.
//!
//! # The input
//!
//! The **already-split** fields: `["Darkshore", "40.77", "78.56", "40", "0"]`. Splitting is not
//! this module's job because the two callers reach it from different places — the importer's lexer
//! has already stripped the `>>` display tail and the `--` dev comment
//! ([`crate::source::strip_inline_dev_comment`]) and split on commas by the time a command exists at
//! all. Re-doing that here would be the third copy of a lexical rule, which is the defect this
//! module exists to remove.

use crate::zone::zone_map_for;

/// A movement line's resolved destination: the continent the navmesh and the server use, plus a
/// world coordinate in that frame.
///
/// Carries no `z`. The corpus never authors one — the optional third numeric of `.goto` is an
/// *arrival radius* (§5.7) — and neither artifact model wants a guessed height: the ADR-05
/// `Position` writes a structural `0.0` and the ADR-07 [`Point`](crate::kernel::Point) writes
/// `None`, both meaning "the engine ground-snaps this". Baking the radius as `z` once buried
/// waypoints ~35 yd inside terrain and wedged travel in `awaiting_path` forever.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ResolvedCoordinate {
    /// Continent/map id — Eastern Kingdoms `0`, Kalimdor `1`, Outland `530`. Never a UiMapID: those
    /// are lookup keys and §2.6 says one must not survive the lookup.
    pub map_id: u32,
    /// World X. The **second** authored value in both coordinate systems.
    pub x: f32,
    /// World Y. The **first** authored value in both coordinate systems.
    pub y: f32,
}

/// Why a movement line resolved to nowhere. Each caller renders this in its own vocabulary — an
/// importer [`Diagnostic`](crate::authoring::Diagnostic), a compiler `LoweringError` — but the
/// decision itself is made once, here.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoordinateError {
    /// Not `3..=5` fields. The corpus holds 16,254 three-field, 5,452 four-field and 17,022
    /// five-field movement lines, and 67 six-field ones which are **three distinct defects**
    /// (a stray trailing `0`, a comma-typed decimal, a stray leading `0`) whose repairs contradict
    /// each other. Refuse; do not guess.
    Arity { found: usize },
    /// Field 0 carried no `/` and names no row of [`ZONE_TABLE`](crate::zone::ZONE_TABLE). ADR 06
    /// invariant 3: a percentage must never survive compilation, so this is no coordinate rather
    /// than a raw percentage wearing a map id.
    UnknownZone { zone: String },
    /// A field that must be numeric was not. `what` names the field so the diagnostic can say which.
    MalformedNumber { what: &'static str, value: String },
}

/// Resolve one movement line's fields to a world coordinate.
///
/// # The discrimination
///
/// Field 0 spells one of two coordinate systems and **the `/` is the only signal**:
///
/// | field 0 | system | operation |
/// | --- | --- | --- |
/// | `Darkshore` / `1439` | zone-relative percentages, both axes `0..100` | transform via the measured [`zone table`](crate::zone) |
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
/// [`ZoneMap`](crate::zone::ZoneMap) documents and what the corpus corroborates: `A-11-23.lua:764`
/// and `:769` are consecutive steps clicking two objects on the same Darkshore beach, authored one
/// in each system, and they lower 385 yd apart under this ordering and 6,911 yd apart under the
/// reverse.
///
/// # Arity is checked first
///
/// Before anything is looked up or parsed. The order matters: three of the six-argument corpus
/// lines name zones that resolve, so an unknown-zone refusal — or worse, a successful lookup — would
/// be the wrong answer to a line that is malformed however it is read.
pub fn resolve_coordinate<S: AsRef<str>>(
    fields: &[S],
) -> Result<ResolvedCoordinate, CoordinateError> {
    if !(3..=5).contains(&fields.len()) {
        return Err(CoordinateError::Arity { found: fields.len() });
    }
    let field = |index: usize| fields[index].as_ref().trim();

    let first = number(field(1), "first authored coordinate (world Y)")?;
    let second = number(field(2), "second authored coordinate (world X)")?;

    match field(0).split_once('/') {
        // Raw world: `<uiMapId>/<mapId>`. The number *after* the slash is the continent the navmesh
        // and server use — `1944/530` is an Outland ui map on continent 530 — and the ui map id is
        // never a resolved `map_id`.
        Some((_ui_map, map)) => Ok(ResolvedCoordinate {
            map_id: integer(map, "map id")?,
            x: second,
            y: first,
        }),
        // Zone-relative percentages, by name (`Darkshore`, 35,449 uses) or by ui map id (`1439`,
        // 1,765 uses) — the table answers to both spellings.
        None => {
            let zone = zone_map_for(field(0)).ok_or_else(|| CoordinateError::UnknownZone {
                zone: field(0).to_owned(),
            })?;
            let (x, y) = zone.to_world(first, second);
            Ok(ResolvedCoordinate { map_id: zone.continent, x, y })
        }
    }
}

/// Parse a coordinate. `f32` is the artifact's own width (§7.1), so parsing wider would only hide
/// the precision the model actually has.
fn number(text: &str, what: &'static str) -> Result<f32, CoordinateError> {
    text.parse::<f32>()
        .ok()
        .filter(|value| value.is_finite())
        .ok_or_else(|| CoordinateError::MalformedNumber { what, value: text.to_owned() })
}

fn integer<T: std::str::FromStr>(text: &str, what: &'static str) -> Result<T, CoordinateError> {
    text.parse::<T>()
        .map_err(|_| CoordinateError::MalformedNumber { what, value: text.to_owned() })
}

#[cfg(test)]
mod tests {
    //! # WHAT THESE TESTS CANNOT SEE
    //!
    //! Anything about an artifact. That a compile of a real guide reaches these answers is pinned
    //! end-to-end in `compiler/tests/kernel_coordinates.rs`, which drives `parse_guide` →
    //! `ProjectBuilder::build` → `Compiler::compile_kernel` over the same corpus lines. What is left
    //! here is the boundary: which shapes are refused, and with which error, before any caller gets
    //! a chance to render it.

    use super::*;

    #[test]
    fn arity_is_refused_before_the_zone_is_looked_up() {
        // `The Burning Crusade.lua:67691` — `.goto Silithus,51.60,16.40,70,0,0`. Silithus IS a
        // ZONE_TABLE row, so a lookup-first implementation lowers this line to a coordinate and the
        // stray sixth field vanishes without a word.
        let fields = ["Silithus", "51.60", "16.40", "70", "0", "0"];
        assert_eq!(
            resolve_coordinate(&fields),
            Err(CoordinateError::Arity { found: 6 }),
            "got: {:?}",
            resolve_coordinate(&fields)
        );
    }

    #[test]
    fn a_malformed_number_names_the_field_it_could_not_parse() {
        let fields = ["Darkshore", "40.77", "not-a-number"];
        assert_eq!(
            resolve_coordinate(&fields),
            Err(CoordinateError::MalformedNumber {
                what: "second authored coordinate (world X)",
                value: "not-a-number".to_owned(),
            }),
            "got: {:?}",
            resolve_coordinate(&fields)
        );
    }

    #[test]
    fn an_unmapped_zone_yields_no_coordinate_rather_than_a_percentage() {
        // ADR 06 invariant 3. Emitting the raw percentages once produced 522 travel actions aimed
        // at meaningless coordinates.
        let fields = ["Nowhereland", "40.77", "78.56"];
        assert_eq!(
            resolve_coordinate(&fields),
            Err(CoordinateError::UnknownZone { zone: "Nowhereland".to_owned() }),
            "got: {:?}",
            resolve_coordinate(&fields)
        );
    }
}
