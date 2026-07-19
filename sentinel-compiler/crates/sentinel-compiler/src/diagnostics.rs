use serde::{Deserialize, Serialize};

/// Diagnostic severity level.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Severity {
    Error,
    Warning,
    Info,
}

/// Compilation stage that produced the diagnostic.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Stage {
    StructuralValidation,
    ReferenceResolution,
    BlueprintExpansion,
    DependencyResolution,
    GoalCoverage,
    Optimization,
    Lowering,
}

/// A single diagnostic message emitted by the compiler.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Diagnostic {
    pub severity: Severity,
    pub code: String,
    pub stage: Stage,
    pub message: String,
    pub entity: Option<String>,
    pub suggested_fix: Option<String>,
}

impl Diagnostic {
    pub fn error(code: impl Into<String>, stage: Stage, message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Error,
            code: code.into(),
            stage,
            message: message.into(),
            entity: None,
            suggested_fix: None,
        }
    }

    pub fn warning(code: impl Into<String>, stage: Stage, message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Warning,
            code: code.into(),
            stage,
            message: message.into(),
            entity: None,
            suggested_fix: None,
        }
    }

    pub fn info(code: impl Into<String>, stage: Stage, message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Info,
            code: code.into(),
            stage,
            message: message.into(),
            entity: None,
            suggested_fix: None,
        }
    }

    pub fn with_entity(mut self, entity: impl Into<String>) -> Self {
        self.entity = Some(entity.into());
        self
    }

    pub fn with_fix(mut self, fix: impl Into<String>) -> Self {
        self.suggested_fix = Some(fix.into());
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_diagnostic_creation() {
        let d = Diagnostic::error("C-1001", Stage::StructuralValidation, "duplicate id");
        assert_eq!(d.severity, Severity::Error);
        assert_eq!(d.code, "C-1001");
        assert!(d.entity.is_none());
        assert!(d.suggested_fix.is_none());
    }

    #[test]
    fn test_warning_with_entity_and_fix() {
        let d = Diagnostic::warning("C-1008", Stage::StructuralValidation, "version mismatch")
            .with_entity("Profile 'Test'")
            .with_fix("Update schema_version");
        assert_eq!(d.severity, Severity::Warning);
        assert_eq!(d.entity.as_deref(), Some("Profile 'Test'"));
        assert_eq!(d.suggested_fix.as_deref(), Some("Update schema_version"));
    }

    #[test]
    fn test_info_diagnostic_creation() {
        let d = Diagnostic::info("C-7001", Stage::Lowering, "Profile lowered successfully");
        assert_eq!(d.severity, Severity::Info);
        assert_eq!(d.code, "C-7001");
    }

    #[test]
    fn test_all_stage_variants() {
        assert!(matches!(Stage::StructuralValidation, Stage::StructuralValidation));
        assert!(matches!(Stage::ReferenceResolution, Stage::ReferenceResolution));
        assert!(matches!(Stage::BlueprintExpansion, Stage::BlueprintExpansion));
        assert!(matches!(Stage::DependencyResolution, Stage::DependencyResolution));
        assert!(matches!(Stage::GoalCoverage, Stage::GoalCoverage));
        assert!(matches!(Stage::Optimization, Stage::Optimization));
        assert!(matches!(Stage::Lowering, Stage::Lowering));
    }
}