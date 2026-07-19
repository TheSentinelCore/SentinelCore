//! Innkeeper Service — Volume 4 §14

use anyhow::Result;
use sentinel_schema::Waypoint;

use super::helpers::zone_name;
use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct InnkeeperService {
    state: ServiceState,
}

impl InnkeeperService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn get_innkeepers(&self) -> Result<Vec<Innkeeper>> {
        self.list().await
    }

    pub async fn list(&self) -> Result<Vec<Innkeeper>> {
        let cache_key = "innkeepers".to_string();
        if let Some(cached) = self.state.cache.get(&cache_key).await {
            return Ok(serde_json::from_value(cached)?);
        }

        let db = self.state.db.clone();
        let results = tokio::task::spawn_blocking(move || -> Result<Vec<Innkeeper>> {
            let conn = db.blocking_lock();

            let mut stmt = conn.prepare(
                "SELECT c.id, c.name, c.map, c.position_x, c.position_y, c.position_z
                 FROM creature_template c
                 JOIN creature c2 ON c2.id = c.id
                 WHERE c.unit_flags & 1024 > 0 LIMIT 100",
            )?;

            let rows = stmt.query_map([], |row| {
                let map = row.get::<_, u32>(2)?;
                let zone = zone_name(&conn, map)?;
                Ok(Innkeeper {
                    entry: row.get(0)?,
                    name: row.get(1)?,
                    rest_area: String::new(),
                    hearth: false,
                    position: Waypoint::new(map, zone, row.get(3)?, row.get(4)?, row.get(5)?, 5.0),
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
