//! Vendor Service — Volume 4 §10

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct VendorService {
    state: ServiceState,
}

impl VendorService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn get_vendor(&self, entry: u32) -> Result<VendorDetails> {
        let cache_key = format!("vendor:{}", entry);
        if let Some(cached) = self.state.cache.get(&cache_key).await {
            return Ok(serde_json::from_value(cached)?);
        }

        let db = self.state.db.clone();
        let row = tokio::task::spawn_blocking(move || -> Result<VendorDetails> {
            let conn = db.blocking_lock();

            let details = conn.query_row(
                "SELECT ct.Entry, ct.Name, ct.Faction, c.map, c.position_x, c.position_y, c.position_z
                 FROM creature_template ct
                 LEFT JOIN creature c ON c.id = ct.Entry
                 WHERE ct.Entry = ?1 LIMIT 1",
                [entry],
                |row| {
                    let _map = row.get::<_, u32>(3)?;
                    Ok(VendorDetails {
                        entry: row.get(0)?,
                        name: row.get(1)?,
                        items: vec![],
                        repairs: false,
                        ammo: false,
                        food: false,
                        drink: false,
                    })
                },
            )?;
            Ok(details)
        })
        .await??;

        self.state
            .cache
            .insert(cache_key, serde_json::to_value(&row)?)
            .await;
        Ok(row)
    }
}
