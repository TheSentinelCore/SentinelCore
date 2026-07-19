use std::sync::{Arc, Mutex};
use once_cell::sync::Lazy;
use rusqlite::Connection;
use anyhow::{Result, Context};
use rusqlite::Row;
use std::path::Path;
use tracing::{info, warn};

// ---------------------------------------------------------------------------
// Row helpers — MaNGOS uses -1 as a sentinel for "no value" across many
// numeric columns (QuestLevel, MinLevel, Req* ids, etc.). Reading those
// directly into a `u32` panics with "Integer -1 out of range". These
// helpers read as `i32` and saturate the sentinel to 0.
// ---------------------------------------------------------------------------

/// Read a possibly-negative DB integer column as `u32`, saturating the
/// MaNGOS `-1` "none" sentinel to `0`.
pub fn get_u32_saturating(row: &Row, idx: usize) -> rusqlite::Result<u32> {
    let v: i32 = row.get(idx)?;
    Ok(v.max(0) as u32)
}

/// Read the `Faction` integer column and return it as a `String`.
///
/// `creature_template.Faction` / `taxi_nodes.faction` are INTEGER ids in the
/// DB, but our API models expose `faction` as a `String` (the editor/Lua side
/// compares faction labels). We have no faction-name lookup table in this DB,
/// so we return the numeric id as a string. This keeps the `String` contract
/// intact and avoids the rusqlite `Integer -> String` type error.
pub fn get_faction_string(row: &Row, idx: usize) -> rusqlite::Result<String> {
    let v: i32 = row.get(idx)?;
    Ok(v.to_string())
}

static DB_INSTANCE: Lazy<Arc<Mutex<Option<Connection>>>> = Lazy::new(|| Arc::new(Mutex::new(None)));

/// Database connection manager
pub struct Database {
    conn: Connection,
}

impl Database {
    /// Open database connection with optimized settings
    pub fn open(path: &Path) -> Result<Self> {
        let conn = Connection::open(path)
            .context("Failed to open database")?;
        
        // Performance pragmas
        conn.execute_batch(r#"
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA cache_size = -32768;  -- 32MB cache
            PRAGMA temp_store = MEMORY;
            PRAGMA mmap_size = 268435456;  -- 256MB mmap
            PRAGMA page_size = 4096;
        "#).context("Failed to set pragmas")?;
        
        info!("Opened database: {:?}", path);
        Ok(Self { conn })
    }
    
    /// Get or create the shared database connection (Arc-wrapped for ServiceState)
    pub fn get_shared(path: &Path) -> Result<Arc<tokio::sync::Mutex<Connection>>> {
        let mut instance = DB_INSTANCE.lock().unwrap();
        if instance.is_none() {
            let conn = Connection::open(path)
                .context("Failed to open shared database")?;
            conn.execute_batch(r#"
                PRAGMA journal_mode = WAL;
                PRAGMA synchronous = NORMAL;
                PRAGMA cache_size = -32768;
                PRAGMA temp_store = MEMORY;
                PRAGMA mmap_size = 268435456;
                PRAGMA page_size = 4096;
            "#).context("Failed to set pragmas")?;
            *instance = Some(conn);
            info!("Opened shared database: {:?}", path);
        }
        // We can't clone Connection, so just wrap the once_cell in tokio Mutex
        // Actually, we need a fresh connection for tokio::sync::Mutex.
        // rusqlite Connection is !Clone, so we open a new one and share via tokio Mutex.
        let conn = Connection::open(path)
            .context("Failed to open database for service")?;
        conn.execute_batch(r#"
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA cache_size = -32768;
            PRAGMA temp_store = MEMORY;
            PRAGMA mmap_size = 268435456;
            PRAGMA page_size = 4096;
        "#).context("Failed to set pragmas")?;
        
        Ok(Arc::new(tokio::sync::Mutex::new(conn)))
    }
    
    /// Get underlying connection for queries
    pub fn conn(&self) -> &Connection {
        &self.conn
    }
    
    /// Get mutable connection for transactions
    pub fn conn_mut(&mut self) -> &mut Connection {
        &mut self.conn
    }
    
    /// Run migrations (Volume 4 §28)
    pub fn migrate(&mut self) -> Result<()> {
        // Schema version tracking
        self.conn.execute_batch(r#"
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );
        "#)?;
        
        let current_version: i32 = self.conn
            .query_row("SELECT COALESCE(MAX(version), 0) FROM schema_version", [], |r| r.get(0))
            .unwrap_or(0);
        
        if current_version < 1 {
            self.apply_v1_indexes()?;
            self.conn.execute("INSERT INTO schema_version (version) VALUES (1)", [])?;
            info!("Applied migration v1: indexes");
        }
        
        Ok(())
    }
    
    /// Apply v1 indexes for query performance
    fn apply_v1_indexes(&self) -> Result<()> {
        let indexes = [
            // Quest indexes
            "CREATE INDEX IF NOT EXISTS idx_quest_template_zone ON quest_template(ZoneOrSort)",
            "CREATE INDEX IF NOT EXISTS idx_quest_template_level ON quest_template(QuestLevel)",
            "CREATE INDEX IF NOT EXISTS idx_quest_template_giver ON creature_questrelation(quest)",
            "CREATE INDEX IF NOT EXISTS idx_quest_template_turnin ON creature_involvedrelation(quest)",
            
            // NPC indexes
            "CREATE INDEX IF NOT EXISTS idx_creature_template_name ON creature_template(Name)",
            "CREATE INDEX IF NOT EXISTS idx_creature_entry ON creature(id)",
            "CREATE INDEX IF NOT EXISTS idx_creature_map ON creature(map)",
            "CREATE INDEX IF NOT EXISTS idx_creature_zone ON creature(map)",
            
            // Vendor indexes
            "CREATE INDEX IF NOT EXISTS idx_npc_vendor_entry ON npc_vendor(entry)",
            
            // Trainer indexes
            "CREATE INDEX IF NOT EXISTS idx_npc_trainer_entry ON npc_trainer(entry)",
            
            // Game object indexes
            "CREATE INDEX IF NOT EXISTS idx_gameobject_template_name ON gameobject_template(name)",
            "CREATE INDEX IF NOT EXISTS idx_gameobject_entry ON gameobject(id)",
            "CREATE INDEX IF NOT EXISTS idx_gameobject_map ON gameobject(map)",
            
            // Item indexes
            "CREATE INDEX IF NOT EXISTS idx_item_template_name ON item_template(name)",
            "CREATE INDEX IF NOT EXISTS idx_item_template_class ON item_template(class)",
        ];
        
        for idx in indexes {
            if let Err(e) = self.conn.execute(idx, []) {
                warn!("Index creation warning (may already exist): {}", e);
            }
        }
        
        Ok(())
    }
}
