//! Shared database helpers used across multiple services.

use rusqlite::Connection;

/// Look up a zone/area name from `areatable` by map id.
/// Returns `"Unknown"` on lookup failure.
pub fn zone_name(conn: &Connection, map_id: u32) -> rusqlite::Result<String> {
    Ok(conn
        .query_row(
            "SELECT name FROM areatable WHERE id = ?1",
            [map_id],
            |r| r.get(0),
        )
        .unwrap_or_else(|_| "Unknown".to_string()))
}
