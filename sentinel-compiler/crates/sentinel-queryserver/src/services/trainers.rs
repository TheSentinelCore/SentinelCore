//! Trainer Service — Volume 4 §11

use anyhow::Result;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct TrainerService {
    state: ServiceState,
}

impl TrainerService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn get_trainer(&self, entry: u32) -> Result<TrainerDetails> {
        let cache_key = format!("trainer:{}", entry);
        if let Some(cached) = self.state.cache.get(&cache_key).await {
            return Ok(serde_json::from_value(cached)?);
        }

        let db = self.state.db.clone();
        let row = tokio::task::spawn_blocking(move || -> Result<TrainerDetails> {
            let conn = db.blocking_lock();

            let details = conn.query_row(
                "SELECT ct.Entry, ct.Name, ct.Faction, c.map, c.position_x, c.position_y, c.position_z
                 FROM creature_template ct
                 LEFT JOIN creature c ON c.id = ct.Entry
                 WHERE ct.Entry = ?1 LIMIT 1",
                [entry],
                |_row| {
                    Ok(TrainerDetails {
                        entry,
                        name: String::new(),
                        class: sentinel_schema::Class::Warrior,
                        spells: vec![],
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
