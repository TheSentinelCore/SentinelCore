use std::sync::Arc;

use rusqlite::params_from_iter;

use crate::error::AppError;
use crate::models::ItemInfo;
use crate::storage::SqliteStore;

#[derive(Clone)]
pub struct ItemRepository {
    store: Arc<SqliteStore>,
}

impl ItemRepository {
    pub fn new(store: Arc<SqliteStore>) -> Self {
        Self { store }
    }

    pub fn get_items_by_ids(&self, ids: &[i64]) -> Result<Vec<ItemInfo>, AppError> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }

        let conn = self.store.open_read_only()?;

        let placeholders: Vec<&str> = ids.iter().map(|_| "?").collect();
        let sql = format!(
            "SELECT entry, name, Quality, SellPrice, class, subclass \
             FROM item_template WHERE entry IN ({})",
            placeholders.join(",")
        );

        let bind: Vec<rusqlite::types::Value> =
            ids.iter().map(|id| (*id).into()).collect();

        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(bind.iter()), |row| {
            Ok(ItemInfo {
                entry: row.get(0)?,
                name: row.get(1)?,
                quality: row.get(2)?,
                sell_price: row.get(3)?,
                item_class: row.get(4)?,
                item_subclass: row.get(5)?,
            })
        })?;

        let mut items = Vec::new();
        for row in rows {
            items.push(row?);
        }

        Ok(items)
    }
}
