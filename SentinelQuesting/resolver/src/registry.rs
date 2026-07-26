//! The task registry — the platform seam (ADR 09 §4).
//!
//! A task type is **data**: a name, a field schema, a pure lowering, and a validation. The core
//! registry knows no task types; a domain registers its own. That is what keeps this a platform
//! instead of a quest editor with extra steps.
//!
//! Two rules from ADR 09 §4 are enforced here rather than documented:
//!
//! 1. The IDE renders its Properties panel **from** [`TaskType::schema`], so the schema is
//!    serializable and complete. A hand-coded panel per task type would build a quest editor
//!    permanently, whatever the document is called.
//! 2. A task lowers only to the existing [`sentinel_models::runtime::RuntimeAction`] vocabulary.
//!    That is a frozen contract this phase — a task needing a new action is a runtime change with
//!    its own review, not an editor feature.

use std::collections::BTreeMap;

use sentinel_models::platform::{EntityKind, EntityRef, Intent, IntentValue};
use sentinel_models::runtime::GuardedAction;
use serde::{Serialize, Serializer};
use thiserror::Error;

use crate::db::ResolverDb;
use crate::diagnostic::{Diagnostic, Severity};

/// Pure: intent + database in, actions out. Diagnostics are pushed rather than returned so a
/// partial lowering can report what it had to drop and still emit the rest — an unresolvable
/// spawn costs the `Travel`, not the interaction that followed it.
///
/// A plain `fn` pointer rather than a boxed closure: task types are static data, and a `fn` keeps
/// [`TaskType`] `Copy`-cheap to clone and impossible to close over mutable state, which is one
/// fewer way to break purity.
pub type LowerFn = fn(&Intent, &dyn ResolverDb, &mut Vec<Diagnostic>) -> Vec<GuardedAction>;

/// Task-specific validation, run after the schema check below. Returns only what the schema
/// cannot express (cross-field requirements, database-backed checks).
pub type ValidateFn = fn(&Intent, &dyn ResolverDb) -> Vec<Diagnostic>;

/// What widget the IDE renders for a field.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FieldKind {
    Entity,
    EntityList,
    Int,
    Float,
    Bool,
    Text,
}

/// A constraint the IDE can enforce inline and the resolver re-checks. Adjacently tagged for
/// consistency with every other enum on the wire in this pipeline.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", content = "payload")]
pub enum ValidationRule {
    MinInt(i64),
    MaxInt(i64),
    NonEmptyText,
    /// Drives a dropdown in the Properties panel instead of a free-text box.
    OneOf(&'static [&'static str]),
}

/// One authored field of a task type. This is the Properties panel, as data.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Field {
    pub name: &'static str,
    pub kind: FieldKind,
    /// Drives entity autocomplete. `None` on an [`FieldKind::Entity`] field means "any kind" —
    /// `questing.Travel` accepts an npc, an object, or an area as its destination, and pinning it
    /// to one would make the other two unauthorable.
    #[serde(
        skip_serializing_if = "Option::is_none",
        serialize_with = "serialize_entity_type"
    )]
    pub entity_type: Option<EntityKind>,
    pub required: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub rules: Vec<ValidationRule>,
}

/// [`EntityKind`] is not `Serialize` in the model — there it only ever exists inside the `ref`
/// string. The schema needs it as a bare kind name for autocomplete, so it is written out here
/// rather than by widening the model's public surface.
fn serialize_entity_type<S: Serializer>(
    value: &Option<EntityKind>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    match value {
        Some(kind) => serializer.serialize_str(kind.as_str()),
        None => serializer.serialize_none(),
    }
}

impl Field {
    pub const fn new(name: &'static str, kind: FieldKind) -> Self {
        Self {
            name,
            kind,
            entity_type: None,
            required: false,
            rules: Vec::new(),
        }
    }

    pub const fn entity(name: &'static str, entity_type: EntityKind) -> Self {
        Self {
            name,
            kind: FieldKind::Entity,
            entity_type: Some(entity_type),
            required: false,
            rules: Vec::new(),
        }
    }

    pub const fn entity_list(name: &'static str, entity_type: EntityKind) -> Self {
        Self {
            name,
            kind: FieldKind::EntityList,
            entity_type: Some(entity_type),
            required: false,
            rules: Vec::new(),
        }
    }

    pub const fn required(mut self) -> Self {
        self.required = true;
        self
    }

    pub fn with_rules(mut self, rules: Vec<ValidationRule>) -> Self {
        self.rules = rules;
        self
    }
}

#[derive(Clone)]
pub struct TaskType {
    /// Namespaced by domain (`questing.AcceptQuest`). The namespace is what lets a second domain
    /// register `crafting.SmeltOre` without coordinating with this one.
    pub type_name: &'static str,
    pub schema: Vec<Field>,
    pub lower: LowerFn,
    pub validate: ValidateFn,
}

impl std::fmt::Debug for TaskType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TaskType")
            .field("type_name", &self.type_name)
            .field("schema", &self.schema)
            .finish_non_exhaustive()
    }
}

impl TaskType {
    /// Everything wrong with an intent: the schema check first, then the task's own rules.
    pub fn check(&self, intent: &Intent, db: &dyn ResolverDb) -> Vec<Diagnostic> {
        let mut diagnostics = self.check_schema(intent);
        diagnostics.extend((self.validate)(intent, db));
        diagnostics
    }

    /// The generic half, derived entirely from [`Self::schema`]. Every task gets required-field,
    /// kind, entity-kind, and rule checking for free — which is what makes hand-writing a
    /// per-task validator (and, eventually, a per-task panel) unnecessary.
    pub fn check_schema(&self, intent: &Intent) -> Vec<Diagnostic> {
        let mut diagnostics = Vec::new();

        for field in &self.schema {
            let Some(value) = intent.get(field.name) else {
                if field.required {
                    diagnostics.push(
                        Diagnostic::error(
                            "resolver.field.missing",
                            format!("`{}` requires a `{}`", self.type_name, field.name),
                        )
                        .with_field(field.name),
                    );
                }
                continue;
            };
            check_value(field, value, &mut diagnostics);
        }

        // Authored keys with no schema field are a warning, not an error: a campaign written
        // against a newer task schema must still resolve on an older resolver rather than refuse
        // to produce a plan at all.
        for name in intent.0.keys() {
            if !self.schema.iter().any(|field| field.name == name) {
                diagnostics.push(
                    Diagnostic::warning(
                        "resolver.field.unknown",
                        format!("`{}` has no field `{name}`", self.type_name),
                    )
                    .with_field(name.clone()),
                );
            }
        }

        diagnostics
    }
}

fn check_value(field: &Field, value: &IntentValue, diagnostics: &mut Vec<Diagnostic>) {
    let kind_ok = match (field.kind, value) {
        (FieldKind::Entity, IntentValue::Entity(entity)) => {
            check_entity_kind(field, entity, diagnostics);
            true
        }
        (FieldKind::EntityList, IntentValue::List(items)) => {
            for item in items {
                match item {
                    IntentValue::Entity(entity) => check_entity_kind(field, entity, diagnostics),
                    _ => diagnostics.push(
                        Diagnostic::error(
                            "resolver.field.kind",
                            format!("`{}` must hold entity references", field.name),
                        )
                        .with_field(field.name),
                    ),
                }
            }
            true
        }
        (FieldKind::Int, IntentValue::Int(_)) => true,
        // JSON `83` deserializes as an integer and `83.0` as a float, so a coordinate authored
        // without a decimal point would otherwise be rejected as the wrong kind.
        (FieldKind::Float, IntentValue::Int(_) | IntentValue::Float(_)) => true,
        (FieldKind::Bool, IntentValue::Bool(_)) => true,
        (FieldKind::Text, IntentValue::Text(_)) => true,
        _ => false,
    };

    if !kind_ok {
        diagnostics.push(
            Diagnostic::error(
                "resolver.field.kind",
                format!(
                    "`{}` expects {:?}, found {}",
                    field.name,
                    field.kind,
                    describe(value)
                ),
            )
            .with_field(field.name),
        );
        return;
    }

    for rule in &field.rules {
        check_rule(field, rule, value, diagnostics);
    }
}

fn check_entity_kind(field: &Field, entity: &EntityRef, diagnostics: &mut Vec<Diagnostic>) {
    let Some(expected) = field.entity_type else {
        return;
    };
    if entity.kind != expected {
        diagnostics.push(
            Diagnostic::error(
                "resolver.field.entity_kind",
                format!(
                    "`{}` expects a {expected} reference, found `{}`",
                    field.name,
                    entity.as_ref_string()
                ),
            )
            .with_field(field.name),
        );
    }
}

fn check_rule(
    field: &Field,
    rule: &ValidationRule,
    value: &IntentValue,
    diagnostics: &mut Vec<Diagnostic>,
) {
    let violation = match (rule, value) {
        (ValidationRule::MinInt(min), IntentValue::Int(n)) if n < min => {
            Some(format!("`{}` must be at least {min}", field.name))
        }
        (ValidationRule::MaxInt(max), IntentValue::Int(n)) if n > max => {
            Some(format!("`{}` must be at most {max}", field.name))
        }
        (ValidationRule::NonEmptyText, IntentValue::Text(text)) if text.trim().is_empty() => {
            Some(format!("`{}` must not be blank", field.name))
        }
        (ValidationRule::OneOf(allowed), IntentValue::Text(text))
            if !allowed.contains(&text.as_str()) =>
        {
            Some(format!(
                "`{}` must be one of {}",
                field.name,
                allowed.join(", ")
            ))
        }
        _ => None,
    };

    if let Some(message) = violation {
        diagnostics
            .push(Diagnostic::new(Severity::Error, "resolver.field.rule", message).with_field(field.name));
    }
}

fn describe(value: &IntentValue) -> &'static str {
    match value {
        IntentValue::Entity(_) => "an entity reference",
        IntentValue::List(_) => "a list",
        IntentValue::Bool(_) => "a boolean",
        IntentValue::Int(_) => "an integer",
        IntentValue::Float(_) => "a float",
        IntentValue::Text(_) => "text",
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum RegistryError {
    #[error("task type `{0}` is already registered")]
    Duplicate(String),
}

/// The registered task types.
///
/// A `BTreeMap` rather than a `HashMap`: [`TaskRegistry::type_names`] feeds the IDE's task palette
/// and, more importantly, iteration order must never be able to leak into resolver output.
#[derive(Debug, Clone, Default)]
pub struct TaskRegistry {
    types: BTreeMap<&'static str, TaskType>,
}

impl TaskRegistry {
    /// Empty. The core knows no task types — see ADR 09 §4.
    pub fn new() -> Self {
        Self::default()
    }

    /// The core plus the questing domain plugin.
    pub fn with_questing() -> Self {
        let mut registry = Self::new();
        for task in crate::tasks::questing_task_types() {
            registry
                .register(task)
                .expect("the questing task set has no duplicate names");
        }
        registry
    }

    /// Rejects rather than shadows a duplicate: two plugins claiming one name is a build-order
    /// bug, and silently letting the last one win would make which lowering ran depend on
    /// registration order.
    pub fn register(&mut self, task: TaskType) -> Result<(), RegistryError> {
        if self.types.contains_key(task.type_name) {
            return Err(RegistryError::Duplicate(task.type_name.to_string()));
        }
        self.types.insert(task.type_name, task);
        Ok(())
    }

    pub fn get(&self, type_name: &str) -> Option<&TaskType> {
        self.types.get(type_name)
    }

    /// Sorted, always.
    pub fn type_names(&self) -> impl Iterator<Item = &'static str> + '_ {
        self.types.keys().copied()
    }

    pub fn types(&self) -> impl Iterator<Item = &TaskType> + '_ {
        self.types.values()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::InMemoryDb;

    fn no_actions(_: &Intent, _: &dyn ResolverDb, _: &mut Vec<Diagnostic>) -> Vec<GuardedAction> {
        Vec::new()
    }

    fn no_validation(_: &Intent, _: &dyn ResolverDb) -> Vec<Diagnostic> {
        Vec::new()
    }

    fn task() -> TaskType {
        TaskType {
            type_name: "test.Thing",
            schema: vec![
                Field::entity("npc", EntityKind::Npc).required(),
                Field::new("count", FieldKind::Int).with_rules(vec![
                    ValidationRule::MinInt(1),
                    ValidationRule::MaxInt(10),
                ]),
                Field::new("mode", FieldKind::Text)
                    .with_rules(vec![ValidationRule::OneOf(&["fast", "slow"])]),
            ],
            lower: no_actions,
            validate: no_validation,
        }
    }

    #[test]
    fn the_schema_alone_catches_a_missing_required_field() {
        let diagnostics = task().check_schema(&Intent::new());
        assert_eq!(diagnostics.len(), 1);
        assert_eq!(diagnostics[0].code, "resolver.field.missing");
        assert_eq!(diagnostics[0].field.as_deref(), Some("npc"));
    }

    #[test]
    fn a_maximum_and_a_one_of_rule_are_both_enforced() {
        let mut intent = Intent::new();
        intent.insert("npc", EntityRef::new(EntityKind::Npc, 1, "x"));
        intent.insert("count", 99i64);
        intent.insert("mode", "sideways");
        let diagnostics = task().check_schema(&intent);
        assert_eq!(diagnostics.len(), 2, "{diagnostics:#?}");
        assert!(diagnostics.iter().all(|d| d.code == "resolver.field.rule"));
    }

    #[test]
    fn a_registry_is_empty_until_something_registers() {
        assert_eq!(TaskRegistry::new().type_names().count(), 0);
    }

    #[test]
    fn registering_twice_is_an_error_not_a_silent_replacement() {
        let mut registry = TaskRegistry::new();
        registry.register(task()).unwrap();
        assert_eq!(
            registry.register(task()),
            Err(RegistryError::Duplicate("test.Thing".to_string()))
        );
    }

    #[test]
    fn check_runs_the_schema_and_then_the_task_rules() {
        let db = InMemoryDb::new("test@0");
        let mut intent = Intent::new();
        intent.insert("npc", EntityRef::new(EntityKind::Quest, 1, "x"));
        let diagnostics = task().check(&intent, &db as &dyn ResolverDb);
        assert_eq!(diagnostics[0].code, "resolver.field.entity_kind");
    }
}
