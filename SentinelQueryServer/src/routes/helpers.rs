use std::sync::Arc;

use crate::blackboard::ServerBlackboard;
use crate::error::AppError;

pub fn parse_optional_bool(value: Option<&str>, field: &str) -> Result<Option<bool>, AppError> {
    let Some(raw) = value else {
        return Ok(None);
    };

    let normalized = raw.trim().to_ascii_lowercase();
    match normalized.as_str() {
        "true" | "1" => Ok(Some(true)),
        "false" | "0" => Ok(Some(false)),
        _ => Err(AppError::invalid_params(format!(
            "{} must be a boolean",
            field
        ))),
    }
}

pub fn ensure_map_exists(state: &Arc<ServerBlackboard>, map_id: i64) -> Result<(), AppError> {
    let conn = state.store.open_read_only()?;
    let exists = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM creature WHERE map = ?1 LIMIT 1)",
        [map_id],
        |row| row.get::<_, i64>(0),
    )?;

    if exists == 1 {
        return Ok(());
    }

    Err(AppError::map_not_found(map_id))
}
