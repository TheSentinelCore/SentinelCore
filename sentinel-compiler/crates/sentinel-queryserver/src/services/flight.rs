//! Flight Master Service — Volume 4 §12

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct FlightService {
    state: ServiceState,
}

impl FlightService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn get_flight_masters(&self) -> Result<Vec<FlightMaster>> {
        self.list().await
    }

    pub async fn list(&self) -> Result<Vec<FlightMaster>> {
        let cache_key = "flight_masters".to_string();
        if let Some(cached) = self.state.cache.get(&cache_key).await {
            return Ok(serde_json::from_value(cached)?);
        }

        let db = self.state.db.clone();
        let results =
            tokio::task::spawn_blocking(move || -> Result<Vec<FlightMaster>> {
                let conn = db.blocking_lock();

                let mut stmt = conn.prepare(
                    "SELECT tn.id, tn.name, tn.faction, c.map, c.position_x, c.position_y, c.position_z
                     FROM taxi_nodes tn
                     LEFT JOIN creature c ON c.id = tn.id
                     WHERE 1=1 LIMIT 100",
                )?;

                let rows = stmt.query_map([], |row| {
                    let _map = row.get::<_, u32>(3)?;
                    Ok(FlightMaster {
                        node: row.get(0)?,
                        name: row.get(1)?,
                        faction: row.get(2)?,
                        connected_routes: vec![],
                    })
                })?;

                let mut results = Vec::new();
                for row in rows {
                    results.push(row?);
                }
                Ok(results)
            })
            .await??;

        self.state
            .cache
            .insert(cache_key, serde_json::to_value(&results)?)
            .await;
        Ok(results)
    }
}
