//! Graph / Node / Edge and the two layers per node (ADR 09 §3, ADR 09a §1.3).
//!
//! A node holds authored `intent` and, when it has been through the resolver, the derived
//! `resolved`. A **linear route is a graph** — every node with exactly one unguarded outgoing
//! edge — so the retired corpus shape needs no special case.

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::EntityRef;
use crate::runtime::GuardedAction;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Graph {
    pub id: Uuid,
    pub name: String,
    pub entry_node: Uuid,
    #[serde(default)]
    pub nodes: Vec<Node>,
    #[serde(default)]
    pub edges: Vec<Edge>,
}

impl Graph {
    pub fn new(name: impl Into<String>, entry_node: Uuid) -> Self {
        Self {
            id: Uuid::now_v7(),
            name: name.into(),
            entry_node,
            nodes: Vec::new(),
            edges: Vec::new(),
        }
    }

    /// True when this graph is the degenerate linear route: every node has exactly one outgoing
    /// edge and that edge is unguarded (the terminal node has none).
    pub fn is_linear(&self) -> bool {
        self.nodes.iter().all(|node| {
            let mut out = self.edges.iter().filter(|edge| edge.from == node.id);
            match (out.next(), out.next()) {
                (Some(edge), None) => edge.guard.is_none(),
                (None, _) => true,
                _ => false,
            }
        })
    }

    pub fn node(&self, id: Uuid) -> Option<&Node> {
        self.nodes.iter().find(|node| node.id == id)
    }
}

/// One task instance. `type` is the registry key (`questing.AcceptQuest`) rather than an enum:
/// the task registry is the platform seam (ADR 09 §4), so a new domain registers a type without
/// editing this model.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Node {
    pub id: Uuid,
    #[serde(rename = "type")]
    pub node_type: String,
    /// The source of truth. Everything else about this node is recoverable from it.
    pub intent: Intent,
    /// Derived state. `None` until the resolver runs; any conflict with `intent` re-resolves.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolved: Option<Resolved>,
    /// Opaque provenance carried through untouched — chiefly the recorder's note of WHICH spawn of
    /// an entry a human actually used, since an entry like npc 823 has many and the resolver would
    /// otherwise guess.
    ///
    /// Held as raw JSON on purpose: the platform model must not learn what a recorder chooses to
    /// stamp here. Without the field serde would still ACCEPT it — unknown keys are ignored — and
    /// then drop it on the next serialize, so a recorded campaign would lose its provenance the
    /// first time any tool loaded and rewrote it, with no error to notice.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<serde_json::Value>,
}

impl Node {
    /// A fresh, unresolved node: intent only. `resolved` arrives from the resolver, never from an
    /// author.
    pub fn new(node_type: impl Into<String>, intent: Intent) -> Self {
        Self {
            id: Uuid::now_v7(),
            node_type: node_type.into(),
            intent,
            resolved: None,
            context: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Edge {
    pub id: Uuid,
    pub from: Uuid,
    pub to: Uuid,
    /// A [`super::ConditionDef`] id when the transition is gated; `null` is the sequential
    /// advance that today's linear routes use.
    #[serde(default)]
    pub guard: Option<Uuid>,
}

impl Edge {
    /// An unguarded edge — the sequential advance. Set `guard` afterwards to gate it.
    pub fn new(from: Uuid, to: Uuid) -> Self {
        Self {
            id: Uuid::now_v7(),
            from,
            to,
            guard: None,
        }
    }
}

/// The authored field bag for a node, keyed by the task type's schema field names.
///
/// A `BTreeMap` rather than insertion order because the resolver's purity requirement (same
/// intent + same `db_fingerprint` ⇒ byte-identical output) needs a deterministic key order.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Intent(pub BTreeMap<String, IntentValue>);

impl Intent {
    pub fn new() -> Self {
        Self(BTreeMap::new())
    }

    pub fn insert(&mut self, field: impl Into<String>, value: impl Into<IntentValue>) {
        self.0.insert(field.into(), value.into());
    }

    pub fn get(&self, field: &str) -> Option<&IntentValue> {
        self.0.get(field)
    }

    /// The entity behind a field, or `None` when the field is absent or is not a reference.
    pub fn entity(&self, field: &str) -> Option<&EntityRef> {
        match self.0.get(field) {
            Some(IntentValue::Entity(entity)) => Some(entity),
            _ => None,
        }
    }
}

/// A single authored field value.
///
/// Serialized untagged — the ADR fixes the authored JSON as plain `{ "count": 8 }` /
/// `{ "from": { "ref": … } }`, and this value never reaches the Lua runtime (only
/// [`Resolved::actions`] does), so the adjacent-tagging rule does not apply to it.
///
/// `Deserialize` is hand-written rather than `#[serde(untagged)]`: an untagged enum reports only
/// "data did not match any variant" and hides *why*, so a typo'd `"ref": "mount:1"` surfaced as an
/// unattributable parse failure instead of "unknown entity kind `mount`".
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(untagged)]
pub enum IntentValue {
    Entity(EntityRef),
    List(Vec<IntentValue>),
    Bool(bool),
    Int(i64),
    Float(f64),
    Text(String),
}

impl<'de> Deserialize<'de> for IntentValue {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        deserializer.deserialize_any(IntentValueVisitor)
    }
}

struct IntentValueVisitor;

impl<'de> serde::de::Visitor<'de> for IntentValueVisitor {
    type Value = IntentValue;

    fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("an intent field value: an entity reference object, a scalar, or a list")
    }

    fn visit_bool<E: serde::de::Error>(self, value: bool) -> Result<Self::Value, E> {
        Ok(IntentValue::Bool(value))
    }

    fn visit_i64<E: serde::de::Error>(self, value: i64) -> Result<Self::Value, E> {
        Ok(IntentValue::Int(value))
    }

    fn visit_u64<E: serde::de::Error>(self, value: u64) -> Result<Self::Value, E> {
        i64::try_from(value).map(IntentValue::Int).map_err(|_| {
            serde::de::Error::custom(format!("intent integer {value} is out of range"))
        })
    }

    fn visit_f64<E: serde::de::Error>(self, value: f64) -> Result<Self::Value, E> {
        Ok(IntentValue::Float(value))
    }

    fn visit_str<E: serde::de::Error>(self, value: &str) -> Result<Self::Value, E> {
        Ok(IntentValue::Text(value.to_string()))
    }

    fn visit_seq<A: serde::de::SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
        let mut items = Vec::new();
        while let Some(item) = seq.next_element()? {
            items.push(item);
        }
        Ok(IntentValue::List(items))
    }

    fn visit_map<A: serde::de::MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let mut reference: Option<String> = None;
        let mut label = String::new();
        while let Some(key) = map.next_key::<String>()? {
            match key.as_str() {
                "ref" => reference = Some(map.next_value()?),
                "label" => label = map.next_value()?,
                other => {
                    return Err(serde::de::Error::custom(format!(
                        "unknown intent object field `{other}` (an object value must be an entity reference)"
                    )))
                }
            }
        }
        let reference = reference.ok_or_else(|| serde::de::Error::missing_field("ref"))?;
        let mut entity = EntityRef::parse(&reference).map_err(serde::de::Error::custom)?;
        entity.label = label;
        Ok(IntentValue::Entity(entity))
    }
}

impl From<EntityRef> for IntentValue {
    fn from(value: EntityRef) -> Self {
        IntentValue::Entity(value)
    }
}

impl From<bool> for IntentValue {
    fn from(value: bool) -> Self {
        IntentValue::Bool(value)
    }
}

impl From<i64> for IntentValue {
    fn from(value: i64) -> Self {
        IntentValue::Int(value)
    }
}

impl From<f64> for IntentValue {
    fn from(value: f64) -> Self {
        IntentValue::Float(value)
    }
}

impl From<String> for IntentValue {
    fn from(value: String) -> Self {
        IntentValue::Text(value)
    }
}

impl From<&str> for IntentValue {
    fn from(value: &str) -> Self {
        IntentValue::Text(value.to_string())
    }
}

impl From<Vec<IntentValue>> for IntentValue {
    fn from(value: Vec<IntentValue>) -> Self {
        IntentValue::List(value)
    }
}

/// Derived state: what the resolver made of an `intent`, and what it made it against.
///
/// `db_fingerprint` + `resolver_version` are what make staleness detectable — a database or
/// resolver update flags every node resolved against the old pair, and bulk re-resolution becomes
/// a diffable operation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Resolved {
    /// The frozen runtime vocabulary, nothing else. A task needing a new action type is a runtime
    /// change with its own review (ADR 09 §4).
    #[serde(default)]
    pub actions: Vec<GuardedAction>,
    pub resolved_at: DateTime<Utc>,
    pub db_fingerprint: String,
    pub resolver_version: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platform::EntityKind;
    use crate::runtime::{RuntimeAcceptQuest, RuntimeAction, RuntimeTravel, RuntimeWaypoint};
    use serde_json::json;

    fn accept_quest_node() -> Node {
        let mut intent = Intent::new();
        intent.insert(
            "quest",
            EntityRef::new(EntityKind::Quest, 783, "Kobold Camp Cleanup"),
        );
        intent.insert(
            "from",
            EntityRef::new(EntityKind::Npc, 823, "Deputy Willem"),
        );
        Node {
            id: Uuid::nil(),
            node_type: "questing.AcceptQuest".to_string(),
            intent,
            resolved: None,
            context: None,
        }
    }

    #[test]
    fn constructors_mint_v7_ids() {
        // One enforcement point for ADR 09 §3.1: ids are v7 (time-sortable) at creation. A v4 here
        // would still serialize fine and silently lose creation order.
        let node = Node::new("questing.AcceptQuest", Intent::new());
        let graph = Graph::new("Elwynn Forest", node.id);
        let edge = Edge::new(node.id, node.id);
        assert_eq!(node.id.get_version_num(), 7);
        assert_eq!(graph.id.get_version_num(), 7);
        assert_eq!(edge.id.get_version_num(), 7);
        assert!(node.resolved.is_none(), "a new node is intent-only");
        assert!(edge.guard.is_none(), "a new edge is the sequential advance");
    }

    #[test]
    fn an_unresolved_node_omits_resolved_entirely() {
        // The recorder (W5) writes campaigns with intent only; `resolved` must not appear as
        // `null` noise in the authored file.
        let json = serde_json::to_value(accept_quest_node()).unwrap();
        assert!(json.get("resolved").is_none(), "{json}");
        assert_eq!(json["type"], "questing.AcceptQuest");
    }

    #[test]
    fn intent_entity_fields_deserialize_as_typed_refs_not_strings() {
        let node: Node = serde_json::from_value(json!({
            "id": "00000000-0000-0000-0000-000000000000",
            "type": "questing.AcceptQuest",
            "intent": {
                "quest": { "ref": "quest:783", "label": "Kobold Camp Cleanup" },
                "from":  { "ref": "npc:823",   "label": "Deputy Willem" }
            }
        }))
        .unwrap();
        let from = node.intent.entity("from").expect("from must be an entity");
        assert_eq!(from.kind, EntityKind::Npc);
        assert_eq!(from.id, 823);
        assert!(node.resolved.is_none(), "resolved is derived, not authored");
    }

    #[test]
    fn intent_carries_scalars_alongside_entities() {
        let mut intent = Intent::new();
        intent.insert(
            "target",
            EntityRef::new(EntityKind::Npc, 299, "Kobold Vermin"),
        );
        intent.insert("count", 8i64);
        intent.insert("loot", true);
        let round: Intent = serde_json::from_value(serde_json::to_value(&intent).unwrap()).unwrap();
        assert_eq!(round, intent);
        assert_eq!(round.get("count"), Some(&IntentValue::Int(8)));
    }

    #[test]
    fn a_malformed_intent_ref_fails_the_whole_node() {
        // Fail loud: an unparseable ref must not degrade into the string "mount:1".
        let err = serde_json::from_value::<Node>(json!({
            "id": "00000000-0000-0000-0000-000000000000",
            "type": "questing.AcceptQuest",
            "intent": { "from": { "ref": "mount:1", "label": "x" } }
        }))
        .expect_err("an invalid ref must not deserialize");
        assert!(err.to_string().contains("mount"), "{err}");
    }

    #[test]
    fn resolved_actions_keep_the_adjacent_tagging_the_lua_runtime_dispatches_on() {
        // An externally tagged enum ({"AcceptQuest": {...}}) makes the Lua handler table miss and
        // fall through fail-open. Pin the {type, payload} bytes here.
        let resolved = Resolved {
            actions: vec![RuntimeAction::AcceptQuest(RuntimeAcceptQuest {
                quest_id: 783,
                npc_entry: 823,
                auto_complete_dialog: false,
                optional: false,
            })
            .into()],
            resolved_at: "2026-07-26T14:00:00Z".parse().unwrap(),
            db_fingerprint: "tbcmangos@a1b2c3".to_string(),
            resolver_version: "1.0.0".to_string(),
        };
        let json = serde_json::to_value(&resolved).unwrap();
        assert_eq!(json["actions"][0]["type"], "AcceptQuest");
        assert_eq!(json["actions"][0]["payload"]["quest_id"], 783);
        assert_eq!(json["actions"][0]["payload"]["npc_entry"], 823);
        assert_eq!(json["resolved_at"], "2026-07-26T14:00:00Z");
        assert_eq!(json["db_fingerprint"], "tbcmangos@a1b2c3");
        assert_eq!(json["resolver_version"], "1.0.0");
    }

    #[test]
    fn resolved_round_trips_with_the_full_travel_payload() {
        let resolved = Resolved {
            actions: vec![RuntimeAction::Travel(RuntimeTravel {
                destination: "Northshire Abbey".to_string(),
                position: RuntimeWaypoint {
                    map: 0,
                    world_x: -8933.4,
                    world_y: -136.4,
                    world_z: 83.2,
                },
                tolerance: 5.0,
                allow_flight: false,
                timeout: None,
            })
            .into()],
            resolved_at: "2026-07-26T14:00:00Z".parse().unwrap(),
            db_fingerprint: "tbcmangos@a1b2c3".to_string(),
            resolver_version: "1.0.0".to_string(),
        };
        let back: Resolved =
            serde_json::from_str(&serde_json::to_string(&resolved).unwrap()).unwrap();
        assert_eq!(back, resolved);
    }

    #[test]
    fn a_linear_route_is_a_graph_of_unguarded_single_out_edges() {
        let a = accept_quest_node();
        let mut b = accept_quest_node();
        b.id = Uuid::from_u128(2);
        let mut c = accept_quest_node();
        c.id = Uuid::from_u128(3);

        let graph = Graph {
            id: Uuid::from_u128(10),
            name: "Elwynn Forest".to_string(),
            entry_node: a.id,
            edges: vec![
                Edge {
                    id: Uuid::from_u128(20),
                    from: a.id,
                    to: b.id,
                    guard: None,
                },
                Edge {
                    id: Uuid::from_u128(21),
                    from: b.id,
                    to: c.id,
                    guard: None,
                },
            ],
            nodes: vec![a, b, c],
        };

        let back: Graph = serde_json::from_str(&serde_json::to_string(&graph).unwrap()).unwrap();
        assert_eq!(back, graph);
        assert!(back.is_linear(), "every node has one unguarded out-edge");
        let wire = serde_json::to_value(&graph).unwrap();
        assert_eq!(wire["edges"][0]["guard"], serde_json::Value::Null);
    }

    #[test]
    fn a_guarded_branch_is_not_linear() {
        let a = accept_quest_node();
        let mut b = accept_quest_node();
        b.id = Uuid::from_u128(2);
        let graph = Graph {
            id: Uuid::from_u128(10),
            name: "branchy".to_string(),
            entry_node: a.id,
            edges: vec![Edge {
                id: Uuid::from_u128(20),
                from: a.id,
                to: b.id,
                guard: Some(Uuid::from_u128(99)),
            }],
            nodes: vec![a, b],
        };
        assert!(!graph.is_linear());
        assert_eq!(
            serde_json::to_value(&graph).unwrap()["edges"][0]["guard"],
            "00000000-0000-0000-0000-000000000063"
        );
    }
}

#[cfg(test)]
mod context_passthrough_tests {
    use super::*;
    use serde_json::json;

    /// The recorder (ADR 09a W5) stamps a `context` block on every node it emits — most
    /// importantly WHICH spawn of an entry the human actually used, since an entry like npc 823
    /// has many and the resolver otherwise has to guess.
    ///
    /// Serde ignores unknown fields by default, which makes that data look safe: it deserializes
    /// without error. It is then dropped on the next serialize, so a recorded campaign loses its
    /// provenance the first time any tool loads and rewrites it — silently, with no diagnostic.
    /// That is the same failure class as the externally-tagged `RuntimeCondition`: valid-looking
    /// JSON, no error, wrong behavior. The field is carried opaquely so the platform model never
    /// has to know what a recorder puts in it.
    #[test]
    fn recorder_context_survives_a_round_trip() {
        let raw = json!({
            "id": "018f2c00-0000-7000-8000-000000000001",
            "type": "questing.AcceptQuest",
            "intent": {},
            "context": { "observed_spawn": { "map": 0, "x": -8933.5, "y": -136.5, "z": 83.25 } }
        });

        let node: Node = serde_json::from_value(raw.clone()).expect("node with context parses");
        let back = serde_json::to_value(&node).expect("node re-serializes");

        assert_eq!(
            back.get("context"),
            raw.get("context"),
            "recorder context must survive load-and-rewrite, not be silently dropped"
        );
    }

    /// A node without context must not grow an empty key — recorded and hand-authored nodes stay
    /// byte-identical where they are semantically identical, which is what keeps re-resolution
    /// diffable.
    #[test]
    fn absent_context_is_not_serialized() {
        let node = Node::new("questing.Travel", Intent::new());
        let value = serde_json::to_value(&node).expect("serializes");
        assert!(value.get("context").is_none(), "absent context must stay absent");
    }
}
