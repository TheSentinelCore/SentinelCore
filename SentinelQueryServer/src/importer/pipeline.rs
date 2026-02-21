use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use rusqlite::{params, Connection};
use uuid::Uuid;

use crate::config::Config;
use crate::error::AppError;

use super::sanitizer::sanitize_dump_to_file;
use super::validator;

#[derive(Clone)]
pub struct Importer {
    pub config: Config,
}

impl Importer {
    pub fn new(config: Config) -> Self {
        Self { config }
    }

    pub fn ensure_runtime_db(&self) -> Result<PathBuf, AppError> {
        std::fs::create_dir_all(&self.config.paths.work_dir).map_err(|e| {
            AppError::dataset_invalid(format!(
                "failed to create work_dir {}: {}",
                self.config.paths.work_dir.display(),
                e
            ))
        })?;

        if self.config.paths.runtime_db.exists() {
            validator::validate_runtime_db(&self.config.paths.runtime_db)?;
            return Ok(self.config.paths.runtime_db.clone());
        }

        self.import_into_runtime()?;
        validator::validate_runtime_db(&self.config.paths.runtime_db)?;
        Ok(self.config.paths.runtime_db.clone())
    }

    pub fn rebuild_runtime_db(&self) -> Result<(), AppError> {
        self.import_into_runtime()
    }

    fn import_into_runtime(&self) -> Result<(), AppError> {
        if !self.config.paths.source_dump_sql.exists() {
            return Err(AppError::dataset_invalid(format!(
                "source dump does not exist at {}",
                self.config.paths.source_dump_sql.display()
            )));
        }

        if !self.config.paths.sqlite3_exe.exists() {
            return Err(AppError::dataset_invalid(format!(
                "sqlite3 executable does not exist at {}",
                self.config.paths.sqlite3_exe.display()
            )));
        }

        let sanitized_path = self.config.paths.work_dir.join("tbcmangos.sanitized.sql");

        let tmp_db = runtime_tmp_db_path(&self.config.paths.runtime_db);
        if tmp_db.exists() {
            let _ = std::fs::remove_file(&tmp_db);
        }

        tracing::info!(
            source_dump = %self.config.paths.source_dump_sql.display(),
            sanitized_sql = %sanitized_path.display(),
            temp_db = %tmp_db.display(),
            "starting_sqlite_import"
        );

        sanitize_dump_to_file(&self.config.paths.source_dump_sql, &sanitized_path)
            .map_err(|e| AppError::dataset_invalid(e.to_string()))?;

        self.run_sqlite_import(&tmp_db, &sanitized_path)?;

        let mut conn = Connection::open(&tmp_db)
            .map_err(|e| AppError::dataset_invalid(format!("failed to open temp db: {}", e)))?;

        self.apply_helper_schema(&mut conn)?;
        self.insert_manifest(&mut conn)?;
        validator::validate_connection(&conn)?;

        drop(conn);
        self.atomic_swap_tmp_db(&tmp_db)?;

        tracing::info!(runtime_db = %self.config.paths.runtime_db.display(), "sqlite_import_complete");
        Ok(())
    }

    fn run_sqlite_import(&self, tmp_db: &Path, sanitized_sql: &Path) -> Result<(), AppError> {
        let read_arg = format!(".read {}", sanitized_sql.display());
        let mut child = Command::new(&self.config.paths.sqlite3_exe)
            .arg(tmp_db)
            .arg(read_arg)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| {
                AppError::dataset_invalid(format!("failed to launch sqlite3 import command: {}", e))
            })?;

        let timeout = Duration::from_secs(self.config.importer.sqlite_import_timeout_secs);
        let start = Instant::now();

        let status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) => {
                    if start.elapsed() >= timeout {
                        let _ = child.kill();
                        let _ = child.wait();
                        return Err(AppError::dataset_invalid(format!(
                            "sqlite import timed out after {} seconds",
                            timeout.as_secs()
                        )));
                    }
                    thread::sleep(Duration::from_millis(200));
                }
                Err(e) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(AppError::dataset_invalid(format!(
                        "failed while waiting for sqlite import: {}",
                        e
                    )));
                }
            }
        };

        let stdout = read_child_pipe(&mut child, PipeKind::Stdout);
        let stderr = read_child_pipe(&mut child, PipeKind::Stderr);

        tracing::info!(
            sqlite_exit_code = ?status.code(),
            stdout_len = stdout.len(),
            stderr_len = stderr.len(),
            "sqlite_import_process_finished"
        );

        if !status.success() {
            return Err(AppError::dataset_invalid(format!(
                "sqlite import failed with status {:?}: {}",
                status.code(),
                stderr
            )));
        }

        Ok(())
    }

    fn apply_helper_schema(&self, conn: &mut Connection) -> Result<(), AppError> {
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS sqs_manifest (
                id INTEGER PRIMARY KEY,
                dataset_version TEXT NOT NULL UNIQUE,
                game_version TEXT NOT NULL,
                source TEXT NOT NULL,
                db_version_string TEXT NOT NULL,
                importer_schema_version INTEGER NOT NULL,
                built_at_utc TEXT NOT NULL,
                dump_path TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sqs_import_runs (
                run_id TEXT PRIMARY KEY,
                started_at_utc TEXT NOT NULL,
                completed_at_utc TEXT,
                status TEXT NOT NULL,
                error_code TEXT,
                error_message TEXT
            );

            CREATE TABLE IF NOT EXISTS sqs_ui_map_map (
                ui_map_id INTEGER PRIMARY KEY,
                map_id INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_creature_map_id ON creature(map, id);
            CREATE INDEX IF NOT EXISTS idx_creature_id_map ON creature(id, map);
            CREATE INDEX IF NOT EXISTS idx_creature_map_xy ON creature(map, position_x, position_y);
            CREATE INDEX IF NOT EXISTS idx_creature_template_entry ON creature_template(Entry);
            CREATE INDEX IF NOT EXISTS idx_npc_vendor_entry ON npc_vendor(entry);
            CREATE INDEX IF NOT EXISTS idx_npc_trainer_entry ON npc_trainer(entry);
            CREATE INDEX IF NOT EXISTS idx_faction_store_entry ON faction_store(Entry);
            "#,
        )
        .map_err(|e| AppError::dataset_invalid(format!("failed to apply helper schema: {}", e)))?;

        if self.config.importer.enable_rtree {
            conn.execute_batch(
                r#"
                CREATE VIRTUAL TABLE IF NOT EXISTS sqs_creature_rtree USING rtree(
                    guid,
                    min_x,
                    max_x,
                    min_y,
                    max_y
                );
                DELETE FROM sqs_creature_rtree;
                INSERT INTO sqs_creature_rtree(guid, min_x, max_x, min_y, max_y)
                SELECT guid, position_x, position_x, position_y, position_y
                FROM creature;
                "#,
            )
            .map_err(|e| {
                AppError::dataset_invalid(format!("failed to build optional rtree index: {}", e))
            })?;
        }

        Ok(())
    }

    fn insert_manifest(&self, conn: &mut Connection) -> Result<(), AppError> {
        let run_id = Uuid::new_v4().to_string();
        let started = chrono::Utc::now().to_rfc3339();

        conn.execute(
            "INSERT INTO sqs_import_runs(run_id, started_at_utc, status) VALUES(?1, ?2, 'started')",
            params![run_id, started],
        )
        .map_err(|e| AppError::dataset_invalid(format!("failed to insert import run: {}", e)))?;

        let (version, ai_version): (String, String) = conn
            .query_row(
                "SELECT COALESCE(version, ''), COALESCE(creature_ai_version, '') FROM db_version LIMIT 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .map_err(|e| AppError::dataset_invalid(format!("failed reading db_version: {}", e)))?;

        let db_version_string = format!("{}|{}", version, ai_version);
        let dataset_version = format!(
            "{}|importer-v{}",
            db_version_string, self.config.importer.schema_version
        );

        conn.execute("DELETE FROM sqs_manifest", []).map_err(|e| {
            AppError::dataset_invalid(format!("failed to clear old manifest rows: {}", e))
        })?;

        let built_at = chrono::Utc::now().to_rfc3339();
        conn.execute(
            "INSERT INTO sqs_manifest(id, dataset_version, game_version, source, db_version_string, importer_schema_version, built_at_utc, dump_path) VALUES(1, ?1, 'tbc', 'cmangos', ?2, ?3, ?4, ?5)",
            params![
                dataset_version,
                db_version_string,
                self.config.importer.schema_version as i64,
                built_at,
                self.config.paths.source_dump_sql.display().to_string()
            ],
        )
        .map_err(|e| AppError::dataset_invalid(format!("failed writing manifest: {}", e)))?;

        let completed = chrono::Utc::now().to_rfc3339();
        conn.execute(
            "UPDATE sqs_import_runs SET completed_at_utc=?1, status='completed' WHERE run_id=?2",
            params![completed, run_id],
        )
        .map_err(|e| AppError::dataset_invalid(format!("failed finalizing import run: {}", e)))?;

        Ok(())
    }

    fn atomic_swap_tmp_db(&self, tmp_db: &Path) -> Result<(), AppError> {
        let runtime_db = &self.config.paths.runtime_db;
        if let Some(parent) = runtime_db.parent() {
            std::fs::create_dir_all(parent).map_err(|e| {
                AppError::dataset_invalid(format!(
                    "failed to create runtime db directory {}: {}",
                    parent.display(),
                    e
                ))
            })?;
        }

        let backup = runtime_db.with_extension("db.bak");

        if runtime_db.exists() {
            if backup.exists() {
                let _ = std::fs::remove_file(&backup);
            }

            std::fs::rename(runtime_db, &backup).map_err(|e| {
                AppError::dataset_invalid(format!(
                    "failed to move existing runtime db to backup: {}",
                    e
                ))
            })?;

            if let Err(err) = std::fs::rename(tmp_db, runtime_db) {
                let _ = std::fs::rename(&backup, runtime_db);
                return Err(AppError::dataset_invalid(format!(
                    "failed to atomically swap runtime db: {}",
                    err
                )));
            }

            let _ = std::fs::remove_file(&backup);
            return Ok(());
        }

        std::fs::rename(tmp_db, runtime_db).map_err(|e| {
            AppError::dataset_invalid(format!("failed to move temp db into runtime path: {}", e))
        })
    }
}

#[derive(Debug, Clone, Copy)]
enum PipeKind {
    Stdout,
    Stderr,
}

fn read_child_pipe(child: &mut std::process::Child, kind: PipeKind) -> String {
    let mut buf = String::new();
    let stream = match kind {
        PipeKind::Stdout => child.stdout.as_mut().map(|s| s as &mut dyn Read),
        PipeKind::Stderr => child.stderr.as_mut().map(|s| s as &mut dyn Read),
    };

    if let Some(stream) = stream {
        let _ = stream.read_to_string(&mut buf);
    }

    buf
}

fn runtime_tmp_db_path(runtime_db: &Path) -> PathBuf {
    let file_name = runtime_db
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_else(|| "world.db".to_string());

    let tmp_name = format!("{}.tmp", file_name);
    runtime_db
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join(tmp_name)
}
