//! World Graph Service — Volume 4 §24

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct GraphService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl GraphService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn get_world_graph_node(&self, id: String) -> Result<WorldGraphNode> {
        self.get_node(id).await
    }

    pub async fn get_node(&self, id: String) -> Result<WorldGraphNode> {
        Ok(WorldGraphNode {
            id,
            node_type: GraphNodeType::Quest,
            data: serde_json::Value::Null,
            connections: vec![],
        })
    }
}
