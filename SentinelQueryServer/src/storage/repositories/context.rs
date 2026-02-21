use std::sync::Arc;

use crate::error::AppError;
use crate::models::{ContextResolveRequest, ContextResolveResponse};
use crate::storage::SqliteStore;

#[derive(Clone)]
pub struct ContextRepository {
    store: Arc<SqliteStore>,
}

impl ContextRepository {
    pub fn new(store: Arc<SqliteStore>) -> Self {
        Self { store }
    }

    pub fn resolve_context(
        &self,
        request: &ContextResolveRequest,
    ) -> Result<ContextResolveResponse, AppError> {
        if let Some(map_id) = request.map_id {
            if self.map_exists(map_id)? {
                return Ok(Self::partial(
                    Some(map_id),
                    "direct_map",
                    vec!["zone_id and area_id are not derivable from dump-only data".to_string()],
                ));
            }

            return Ok(Self::unresolved(
                "direct_map",
                vec![format!("map_id {} not found in dataset", map_id)],
            ));
        }

        if let Some(ui_map_id) = request.ui_map_id {
            if let Some(map_id) = self.lookup_ui_map_id(ui_map_id)? {
                return Ok(Self::partial(
                    Some(map_id),
                    "ui_map_map",
                    vec!["zone_id and area_id are not derivable from dump-only data".to_string()],
                ));
            }

            if self.map_exists(ui_map_id)? {
                return Ok(Self::partial(
                    Some(ui_map_id),
                    "ui_map_fallback_direct_map",
                    vec![
                        "ui_map_id mapping missing; treated ui_map_id as canonical map_id"
                            .to_string(),
                        "zone_id and area_id are not derivable from dump-only data".to_string(),
                    ],
                ));
            }

            if let Some(inferred_map_id) = self.infer_map_from_position(request)? {
                return Ok(Self::partial(
                    Some(inferred_map_id),
                    "ui_map_fallback_position",
                    vec![
                        format!(
                            "ui_map_id {} has no explicit mapping; inferred map from position window",
                            ui_map_id
                        ),
                        "zone_id and area_id are not derivable from dump-only data".to_string(),
                    ],
                ));
            }

            return Ok(Self::unresolved(
                "ui_map_map",
                vec![format!("ui_map_id {} has no mapping", ui_map_id)],
            ));
        }

        if request.x.is_some() || request.y.is_some() || request.z.is_some() {
            return Ok(Self::unresolved(
                "position_inference",
                vec![
                    "position-only inference is disabled in v1 without canonical map_id"
                        .to_string(),
                ],
            ));
        }

        Ok(Self::unresolved(
            "none",
            vec!["no resolvable context inputs provided".to_string()],
        ))
    }

    pub fn map_exists(&self, map_id: i64) -> Result<bool, AppError> {
        let conn = self.store.open_read_only()?;
        let exists = conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM creature WHERE map = ?1 LIMIT 1)",
            [map_id],
            |row| row.get::<_, i64>(0),
        )?;
        Ok(exists == 1)
    }

    fn lookup_ui_map_id(&self, ui_map_id: i64) -> Result<Option<i64>, AppError> {
        let conn = self.store.open_read_only()?;
        let table_exists = conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='sqs_ui_map_map')",
            [],
            |row| row.get::<_, i64>(0),
        )?;

        if table_exists != 1 {
            return Ok(None);
        }

        let mut stmt =
            conn.prepare("SELECT map_id FROM sqs_ui_map_map WHERE ui_map_id = ?1 LIMIT 1")?;
        let mut rows = stmt.query([ui_map_id])?;
        if let Some(row) = rows.next()? {
            Ok(Some(row.get(0)?))
        } else {
            Ok(None)
        }
    }

    fn infer_map_from_position(
        &self,
        request: &ContextResolveRequest,
    ) -> Result<Option<i64>, AppError> {
        let (Some(x), Some(y)) = (request.x, request.y) else {
            return Ok(None);
        };

        let conn = self.store.open_read_only()?;
        let window = 120.0;

        let sql = if request.instance_type.as_deref() == Some("none") {
            "SELECT map, COUNT(*) AS hits
             FROM creature
             WHERE map IN (0, 1, 530)
               AND position_x BETWEEN ?1 AND ?2
               AND position_y BETWEEN ?3 AND ?4
             GROUP BY map
             ORDER BY hits DESC, map ASC
             LIMIT 2"
        } else {
            "SELECT map, COUNT(*) AS hits
             FROM creature
             WHERE position_x BETWEEN ?1 AND ?2
               AND position_y BETWEEN ?3 AND ?4
             GROUP BY map
             ORDER BY hits DESC, map ASC
             LIMIT 2"
        };

        let mut stmt = conn.prepare(sql)?;
        let mut rows = stmt.query([x - window, x + window, y - window, y + window])?;

        let mut ranked: Vec<(i64, i64)> = Vec::with_capacity(2);
        while let Some(row) = rows.next()? {
            ranked.push((row.get(0)?, row.get(1)?));
        }

        let Some((top_map, top_hits)) = ranked.first().copied() else {
            return Ok(None);
        };

        let second_hits = ranked.get(1).map(|(_, hits)| *hits).unwrap_or(0);
        if top_hits >= 1 && (second_hits == 0 || top_hits >= second_hits * 2) {
            Ok(Some(top_map))
        } else {
            Ok(None)
        }
    }

    fn partial(map_id: Option<i64>, source: &str, warnings: Vec<String>) -> ContextResolveResponse {
        ContextResolveResponse {
            canonical_map_id: map_id,
            map_id,
            zone_id: None,
            area_id: None,
            resolved: true,
            ambiguous: false,
            diagnostic_confidence: 1.0,
            resolution: "partial".to_string(),
            source: source.to_string(),
            warnings,
        }
    }

    fn unresolved(source: &str, warnings: Vec<String>) -> ContextResolveResponse {
        ContextResolveResponse {
            canonical_map_id: None,
            map_id: None,
            zone_id: None,
            area_id: None,
            resolved: false,
            ambiguous: false,
            diagnostic_confidence: 0.0,
            resolution: "unresolved".to_string(),
            source: source.to_string(),
            warnings,
        }
    }
}
