//! C6: the combat policy — a profile-level default plus the per-task override that differs from it.
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §5.6 (C6 and its corpus mapping table), §7.1
//! ([`CombatPolicy`](k::CombatPolicy), [`ProfileDefaults`](k::ProfileDefaults)), §5.4.1 / §5.8
//! ([`NpcRef::expect_name`](k::NpcRef) and the first-touch probe), §7.3.3 (the three lowered
//! policies, and the four tasks that carry none).
//!
//! # What the artifact holds, and what it does not
//!
//! A policy says *what* combat may fight and *how much initiative* it may take. It does not say how
//! to fight: that is the combat service's, which is the whole content of C6. So everything below is
//! a classification of the authored step, never a tactic.
//!
//! # The stance rule
//!
//! §5.6's table maps `.mob` to `Objective` and `#loop` + `.mob` + `.complete` to `Aggressive`
//! ("a grind circuit *wants* pulls"). §7.3.3 then shows a third case the table does not cover:
//! task 4 is `Aggressive` with **no combat command at all**, because its completion is
//! `.xp 10+6760 >> Grind to 6760+/7600xp` and nothing but killing can satisfy an experience
//! threshold. The generalisation that produces all three — and that is not three special cases — is
//! *what the task's completion requires*:
//!
//! * a completion that cannot advance without killing ⇒ [`Aggressive`](k::CombatStance::Aggressive)
//!   — an experience threshold, or a `#loop` circuit whose `.mob` whitelist is what advances its
//!   `.complete` objective;
//! * a step that merely names combat targets ⇒ [`Objective`](k::CombatStance::Objective), which
//!   §5.6 defines as killing only what blocks the objective and refusing adds;
//! * anything else ⇒ the profile default.
//!
//! # `.unitscan` is a target as well as a watch
//!
//! §7.3.3 task 2 (`A-11-23.lua:243-260`) carries **no** `.mob` — its one combat command is
//! `.unitscan Rabid Thistle Bear` — and the fixture still puts 2164 in `targets` *and* in
//! `watch_units`. A unit worth noticing is a unit this task fights; `watch_units` is the subset
//! §5.6 describes as "roamers/rares to notice", not a separate population.
//!
//! # The magnitudes are not all derived, and the ones that are not say so
//!
//! `leash_yards` on a circuit is §5.6's own "leash from route radius" and comes from the route the
//! task walks. The profile **default** leash of 40 does not: ADR 07 §9 item 25 records that it
//! "appears only inside §7.3.3's listing" and asks for it to be chosen deliberately later. It is
//! [`DEFAULT_LEASH_YARDS`] here, named and cited, rather than an unexplained literal.

use sentinel_models::authoring::KillTargetAction;
use sentinel_models::kernel as k;

/// The profile-level leash, in yards (§7.3.3's `defaults.combat`).
///
/// **Illustrative, not derived.** ADR 07 §9 item 25: "`leash_yards: 40` and `budget_ticks: 60`
/// appear only inside §7.3.3's listing … A leash distance and an escalation budget are behavioural
/// constants that belong in §5.6 and §5.1.2 with a justification, not in a worked example. Until
/// they are chosen deliberately, treat the printed values as illustrative." Named here so the day
/// somebody chooses one there is exactly one place to change.
pub const DEFAULT_LEASH_YARDS: u16 = 40;

/// The profile-level combat policy every [`Task::combat`](k::Task::combat) is measured against
/// (§7.1, §5.6).
///
/// `Defensive` with an empty whitelist is §5.6's own "no combat token" row, and it is the value
/// 16,438 of the corpus's 23,894 tasks resolve to.
pub(crate) fn profile_default() -> k::CombatPolicy {
    k::CombatPolicy {
        stance: k::CombatStance::Defensive,
        targets: Vec::new(),
        watch_units: Vec::new(),
        leash_yards: DEFAULT_LEASH_YARDS,
        // §7.3.3's `defaults.combat`. A `Defensive` stance already refuses to *start* a fight, so
        // the flag governs only what happens once one has started, and refusing adds there means
        // standing next to a second attacker doing nothing.
        allow_adds: true,
        // `.solo` (13), `.group [n]` (190) and `.dungeon` (1,351) are §5.6's other three rows and
        // none of them reaches this compiler yet, so every artifact so far is a solo one.
        expect_group: k::GroupExpectation::Solo,
    }
}

/// The per-task override, or `None` when the task wants exactly the profile default.
///
/// # Why `None` rather than a copy
///
/// §5.6's scope decision, restated: 16,438 of 23,894 corpus tasks carry no combat token, so
/// emitting a policy on every task would put a byte-for-byte copy of `defaults.combat` on
/// two-thirds of the artifact. `None` is not "no policy" — it is "the profile's" (§7.1) — so the
/// comparison against the default is the whole emission rule, and a task whose derivation happens
/// to land on the default carries nothing. §7.3.3's four policy-less tasks are exactly that case.
///
/// `kills` are the step's surviving `.mob` / `.unitscan` payloads, `looping` is its `#loop`, and
/// `ops` are the ops this task actually emitted — the last two are properties of the *lowered*
/// task, which is why this is called from the task graph rather than from an action walk.
pub(crate) fn lower_combat(
    kills: &[KillTargetAction],
    looping: bool,
    complete_when: Option<&k::Predicate>,
    ops: &[k::Op],
) -> Option<k::CombatPolicy> {
    let default = profile_default();
    let mut targets: Vec<k::NpcRef> = Vec::new();
    let mut watch_units: Vec<k::NpcRef> = Vec::new();
    let mut named_a_mob = false;

    for kill in kills {
        named_a_mob |= !kill.watch;
        for creature in &kill.creatures {
            let reference = k::NpcRef {
                entry: creature.entry,
                expect_name: creature.name.clone(),
                // Nothing in the corpus says where a `.mob` stands, and the route the task walks is
                // not the creature's spawn point. §7.3.3 prints `pos: null` for all three of its
                // whitelists.
                pos: None,
            };
            if kill.watch && !watch_units.contains(&reference) {
                watch_units.push(reference.clone());
            }
            if !targets.contains(&reference) {
                targets.push(reference);
            }
        }
    }

    let stance = stance_for(kills, looping, complete_when, named_a_mob, default.stance);
    let policy = k::CombatPolicy {
        stance,
        targets,
        watch_units,
        leash_yards: leash_for(looping, ops).unwrap_or(default.leash_yards),
        allow_adds: match stance {
            // "A grind circuit *wants* pulls" (§5.6). Refusing adds on a farm loop is refusing the
            // work the loop exists to do.
            k::CombatStance::Aggressive => true,
            // §5.6: `Objective` "kills only what blocks the objective and refuses adds".
            k::CombatStance::Objective => false,
            _ => default.allow_adds,
        },
        expect_group: default.expect_group,
    };

    (policy != default).then_some(policy)
}

/// How much initiative this task's own content justifies.
fn stance_for(
    kills: &[KillTargetAction],
    looping: bool,
    complete_when: Option<&k::Predicate>,
    named_a_mob: bool,
    default: k::CombatStance,
) -> k::CombatStance {
    // Whether the completion is an experience threshold — the `.xp` grind step (`A-11-23.lua:271`,
    // `.xp 10+6760 >> Grind to 6760+/7600xp`). Both predicates count: `XpAtLeast` is what §7.3.3
    // prints and `LevelAtLeast` is what the `.xp` lowering emits today, and they are the same
    // instruction at two precisions. Nothing but killing advances either.
    let grinds_experience = matches!(
        complete_when,
        Some(k::Predicate::XpAtLeast { .. } | k::Predicate::LevelAtLeast { .. })
    );
    // §5.6's 1,661-use row, spelled out: a `#loop` circuit whose `.mob` whitelist is what advances
    // its `.complete` objective. All three conjuncts are load-bearing — `#loop` without `.mob` is a
    // patrol, `.mob` without `#loop` is a single objective pull, and either without a `.complete`
    // is not farming anything.
    let farms_an_objective = looping
        && named_a_mob
        && matches!(complete_when, Some(k::Predicate::QuestObjective { .. }));

    if grinds_experience || farms_an_objective {
        k::CombatStance::Aggressive
    } else if !kills.is_empty() {
        // §5.6's 7,456-use row. Reached by `.unitscan` too: task 2 of §7.3.3 has no `.mob` and the
        // fixture still gives it `Objective`.
        k::CombatStance::Objective
    } else {
        default
    }
}

/// §5.6's "leash from route radius", in yards, or `None` when this task authored no circuit.
///
/// # Only a circuit, and only its own radii
///
/// A leash is how far combat may chase from the work, and on a `#loop` grind the work *is* the
/// route — the radius the author put on each waypoint is the width of the farm. The largest of them
/// is the reduction, because a leash narrower than the circuit refuses fights at the far end of it.
///
/// A `Destination`'s arrival radius is not a leash and must not become one. Three-argument `.goto`
/// lines author no radius at all and the importer gives them a 5-yard arrival default
/// (`DEFAULT_ARRIVAL_RADIUS_YARDS`), so reading a radius off every task would leash 16,231 corpus
/// steps to five yards — an objective step refusing to fight the creature it is standing next to.
/// Hence the `#loop` condition, which is exactly the condition §5.6's table states.
///
/// A circuit whose radii are all zero (three of §7.3.3 task 0's seventeen points are) yields `None`
/// rather than `0`: "zero yards" as a leash is a policy that can never fight, and a circuit that
/// authored no width has not said how wide the farm is.
fn leash_for(looping: bool, ops: &[k::Op]) -> Option<u16> {
    if !looping {
        return None;
    }
    ops.iter()
        .filter_map(|op| match op {
            k::Op::Travel { route } => route.radii.iter().copied().max(),
            _ => None,
        })
        .max()
        .filter(|radius| *radius > 0)
}
