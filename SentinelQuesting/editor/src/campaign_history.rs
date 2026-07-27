//! CampaignHistory — command-pattern undo/redo for campaign graph mutations.
//!
//! Each graph/edge/node mutation is wrapped in a `CampaignCommand` that stores
//! enough information to reverse itself. `CampaignHistory` manages the undo/redo
//! stacks and enforces the history depth limit.

use sentinel_models::platform::{
    Campaign, ConditionDef, Edge, Graph, Node,
};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Trait
// ---------------------------------------------------------------------------

/// A single reversible mutation on a `Campaign`.
pub trait CampaignCommand: Send + Sync {
    /// Apply the forward mutation.
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String>;

    /// Return a command that reverses this one.
    fn inverse(&self) -> Box<dyn CampaignCommand>;

    /// Human-readable label, e.g. "Add Node 'questing.AcceptQuest'".
    fn description(&self) -> String;
}

// ---------------------------------------------------------------------------
// Node commands
// ---------------------------------------------------------------------------

pub struct AddNode {
    pub campaign_name: String,
    pub graph_id: Uuid,
    pub node: Node,
}

impl CampaignCommand for AddNode {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        let graph = campaign
            .graphs
            .iter_mut()
            .find(|g| g.id == self.graph_id)
            .ok_or_else(|| format!("Graph {} not found", self.graph_id))?;
        graph.nodes.push(self.node.clone());
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(RemoveNode {
            campaign_name: self.campaign_name.clone(),
            graph_id: self.graph_id,
            node: self.node.clone(),
        })
    }

    fn description(&self) -> String {
        format!(
            "Add Node '{}' to graph {}",
            self.node.node_type, self.graph_id
        )
    }
}

pub struct RemoveNode {
    pub campaign_name: String,
    pub graph_id: Uuid,
    pub node: Node,
}

impl CampaignCommand for RemoveNode {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        let graph = campaign
            .graphs
            .iter_mut()
            .find(|g| g.id == self.graph_id)
            .ok_or_else(|| format!("Graph {} not found", self.graph_id))?;
        let pos = graph
            .nodes
            .iter()
            .position(|n| n.id == self.node.id)
            .ok_or_else(|| format!("Node {} not found", self.node.id))?;
        graph.nodes.remove(pos);
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(AddNode {
            campaign_name: self.campaign_name.clone(),
            graph_id: self.graph_id,
            node: self.node.clone(),
        })
    }

    fn description(&self) -> String {
        format!(
            "Remove Node '{}' from graph {}",
            self.node.node_type, self.graph_id
        )
    }
}

pub struct ModifyNode {
    pub campaign_name: String,
    pub graph_id: Uuid,
    pub old_node: Node,
    pub new_node: Node,
}

impl CampaignCommand for ModifyNode {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        let graph = campaign
            .graphs
            .iter_mut()
            .find(|g| g.id == self.graph_id)
            .ok_or_else(|| format!("Graph {} not found", self.graph_id))?;
        let node = graph
            .nodes
            .iter_mut()
            .find(|n| n.id == self.old_node.id)
            .ok_or_else(|| format!("Node {} not found", self.old_node.id))?;
        *node = self.new_node.clone();
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(ModifyNode {
            campaign_name: self.campaign_name.clone(),
            graph_id: self.graph_id,
            old_node: self.new_node.clone(),
            new_node: self.old_node.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Modify Node {} in graph {}", self.old_node.id, self.graph_id)
    }
}

// ---------------------------------------------------------------------------
// Edge commands
// ---------------------------------------------------------------------------

pub struct AddEdge {
    pub campaign_name: String,
    pub graph_id: Uuid,
    pub edge: Edge,
}

impl CampaignCommand for AddEdge {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        let graph = campaign
            .graphs
            .iter_mut()
            .find(|g| g.id == self.graph_id)
            .ok_or_else(|| format!("Graph {} not found", self.graph_id))?;
        graph.edges.push(self.edge.clone());
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(RemoveEdge {
            campaign_name: self.campaign_name.clone(),
            graph_id: self.graph_id,
            edge: self.edge.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Add Edge {} → {} in graph {}", self.edge.from, self.edge.to, self.graph_id)
    }
}

pub struct RemoveEdge {
    pub campaign_name: String,
    pub graph_id: Uuid,
    pub edge: Edge,
}

impl CampaignCommand for RemoveEdge {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        let graph = campaign
            .graphs
            .iter_mut()
            .find(|g| g.id == self.graph_id)
            .ok_or_else(|| format!("Graph {} not found", self.graph_id))?;
        let pos = graph
            .edges
            .iter()
            .position(|e| e.id == self.edge.id)
            .ok_or_else(|| format!("Edge {} not found", self.edge.id))?;
        graph.edges.remove(pos);
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(AddEdge {
            campaign_name: self.campaign_name.clone(),
            graph_id: self.graph_id,
            edge: self.edge.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Remove Edge {} from graph {}", self.edge.id, self.graph_id)
    }
}

// ---------------------------------------------------------------------------
// Graph commands
// ---------------------------------------------------------------------------

pub struct AddGraph {
    pub campaign_name: String,
    pub graph: Graph,
}

impl CampaignCommand for AddGraph {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        if campaign.graphs.iter().any(|g| g.id == self.graph.id) {
            return Err(format!("Graph {} already exists", self.graph.id));
        }
        campaign.graphs.push(self.graph.clone());
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(RemoveGraph {
            campaign_name: self.campaign_name.clone(),
            graph: self.graph.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Add Graph '{}'", self.graph.name)
    }
}

pub struct RemoveGraph {
    pub campaign_name: String,
    pub graph: Graph,
}

impl CampaignCommand for RemoveGraph {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        let pos = campaign
            .graphs
            .iter()
            .position(|g| g.id == self.graph.id)
            .ok_or_else(|| format!("Graph {} not found", self.graph.id))?;
        campaign.graphs.remove(pos);
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(AddGraph {
            campaign_name: self.campaign_name.clone(),
            graph: self.graph.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Remove Graph '{}'", self.graph.name)
    }
}

// ---------------------------------------------------------------------------
// Condition commands
// ---------------------------------------------------------------------------

pub struct AddCondition {
    pub campaign_name: String,
    pub condition: ConditionDef,
}

impl CampaignCommand for AddCondition {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        if campaign.conditions.iter().any(|c| c.id == self.condition.id) {
            return Err(format!("Condition {} already exists", self.condition.id));
        }
        campaign.conditions.push(self.condition.clone());
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(RemoveCondition {
            campaign_name: self.campaign_name.clone(),
            condition: self.condition.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Add Condition {}", self.condition.id)
    }
}

pub struct RemoveCondition {
    pub campaign_name: String,
    pub condition: ConditionDef,
}

impl CampaignCommand for RemoveCondition {
    fn apply(&self, campaign: &mut Campaign) -> Result<(), String> {
        let pos = campaign
            .conditions
            .iter()
            .position(|c| c.id == self.condition.id)
            .ok_or_else(|| format!("Condition {} not found", self.condition.id))?;
        campaign.conditions.remove(pos);
        Ok(())
    }

    fn inverse(&self) -> Box<dyn CampaignCommand> {
        Box::new(AddCondition {
            campaign_name: self.campaign_name.clone(),
            condition: self.condition.clone(),
        })
    }

    fn description(&self) -> String {
        format!("Remove Condition {}", self.condition.id)
    }
}

// ---------------------------------------------------------------------------
// Campaign History
// ---------------------------------------------------------------------------

pub struct CampaignHistory {
    undo_stack: Vec<Box<dyn CampaignCommand>>,
    redo_stack: Vec<Box<dyn CampaignCommand>>,
    max_history: usize,
}

// Manual Clone — we cannot clone Box<dyn CampaignCommand>, so cloned
// histories start empty. The clone is only used for `AppState` which is
// shared via `Arc<RwLock<>>`, so this is fine in practice.
impl Clone for CampaignHistory {
    fn clone(&self) -> Self {
        Self {
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            max_history: self.max_history,
        }
    }
}

impl Default for CampaignHistory {
    fn default() -> Self {
        Self::new()
    }
}

impl CampaignHistory {
    pub fn new() -> Self {
        Self {
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            max_history: 50,
        }
    }

    pub fn with_max(max_history: usize) -> Self {
        Self {
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            max_history,
        }
    }

    /// Execute a command: apply it, push to undo stack, clear redo stack.
    pub fn execute(
        &mut self,
        cmd: Box<dyn CampaignCommand>,
        campaign: &mut Campaign,
    ) -> Result<(), String> {
        cmd.apply(campaign)?;
        self.undo_stack.push(cmd);
        self.redo_stack.clear();

        // Enforce max_history limit (0 = unlimited).
        if self.max_history > 0 && self.undo_stack.len() > self.max_history {
            self.undo_stack.remove(0);
        }

        Ok(())
    }

    /// Undo the most recent command.
    pub fn undo(&mut self, campaign: &mut Campaign) -> Result<String, String> {
        let cmd = self
            .undo_stack
            .pop()
            .ok_or_else(|| "Nothing to undo".to_string())?;
        let desc = cmd.description();
        let inverse = cmd.inverse();
        inverse.apply(campaign)?;
        self.redo_stack.push(cmd);
        Ok(desc)
    }

    /// Redo the most recently undone command.
    pub fn redo(&mut self, campaign: &mut Campaign) -> Result<String, String> {
        let cmd = self
            .redo_stack
            .pop()
            .ok_or_else(|| "Nothing to redo".to_string())?;
        let desc = cmd.description();
        cmd.apply(campaign)?;
        self.undo_stack.push(cmd);
        Ok(desc)
    }

    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    pub fn undo_description(&self) -> Option<String> {
        self.undo_stack.last().map(|cmd| cmd.description())
    }

    pub fn redo_description(&self) -> Option<String> {
        self.redo_stack.last().map(|cmd| cmd.description())
    }

    pub fn clear(&mut self) {
        self.undo_stack.clear();
        self.redo_stack.clear();
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_models::platform::{Edge, Graph, Intent, Node};
    use std::collections::BTreeMap;

    fn make_graph(id: u128) -> Graph {
        Graph {
            id: Uuid::from_u128(id),
            name: "test-graph".to_string(),
            entry_node: Uuid::nil(),
            nodes: Vec::new(),
            edges: Vec::new(),
        }
    }

    fn make_node(id: u128, node_type: &str) -> Node {
        Node {
            id: Uuid::from_u128(id),
            node_type: node_type.to_string(),
            intent: Intent(BTreeMap::new()),
            resolved: None,
            context: None,
        }
    }

    fn make_edge(id: u128, from: u128, to: u128) -> Edge {
        Edge {
            id: Uuid::from_u128(id),
            from: Uuid::from_u128(from),
            to: Uuid::from_u128(to),
            guard: None,
        }
    }

    fn make_condition(id: u128) -> ConditionDef {
        ConditionDef {
            id: Uuid::from_u128(id),
            condition: sentinel_models::runtime::RuntimeCondition::AlwaysTrue,
        }
    }

    // ---- Add/Undo/Redo node cycle ----------------------------------------

    #[test]
    fn add_node_undo_redo() {
        let mut campaign = Campaign::new("test");
        let graph = make_graph(1);
        campaign.graphs.push(graph);
        let mut history = CampaignHistory::new();

        let node = make_node(10, "questing.Travel");
        history
            .execute(
                Box::new(AddNode {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    node,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.graphs[0].nodes.len(), 1);
        assert_eq!(campaign.graphs[0].nodes[0].node_type, "questing.Travel");

        // Undo — description is the original command (Add Node)
        let desc = history.undo(&mut campaign).unwrap();
        assert!(desc.contains("Add Node"));
        assert_eq!(campaign.graphs[0].nodes.len(), 0);

        // Redo
        history.redo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs[0].nodes.len(), 1);
    }

    #[test]
    fn modify_node_undo_redo() {
        let mut campaign = Campaign::new("test");
        let graph = make_graph(1);
        campaign.graphs.push(graph);
        campaign.graphs[0].nodes.push(make_node(10, "questing.Travel"));
        let mut history = CampaignHistory::new();

        let old = campaign.graphs[0].nodes[0].clone();
        let mut new = old.clone();
        new.node_type = "questing.AcceptQuest".to_string();

        history
            .execute(
                Box::new(ModifyNode {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    old_node: old,
                    new_node: new,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.graphs[0].nodes[0].node_type, "questing.AcceptQuest");

        history.undo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs[0].nodes[0].node_type, "questing.Travel");

        history.redo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs[0].nodes[0].node_type, "questing.AcceptQuest");
    }

    #[test]
    fn remove_node_undo_redo() {
        let mut campaign = Campaign::new("test");
        let graph = make_graph(1);
        campaign.graphs.push(graph);
        let node = make_node(10, "questing.Travel");
        campaign.graphs[0].nodes.push(node.clone());
        let mut history = CampaignHistory::new();

        history
            .execute(
                Box::new(RemoveNode {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    node,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.graphs[0].nodes.len(), 0);

        history.undo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs[0].nodes.len(), 1);

        history.redo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs[0].nodes.len(), 0);
    }

    // ---- Edge commands ---------------------------------------------------

    #[test]
    fn add_edge_undo_redo() {
        let mut campaign = Campaign::new("test");
        let mut graph = make_graph(1);
        let node_a = make_node(10, "questing.A");
        let node_b = make_node(11, "questing.B");
        graph.nodes.push(node_a);
        graph.nodes.push(node_b);
        campaign.graphs.push(graph);
        let mut history = CampaignHistory::new();

        let edge = make_edge(100, 10, 11);
        history
            .execute(
                Box::new(AddEdge {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    edge,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.graphs[0].edges.len(), 1);

        history.undo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs[0].edges.len(), 0);

        history.redo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs[0].edges.len(), 1);
    }

    #[test]
    fn remove_edge_undo_redo() {
        let mut campaign = Campaign::new("test");
        let mut graph = make_graph(1);
        graph.nodes.push(make_node(10, "questing.A"));
        graph.nodes.push(make_node(11, "questing.B"));
        let edge = make_edge(100, 10, 11);
        graph.edges.push(edge.clone());
        campaign.graphs.push(graph);
        let mut history = CampaignHistory::new();

        history
            .execute(
                Box::new(RemoveEdge {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    edge,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.graphs[0].edges.len(), 0);

        history.undo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs[0].edges.len(), 1);
    }

    // ---- Graph commands --------------------------------------------------

    #[test]
    fn add_graph_undo_redo() {
        let mut campaign = Campaign::new("test");
        let mut history = CampaignHistory::new();

        let graph = make_graph(1);
        history
            .execute(
                Box::new(AddGraph {
                    campaign_name: "test".to_string(),
                    graph,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.graphs.len(), 1);

        history.undo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs.len(), 0);

        history.redo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs.len(), 1);
    }

    #[test]
    fn remove_graph_undo_redo() {
        let mut campaign = Campaign::new("test");
        let graph = make_graph(1);
        campaign.graphs.push(graph.clone());
        let mut history = CampaignHistory::new();

        history
            .execute(
                Box::new(RemoveGraph {
                    campaign_name: "test".to_string(),
                    graph,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.graphs.len(), 0);

        history.undo(&mut campaign).unwrap();
        assert_eq!(campaign.graphs.len(), 1);
    }

    // ---- Condition commands ----------------------------------------------

    #[test]
    fn add_condition_undo_redo() {
        let mut campaign = Campaign::new("test");
        let mut history = CampaignHistory::new();

        let condition = make_condition(1);
        history
            .execute(
                Box::new(AddCondition {
                    campaign_name: "test".to_string(),
                    condition,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.conditions.len(), 1);

        history.undo(&mut campaign).unwrap();
        assert_eq!(campaign.conditions.len(), 0);
    }

    #[test]
    fn remove_condition_undo_redo() {
        let mut campaign = Campaign::new("test");
        let condition = make_condition(1);
        campaign.conditions.push(condition.clone());
        let mut history = CampaignHistory::new();

        history
            .execute(
                Box::new(RemoveCondition {
                    campaign_name: "test".to_string(),
                    condition,
                }),
                &mut campaign,
            )
            .unwrap();
        assert_eq!(campaign.conditions.len(), 0);

        history.undo(&mut campaign).unwrap();
        assert_eq!(campaign.conditions.len(), 1);
    }

    // ---- History management ----------------------------------------------

    #[test]
    fn new_command_clears_redo() {
        let mut campaign = Campaign::new("test");
        let graph = make_graph(1);
        campaign.graphs.push(graph);
        let mut history = CampaignHistory::new();

        let node_a = make_node(10, "questing.A");
        history
            .execute(
                Box::new(AddNode {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    node: node_a,
                }),
                &mut campaign,
            )
            .unwrap();
        history.undo(&mut campaign).unwrap();
        assert!(history.can_redo());

        // New command after undo should clear redo.
        let node_b = make_node(11, "questing.B");
        history
            .execute(
                Box::new(AddNode {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    node: node_b,
                }),
                &mut campaign,
            )
            .unwrap();
        assert!(!history.can_redo());
        assert_eq!(campaign.graphs[0].nodes.len(), 1);
        assert_eq!(campaign.graphs[0].nodes[0].id, Uuid::from_u128(11));
    }

    #[test]
    fn max_history_limit() {
        let mut campaign = Campaign::new("test");
        let graph = make_graph(1);
        campaign.graphs.push(graph);
        let mut history = CampaignHistory::with_max(3);

        for i in 0..5 {
            history
                .execute(
                    Box::new(AddNode {
                        campaign_name: "test".to_string(),
                        graph_id: Uuid::from_u128(1),
                        node: make_node(10 + i, "questing.Travel"),
                    }),
                    &mut campaign,
                )
                .unwrap();
        }

        assert_eq!(history.undo_stack.len(), 3);
        assert!(history.undo(&mut campaign).is_ok());
        assert!(history.undo(&mut campaign).is_ok());
        assert!(history.undo(&mut campaign).is_ok());
        assert!(history.undo(&mut campaign).is_err());
    }

    #[test]
    fn can_undo_redo_descriptions() {
        let mut history = CampaignHistory::new();
        assert!(!history.can_undo());
        assert!(!history.can_redo());
        assert!(history.undo_description().is_none());
        assert!(history.redo_description().is_none());

        let mut campaign = Campaign::new("test");
        let graph = make_graph(1);
        campaign.graphs.push(graph);
        let node = make_node(10, "questing.Travel");
        history
            .execute(
                Box::new(AddNode {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    node,
                }),
                &mut campaign,
            )
            .unwrap();

        assert!(history.can_undo());
        let desc = history.undo_description().unwrap();
        assert!(desc.contains("Add Node"));

        history.undo(&mut campaign).unwrap();
        assert!(!history.can_undo());
        assert!(history.can_redo());
        let desc = history.redo_description().unwrap();
        assert!(desc.contains("Add Node"));
    }

    #[test]
    fn clear_history() {
        let mut campaign = Campaign::new("test");
        let graph = make_graph(1);
        campaign.graphs.push(graph);
        let mut history = CampaignHistory::new();

        history
            .execute(
                Box::new(AddNode {
                    campaign_name: "test".to_string(),
                    graph_id: Uuid::from_u128(1),
                    node: make_node(10, "questing.A"),
                }),
                &mut campaign,
            )
            .unwrap();
        assert!(history.can_undo());

        history.clear();
        assert!(!history.can_undo());
        assert!(!history.can_redo());
    }
}
