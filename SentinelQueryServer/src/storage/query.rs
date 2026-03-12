use crate::cursor::{decode_cursor, encode_cursor, CursorSort, CursorToken};
use crate::error::AppError;

pub fn map_faction_team(team: Option<i64>) -> Option<String> {
    match team {
        Some(469) => Some("alliance".to_string()),
        Some(67) => Some("horde".to_string()),
        Some(_) => Some("neutral".to_string()),
        None => None,
    }
}

pub fn encode_nearby_cursor(
    endpoint: &str,
    dataset_version: &str,
    distance_sq: f64,
    guid: i64,
) -> Result<String, AppError> {
    encode_cursor(&CursorToken {
        endpoint: endpoint.to_string(),
        dataset_version: dataset_version.to_string(),
        sort: CursorSort::Nearby { distance_sq, guid },
    })
}

pub fn decode_nearby_cursor(
    endpoint: &str,
    dataset_version: &str,
    cursor: &str,
) -> Result<(f64, i64), AppError> {
    let parsed = decode_cursor(cursor)?;
    if parsed.endpoint != endpoint || parsed.dataset_version != dataset_version {
        return Err(AppError::pagination_invalid(
            "cursor does not match endpoint or dataset version",
        ));
    }

    match parsed.sort {
        CursorSort::Nearby { distance_sq, guid } => Ok((distance_sq, guid)),
        _ => Err(AppError::pagination_invalid("cursor sort kind mismatch")),
    }
}

pub fn encode_list_cursor(
    endpoint: &str,
    dataset_version: &str,
    entry: i64,
    guid: i64,
) -> Result<String, AppError> {
    encode_cursor(&CursorToken {
        endpoint: endpoint.to_string(),
        dataset_version: dataset_version.to_string(),
        sort: CursorSort::List { entry, guid },
    })
}

pub fn decode_list_cursor(
    endpoint: &str,
    dataset_version: &str,
    cursor: &str,
) -> Result<(i64, i64), AppError> {
    let parsed = decode_cursor(cursor)?;
    if parsed.endpoint != endpoint || parsed.dataset_version != dataset_version {
        return Err(AppError::pagination_invalid(
            "cursor does not match endpoint or dataset version",
        ));
    }

    match parsed.sort {
        CursorSort::List { entry, guid } => Ok((entry, guid)),
        _ => Err(AppError::pagination_invalid("cursor sort kind mismatch")),
    }
}

pub fn encode_unified_cursor(
    endpoint: &str,
    dataset_version: &str,
    distance_sq: f64,
    guid: i64,
    entity_type: &str,
) -> Result<String, AppError> {
    encode_cursor(&CursorToken {
        endpoint: endpoint.to_string(),
        dataset_version: dataset_version.to_string(),
        sort: CursorSort::Unified {
            distance_sq,
            guid,
            entity_type: entity_type.to_string(),
        },
    })
}

pub fn decode_unified_cursor(
    endpoint: &str,
    dataset_version: &str,
    cursor: &str,
) -> Result<(f64, i64, String), AppError> {
    let parsed = decode_cursor(cursor)?;
    if parsed.endpoint != endpoint || parsed.dataset_version != dataset_version {
        return Err(AppError::pagination_invalid(
            "cursor does not match endpoint or dataset version",
        ));
    }

    match parsed.sort {
        CursorSort::Unified {
            distance_sq,
            guid,
            entity_type,
        } => Ok((distance_sq, guid, entity_type)),
        _ => Err(AppError::pagination_invalid("cursor sort kind mismatch")),
    }
}
