//! Serialize-time finite-float guards for the artifact's `f32` fields (C4, ADR
//! `07_RUNTIME_PROFILE_SCHEMA` §5.4).
//!
//! JSON has no spelling for infinity or NaN, and `serde_json`'s answer is to write `null`. That
//! degrades two different ways and neither is acceptable under refuse-don't-degrade:
//!
//! * **`Option<f32>`** — [`Point::z`](crate::kernel::Point::z) — `Some(non-finite)` is written as
//!   `null` and read back as `None`. The value is gone and *nothing fails*. §5.7 has the compiler
//!   fill `z` from a navmesh probe, i.e. from exactly the kind of source that can hand back a
//!   non-finite answer.
//! * **Bare `f32`** — the two coordinates and the three predicate operands — the non-finite is
//!   written as `null` and then fails to load (`invalid type: null`). The refusal is correct but it
//!   lands on the *consumer*; the producer wrote an unloadable artifact and was told nothing.
//!
//! The fix follows the [`magic`](super::ids::magic) codec precedent (§6.2.5): report it as a
//! **serialization** error rather than emit a file that cannot be read back.
//!
//! Only serialization is guarded. There is deliberately no matching deserialize hook: JSON cannot
//! carry a non-finite number in the first place, a `null` in a bare `f32` field already fails on the
//! way in, and a `null` in `Point::z` legitimately means `None`.
//!
//! Six field slots across five names are guarded — [`Point::x`](crate::kernel::Point::x),
//! [`Point::y`](crate::kernel::Point::y), [`Point::z`](crate::kernel::Point::z),
//! `Predicate::AtLocation::radius`, `Predicate::CooldownCmp::secs` and
//! `Predicate::ItemStatCmp::value`. They are the complete set of `f32` fields in this module tree;
//! a guard on one leaves the rest degrading.

use serde::Serializer;

/// Serializes a finite `f32`, refusing `+inf`, `-inf` and `NaN` at write time.
///
/// For `#[serde(serialize_with = "…")]` on a bare `f32` field.
pub fn serialize<S>(value: &f32, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    if !value.is_finite() {
        return Err(serde::ser::Error::custom(non_finite_message(*value)));
    }
    serializer.serialize_f32(*value)
}

/// Serializes an optional finite `f32`, refusing a non-finite `Some` at write time.
///
/// For `#[serde(serialize_with = "…")]` on an `Option<f32>` field. `None` still writes `null`, which
/// is what §7.2 types as the "compiler could not resolve it" case.
pub fn serialize_option<S>(value: &Option<f32>, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    match value {
        Some(inner) => serialize(inner, serializer),
        None => serializer.serialize_none(),
    }
}

/// The diagnostic a producer sees, naming the value and why it cannot be written.
fn non_finite_message(value: f32) -> String {
    let what = if value.is_nan() {
        "NaN"
    } else if value > 0.0 {
        "+inf"
    } else {
        "-inf"
    };
    format!(
        "kernel artifact floats must be finite; got {what}. JSON cannot spell it, so \
         serialization would write `null` and the value would be lost or the artifact would fail \
         to load (C4, ADR 07 §5.4)"
    )
}
