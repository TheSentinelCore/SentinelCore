/// Mailbox API endpoints — Volume 4 §13

use axum::{extract::State, response::Json};
use crate::{AppState, models::*, error::QueryResult};

#[axum::debug_handler]
pub async fn list(
    State(state): State<AppState>,
) -> QueryResult<Json<Vec<Mailbox>>> {
    let cache_key = crate::cache::keys::MAILBOXES.to_string();
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(serde_json::from_value(cached)?));
    }
    
    let mailboxes = state.service.get_mailboxes().await?;
    state.cache.insert(cache_key, serde_json::to_value(&mailboxes)?).await;
    Ok(Json(mailboxes))
}