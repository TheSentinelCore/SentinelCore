use std::path::Path;

use rusqlite::Connection;

use crate::error::AppError;
use crate::models::DatasetManifest;

const REQUIRED_SOURCE_TABLES: &[&str] = &[
    "creature",
    "creature_template",
    "npc_vendor",
    "npc_trainer",
    "npc_trainer_template",
    "faction_store",
    "db_version",
];

const REQUIRED_INTERNAL_TABLES: &[&str] = &["sqs_manifest", "sqs_import_runs"];

pub fn validate_runtime_db(db_path: &Path) -> Result<DatasetManifest, AppError> {
    if !db_path.exists() {
        return Err(AppError::dataset_not_ready(format!(
            "runtime db does not exist at {}",
            db_path.display()
        )));
    }

    let conn = Connection::open(db_path).map_err(|e| AppError::dataset_invalid(e.to_string()))?;
    validate_connection(&conn)
}

pub fn validate_connection(conn: &Connection) -> Result<DatasetManifest, AppError> {
    for table in REQUIRED_SOURCE_TABLES {
        if !table_exists(conn, table)? {
            return Err(AppError::dataset_invalid(format!(
                "missing required source table {}",
                table
            )));
        }
    }

    for table in REQUIRED_INTERNAL_TABLES {
        if !table_exists(conn, table)? {
            return Err(AppError::dataset_invalid(format!(
                "missing required internal table {}",
                table
            )));
        }
    }

    let db_version_exists = conn
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM db_version LIMIT 1)",
            [],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| AppError::dataset_invalid(e.to_string()))?;

    if db_version_exists != 1 {
        return Err(AppError::dataset_invalid(
            "db_version table is empty".to_string(),
        ));
    }

    let manifest_count = conn
        .query_row("SELECT COUNT(*) FROM sqs_manifest", [], |row| {
            row.get::<_, i64>(0)
        })
        .map_err(|e| AppError::dataset_invalid(e.to_string()))?;

    if manifest_count != 1 {
        return Err(AppError::dataset_invalid(format!(
            "expected exactly one manifest row, found {}",
            manifest_count
        )));
    }

    conn.query_row(
        "SELECT dataset_version, source, game_version, db_version_string, importer_schema_version, built_at_utc FROM sqs_manifest LIMIT 1",
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
    )
    .map_err(|e| AppError::dataset_invalid(e.to_string()))
}

fn table_exists(conn: &Connection, table: &str) -> Result<bool, AppError> {
    let exists = conn
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1)",
            [table],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| AppError::dataset_invalid(e.to_string()))?;

    Ok(exists == 1)
}
