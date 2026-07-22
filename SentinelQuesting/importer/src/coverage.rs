//! Coverage reporting (IF7, feeds CL5's corpus fidelity check): a per-command tally of how the
//! importer resolved guide commands — typed/semantic, inert-preserved (never-drop, IF7), or a
//! bare unresolved `Comment` — plus a JSON-serializable report and a human summary (design
//! Decision 6).

use std::collections::BTreeMap;

use sentinel_models::authoring::{Action, ActionPayload, Diagnostic, Project};

/// Outcome bucket for a single lowered command (IF7 never-drop taxonomy).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CoverageKind {
    /// Lowered to a non-`Comment` payload, or a typed `Condition` gate (IF2).
    Typed,
    /// Preserved as a typed inert `Comment` carrying a `COMMAND_PRESERVED_INERT` diagnostic (IF7).
    InertPreserved,
    /// A bare `Comment` with no never-drop diagnostic trail (unresolved NPC/quest, malformed args).
    Unresolved,
}

/// Per-command typed/inert-preserved/unresolved counts.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct CommandTally {
    pub typed: usize,
    pub inert_preserved: usize,
    pub unresolved: usize,
}

impl CommandTally {
    pub fn total(&self) -> usize {
        self.typed + self.inert_preserved + self.unresolved
    }

    fn record(&mut self, kind: CoverageKind) {
        match kind {
            CoverageKind::Typed => self.typed += 1,
            CoverageKind::InertPreserved => self.inert_preserved += 1,
            CoverageKind::Unresolved => self.unresolved += 1,
        }
    }
}

/// Corpus-wide coverage report (design Decision 6): per-command tallies plus the aggregate
/// totals, serializable to JSON and renderable as a human summary for `import-guides`.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct CoverageReport {
    pub per_command: BTreeMap<String, CommandTally>,
    pub totals: CommandTally,
}

impl CoverageReport {
    /// Build a report from a single imported project.
    pub fn from_project(project: &Project) -> Self {
        let mut report = Self::default();
        report.absorb(project);
        report
    }

    /// Build a report aggregated across every project in a bundle/corpus import (CL5).
    pub fn from_projects<'a>(projects: impl IntoIterator<Item = &'a Project>) -> Self {
        let mut report = Self::default();
        for project in projects {
            report.absorb(project);
        }
        report
    }

    fn absorb(&mut self, project: &Project) {
        for op in &project.operations {
            for action in &op.actions {
                let (name, kind) = classify(project, action);
                self.per_command.entry(name).or_default().record(kind);
                self.totals.record(kind);
            }
        }
    }

    /// Human-readable summary (design Decision 6: JSON + text summary alongside `import-guides`).
    pub fn text_summary(&self) -> String {
        let t = self.totals;
        let total = t.total().max(1);
        let pct = |n: usize| (n as f64 / total as f64) * 100.0;
        let mut out = format!(
            "Coverage: {} typed ({:.1}%), {} inert-preserved ({:.1}%), {} unresolved ({:.1}%) of {} commands\n",
            t.typed, pct(t.typed),
            t.inert_preserved, pct(t.inert_preserved),
            t.unresolved, pct(t.unresolved),
            t.total(),
        );
        for (name, tally) in &self.per_command {
            out.push_str(&format!(
                "  .{name}: {} typed, {} inert-preserved, {} unresolved\n",
                tally.typed, tally.inert_preserved, tally.unresolved
            ));
        }
        out
    }
}

fn classify(project: &Project, action: &Action) -> (String, CoverageKind) {
    match &action.payload {
        ActionPayload::Comment(c) => {
            let diag = project.diagnostics.iter()
                .find(|d| d.action.as_deref() == Some(action.id.to_string().as_str()));
            let name = command_name(diag, &c.text);
            match diag.map(|d| d.code.as_str()) {
                Some("COMMAND_PRESERVED_INERT") => (name, CoverageKind::InertPreserved),
                _ => (name, CoverageKind::Unresolved),
            }
        }
        typed => (typed_command_name(typed), CoverageKind::Typed),
    }
}

/// Best-effort command name for bucketing: prefer the diagnostic message (present for
/// `COMMAND_PRESERVED_INERT`/`MALFORMED_*`, both of which embed a quoted `.command`), else parse
/// the leading `.command` token off the Comment text itself (covers the `accept`/`turnin`/
/// `vendor`/`train`/`fly`/`fp` unresolved-NPC/quest fallbacks, which carry no per-action
/// diagnostic).
fn command_name(diag: Option<&Diagnostic>, comment_text: &str) -> String {
    diag.and_then(|d| {
        let start = d.message.find("'.")? + 2;
        let end = d.message[start..].find('\'')? + start;
        Some(d.message[start..end].to_string())
    })
    .unwrap_or_else(|| {
        comment_text
            .strip_prefix('.')
            .map(|rest| rest.chars().take_while(|c| c.is_alphanumeric()).collect::<String>())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "unknown".to_string())
    })
}

fn typed_command_name(payload: &ActionPayload) -> String {
    match payload {
        ActionPayload::AcceptQuest(_) => "accept",
        ActionPayload::TurnInQuest(_) => "turnin",
        ActionPayload::Travel(_) => "goto",
        ActionPayload::Kill(_) => "mob",
        ActionPayload::Vendor(_) => "vendor",
        ActionPayload::Train(_) => "train",
        ActionPayload::LearnFlightPath(_) => "fp",
        ActionPayload::UseItem(_) => "item",
        ActionPayload::Flight(_) => "fly",
        ActionPayload::Hearth(_) => "hs",
        ActionPayload::Condition(_) => "condition",
        _ => "typed",
    }
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_models::authoring::{AcceptQuestAction, Operation, Severity};
    use uuid::Uuid;

    fn project_with(actions: Vec<Action>, diagnostics: Vec<Diagnostic>) -> Project {
        let mut project = sentinel_models::authoring::new_project("Fixture");
        let mut op = Operation::new("Step 0");
        op.actions = actions;
        project.operations = vec![op];
        project.diagnostics = diagnostics;
        project
    }

    fn comment_action(id: Uuid, text: &str) -> Action {
        Action {
            id,
            enabled: true,
            condition: None,
            class_restriction: None,
            note: None,
            payload: ActionPayload::Comment(sentinel_models::authoring::CommentAction {
                text: text.to_string(),
            }),
        }
    }

    #[test]
    fn typed_inert_and_unresolved_commands_are_tallied_separately() {
        let typed_id = Uuid::new_v4();
        let inert_id = Uuid::new_v4();
        let unresolved_id = Uuid::new_v4();

        let typed = Action {
            id: typed_id,
            enabled: true,
            condition: None,
            class_restriction: None,
            note: None,
            payload: ActionPayload::AcceptQuest(AcceptQuestAction {
                quest: 1,
                npc: None,
                auto_complete_dialog: false,
                optional: false,
            }),
        };
        let inert = comment_action(inert_id, ".skill 171,300");
        let unresolved = comment_action(unresolved_id, ".turnin 999");

        let project = project_with(
            vec![typed, inert, unresolved],
            vec![Diagnostic {
                severity: Severity::Info,
                code: "COMMAND_PRESERVED_INERT".to_string(),
                message: "Command '.skill' is outside leveling-core semantic lowering; preserved \
                          as an inert action (args: [\"171\", \"300\"])"
                    .to_string(),
                entity: Some("step:0".to_string()),
                action: Some(inert_id.to_string()),
            }],
        );

        let report = CoverageReport::from_project(&project);
        assert_eq!(
            report.totals,
            CommandTally { typed: 1, inert_preserved: 1, unresolved: 1 }
        );
        assert_eq!(report.per_command.get("accept").unwrap().typed, 1);
        assert_eq!(report.per_command.get("skill").unwrap().inert_preserved, 1);
        assert_eq!(report.per_command.get("turnin").unwrap().unresolved, 1);
    }

    #[test]
    fn text_summary_reports_percentages_and_per_command_breakdown() {
        let mut report = CoverageReport::default();
        report.totals = CommandTally { typed: 3, inert_preserved: 1, unresolved: 0 };
        report.per_command.insert(
            "accept".to_string(),
            CommandTally { typed: 3, inert_preserved: 0, unresolved: 0 },
        );
        report.per_command.insert(
            "skill".to_string(),
            CommandTally { typed: 0, inert_preserved: 1, unresolved: 0 },
        );
        let text = report.text_summary();
        assert!(text.contains("3 typed"));
        assert!(text.contains("75.0%"));
        assert!(text.contains(".accept:"));
        assert!(text.contains(".skill:"));
    }

    #[test]
    fn from_projects_aggregates_multiple_projects() {
        let a = project_with(
            vec![Action {
                id: Uuid::new_v4(),
                enabled: true,
                condition: None,
                class_restriction: None,
                note: None,
                payload: ActionPayload::AcceptQuest(AcceptQuestAction {
                    quest: 1,
                    npc: None,
                    auto_complete_dialog: false,
                    optional: false,
                }),
            }],
            vec![],
        );
        let b = project_with(vec![comment_action(Uuid::new_v4(), ".turnin 2")], vec![]);
        let report = CoverageReport::from_projects([&a, &b]);
        assert_eq!(report.totals.typed, 1);
        assert_eq!(report.totals.unresolved, 1);
    }
}
