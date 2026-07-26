//! The task graph: `#label`, `#requires`, `#completewith`, `#sticky` and `#optional` become
//! [`Task::deps`], [`Task::completion`], [`Task::lifetime`] and [`Task::blocking`].
//!
//! Authority: ADR `07_RUNTIME_PROFILE_SCHEMA` §5.3 ("Concurrency"), §7.1 ([`Task`]), §7.2 (the
//! `band` bound) and §7.3.3 (the worked example, whose eight tasks are the only place in the
//! repository that states what a lowered [`Lifetime::Background`] actually looks like).
//!
//! # Order, and why it is not negotiable
//!
//! 1. **Archetype gates first** ([`super::archetype`], C2). Every `<<` tail is decided against one
//!    concrete [`Archetype`] before anything is resolved, at **op** granularity — the corpus has
//!    3,052 command-level gates, and `A-1-11-Human.lua:185-196` is one ungated step holding six
//!    mutually exclusive class-gated `.accept`s, so a task-granular resolver gives a Warrior either
//!    all six letters or none.
//! 2. **Then the label symbol table**, built from the **survivors**. This is what "picking among
//!    gated duplicates by archetype" means in practice: `TBC:16256` `#label UldaLoch << Mage` and
//!    `TBC:16264` `#label UldaLoch` (on a `step << !Mage`) are two definitions of one name that only
//!    an archetype can separate, which is exactly why `LabelGraph::definitions` is a multimap that
//!    keeps both and ranks neither. Once gates are resolved, at most one of the pair is left and
//!    there is nothing to tie-break. A resolver that ran before gate resolution would have to
//!    tie-break by source order, and first-wins binds every non-Mage to the teleport step while
//!    last-wins binds every Mage to the gryphon step — both silent, both wrong.
//! 3. **Then `#requires`.** Each entry carries its **own** gate (`Gated<String>`), so gates are
//!    resolved per entry *first* and whatever survives is ANDed. That is what makes
//!    `TBC:24728/24729` (`cloth1` + `cloth2`, both ungated — a genuine AND) and `TBC:91092/91093`
//!    (`FlyMoongladeH << Horde` + `FlyMoongladeA << Alliance` — a faction-exclusive OR) both come
//!    out right, with no `Or` operator anywhere in the model.
//! 4. **Then `#completewith`**, which needs the whole block's symbol table: 2,670 of the corpus's
//!    2,788 label-valued links point **forward** — `TBC:103798` reaches back 1,219 lines, and most
//!    reach the other way — so a resolver that only knew what it had already emitted would resolve
//!    almost none of them.
//! 5. **Then `#sticky` / `#optional`** into [`Lifetime`] and `blocking`.
//! 6. **Elision and renumbering happen throughout, by construction**: ids are assigned from the
//!    surviving order and every id-bearing field is resolved *through* that order, never through the
//!    authored one. See [`assemble_tasks`].
//!
//! # Names do not reach the artifact
//!
//! `#label` is a compiler symbol table and nothing else. [`Task`] has no name field and none is
//! added: the kernel resolves by [`TaskId`], and a name that survives is a name something can still
//! look up at runtime — which is precisely the RXPGuides defect §3.1 describes, where
//! `guide.labels[…]` returns nil and the edge silently never fires.

use std::collections::HashMap;

use sentinel_models::authoring::{
    Action, ActionPayload, CompleteWithTarget, ConditionRole, Diagnostic, GuideGate, Operation,
    Project, Severity,
};
use sentinel_models::kernel as k;

use super::{archetype, lower_predicate, QuestMeta, WaypointPool};
use crate::CompilerError;

/// The band the first channel-holding background task claims, from ADR 07 §7.3.3: its two `#sticky`
/// patrols are bands **34** and **35**, in task order.
const FIRST_HOLDING_BAND: u8 = 34;

/// The band a `#completewith` ride-along claims, from ADR 07 §7.3.3 task 6.
///
/// Ride-alongs hold **no** channels, so they cannot deadlock against each other and do not need the
/// per-task offset that §5.3 requires of the holders. They all sit at the bottom of the Goal band,
/// below every patrol.
const RIDE_ALONG_BAND: u8 = 30;

/// One authored operation that survived C2 resolution, before task ids are assigned.
///
/// Ids cannot be assigned during resolution: an operation is elided *after* its ops are resolved, so
/// the surviving indices are not known until the whole project has been walked.
pub(crate) struct SurvivingStep {
    /// The ops whose gates the archetype satisfied, in authored order.
    ops: Vec<k::Op>,
    /// `#label` names this step defines, gate-satisfied ones only.
    labels: Vec<String>,
    /// `#requires` label names, gate-satisfied ones only, still raw.
    requires: Vec<String>,
    /// `#completewith` targets, gate-satisfied ones only, still raw.
    complete_with: Vec<CompleteWithTarget>,
    /// `#sticky` ⇒ a concurrent task.
    sticky: bool,
    /// `#optional` ⇒ `false`.
    blocking: bool,
    /// The step's own completion authority, baked from its `ConditionRole::Completion` actions.
    complete_when: Option<k::Predicate>,
    /// Whether the step applies at all, baked from its `ConditionRole::Applicability` actions.
    applies_when: Option<k::Predicate>,
    /// Items this step must keep, baked from the item objectives its `.complete` lines name.
    loot_filter: Vec<k::LootRule>,
    /// The source lines the authoring model happens to carry for this step, for provenance.
    lines: Option<(u32, u32)>,
}

/// Lower a whole project into the artifact's [`Task`](k::Task) list, for one resolved archetype.
///
/// The two phases are separate because they must be: nothing can be *resolved* until every step has
/// been *elided*, since `Task::id` is the index into the surviving list.
pub(crate) fn lower_task_graph(
    project: &Project,
    archetype: &k::Archetype,
    pool: &mut WaypointPool,
    meta: &dyn QuestMeta,
    diagnostics: &mut Vec<Diagnostic>,
) -> Result<Vec<k::Task>, CompilerError> {
    let survivors = resolve_operations(project, archetype, pool, meta, diagnostics)?;
    Ok(assemble_tasks(project, survivors, diagnostics))
}

/// Resolve `gate` against `archetype`, collecting whatever the resolver had to say.
///
/// `None` is "no gate", which applies to everyone — not to be confused with a gate that resolved to
/// [`GateOutcome::DoesNotApply`](archetype::GateOutcome::DoesNotApply).
fn gate_applies(
    gate: Option<&GuideGate>,
    archetype: &k::Archetype,
    diagnostics: &mut Vec<Diagnostic>,
) -> Result<bool, CompilerError> {
    let Some(gate) = gate else {
        return Ok(true);
    };
    let resolution = archetype::resolve_gate(gate, archetype)?;
    let applies = resolution.outcome == archetype::GateOutcome::Applies;
    diagnostics.extend(resolution.diagnostics);
    Ok(applies)
}

/// Walk the project's operations and keep the ones this archetype actually runs.
fn resolve_operations(
    project: &Project,
    archetype: &k::Archetype,
    pool: &mut WaypointPool,
    meta: &dyn QuestMeta,
    diagnostics: &mut Vec<Diagnostic>,
) -> Result<Vec<SurvivingStep>, CompilerError> {
    let mut survivors = Vec::new();

    for op in &project.operations {
        // The importer's flag, honoured rather than re-derived (`Operation::enabled`, 140 corpus
        // steps disabled by `skip`).
        if !op.enabled {
            continue;
        }
        if !gate_applies(op.gate.as_ref(), archetype, diagnostics)? {
            continue;
        }

        let mut step_applies = true;
        for directive in &op.directives {
            let resolution = archetype::resolve_directive(directive, archetype)?;
            let applies = resolution.outcome == archetype::GateOutcome::Applies;
            diagnostics.extend(resolution.diagnostics);
            if !applies {
                step_applies = false;
                break;
            }
        }
        if !step_applies {
            continue;
        }

        // Op granularity: each action carries its own gate, and one step's actions routinely
        // resolve differently from one another.
        let mut ops = Vec::new();
        let mut completion_terms = Vec::new();
        let mut applicability_terms = Vec::new();
        let mut loot_filter: Vec<k::LootRule> = Vec::new();
        let mut surviving_actions = 0usize;
        // The movement run currently open. Flushed into one `Op::Travel` by the first op-bearing
        // action that follows it, and again at the end of the step — see `flush_route`.
        let mut run: Vec<&Action> = Vec::new();
        for action in &op.actions {
            if !action.enabled {
                continue;
            }
            if !gate_applies(action.gate.as_ref(), archetype, diagnostics)? {
                continue;
            }
            surviving_actions += 1;

            // A `Condition` action is not an op: it is one of the task's three predicate slots, and
            // routing it through `lower_op` would file it under KERNEL_OP_NOT_LOWERED as though the
            // artifact had lost it.
            if let ActionPayload::Condition(condition) = &action.payload {
                let predicate = lower_predicate(&condition.expression, meta)?;
                match condition.role {
                    ConditionRole::Completion => {
                        collect_loot_rules(&predicate, meta, &mut loot_filter);
                        completion_terms.push(predicate);
                    }
                    ConditionRole::Applicability => applicability_terms.push(predicate),
                }
                continue;
            }

            if matches!(action.payload, ActionPayload::Travel(_)) {
                run.push(action);
                continue;
            }
            if !breaks_movement_run(&action.payload) {
                continue;
            }

            flush_route(&mut run, op.looping, &mut ops, pool, diagnostics);
            if let Some(lowered) = lower_op(action, diagnostics) {
                ops.push(lowered);
            }
        }
        flush_route(&mut run, op.looping, &mut ops, pool, diagnostics);

        // Elision. A task with nothing left to execute is not a task: emitting an empty one gives
        // the runner a step that can never complete and a cursor that never advances. Counted over
        // *surviving actions* rather than lowered ops, so a step is elided because this archetype
        // was gated out of it — never because this compiler cannot lower an action type yet.
        if surviving_actions == 0 {
            continue;
        }

        let mut labels = Vec::new();
        for label in &op.labels {
            if gate_applies(label.gate.as_ref(), archetype, diagnostics)? {
                labels.push(label.value.clone());
            }
        }
        let mut requires = Vec::new();
        for required in &op.requires {
            if gate_applies(required.gate.as_ref(), archetype, diagnostics)? {
                requires.push(required.value.clone());
            }
        }
        let mut complete_with = Vec::new();
        for entry in &op.complete_with {
            if gate_applies(entry.gate.as_ref(), archetype, diagnostics)? {
                complete_with.push(entry.value.clone());
            }
        }
        let blocking = match &op.optional {
            Some(optional) => !gate_applies(optional.gate.as_ref(), archetype, diagnostics)?,
            None => true,
        };

        survivors.push(SurvivingStep {
            ops,
            labels,
            requires,
            complete_with,
            sticky: op.sticky,
            blocking,
            complete_when: fold_and(completion_terms),
            applies_when: fold_and(applicability_terms),
            loot_filter,
            lines: authored_lines(op),
        });
    }

    Ok(survivors)
}

/// Conjoin a step's predicate terms, without wrapping a lone one.
///
/// A step may carry more than one `.complete` — §7.3.3 task 4 is the folded multi-`#requires` step
/// and its `complete_when` is an `And` over one objective predicate per predecessor. One term must
/// **not** become `And([term])`: §5.1.1 is explicit that there is to be one way to say one thing,
/// and a single-element conjunction is a second spelling of its own operand.
fn fold_and(mut terms: Vec<k::Predicate>) -> Option<k::Predicate> {
    match terms.len() {
        0 => None,
        1 => terms.pop(),
        _ => Some(k::Predicate::And(terms)),
    }
}

/// The span of source lines the authoring model carries for `op`, if any.
///
/// The authoritative answer is [`Operation::source_line_start`] / [`Operation::source_line_end`],
/// which the importer records from the `step` marker through the last line that belongs to the
/// step. §7.3.3's eight spans tile `A-11-23.lua:211-280` without a gap, and its task 4 ends on
/// `:268` — the author's bare `--XXREQ` comment, which is neither a directive nor a command.
///
/// The fallback below is the *old* derivation, over the gated directive entries, kept for a project
/// stored before those fields existed: a `Project` is a JSON file that outlives the compiler that
/// wrote it, and reading `None` where the file simply predates the field would silently downgrade
/// every task in it from a bad span to no span. It is a strictly worse answer — `A-11-23.lua:211`
/// comes out as `213`, the `#label` line — so it is only ever reached when there is nothing better.
///
/// `None` is what an editor-authored step looks like, and it stays `None`: inventing `1..1` would be
/// worse than admitting the gap, because a runtime failure would then point at a line that exists.
fn authored_lines(op: &Operation) -> Option<(u32, u32)> {
    if let (Some(start), Some(end)) = (op.source_line_start, op.source_line_end) {
        return Some((start, end.max(start)));
    }

    let lines = op
        .labels
        .iter()
        .map(|entry| entry.line)
        .chain(op.requires.iter().map(|entry| entry.line))
        .chain(op.complete_with.iter().map(|entry| entry.line))
        .chain(op.optional.iter().map(|entry| entry.line))
        .chain(op.directives.iter().map(|entry| entry.line))
        .map(|line| line as u32);

    lines.fold(None, |span, line| match span {
        None => Some((line, line)),
        Some((low, high)) => Some((low.min(line), high.max(line))),
    })
}

/// Append a [`LootRule`](k::LootRule) for every item objective `predicate` names.
///
/// # Why a `.complete` line produces a loot rule
///
/// §7.1 annotates [`Task::loot_filter`](k::Task::loot_filter) "`.collect` / `.addquestitem`", and
/// those are indeed loot rules — but they are not the *only* source, because §7.3.3 emits
/// `{ item: 5385, for_quest: 983 }` on a task whose only relevant line is
/// `.complete 983,1 --Crawler Leg (6)` and which carries no `.collect` at all. §7.3.2 supplies the
/// derivation: `quest_template` row 983 has `ReqItemId1 = 5385, ReqItemCount1 = 6`, matching the
/// author's comment exactly. A task working an objective whose requirement is an item has to keep
/// that item, or the objective it is waiting on can never advance — the filter is not an
/// optimisation, it is what stops the bot vendoring its own quest progress.
///
/// Only `ConditionRole::Completion` predicates are walked. An `applies_when` names a quest the task
/// is *gated* on, which is not work this task is doing, and a loot rule from it would keep an item
/// for a task that never runs.
fn collect_loot_rules(
    predicate: &k::Predicate,
    meta: &dyn QuestMeta,
    out: &mut Vec<k::LootRule>,
) {
    match predicate {
        k::Predicate::QuestObjective { id, index, .. } => {
            let Some(item) = meta.objective_item(*id, *index) else {
                return;
            };
            let rule = k::LootRule { item, for_quest: Some(*id) };
            if !out.contains(&rule) {
                out.push(rule);
            }
        }
        k::Predicate::And(children) | k::Predicate::Or(children) => {
            for child in children {
                collect_loot_rules(child, meta, out);
            }
        }
        k::Predicate::Not(child) => collect_loot_rules(child, meta, out),
        _ => {}
    }
}

/// Every quest id `task` names, in first-seen order — [`Task::serves_quests`](k::Task::serves_quests).
///
/// # Why a census rather than a transcription
///
/// §7.1 annotates the field "`.requires quest,<id>`" (445 uses) and warns, correctly, that it is
/// **not** the `#requires` metadata tag — that one lowers to [`deps`](k::Task::deps) and conflating
/// the two is silent. But the annotation cannot be the whole rule: the §7.3.1 excerpt contains no
/// `.requires` command anywhere, and §7.3.3 still gives its tasks `[983]`, `[3524]`, `[2118]`,
/// `[984]`, `[2118, 983]` and `[983]` — precisely the quest ids each task's own ops and predicates
/// name, in the order they name them, including the *pair* in printed order on the multi-dependency
/// task. §4.1 supplies the purpose that settles which reading is right: whole-chain pruning when a
/// quest is unobtainable needs every task that touches the quest, not only the ones that annotate
/// it. An explicit `.requires quest,<id>` is one more reference and lands here through the same
/// walk once something lowers it.
///
/// Order is first-seen and never sorted: `[2118, 983]` corresponds position-for-position with the
/// `And` that produced it, and `[983, 2118]` would silently break that correspondence.
fn serves_quests(task_ops: &[k::Op], predicates: &[&k::Predicate]) -> Vec<k::QuestId> {
    let mut served: Vec<k::QuestId> = Vec::new();
    let push = |quest: k::QuestId, served: &mut Vec<k::QuestId>| {
        if !served.contains(&quest) {
            served.push(quest);
        }
    };

    for op in task_ops {
        match op {
            k::Op::Accept { quest, .. } | k::Op::UntrackQuest { quest } => push(*quest, &mut served),
            k::Op::TurnIn { quest, any_of, .. } => {
                push(*quest, &mut served);
                for quest in any_of {
                    push(*quest, &mut served);
                }
            }
            k::Op::Abandon { quests } => {
                for quest in quests {
                    push(*quest, &mut served);
                }
            }
            _ => {}
        }
    }
    for predicate in predicates {
        collect_predicate_quests(predicate, &mut served);
    }
    served
}

/// Append every quest id `predicate` names, recursing through the three combinators.
///
/// The match is exhaustive rather than `_ => {}` on the quest-bearing arms so that a new
/// quest-carrying [`Predicate`](k::Predicate) variant is a compile error here rather than a task
/// that silently stops serving the quest it gates on.
fn collect_predicate_quests(predicate: &k::Predicate, out: &mut Vec<k::QuestId>) {
    let push = |quest: k::QuestId, out: &mut Vec<k::QuestId>| {
        if !out.contains(&quest) {
            out.push(quest);
        }
    };
    match predicate {
        k::Predicate::QuestComplete { id }
        | k::Predicate::QuestObjective { id, .. }
        | k::Predicate::QuestInLog { id }
        | k::Predicate::QuestTurnedIn { id }
        | k::Predicate::QuestAvailable { id } => push(*id, out),
        k::Predicate::And(children) | k::Predicate::Or(children) => {
            for child in children {
                collect_predicate_quests(child, out);
            }
        }
        k::Predicate::Not(child) => collect_predicate_quests(child, out),
        _ => {}
    }
}

/// The arrival radius a movement line that authored none is given, in yards.
///
/// The importer's reach default (`project_builder.rs`), and what §7.3.3 prints for each of the
/// excerpt's three-argument `.goto` lines — `A-11-23.lua:240`, `:262` and `:278` all lower to
/// `radii: [5]`. Distinct from an authored `0`, which §7.3.3 also prints and which this deliberately
/// does not overwrite: "zero yards" and "the guide said nothing" are different instructions, and
/// [`TravelAction::authored_radius`](sentinel_models::authoring::TravelAction::authored_radius)
/// exists precisely so they stay distinguishable.
const DEFAULT_ARRIVAL_RADIUS_YARDS: u16 = 5;

/// Whether `payload` becomes an [`Op`](k::Op), and therefore ends the movement run in front of it.
///
/// **This is drawn on the authored action kind, never on whether the current deliverable can lower
/// it.** `.turnin` has no kernel op today; a boundary drawn on *emitted* ops would merge the two
/// halves of the 568 corpus steps that write a turn-in between two walks, and then silently split
/// them again on the day `TurnIn` lands.
///
/// Measured over 23,894 corpus steps: 691 hold movement lines in more than one authored run. 151 of
/// those are separated *only* by the `false` arms below — `.complete`/`.collect`/`.itemcount`/
/// `.isOnQuest` (task predicates), `.mob`/`.unitscan` (the combat whitelist), `.target` (which emits
/// no action at all), `.money`/`.itemStat` (inert). Splitting there would fabricate 293 routes for
/// walks the author wrote as one; `A-1-11-Draenei.lua:4203` is `.complete`, nine `.goto`s,
/// `.complete`, one more `.goto` — a completion predicate written in the middle of a ten-point walk.
/// The other 540 are separated by real operations, `A-1-11-Draenei.lua:83` being the shape:
/// `.goto` → `.accept` → `.goto`, walk to a quest giver, take the quest, walk to the next.
///
/// The match is exhaustive rather than `_ => true` so a new payload kind is a compile error here and
/// somebody has to decide which side of the boundary it is on.
fn breaks_movement_run(payload: &ActionPayload) -> bool {
    match payload {
        // Not operations. None of these executes between two steps of a walk.
        //
        // * `Condition` is one of the task's three predicate slots (§7.1).
        // * `Kill` is `.mob` / `.unitscan`, which §7.3.3 task 0 and task 2 put in
        //   `combat.targets` / `combat.watch_units`, not in `ops`.
        // * `Comment` is the never-drop inert preserve — text, carrying no execution.
        ActionPayload::Condition(_) | ActionPayload::Kill(_) | ActionPayload::Comment(_) => false,
        // `Travel` is handled by the caller: it *extends* the run rather than ending it.
        ActionPayload::Travel(_) => false,
        ActionPayload::AcceptQuest(_)
        | ActionPayload::TurnInQuest(_)
        | ActionPayload::GrindArea(_)
        | ActionPayload::LootObject(_)
        | ActionPayload::InteractNPC(_)
        | ActionPayload::Vendor(_)
        | ActionPayload::Repair(_)
        | ActionPayload::Train(_)
        | ActionPayload::Flight(_)
        | ActionPayload::LearnFlightPath(_)
        | ActionPayload::Hearth(_)
        | ActionPayload::SetHearth(_)
        | ActionPayload::UseItem(_)
        | ActionPayload::SetVariable(_)
        | ActionPayload::Escort(_)
        | ActionPayload::Patrol(_)
        | ActionPayload::Bank(_)
        | ActionPayload::Mailbox(_)
        | ActionPayload::Wait(_) => true,
    }
}

/// Close the open movement run into a single [`Op::Travel`](k::Op::Travel) and append it.
///
/// A no-op when the run is empty, which is what makes it safe to call at every boundary and again at
/// the end of the step.
///
/// # One op, not one per line
///
/// §5.7's decisive witness is `A-11-23.lua:215-231`: the run's last `.waypoint` is byte-identical to
/// its first `.goto`, and the step carries `#loop`. "A navmesh asked to path from A to A returns a
/// zero-length path; it cannot know the intent is to walk a 15-node loop repeatedly to farm
/// respawns. The route *is* the objective." Seventeen `Destination` ops assert the opposite — each
/// one an invitation to smooth a single hop — and lose the fact that they are one walk.
/// [`ResumeCursor`](k::ResumeCursor) is built on this shape too: its `waypoint` field exists
/// because "one `Op::Travel` carries the whole route".
fn flush_route(
    run: &mut Vec<&Action>,
    looping: bool,
    ops: &mut Vec<k::Op>,
    pool: &mut WaypointPool,
    diagnostics: &mut Vec<Diagnostic>,
) {
    if run.is_empty() {
        return;
    }

    let mut points: Vec<u32> = Vec::with_capacity(run.len());
    let mut radii: Vec<u16> = Vec::with_capacity(run.len());
    for action in run.drain(..) {
        let ActionPayload::Travel(travel) = &action.payload else {
            unreachable!("only `ActionPayload::Travel` actions are pushed onto the run")
        };
        let Some(position) = travel.position else {
            diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: "TRAVEL_WITHOUT_POSITION".to_string(),
                message: format!(
                    "travel action to '{}' carries no resolved position, so it contributes no \
                     waypoint to its route. The rest of the run is emitted rather than dropped — \
                     dropping it would elide the whole step — but the engine will not walk this \
                     line's coordinate.",
                    travel.destination
                ),
                entity: Some(travel.destination.clone()),
                action: Some(action.id.to_string()),
            });
            continue;
        };
        points.push(pool.intern(k::Point {
            map_id: position.map,
            x: position.world_x,
            y: position.world_y,
            // `None`, never `Some(position.world_z)`. §5.7: `z` is `Option` because the corpus
            // never supplies it — the compiler fills it from the navmesh where it can and leaves
            // `None` otherwise, letting the engine ground-snap. The importer's `world_z` is a
            // structural `0.0` placeholder for exactly that (`build_travel_position`: "Z is always
            // 0 here; the runtime resolves ground height on arrival"), and carrying it through as
            // `Some(0.0)` turns a placeholder into an assertion that the waypoint is at sea level.
            z: None,
        }));
        // The radius the *guide* authored, not the importer's executable `tolerance`, which drops a
        // `0` and clamps into `[5, 60]`. §7.3.3 prints `radii: [0,0,0,60 × 14]` for the circuit at
        // `A-11-23.lua:215-231`, matching the source exactly.
        radii.push(travel.authored_radius.unwrap_or(DEFAULT_ARRIVAL_RADIUS_YARDS));
    }

    let kind = if looping {
        // §4.3 maps `#loop` (1,661) to `RouteKind::Circuit`; §5.7 says the compiler emits `Circuit`
        // for `#loop` tasks. `close` states the **cycling intent** and not a geometric property:
        // §7.3.3 prints `close: true` for both of its circuits, and only one of the two returns to
        // its first point — `A-11-23.lua:231` closes onto `:215`, while `:254` ends at a different
        // coordinate from `:247`. A geometric test would disagree with the specification on the
        // second, and would also silently reclassify any circuit whose author left the last hop to
        // the engine.
        k::RouteKind::Circuit { close: true }
    } else if points.len() <= 1 {
        // §5.7: `Destination` for an isolated `.goto` — 16,231 three-argument lines where the
        // coordinate is just where the NPC stands and the navmesh paths there better than a
        // 2004-era waypoint chain. A run that resolved to no point at all lands here too: it is not
        // a corridor, and `Circuit` would claim an intent the step never expressed.
        k::RouteKind::Destination
    } else {
        // §5.7: `Corridor` for a run of `.goto`/`.waypoint` in a non-loop task — ordered points the
        // engine *may* smooth between, which is exactly what a `Circuit` may not do.
        k::RouteKind::Corridor
    };

    ops.push(k::Op::Travel {
        route: k::Route {
            kind,
            // `Any` — the engine picks — and never `Ground`. §7.1 maps the media one way only:
            // `.goto`/`.waypoint` to `Any`, `.groundgoto` to `Ground`, `.flygoto` to `Air`.
            // `TravelAction::allow_flight` is not the same fact as `.groundgoto` (114 uses), which
            // exists to *override* the engine's preferred line through mountain paths, caves and
            // stairs (§5.7); reading it as one would mark all 38,087 ordinary `.goto` routes
            // ground-forced. `ProjectBuilder` lowers neither `.groundgoto` nor `.flygoto` to a
            // travel action yet, so no route reaching here can legitimately be anything else.
            mode: k::TravelMode::Any,
            points,
            radii,
        },
    });
}

/// Lower one surviving non-movement action into a kernel [`Op`](k::Op).
///
/// Returns `None` for an action type this deliverable does not lower yet, with a diagnostic naming
/// it. The step still survives — see the elision comment in [`resolve_operations`] — because "no
/// kernel op exists for this yet" and "this archetype does not run this" are different facts and
/// collapsing them would silently delete content from the artifact.
///
/// Movement is **not** handled here: a route spans more than one action, so it is aggregated by
/// [`flush_route`] and this function never sees a [`ActionPayload::Travel`].
fn lower_op(action: &Action, diagnostics: &mut Vec<Diagnostic>) -> Option<k::Op> {
    match &action.payload {
        ActionPayload::AcceptQuest(accept) => Some(k::Op::Accept {
            quest: accept.quest,
            // `.daily` (35) is the only source of `repeatable` and the authoring model does not
            // carry it; `false` is the value for the other 7,455 `.accept` lines.
            repeatable: false,
        }),
        ActionPayload::TurnInQuest(turn_in) => Some(k::Op::TurnIn {
            quest: turn_in.quest,
            // `.turninmultiple` (1) is the only source of `any_of` — the Aldor/Scryer choice point
            // (§8) — and the authoring model does not carry it, so the other 7,711 `.turnin` lines
            // get the empty list that means "this quest and no alternative".
            any_of: Vec::new(),
            // §7.1: the second argument of `.turnin`, proven by `A-1-11-Human.lua:155/156`, which
            // turn in quest 33 with reward 2 vs 1 split by armour class. `u8` there, `u32` in the
            // authoring model; a value that does not fit is dropped loudly rather than truncated,
            // because reward 1 and reward 257 are different rewards.
            reward_choice: match turn_in.choose_reward {
                Some(choice) => match u8::try_from(choice) {
                    Ok(choice) => Some(choice),
                    Err(_) => {
                        diagnostics.push(Diagnostic {
                            severity: Severity::Warning,
                            code: "REWARD_CHOICE_OUT_OF_RANGE".to_string(),
                            message: format!(
                                "`.turnin {}` names reward {choice}, and ADR 07 §7.1's \
                                 `Op::TurnIn::reward_choice` is a `u8`. The choice is dropped \
                                 rather than truncated — the runtime will take the default reward",
                                turn_in.quest
                            ),
                            entity: None,
                            action: Some(action.id.to_string()),
                        });
                        None
                    }
                },
                None => None,
            },
            // A negative quest id in the source means an optional turn-in (38 instances); the
            // importer has already decided it.
            optional: turn_in.optional,
            // `.dailyturnin` (40), which the authoring model does not carry.
            repeatable: false,
        }),
        ActionPayload::UseItem(use_item) => {
            // `UseItemAction::target` has no kernel counterpart: §7.1's `Op::UseItem` carries the
            // item and nothing else, because `.use` (1,678) is always bare in the corpus and the
            // unit an item is used *on* is the step's own target. Said out loud rather than dropped
            // in silence.
            if use_item.target.is_some() {
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "USE_ITEM_TARGET_DROPPED".to_string(),
                    message: format!(
                        "`.use {}` names a target, and ADR 07 §7.1's `Op::UseItem` carries only the \
                         item. The op is emitted without it",
                        use_item.item
                    ),
                    entity: None,
                    action: Some(action.id.to_string()),
                });
            }
            Some(k::Op::UseItem { item: use_item.item })
        }
        other => {
            diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: "KERNEL_OP_NOT_LOWERED".to_string(),
                message: format!(
                    "action {} survived archetype resolution but this deliverable lowers only \
                     AcceptQuest and Travel into kernel ops, so it is absent from the artifact",
                    action_kind(other)
                ),
                entity: None,
                action: Some(action.id.to_string()),
            });
            None
        }
    }
}

/// The authored name of a payload variant, for diagnostics.
fn action_kind(payload: &ActionPayload) -> &'static str {
    match payload {
        ActionPayload::AcceptQuest(_) => "AcceptQuest",
        ActionPayload::TurnInQuest(_) => "TurnInQuest",
        ActionPayload::Travel(_) => "Travel",
        ActionPayload::Kill(_) => "Kill",
        ActionPayload::GrindArea(_) => "GrindArea",
        ActionPayload::LootObject(_) => "LootObject",
        ActionPayload::InteractNPC(_) => "InteractNPC",
        ActionPayload::Vendor(_) => "Vendor",
        ActionPayload::Repair(_) => "Repair",
        ActionPayload::Train(_) => "Train",
        ActionPayload::Flight(_) => "Flight",
        ActionPayload::LearnFlightPath(_) => "LearnFlightPath",
        ActionPayload::Hearth(_) => "Hearth",
        ActionPayload::SetHearth(_) => "SetHearth",
        ActionPayload::UseItem(_) => "UseItem",
        ActionPayload::Comment(_) => "Comment",
        ActionPayload::Condition(_) => "Condition",
        ActionPayload::SetVariable(_) => "SetVariable",
        ActionPayload::Escort(_) => "Escort",
        ActionPayload::Patrol(_) => "Patrol",
        ActionPayload::Bank(_) => "Bank",
        ActionPayload::Mailbox(_) => "Mailbox",
        ActionPayload::Wait(_) => "Wait",
    }
}

/// Assign task ids to the survivors and resolve every edge against them.
///
/// This is where elision is paid for. `Task::id` **is** the index into
/// [`RuntimeProfile::tasks`](k::RuntimeProfile::tasks), so removing an entry moves every id and
/// every edge past the hole, and an off-by-one there is silent — the profile loads and the runner
/// waits on the wrong predecessor forever.
///
/// **Every id-bearing field is produced in survivor space by construction, not remapped after the
/// fact.** There are three of them and all three are covered:
///
/// * `deps` — resolved through a label table built from the *surviving* order.
/// * `completion` ([`CompletionSource::LinkedTo`](k::CompletionSource::LinkedTo)) — the same table
///   for the label form, and `index + 1` in the **surviving** list for the reserved `next` literal.
///   Authored adjacency is not survivor adjacency: `TBC:16270` and `TBC:16276` are adjacent for a
///   Mage and both gated out for everyone else, and a `next` recorded as an authored index points
///   one task past the end for any archetype that lost a step in between.
/// * `jump_to` — always `None` today, because its only source is the 2-argument `.maxlevel` form
///   (§4.1) and no op lowering produces it yet. When it lands it must be resolved through the same
///   surviving order and through nothing else; an authored index there fails exactly the way the
///   other two would.
fn assemble_tasks(
    project: &Project,
    survivors: Vec<SurvivingStep>,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<k::Task> {
    let label_to_task = build_label_table(&survivors, diagnostics);

    // Completions are resolved for the whole block before any task is built, because 2,670 of the
    // corpus's 2,788 label-valued `#completewith` links point forward: a single pass that resolved
    // as it emitted would see none of them.
    let completions: Vec<k::CompletionSource> = (0..survivors.len())
        .map(|index| resolve_completion(index, &survivors, &label_to_task, diagnostics))
        .collect();

    // §5.3: "`terminate_on` is a `Predicate` — normally the linked task's completion or its own
    // `complete_when`." Derived here, while every step is still in hand, because the linked task's
    // predicate lives on a *different* survivor.
    let terminate_ons: Vec<Option<k::Predicate>> = (0..survivors.len())
        .map(|index| {
            survivors[index].complete_when.clone().or_else(|| {
                let k::CompletionSource::LinkedTo(target) = completions[index] else {
                    return None;
                };
                survivors
                    .get(target as usize)
                    .and_then(|linked| linked.complete_when.clone())
            })
        })
        .collect();

    // No cycle detection pass, deliberately. All 346 resolvable `#requires` edges in the corpus
    // point BACKWARD (target index < referencing index) — zero forward, zero self — so the
    // dependency graph is acyclic by construction and a detector would be dead code over every
    // input that exists today, which is worse than absent: dead code that reports nothing is
    // indistinguishable from dead code that is broken. The two ways a cycle could be *created*
    // here are a self-`#requires` and a self-`#completewith`, and both are refused at the point
    // they would be constructed (below, and in `resolve_completion`), which is also the only place
    // with enough context to name the label in the diagnostic. The whole-graph property is guarded
    // from outside by `compiler/tests/kernel_task_graph.rs::the_lowered_task_graph_is_acyclic`.

    let source_file = project
        .import_metadata
        .as_ref()
        .map(|metadata| metadata.source_file.clone())
        .unwrap_or_default();

    let mut holding_band = FIRST_HOLDING_BAND;

    survivors
        .into_iter()
        .enumerate()
        .map(|(index, step)| {
            let id = index as k::TaskId;
            let mut deps: Vec<k::TaskId> = Vec::new();
            for label in &step.requires {
                match label_to_task.get(label.as_str()) {
                    Some(dep) if *dep == id => diagnostics.push(Diagnostic {
                        severity: Severity::Error,
                        code: "SELF_REQUIRES_LABEL".to_string(),
                        message: format!(
                            "#requires '{label}' names a label this very step defines, so the step \
                             would wait for itself forever. The edge is dropped"
                        ),
                        entity: Some(label.clone()),
                        action: None,
                    }),
                    Some(dep) if !deps.contains(dep) => deps.push(*dep),
                    Some(_) => {}
                    // An ERROR, not a warning. A dropped edge runs the step early, which is
                    // recoverable; what is not recoverable is an author who never learns a rename
                    // broke the link because it was filed beside the routine
                    // `KERNEL_OP_NOT_LOWERED` warnings a normal compile already emits.
                    None => diagnostics.push(Diagnostic {
                        severity: Severity::Error,
                        code: "UNRESOLVED_REQUIRES_LABEL".to_string(),
                        message: format!(
                            "#requires '{label}' names a label no surviving step defines — either \
                             the defining step was gated out for this archetype, or the label does \
                             not exist. The edge is dropped, so this step no longer waits for it"
                        ),
                        entity: Some(label.clone()),
                        action: None,
                    }),
                }
            }

            let completion = completions[index];
            let lifetime = lower_lifetime(
                id,
                &step,
                completion,
                terminate_ons[index].clone(),
                &mut holding_band,
                diagnostics,
            );

            let (line_start, line_end) = step.lines.unwrap_or((0, 0));
            // Every predicate slot the task ends up with, in the order §7.1 declares them, plus the
            // one that lives *inside* the lifetime payload. A census that walked only the task's
            // own three slots would miss every `Background` termination condition — and §7.3.3
            // task 0 serves quest 983 through `terminate_on: QuestTurnedIn(983)` as much as
            // through anything else.
            let mut predicates: Vec<&k::Predicate> = Vec::new();
            predicates.extend(step.applies_when.as_ref());
            predicates.extend(step.complete_when.as_ref());
            if let k::Lifetime::Background { terminate_on, .. } = &lifetime {
                predicates.push(terminate_on);
            }
            let serves_quests = serves_quests(&step.ops, &predicates);

            k::Task {
                id,
                deps,
                blocking: step.blocking,
                lifetime,
                completion,
                applies_when: step.applies_when,
                complete_when: step.complete_when,
                abort_when: None,
                unknown_policy: k::UnknownPolicy::Defer { budget_ticks: 60 },
                ops: step.ops,
                interact_target: None,
                combat: None,
                loot_filter: step.loot_filter,
                serves_quests,
                suppress: Vec::new(),
                // See the `jump_to` bullet on this function: `None` because nothing produces it,
                // and when something does it resolves through the surviving order above.
                jump_to: None,
                source: k::SourceSpan {
                    file: source_file.clone(),
                    line_start,
                    line_end,
                },
            }
        })
        .collect()
}

/// The block's `#label` symbol table, keyed by name and valued by **surviving** task id.
///
/// Scope is the guide block — one `RegisterGuide`, one `Project`, one call to this function — and
/// not the file: 768 of the corpus's 1,560 distinct names are defined in more than one file, so a
/// file-scoped table would fabricate cross-guide edges.
///
/// Gate-disambiguated duplicates are already gone by the time this runs, because
/// [`resolve_operations`] dropped every label whose own gate the archetype did not satisfy. What is
/// left is the genuinely undecidable population — the 44 groups the importer already flags
/// `DUPLICATE_LABEL` — and those keep the previous rule (later definition wins) plus a warning,
/// because there is no further information to decide them with.
fn build_label_table(
    survivors: &[SurvivingStep],
    diagnostics: &mut Vec<Diagnostic>,
) -> HashMap<String, k::TaskId> {
    let mut label_to_task: HashMap<String, k::TaskId> = HashMap::new();
    for (index, step) in survivors.iter().enumerate() {
        for label in &step.labels {
            if label_to_task
                .insert(label.clone(), index as k::TaskId)
                .is_some()
            {
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "DUPLICATE_STEP_LABEL".to_string(),
                    message: format!(
                        "#label '{label}' is defined by more than one surviving step; the archetype \
                         did not separate them, so the later definition wins and every edge naming \
                         '{label}' now points at it"
                    ),
                    entity: Some(label.clone()),
                    action: None,
                });
            }
        }
    }
    label_to_task
}

/// Resolve one step's `#completewith` into a [`CompletionSource`](k::CompletionSource).
///
/// Every failure lands on [`CompletionSource::OwnPredicate`](k::CompletionSource::OwnPredicate)
/// with an **ERROR** diagnostic, and the step is never dropped. That ruling is safe because it was
/// measured: all 52 truly-unresolvable steps in the corpus carry their own completion anyway — 37
/// via `.complete`/`.collect`/`.accept`, 15 via a side-effect command that finishes on execution.
/// Dropping the step instead would delete real work from the route (`A-1-11-Human.lua:1994-2000` is
/// every Warlock's Soul Shard farm); falling back *silently* would reproduce the RXPGuides defect
/// this model exists to prevent, where the edge never fires and nothing says so.
fn resolve_completion(
    index: usize,
    survivors: &[SurvivingStep],
    label_to_task: &HashMap<String, k::TaskId>,
    diagnostics: &mut Vec<Diagnostic>,
) -> k::CompletionSource {
    let step = &survivors[index];
    let Some(target) = step.complete_with.first() else {
        return k::CompletionSource::OwnPredicate;
    };
    if step.complete_with.len() > 1 {
        diagnostics.push(Diagnostic {
            severity: Severity::Warning,
            code: "MULTIPLE_COMPLETEWITH".to_string(),
            message: format!(
                "{} `#completewith` entries survived gate resolution on one step, but a task has \
                 exactly one completion authority; the first is used and the rest are dropped",
                step.complete_with.len()
            ),
            entity: None,
            action: None,
        });
    }

    let resolved = match target {
        // `next` is the only reserved word in this value space — `end` is a real label with 11
        // definitions — and it means the following **surviving** task, not the following authored
        // one. See the `completion` bullet on `assemble_tasks`.
        CompleteWithTarget::Next => {
            let successor = index + 1;
            if successor < survivors.len() {
                Some(successor as k::TaskId)
            } else {
                diagnostics.push(Diagnostic {
                    severity: Severity::Error,
                    code: "UNRESOLVED_COMPLETEWITH_NEXT".to_string(),
                    message: "#completewith next names the following step, and this is the last \
                              step that survived for this archetype. The link is dropped and the \
                              task falls back to its own completion authority"
                        .to_string(),
                    entity: None,
                    action: None,
                });
                None
            }
        }
        CompleteWithTarget::Label(name) => match label_to_task.get(name.as_str()) {
            Some(target) => Some(*target),
            None => {
                diagnostics.push(Diagnostic {
                    severity: Severity::Error,
                    code: "UNRESOLVED_COMPLETEWITH_LABEL".to_string(),
                    message: format!(
                        "#completewith '{name}' names a label no surviving step defines — either \
                         the defining step was gated out for this archetype, or the label does not \
                         exist. The link is dropped and the task falls back to its own completion \
                         authority"
                    ),
                    entity: Some(name.clone()),
                    action: None,
                });
                None
            }
        },
    };

    match resolved {
        Some(target) if target as usize != index => k::CompletionSource::LinkedTo(target),
        Some(_) => {
            diagnostics.push(Diagnostic {
                severity: Severity::Error,
                code: "SELF_COMPLETEWITH".to_string(),
                message: "#completewith resolves to the step that wrote it, so the task would wait \
                          on its own completion. The link is dropped and the task falls back to its \
                          own completion authority"
                    .to_string(),
                entity: None,
                action: None,
            });
            k::CompletionSource::OwnPredicate
        }
        None => k::CompletionSource::OwnPredicate,
    }
}

/// `#sticky` and `#completewith` into a [`Lifetime`](k::Lifetime) (§5.3).
///
/// The two directives are **disjoint as authored** (§2.4) and neither implies the other, yet both
/// produce a concurrent task, for different reasons and with different payloads:
///
/// * `#sticky` (311 uses; payload 416 `.waypoint` + 296 `.goto`) claims
///   [`Channel::Movement`](k::Channel::Movement) for its lifetime, so a patrol keeps walking while a
///   foreground turn-in holds `INTERACTION`.
/// * `#completewith` makes a task concurrent **by definition** — it cannot be the foreground task if
///   the task it finishes with is — but it contends for nothing. §7.3.3 task 6 is
///   `Background { channels: [], band: 30 }`. Deriving its channels from its ops instead would hand
///   it `MOVEMENT` the moment `.subzone` gains a travel lowering, and it would then fight the very
///   task it is waiting for.
///
/// `holding_band` is the running offset §5.3 requires ("offset by task order so two sticky tasks
/// cannot deadlock"): §7.3.3's two patrols are 34 and 35, its ride-along is 30.
fn lower_lifetime(
    id: k::TaskId,
    step: &SurvivingStep,
    completion: k::CompletionSource,
    terminate_on: Option<k::Predicate>,
    holding_band: &mut u8,
    diagnostics: &mut Vec<Diagnostic>,
) -> k::Lifetime {
    let linked = matches!(completion, k::CompletionSource::LinkedTo(_));
    if !step.sticky && !linked {
        return k::Lifetime::Exclusive;
    }

    let holds_movement = step.sticky && step.ops.iter().any(is_movement);
    let channels = if holds_movement {
        vec![k::Channel::Movement]
    } else {
        Vec::new()
    };

    let band = if holds_movement {
        let band = *holding_band;
        if band == *k::GOAL_BAND.end() {
            diagnostics.push(Diagnostic {
                severity: Severity::Warning,
                code: "BAND_OFFSET_SATURATED".to_string(),
                message: format!(
                    "task {id} is the {}th channel-holding concurrent task in this guide, and ADR \
                     07 §7.2's Goal band ends at {}. Its band is clamped rather than pushed above \
                     the band 90-99 safety net, so it shares a band with its predecessor and §5.3's \
                     per-task offset no longer separates them",
                    *k::GOAL_BAND.end() - FIRST_HOLDING_BAND + 1,
                    k::GOAL_BAND.end()
                ),
                entity: None,
                action: None,
            });
        } else {
            *holding_band += 1;
        }
        band
    } else {
        RIDE_ALONG_BAND
    };

    let terminate_on = terminate_on.unwrap_or_else(|| {
        diagnostics.push(Diagnostic {
            severity: Severity::Warning,
            code: "BACKGROUND_WITHOUT_TERMINATION".to_string(),
            message: format!(
                "task {id} is concurrent but neither it nor the task it links to carries a \
                 completion predicate, so no voluntary termination condition can be derived from \
                 the guide. §5.3 gives termination two routes and this task keeps only the second: \
                 the profile cursor passing it. An invented predicate would be worse — a plausible \
                 wrong one is indistinguishable from a right one at every later stage"
            ),
            entity: None,
            action: None,
        });
        // The empty disjunction: "none of the following", i.e. no authored condition. Chosen over
        // an empty conjunction, which is vacuously TRUE and would terminate the task the instant it
        // was evaluated — a `#sticky` patrol that ends before it walks anywhere. Never satisfied is
        // the honest reading of "the guide states no termination condition", and §5.3's cursor
        // route still ends the task.
        k::Predicate::Or(Vec::new())
    });

    k::Lifetime::Background {
        channels,
        band,
        terminate_on,
    }
}

/// Whether an op moves the character, and therefore whether a `#sticky` task must hold
/// [`Channel::Movement`](k::Channel::Movement) to keep doing it.
fn is_movement(op: &k::Op) -> bool {
    matches!(op, k::Op::Travel { .. })
}
