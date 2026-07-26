//! RED: the scheduler band is a **bounded** value, and today nothing bounds it.
//!
//! ADR `07_RUNTIME_PROFILE_SCHEMA` §7.2 constrains `Lifetime::Background::band` to
//! `{ "type": "integer", "minimum": 30, "maximum": 49 }` — the Goal band of §5.3. `shared/src/
//! kernel/task.rs::Lifetime` types it as a `u8` and says so out loud: *"R1 does not enforce the
//! range; §7.2's schema does, and the compiler that assigns the band is R2's concern."*
//!
//! # The hole
//!
//! §7.2's schema does **not** enforce it either, because the schema is generated from the struct
//! and a `u8` carries no bound. `kernel_schema.rs::lifetime_band_range_is_not_expressed_by_the_
//! generated_schema` asserts that absence as a recorded R1 limitation — it is an honest statement
//! about today, and it is not the problem. The problem is that it is the **only** statement: with
//! the range unexpressed in the schema, unenforced by the type, and unchecked on load, `band: 200`
//! is a legal artifact everywhere in this repository. It round-trips, it validates, it loads, and
//! the entire suite stays green.
//!
//! What band 200 does at runtime is not subtle. The bands are a total order over lease priority:
//! the 20s are opportunistic work, the 30s-40s are goals, and the 90s are the safety net — the one
//! `#ignorecorpse` exists to switch off so that deliberate death can work at all (§8). A sticky
//! patrol at band 200 outranks the safety net. It holds MOVEMENT through a corpse run, through
//! combat, through everything, and it got there from one arithmetic slip in the per-task offset
//! that §5.3 requires ("offset by task order so two sticky tasks cannot deadlock").
//!
//! # Why the refusal belongs on the wire and not only in the compiler
//!
//! `compiler/tests/kernel_task_graph.rs::every_emitted_background_band_sits_inside_the_goal_band`
//! is the other half: it pins that the lowering never *emits* an out-of-range band. That half alone
//! is insufficient. A profile is a JSON file on disk that outlives the compiler that wrote it; §6.5
//! versions it precisely because artifacts are loaded by code that did not produce them. A
//! hand-edited artifact, an artifact from an older compiler, or an artifact from a future one walks
//! straight past a compiler-side check. C4 is fail-closed (§5.4): the model refuses what it cannot
//! execute, at the boundary.
//!
//! # WHAT THESE TESTS CANNOT SEE
//!
//! * **They do not say which mechanism enforces the bound.** A validating `Deserialize`, a `Band`
//!   newtype with a `TryFrom<u8>`, or a whole-profile `validate()` called by the loader would each
//!   satisfy them. That is deliberate — the assertion is on behaviour at the wire boundary, and
//!   picking the mechanism here would prejudge a model change these tests have no business making.
//! * **They cannot see the ORDERING rule.** §5.3 requires the band to be offset by task order so
//!   two sticky tasks cannot deadlock; §7.3.3 shows 34 then 35 for two stickies and 30 for a
//!   ride-along. A profile whose every `Background` sat at band 30 satisfies every assertion below
//!   and reintroduces exactly the deadlock the offset exists to prevent. Nothing in this repository
//!   tests that rule.
//! * **They cannot see whether 30..=49 is the RIGHT range.** It is transcribed from §7.2. If the
//!   ADR is wrong about where the Goal band sits relative to the 90s safety net, these tests are
//!   wrong with it, in the same direction.
//! * **They do not touch `RuntimeProfile`.** The refusal is asserted on `Lifetime` alone. A loader
//!   that reconstructed a profile without going through `Lifetime`'s deserializer — there is no such
//!   path today — would not be covered.
//!
//! # Note for whoever closes this
//!
//! Enforcing the bound in a way that also reaches the **generated schema** (a `schemars`-annotated
//! newtype, say) will falsify `kernel_schema.rs::lifetime_band_range_is_not_expressed_by_the_
//! generated_schema`, which currently asserts `minimum` is absent. That test records a limitation,
//! not a desired property; update it in the same change rather than routing around it. Enforcing
//! the bound only at deserialization leaves it untouched and still closes this hole.

use serde_json::json;

use sentinel_models::kernel::{Channel, Lifetime, Predicate};

/// The `terminate_on` every case below shares: §7.3.3's task 6 uses `InArea { area: 442 }`, from
/// `A-11-23.lua:275` `.subzone 442 >> Travel to Auberdine`. Any well-formed predicate would do; a
/// real one is used so a failure is never about the payload beside the band.
fn terminate_on() -> serde_json::Value {
    json!({ "type": "InArea", "payload": { "area": 442, "kind": "SubArea" } })
}

fn background_with(band: i64) -> serde_json::Value {
    json!({
        "type": "Background",
        "payload": {
            "channels": ["MOVEMENT"],
            "band": band,
            "terminate_on": terminate_on(),
        }
    })
}

/// A band above the Goal band outranks the band 90-99 safety net.
///
/// **RED.** `band` is a `u8`, so serde accepts 200 and every downstream check accepts it too.
#[test]
fn a_scheduler_band_above_the_goal_band_is_refused_on_the_wire() {
    let value = background_with(200);
    let outcome = serde_json::from_value::<Lifetime>(value.clone());
    assert!(
        outcome.is_err(),
        "ADR 07 §7.2 pins the band to 30..=49; a task at band 200 outranks the safety net \
         `#ignorecorpse` exists to switch off, and holds its channels through a corpse run. \
         Loaded anyway as: {:?}",
        outcome.ok()
    );
}

/// A band below the Goal band loses every lease it should win.
///
/// The mirror case, and not redundant: an off-by-one in the per-task offset walks *down* as readily
/// as up, and a clamp-to-max fix that only guards the ceiling passes the test above while leaving a
/// patrol at band 12 permanently outranked by opportunistic work.
///
/// **RED**, same cause.
#[test]
fn a_scheduler_band_below_the_goal_band_is_refused_on_the_wire() {
    for band in [0, 29] {
        let outcome = serde_json::from_value::<Lifetime>(background_with(band));
        assert!(
            outcome.is_err(),
            "band {band} sits below ADR 07 §7.2's Goal band of 30..=49, where opportunistic work \
             outranks it and the patrol never gets a lease. Loaded anyway as: {:?}",
            outcome.ok()
        );
    }
}

/// The first band outside the range, on each side. `29` and `50` are the values an inclusive/
/// exclusive mix-up produces, and they are the ones a range check written as `30..49` gets wrong.
///
/// **RED.**
#[test]
fn the_bands_immediately_outside_the_goal_band_are_refused() {
    for band in [29, 50] {
        let outcome = serde_json::from_value::<Lifetime>(background_with(band));
        assert!(
            outcome.is_err(),
            "ADR 07 §7.2's range is INCLUSIVE at both ends — `minimum: 30, maximum: 49` — so \
             {band} is outside it. Loaded anyway as: {:?}",
            outcome.ok()
        );
    }
}

/// Both endpoints, and the two §7.3.3 uses in between, must keep loading.
///
/// This is the guard against over-tightening: a fix that refused 49, or that hardcoded §7.3.3's
/// observed 30/34/35 as the allowed set, would satisfy every assertion above and reject a legal
/// artifact. `band: 30` is §7.3.3's ride-along task 6; `34` and `35` are its two sticky patrols,
/// tasks 0 and 2.
///
/// **Expected GREEN today**, and it must stay green.
#[test]
fn every_band_inside_the_goal_band_still_loads() {
    for band in [30, 34, 35, 49] {
        let value = background_with(band);
        let outcome = serde_json::from_value::<Lifetime>(value);
        let Ok(lifetime) = outcome else {
            panic!(
                "band {band} is inside ADR 07 §7.2's 30..=49 and must load, got: {:?}",
                outcome.err()
            )
        };
        let Lifetime::Background {
            channels,
            band: loaded,
            ..
        } = lifetime
        else {
            panic!("a Background payload must load as Background, got: {lifetime:?}")
        };
        assert_eq!(loaded, band as u8, "the band must survive the round trip");
        assert_eq!(
            channels,
            vec![Channel::Movement],
            "the channel set must survive the round trip, got: {channels:?}"
        );
    }
}

/// The refusal must not be bought by breaking the round trip: a `Background` built in Rust with a
/// legal band still serializes to §7.2's shape and reloads unchanged.
///
/// **Expected GREEN today.** It exists because the cheapest way to make the three refusal tests
/// above pass is a custom `Deserialize` that quietly disagrees with the derived `Serialize` — and
/// an artifact that cannot reload what it just wrote is a worse failure than the one being fixed.
#[test]
fn a_legal_background_still_round_trips_through_json() {
    let lifetime = Lifetime::Background {
        channels: vec![Channel::Movement],
        band: 34,
        terminate_on: Predicate::QuestTurnedIn { id: 983 },
    };

    let value = serde_json::to_value(&lifetime)
        .unwrap_or_else(|err| panic!("a Background lifetime must serialize, got: {err:?}"));
    assert_eq!(
        value["payload"]["band"],
        json!(34),
        "§7.2 puts the band inside the adjacent-tagging payload, got: {value}"
    );

    let reloaded: Lifetime = serde_json::from_value(value.clone())
        .unwrap_or_else(|err| panic!("what the model wrote, the model must read, got: {err:?}\n{value}"));
    assert_eq!(reloaded, lifetime, "the round trip must be lossless");
}
