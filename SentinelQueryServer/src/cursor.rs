use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::{Deserialize, Serialize};

use crate::error::AppError;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum CursorSort {
    Nearby {
        distance_sq: f64,
        guid: i64,
    },
    List {
        entry: i64,
        guid: i64,
    },
    Unified {
        distance_sq: f64,
        guid: i64,
        entity_type: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CursorToken {
    pub endpoint: String,
    pub dataset_version: String,
    pub sort: CursorSort,
}

pub fn encode_cursor(cursor: &CursorToken) -> Result<String, AppError> {
    let json =
        serde_json::to_vec(cursor).map_err(|e| AppError::pagination_invalid(e.to_string()))?;
    Ok(URL_SAFE_NO_PAD.encode(json))
}

pub fn decode_cursor(raw: &str) -> Result<CursorToken, AppError> {
    let bytes = URL_SAFE_NO_PAD
        .decode(raw)
        .map_err(|_| AppError::pagination_invalid("invalid cursor encoding"))?;

    serde_json::from_slice::<CursorToken>(&bytes)
        .map_err(|_| AppError::pagination_invalid("invalid cursor payload"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursor_round_trip() {
        let cursor = CursorToken {
            endpoint: "vendors_nearby".to_string(),
            dataset_version: "v1".to_string(),
            sort: CursorSort::Nearby {
                distance_sq: 12.5,
                guid: 42,
            },
        };

        let encoded = encode_cursor(&cursor).expect("should encode");
        let decoded = decode_cursor(&encoded).expect("should decode");
        assert_eq!(cursor, decoded);
    }
}
