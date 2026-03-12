use std::sync::Arc;

use crate::error::AppError;
use crate::models::DatasetManifest;
use crate::storage::SqliteStore;

#[derive(Clone)]
pub struct MetaRepository {
    store: Arc<SqliteStore>,
}

impl MetaRepository {
    pub fn new(store: Arc<SqliteStore>) -> Self {
        Self { store }
    }

    pub fn get_manifest(&self) -> Result<DatasetManifest, AppError> {
        let conn = self.store.open_read_only()?;
        let manifest = conn.query_row(
            "SELECT dataset_version, source, game_version, db_version_string, importer_schema_version, built_at_utc FROM sqs_manifest ORDER BY id DESC LIMIT 1",
            [],
            |row| {
                Ok(DatasetManifest {
                    dataset_version: row.get(0)?,
                    source: row.get(1)?,
                    game_version: row.get(2)?,
                    db_version_string: row.get(3)?,
                    importer_schema_version: row.get::<_, i64>(4)? as u32,
                    built_at_utc: row.get(5)?,
                })
            },
        )?;
        Ok(manifest)
    }
}
