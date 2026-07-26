//! Campaign — the authored root document (ADR 09a §1.3).
//!
//! A campaign owns graphs, plus the two things graphs reference by id: [`Variable`]s and
//! [`ConditionDef`]s. It may import other campaigns and layer overrides on them by stable id;
//! overrides never mutate the imported source (ADR 09 §8).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{default_schema_version, Graph, Intent};
use crate::runtime::RuntimeCondition;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Campaign {
    #[serde(default = "default_schema_version")]
    pub schema_version: u32,
    pub id: Uuid,
    pub name: String,
    #[serde(default)]
    pub imports: Vec<CampaignImport>,
    #[serde(default)]
    pub variables: Vec<Variable>,
    #[serde(default)]
    pub conditions: Vec<ConditionDef>,
    #[serde(default)]
    pub graphs: Vec<Graph>,
}

impl Campaign {
    /// Mints a fresh v7 id. v7 is time-sortable, so creation order survives without a separate
    /// field, and ids are never reused or renumbered afterwards (ADR 09 §3.1).
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            schema_version: default_schema_version(),
            id: Uuid::now_v7(),
            name: name.into(),
            imports: Vec::new(),
            variables: Vec::new(),
            conditions: Vec::new(),
            graphs: Vec::new(),
        }
    }

    pub fn graph(&self, id: Uuid) -> Option<&Graph> {
        self.graphs.iter().find(|graph| graph.id == id)
    }

    pub fn condition(&self, id: Uuid) -> Option<&ConditionDef> {
        self.conditions.iter().find(|condition| condition.id == id)
    }
}

/// An imported campaign plus this campaign's override layer over it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CampaignImport {
    pub campaign: Uuid,
    #[serde(default)]
    pub overrides: Vec<NodeOverride>,
    #[serde(default)]
    pub disabled_nodes: Vec<Uuid>,
}

/// A partial intent patch applied to one imported node, keyed by that node's stable id. Only the
/// named fields change; the imported campaign is never rewritten.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NodeOverride {
    pub node: Uuid,
    pub intent: Intent,
}

/// A named condition a graph edge can point at by id.
///
/// The condition itself is flattened, so the wire form is `{ id, type, payload }` and the
/// `{ type, payload }` half is byte-identical to the [`RuntimeCondition`] the Lua runtime already
/// dispatches on. Do not un-flatten it and do not re-tag it: an externally tagged condition made
/// every non-unit variant miss the Lua handler table and fail open (see `CLAUDE.md` known state).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConditionDef {
    pub id: Uuid,
    #[serde(flatten)]
    pub condition: RuntimeCondition,
}

/// A campaign-scoped variable.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Variable {
    pub id: Uuid,
    pub name: String,
    #[serde(rename = "type")]
    pub var_type: VariableType,
    pub default: VariableValue,
}

/// The declared type of a [`Variable`].
///
/// Deliberately narrower than the ADR-02 authoring `VariableType`: its `QuestId`/`NpcId` cases are
/// entity pointers, and in this model entity pointers are [`super::EntityRef`] inside `intent`.
/// Keeping them here would also make the untagged `default` ambiguous — `783` could be `Int` or
/// `QuestId`, and a round-trip would silently pick one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VariableType {
    Bool,
    Int,
    Float,
    #[serde(rename = "string")]
    Text,
}

/// A variable's value. Serialized bare (`false`, `8`, `"goldshire"`) per ADR 09a §1.3 — it is
/// authoring state that the resolver reads, never a tagged value the Lua runtime dispatches on.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum VariableValue {
    Bool(bool),
    Int(i64),
    Float(f64),
    Text(String),
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platform::{Edge, Graph, Intent, Node, PLATFORM_SCHEMA_VERSION};
    use serde_json::json;

    /// The literal ADR 09a §1.3 document, with two edits: the plan abbreviates the Travel payload
    /// as `{ }`, which is not a `RuntimeTravel`, and its coordinate literals are not exactly
    /// representable in the `f32` that `RuntimeWaypoint` (a frozen runtime type) stores, which
    /// would make a byte-for-byte assertion test float formatting rather than the schema.
    fn plan_example() -> serde_json::Value {
        json!({
          "schema_version": 3,
          "id": "018f0000-0000-7000-8000-000000000001", "name": "Human 1-60",
          "imports": [ { "campaign": "018f0000-0000-7000-8000-000000000002",
                         "overrides": [], "disabled_nodes": [] } ],
          "variables": [ { "id": "018f0000-0000-7000-8000-000000000003",
                           "name": "hearth_set", "type": "bool", "default": false } ],
          "conditions": [ { "id": "018f0000-0000-7000-8000-000000000004",
                            "type": "LevelAtLeast", "payload": 10 } ],
          "graphs": [
            {
              "id": "018f0000-0000-7000-8000-000000000005", "name": "Elwynn Forest",
              "entry_node": "018f0000-0000-7000-8000-000000000006",
              "nodes": [
                {
                  "id": "018f0000-0000-7000-8000-000000000006",
                  "type": "questing.AcceptQuest",
                  "intent": { "quest": { "ref": "quest:783", "label": "Kobold Camp Cleanup" },
                              "from":  { "ref": "npc:823",   "label": "Deputy Willem" } },
                  "resolved": {
                    "actions": [
                      { "type": "Travel", "payload": {
                          "destination": "Northshire Abbey",
                          "position": { "map": 0, "world_x": -8933.5, "world_y": -136.5,
                                        "world_z": 83.25 },
                          "tolerance": 5.0, "allow_flight": false } },
                      { "type": "AcceptQuest", "payload": {
                          "quest_id": 783, "npc_entry": 823,
                          "auto_complete_dialog": false, "optional": false } }
                    ],
                    "resolved_at": "2026-07-26T14:00:00Z",
                    "db_fingerprint": "tbcmangos@a1b2c3",
                    "resolver_version": "1.0.0"
                  }
                }
              ],
              "edges": [ { "id": "018f0000-0000-7000-8000-000000000007",
                           "from": "018f0000-0000-7000-8000-000000000006",
                           "to": "018f0000-0000-7000-8000-000000000006", "guard": null } ]
            }
          ]
        })
    }

    #[test]
    fn the_plan_example_round_trips_byte_for_byte() {
        let document = plan_example();
        let campaign: Campaign = serde_json::from_value(document.clone()).unwrap();
        assert_eq!(campaign.schema_version, 3);
        assert_eq!(campaign.name, "Human 1-60");
        assert_eq!(serde_json::to_value(&campaign).unwrap(), document);
    }

    #[test]
    fn the_plan_example_resolves_its_typed_parts() {
        let campaign: Campaign = serde_json::from_value(plan_example()).unwrap();
        let graph = &campaign.graphs[0];
        let node = graph.node(graph.entry_node).expect("entry node must exist");
        assert_eq!(node.node_type, "questing.AcceptQuest");
        assert_eq!(node.intent.entity("quest").unwrap().id, 783);
        let resolved = node.resolved.as_ref().expect("example node is resolved");
        assert_eq!(resolved.actions.len(), 2);
        assert_eq!(resolved.db_fingerprint, "tbcmangos@a1b2c3");
        assert_eq!(campaign.imports[0].disabled_nodes.len(), 0);
        assert_eq!(campaign.variables[0].var_type, VariableType::Bool);
        assert_eq!(campaign.variables[0].default, VariableValue::Bool(false));
    }

    #[test]
    fn a_new_campaign_is_schema_version_3_with_a_v7_id() {
        let campaign = Campaign::new("Human 1-60");
        assert_eq!(campaign.schema_version, PLATFORM_SCHEMA_VERSION);
        assert_eq!(campaign.schema_version, 3);
        // v7 is time-sortable, which is what lets creation order survive without a separate field.
        assert_eq!(campaign.id.get_version_num(), 7);
    }

    #[test]
    fn ids_serialize_lowercase_hyphenated() {
        let campaign = Campaign::new("x");
        let text = serde_json::to_value(&campaign).unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        assert_eq!(text, text.to_lowercase());
        assert_eq!(text.matches('-').count(), 4);
        assert_eq!(text.len(), 36);
    }

    #[test]
    fn a_condition_def_keeps_the_adjacent_tagging_the_lua_runtime_dispatches_on() {
        // Externally tagged ({"LevelAtLeast": 10}) is what previously made every non-unit
        // condition fall through to fail-open `true` in Lua. Pin {type, payload}.
        let condition = ConditionDef {
            id: Uuid::from_u128(4),
            condition: RuntimeCondition::LevelAtLeast(10),
        };
        assert_eq!(
            serde_json::to_value(&condition).unwrap(),
            json!({ "id": "00000000-0000-0000-0000-000000000004",
                    "type": "LevelAtLeast", "payload": 10 })
        );
        let back: ConditionDef =
            serde_json::from_str(&serde_json::to_string(&condition).unwrap()).unwrap();
        assert_eq!(back, condition);
    }

    #[test]
    fn a_unit_condition_def_emits_type_only() {
        let condition = ConditionDef {
            id: Uuid::from_u128(5),
            condition: RuntimeCondition::AlwaysTrue,
        };
        let wire = serde_json::to_value(&condition).unwrap();
        assert_eq!(wire["type"], "AlwaysTrue");
        assert!(wire.get("payload").is_none(), "{wire}");
        let back: ConditionDef = serde_json::from_value(wire).unwrap();
        assert_eq!(back, condition);
    }

    #[test]
    fn every_variable_type_round_trips_with_its_value() {
        for (var_type, value, wire_type, wire_default) in [
            (
                VariableType::Bool,
                VariableValue::Bool(true),
                "bool",
                json!(true),
            ),
            (VariableType::Int, VariableValue::Int(-3), "int", json!(-3)),
            (
                VariableType::Float,
                VariableValue::Float(1.5),
                "float",
                json!(1.5),
            ),
            (
                VariableType::Text,
                VariableValue::Text("goldshire".into()),
                "string",
                json!("goldshire"),
            ),
        ] {
            let variable = Variable {
                id: Uuid::from_u128(3),
                name: "v".to_string(),
                var_type,
                default: value.clone(),
            };
            let wire = serde_json::to_value(&variable).unwrap();
            assert_eq!(wire["type"], wire_type);
            assert_eq!(wire["default"], wire_default);
            let back: Variable = serde_json::from_value(wire).unwrap();
            assert_eq!(back, variable);
        }
    }

    #[test]
    fn an_import_override_patches_intent_without_touching_the_source() {
        let mut patch = Intent::new();
        patch.insert("count", 8i64);
        let import = CampaignImport {
            campaign: Uuid::from_u128(2),
            overrides: vec![NodeOverride {
                node: Uuid::from_u128(6),
                intent: patch,
            }],
            disabled_nodes: vec![Uuid::from_u128(7)],
        };
        let wire = serde_json::to_value(&import).unwrap();
        assert_eq!(wire["overrides"][0]["intent"]["count"], 8);
        let back: CampaignImport = serde_json::from_value(wire).unwrap();
        assert_eq!(back, import);
    }

    #[test]
    fn an_empty_campaign_still_carries_its_collections() {
        let campaign = Campaign::new("empty");
        let wire = serde_json::to_value(&campaign).unwrap();
        for key in ["imports", "variables", "conditions", "graphs"] {
            assert!(wire[key].is_array(), "{key} must serialize as an array");
        }
        let back: Campaign = serde_json::from_value(wire).unwrap();
        assert_eq!(back, campaign);
    }

    #[test]
    fn a_linear_campaign_graph_round_trips() {
        let nodes: Vec<Node> = (1..=3)
            .map(|n| Node {
                id: Uuid::from_u128(n),
                node_type: "questing.Travel".to_string(),
                intent: Intent::new(),
                resolved: None,
                context: None,
            })
            .collect();
        let edges: Vec<Edge> = (1..=2)
            .map(|n| Edge {
                id: Uuid::from_u128(100 + n),
                from: Uuid::from_u128(n),
                to: Uuid::from_u128(n + 1),
                guard: None,
            })
            .collect();
        let mut campaign = Campaign::new("linear");
        campaign.graphs.push(Graph {
            id: Uuid::from_u128(10),
            name: "route".to_string(),
            entry_node: nodes[0].id,
            nodes,
            edges,
        });
        let back: Campaign =
            serde_json::from_str(&serde_json::to_string(&campaign).unwrap()).unwrap();
        assert_eq!(back, campaign);
        assert!(back.graphs[0].is_linear());
    }
}
