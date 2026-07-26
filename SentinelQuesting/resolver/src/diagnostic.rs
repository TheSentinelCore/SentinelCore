//! Resolver diagnostics.
//!
//! Distinct from [`sentinel_models::authoring::Diagnostic`], which points at an operation or an
//! action by *name*. Everything in the platform model is keyed by stable id, so a diagnostic that
//! could not name the node it came from would be unactionable in the IDE — `node_id` and `field`
//! are what let the editor put a squiggle on the right widget.
//!
//! [`Severity`] is re-exported rather than redefined: two severity vocabularies in one pipeline
//! would eventually disagree about what blocks a compile.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub use sentinel_models::authoring::Severity;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Diagnostic {
    pub severity: Severity,
    /// Stable, machine-readable, dotted (`resolver.field.missing`). The IDE routes on this; the
    /// message is for humans and may be reworded freely.
    pub code: String,
    pub message: String,
    /// The node the diagnostic belongs to. `None` for campaign-scoped problems (a dangling
    /// import, a campaign with no graph).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node_id: Option<Uuid>,
    /// The intent field at fault, when there is one — the Properties-panel widget to highlight.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub field: Option<String>,
}

impl Diagnostic {
    pub fn new(severity: Severity, code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            severity,
            code: code.into(),
            message: message.into(),
            node_id: None,
            field: None,
        }
    }

    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self::new(Severity::Error, code, message)
    }

    pub fn warning(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self::new(Severity::Warning, code, message)
    }

    pub fn info(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self::new(Severity::Info, code, message)
    }

    pub fn with_field(mut self, field: impl Into<String>) -> Self {
        self.field = Some(field.into());
        self
    }

    /// Stamped by the resolver, not by the task. A task type lowers one intent and has no idea
    /// which node instance it came from — leaving that to the caller keeps task plugins from
    /// having to thread an id they cannot use.
    pub fn with_node(mut self, node_id: Uuid) -> Self {
        self.node_id = Some(node_id);
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_diagnostic_without_a_node_or_field_omits_them() {
        let wire = serde_json::to_value(Diagnostic::error("x.y", "boom")).unwrap();
        assert!(wire.get("node_id").is_none(), "{wire}");
        assert!(wire.get("field").is_none(), "{wire}");
        assert_eq!(wire["severity"], "Error");
    }

    #[test]
    fn builders_attach_the_node_and_field_the_ide_needs() {
        let diagnostic = Diagnostic::warning("x.y", "boom")
            .with_field("count")
            .with_node(Uuid::from_u128(2));
        assert_eq!(diagnostic.field.as_deref(), Some("count"));
        assert_eq!(diagnostic.node_id, Some(Uuid::from_u128(2)));
    }
}
