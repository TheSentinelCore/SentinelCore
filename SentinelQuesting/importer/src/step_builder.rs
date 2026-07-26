//! [`StepBuilder`]: group the step-region token stream into [`Step`](crate::Step) AST nodes.
//!
//! A [`Token::StepStart`](crate::Token::StepStart) opens a new step; subsequent directive,
//! command, and text tokens attach to the open step until the next `StepStart`.

use crate::{Command, Directive, Step, Token};
use super::name_hints::extract_npc_name_hints;

pub struct StepBuilder;

impl StepBuilder {
    pub fn build(tokens: &[Token]) -> Vec<Step> {
        let mut steps: Vec<Step> = Vec::new();
        let mut current: Option<Step> = None;

        for tok in tokens {
            match tok {
                Token::StepStart { conditions, gate, line } => {
                    if let Some(s) = current.take() {
                        steps.push(s);
                    }
                    current = Some(Step {
                        index: steps.len(),
                        line: *line,
                        // A step with no body spans exactly its marker line.
                        line_end: *line,
                        conditions: conditions.clone(),
                        gate: gate.clone(),
                        directives: Vec::new(),
                        commands: Vec::new(),
                        text: Vec::new(),
                        npc_name_hints: Vec::new(),
                    });
                }
                Token::StepDirective { name, value, line, original } => {
                    if let Some(s) = current.as_mut() {
                        s.line_end = s.line_end.max(*line);
                        s.directives.push(Directive {
                            name: name.clone(),
                            value: value.clone(),
                            line: *line,
                            original: original.clone(),
                        });
                    }
                }
                Token::Command { name, args, note, line, class_restriction } => {
                    if let Some(s) = current.as_mut() {
                        s.line_end = s.line_end.max(*line);
                        s.commands.push(Command {
                            name: name.clone(),
                            args: args.clone(),
                            note: note.clone(),
                            line: *line,
                            class_restriction: class_restriction.clone(),
                        });
                        // Extract NPC name hints from command notes
                        if let Some(note_text) = note {
                            s.npc_name_hints.extend(extract_npc_name_hints(note_text));
                        }
                    }
                }
                Token::Text { content, line } => {
                    if let Some(s) = current.as_mut() {
                        s.line_end = s.line_end.max(*line);
                        s.text.push(content.clone());
                        // Extract NPC name hints from text lines
                        s.npc_name_hints.extend(extract_npc_name_hints(content));
                    }
                }
                Token::GuideHeader { .. } => {
                    // Headers are not part of any step.
                }
            }
        }
        if let Some(s) = current.take() {
            steps.push(s);
        }
        steps
    }
}
