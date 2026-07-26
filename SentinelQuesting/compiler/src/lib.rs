//! Sentinel Questing — Compiler (Phase 6).
//!
//! Compiles Projects into RuntimeProfiles for Lua execution.

use std::collections::HashMap;
use uuid::Uuid;

mod condition;
pub mod kernel;

use sentinel_models::authoring::{Action, ActionPayload, Diagnostic, Project, Severity};
use sentinel_models::runtime::{
    compute_content_hash, GuardedAction, RuntimeAction, RuntimeOperation, RuntimeProfile, RuntimeAcceptQuest,
    RuntimeFlight, RuntimeHearth, RuntimeKill, RuntimeVendor, RuntimeTrain, RuntimeUseItem,
    RuntimeComment, RuntimeTravel, RuntimeTurnInQuest, RuntimeWaypoint, RuntimeRepair,
    RuntimeLearnFlightPath, RuntimeConditionAction, RuntimeSetVariable, RuntimeEscort,
    RuntimePatrol, RuntimeGrind, RuntimeLoot, RuntimeBank, RuntimeMailbox, RuntimeWait,
    RuntimeCondition, RuntimeInteractNpc, RuntimeNpc,
};

/// Title-Case class names the runtime's `CLASS_ID_TO_NAME` map can produce
/// (`sentinel/modules/questing/runtime_profile.lua`). Anything else in a `class_restriction`
/// tail is an authoring error worth a diagnostic, not a guess.
const KNOWN_CLASSES: &[&str] = &[
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "DeathKnight", "Shaman", "Mage", "Warlock",
    "Druid",
];

/// Lower a RestedXP class-tail (e.g. `"Warrior"`, `"Warrior/Paladin"`, `"!Rogue"`) into a
/// `RuntimeCondition` guard (CL4). Returns `None` — plus a diagnostic — for empty/unknown class
/// tokens; never panics, never guesses.
fn parse_class_guard(
    restriction: &str,
    action_id: Uuid,
    diagnostics: &mut Vec<Diagnostic>,
) -> Option<RuntimeCondition> {
    let trimmed = restriction.trim();
    if trimmed.is_empty() {
        return None;
    }
    let (negate, rest) = match trimmed.strip_prefix('!') {
        Some(stripped) => (true, stripped),
        None => (false, trimmed),
    };
    let names: Vec<&str> = rest.split('/').map(|s| s.trim()).collect();

    let unknown = |diagnostics: &mut Vec<Diagnostic>, detail: String| {
        diagnostics.push(Diagnostic {
            severity: Severity::Warning,
            code: "UNKNOWN_CLASS_RESTRICTION".to_string(),
            message: format!(
                "class restriction '{restriction}' could not be mapped to a guard: {detail}"
            ),
            entity: Some(restriction.to_string()),
            action: Some(action_id.to_string()),
        });
    };

    if names.is_empty() || names.iter().any(|n| n.is_empty()) {
        unknown(diagnostics, "empty class token".to_string());
        return None;
    }
    for name in &names {
        if !KNOWN_CLASSES.contains(name) {
            unknown(diagnostics, format!("unknown class '{name}'"));
            return None;
        }
    }

    let base = if names.len() == 1 {
        RuntimeCondition::ClassIs(names[0].to_string())
    } else {
        RuntimeCondition::Any(names.iter().map(|n| RuntimeCondition::ClassIs(n.to_string())).collect())
    };
    Some(if negate { RuntimeCondition::Not(Box::new(base)) } else { base })
}

/// Compiler errors that prevent profile generation.
#[derive(Debug, Clone, thiserror::Error)]
pub enum CompilerError {
    /// Retained for API compatibility. An unresolvable NPC reference is no longer fatal — it is
    /// degraded to a `RuntimeAction::Comment` plus an `UNRESOLVED_NPC` diagnostic (mirroring
    /// `LootObject`'s `UNRESOLVED_OBJECT` precedent) so a single bad reference never aborts an
    /// entire guide compile (IF7 never-drop philosophy). Nothing in this crate returns this
    /// variant anymore.
    #[error("NPC reference could not be resolved to an entry")]
    UnresolvedNpc,
    #[error("Quest reference could not be resolved")]
    UnresolvedQuest,
    /// A refusal raised by the ADR-07 kernel lowering — today, only an unrecognised gate token
    /// (`kernel::archetype`). Fatal on purpose: a gate the compiler cannot read is a gate it cannot
    /// resolve away, and C2 leaves nowhere in the artifact to carry one (§5.2).
    ///
    /// Reached only through [`Compiler::compile_kernel`]. [`Compiler::compile`] is the ADR-05 path
    /// and is untouched by it.
    #[error("kernel lowering refused the project: {0}")]
    KernelLowering(#[from] kernel::LoweringError),
}

/// Resolve an (optionally present) NPC UUID reference to a concrete entry. On any failure to
/// resolve — either the reference itself is absent (`None`) or it does not appear in the
/// project's NPC library — this is a NON-FATAL degradation: `*unresolved` is bumped and an
/// `UNRESOLVED_NPC` diagnostic is recorded, mirroring the existing `LootObject` /
/// `UNRESOLVED_OBJECT` precedent. Returns `None` on failure so the caller can lower the action to
/// a `RuntimeAction::Comment` instead of aborting the whole guide compile.
fn resolve_npc_or_report(
    npc: Option<Uuid>,
    npc_uuid_to_entry: &HashMap<Uuid, u32>,
    action_id: Uuid,
    action_kind: &str,
    diagnostics: &mut Vec<Diagnostic>,
    unresolved: &mut u32,
) -> Option<u32> {
    let entry = npc.and_then(|u| npc_uuid_to_entry.get(&u).copied());
    if entry.is_none() {
        *unresolved += 1;
        let message = match npc {
            Some(u) => format!(
                "{action_kind} NPC reference '{u}' could not be resolved to an entry"
            ),
            None => format!("{action_kind} action has no NPC reference"),
        };
        diagnostics.push(Diagnostic {
            severity: Severity::Warning,
            code: "UNRESOLVED_NPC".to_string(),
            message,
            entity: npc.map(|u| u.to_string()),
            action: Some(action_id.to_string()),
        });
    }
    entry
}

/// Non-fatal compile-time findings, kept out of `RuntimeProfile` (clean runtime artifact).
/// `unmapped_conditions` populated here (CL1); PR2b adds `unresolved` (unresolvable
/// `LootObject` references — CL2). Class filtering (CL4, PR5c) lowers `Action.class_restriction`
/// into a per-action `GuardedAction.guard` (`RuntimeCondition`); unknown class tokens surface
/// here as `UNKNOWN_CLASS_RESTRICTION` diagnostics rather than a guessed guard.
#[derive(Debug, Clone, Default)]
pub struct CompileReport {
    pub unmapped_conditions: Vec<Diagnostic>,
    /// Count of references (`LootObject`, and any of the NPC-bearing actions) that could not be
    /// resolved to a concrete entry. Mirrored as an `UNRESOLVED_OBJECT` or `UNRESOLVED_NPC`
    /// diagnostic in `unmapped_conditions`; the action itself is lowered to a
    /// `RuntimeAction::Comment` rather than aborting the whole guide compile.
    pub unresolved: u32,
}

pub struct Compiler;

impl Compiler {
    /// Compile a Project into a RuntimeProfile plus a report of non-fatal findings.
    pub fn compile(project: &Project) -> Result<(RuntimeProfile, CompileReport), CompilerError> {
        let npc_uuid_to_entry: HashMap<Uuid, u32> = project.npc_library
            .iter()
            .filter_map(|n| n.entry.map(|e| (n.id, e)))
            .collect();
        let object_uuid_to_entry: HashMap<Uuid, u32> = project.object_library
            .iter()
            .map(|o| (o.id, o.entry))
            .collect();

        let mut diagnostics: Vec<Diagnostic> = Vec::new();
        let mut unresolved: u32 = 0;
        let runtime_operations: Vec<RuntimeOperation> = project.operations
            .iter()
            .map(|op| resolve_operation(op, &npc_uuid_to_entry, &object_uuid_to_entry, &mut diagnostics, &mut unresolved))
            .collect::<Result<Vec<_>, _>>()?;

        let mut profile = RuntimeProfile::new(project.metadata.name.clone(), runtime_operations);
        // Embed resolved NPC spawn positions. The Lua runtime navigates to these when an
        // NPC is beyond object-manager draw distance (e.g. Marshal McBride inside
        // Northshire Abbey) — without them, quest accepts/turn-ins at unseen NPCs had no
        // nav target and were skipped after exhausting retries. Set BEFORE the content
        // hash so the fingerprint covers them.
        profile.npcs = project.npc_library
            .iter()
            .filter_map(|n| Some(RuntimeNpc::new(n.entry?, n.name.clone(), n.position.clone()?)))
            .collect();
        profile.content_hash = compute_content_hash(&profile);
        let report = CompileReport { unmapped_conditions: diagnostics, unresolved };
        Ok((profile, report))
    }

    /// Compile a Project into the **ADR-07 kernel artifact**, for a named archetype.
    ///
    /// Additive and independent: [`Compiler::compile`] above is untouched, still produces the ADR-05
    /// [`RuntimeProfile`] the Lua runtime executes today, and neither artifact is derived from the
    /// other.
    ///
    /// # Why an archetype and a metadata provider are parameters
    ///
    /// * `archetype` is an **input**, not an output. C2 (§5.2) resolves every static gate at compile
    ///   time and emits one artifact per archetype, because the runtime cannot evaluate them: player
    ///   faction is not readable from the Sylvanas API and there is no race enum.
    /// * `meta` supplies the required counts baked into
    ///   [`Predicate::QuestObjective`](sentinel_models::kernel::Predicate::QuestObjective). Those
    ///   come from `quest_template`, which a `&Project` does not carry. It is a synchronous trait on
    ///   purpose: the QueryServer lookups happen *before* this call and populate the provider, so
    ///   lowering itself stays pure and testable with no running server.
    ///
    ///   `meta` is consulted for every `.complete <quest>,<index>` a surviving step carries, and for
    ///   nothing else. A project with no objective predicates never touches it, which is why
    ///   `kernel_lowering::the_metadata_provider_is_not_consulted_until_the_task_graph_lands` still
    ///   holds over an operation-free project.
    ///
    /// # What it does do: C2
    ///
    /// Every static gate is resolved here, against `archetype`, and **nothing that carries one
    /// reaches the artifact** (§5.2). Resolution happens at **op granularity**, not task granularity:
    /// the corpus has 3,052 command-level `<<` gates across 134 distinct expressions, and a
    /// task-granular resolver is wrong on every one of them — `A-1-11-Human.lua:185-196` is one
    /// ungated step containing six mutually exclusive class-gated `.accept`s, so it would give a
    /// Warrior either all six letters or none. A task left with no surviving op is elided, and the
    /// survivors are **renumbered**, with every `#requires` edge remapped: `Task::id` *is* the index
    /// into `tasks`, so removing an entry moves every id and every edge past the hole, and an
    /// off-by-one there is silent — the profile loads and the runner waits on the wrong predecessor
    /// forever.
    ///
    /// `Operation::enabled` is **honoured, not re-derived**. The importer already decided it for the
    /// 140 corpus steps carrying the `skip` disable sentinel, and an editor toggle produces the same
    /// flag with no gate at all; re-deriving the decision from the gate string misses every disable
    /// that did not come from `skip`.
    ///
    /// # And C3: the task graph
    ///
    /// `#label`, `#requires`, `#completewith`, `#sticky` and `#optional` are lowered by
    /// [`kernel::lower_task_graph`], which owns the ordering constraints between them. Label names
    /// are a symbol table and are consumed there: nothing carries one into the artifact.
    ///
    /// # And C6, and the header
    ///
    /// `.mob` / `.unitscan` become a per-task [`CombatPolicy`](sentinel_models::kernel::CombatPolicy)
    /// wherever the derived policy differs from `defaults.combat` (`kernel::combat`), and
    /// `#name` / `#group` / `#subgroup` / `#version` / `#next` become
    /// [`GuideMeta`](sentinel_models::kernel::GuideMeta) with each entry's gate resolved against the
    /// same archetype (`kernel::meta`).
    ///
    /// # What it still does not do
    ///
    /// The two digests, `abort_when`, `interact_target`, `suppress` and `jump_to`; routes are
    /// lowered only from a `Travel` action's own resolved `Position`, with no circuit collapse, and
    /// `UnknownPolicy` is `Defer { 60 }` on every task rather than chosen per §5.1.2. The report
    /// still carries a `KERNEL_PROFILE_INCOMPLETE` warning naming each gap, so no caller can mistake
    /// this for a shippable artifact.
    ///
    /// [`kernel::lower_task_graph`]: kernel::lower_task_graph
    pub fn compile_kernel(
        project: &Project,
        archetype: &sentinel_models::kernel::Archetype,
        meta: &dyn kernel::QuestMeta,
    ) -> Result<(sentinel_models::kernel::RuntimeProfile, CompileReport), CompilerError> {
        use sentinel_models::kernel as k;

        let mut diagnostics = vec![Diagnostic {
            severity: Severity::Warning,
            code: "KERNEL_PROFILE_INCOMPLETE".to_string(),
            message:
                "kernel lowering is partial: archetype gates are resolved and the task graph carries \
                 ops, dependency edges, lifetimes, completion links, the `.complete` / `.isOnQuest` \
                 predicates, the derived quest-log gate, hand-in pair and hand-in termination, the \
                 per-task §5.1.2 unknown-policy, the guide header and the C6 combat policy — but no \
                 task carries an abort predicate or an interact target, the waypoint pool holds only \
                 positions the importer had already resolved with no circuit collapse, and \
                 `schema_hash` / `content_hash` are zero placeholders rather than computed digests. \
                 Do not execute this artifact."
                    .to_string(),
            entity: Some(project.metadata.name.clone()),
            action: None,
        }];

        let mut pool = kernel::WaypointPool::default();
        let tasks =
            kernel::lower_task_graph(project, archetype, &mut pool, meta, &mut diagnostics)?;
        let guide_meta = kernel::lower_guide_meta(project, archetype, &mut diagnostics)?;

        let profile = k::RuntimeProfile {
            magic: k::MAGIC,
            schema_version: k::SCHEMA_VERSION,
            schema_hash: [0u8; 32],
            // Computed from the tasks just built, never transcribed — see `kernel::tag_census` for
            // why a hand-maintained list is wrong in two different ways at once.
            tags_used: kernel::tag_census(&tasks),
            integrity: k::ContentIntegrity {
                content_hash: [0u8; 32],
                world_source: String::new(),
                world_build: String::new(),
            },
            archetype: archetype.clone(),
            meta: guide_meta,
            defaults: k::ProfileDefaults {
                // §5.6: `Defensive` is the profile-level default — 16,438 of 23,894 corpus tasks
                // carry no combat token at all. Taken from the same function the per-task lowering
                // measures its override against (`kernel::combat`), because "the task wants exactly
                // the default" is decided by comparing the two and two transcriptions of one policy
                // would make every task carry a redundant copy of it.
                combat: kernel::default_combat_policy(),
                // §5.1.2: `Defer` is the compiler's default for `complete_when`; 60 ticks is the
                // budget §7.3.3 uses. Taken from the same constant the per-task rule falls back to
                // (`kernel::task_graph::unknown_policy`), because an artifact whose `defaults`
                // block disagrees with the value its ordinary tasks carry states §5.1.2 twice and
                // differently inside one file.
                unknown_policy: kernel::default_unknown_policy(),
            },
            waypoint_pool: pool.into_points(),
            tasks,
        };

        Ok((
            profile,
            CompileReport { unmapped_conditions: diagnostics, unresolved: 0 },
        ))
    }
}

fn resolve_operation(
    op: &sentinel_models::authoring::Operation,
    npc_uuid_to_entry: &HashMap<Uuid, u32>,
    object_uuid_to_entry: &HashMap<Uuid, u32>,
    diagnostics: &mut Vec<Diagnostic>,
    unresolved: &mut u32,
) -> Result<RuntimeOperation, CompilerError> {
    let runtime_actions: Vec<GuardedAction> = op.actions
        .iter()
        .map(|a| resolve_action(a, npc_uuid_to_entry, object_uuid_to_entry, diagnostics, unresolved))
        .collect::<Result<Vec<_>, _>>()?;

    Ok(RuntimeOperation {
        id: op.id,
        name: op.name.clone(),
        entry_conditions: Vec::new(),
        exit_conditions: Vec::new(),
        actions: runtime_actions,
    })
}

fn resolve_action(
    action: &Action,
    npc_uuid_to_entry: &HashMap<Uuid, u32>,
    object_uuid_to_entry: &HashMap<Uuid, u32>,
    diagnostics: &mut Vec<Diagnostic>,
    unresolved: &mut u32,
) -> Result<GuardedAction, CompilerError> {
    let runtime_action = match &action.payload {
        ActionPayload::AcceptQuest(a) => {
            match resolve_npc_or_report(a.npc, npc_uuid_to_entry, action.id, "AcceptQuest", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::AcceptQuest(RuntimeAcceptQuest {
                    quest_id: a.quest,
                    npc_entry,
                    auto_complete_dialog: a.auto_complete_dialog,
                    optional: a.optional,
                }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".AcceptQuest {} (unresolved NPC)", a.quest),
                }),
            }
        }
        ActionPayload::TurnInQuest(t) => {
            match resolve_npc_or_report(t.npc, npc_uuid_to_entry, action.id, "TurnInQuest", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::TurnInQuest(RuntimeTurnInQuest {
                    quest_id: t.quest,
                    npc_entry,
                    choose_reward: t.choose_reward,
                    optional: t.optional,
                }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".TurnInQuest {} (unresolved NPC)", t.quest),
                }),
            }
        }
        ActionPayload::Travel(tr) => {
            // Pass through .goto coordinates from importer as waypoint
            let position = tr.position
                .map(|p| RuntimeWaypoint::new(p.map, p.world_x, p.world_y, p.world_z))
                .unwrap_or_else(|| RuntimeWaypoint::new(0, 0.0, 0.0, 0.0));
            RuntimeAction::Travel(RuntimeTravel {
                destination: tr.destination.clone(),
                position,
                tolerance: tr.tolerance,
                allow_flight: tr.allow_flight,
                timeout: tr.timeout,
            })
        }
        ActionPayload::Vendor(v) => {
            match resolve_npc_or_report(Some(v.npc), npc_uuid_to_entry, action.id, "Vendor", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::Vendor(RuntimeVendor {
                    npc_entry,
                    sell_grey: v.sell_grey,
                    repair: v.repair,
                    buy_items: v.buy_items.clone(),
                    minimum_free_slots: v.minimum_free_slots,
                }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".Vendor npc={} (unresolved NPC)", v.npc),
                }),
            }
        }
        ActionPayload::Train(tr) => {
            match resolve_npc_or_report(Some(tr.npc), npc_uuid_to_entry, action.id, "Train", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::Train(RuntimeTrain {
                    npc_entry,
                    spells: tr.spells.clone(),
                    trainer_type: tr.trainer_type.clone(),
                    minimum_level: tr.minimum_level,
                }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".Train npc={} spells={:?} (unresolved NPC)", tr.npc, tr.spells),
                }),
            }
        }
        ActionPayload::Flight(f) => {
            match resolve_npc_or_report(Some(f.npc), npc_uuid_to_entry, action.id, "Flight", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::Flight(RuntimeFlight {
                    npc_entry,
                    destination: f.destination.clone(),
                }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".Flight npc={} destination={} (unresolved NPC)", f.npc, f.destination),
                }),
            }
        }
        ActionPayload::Hearth(h) => {
            RuntimeAction::Hearth(RuntimeHearth {
                innkeeper_entry: h.innkeeper.and_then(|u| npc_uuid_to_entry.get(&u).copied()),
                destination: h.destination.clone(),
            })
        }
        // A `.unitscan` watch is INERT on this path, and deliberately so. `.unitscan` reached no
        // authoring carrier at all until the ADR-07 combat policy needed it (§5.6 fills
        // `CombatPolicy::watch_units` from it); before that the importer preserved it as a bare
        // `Comment`, and the live runtime has never killed anything because of one. Lowering it to
        // a `RuntimeAction::Kill` now would give 735 corpus lines new execution behaviour as a side
        // effect of an additive kernel field, so it stays what it was.
        ActionPayload::Kill(k) if k.watch => {
            RuntimeAction::Comment(RuntimeComment {
                text: format!(".unitscan {}", k.creature_entries.iter().map(u32::to_string).collect::<Vec<_>>().join(",")),
            })
        }
        ActionPayload::Kill(k) => {
            RuntimeAction::Kill(RuntimeKill {
                creature_entries: k.creature_entries.clone(),
                quantity: k.quantity,
                loot: k.loot,
                ignore_elites: k.ignore_elites,
            })
        }
        ActionPayload::UseItem(u) => {
            RuntimeAction::UseItem(RuntimeUseItem {
                item: u.item,
                target_entry: u.target.and_then(|e| npc_uuid_to_entry.get(&e).copied()),
            })
        }
        ActionPayload::Comment(c) => {
            RuntimeAction::Comment(RuntimeComment {
                text: c.text.clone(),
            })
        }
        // Additional action types (Wave 3 completions)
        ActionPayload::Repair(r) => {
            match resolve_npc_or_report(Some(r.npc), npc_uuid_to_entry, action.id, "Repair", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::Repair(RuntimeRepair { npc_entry }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".Repair npc={} (unresolved NPC)", r.npc),
                }),
            }
        }
        ActionPayload::LearnFlightPath(fp) => {
            match resolve_npc_or_report(Some(fp.npc), npc_uuid_to_entry, action.id, "LearnFlightPath", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::LearnFlightPath(RuntimeLearnFlightPath { npc_entry }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".LearnFlightPath npc={} (unresolved NPC)", fp.npc),
                }),
            }
        }
        ActionPayload::Condition(cond) => {
            // §23 DSL -> typed RuntimeCondition; unmappable: diagnostic first, THEN fail open to
            // AlwaysTrue (design Decision 7) — never silently substituted.
            let condition = condition::parse_condition(&cond.expression).unwrap_or_else(|err| {
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "UNMAPPED_CONDITION".to_string(),
                    message: format!(
                        "condition expression '{}' could not be mapped to a RuntimeCondition: {err}",
                        cond.expression
                    ),
                    entity: Some(cond.expression.clone()),
                    action: Some(action.id.to_string()),
                });
                RuntimeCondition::AlwaysTrue
            });
            RuntimeAction::Condition(RuntimeConditionAction { condition, role: cond.role })
        }
        ActionPayload::SetVariable(sv) => {
            RuntimeAction::SetVariable(RuntimeSetVariable {
                name: sv.name.clone(),
                value: sv.value.clone(),
            })
        }
        ActionPayload::Escort(e) => {
            match resolve_npc_or_report(Some(e.npc), npc_uuid_to_entry, action.id, "Escort", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::Escort(RuntimeEscort {
                    npc_entry,
                    area: e.area,
                    timeout: e.timeout,
                }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".Escort npc={} area={:?} (unresolved NPC)", e.npc, e.area),
                }),
            }
        }
        ActionPayload::Patrol(p) => {
            RuntimeAction::Patrol(RuntimePatrol {
                area: p.area,
                waypoints: p.waypoints.iter()
                    .map(|w| RuntimeWaypoint::new(w.map, w.world_x, w.world_y, w.world_z))
                    .collect(),
            })
        }
        ActionPayload::GrindArea(g) => {
            RuntimeAction::Grind(RuntimeGrind {
                polygon: g.polygon,
                targets: g.targets.clone(),
                loot: g.loot,
                timeout: g.timeout,
                minimum_kills: g.minimum_kills,
                maximum_kills: g.maximum_kills,
                stop_condition: g.stop_condition.clone(),
            })
        }
        ActionPayload::LootObject(l) => {
            // CL2: resolve the authoring object UUID to its concrete entry via the project's
            // object library (mirrors the NPC-resolution path). Unresolvable -> diagnostic +
            // `unresolved` tally, never a silent `0` masquerading as a valid entry.
            let object_entry = object_uuid_to_entry.get(&l.object).copied().unwrap_or_else(|| {
                *unresolved += 1;
                diagnostics.push(Diagnostic {
                    severity: Severity::Warning,
                    code: "UNRESOLVED_OBJECT".to_string(),
                    message: format!(
                        "loot object reference '{}' could not be resolved to an entry",
                        l.object
                    ),
                    entity: Some(l.object.to_string()),
                    action: Some(action.id.to_string()),
                });
                0
            });
            RuntimeAction::Loot(RuntimeLoot {
                object_entry,
                count: l.count,
            })
        }
        ActionPayload::Bank(b) => {
            match resolve_npc_or_report(Some(b.npc), npc_uuid_to_entry, action.id, "Bank", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::Bank(RuntimeBank { npc_entry }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".Bank npc={} (unresolved NPC)", b.npc),
                }),
            }
        }
        ActionPayload::Mailbox(m) => {
            match resolve_npc_or_report(Some(m.npc), npc_uuid_to_entry, action.id, "Mailbox", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::Mailbox(RuntimeMailbox { npc_entry }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".Mailbox npc={} (unresolved NPC)", m.npc),
                }),
            }
        }
        ActionPayload::InteractNPC(i) => {
            match resolve_npc_or_report(Some(i.npc), npc_uuid_to_entry, action.id, "InteractNpc", diagnostics, unresolved) {
                Some(npc_entry) => RuntimeAction::InteractNpc(RuntimeInteractNpc {
                    npc_entry,
                    gossip: i.gossip.clone(),
                }),
                None => RuntimeAction::Comment(RuntimeComment {
                    text: format!(".InteractNpc npc={} gossip={:?} (unresolved NPC)", i.npc, i.gossip),
                }),
            }
        }
        ActionPayload::Wait(w) => {
            RuntimeAction::Wait(RuntimeWait { duration: w.duration })
        }
        ActionPayload::SetHearth(sh) => {
            RuntimeAction::Hearth(RuntimeHearth {
                innkeeper_entry: sh.npc.and_then(|u| npc_uuid_to_entry.get(&u).copied()),
                destination: None,
            })
        }
    };

    // CL4: lower the authoring class-tail into a per-action guard. `None`/empty -> no guard,
    // unchanged behavior; unknown tokens -> diagnostic + no guard (fail open, never a guess).
    let guard = action.class_restriction
        .as_deref()
        .and_then(|r| parse_class_guard(r, action.id, diagnostics));

    Ok(GuardedAction { action: runtime_action, guard })
}